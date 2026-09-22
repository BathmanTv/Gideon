--[[--------------------------------------------------------------------------
    GideonRaid / Core / Simulation.lua

    "SIMULATION MODE" - PURE LOGIC (Lua 5.1). This file touches NO WoW API,
    registers no event, reads no unit value, contains no combat log token and
    calls no clock: it runs as-is under busted and under lua5.1 outside the
    client.

    WHY: the raid lead must be able to REHEARSE ALONE, with no boss and no raid.
    Two guided sequences, both advanced by an INJECTED time step (dt), exactly
    like Core/Intermission.tick:

      1. "INTERMISSION GROUP" (newRun / advance): the intermission panel opens by
         itself after a few seconds, the player clicks the composition they see,
         corrects it (REDO), the panel closes by itself and the cycle repeats
         DEFAULT_CYCLES times (1 by default; up to MAX_CYCLES with
         `/gr sim inter cycles=N`). No boss, no ENCOUNTER_START, no combat event.
      2. "PING TRAINING" (newPingTest / advancePingTest / confirmPingTest):
         the THREE native pings are announced one after the other
         (Warning -> OnMyWay -> Assist, EXPLICIT order). Measured in game by the
         raid lead: the ping lands WHERE THE MOUSE IS, so hovering YOUR OWN
         character frame pings YOURSELF - which is exactly the ANCHOR (1V3R)
         gesture. The frame therefore states the gesture step by step, with the
         key the player really bound (INJECTED resolver: Core/ never calls
         GetBindingKey, see docs/CONVENTIONS.md section 10.2bis) and a visible
         countdown.

    HONESTY RULES (docs/CONVENTIONS.md section 10):
      - the addon can NOT detect a ping: no API reports one. The ping test never
        claims a ping was placed; it says which ping was ANNOUNCED and how many
        steps the player validated themselves;
      - pings are only visible on screen while the player is in a group or a
        raid: the test says so explicitly;
      - a simulation NEVER arms, disarms or advances the pre-computed
        ENCOUNTER_START timeline (Intermission.newRun / advanceRun): the wiring
        keeps the two machines apart, and a simulation never publishes a decision
        into the SavedVariables (the diagnostic kit must not read a rehearsal as
        a real choice).

    BOUNDED INPUTS, REFUSED UNKNOWNS (explicit, never guessed):
      - an option that is not a number is REFUSED (never coerced);
      - a numeric option is CLAMPED to a documented bound (an endless or empty
        sequence is impossible);
      - an unknown ping, an empty ping sequence and an unknown sub-command are
        REFUSED with a message.
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

--- Simulation model version. 1 = two guided sequences (intermission rehearsal,
--- native ping test). 2 = the ping test trains the SELF-PING gesture (hover your
--- own character frame) and the rehearsal defaults to ONE cycle.
Simulation.SCHEMA_VERSION = 2

--- Default number of simulated intermissions. In-game feedback from the raid
--- lead: ONE cycle is enough to learn the gesture ("just keep it at 1 test
--- intermission"). A longer rehearsal stays possible with `/gr sim inter
--- cycles=N` (bounded to MIN_CYCLES..MAX_CYCLES).
Simulation.DEFAULT_CYCLES = 1
Simulation.MIN_CYCLES = 1
Simulation.MAX_CYCLES = 9

--- How many seconds after the command (and after each closing) the panel opens.
Simulation.DEFAULT_OPEN_DELAY_SECONDS = 3
Simulation.MAX_OPEN_DELAY_SECONDS = 30

--- Duration of a simulated intermission: the panel closes by itself at the end.
Simulation.DEFAULT_INTERMISSION_SECONDS = Intermission.DEFAULT_DURATION_SECONDS
Simulation.MAX_INTERMISSION_SECONDS = 120

--- Visibility window of a simulated intermission (the 3 s of the guide).
Simulation.MIN_VISIBILITY_SECONDS = 1
Simulation.MAX_VISIBILITY_SECONDS = 10

--- Ping test: time given to the player to press the key and validate one ping.
Simulation.DEFAULT_PING_STEP_SECONDS = 15
Simulation.MAX_PING_STEP_SECONDS = 120

--- Ping test: wait between two pings. The client accepts 3 pings in a row, then
--- about 5 s of wait (measured in game by the raid lead, 2026-09-22): the default
--- wait keeps the rehearsal under that limit.
Simulation.DEFAULT_PING_GAP_SECONDS = 5
Simulation.MAX_PING_GAP_SECONDS = 30

--- The THREE native pings, in EXPLICIT order (Warning -> OnMyWay -> Assist).
--- The canonical identifiers are English ("Warning" / "OnMyWay" / "Assist"); the
--- label the player reads is translated (Avertissement / En route / Aide).
Simulation.PING_SEQUENCE = { "Warning", "OnMyWay", "Assist" }

--- Phases of the intermission rehearsal.
---   WAIT : nothing on screen, the panel opens at the end of the delay;
---   OPEN : the panel is shown, the simulated intermission is running;
---   DONE : all the cycles are over.
Simulation.RUN_PHASE = { WAIT = "WAIT", OPEN = "OPEN", DONE = "DONE" }

--- Events returned by advance() (ONE transition per call, like advanceRun).
Simulation.EVENT = { OPEN = "open", CLOSE = "close" }

--- Phases of the ping test.
---   STEP : one ping is announced, waiting for the player's OK;
---   WAIT : countdown between two pings (client ping limit);
---   DONE : the sequence is over (or was left early).
Simulation.PING_PHASE = { STEP = "STEP", WAIT = "WAIT", DONE = "DONE" }

--- Accepted sub-commands of /gr sim (and their aliases). An unknown value is
--- REFUSED by resolveCommand (nil), never guessed.
Simulation.COMMANDS = { inter = "inter", group = "inter", groupe = "inter", ping = "ping", stop = "stop" }

local PHASE_WAIT = Simulation.RUN_PHASE.WAIT
local PHASE_OPEN = Simulation.RUN_PHASE.OPEN
local PHASE_DONE = Simulation.RUN_PHASE.DONE

local PING_STEP = Simulation.PING_PHASE.STEP
local PING_WAIT = Simulation.PING_PHASE.WAIT
local PING_DONE = Simulation.PING_PHASE.DONE

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

--- Bounded numeric option: a NUMBER is clamped to its documented bound, anything
--- else (string, boolean, table) is REFUSED with the name of the option. nil
--- means "not provided" and yields the default.
--- @return number|nil value, string|nil error
local function optionNumber(raw, default, min, max, name)
    if raw == nil then
        return default
    end
    if type(raw) ~= "number" then
        return nil, Locale.format("err.simulationOption", name)
    end
    return round(clampNumber(raw, min, max))
end

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

--- Parses the WHOLE argument of /gr sim: "<mode>" or "inter cycles=N".
--- Bounded and explicit, nothing is guessed:
---   - an unknown sub-command returns nil with NO error (the caller shows the
---     help, exactly like before);
---   - a trailing token that is not "%d+" after "cycles=" - or that is glued to a
---     sub-command that takes no option - is REFUSED with an explicit error;
---   - the value itself is CLAMPED by newRun (MIN_CYCLES..MAX_CYCLES), so a
---     hand-typed "cycles=999" can never build an endless rehearsal.
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
        return nil, nil, nil
    end
    local options = {}
    if rest == nil or rest == "" then
        return mode, options, nil
    end
    local cycles = mode == "inter" and rest:match("^cycles%s*=%s*(%d+)$") or nil
    if cycles == nil then
        return nil, nil, Locale.format("err.simulationOption", rest)
    end
    options.cycles = tonumber(cycles)
    return mode, options, nil
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

--- Localized list of the ping sequence ("Warning -> OnMyWay -> Assist", or
--- "Avertissement -> En route -> Aide" in French): built HERE, displayed by the
--- wiring, so the order never drifts between the chat and the panel.
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

--- Creates a rehearsal run. OPTIONAL options (all bounded, unknown types
--- refused):
---   cycles              number of simulated intermissions (1..9, default 1);
---   openDelaySeconds    delay before the panel opens (0..30, default 3);
---   visibilitySeconds   visibility window of a simulation (1..10);
---   durationSeconds     duration of a simulation (visibility+1..120, default 20).
--- @return table|nil run, string|nil error
function Simulation.newRun(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    local opts = options or {}
    local cycles, err = optionNumber(opts.cycles, Simulation.DEFAULT_CYCLES, Simulation.MIN_CYCLES, Simulation.MAX_CYCLES, "cycles")
    if cycles == nil then
        return nil, err
    end
    local openDelay
    openDelay, err =
        optionNumber(opts.openDelaySeconds, Simulation.DEFAULT_OPEN_DELAY_SECONDS, 0, Simulation.MAX_OPEN_DELAY_SECONDS, "openDelaySeconds")
    if openDelay == nil then
        return nil, err
    end
    local visibility
    visibility, err = optionNumber(
        opts.visibilitySeconds,
        Intermission.VISIBILITY_SECONDS,
        Simulation.MIN_VISIBILITY_SECONDS,
        Simulation.MAX_VISIBILITY_SECONDS,
        "visibilitySeconds"
    )
    if visibility == nil then
        return nil, err
    end
    local duration
    duration, err = optionNumber(
        opts.durationSeconds,
        Simulation.DEFAULT_INTERMISSION_SECONDS,
        visibility + 1,
        Simulation.MAX_INTERMISSION_SECONDS,
        "durationSeconds"
    )
    if duration == nil then
        return nil, err
    end
    return {
        cycles = cycles,
        openDelay = openDelay,
        visibility = visibility,
        duration = duration,
        index = 1,
        elapsed = 0,
        closed = 0,
        phase = PHASE_WAIT,
    }
end

--- Advances the rehearsal clock by dt and reports the transition of the cycle:
---   "open"  : the panel must be shown (the simulated intermission starts);
---   "close" : the panel must be hidden (the simulated intermission is over);
---   nil     : nothing to do.
--- INVARIANT: at most ONE transition per call (a huge dt never skips a cycle:
--- the next call reports it), exactly like Intermission.advanceRun.
--- @return table run, string|nil event
function Simulation.advance(run, dt)
    if type(run) ~= "table" then
        return run, nil
    end
    if run.phase == PHASE_DONE then
        return run, nil
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return run, nil
    end
    run.elapsed = (run.elapsed or 0) + step
    if run.phase == PHASE_WAIT then
        if run.elapsed >= run.openDelay then
            run.phase = PHASE_OPEN
            run.elapsed = 0
            return run, Simulation.EVENT.OPEN
        end
        return run, nil
    end
    if run.elapsed >= run.duration then
        run.closed = (run.closed or 0) + 1
        run.elapsed = 0
        if run.index >= run.cycles then
            run.phase = PHASE_DONE
        else
            run.index = run.index + 1
            run.phase = PHASE_WAIT
        end
        return run, Simulation.EVENT.CLOSE
    end
    return run, nil
end

--- Is the rehearsal over? (every cycle replayed)
function Simulation.runFinished(run)
    return type(run) == "table" and run.phase == PHASE_DONE
end

--- The timeline to give to the simulated intermission: NO lead time (the delay
--- before the opening is handled by the run itself), the configured visibility
--- and the duration of the cycle. Pure copy: the caller cannot corrupt the run.
--- @return table|nil { leadSeconds, visibilitySeconds, durationSeconds }
function Simulation.cycleTimeline(run)
    if type(run) ~= "table" then
        return nil
    end
    return {
        leadSeconds = 0,
        visibilitySeconds = run.visibility or Intermission.VISIBILITY_SECONDS,
        durationSeconds = run.duration or Simulation.DEFAULT_INTERMISSION_SECONDS,
    }
end

--- Displayable state of the rehearsal, fully computed here (the UI only renders).
--- @param run table|nil
--- @return table|nil snapshot, string|nil error
function Simulation.snapshot(run)
    if type(run) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    local snap = {
        phase = run.phase,
        cycle = run.index,
        cycles = run.cycles,
        closed = run.closed or 0,
        done = run.phase == PHASE_DONE,
        -- The banner is the guarantee that the player never mistakes a rehearsal
        -- for a real fight.
        banner = Locale.t("sim.banner"),
        cycleLine = Locale.format("sim.cycleLine", run.index, run.cycles),
        countdownText = "0",
        remaining = 0,
        headline = "",
    }
    local left
    if run.phase == PHASE_OPEN then
        left = run.duration - (run.elapsed or 0)
        if left < 0 then
            left = 0
        end
        snap.remaining = round(left)
        snap.countdownText = tostring(snap.remaining)
        snap.headline = Locale.format("sim.running", snap.remaining)
    elseif run.phase == PHASE_WAIT then
        left = run.openDelay - (run.elapsed or 0)
        if left < 0 then
            left = 0
        end
        snap.remaining = round(left)
        snap.countdownText = tostring(snap.remaining)
        snap.headline = Locale.format("sim.opens", snap.remaining)
    else
        snap.headline = Locale.t("sim.finished")
    end
    return snap
end

--- ---------------------------------------------------------------------------
--- 2. NATIVE PING TEST ("Test du ping en conditions reelles")
--- ---------------------------------------------------------------------------

--- Creates the guided ping sequence. OPTIONAL options:
---   sequence    ordered ping identifiers (default PING_SEQUENCE). An unknown
---               ping, an empty list or a non-table is REFUSED;
---   stepSeconds time to press the key and validate one ping (1..120, default 15);
---   gapSeconds  wait between two pings (0..30, default 5).
--- @return table|nil run, string|nil error
function Simulation.newPingTest(options)
    if options ~= nil and type(options) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    local opts = options or {}
    local stepSeconds, err =
        optionNumber(opts.stepSeconds, Simulation.DEFAULT_PING_STEP_SECONDS, 1, Simulation.MAX_PING_STEP_SECONDS, "stepSeconds")
    if stepSeconds == nil then
        return nil, err
    end
    local gapSeconds
    gapSeconds, err = optionNumber(opts.gapSeconds, Simulation.DEFAULT_PING_GAP_SECONDS, 0, Simulation.MAX_PING_GAP_SECONDS, "gapSeconds")
    if gapSeconds == nil then
        return nil, err
    end
    local raw = opts.sequence
    if raw == nil then
        raw = Simulation.PING_SEQUENCE
    end
    if type(raw) ~= "table" or #raw == 0 then
        return nil, Locale.t("err.pingSequenceEmpty")
    end
    local steps = {}
    for index = 1, #raw do
        local ping = raw[index]
        if Simulation.stateKeyForPing(ping) == nil then
            return nil, Locale.format("err.unknownPing", tostring(ping))
        end
        steps[#steps + 1] = ping
    end
    return {
        steps = steps,
        index = 1,
        elapsed = 0,
        confirmed = 0,
        cancelled = false,
        stepSeconds = stepSeconds,
        gapSeconds = gapSeconds,
        phase = PING_STEP,
    }
end

--- Is a ping still being announced (the sequence is running)?
function Simulation.pingTestActive(run)
    return type(run) == "table" and run.phase ~= PING_DONE
end

--- Number of pings in the sequence (0 outside a run).
function Simulation.pingTestTotal(run)
    if type(run) ~= "table" or type(run.steps) ~= "table" then
        return 0
    end
    return #run.steps
end

--- The ping announced right now (nil once the sequence is over).
function Simulation.currentPing(run)
    if type(run) ~= "table" or type(run.steps) ~= "table" then
        return nil
    end
    if run.phase == PING_DONE then
        return nil
    end
    return run.steps[run.index]
end

--- Has the player exceeded the time given to press the key? A step NEVER moves on
--- by itself: the addon cannot know whether a ping was placed, so it waits for
--- the player's OK (or for them to leave the test).
function Simulation.pingTestOverdue(run)
    if type(run) ~= "table" or run.phase ~= PING_STEP then
        return false
    end
    return (run.elapsed or 0) >= run.stepSeconds
end

--- Remaining seconds of the current step (or of the wait between two pings).
function Simulation.pingTestRemaining(run)
    if type(run) ~= "table" then
        return 0
    end
    local left
    if run.phase == PING_STEP then
        left = run.stepSeconds - (run.elapsed or 0)
    elseif run.phase == PING_WAIT then
        left = run.gapSeconds - (run.elapsed or 0)
    else
        return 0
    end
    if left < 0 then
        left = 0
    end
    return round(left)
end

--- Advances the ping test clock. ONLY the wait between two pings is timed: it
--- returns "next" when the next ping has to be announced. The step itself never
--- auto-advances (ONLY the player's OK moves the test forward).
--- @return table run, string|nil event
function Simulation.advancePingTest(run, dt)
    if type(run) ~= "table" then
        return run, nil
    end
    if run.phase ~= PING_STEP and run.phase ~= PING_WAIT then
        return run, nil
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return run, nil
    end
    run.elapsed = (run.elapsed or 0) + step
    if run.phase == PING_WAIT and run.elapsed >= run.gapSeconds then
        run.phase = PING_STEP
        run.elapsed = 0
        return run, "next"
    end
    return run, nil
end

--- The player validates a step ("my ping is placed"): the test moves to the next
--- ping after the countdown, or ends when the sequence is over. The addon claims
--- NOTHING about the ping itself: it only records that the step was validated.
--- @return table|nil run, string|nil error
function Simulation.confirmPingTest(run)
    if type(run) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    if run.phase ~= PING_STEP then
        return nil, Locale.t("err.nothingToConfirm")
    end
    run.confirmed = (run.confirmed or 0) + 1
    run.elapsed = 0
    if run.index >= Simulation.pingTestTotal(run) then
        run.phase = PING_DONE
    else
        run.index = run.index + 1
        run.phase = PING_WAIT
    end
    return run
end

--- Leaves the test at any time (the QUIT button, the close cross). Idempotent.
--- @return table|nil run
function Simulation.cancelPingTest(run)
    if type(run) ~= "table" then
        return nil
    end
    run.phase = PING_DONE
    run.elapsed = 0
    run.cancelled = true
    return run
end

--- Displayable state of the ping training, fully computed here.
--- The key to display is INJECTED (injected resolver, called under pcall by
--- Core/): when no key is known the frame says "your ping key" and asks for a
--- keybind, never an invented shortcut.
--- The BIG instruction is the ANCHOR gesture, step by step: the ping lands where
--- the MOUSE is, so hovering YOUR OWN character frame pings YOURSELF.
--- @param run table|nil
--- @param bindingResolver function|nil function(bindNames) -> key|nil
--- @return table|nil snapshot, string|nil error
function Simulation.pingTestSnapshot(run, bindingResolver)
    if type(run) ~= "table" then
        return nil, Locale.t("err.invalidSimulation")
    end
    local total = Simulation.pingTestTotal(run)
    local snap = {
        phase = run.phase,
        index = run.index,
        total = total,
        confirmed = run.confirmed or 0,
        cancelled = run.cancelled == true,
        done = run.phase == PING_DONE,
        overdue = false,
        banner = Locale.t("sim.banner"),
        stepLine = Locale.format("sim.ping.stepLine", run.index, total),
        headline = "",
        countdownText = "0",
        remaining = 0,
        ping = nil,
        label = nil,
        stateKey = nil,
        key = nil,
        bindNames = nil,
        lines = {},
        stepLabel = Locale.t("sim.ping.ok"),
        quitLabel = Locale.t("sim.ping.quit"),
        nativeReminder = Locale.t("sim.ping.native"),
        groupReminder = Locale.t("sim.ping.group"),
        noDetection = Locale.t("sim.ping.noDetection"),
        anchorNote = Locale.t("sim.ping.anchorNote"),
        yourKey = Locale.t("sim.ping.yourKey"),
    }
    if snap.done then
        snap.headline = Locale.t("sim.ping.finished")
        snap.lines[#snap.lines + 1] = Locale.format("sim.ping.finishedLine", snap.confirmed, total)
        return snap
    end
    local ping = Simulation.currentPing(run)
    snap.ping = ping
    snap.label = Intermission.pingLabel(ping)
    snap.stateKey = Simulation.stateKeyForPing(ping)
    if snap.stateKey ~= nil then
        local bindNames = Intermission.bindNames(snap.stateKey)
        snap.bindNames = bindNames
        local pressed = nil
        if type(bindingResolver) == "function" then
            local ok, resolved = pcall(bindingResolver, bindNames)
            if ok and type(resolved) == "string" and resolved ~= "" then
                pressed = resolved
            end
        end
        snap.key = pressed
    end
    snap.remaining = Simulation.pingTestRemaining(run)
    snap.countdownText = tostring(snap.remaining)
    if run.phase == PING_WAIT then
        snap.headline = Locale.format("sim.ping.ready", snap.label)
        snap.lines[#snap.lines + 1] = Locale.format("sim.ping.nextIn", snap.remaining)
    else
        snap.overdue = Simulation.pingTestOverdue(run)
        -- The ONE big instruction: hover YOUR OWN frame, then press the key.
        snap.headline = Locale.format("sim.ping.selfSteps", snap.key or snap.yourKey, snap.label)
        if snap.overdue then
            snap.lines[#snap.lines + 1] = Locale.t("sim.ping.overdue")
        else
            snap.lines[#snap.lines + 1] = Locale.format("sim.ping.countdown", snap.remaining)
        end
        if snap.key == nil then
            snap.lines[#snap.lines + 1] = Locale.t("sim.ping.noKey")
        end
        snap.lines[#snap.lines + 1] = snap.anchorNote
    end
    snap.lines[#snap.lines + 1] = snap.nativeReminder
    snap.lines[#snap.lines + 1] = snap.groupReminder
    snap.lines[#snap.lines + 1] = snap.noDetection
    return snap
end

return Simulation
