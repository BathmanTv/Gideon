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

--- Lecture audio : autorisee, mais encadree (voir le test dedie). Core/ n'a
--- JAMAIS le droit d'appeler PlaySoundFile (c'est la couche de rendu qui joue).
local SOUND_PLAYBACK = "PlaySoundFile"

describe("garde anti-API-interdite (fichiers charges par le client)", function()
    local files = wowenv.tocFiles()

    it("scanne reellement tous les fichiers du .toc", function()
        assert.are.equal(13, #files)
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
            "Core/Sound.lua",
            "Core/BossFilter.lua",
            "Core/Diag.lua",
            "Core/Config.lua",
            "Core/Pairing.lua",
            "Core/Intermission.lua",
            "Core/Simulation.lua",
            "Core/Textures.lua",
            "Core/Layout.lua",
        }
        for _, file in ipairs(pureFiles) do
            local code = stripComments(readFile(file))
            assert.is_nil(code:find("GetTime", 1, true), file .. " lit l'heure du client (interdit dans Core/)")
            assert.is_nil(code:find("math.random", 1, true), file .. " utilise math.random (non deterministe)")
            assert.is_nil(code:find("CreateFrame", 1, true), file .. " appelle l'API WoW (interdit dans Core/)")
            assert.is_nil(code:find("UnitName", 1, true), file .. " lit une unite (interdit dans Core/)")
            assert.is_nil(code:find(BINDING_LOOKUP, 1, true), file .. " lit un raccourci (reserve a la couche de rendu)")
        end
        for _, file in ipairs({
            "Core/Pairing.lua",
            "Core/Intermission.lua",
            "Core/Simulation.lua",
            "Core/Sound.lua",
            "Core/BossFilter.lua",
        }) do
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

    it("garde la DECISION d'ouverture auto dans Core/, sous pcall, bornee", function()
        -- Le panneau ne doit plus s'ouvrir sur n'importe quel boss : la decision
        -- (allow-list d'ids d'encounter, `/gr boss <id>`) vit dans
        -- Core/BossFilter.lua, qui lit chaque argument de l'evenement SOUS pcall
        -- (une valeur SECRETE leve au moindre acces) et dont la liste VIDE
        -- n'ouvre rien (defaut sur).
        local code = stripComments(readFile("Core/BossFilter.lua"))
        assert.is_truthy(code:find("pcall", 1, true) ~= nil, "Core/BossFilter.lua doit lire les arguments sous pcall")
        assert.is_truthy(code:find("bossIds", 1, true) ~= nil, "Core/BossFilter.lua doit porter l'allow-list d'ids")
        assert.is_truthy(code:find("MAX_SEEN", 1, true) ~= nil, "Core/BossFilter.lua doit borner l'idlog")
        -- La couche de rendu REND la decision : elle ne compare ni id ni nom
        -- elle-meme, elle passe par Core/ (et sous pcall).
        local ui = stripComments(readFile("UI/Intermission.lua"))
        assert.is_truthy(ui:find("BossFilter", 1, true) ~= nil, "UI/Intermission.lua doit passer par Core/BossFilter")
        assert.is_nil(ui:find("bossIds", 1, true), "UI/Intermission.lua ne doit pas lire l'allow-list lui-meme")
        assert.is_truthy(ui:find("pcall(BossFilter", 1, true) ~= nil, "la decision doit etre appelee sous pcall dans UI/")
    end)

    it("garde le SON d'intermission EXPLICITE dans UI/, sous pcall, et AUCUN son automatique", function()
        -- REGLE EN JEU (decision du raid lead) : plus AUCUN son ne part tout seul.
        -- Le son de debut d'intermission n'est plus joue a l'ouverture du panneau :
        -- la table pure et la regle « une seule lecture » restent dans
        -- Core/Sound.lua (elles servent la commande explicite /gr sound test start),
        -- mais UI/Intermission.lua ne doit plus APPELER la lecture automatique.
        local core = stripComments(readFile("Core/Sound.lua"))
        assert.is_truthy(core:find("takeIntermissionStart", 1, true) ~= nil, "Core/Sound.lua doit porter la regle du son de debut")
        assert.is_truthy(core:find("START_FILE", 1, true) ~= nil, "Core/Sound.lua doit nommer le fichier de debut")
        local guard = stripComments(readFile("UI/Intermission.lua"))
        assert.is_nil(
            guard:find("takeIntermissionStart", 1, true),
            "UI/Intermission.lua ne doit plus APPELER la lecture automatique du son de debut"
        )
        -- Le SEUL chemin audio restant est le clic sur un bouton de composition,
        -- sous pcall (voir tests/spec/sound_spec.lua, qui le prouve en jouant).
        assert.is_truthy(
            guard:find("takeAssignSound", 1, true) ~= nil,
            "UI/Intermission.lua doit jouer le son d'assignation du bouton clique"
        )
        assert.is_truthy(guard:find("pcall", 1, true) ~= nil, "tout appel audio de UI/ doit etre sous pcall")
    end)

    it("garde /gr diag : le controle audio passe par la PORTE DU SILENCE de Core/", function()
        -- PlaySoundFile est appele par le diagnostic pour SAVOIR si un fichier est
        -- charge (il renvoie false/nil quand il ne sera pas joue). Comme cet appel
        -- EST une lecture audio, il est interdit de le lancer quand le joueur entend
        -- le jeu : la porte (Core/Diag.probeGate) decide, la couche de rendu obeit.
        local core = stripComments(readFile("Core/Diag.lua"))
        assert.is_truthy(core:find("probeGate", 1, true) ~= nil, "Core/Diag.lua doit porter la porte du silence")
        assert.is_truthy(core:find("probeGate", 1, true) ~= nil, "Core/Diag.lua doit decider si la sonde peut tourner")
        assert.is_truthy(core:find("GATE", 1, true) ~= nil, "Core/Diag.lua doit nommer les decisions de la porte")
        local ui = stripComments(readFile("UI/Panel.lua"))
        assert.is_truthy(ui:find("probeGate", 1, true) ~= nil, "UI/Panel.lua doit interroger la porte avant toute sonde")
        assert.is_truthy(ui:find("GATE.PROBE", 1, true) ~= nil, "UI/Panel.lua ne doit sonder QUE sur decision PROBE")
        assert.is_truthy(ui:find("GetCVar", 1, true) ~= nil, "UI/Panel.lua doit LIRE l'etat du son (lecture seule)")
        -- La couche de rendu lit les CVars sous pcall et ne les ECRIT jamais.
        local raw = stripComments(readFile("UI/Panel.lua"))
        assert.is_nil(raw:find("SetCVar", 1, true), "UI/Panel.lua ne doit jamais MODIFIER un reglage du joueur")
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

    it("joue un son UNIQUEMENT dans la couche de rendu et SOUS pcall", function()
        -- PlaySoundFile est le SEUL appel audio de l'addon. Il ne doit apparaitre
        -- ni dans Core/ (une table pure y decide QUOI jouer, jamais l'appel), ni
        -- hors de UI/, et chaque ligne qui l'appelle doit etre protegee par
        -- pcall (ou par le type() qui precede l'appel) : un fichier manquant ou
        -- un client qui refuse doit laisser l'addon SILENCIEUX, sans erreur Lua.
        for _, file in ipairs({
            "Core/Locale.lua",
            "Core/Sound.lua",
            "Core/BossFilter.lua",
            "Core/Diag.lua",
            "Core/Config.lua",
            "Core/Pairing.lua",
            "Core/Intermission.lua",
            "Core/Simulation.lua",
            "Core/Textures.lua",
            "Core/Layout.lua",
        }) do
            local code = stripStrings(stripComments(readFile(file)))
            assert.is_nil(code:find(SOUND_PLAYBACK, 1, true), file .. " appelle " .. SOUND_PLAYBACK .. " (interdit dans Core/)")
        end
        local found = false
        for _, file in ipairs(files) do
            -- Les chaines sont retirees ici : un message qui NOMME PlaySoundFile
            -- (Core/Locale.lua) n'est pas un appel.
            local code = stripStrings(stripComments(readFile(file)))
            if code:find(SOUND_PLAYBACK, 1, true) ~= nil then
                found = true
                assert.is_truthy(file:match("^UI/") ~= nil, file .. " joue un son hors de UI/")
                for line in code:gmatch("[^\n]+") do
                    if line:find(SOUND_PLAYBACK, 1, true) ~= nil then
                        local guarded = line:find("pcall(", 1, true) ~= nil or line:find("type(", 1, true) ~= nil
                        assert.is_true(guarded, file .. " : lecture audio NON protegee : " .. line)
                    end
                end
            end
        end
        assert.is_true(found, "l'appel audio de l'assignation a disparu de la couche de rendu")
    end)
end)
