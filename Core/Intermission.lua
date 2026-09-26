--[[--------------------------------------------------------------------------
    GideonRaid / Core / Intermission.lua

    "Intermission Coach" - boss Entombed Sentinels (mythic), raid
    The Venomous Abyss (WoW Midnight 12.1.0).

    PURE LOGIC (Lua 5.1). This file touches NO WoW API, reads no unit value and
    registers no event. It runs as-is under busted and under lua5.1 outside the
    client.

    REFERENCE MECHANICS (CORRECTED model, authoritative)
    https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview
      - the NUMBER displayed above the head does NOT determine the colors:
          "2" = ALWAYS 2 green + 2 red, unambiguously;
          "1" or "3" = either 3 green + 1 red, or 1 green + 3 red:
          it is the COLOR of the orbs that decides, never the number.
        There are therefore only THREE real states: 3V1R, 2V2R, 1V3R.
      - the survival rule is a COLOR ADDITION: the sum of the two players must
        make 4 GREEN and 4 RED. Valid pairings: 3V1R + 1V3R (= 4V4R) and
        2V2R + 2V2R (= 4V4R). Any other combination kills: 3V1R + 2V2R = 5 green
        = the guide's "5g".
      - about 3 s after the start, the room goes dark: each player then sees only
        THEIR own orbs (their number alone is not enough).

    THE PING IS PLACED BY THE PLAYER, WITH THE NATIVE BLIZZARD PING KEYBINDS.
    Since Dragonflight 10.1.7 the player can bind a key to each ping type
    (Options > Keybindings > ping system) and ping without opening the ping
    wheel. Measured in game by the raid lead: an addon CANNOT ping at all - not
    from a macro, not from a binding - the ping API is restricted to Blizzard's
    own UI ("forbidden action"). The addon therefore:
      - DISPLAYS which ping to use ("PING: Warning");
      - DISPLAYS which key to press, when the player has bound one (the key is
        read by the rendering layer, UI/Intermission.lua, and INJECTED here:
        Core/ never calls an API);
      - and NEVER pings, never prepares a macro, never mentions one.
    A single keybind per player is enough: a warning ping marks the ANCHOR, the
    chasers run to it.

    API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
    Constrained source: "Combat API functions may now return secret values ...
    Tainted code is not allowed to compare or perform boolean tests on secret
    values."
    => this module NEVER compares a unit value. Everything it handles comes from
       the player (click) or from a file prepared out of game (SavedVariables).

    NO GetTime, NO math.random, NO non-deterministic order: time is injected
    into tick(state, dt) / advanceRun(run, dt) by the wiring layer.

    ROLES AND PING POLICY (raid-lead decision, replace "one role per number"):
    a state does not carry a NUMBER-based duty but a ROLE:
      1V3R = ANCHOR : does not move, pings itself with its own key (or is pinged
                      by another player), and DOES NOT MOVE;
      3V1R = CHASER : does NOT ping, spots a ping and runs to it (any 1V3R
                      anchor works);
      2V2R = MIDDLE : does NOT ping, goes to the middle / under the boss and
                      pairs up with another 2V2R.
    With the "anchors" policy the raid goes from ~20 pings to at most ~8 (one
    ping per anchor, 4 per side), which keeps the ping channel readable (the
    client also rate-limits pings per player).
    The policy is CONFIGURABLE (Core/Config.lua -> pingMode, /gideon ping):
      "anchors" (default) : only the ANCHOR states ping;
      "color"             : raidstrats variant - every state pings its own ping
                            (1V3R Warning, 2V2R OnMyWay, 3V1R Assist);
      "none"              : nobody pings, the raid plays on positions only.
    Everything below is PURE: no API, injected mode, no clock.
----------------------------------------------------------------------------]]
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: the language layer is
--- a hard dependency (every string displayed in game goes through it).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Intermission.lua")

--- Core/Config.lua is loaded BEFORE this file by the .toc: it owns the canonical
--- list of ping policies, the default schedule and their pure resolvers.
local Config = assert(ns.Config, "Core/Config.lua must be loaded before Core/Intermission.lua")

---@class Intermission
local Intermission = {}
ns.Intermission = Intermission

--- Intermission model version. 2 = COLOR-based model (3V1R/2V2R/1V3R), the
--- numbers 1/2/3 being only hints (1 and 3 ambiguous).
Intermission.SCHEMA_VERSION = 2

--- Duration of the window where the other players' indicators are visible (guide).
Intermission.VISIBILITY_SECONDS = 3

--- Default intermission duration when the prepared timeline does not provide one.
Intermission.DEFAULT_DURATION_SECONDS = 20

--- How long the panel is shown BEFORE the intermission starts (lead time). The
--- player reads the three choices and gets ready; the intermission clock itself
--- only starts at the intermission.
Intermission.LEAD_SECONDS = Config.DEFAULT_LEAD_SECONDS

--- Pre-computed schedule of the intermissions, in seconds since the pull
--- (ENCOUNTER_START). Same table as Config: it cannot drift.
Intermission.SCHEDULE_SECONDS = Config.DEFAULT_SCHEDULE_SECONDS

--- Pure normalization of a persisted schedule (sorted, positive, bounded).
Intermission.validateSchedule = Config.resolveSchedule

--- Three canonical STATES, DETERMINISTIC display order (increasing green,
--- never pairs()): 1V3R, 2V2R, 3V1R.
Intermission.STATES = { "1V3R", "2V2R", "3V1R" }

--- Historical alias: the module used to talk about "declarations 1/2/3". These
--- are now ORB COMPOSITIONS; the alias avoids breaking the callers.
Intermission.DECLARATIONS = Intermission.STATES

--- The THREE ping policies. The canonical list lives in Core/Config.lua (the
--- persistence layer): this is the same table, so it cannot drift.
Intermission.PING_MODES = Config.PING_MODES

--- Default ping policy: the raid lead's decision ("anchors").
Intermission.DEFAULT_PING_MODE = Config.DEFAULT_PING_MODE

--- Pure, total resolution of a ping policy: accepts "anchors" / "color" / "none"
--- (case-insensitive) and returns "anchors" for anything else, never an error.
Intermission.resolvePingMode = Config.resolvePingMode

--- The THREE roles. A role is carried by the ORB COMPOSITION, never by the
--- number displayed above the head (the number 1 or 3 is ambiguous).
Intermission.ROLES = { ANCHOR = "ANCHOR", CHASER = "CHASER", MID = "MID" }

--- State -> role, DETERMINISTIC table (no pairs()): 1V3R / 2V2R / 3V1R.
local ROLE_BY_STATE = { ["1V3R"] = "ANCHOR", ["2V2R"] = "MID", ["3V1R"] = "CHASER" }
Intermission.ROLE_BY_STATE = ROLE_BY_STATE

--- Intermission phases.
---   IDLE    : not started (the panel shows the pre-pull / placement content);
---   PENDING : the panel is open BEFORE the intermission (lead time countdown);
---   VISIBLE : the intermission is running and the other players are visible;
---   DARK    : the room is darkened (only your own orbs);
---   DONE    : intermission over -> the wiring CLOSES the panel.
Intermission.PHASE = {
    IDLE = "IDLE",
    PENDING = "PENDING",
    VISIBLE = "VISIBLE",
    DARK = "DARK",
    DONE = "DONE",
}

local PHASE_IDLE = Intermission.PHASE.IDLE
local PHASE_PENDING = Intermission.PHASE.PENDING
local PHASE_VISIBLE = Intermission.PHASE.VISIBLE
local PHASE_DARK = Intermission.PHASE.DARK
local PHASE_DONE = Intermission.PHASE.DONE

