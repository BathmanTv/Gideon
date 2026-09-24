--[[--------------------------------------------------------------------------
    GideonRaid / Core / Simulation.lua

    "SIMULATION MODE" - PURE LOGIC (Lua 5.1). This file touches NO WoW API,
    registers no event, reads no unit value, contains no combat log token and
    calls no clock: it runs as-is under busted and under lua5.1 outside the
    client.

    WHY: the raid lead must be able to REHEARSE ALONE, with no boss and no raid.
    Two entries, both reachable from the main panel and from the chat:

      1. "INTERMISSION GROUP" (`/gr sim inter`) - `newRun` / `closeRun`: the
         intermission panel opens RIGHT AWAY (fourth in-game test: the former 3 s
         delay is gone) and NOTHING closes it by itself: the PLAYER closes it
         (close cross or Close button). One single rehearsal, no automatic
         relaunch. While it runs, the panel shows the SIMULATION banner and a
         rehearsal headline instead of the combat countdown, because there is no
         orb to read and no clock (see `forRehearsal`).
      2. "PING HELP" (`/gr sim ping`) - `pingHelpView`: a SHORT information
         window that says HOW to bind the ping keys and WHAT to do during the
         boss ("when the panel says PING: YES, ping YOURSELF"). The former guided
         sequence (countdown, three announced pings, "ping placed" button) is
         GONE: measured in game by the raid lead, the ping cannot be detected nor
         triggered by an addon, so there was nothing to sequence.

    HONESTY RULES (docs/CONVENTIONS.md section 10):
      - the addon can NOT detect a ping: no API reports one. Nothing here ever
        claims a ping was placed;
      - pings are only visible on screen while the player is in a group or a
        raid: both texts say so explicitly;
      - a simulation NEVER arms, disarms or advances the pre-computed timeline
        (Intermission module): the wiring keeps the two machines apart, and a
        rehearsal never publishes a decision into the SavedVariables (the
        diagnostic kit must not read a rehearsal as a real choice).

    BOUNDED INPUTS, REFUSED UNKNOWNS (explicit, never guessed):
      - an unknown sub-command is REFUSED with a message;
      - the rehearsal has NO option any more: a trailing token (the former
        `cycles=N`) is REFUSED with an explicit message, never silently ignored.
----------------------------------------------------------------------------]]
--
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: the language layer is
--- a hard dependency (every displayed string goes through it).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Simulation.lua")

--- Core/Intermission.lua is loaded BEFORE this file by the .toc: the simulation
--- reuses the canonical states, the ping labels and the ping binding candidates
--- (no duplicated table: they cannot drift).
local Intermission = assert(ns.Intermission, "Core/Intermission.lua must be loaded before Core/Simulation.lua")

---@class Simulation
local Simulation = {}
ns.Simulation = Simulation

--- Simulation model version. 1 = two guided sequences. 2 = the ping test trained
--- the SELF-PING gesture and the rehearsal defaulted to ONE cycle. 3 = the ping
--- test is a plain HELP WINDOW (no sequence at all) and the rehearsal opens
--- immediately and is closed BY THE PLAYER (no delay, no automatic close).
Simulation.SCHEMA_VERSION = 3

--- The THREE native pings, in EXPLICIT order. The canonical identifiers are
--- English ("Warning" / "OnMyWay" / "Assist"); the label the player reads is
--- translated (Avertissement / En route / Aide). The ping help window lists them
--- with the key the player bound, when one is known.
Simulation.PING_SEQUENCE = { "Warning", "OnMyWay", "Assist" }

--- Phases of the intermission rehearsal.
---   OPEN : the panel is on screen and stays there until the player closes it;
---   DONE : the player closed it (or `/gr sim stop`).
Simulation.RUN_PHASE = { OPEN = "OPEN", DONE = "DONE" }

--- Accepted sub-commands of /gr sim (and their aliases). An unknown value is
--- REFUSED by resolveCommand (nil), never guessed.
Simulation.COMMANDS = { inter = "inter", group = "inter", groupe = "inter", ping = "ping", stop = "stop" }

local PHASE_OPEN = Simulation.RUN_PHASE.OPEN
local PHASE_DONE = Simulation.RUN_PHASE.DONE

