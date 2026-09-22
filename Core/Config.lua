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

local Config = {}
ns.Config = Config

Config.MIN_SCALE = 0.5
Config.MAX_SCALE = 3.0

Config.DEFAULTS = {
    enabled = true,
    autoShow = true,
    scale = 1.0,
    lockPanel = true,
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
        visibilitySeconds = 3,
        durationSeconds = 20,
        macroTargetToken = "player",
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    }
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
function Config.ensureDB(db)
    db = db or {}
    for k, v in pairs(Config.DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
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
    if type(raw.macroTargetToken) == "string" and raw.macroTargetToken ~= "" then
        out.macroTargetToken = raw.macroTargetToken
    end

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