--[[ Blizzard native ping keybinds, PER STATE (Options > Keybindings > ping
     system). MEASURED IN GAME by the raid lead (2026-09-22) on a FRENCH client:
     the native ping keybinds DO exist, separately, under the labels « Ping »,
     « Attaque », « Avertissement » (= Warning), « En route » (= On My Way),
     « Aide » (= Assist/Help), plus « Activer le ciblage de ping » (ping
     targeting). So the player binds ONE key per ping and the addon only READS
     it (rendering layer) to tell the player which key to press.

     The COMMAND NAME of each binding (what GetBindingKey expects) was NOT
     displayed by the client and is still NOT confirmed: each state therefore
     carries a list of CANDIDATES, tried in order by the rendering layer (the
     comparison happens on a Binding string, never on a combat value). The first
     candidate that returns a key wins; if none does, the panel shows no key at
     all and says "set a keybind in Options > Keybindings" (never a wrong
     shortcut).

     The candidates stay semantically pure: a state never borrows the key of
     ANOTHER ping (PING_ATTACK, for the « Attaque » ping, is deliberately absent
     — displaying the Attack key for a Warning instruction would be a lie).

     TO BE CONFIRMED IN GAME (docs/TESTPLAN.md section 3.5): dump the binding
     list of a real client and replace these candidates by the real names.
]]
Intermission.PING_BINDINGS = {
    ["1V3R"] = { "PING_WARNING", "PINGTYPE_WARNING", "PINGSUBJECTTYPE_WARNING", "BINDING_PING_WARNING" },
    ["2V2R"] = { "PING_ONMYWAY", "PING_ON_MY_WAY", "PINGTYPE_ONMYWAY", "BINDING_PING_ONMYWAY" },
    ["3V1R"] = { "PING_ASSIST", "PING_HELP", "PINGTYPE_ASSIST", "BINDING_PING_ASSIST" },
}

--- Pure helper: the DISPLAYED label of a ping, in the active language.
--- The canonical identifier ("Warning", "OnMyWay", "Assist") never changes; only
--- the label the player reads is translated, because the client shows its own
--- label ("Avertissement" / "En route" / "Aide" on a FRENCH client — measured in
--- game by the raid lead, 2026-09-22). A missing locale key falls back to the
--- canonical identifier, never to a broken string.
--- @param ping string|nil canonical identifier
--- @return string label
function Intermission.pingLabel(ping)
    if type(ping) ~= "string" or ping == "" then
        return ""
    end
    local key = "ping.name." .. ping
    local label = Locale.t(key)
    if label == key then
        return ping
    end
    return label
end

--- Pure helper: the binding candidates of the ping to use, for one state key.
--- @param key string "1V3R" | "2V2R" | "3V1R"
--- @return table|nil ordered candidate names
function Intermission.bindNames(key)
    local list = Intermission.PING_BINDINGS[key]
    if type(list) ~= "table" then
        return nil
    end
    local out = {}
    for index = 1, #list do
        out[index] = list[index]
    end
    return out
end

--[[ PING BUDGET. The client's per-player ping limit was MEASURED IN GAME by the
     raid lead (2026-09-22): 3 pings in a row, then about 5 seconds of wait, then
     3 again. Consequence for the design: the addon must NEVER ask a player to
     ping several times in a burst (the client would swallow everything past the
     third). With the default `anchors` policy each concerned player sends exactly
     ONE ping per intermission, so the raid stays very far from the limit - which
     is what validates that choice. Any future instruction of the form "ping,
     then ping again" has to be refused. Full detail: docs/INTERMISSION-COACH.md
     section 2.1 and docs/TESTPLAN.md section 3.5.
]]

--[[ The THREE color states (no API read in game).

     key            : short key used everywhere (3V1R / 2V2R / 1V3R)
     display        : locale key of the visual label ("3 GREEN + 1 RED" /
                      "3 VERTS + 1 ROUGE" in French)
     orbs / greens / reds : composition; greens and reds are the ONLY basis of
                      the survival rule (sum 4 green + 4 red = survival)
     numbers        : number(s) that can be displayed above the head
     numberAmbiguous: true when the number does NOT reveal the color
     dominant       : dominant color (the one that decides the ping)
     position       : position code; positionLabel: displayed text
     ping           : ping to use, VERIFIED on the wiki gallery
                      https://warcraft.wiki.gg/wiki/Ping_System :
                      Warning = red, OnMyWay = blue, Assist = green.
                      raidstrats guide convention, BY DOMINANT COLOR:
                      3 green -> Assist (green), 2-2 -> OnMyWay (blue),
                      3 red -> Warning (red).
     role           : PING ROLE carried by the state (ANCHOR / MID / CHASER).
                      It comes from the ORB COMPOSITION, never from the number.
     roleName       : locale key of the displayed role label ("ANCHOR", "ANCRE")
     actionPing     : the ONE action line when the role must ping (%s = ping)
     actionNoPing   : the ONE action line when it must not ping
                      (the ping decision comes from the role + the policy, so
                      the same role never receives a contradictory order)
     complement     : the state that MUST join it (4 green + 4 red)
     buttonLabel    : declaration button label (composition, number as a hint).
                      Computed HERE: the UI layer computes nothing.

     POSITIONS: the positional lines of the guide CONTRADICT each other (they
     give both "1 green 3 red -> left" and "3 red 1 green -> right"). Our
     convention is therefore EXPLICIT and CONFIGURABLE here: by default the
     FIXED point is the RED-majority state (1V3R, red Warning ping) and the
     RUNNER is the GREEN-majority state (3V1R, green Assist ping), the 2V2R
     going to the middle. It is the only convention consistent with "the color
     decides".

     ROLES (raid-lead decision, replaces "one duty per number"): the ANCHOR is
     the 1V3R state (holds its position, pings itself with its own key or is
     pinged by somebody else), the CHASER is the 3V1R state (runs to a ping, any
     anchor works) and the MIDDLE is the 2V2R state (goes to the middle and
     pairs with a 2V2R). Which of them actually pings depends on the ping policy.

     DISPLAY: ONLY the essential is displayed (the panel is read in combat):
     state, role, PING: YES/NO and ONE action line. The long explanations live
     in docs/INTERMISSION-COACH.md, never on screen. As soon as a composition is
     clicked the three choices DISAPPEAR (snapshot.showButtons = false) and only
     CORRECT stays (snapshot.showRedo = true), which brings them back.
]]
--- The record fields that are DISPLAYED hold a LOCALE KEY, never a literal:
--- copyRecord() resolves them through Locale.t, so /gideon lang applies immediately,
--- without a reload. Structural fields (key, greens, reds, numbers, position,
--- ping, complement) are language-independent and stay literal.
local CONVENTION = {
    ["1V3R"] = {
        key = "1V3R",
        display = "state.display.1V3R",
        orbs = "state.orbs.1V3R",
        greens = 1,
        reds = 3,
        numbers = { "1", "3" },
        numberText = "state.numberText.1V3R",
        numberAmbiguous = true,
        dominant = "state.dominant.1V3R",
        position = "HOLD",
        positionLabel = "state.positionLabel.1V3R",
        ping = "Warning",
        pingColor = "state.pingColor.1V3R",
        pingColorHex = "|cffff4040",
        role = "ANCHOR",
        roleName = "state.roleName.1V3R",
        actionPing = "state.actionPing.1V3R",
        actionNoPing = "state.actionNoPing.1V3R",
        complement = "3V1R",
        buttonLabel = "state.buttonLabel.1V3R",
        -- THE ONE WORD shown after the click (raid-lead wording): "Ping".
        word = "state.word.1V3R",
    },
    ["2V2R"] = {
        key = "2V2R",
        display = "state.display.2V2R",
        orbs = "state.orbs.2V2R",
        greens = 2,
        reds = 2,
        numbers = { "2" },
        numberText = "state.numberText.2V2R",
        numberAmbiguous = false,
        dominant = "state.dominant.2V2R",
        position = "MIDDLE",
        positionLabel = "state.positionLabel.2V2R",
        ping = "OnMyWay",
        pingColor = "state.pingColor.2V2R",
        pingColorHex = "|cff40a0ff",
        role = "MID",
        roleName = "state.roleName.2V2R",
        actionPing = "state.actionPing.2V2R",
        actionNoPing = "state.actionNoPing.2V2R",
        complement = "2V2R",
        buttonLabel = "state.buttonLabel.2V2R",
        -- THE ONE WORD shown after the click (raid-lead wording): "BOSS".
        word = "state.word.2V2R",
    },
    ["3V1R"] = {
        key = "3V1R",
        display = "state.display.3V1R",
        orbs = "state.orbs.3V1R",
        greens = 3,
        reds = 1,
        numbers = { "1", "3" },
        numberText = "state.numberText.3V1R",
        numberAmbiguous = true,
        dominant = "state.dominant.3V1R",
        position = "PURSUE",
        positionLabel = "state.positionLabel.3V1R",
        ping = "Assist",
        pingColor = "state.pingColor.3V1R",
        pingColorHex = "|cff40ff40",
        role = "CHASER",
        roleName = "state.roleName.3V1R",
        actionPing = "state.actionPing.3V1R",
        actionNoPing = "state.actionNoPing.3V1R",
        complement = "1V3R",
        buttonLabel = "state.buttonLabel.3V1R",
        -- THE ONE WORD shown after the click (raid-lead wording): "Chasseur".
        word = "state.word.3V1R",
    },
}

