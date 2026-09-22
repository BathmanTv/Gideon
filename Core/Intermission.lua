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

    REJECTION OF THE OLD MODEL: the code used to bind "1" to "1 green + 3 red"
    and "3" to "3 green + 1 red", with a position and a ping deduced from the
    number. That is WRONG: 1 and 3 are ambiguous about the colors, only 2 is
    not. A declaration reduced to "1" or "3" is therefore REFUSED with a message
    asking for the dominant color (never guessed).

    API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
    Constrained source: "Combat API functions may now return secret values ...
    Tainted code is not allowed to compare or perform boolean tests on secret
    values."
    => this module NEVER compares a unit value. Everything it handles comes from
       the player (click) or from a file prepared out of game (SavedVariables).

    API ref 12.1.0: https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing
    Constrained source: "#protected - This can only be called from secure code."
    => the addon can NOT send a ping itself: it generates the TEXT of a macro
       that the player pastes and triggers (a macro is secure code).

    NO GetTime, NO math.random, NO non-deterministic order: time is injected
    into tick(state, dt) by the wiring layer.
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: the language layer is
--- a hard dependency (every string displayed in game goes through it).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Intermission.lua")

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

--- Default target token of the ping macro (ping yourself).
Intermission.DEFAULT_TARGET_TOKEN = "player"

--- Three canonical STATES, DETERMINISTIC display order (increasing green,
--- never pairs()): 1V3R, 2V2R, 3V1R.
Intermission.STATES = { "1V3R", "2V2R", "3V1R" }

--- Historical alias: the module used to talk about "declarations 1/2/3". These
--- are now ORB COMPOSITIONS; the alias avoids breaking the callers.
Intermission.DECLARATIONS = Intermission.STATES

--- Intermission phases.
Intermission.PHASE = {
    IDLE = "IDLE",
    VISIBLE = "VISIBLE",
    DARK = "DARK",
    DONE = "DONE",
}

local PHASE_IDLE = Intermission.PHASE.IDLE
local PHASE_VISIBLE = Intermission.PHASE.VISIBLE
local PHASE_DARK = Intermission.PHASE.DARK
local PHASE_DONE = Intermission.PHASE.DONE

--[[ The THREE color states (no API read in game).

     key            : short key used everywhere (3V1R / 2V2R / 1V3R)
     display        : locale key of the visual label ("3 GREEN + 1 RED" /
                      "3 VERTS + 1 ROUGE" in French)
     orbs / greens / reds : composition; greens and reds are the ONLY basis of
                      the survival rule (sum 4 green + 4 red = survival)
     numbers        : number(s) that can be displayed above the head
     numberAmbiguous: true when the number does NOT reveal the color
     dominant       : dominant color (the one used for the ping)
     position       : position code; positionLabel: displayed text
     ping           : Enum.PingSubjectType value (API source 12.1.0)
     pingToken      : token usable in a /ping macro (to be confirmed)
     pingColor / pingColorHex : ping color, VERIFIED on the wiki gallery
                      https://warcraft.wiki.gg/wiki/Ping_System :
                      Warning = red, OnMyWay = blue, Assist = green.
                      raidstrats guide convention, BY DOMINANT COLOR:
                      3 green -> Assist (green), 2-2 -> OnMyWay (blue),
                      3 red -> Warning (red).
     action         : operational instruction (what the player DOES)
     find           : which state can join it + the sum computation
     complement     : the state that MUST join it (4 green + 4 red)
     numberRule     : guild convention recalled for this number
     buttonLabel    : declaration button label (composition, number as a hint).
                      Computed HERE: the UI layer computes nothing.

     POSITIONS: the positional lines of the guide CONTRADICT each other (they
     give both "1 green 3 red -> left" and "3 red 1 green -> right"). Our
     convention is therefore EXPLICIT and CONFIGURABLE here: by default the
     FIXED point is the RED-majority state (1V3R, RED ping) and the RUNNER is
     the GREEN-majority state (3V1R, GREEN ping), the 2V2R going to the middle.
     It is the only convention consistent with "the color decides".
]]
--- The record fields that are DISPLAYED hold a LOCALE KEY, never a literal:
--- copyRecord() resolves them through Locale.t, so /gr lang applies immediately,
--- without a reload. Structural fields (key, greens, reds, numbers, position,
--- ping, pingToken, complement) are language-independent and stay literal.
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
        pingToken = "Warning",
        pingColor = "state.pingColor.1V3R",
        pingColorHex = "|cffff4040",
        action = "state.action.1V3R",
        find = "state.find.1V3R",
        complement = "3V1R",
        numberRule = "state.numberRule.1V3R",
        buttonLabel = "state.buttonLabel.1V3R",
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
        pingToken = "OnMyWay",
        pingColor = "state.pingColor.2V2R",
        pingColorHex = "|cff40a0ff",
        action = "state.action.2V2R",
        find = "state.find.2V2R",
        complement = "2V2R",
        numberRule = "state.numberRule.2V2R",
        buttonLabel = "state.buttonLabel.2V2R",
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
        pingToken = "Assist",
        pingColor = "state.pingColor.3V1R",
        pingColorHex = "|cff40ff40",
        action = "state.action.3V1R",
        find = "state.find.3V1R",
        complement = "1V3R",
        numberRule = "state.numberRule.3V1R",
        buttonLabel = "state.buttonLabel.3V1R",
    },
}

