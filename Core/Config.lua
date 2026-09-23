--[[--------------------------------------------------------------------------
    GideonRaid / Core / Config.lua

    Default values + SavedVariables initialization + resolution of the
    "Intermission Coach" module configuration. No business logic.

    No WoW API here: this file reads only tables and numbers, and
    `resolveIntermission` receives the raw table as a PARAMETER (the wiring
    passes it GideonRaidDB.intermission).
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: the language layer is
--- a hard dependency (the persisted preference is normalized against it).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Config.lua")

--- Core/Sound.lua is loaded BEFORE this file by the .toc: it owns the pure table
--- "canonical state -> soundboard file", the one-playback-per-assignment gate
--- and the BOUNDED resolvers of the assignment-sound preference (/gr sound).
local Sound = assert(ns.Sound, "Core/Sound.lua must be loaded before Core/Config.lua")

local Config = {}
ns.Config = Config

Config.MIN_SCALE = 0.5
Config.MAX_SCALE = 3.0

--- PING POLICIES accepted by the module (persisted preference `pingMode`).
--- SORTED list, no pairs() anywhere (determinism):
---   "anchors" (DEFAULT, raid-lead decision): only the 1V3R ANCHORS ping, one
---      ping per anchor -> about 8 pings per raid instead of ~20. 3V1R CHASERS
---      and 2V2R MIDDLE players never ping;
---   "color": raidstrats guide variant, every state pings with its own color
---      (1V3R = red/Warning, 2V2R = blue/OnMyWay, 3V1R = green/Assist);
---   "none": nobody pings at all, the raid plays on positions only.
Config.PING_MODES = { "anchors", "color", "none" }

--- Default ping policy: the raid lead's decision ("anchors").
Config.DEFAULT_PING_MODE = "anchors"

--- Pre-computed intermission timeline, in SECONDS SINCE ENCOUNTER_START (the pull
--- is the time origin). Values measured on the real encounter by the raid lead:
--- the first intermission lands ~46 s after the pull, then every ~102.6 s.
--- Prepared by hand and persisted: GIDEON can overwrite it out of game.
--- https://warcraft.wiki.gg/wiki/ENCOUNTER_START (arguments never read).
Config.DEFAULT_SCHEDULE_SECONDS = { 46.3, 148.9, 251.5, 353.2 }

--- How many seconds BEFORE each intermission the panel opens by itself.
Config.DEFAULT_LEAD_SECONDS = 2

--- Maximum number of intermissions kept from a persisted schedule (a hand-edited
--- SavedVariables must never produce an unbounded loop).
Config.MAX_SCHEDULE_ENTRIES = 12

--- Anchor points accepted when reading a PERSISTED panel position. A hand-edited
--- SavedVariables holding an unknown point name would make the client raise on
--- SetPoint: the resolver only ever returns a value from this list.
Config.POSITION_POINTS = {
    "CENTER",
    "TOP",
    "BOTTOM",
    "LEFT",
    "RIGHT",
    "TOPLEFT",
    "TOPRIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
}

--- SavedVariables schema of the PANEL preferences (position + lock). Bumped when
--- a migration has to run once: see Config.ensureDB.
Config.PANEL_SCHEMA = 1

Config.DEFAULTS = {
    enabled = true,
    autoShow = true,
    scale = 1.0,
    -- The main panel is MOVABLE BY DEFAULT (in-game feedback: a panel the player
    -- cannot move is unusable). /gr lock freezes it, /gr unlock frees it again.
    -- Any other value than a boolean counts as "not locked".
    lockPanel = false,
    -- Language preference of the player: "auto" (follow the client), "en", "fr".
    locale = Locale.AUTO,
    -- Block published by GIDEON out of game (see docs/TESTPLAN.md, step 4).
    assignment = nil,
}

--- Default values of the "Intermission Coach" module.
--- This is a FUNCTION, not a constant: returning the same table shared between
--- two characters (or between two /reload) would create a SavedVariables alias,
--- hence a silent bug as soon as a player moves the panel.
--- The ns.Intermission module (loaded AFTER this file in the .toc) documents the
--- same duration: Core/Intermission.lua -> VISIBILITY_SECONDS = 3.
function Config.defaultIntermission()
    return {
        enabled = true,
        startOnEncounterStart = true,
        autoShowPanel = true,
        scale = 1.0,
        -- The panel opens `leadSeconds` BEFORE the intermission so the player
        -- reads the three choices before the orbs appear.
        leadSeconds = Config.DEFAULT_LEAD_SECONDS,
        visibilitySeconds = 3,
        durationSeconds = 20,
        -- Pre-computed intermission schedule, in seconds since ENCOUNTER_START.
        scheduleSeconds = Config.defaultScheduleSeconds(),
        -- Ping policy (see Config.PING_MODES): the raid-lead decision, persisted
        -- and changeable in game with /gr ping anchors|color|none.
        pingMode = Config.DEFAULT_PING_MODE,
        -- ASSIGNMENT SOUNDBOARD (see Core/Sound.lua): enabled by default, one
        -- sound per canonical state, played ONCE when the player declares their
        -- composition. /gr sound on|off, /gr sound test 1v3r|2v2r|3v1r.
        soundEnabled = Sound.DEFAULT_ENABLED,
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    }
end

--- Fresh copy of the default schedule (never a shared table: a caller mutating
--- the returned list must not corrupt the defaults of the next character).
function Config.defaultScheduleSeconds()
    local out = {}
    for index = 1, #Config.DEFAULT_SCHEDULE_SECONDS do
        out[index] = Config.DEFAULT_SCHEDULE_SECONDS[index]
    end
    return out
end

--- PURE normalization of a prepared schedule: keeps positive numbers only,
--- sorts them ASCENDING (deterministic, no pairs()) and caps the number of
--- entries. A missing/absurd value never raises and never yields an empty list
--- (fallback: the default schedule).
--- @param raw table|nil persisted schedule (seconds since ENCOUNTER_START)
--- @return table sorted copy of numbers
function Config.resolveSchedule(raw)
    local out = {}
    if type(raw) == "table" then
        for index = 1, #raw do
            local value = tonumber(raw[index])
            if value ~= nil and value > 0 then
                out[#out + 1] = value
            end
        end
    end
    if #out == 0 then
        return Config.defaultScheduleSeconds()
    end
    table.sort(out)
    while #out > Config.MAX_SCHEDULE_ENTRIES do
        table.remove(out)
    end
    return out
end

--- Fresh copy of the DEFAULT panel position (never a shared table: two characters
--- must not alias the same position). Used by the main panel, the intermission
--- panel and the ping-training frame.
--- @return table { point, relativePoint, x, y }
function Config.defaultPanelPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
end

--- PURE resolution of the persisted LOCK preference (GideonRaidDB.lockPanel).
--- true = the player froze the panels, false = they can be dragged. Anything else
--- - absent, string, number, table, hand-edited SavedVariables - means NOT
--- locked: the resolver is total, it never raises and never returns nil.
--- @param raw boolean|any
--- @return boolean
function Config.resolveLockPanel(raw)
    return raw == true
end

--- PURE normalization of a persisted panel position (point / relativePoint / x /
--- y). Only a KNOWN anchor point is kept (an unknown name would make the client
--- raise on SetPoint), the coordinates must be numbers: anything else falls back
--- to the centered default. Total: never raises, never returns nil.
--- @param raw table|nil raw position block
--- @return table { point, relativePoint, x, y }
function Config.resolvePosition(raw)
    local out = Config.defaultPanelPosition()
    if type(raw) ~= "table" then
        return out
    end
    local wanted = type(raw.point) == "string" and raw.point:upper() or nil
    for index = 1, #Config.POSITION_POINTS do
        if wanted == Config.POSITION_POINTS[index] then
            out.point = wanted
            break
        end
    end
    local relative = type(raw.relativePoint) == "string" and raw.relativePoint:upper() or nil
    for index = 1, #Config.POSITION_POINTS do
        if relative == Config.POSITION_POINTS[index] then
            out.relativePoint = relative
            break
        end
    end
    if type(raw.x) == "number" then
        out.x = raw.x
    end
    if type(raw.y) == "number" then
        out.y = raw.y
    end
    return out
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

--- Creates the SavedVariables table with the default values (non-destructive call).
--- Also runs the ONE-TIME soft migration of the panel preferences:
---   - a SavedVariables written by an older version carries `lockPanel = true`
---     (the old hard-coded default, which no player could change: no command
---     existed then), and no `panelSchema` marker. It is unlocked ONCE, then the
---     player's own choice (/gr lock, /gr unlock, the panel button) is preserved;
---   - a value that is not a boolean never raises: it counts as "not locked".
--- The panel positions are created fresh (never aliased between characters).
function Config.ensureDB(db)
    db = db or {}
    for k, v in pairs(Config.DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end
    if db.panelSchema ~= Config.PANEL_SCHEMA then
        db.lockPanel = false
        db.panelSchema = Config.PANEL_SCHEMA
    else
        db.lockPanel = Config.resolveLockPanel(db.lockPanel)
    end
    if type(db.panelPosition) ~= "table" then
        db.panelPosition = Config.defaultPanelPosition()
    end
    if type(db.pingPanelPosition) ~= "table" then
        db.pingPanelPosition = Config.defaultPanelPosition()
    end
    if type(db.intermission) ~= "table" then
        db.intermission = Config.defaultIntermission()
    end
    return db
end

--- Resolves the persisted language preference (GideonRaidDB.locale).
--- Accepted values: "auto" (default), "en", "fr". Anything else - absent,
--- mistyped, hand-edited SavedVariables - falls back to "auto".
--- Pure: no API, no clock.
--- @param raw string|nil raw GideonRaidDB.locale value
--- @return string "auto", "en" or "fr"
function Config.resolveLocale(raw)
    local wanted = (type(raw) == "string") and raw:lower() or ""
    for index = 1, #Locale.PREFERENCES do
        local candidate = Locale.PREFERENCES[index]
        if wanted == candidate then
            return candidate
        end
    end
    return Locale.AUTO
end

--- Resolves the PERSISTED PING POLICY (GideonRaidDB.intermission.pingMode).
--- Accepted values: "anchors" (default), "color", "none". Anything else -
--- absent, mistyped, hand-edited SavedVariables, a number, a table - falls back
--- to "anchors": the resolver is PURE and TOTAL, it never raises and never
--- returns nil. The comparison is case-insensitive.
--- @param raw string|nil raw GideonRaidDB.intermission.pingMode value
--- @return string "anchors", "color" or "none"
function Config.resolvePingMode(raw)
    local wanted = (type(raw) == "string") and raw:lower() or ""
    for index = 1, #Config.PING_MODES do
        local candidate = Config.PING_MODES[index]
        if wanted == candidate then
            return candidate
        end
    end
    return Config.DEFAULT_PING_MODE
end

--- Returns (assignment, err). Validates the block before use.
function Config.getAssignment()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil, "GideonRaidDB absent"
    end
    return ns.Pairing.validateAssignment(db.assignment)
end

--- Publishes the player's LAST decision (click on a composition button) into the
--- SavedVariables. This is THE FIELD the diagnostic kit (GideonDiagAddon) reads
--- to timestamp the choice WITHOUT any chat input: we publish data, we send NO
--- message (no inter-addon communication, which is forbidden in instances).
---
--- Published shape: db.intermission.lastDecision =
---   { composition = "3V1R", at = <client epoch>, clock = "YYYY-MM-DD HH:MM:SS",
---     source = "coach-panel" }
--- The timestamp comes from the UI layer (it alone may call time()).
--- @param db table SavedVariables
--- @param record table { composition, at, clock, source }
--- @return table|nil published entry (nil if the composition is refused)
function Config.recordDecision(db, record)
    if type(db) ~= "table" or type(record) ~= "table" then
        return nil
    end
    local key = ns.Intermission.normalizeDeclaration(record.composition)
    if key == nil then
        return nil
    end
    if type(db.intermission) ~= "table" then
        db.intermission = Config.defaultIntermission()
    end
    local entry = {
        composition = key,
        at = tonumber(record.at),
        clock = record.clock,
        source = tostring(record.source or "coach-panel"),
    }
    db.intermission.lastDecision = entry
    return entry
end

--- PURE resolution of the module configuration: clamps, filters inconsistent
--- types, never keeps a value that cannot be rendered.
--- @param raw table|nil raw content of GideonRaidDB.intermission
--- @return table usable configuration
function Config.resolveIntermission(raw)
    local out = Config.defaultIntermission()
    if type(raw) ~= "table" then
        return out
    end

    if type(raw.enabled) == "boolean" then
        out.enabled = raw.enabled
    end
    if type(raw.startOnEncounterStart) == "boolean" then
        out.startOnEncounterStart = raw.startOnEncounterStart
    end
    if type(raw.autoShowPanel) == "boolean" then
        out.autoShowPanel = raw.autoShowPanel
    end
    if type(raw.scale) == "number" then
        out.scale = clampNumber(raw.scale, Config.MIN_SCALE, Config.MAX_SCALE)
    end
    if type(raw.visibilitySeconds) == "number" then
        out.visibilitySeconds = math.floor(clampNumber(raw.visibilitySeconds, 1, 10) + 0.5)
    end
    if type(raw.durationSeconds) == "number" then
        out.durationSeconds = math.floor(clampNumber(raw.durationSeconds, out.visibilitySeconds + 1, 120) + 0.5)
    end
    -- Lead time (the panel opens BEFORE the intermission): bounded, an absurd
    -- value falls back to the default instead of showing the panel way too early.
    if type(raw.leadSeconds) == "number" then
        out.leadSeconds = math.floor(clampNumber(raw.leadSeconds, 0, 10) + 0.5)
    end
    out.scheduleSeconds = Config.resolveSchedule(raw.scheduleSeconds)
    -- Ping policy: pure and bounded resolution, an unknown value falls back to
    -- "anchors" (never an error, never nil).
    out.pingMode = Config.resolvePingMode(raw.pingMode)
    -- Assignment soundboard: TOTAL resolution (only an exact `false` mutes the
    -- sound, everything else - an older SavedVariables without the field, a
    -- hand-edited value - falls back to the default: ENABLED). The soft
    -- migration of the existing saves is exactly this: a missing field means
    -- "enabled", no schema bump is needed.
    out.soundEnabled = Sound.resolveEnabled(raw.soundEnabled)

    local pos = raw.position
    if type(pos) == "table" then
        if type(pos.point) == "string" and pos.point ~= "" then
            out.position.point = pos.point
        end
        if type(pos.relativePoint) == "string" and pos.relativePoint ~= "" then
            out.position.relativePoint = pos.relativePoint
        end
        if type(pos.x) == "number" then
            out.position.x = pos.x
        end
        if type(pos.y) == "number" then
            out.position.y = pos.y
        end
    end

    if out.durationSeconds <= out.visibilitySeconds then
        out.durationSeconds = out.visibilitySeconds + 1
    end
    return out
end