-- The table is exposed read-only (UI: colors, labels) but never returned
-- directly: getDeclaration() returns a copy.
Intermission.CONVENTION = CONVENTION

--- Green-count -> canonical state mapping (no state with 0 or 4 green).
local GREENS_TO_STATE = { [1] = "1V3R", [2] = "2V2R", [3] = "3V1R" }

--- Does the ROLE of `rec` have to ping under `mode`?
--- PURE and DETERMINISTIC (no clock, no API, no random):
---   "none"    -> never (nobody pings, positions only);
---   "color"   -> always (raidstrats variant: every state pings its own ping);
---   "anchors" -> only the ANCHOR (1V3R): one ping per anchor, ~8 per raid.
--- The mode is normalized first, so an unknown mode behaves like "anchors".
local function pingsInMode(rec, mode)
    local resolved = Config.resolvePingMode(mode)
    if resolved == "none" then
        return false
    end
    if resolved == "color" then
        return true
    end
    return rec.role == Intermission.ROLES.ANCHOR
end

--- Glued symbolic forms: "3v1r", "3 v 1 r" (once the spaces are removed).
local STATE_BY_SYMBOLS = { ["3v1r"] = "3V1R", ["2v2r"] = "2V2R", ["1v3r"] = "1V3R" }

--- BARE numbers that are ambiguous about the color: explicit refusal, never guessed.
local AMBIGUOUS_NUMBERS = { ["1"] = true, ["3"] = true }

--- Words accepted for each color ("v" / "r" forms included).
local GREEN_WORDS = {
    ["vert"] = true,
    ["verts"] = true,
    ["verte"] = true,
    ["vertes"] = true,
    ["green"] = true,
    ["greens"] = true,
    ["v"] = true,
}
local RED_WORDS = {
    ["rouge"] = true,
    ["rouges"] = true,
    ["red"] = true,
    ["reds"] = true,
    ["r"] = true,
}

--- UTF-8 -> ASCII replacements, SORTED list (no pairs(), determinism).
--- Allows typing "majorite verte" without accents: the input stays tolerated.
local ACCENT_MAP = {
    { "\195\168", "e" },
    { "\195\169", "e" },
    { "\195\170", "e" },
    { "\195\167", "c" },
    { "\195\174", "i" },
    { "\195\180", "o" },
    { "\195\185", "u" },
    { "\195\187", "u" },
    { "\195\160", "a" },
    { "\195\162", "a" },
}

local function deaccent(text)
    local out = text
    for index = 1, #ACCENT_MAP do
        out = out:gsub(ACCENT_MAP[index][1], ACCENT_MAP[index][2])
    end
    return out
end

local function flatten(raw)
    local text = deaccent(tostring(raw)):lower()
    -- non-breaking spaces + all the usual separators -> single space
    text = text:gsub("[\194\160]", " ")
    text = text:gsub("[%-_+/,;:%.]+", " ")
    text = text:gsub("%s+", " ")
    return text:gsub("^%s*(.-)%s*$", "%1")
end

local function ambiguousMessage(number)
    return Locale.format("err.numberAmbiguous", tostring(number))
end

local function round(n)
    return math.floor(n + 0.5)
end