-- The table is exposed read-only (UI: colors, labels) but never returned
-- directly: getDeclaration() returns a copy.
Intermission.CONVENTION = CONVENTION

--- Green-count -> canonical state mapping (no state with 0 or 4 green).
local GREENS_TO_STATE = { [1] = "1V3R", [2] = "2V2R", [3] = "3V1R" }

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

local function copyRecord(rec)
    local numbers = {}
    for index = 1, #rec.numbers do
        numbers[#numbers + 1] = rec.numbers[index]
    end
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
        ping = rec.ping,
        pingToken = rec.pingToken,
        pingColor = Locale.t(rec.pingColor),
        pingColorHex = rec.pingColorHex,
        action = Locale.t(rec.action),
        find = Locale.t(rec.find),
        complement = rec.complement,
        numberRule = Locale.t(rec.numberRule),
        buttonLabel = Locale.t(rec.buttonLabel),
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
function Intermission.getDeclaration(raw)
    local key, err, info = Intermission.normalizeDeclaration(raw)
    if key == nil then
        return nil, err, info
    end
    return copyRecord(CONVENTION[key])
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

--- Generates the macro text to paste (the player triggers it: a macro is secure
--- code, the only way to call the #protected API).
--- @return table|nil { primary, fallback, ping, target, note }, string|nil error
function Intermission.buildMacro(raw, targetToken)
    local rec, err = Intermission.getDeclaration(raw)
    if rec == nil then
        return nil, err
    end
    local target = targetToken
    if type(target) ~= "string" or target == "" then
        target = Intermission.DEFAULT_TARGET_TOKEN
    end
    return {
        primary = "/run C_Ping.SendMacroPing({type = Enum.PingSubjectType." .. rec.ping .. ', targetToken = "' .. target .. '"})',
        fallback = "/ping " .. rec.pingToken,
        ping = rec.ping,
        target = target,
        note = Locale.t("macro.note"),
    }
end

--- Validates a timeline prepared out of game (SavedVariables).
--- @return table|nil { name, visibilitySeconds, durationSeconds }, string|nil error
function Intermission.validateTimeline(entry)
    if entry == nil then
        return {
            name = "Intermission",
            visibilitySeconds = Intermission.VISIBILITY_SECONDS,
            durationSeconds = Intermission.DEFAULT_DURATION_SECONDS,
        }
    end
    if type(entry) ~= "table" then
        return nil, Locale.t("err.invalidTimeline")
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
    return { name = name, visibilitySeconds = visibility, durationSeconds = duration }
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

--- Starts the intermission (trigger: ENCOUNTER_START or a player action).
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
    state.phase = PHASE_VISIBLE
    state.elapsed = 0
    state.declaration = nil
    return state
end

--- Advances the intermission clock. dt is provided by the wiring layer:
--- this module never calls GetTime (forbidden in Core/, see CONVENTIONS 7).
function Intermission.tick(state, dt)
    if type(state) ~= "table" then
        return state
    end
    if state.phase ~= PHASE_VISIBLE and state.phase ~= PHASE_DARK then
        return state
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return state
    end
    state.elapsed = state.elapsed + step
    local timeline = state.timeline
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

--- Displayable state, fully computed here: the UI layer only renders.
function Intermission.snapshot(state)
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
        showButtons = phase == PHASE_VISIBLE or phase == PHASE_DARK,
        declaration = declaration,
        countdownText = "0",
        headline = "",
        lines = {},
        macroPrimary = nil,
        macroFallback = nil,
        macroNote = nil,
        caveat = Locale.t("inter.caveat"),
        prompt = Locale.t("inter.prompt"),
        ambiguity = Locale.t("inter.ambiguity"),
    }

    local lines = snap.lines
    if phase == PHASE_IDLE then
        snap.headline = Locale.t("inter.headline.idle")
        lines[#lines + 1] = Locale.format("inter.line.idleTimeline", timeline.visibilitySeconds)
        lines[#lines + 1] = Locale.t("inter.line.idleTrigger")
        lines[#lines + 1] = Locale.t("inter.prompt")
        lines[#lines + 1] = Locale.t("inter.ambiguity")
        return snap
    end

    if phase == PHASE_VISIBLE then
        local left = Intermission.remainingVisibility({ timeline = timeline, elapsed = elapsed })
        snap.countdownText = tostring(left)
        snap.headline = Locale.format("inter.headline.visible", left)
        if declaration == nil then
            lines[#lines + 1] = Locale.t("inter.line.visibleIndicators")
            lines[#lines + 1] = Locale.t("inter.prompt")
        end
    elseif phase == PHASE_DARK then
        snap.headline = Locale.t("inter.headline.dark")
        if declaration == nil then
            lines[#lines + 1] = Locale.t("inter.line.darkIndicators")
            lines[#lines + 1] = Locale.t("inter.prompt")
        end
    else
        snap.headline = Locale.t("inter.headline.done")
    end

    local rec = declaration and CONVENTION[declaration] or nil
    if rec ~= nil then
        -- copyRecord resolves the locale keys: only the copy is displayed.
        local shown = copyRecord(rec)
        snap.instruction = shown
        lines[#lines + 1] = Locale.format("inter.line.youSee", shown.display, shown.key)
        local numberSuffix = shown.numberAmbiguous and Locale.t("inter.suffix.ambiguous") or Locale.t("inter.suffix.unambiguous")
        lines[#lines + 1] = Locale.format("inter.line.number", shown.numberText, numberSuffix)
        lines[#lines + 1] = Locale.format("inter.line.action", shown.action)
        lines[#lines + 1] = Locale.format("inter.line.position", shown.positionLabel)
        lines[#lines + 1] = Locale.format("inter.line.join", shown.complement, shown.find)
        lines[#lines + 1] = Locale.format("inter.line.ping", shown.pingColor, shown.ping)
        lines[#lines + 1] = Locale.format("inter.line.guildRule", shown.numberRule)
        local macro = Intermission.buildMacro(shown.key, nil)
        if macro ~= nil then
            snap.macroPrimary = macro.primary
            snap.macroFallback = macro.fallback
            snap.macroNote = macro.note
        end
    end
    lines[#lines + 1] = Locale.t("inter.ambiguity")
    lines[#lines + 1] = Locale.t("inter.caveat")
    lines[#lines + 1] = Locale.t("inter.channel")
    return snap
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
--- @param assignment table block validated by Pairing.validateAssignment
--- @param playerName string name of the current player (string provided by the wiring)
--- @return table|nil plan, string|nil error
function Intermission.buildPlan(assignment, playerName)
    if type(assignment) ~= "table" or type(assignment.pairs) ~= "table" then
        return nil, Locale.t("err.invalidAssignment")
    end
    if type(playerName) ~= "string" or playerName == "" then
        return nil, Locale.t("err.invalidPlayerName")
    end

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
    lines[#lines + 1] = Locale.t("plan.disclaimer")
    return out
end
