--[[--------------------------------------------------------------------------
    tests/spec/guard_spec.lua   (busted)

    GARDE ANTI-API-INTERDITE. Elle lit le code REELLEMENT charge par le client
    (les fichiers listes dans le .toc) et fait echouer la suite si un token
    interdit par docs/CONVENTIONS.md y apparait ailleurs que dans un commentaire.

    Trois niveaux :
      1. tokens qui ne doivent apparaitre NULLE PART hors commentaire, meme dans
         une chaine : journal de combat, auras, GUID, chat, roster ;
      2. AUCUNE API DE PING, meme sous forme de texte : depuis le test en jeu reel
         la generation de macro a disparu (Blizzard refuse l'appel : « action
         utilisable uniquement par l'UI de Blizzard »), donc plus aucune raison
         qu'un `C_Ping` / `SendMacroPing` traine dans un fichier charge ;
      3. la LECTURE du raccourci de ping (GetBindingKey) est autorisee, mais
         UNIQUEMENT dans la couche de rendu et UNIQUEMENT sous pcall : Core/ reste
         pur (aucune API) et le client ne doit jamais pouvoir excepter sur une
         lecture de raccourci.
----------------------------------------------------------------------------]]
--
--
local wowenv = require("tests.support.wowenv")

--- Retire les commentaires (blocs puis lignes). Le code a le DROIT de citer une
--- API interdite pour dire qu'il ne s'en sert pas ; il n'a pas le droit d'y
--- toucher.
local function stripComments(source)
    source = source:gsub("%-%-%[%[.-%]%]", " ")
    source = source:gsub("%-%-[^\n]*", " ")
    return source
end

--- Retire les chaines de caracteres (double puis simple quotes).
local function stripStrings(source)
    source = source:gsub('"[^"]*"', " ")
    source = source:gsub("'[^']*'", " ")
    return source
end

local function readFile(path)
    local handle = assert(io.open(path, "r"))
    local content = handle:read("*a")
    handle:close()
    return content
end

--- Tokens interdits PARTOUT hors commentaire.
local NEVER_ANYWHERE = {
    "COMBAT_LOG_EVENT",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "CombatLogGetCurrentEventInfo",
    "UnitAura",
    "UnitBuff",
    "UnitDebuff",
    "UnitGUID",
    "SendChatMessage",
    "GetRaidRosterInfo",
    "C_VoiceChat",
}

--- Tokens interdits PARTOUT, chaines comprises : aucune trace d'API de ping ne
--- doit subsister dans un fichier charge par le client.
local NEVER_EVEN_IN_A_STRING = { "C_Ping", "SendMacroPing", "PingSubjectType" }

--- Lecture de raccourci : autorisee, mais encadree (voir le test dedie).
local BINDING_LOOKUP = "GetBindingKey"

describe("garde anti-API-interdite (fichiers charges par le client)", function()
    local files = wowenv.tocFiles()

    it("scanne reellement tous les fichiers du .toc", function()
        assert.are.equal(8, #files)
        for _, file in ipairs(files) do
            assert.is_truthy(readFile(file):len() > 0, file .. " est vide")
        end
    end)

    it("ne touche a AUCUNE API interdite hors commentaire", function()
        for _, file in ipairs(files) do
            local code = stripComments(readFile(file))
            for _, token in ipairs(NEVER_ANYWHERE) do
                assert.is_nil(code:find(token, 1, true), ("%s contient %s hors commentaire (interdit en 12.x)"):format(file, token))
            end
        end
    end)

    it("ne contient AUCUNE API de ping, meme sous forme de texte", function()
        for _, file in ipairs(files) do
            local code = stripComments(readFile(file))
            for _, token in ipairs(NEVER_EVEN_IN_A_STRING) do
                assert.is_nil(
                    code:find(token, 1, true),
                    ("%s contient %s : l'addon ne ping pas et ne fabrique plus de macro"):format(file, token)
                )
            end
        end
    end)

    it("garde Core/ sans horloge, sans hasard, sans API WoW et sans raccourci", function()
        -- Config.lua est l'ACCESSOR des SavedVariables (son job) : les controles
        -- ci-dessous portent sur l'horloge, le hasard et l'API WoW, pas sur la
        -- lecture de GideonRaidDB, verifiee separement pour les modules de CALCUL.
        local pureFiles = {
            "Core/Locale.lua",
            "Core/Config.lua",
            "Core/Pairing.lua",
            "Core/Intermission.lua",
            "Core/Simulation.lua",
        }
        for _, file in ipairs(pureFiles) do
            local code = stripComments(readFile(file))
            assert.is_nil(code:find("GetTime", 1, true), file .. " lit l'heure du client (interdit dans Core/)")
            assert.is_nil(code:find("math.random", 1, true), file .. " utilise math.random (non deterministe)")
            assert.is_nil(code:find("CreateFrame", 1, true), file .. " appelle l'API WoW (interdit dans Core/)")
            assert.is_nil(code:find("UnitName", 1, true), file .. " lit une unite (interdit dans Core/)")
            assert.is_nil(code:find(BINDING_LOOKUP, 1, true), file .. " lit un raccourci (reserve a la couche de rendu)")
        end
        for _, file in ipairs({ "Core/Pairing.lua", "Core/Intermission.lua", "Core/Simulation.lua" }) do
            local code = stripComments(readFile(file))
            assert.is_nil(code:find("GideonRaidDB", 1, true), file .. " lit les SavedVariables (interdit dans Core/)")
        end
    end)

    it("garde la SIMULATION isolee de la timeline ENCOUNTER_START", function()
        -- La simulation est une repetition : elle ne doit ni armer, ni desarmer,
        -- ni avancer la timeline pre-calculee (Core/Intermission.newRun /
        -- advanceRun / resetRun) et ne doit toucher aucun evenement de combat.
        local code = stripComments(readFile("Core/Simulation.lua"))
        for _, token in ipairs({ "ENCOUNTER_START", "Intermission.newRun", "advanceRun", "resetRun", "RegisterEvent" }) do
            assert.is_nil(code:find(token, 1, true), "Core/Simulation.lua reference " .. token .. " (la simulation doit etre isolee)")
        end
    end)

    it("lit le raccourci de ping UNIQUEMENT dans la couche de rendu et SOUS pcall", function()
        local found = false
        for _, file in ipairs(files) do
            local code = stripComments(readFile(file))
            if code:find(BINDING_LOOKUP, 1, true) ~= nil then
                found = true
                assert.is_truthy(file:match("^UI/") ~= nil, file .. " lit un raccourci hors de UI/")
                for line in code:gmatch("[^\n]+") do
                    if line:find(BINDING_LOOKUP, 1, true) ~= nil then
                        local guarded = line:find("pcall(", 1, true) ~= nil or line:find("type(", 1, true) ~= nil
                        assert.is_true(guarded, file .. " : lecture de raccourci NON protegee : " .. line)
                    end
                end
            end
        end
        assert.is_true(found, "la lecture du raccourci de ping a disparu de la couche de rendu")
    end)

    it("ne fabrique plus de macro et n'appelle aucune API de ping", function()
        assert.is_nil(
            stripComments(readFile("Core/Intermission.lua")):find("buildMacro", 1, true),
            "Core/ fabrique encore une macro de ping"
        )
        for _, file in ipairs(files) do
            local code = stripStrings(stripComments(readFile(file)))
            for _, token in ipairs({ "C_Ping", "SendMacroPing", "SendPing", "PingSubjectType" }) do
                assert.is_nil(code:find(token, 1, true), file .. " appelle " .. token .. " (le client refuse)")
            end
        end
    end)
end)