local function clampNumber(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function clampInt(value, min, max)
    return round(clampNumber(tonumber(value) or min, min, max))
end

local function copyRecord(rec, mode)
    local resolvedMode = Config.resolvePingMode(mode)
    local numbers = {}
    for index = 1, #rec.numbers do
        numbers[#numbers + 1] = rec.numbers[index]
    end
    local bindNames = Intermission.bindNames(rec.key)
    -- The ping decision depends ONLY on the role and the configured policy; the
    -- ONE action line and the "PING: YES/NO" banner follow it, so a role never
    -- receives a contradictory order.
    local shouldPing = pingsInMode(rec, resolvedMode)
    local roleName = Locale.t(rec.roleName)
    return {
        key = rec.key,
        display = Locale.t(rec.display),
        orbs = Locale.t(rec.orbs),
        greens = rec.greens,
        reds = rec.reds,
        numbers = numbers,
        numberText = Locale.t(rec.numberText),
        numberAmbiguous = rec.numberAmbiguous,
        dominant = Locale.t(rec.dominant),
        position = rec.position,
        positionLabel = Locale.t(rec.positionLabel),
        -- The ping to use (the player triggers it with their own keybind).
        ping = rec.ping,
        pingColor = Locale.t(rec.pingColor),
        pingColorHex = rec.pingColorHex,
        bindName = bindNames ~= nil and bindNames[1] or nil,
        bindNames = bindNames,
        -- PING ROLE (never deduced from the number) + its action line.
        role = rec.role,
        roleName = roleName,
        roleLine = Locale.format("ui.roleLine", roleName),
        action = Locale.t(shouldPing and rec.actionPing or rec.actionNoPing),
        actionLine = Locale.format(shouldPing and rec.actionPing or rec.actionNoPing, Intermission.pingLabel(rec.ping)),
        -- Ping policy applied to this state.
        shouldPing = shouldPing,
        pingDecision = Locale.t(shouldPing and "state.ping.yes" or "state.ping.no"),
        -- Ping line: only for a role that has to ping (the key itself is read by
        -- the rendering layer and formatted in pingHint); nil otherwise, so a
        -- role that must not ping never carries a ping instruction.
        pingLine = shouldPing and Locale.format("ping.noKey", Intermission.pingLabel(rec.ping)) or nil,
        pingPolicy = resolvedMode,
        policyLine = Locale.format(
            "pingMode." .. resolvedMode,
            Intermission.pingLabel("Warning"),
            Intermission.pingLabel("OnMyWay"),
            Intermission.pingLabel("Assist")
        ),
        complement = rec.complement,
        buttonLabel = Locale.t(rec.buttonLabel),
        -- THE ONE WORD the panel writes after the click ("Ping" / "BOSS" /
        -- "Chasseur"): resolved HERE like every other displayed string, so
        -- /gideon lang applies immediately and the rendering layer writes no literal.
        word = Locale.t(rec.word),
    }
end

--- "vvvr" / "vvrr" / "vrrr": 4 color letters, the green ones are counted.
local function stateFromLetters(compact)
    if #compact ~= 4 or compact:match("^[vr]+$") == nil then
        return nil
    end
    local greens = 0
    for index = 1, 4 do
        if compact:sub(index, index) == "v" then
            greens = greens + 1
        end
    end
    return GREENS_TO_STATE[greens]
end

--- Counts the colors cited in text: "3 verts + 1 rouge", "vert-vert-vert-rouge".
--- `explicit` counts the colors preceded by a number; `words` the total number of
--- color words (used to distinguish "vert" alone = dominant color from
--- "vert vert vert rouge" = 3 green + 1 red).
local function analyzeColors(flat)
    local greens, reds, explicit, words = 0, 0, 0, 0
    local hasGreenWord, hasRedWord = false, false
    for number, word in flat:gmatch("(%d*)%s*([a-z]+)") do
        local isGreen = GREEN_WORDS[word] ~= nil
        local isRed = RED_WORDS[word] ~= nil
        if isGreen or isRed then
            local count = tonumber(number)
            if count == nil then
                count = 1
            else
                explicit = explicit + 1
            end
            words = words + 1
            if isGreen then
                greens = greens + count
                hasGreenWord = true
            else
                reds = reds + count
                hasRedWord = true
            end
        end
    end
    return {
        greens = greens,
        reds = reds,
        explicit = explicit,
        words = words,
        hasGreenWord = hasGreenWord,
        hasRedWord = hasRedWord,
    }
end

--- Normalizes the player's input into a state key: "3V1R" | "2V2R" | "1V3R".
---
--- Accepted forms (tolerant: case, spaces, accents, separators):
---   short composition  : "3V1R", "2V2R", "1V3R" (including "3 v 1 r");
---   letters            : "vvvr", "vvrr", "vrrr", "vert-vert-vert-rouge";
---   text               : "3 verts + 1 rouge", "3 verts", "1 vert 3 rouges";
---   dominant color     : "vert" (= 3V1R), "rouge" (= 1V3R);
---   bare number        : "2" (= 2V2R, NOT ambiguous).
---
--- EXPLICIT REFUSAL: "1" and "3" ALONE are AMBIGUOUS (the number does not reveal
--- the color) -> (nil, message asking for the dominant color,
--- { ambiguous = true, number = ... }). The code NEVER guesses the color.
--- @return string|nil key, string|nil error, table|nil info
function Intermission.normalizeDeclaration(raw)
    if type(raw) == "number" then
        raw = tostring(raw)
    end
    if type(raw) ~= "string" then
        return nil, Locale.t("err.declarationInvalid")
    end
    local flat = flatten(raw)
    local compact = flat:gsub("%s+", "")
    if compact == "" then
        return nil, Locale.t("err.declarationEmpty")
    end
    if compact == "2" then
        return "2V2R"
    end
    if AMBIGUOUS_NUMBERS[compact] then
        return nil, ambiguousMessage(compact), { ambiguous = true, number = compact }
    end
    local bySymbol = STATE_BY_SYMBOLS[compact]
    if bySymbol ~= nil then
        return bySymbol
    end
    local byLetters = stateFromLetters(compact)
    if byLetters ~= nil then
        return byLetters
    end

    local colors = analyzeColors(flat)
    -- A SINGLE color word without a number = the announced dominant color:
    -- "vert" -> 3 green, "rouge" -> 3 red (the only compositions with a
    -- dominant color are 3-1).
    if colors.words == 1 and colors.explicit == 0 then
        if colors.hasGreenWord then
            return "3V1R"
        end
        return "1V3R"
    end
    local total = colors.greens + colors.reds
    if total == 4 and colors.reds == 4 - colors.greens and GREENS_TO_STATE[colors.greens] ~= nil then
        return GREENS_TO_STATE[colors.greens]
    end
    if total > 0 and colors.reds == 0 and GREENS_TO_STATE[colors.greens] ~= nil then
        -- a single count is given: the rest is deduced (4 orbs in total)
        return GREENS_TO_STATE[colors.greens]
    end
    if total > 0 then
        return nil, Locale.format("err.compositionUnusable", colors.greens, colors.reds), { ambiguous = true }
    end
    return nil, Locale.format("err.declarationUnknown", raw), { ambiguous = false }
end

--- Returns (copy of the canonical state, nil) or (nil, error, info).
--- The info carries { ambiguous = true } when the input did NOT reveal the
--- color: the caller must then ASK for the dominant color.
--- `pingMode` is the configured ping policy ("anchors" by default): it decides
--- `shouldPing` and the action line. An unknown value falls back to "anchors"
--- (never an error).
function Intermission.getDeclaration(raw, pingMode)
    local key, err, info = Intermission.normalizeDeclaration(raw)
    if key == nil then
        return nil, err, info
    end
    return copyRecord(CONVENTION[key], pingMode)
end

--- Does the state declared by `raw` have to ping under `pingMode`?
--- @return boolean|nil shouldPing, string|nil error
function Intermission.shouldPing(raw, pingMode)
    local rec, err = Intermission.getDeclaration(raw, pingMode)
    if rec == nil then
        return nil, err
    end
    return rec.shouldPing
end

--- Localized explanation of a ping policy (pure, never raises): used by the UI
--- and by /gideon ping. The policy is NOT displayed on the combat panel any more.
--- @param pingMode string|nil raw policy
--- @return string line, string resolvedMode
function Intermission.pingPolicyLine(pingMode)
    local mode = Config.resolvePingMode(pingMode)
    return Locale.t("pingMode." .. mode), mode
end

--- The state that MUST join `raw` to make 4 green + 4 red.
--- @return string|nil key, string|nil error
function Intermission.complementOf(raw)
    local rec, err = Intermission.getDeclaration(raw)
    if rec == nil then
        return nil, err
    end
    return rec.complement
end

--- Checks whether two declarations can join WITHOUT DYING.
--- Rule (COLOR ADDITION): the sum must make 4 GREEN and 4 RED.
---   3V1R + 1V3R = 4V4R: safe;
---   2V2R + 2V2R = 4V4R: safe;
---   3V1R + 2V2R = 5 green = "5g": dead;
---   1V3R + 1V3R = 2 green + 6 red: dead.
--- @return table|nil result { ok, label, greens, reds, reason, required }, string|nil error
function Intermission.checkMeeting(rawA, rawB)
    local a, errA = Intermission.getDeclaration(rawA)
    if a == nil then
        return nil, errA
    end
    local b, errB = Intermission.getDeclaration(rawB)
    if b == nil then
        return nil, errB
    end
    local greens = a.greens + b.greens
    local reds = a.reds + b.reds
    local label = a.key .. "+" .. b.key
    local ok = (greens == 4 and reds == 4)
    local reason
    if ok then
        reason = Locale.format("meeting.safe", greens, reds)
    elseif greens == 5 then
        reason = Locale.t("meeting.fiveGreen")
    else
        reason = Locale.format("meeting.forbidden", greens, reds)
    end
    return { ok = ok, label = label, greens = greens, reds = reds, reason = reason, required = a.complement }
end

--- The ping instruction of a state: WHICH ping to use and, when the rendering
--- layer managed to read the player's keybind, WHICH key to press.
--- PURE: the key is INJECTED (the binding lookup happens in UI/, never here).
--- An empty or non-string key is treated as "no keybind": the line then asks for
--- a keybind instead of showing a shortcut that does not exist.
--- @param raw string|nil composition
--- @param pingMode string|nil configured ping policy
--- @param key string|nil key bound by the player, read by the wiring layer
--- @return table|nil { ping, key, bindName, bindNames, line }, string|nil error
function Intermission.pingHint(raw, pingMode, key)
    local rec, err = Intermission.getDeclaration(raw, pingMode)
    if rec == nil then
        return nil, err
    end
    if not rec.shouldPing then
        return nil, Locale.format("err.pingNotAllowed", rec.roleName, rec.pingPolicy)
    end
    local pressed = nil
    if type(key) == "string" and key ~= "" then
        pressed = key
    end
    local label = Intermission.pingLabel(rec.ping)
    local line
    if pressed ~= nil then
        line = Locale.format("ping.press", label, pressed)
    else
        line = Locale.format("ping.noKey", label)
    end
    return {
        ping = rec.ping,
        label = label,
        key = pressed,
        bindName = rec.bindName,
        bindNames = rec.bindNames,
        line = line,
    }
end

--- Validates a timeline prepared out of game (SavedVariables) or built by the
--- wiring from the configuration.
--- @return table|nil { name, leadSeconds, visibilitySeconds, durationSeconds }, string|nil error
function Intermission.validateTimeline(entry)
    if entry == nil then
        return {
            name = "Intermission",
            leadSeconds = Intermission.LEAD_SECONDS,
            visibilitySeconds = Intermission.VISIBILITY_SECONDS,
            durationSeconds = Intermission.DEFAULT_DURATION_SECONDS,
        }
    end
    if type(entry) ~= "table" then
        return nil, Locale.t("err.invalidTimeline")
    end
    local lead = Intermission.LEAD_SECONDS
    if type(entry.leadSeconds) == "number" then
        lead = clampInt(entry.leadSeconds, 0, 10)
    end
    local visibility = Intermission.VISIBILITY_SECONDS
    if type(entry.visibilitySeconds) == "number" then
        visibility = clampInt(entry.visibilitySeconds, 1, 10)
    end
    local duration = Intermission.DEFAULT_DURATION_SECONDS
    if type(entry.durationSeconds) == "number" then
        duration = clampInt(entry.durationSeconds, visibility + 1, 120)
    end
    if duration <= visibility then
        duration = visibility + 1
    end
    local name = "Intermission"
    if type(entry.name) == "string" and entry.name ~= "" then
        name = entry.name
    end
    return { name = name, leadSeconds = lead, visibilitySeconds = visibility, durationSeconds = duration }
end

--- Creates a fresh state (IDLE).
function Intermission.newState(timeline)
    local resolved = Intermission.validateTimeline(timeline) or Intermission.validateTimeline(nil)
    return {
        phase = PHASE_IDLE,
        elapsed = 0,
        declaration = nil,
        timeline = resolved,
    }
end

--- Starts the intermission (trigger: the pre-computed schedule, a key/button).
--- A positive lead time opens the panel in the PENDING phase: the intermission
--- clock itself (visibility window, then darkened room) only starts when the
--- lead time has elapsed, i.e. at the intermission.
--- @return table|nil state, string|nil error
function Intermission.start(state, timeline)
    if type(state) ~= "table" then
        return nil, Locale.t("err.invalidState")
    end
    if timeline ~= nil then
        local resolved, err = Intermission.validateTimeline(timeline)
        if resolved == nil then
            return nil, err
        end
        state.timeline = resolved
    end
    state.elapsed = 0
    state.declaration = nil
    if state.timeline.leadSeconds > 0 then
        state.phase = PHASE_PENDING
    else
        state.phase = PHASE_VISIBLE
    end
    return state
end

--- Advances the intermission clock. dt is provided by the wiring layer:
--- this module never calls GetTime (forbidden in Core/, see CONVENTIONS 7).
function Intermission.tick(state, dt)
    if type(state) ~= "table" then
        return state
    end
    if state.phase ~= PHASE_PENDING and state.phase ~= PHASE_VISIBLE and state.phase ~= PHASE_DARK then
        return state
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return state
    end
    local timeline = state.timeline
    state.elapsed = state.elapsed + step
    if state.phase == PHASE_PENDING then
        -- The lead time only decides WHEN the intermission starts; the
        -- intermission clock starts from zero at that exact moment.
        if state.elapsed >= timeline.leadSeconds then
            state.phase = PHASE_VISIBLE
            state.elapsed = 0
        end
        return state
    end
    if state.elapsed >= timeline.durationSeconds then
        state.phase = PHASE_DONE
    elseif state.elapsed >= timeline.visibilitySeconds then
        state.phase = PHASE_DARK
    else
        state.phase = PHASE_VISIBLE
    end
    return state
end

--- Records the player's declaration: the ORB COMPOSITION they see ("3V1R",
--- "2V2R", "1V3R", or a tolerated form such as "3 verts"). A bare number "1" or
--- "3" is REFUSED (ambiguous): see normalizeDeclaration.
--- Allowed in PENDING (the panel opens before the intermission), VISIBLE and DARK.
--- @return table|nil state, string|nil error
function Intermission.declare(state, raw)
    if type(state) ~= "table" then
        return nil, Locale.t("err.invalidState")
    end
    if state.phase == PHASE_IDLE then
        return nil, Locale.t("err.notStarted")
    end
    if state.phase == PHASE_DONE then
        return nil, Locale.t("err.finished")
    end
    local n, err = Intermission.normalizeDeclaration(raw)
    if n == nil then
        return nil, err
    end
    state.declaration = n
    return state
end

--- The REDO / CORRECT button: forgets the declaration and brings the panel back
--- to the three composition choices. Usable as many times as needed, in every
--- phase except IDLE.
--- @return table|nil state, string|nil error
function Intermission.clearDeclaration(state)
    if type(state) ~= "table" then
        return nil, Locale.t("err.invalidState")
    end
    if state.phase == PHASE_IDLE then
        return nil, Locale.t("err.notStarted")
    end
    if state.declaration == nil then
        return nil, Locale.t("err.nothingToRedo")
    end
    state.declaration = nil
    return state
end

--- Resets the state to zero (IDLE).
function Intermission.reset(state)
    if type(state) ~= "table" then
        return nil, Locale.t("err.invalidState")
    end
    state.phase = PHASE_IDLE
    state.elapsed = 0
    state.declaration = nil
    return state
end

--- Remaining seconds of the visibility window (0 once the room is dark).
function Intermission.remainingVisibility(state)
    if type(state) ~= "table" or type(state.timeline) ~= "table" then
        return 0
    end
    local left = state.timeline.visibilitySeconds - state.elapsed
    if left < 0 then
        left = 0
    end
    return round(left)
end

--- Remaining seconds before the intermission starts (0 outside PENDING).
function Intermission.remainingLead(state)
    if type(state) ~= "table" or type(state.timeline) ~= "table" then
        return 0
    end
    local left = state.timeline.leadSeconds - state.elapsed
    if left < 0 then
        left = 0
    end
    return round(left)
end

--[[ BOUNDED AUTO-CLOSE (the safety net of the panel) --------------------------

     The panel closes BY ITSELF at the end of the intermission: the state machine
     reaches DONE (after `visibilitySeconds` of visibility, then the darkened
     room, `durationSeconds` in total) and the wiring hides the panel.

     That path ALONE is not enough. If the clock stops ticking before DONE - a
     state that never advances any more, a panel shown with no intermission
     running, a ticker stopped by another module - the panel stays on screen
     indefinitely, over the raid, and nothing brings it back. In-game report of
     the raid lead: the frame must DISAPPEAR when the intermission is over.

     The guard below is that safety net. It is PURE (no clock of its own: the
     wiring feeds it the same constant dt as the state machine) and obeys three
     rules:
       - it is ARMED when the panel opens and RE-ARMED at every new intermission
         (a fresh delay, a fresh elapsed);
       - its delay is BOUNDED and CONFIGURABLE (Config.autoCloseSeconds) and can
         NEVER be shorter than the WHOLE legitimate window of an intermission
         (lead + visibility + duration + margin): the guard can therefore never
         cut a real intermission short - it only catches the cases where the
         panel should already be gone;
       - once expired it reports `true` ONCE (it disarms itself), so the wiring
         hides the panel exactly once and the next intermission re-arms it.
]]

--- Margin added to the legitimate window of an intermission before the safety
--- net fires: the panel must close at the end of the intermission, and the net
--- only exists for the cases where that close never happened.
Intermission.AUTO_CLOSE_MARGIN_SECONDS = 5

--- Default safety delay (seconds), MEASURED on the real timings of the target
--- boss: lead 2 s + visibility 3 s + duration 20 s = a 25 s window, plus the 5 s
--- margin above. `/gideon ` never needs to touch it; Config clamps any persisted
--- value.
Intermission.DEFAULT_AUTO_CLOSE_SECONDS = 30

--- Bounds of the CONFIGURED delay (Config.autoCloseSeconds). Below the minimum
--- the panel could vanish in the middle of a real intermission; above the
--- maximum a hand-edited SavedVariables could park it on screen for minutes.
Intermission.MIN_AUTO_CLOSE_SECONDS = 5
Intermission.MAX_AUTO_CLOSE_SECONDS = 300

--- The whole legitimate on-screen window of an intermission, in seconds: the
--- lead time (the panel is open before the intermission starts) plus the
--- intermission itself. The timeline goes through the pure resolver first, so an
--- absurd persisted value can not make the window huge.
--- @param timeline table|nil resolved timeline (nil = the module defaults)
--- @return number seconds
function Intermission.windowSeconds(timeline)
    local resolved = Intermission.validateTimeline(timeline)
    return resolved.leadSeconds + resolved.visibilitySeconds + resolved.durationSeconds
end

--- The BOUNDED auto-close delay of a panel session: the configured safety delay,
--- or the whole legitimate window plus a margin when that is LONGER. Always
--- finite, always >= the real intermission: it can never cut one short.
--- `configuredSeconds` is the RESOLVED preference, injected by the wiring
--- (Core/ never reads the SavedVariables): nil falls back to the default.
--- @param timeline table|nil timeline of the session (nil = no intermission running)
--- @param configuredSeconds number|nil resolved config (Config.autoCloseSeconds)
--- @return number seconds (> 0)
function Intermission.closeDelay(timeline, configuredSeconds)
    local configured = tonumber(configuredSeconds) or Intermission.DEFAULT_AUTO_CLOSE_SECONDS
    if configured < Intermission.MIN_AUTO_CLOSE_SECONDS then
        configured = Intermission.MIN_AUTO_CLOSE_SECONDS
    end
    if configured > Intermission.MAX_AUTO_CLOSE_SECONDS then
        configured = Intermission.MAX_AUTO_CLOSE_SECONDS
    end
    if timeline == nil then
        -- No intermission running (a panel shown by hand, or a state that was
        -- lost): the configured delay is the only bound.
        return configured
    end
    local window = Intermission.windowSeconds(timeline) + Intermission.AUTO_CLOSE_MARGIN_SECONDS
    if window > configured then
        return window
    end
    return configured
end

--- Creates the guard (`{ armed = false }`): plain data, no API, no clock.
--- @return table guard
function Intermission.newCloseGuard()
    return { armed = false, delay = 0, elapsed = 0 }
end

--- True while the guard is counting.
--- @param guard table|nil
--- @return boolean
function Intermission.closeGuardArmed(guard)
    return type(guard) == "table" and guard.armed == true
end

--- ARMS (or RE-ARMS) the guard with a fresh delay: called when the panel opens
--- and at every new intermission. A delay that is not a positive number arms
--- nothing (a caller that forgot the value can not park the panel for ever).
--- @param guard table|nil
--- @param delay number|nil seconds
--- @return table|nil the guard
function Intermission.armCloseGuard(guard, delay)
    if type(guard) ~= "table" then
        return nil
    end
    local seconds = tonumber(delay)
    if seconds == nil or seconds <= 0 then
        guard.armed = false
        guard.elapsed = 0
        guard.delay = 0
        return guard
    end
    guard.armed = true
    guard.delay = seconds
    guard.elapsed = 0
    return guard
end

--- Disarms the guard (the panel was closed by the player, or the intermission
--- ended through the normal path).
--- @param guard table|nil
--- @return table|nil
function Intermission.disarmCloseGuard(guard)
    if type(guard) ~= "table" then
        return nil
    end
    guard.armed = false
    guard.elapsed = 0
    return guard
end

--- Advances the guard by dt and reports whether the panel MUST be hidden now.
--- Returns `true` at most once per arming (the guard disarms itself), so a
--- caller that hides the panel can not hide it twice by accident.
--- @param guard table|nil
--- @param dt number|nil injected time step (seconds)
--- @return boolean expired
function Intermission.tickCloseGuard(guard, dt)
    if type(guard) ~= "table" or guard.armed ~= true then
        return false
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return false
    end
    guard.elapsed = (guard.elapsed or 0) + step
    if guard.elapsed >= guard.delay then
        guard.armed = false
        return true
    end
    return false
end

--- Displayable state, fully computed here: the UI layer only renders.
--- The panel shows the ESSENTIAL only (state, role, PING: YES/NO, ONE action
--- line) because it is read during combat.
--- @param state table|nil intermission state
--- @param pingMode string|nil configured ping policy
--- @param bindingResolver function|nil injected by the wiring layer:
---        function(bindNames) -> key|nil. Core/ NEVER calls an API: it only calls
---        this injected resolver under pcall (an absent resolver = no key known).
function Intermission.snapshot(state, pingMode, bindingResolver)
    local mode = Config.resolvePingMode(pingMode)
    local phase = PHASE_IDLE
    local declaration, elapsed, timeline = nil, 0, Intermission.validateTimeline(nil)
    if type(state) == "table" then
        phase = state.phase or PHASE_IDLE
        declaration = state.declaration
        elapsed = state.elapsed or 0
        timeline = state.timeline or timeline
    end

    local snap = {
        phase = phase,
        visible = phase ~= PHASE_IDLE,
        -- The wiring closes the panel by itself when the intermission is over.
        autoClose = phase == PHASE_DONE,
        -- THE THREE CHOICES ARE HIDDEN AS SOON AS ONE IS CLICKED (in-game
        -- feedback: "once you click, you must not see the others any more"):
        -- only the result stays, with CORRECT.
        showButtons = (phase == PHASE_PENDING or phase == PHASE_VISIBLE or phase == PHASE_DARK) and declaration == nil,
        showRedo = false,
        declaration = declaration,
        stateText = declaration or "",
        stateLong = nil,
        -- THE ONE WORD of the panel (raid-lead request: after the click the
        -- panel shows ONE word and nothing else): nil until a composition is
        -- declared. `wordKey` is the canonical state the word belongs to, so the
        -- rendering layer can pick the size and the color WITHOUT parsing the
        -- word itself.
        word = nil,
        wordKey = nil,
        headline = "",
        countdownText = "0",
        lines = {},
        prompt = nil,
        role = nil,
        roleName = nil,
        roleLine = nil,
        shouldPing = false,
        pingDecision = nil,
        pingBanner = nil,
        pingColorHex = nil,
        pingHint = nil,
        actionLine = nil,
        pingPolicy = mode,
        policyLine = Locale.t("pingMode." .. mode),
    }

    if phase == PHASE_IDLE then
        snap.headline = Locale.t("inter.headline.idle")
        snap.lines[1] = Locale.t("inter.line.idle")
    elseif phase == PHASE_PENDING then
        local left = Intermission.remainingLead({ timeline = timeline, elapsed = elapsed })
        snap.countdownText = tostring(left)
        snap.headline = Locale.format("inter.headline.getReady", left)
    elseif phase == PHASE_VISIBLE then
        local left = Intermission.remainingVisibility({ timeline = timeline, elapsed = elapsed })
        snap.countdownText = tostring(left)
        snap.headline = Locale.format("inter.headline.visible", left)
    elseif phase == PHASE_DARK then
        snap.headline = Locale.t("inter.headline.dark")
    else
        snap.headline = Locale.t("inter.headline.done")
    end

    local rec = declaration and CONVENTION[declaration] or nil
    if rec ~= nil then
        -- copyRecord resolves the locale keys: only the copy is displayed.
        local shown = copyRecord(rec, mode)
        snap.instruction = shown
        snap.stateLong = shown.display
        snap.role = shown.role
        snap.roleName = shown.roleName
        snap.roleLine = shown.roleLine
        snap.shouldPing = shown.shouldPing
        snap.pingDecision = shown.pingDecision
        snap.pingBanner = Locale.format("ui.pingBanner", shown.pingDecision)
        snap.pingColorHex = shown.shouldPing and shown.pingColorHex or nil
        snap.actionLine = shown.actionLine
        -- The ONE word of the panel ("Ping" / "BOSS" / "Chasseur") and the state
        -- it belongs to: everything else the old panel used to write (state,
        -- role, ping banner, action line) is still computed above for the chat
        -- commands, but the PANEL displays the word only.
        snap.word = shown.word
        snap.wordKey = shown.key
        -- CORRECT is available as long as the intermission session is open: it
        -- forgets the declaration and brings the three choices back.
        snap.showRedo = phase == PHASE_PENDING or phase == PHASE_VISIBLE or phase == PHASE_DARK
        if shown.shouldPing then
            -- The key is read by the RENDERING layer (injected resolver) and
            -- formatted HERE: an unknown key simply yields the "set a keybind"
            -- line, never a wrong shortcut.
            local pressed = nil
            if type(bindingResolver) == "function" then
                local ok, resolved = pcall(bindingResolver, shown.bindNames)
                if ok and type(resolved) == "string" and resolved ~= "" then
                    pressed = resolved
                end
            end
            snap.pingHint = Intermission.pingHint(shown.key, mode, pressed)
        end
        snap.lines[#snap.lines + 1] = shown.roleLine
        if snap.pingHint ~= nil then
            snap.lines[#snap.lines + 1] = snap.pingHint.line
        end
        snap.lines[#snap.lines + 1] = shown.actionLine
    elseif snap.showButtons then
        snap.prompt = Locale.t("inter.prompt")
        snap.lines[#snap.lines + 1] = snap.prompt
    end
    return snap
end

--[[ Pre-pull / placement: NO TEXT ANY MORE.

     The placement panel displays ONE thing - the Gideon illustration the raid
     lead delivered (Core/Layout.placementPanel, Core/Textures.placement*) - and
     nothing else. The former content builder (headline "BEFORE THE PULL - PLACE
     THE PANEL", drag/keybind/procedure lines, the OK label) was DELETED with its
     locale keys: it was the last title a player could read at the top of the
     intermission window, and the raid lead asked for it to go for good. The
     placement is validated by `/gideon inter ok` (UI.IntermissionConfirmSetup), the
     cross cancels and the picture is dragged to the wanted spot.
]]

--[[ Pre-computed intermission RUN: everything is timed from ENCOUNTER_START.

     The pull is the time origin (the wiring calls newRun() on ENCOUNTER_START and
     feeds advanceRun(run, dt) with a constant step). The panel must open
     `lead` seconds BEFORE each intermission of the schedule, close at the end of
     the intermission, and open again at the next one.

     Timer values measured by the raid lead: 46.3 s for the first intermission,
     then 148.9 / 251.5 / 353.2 s. They are PERSISTED (Config) and can be
     replaced out of game.
]]

--- @param schedule table|nil persisted schedule (seconds since the pull)
--- @param leadSeconds number|nil seconds of lead before each intermission
--- @return table run { schedule, lead, index, elapsed }
function Intermission.newRun(schedule, leadSeconds)
    return {
        schedule = Config.resolveSchedule(schedule),
        lead = clampInt(leadSeconds or Intermission.LEAD_SECONDS, 0, 10),
        index = 1,
        elapsed = 0,
    }
end

--- Absolute time (seconds since the pull) of the NEXT intermission, nil once the
--- schedule is exhausted.
function Intermission.runNextAt(run)
    if type(run) ~= "table" or type(run.schedule) ~= "table" then
        return nil
    end
    return run.schedule[run.index or 1]
end

--- Absolute time at which the PANEL must open for the next intermission.
function Intermission.runOpenAt(run)
    local at = Intermission.runNextAt(run)
    if at == nil then
        return nil
    end
    return at - (run.lead or Intermission.LEAD_SECONDS)
end

--- How many intermissions are still to come (0 once the schedule is exhausted).
function Intermission.runRemaining(run)
    if type(run) ~= "table" or type(run.schedule) ~= "table" then
        return 0
    end
    local left = #run.schedule - ((run.index or 1) - 1)
    if left < 0 then
        left = 0
    end
    return left
end

function Intermission.runFinished(run)
    return Intermission.runNextAt(run) == nil
end

--- Advances the encounter clock by dt and reports whether a new intermission had
--- to be opened. INVARIANT: at most ONE opening per call (a huge dt never skips
--- an intermission: the next call reports it).
--- @return table run, number|nil openedIndex (1-based index in the schedule)
function Intermission.advanceRun(run, dt)
    if type(run) ~= "table" then
        return run, nil
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return run, nil
    end
    run.elapsed = (run.elapsed or 0) + step
    local openAt = Intermission.runOpenAt(run)
    if openAt ~= nil and run.elapsed >= openAt then
        local opened = run.index or 1
        run.index = opened + 1
        return run, opened
    end
    return run, nil
end

--- Restarts the encounter clock (new pull). Keeps the previous schedule/lead.
--- @return table|nil run
function Intermission.resetRun(run, schedule, leadSeconds)
    if type(run) ~= "table" then
        return nil
    end
    run.schedule = Config.resolveSchedule(schedule or run.schedule)
    run.lead = clampInt(leadSeconds or run.lead or Intermission.LEAD_SECONDS, 0, 10)
    run.index = 1
    run.elapsed = 0
    return run
end

--[[ Plan prepared out of game.

     OPTIONAL block written by GIDEON into the SavedVariables:

       assignment = {
           schema = 1,
           pairs = { { a = "Velna", b = "Torgh" }, ... },
           plan  = {                                  -- optional
               { name = "Velna", role = "2", position = "MIDDLE", note = "..." },
               ...
           },
       }

     `role` may contain the prepared ORB COMPOSITION ("3V1R", "2V2R", "1V3R", or
     even "3 verts") or a free raid role ("Tank", "Heal"). A bare number "1" or
     "3" is AMBIGUOUS: it is reported as such, never guessed. Nothing is
     invented: if GIDEON does not write it, the addon does not display it.
]]

--- Validates the `plan` block: malformed entries dropped and listed, never a crash.
--- @return table { byName = {}, order = {}, errors = {} }
function Intermission.validatePlan(plan)
    local out = { byName = {}, order = {}, errors = {} }
    if plan == nil then
        return out
    end
    if type(plan) ~= "table" then
        out.errors[#out.errors + 1] = Locale.t("err.planInvalid")
        return out
    end
    for index = 1, #plan do
        local entry = plan[index]
        if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == "" then
            out.errors[#out.errors + 1] = Locale.format("err.planEntryNoName", index)
        elseif out.byName[entry.name] ~= nil then
            out.errors[#out.errors + 1] = Locale.format("err.planEntryDuplicate", index, entry.name)
        else
            local rec = { name = entry.name }
            if type(entry.role) == "string" and entry.role ~= "" then
                rec.role = entry.role
            end
            if type(entry.position) == "string" and entry.position ~= "" then
                rec.position = entry.position
            end
            if type(entry.note) == "string" and entry.note ~= "" then
                rec.note = entry.note
            end
            out.byName[entry.name] = rec
            out.order[#out.order + 1] = entry.name
        end
    end
    table.sort(out.order)
    table.sort(out.errors)
    return out
end

local function sortedPairs(assignment)
    local list = {}
    for index = 1, #assignment.pairs do
        local pair = assignment.pairs[index]
        list[#list + 1] = { a = pair.a, b = pair.b }
    end
    table.sort(list, function(left, right)
        if left.a ~= right.a then
            return left.a < right.a
        end
        return left.b < right.b
    end)
    return list
end

local function describePlayer(plan, name)
    local rec = plan.byName[name]
    if rec == nil then
        return nil
    end
    local parts = {}
    if rec.role ~= nil then
        parts[#parts + 1] = Locale.format("plan.roleWord", rec.role)
    end
    if rec.position ~= nil then
        parts[#parts + 1] = Locale.format("plan.positionWord", rec.position)
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

--- Builds the pre-pull view: partner, prepared role/position, sorted pairs.
--- No API read: everything comes from the already validated GIDEON block.
--- `pingMode` is the configured ping policy: it decides the ping role deduced
--- from the prepared composition, and which ping/key it has to use.
--- @param assignment table block validated by Pairing.validateAssignment
--- @param playerName string name of the current player (string provided by the wiring)
--- @param pingMode string|nil configured ping policy ("anchors" by default)
--- @param bindingResolver function|nil injected by the wiring layer
--- @return table|nil plan, string|nil error
function Intermission.buildPlan(assignment, playerName, pingMode, bindingResolver)
    if type(assignment) ~= "table" or type(assignment.pairs) ~= "table" then
        return nil, Locale.t("err.invalidAssignment")
    end
    if type(playerName) ~= "string" or playerName == "" then
        return nil, Locale.t("err.invalidPlayerName")
    end
    local mode = Config.resolvePingMode(pingMode)

    local plan = Intermission.validatePlan(assignment.plan)
    local pairsList = sortedPairs(assignment)
    for index = 1, #pairsList do
        local pair = pairsList[index]
        pair.roleA = plan.byName[pair.a] and plan.byName[pair.a].role or nil
        pair.roleB = plan.byName[pair.b] and plan.byName[pair.b].role or nil
        pair.positionA = plan.byName[pair.a] and plan.byName[pair.a].position or nil
        pair.positionB = plan.byName[pair.b] and plan.byName[pair.b].position or nil
    end

    local out = {
        partner = nil,
        me = plan.byName[playerName],
        pairs = pairsList,
        planErrors = plan.errors,
        planCount = #plan.order,
        meeting = nil,
        pingRole = nil,
        shouldPing = nil,
        pingPolicy = mode,
        pingHint = nil,
        lines = {},
    }

    local lines = out.lines
    local partner = ns.Pairing.findPartner(assignment, playerName)
    if partner == nil then
        lines[#lines + 1] = Locale.t("plan.notPaired")
    else
        out.partner = partner
        lines[#lines + 1] = Locale.format("plan.partner", partner)
        if out.me ~= nil and out.me.role ~= nil then
            lines[#lines + 1] = Locale.format("plan.yourRole", out.me.role)
        end
        if out.me ~= nil and out.me.position ~= nil then
            lines[#lines + 1] = Locale.format("plan.yourPosition", out.me.position)
        end
        local partnerInfo = describePlayer(plan, partner)
        if partnerInfo ~= nil then
            lines[#lines + 1] = Locale.format("plan.playerInfo", partner, partnerInfo)
        end
        if out.me ~= nil and out.me.role ~= nil and plan.byName[partner] ~= nil then
            local meeting, meetingErr = Intermission.checkMeeting(out.me.role, plan.byName[partner].role)
            if meeting ~= nil then
                out.meeting = meeting
                if meeting.ok then
                    lines[#lines + 1] = Locale.format("meeting.labelOk", meeting.label, meeting.reason)
                else
                    lines[#lines + 1] = Locale.format("meeting.labelDead", meeting.label, meeting.reason)
                end
            else
                -- A prepared role of "1" or "3" alone is AMBIGUOUS: we say so, we do not guess.
                lines[#lines + 1] = Locale.format("meeting.unverifiable", tostring(meetingErr))
            end
        end
    end

    -- PING ROLE deduced from the PREPARED composition, under the configured
    -- policy: displayed only when GIDEON prepared an ORB COMPOSITION (a free
    -- raid role such as "Tank" deduces nothing). The ping to use (and, when the
    -- player bound one, the key to press) is named: there is NO macro any more.
    if out.me ~= nil and out.me.role ~= nil then
        local shown = Intermission.getDeclaration(out.me.role, mode)
        if shown ~= nil then
            out.pingRole = shown.role
            out.shouldPing = shown.shouldPing
            lines[#lines + 1] = Locale.format("plan.yourPingRole", shown.roleName, shown.key, shown.pingDecision)
            if shown.shouldPing then
                local pressed = nil
                if type(bindingResolver) == "function" then
                    local ok, resolved = pcall(bindingResolver, shown.bindNames)
                    if ok and type(resolved) == "string" and resolved ~= "" then
                        pressed = resolved
                    end
                end
                local hint = Intermission.pingHint(shown.key, mode, pressed)
                out.pingHint = hint
                if hint ~= nil then
                    lines[#lines + 1] = hint.line
                end
            end
        end
    end

    lines[#lines + 1] = Locale.format("plan.pairsHeader", #pairsList)
    for index = 1, #pairsList do
        local pair = pairsList[index]
        local suffix = ""
        local roles = {}
        if pair.roleA ~= nil then
            roles[#roles + 1] = pair.a .. "=" .. pair.roleA
        end
        if pair.roleB ~= nil then
            roles[#roles + 1] = pair.b .. "=" .. pair.roleB
        end
        if #roles > 0 then
            suffix = "  [" .. table.concat(roles, " / ") .. "]"
        end
        lines[#lines + 1] = "  " .. index .. ". " .. pair.a .. " - " .. pair.b .. suffix
    end
    if #plan.errors > 0 then
        lines[#lines + 1] = Locale.format("plan.errorsLine", #plan.errors)
    end
    -- The current ping policy is recalled with the plan (it decides the roles).
    lines[#lines + 1] = Locale.t("pingMode." .. mode)
    lines[#lines + 1] = Locale.t("plan.disclaimer")
    return out
end