--- Pure resolution of a /gr sim sub-command: "inter" (aliases group, groupe),
--- "ping", "stop". Anything else (unknown word, empty string, number, table)
--- returns nil: the caller refuses it, nothing is guessed.
--- @param raw string|nil
--- @return string|nil "inter" | "ping" | "stop"
function Simulation.resolveCommand(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local wanted = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if wanted == "" then
        return nil
    end
    return Simulation.COMMANDS[wanted]
end

--- Parses the WHOLE argument of /gr sim: the sub-command ALONE.
--- The rehearsal takes no option any more (it opens right away and the player
--- closes it), so a trailing token is REFUSED with an explicit message: a
--- hand-typed `cycles=3` must never look accepted.
--- @param raw string|nil
--- @return string|nil mode, table|nil options, string|nil error
function Simulation.parseCommand(raw)
    if type(raw) ~= "string" then
        return nil, nil, nil
    end
    local trimmed = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then
        return nil, nil, nil
    end
    local word, rest = trimmed:match("^(%S+)%s*(.*)$")
    local mode = Simulation.resolveCommand(word)
    if mode == nil then
        -- Unknown sub-command: no error here, the caller shows the help.
        return nil, nil, nil
    end
    if rest ~= nil and rest ~= "" then
        return nil, nil, Locale.t("err.simNoOption")
    end
    return mode, {}, nil
end

--- The canonical state that carries a given ping ("Warning" -> "1V3R",
--- "OnMyWay" -> "2V2R", "Assist" -> "3V1R"), or nil when the ping is unknown.
--- The scan follows Intermission.STATES in its deterministic order (no pairs()).
--- @param ping string|nil
--- @return string|nil state key
function Simulation.stateKeyForPing(ping)
    if type(ping) ~= "string" or ping == "" then
        return nil
    end
    for index = 1, #Intermission.STATES do
        local key = Intermission.STATES[index]
        local rec = Intermission.CONVENTION[key]
        if rec ~= nil and rec.ping == ping then
            return key
        end
    end
    return nil
end

--- Localized list of the ping sequence ("Warning -> On My Way -> Assist", or
--- "Avertissement -> En route -> Aide" in French): built HERE, displayed by the
--- wiring, so the order never drifts between the chat and the window.
--- @return string
function Simulation.pingSequenceLine()
    local parts = {}
    for index = 1, #Simulation.PING_SEQUENCE do
        parts[#parts + 1] = Intermission.pingLabel(Simulation.PING_SEQUENCE[index])
    end
    return table.concat(parts, " -> ")
end

--- ---------------------------------------------------------------------------
--- 1. INTERMISSION REHEARSAL ("Groupe inter")
--- ---------------------------------------------------------------------------

--- Creates a rehearsal run. There is NO option any more: the panel opens right
--- away and the PLAYER closes it (fourth in-game test). A non-table argument, or
--- a table carrying any option, is REFUSED explicitly.
--- @return table|nil run, string|nil error
function Simulation.newRun(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    if type(options) == "table" and next(options) ~= nil then
        return nil, Locale.t("err.simNoOption")
    end
    return {
        phase = PHASE_OPEN,
        closed = false,
    }
end

--- Is the rehearsal over (closed by the player, or stopped by /gr sim stop)?
function Simulation.runFinished(run)
    return type(run) == "table" and run.phase == PHASE_DONE
end

--- The PLAYER closes the rehearsal: the close cross, the Close button or
--- `/gr sim stop`. The only way a rehearsal ends: nothing times it out.
--- Idempotent (a second close changes nothing and is not an error).
--- @return table|nil run, string|nil error
function Simulation.closeRun(run)
    if type(run) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    if run.phase ~= PHASE_DONE then
        run.phase = PHASE_DONE
        run.closed = true
    end
    return run
end

--- Displayable state of the rehearsal, fully computed here (the UI only renders).
--- @param run table|nil
--- @return table|nil snapshot, string|nil error
function Simulation.snapshot(run)
    if type(run) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    return {
        phase = run.phase,
        open = run.phase == PHASE_OPEN,
        closed = run.closed == true,
        done = run.phase == PHASE_DONE,
        -- Two lines: the banner itself (never a doubt about what is on screen)
        -- and the fact that the player is the one who closes the panel.
        bannerLines = { Locale.t("sim.banner"), Locale.t("sim.singleLine") },
        headline = Locale.t("sim.rehearsal.headline"),
        note = Locale.t("sim.rehearsal.note"),
    }
end

--- Turns an INTERMISSION snapshot into the REHEARSAL view: the combat headline
--- (which counts the seconds left to read the orbs) is replaced by the rehearsal
--- line and an explanatory note is appended, so the panel never shows a
--- countdown that contradicts what the player sees (no boss, no orb).
--- PURE: the input snapshot is not modified (explicit copy, no pairs(): the
--- field list is deterministic), and nothing is published anywhere.
--- @param snap table|nil snapshot of ns.Intermission.snapshot
--- @param run table|nil rehearsal run
--- @return table|nil the rehearsal view (the input one when there is no run)
function Simulation.forRehearsal(snap, run)
    if type(snap) ~= "table" or type(run) ~= "table" then
        return snap
    end
    local view = Simulation.snapshot(run)
    if view == nil then
        return snap
    end
    local out = {
        phase = snap.phase,
        visible = snap.visible,
        autoClose = snap.autoClose,
        showButtons = snap.showButtons,
        showRedo = snap.showRedo,
        declaration = snap.declaration,
        stateText = snap.stateText,
        stateLong = snap.stateLong,
        -- THE ONE WORD of the panel and the state that sizes/colors it: copied
        -- like every other displayed field, so a rehearsal shows the very same
        -- word as the real flow ("Ping" / "BOSS" / "Chasseur").
        word = snap.word,
        wordKey = snap.wordKey,
        headline = view.headline,
        countdownText = snap.countdownText,
        lines = {},
        prompt = snap.prompt,
        role = snap.role,
        roleName = snap.roleName,
        roleLine = snap.roleLine,
        shouldPing = snap.shouldPing,
        pingDecision = snap.pingDecision,
        pingBanner = snap.pingBanner,
        pingColorHex = snap.pingColorHex,
        pingHint = snap.pingHint,
        actionLine = snap.actionLine,
        pingPolicy = snap.pingPolicy,
        policyLine = snap.policyLine,
        simBannerLines = view.bannerLines,
        rehearsal = true,
    }
    local lines = snap.lines or {}
    for index = 1, #lines do
        out.lines[#out.lines + 1] = lines[index]
    end
    out.lines[#out.lines + 1] = view.note
    return out
end

--- ---------------------------------------------------------------------------
--- 2. PING HELP (information window: no sequence, no detection)
--- ---------------------------------------------------------------------------

--- The whole content of the ping help window, fully computed here.
--- The key of each ping is INJECTED (Core/ never calls GetBindingKey): when no
--- key is known the window says so instead of showing a shortcut that does not
--- exist.
--- @param bindingResolver function|nil function(bindNames) -> key|nil
--- @return table { title, headline, lines, keyLines, closeLabel }
function Simulation.pingHelpView(bindingResolver)
    local lines = {
        Locale.format("sim.ping.helpBind", Simulation.pingSequenceLine()),
        Locale.t("sim.ping.helpGesture"),
        Locale.t("sim.ping.anchorNote"),
        Locale.t("sim.ping.group"),
        Locale.t("sim.ping.noDetection"),
    }
    local keyLines = {}
    for index = 1, #Simulation.PING_SEQUENCE do
        local ping = Simulation.PING_SEQUENCE[index]
        local stateKey = Simulation.stateKeyForPing(ping)
        local bindNames = stateKey ~= nil and Intermission.bindNames(stateKey) or nil
        local key = nil
        if type(bindingResolver) == "function" then
            local ok, resolved = pcall(bindingResolver, bindNames)
            if ok and type(resolved) == "string" and resolved ~= "" then
                key = resolved
            end
        end
        local label = Intermission.pingLabel(ping)
        if key ~= nil then
            keyLines[#keyLines + 1] = Locale.format("sim.ping.keyLine", label, key)
        else
            keyLines[#keyLines + 1] = Locale.format("sim.ping.noKeyLine", label)
        end
    end
    return {
        title = Locale.t("sim.ping.title"),
        headline = Locale.t("sim.ping.helpHeadline"),
        lines = lines,
        keyLines = keyLines,
        closeLabel = Locale.t("ui.close"),
    }
end

return Simulation
