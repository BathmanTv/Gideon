--[[--------------------------------------------------------------------------
    GideonRaid / Core / Config.lua

    Valeurs par defaut + initialisation des SavedVariables + resolution de la
    configuration du module « Intermission Coach ». Pas de logique metier.

    Aucune API WoW ici : ce fichier ne lit que des tables et des nombres, et
    `resolveIntermission` recoit la table brute en PARAMETRE (le cablage lui
    passe GideonRaidDB.intermission).
----------------------------------------------------------------------------]]
local _, ns = ...

local Config = {}
ns.Config = Config

Config.MIN_SCALE = 0.5
Config.MAX_SCALE = 3.0

Config.DEFAULTS = {
    enabled = true,
    autoShow = true,
    scale = 1.0,
    lockPanel = true,
    -- Bloc publie par GIDEON hors jeu (voir docs/TESTPLAN.md, etape 4).
    assignment = nil,
}

--- Valeurs par defaut du module « Intermission Coach ».
--- C'est une FONCTION, pas une constante : renvoyer la meme table partagee entre
--- deux personnages (ou entre deux /reload) creerait un alias de SavedVariables,
--- donc un bug silencieux des qu'un joueur bouge le panneau.
--- Le module ns.Intermission (charge APRES ce fichier dans le .toc) documente la
--- meme duree : Core/Intermission.lua -> VISIBILITY_SECONDS = 3.
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

--- Cree la table SavedVariables avec les valeurs par defaut (appel non destructif).
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

--- Retourne (assignment, err). Valide le bloc avant usage.
function Config.getAssignment()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil, "GideonRaidDB absent"
    end
    return ns.Pairing.validateAssignment(db.assignment)
end

--- Resolution PURE de la configuration du module : borne, filtre les types
--- incoherents, ne garde jamais une valeur impossible a rendre.
--- @param raw table|nil contenu brut de GideonRaidDB.intermission
--- @return table configuration exploitable
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
