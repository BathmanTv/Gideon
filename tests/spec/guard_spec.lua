--[[--------------------------------------------------------------------------
    tests/spec/guard_spec.lua   (busted)

    GARDE ANTI-API-INTERDITE. Elle lit le code REELLEMENT charge par le client
    (les fichiers listes dans le .toc) et fait echouer la suite si un token
    interdit par docs/CONVENTIONS.md y apparait ailleurs que dans un commentaire.

    Deux niveaux, parce que le module d'intermission doit LITTERALEMENT afficher
    le TEXTE d'une macro (chaine contenant C_Ping.SendMacroPing) :
      1. tokens qui ne doivent apparaitre NULLE PART hors commentaire, meme dans
         une chaine : journal de combat, auras, GUID, chat, roster ;
      2. C_Ping / SendMacroPing : interdits comme APPEL dans le code (les chaines
         sont retirees avant la recherche). C'est ce qui distingue « texte de
         macro a coller » (#protected respecte) d'un envoi de ping par l'addon.
----------------------------------------------------------------------------]]
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

--- Tokens interdits comme APPEL (chaine du texte de macro mise a part).
local NEVER_AS_CALL = { "C_Ping", "SendMacroPing" }

describe("garde anti-API-interdite (fichiers charges par le client)", function()
    local files = wowenv.tocFiles()

    it("scanne reellement tous les fichiers du .toc", function()
        assert.are.equal(6, #files)
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

    it("n'APPELLE jamais C_Ping : la macro est du texte, pas un appel", function()
        for _, file in ipairs(files) do
            local code = stripStrings(stripComments(readFile(file)))
            for _, token in ipairs(NEVER_AS_CALL) do
                assert.is_nil(code:find(token, 1, true), ("%s appelle %s (API #protected, cf. CONVENTIONS 10.2)"):format(file, token))
            end
        end
    end)

    it("garde Core/ sans horloge, sans hasard et sans API WoW", function()
        -- Config.lua est l'ACCESSOR des SavedVariables (son job) : les controles
        -- ci-dessous portent sur l'horloge, le hasard et l'API WoW, pas sur la
        -- lecture de GideonRaidDB, verifiee separement pour les modules de CALCUL.
        for _, file in ipairs({ "Core/Config.lua", "Core/Pairing.lua", "Core/Intermission.lua" }) do
            local code = stripComments(readFile(file))
            assert.is_nil(code:find("GetTime", 1, true), file .. " lit l'heure du client (interdit dans Core/)")
            assert.is_nil(code:find("math.random", 1, true), file .. " utilise math.random (non deterministe)")
            assert.is_nil(code:find("CreateFrame", 1, true), file .. " appelle l'API WoW (interdit dans Core/)")
            assert.is_nil(code:find("UnitName", 1, true), file .. " lit une unite (interdit dans Core/)")
        end
        for _, file in ipairs({ "Core/Pairing.lua", "Core/Intermission.lua" }) do
            local code = stripComments(readFile(file))
            assert.is_nil(code:find("GideonRaidDB", 1, true), file .. " lit les SavedVariables (interdit dans Core/)")
        end
    end)
end)
