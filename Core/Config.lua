--[[--------------------------------------------------------------------------
    GideonRaid / Core / Config.lua
    Valeurs par defaut + initialisation des SavedVariables. Pas de logique metier.
----------------------------------------------------------------------------]]
local _, ns = ...

local Config = {}
ns.Config = Config

Config.DEFAULTS = {
    enabled = true,
    autoShow = true,
    scale = 1.0,
    lockPanel = true,
    -- Bloc publie par GIDEON hors jeu (voir docs/TESTPLAN.md, etape 4).
    assignment = nil,
}

--- Cree la table SavedVariables avec les valeurs par defaut (appel non destructif).
function Config.ensureDB(db)
    db = db or {}
    for k, v in pairs(Config.DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end
    return db
end

--- Retourne (assignment, err). Valide le bloc avant usage.
function Config.getAssignment()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil, "GideonRaidDB absent"
    end
    return ns.Pairing.validateAssignment(db.assignment)
end
