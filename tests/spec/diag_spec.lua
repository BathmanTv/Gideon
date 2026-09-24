--[[--------------------------------------------------------------------------
    tests/spec/diag_spec.lua   (busted)

    `/gr diag` : LE BILAN DE SANTE DE L'ADDON EN UNE COMMANDE.

    Ce que ces tests verrouillent, HORS JEU :

      1. Core/Diag.lua (PUR) : la liste des fichiers de son (les quatre, dans
         l'ordre canonique de Core/Sound.lua), la PORTE DU SILENCE
         (`probeGate` : le controle audio ne tourne que si le client est deja
         silencieux), le verdict d'une sonde (`willPlay` booleen de
         PlaySoundFile) et le rapport ligne par ligne ;
      2. le CABLAGE (stub) : `/gr diag` lit deux CVars du client, MAIS ne joue
         aucun son quand le son du jeu est actif (aucun bruit en raid), ne joue
         RIEN non plus quand le son est coupe (le verdict serait un mensonge), et
         joue les quatre fichiers DE MANIERE INAUDIBLE (volume general a 0, canal
         actif) quand c'est le seul cas ou le test est a la fois utile et muet.

    ASTUCE DOCUMENTEE : `PlaySoundFile` renvoie `willPlay` - vrai si le client VA
    jouer le fichier, faux/nil sinon (fichier absent, fichier ajoute APRES le
    lancement du client, lecture refusee). C'est le seul moyen de savoir EN JEU si
    un fichier de son est vraiment charge. Comme cet appel EST une lecture audio, il
    est interdit de le faire quand le joueur entend le jeu : d'ou la porte.

    Lecture seule : rien n'est ecrit dans les SavedVariables, rien n'est envoye,
    aucun ping, aucune macro (verifie par guard_spec.lua).
----------------------------------------------------------------------------]]
--
--
--
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

--- Compte les occurrences d'une sous-chaine (un verdict par fichier de son).
local function countOf(text, needle)
    local count = 0
    local from = 1
    while true do
        local found = string.find(text, needle, from, true)
        if found == nil then
            return count
        end
        count = count + 1
        from = found + 1
    end
end

-- ===========================================================================
-- 1. LOGIQUE PURE : Core/Diag.lua
-- ===========================================================================
describe("/gr diag : le rapport de sante (logique pure)", function()
    local ns = wowenv.loadCore()
    local Diag = ns.Diag
    local Sound = ns.Sound

    it("couvre les QUATRE fichiers de l'addon, dans l'ordre canonique du .toc", function()
        local entries = Diag.soundEntries()
        assert.are.equal(4, #entries)
        assert.are.equal(Diag.count(), #entries)
        assert.are.same({
            Sound.ALL_FILE_NAMES[1],
            Sound.ALL_FILE_NAMES[2],
            Sound.ALL_FILE_NAMES[3],
            Sound.ALL_FILE_NAMES[4],
        }, { entries[1].fileName, entries[2].fileName, entries[3].fileName, entries[4].fileName })
        -- Le chemin sonde est celui que l'addon JOUE vraiment, pas une copie.
        assert.are.equal(Sound.FOLDER .. "assign-1v3r.ogg", entries[1].path)
        assert.are.equal(Sound.FOLDER .. "assign-3v1r.ogg", entries[3].path)
        assert.are.equal(Sound.startPath(), entries[4].path)
        assert.are.equal(Sound.START_FILE, entries[4].fileName)
    end)

    it("la PORTE DU SILENCE : la sonde ne tourne que si elle ne peut pas s'entendre", function()
        -- Canal ACTIF + volume a 0 : le client repond, et RIEN n'est audible.
        assert.are.equal(Diag.GATE.PROBE, Diag.probeGate({ allSound = "1", masterVolume = "0.000000" }))
        assert.are.equal(Diag.GATE.PROBE, Diag.probeGate({ allSound = "1", masterVolume = "0" }))
        -- Volume audible : on ne sonde PAS (aucun bruit pendant un combat).
        assert.are.equal(Diag.GATE.SOUND_ON, Diag.probeGate({ allSound = "1", masterVolume = "1.000000" }))
        assert.are.equal(Diag.GATE.SOUND_ON, Diag.probeGate({ allSound = "1", masterVolume = "0.400000" }))
        -- Son coupe : un canal DESACTIVE repond « rien ne sera joue » meme pour un
        -- fichier present - le verdict serait un mensonge, donc on ne sonde pas.
        assert.are.equal(Diag.GATE.SOUND_OFF, Diag.probeGate({ allSound = "0", masterVolume = "0" }))
        assert.are.equal(Diag.GATE.SOUND_OFF, Diag.probeGate({ allSound = "0", masterVolume = "1.000000" }))
        -- Etat INCONNU (hors client, CVar refusee, valeur inattendue) : jamais de sonde.
        assert.are.equal(Diag.GATE.UNKNOWN, Diag.probeGate(nil))
        assert.are.equal(Diag.GATE.UNKNOWN, Diag.probeGate({}))
        -- Une valeur inattendue pour l'interrupteur ("true", "oui", vide) n'est PAS
        -- "active" : on la lit comme un canal qui n'accepte pas la lecture, et on ne
        -- sonde pas (le doute ne fait jamais de bruit).
        assert.are.equal(Diag.GATE.SOUND_OFF, Diag.probeGate({ allSound = "true", masterVolume = "0" }))
        assert.are.equal(Diag.GATE.SOUND_OFF, Diag.probeGate({ allSound = "", masterVolume = "0" }))
        -- Un volume illisible ne prouve PAS le silence : on ne sonde pas.
        assert.are.equal(Diag.GATE.SOUND_ON, Diag.probeGate({ allSound = "1", masterVolume = "beaucoup" }))
        assert.is_false(Diag.isSilentVolume(nil))
        assert.is_false(Diag.isSilentVolume(""))
        assert.is_true(Diag.isSilentVolume("0.000000"))
        assert.is_false(Diag.isEnabled("0"))
        assert.is_true(Diag.isEnabled("1"))
    end)

    it("le verdict d'une sonde : seul un vrai booleen tranche, jamais une devinette", function()
        assert.are.equal(Diag.STATUS.PLAYABLE, Diag.verdict(true))
        assert.are.equal(Diag.STATUS.NOT_PLAYABLE, Diag.verdict(false))
        assert.are.equal(Diag.STATUS.NOT_PLAYABLE, Diag.verdict(nil))
        assert.are.equal(Diag.STATUS.UNKNOWN, Diag.verdict("oui"))
        assert.are.equal(Diag.STATUS.UNKNOWN, Diag.verdict(0))
    end)

    it("allRefused : seulement quand TOUTES les sondes reviennent non jouables", function()
        assert.is_false(Diag.allRefused({ true, false }))
        assert.is_false(Diag.allRefused({}))
        assert.is_false(Diag.allRefused(nil))
        assert.is_true(Diag.allRefused({ false, false, nil, false }))
    end)

    it("les QUATRE lignes de fichier portent un verdict lisible (et un chemin de .toc)", function()
        local ok = Diag.soundLine("assign-1v3r.ogg", Diag.STATUS.PLAYABLE)
        assert.is_true(contains(ok, "Sound/assign-1v3r.ogg: present and playable [OK]"), ok)

        local ko = Diag.soundLine("assign-2v2r.ogg", Diag.STATUS.NOT_PLAYABLE)
        assert.is_true(contains(ko, "Sound/assign-2v2r.ogg: NOT playable [KO]"), ko)
        -- La cause la plus probable et le geste qui la corrige sont dans la ligne.
        assert.is_true(contains(ko, "GideonRaid.toc"), ko)
        assert.is_true(contains(ko, "RESTARTED"), ko)

        local skipped = Diag.soundLine("assign-3v1r.ogg", Diag.STATUS.NOT_TESTED)
        assert.is_true(contains(skipped, "NOT TESTED"), skipped)

        -- Un statut inconnu ne doit JAMAIS produire une ligne vide ni un identifiant brut.
        local unknown = Diag.soundLine("assign-3v1r.ogg", "nimportequoi")
        assert.is_true(contains(unknown, "Sound/assign-3v1r.ogg"), unknown)
        assert.is_true(contains(unknown, "UNKNOWN"), unknown)
    end)

    it("le rapport rappelle la cible, l'idlog et le ping, et dit POURQUOI rien n'a ete teste", function()
        local lines = Diag.report({
            target = "ids 3445",
            source = "Target source: the default DELIVERED with the addon (no player ever added anything).",
            delivered = "Default delivered with the addon: id 3445.",
            idlog = "disabled",
            pingMode = "anchors",
            ping = "ANCHORS: only a 1V3R anchor pings.",
            sound = "enabled",
            gate = Diag.GATE.SOUND_ON,
            results = {},
        })
        local text = table.concat(lines, "\n")
        assert.is_true(contains(text, "DIAGNOSTIC"), text)
        assert.is_true(contains(text, "read-only"), text)
        assert.is_true(contains(text, "auto-open target: ids 3445"), text)
        assert.is_true(contains(text, "the default DELIVERED with the addon"), text)
        assert.is_true(contains(text, "encounter id log: disabled"), text)
        assert.is_true(contains(text, "intermission ping policy: anchors"), text)
        assert.is_true(contains(text, "assignment sound preference: enabled"), text)
        -- Les quatre fichiers sont LISTES, et aucun n'est teste : le rapport dit
        -- comment rendre le test possible, sans jamais le faire en douce.
        assert.are.equal(4, countOf(text, "NOT TESTED"), text)
        assert.are.equal(0, countOf(text, "[OK]"), text)
        assert.is_true(contains(text, "the audio check did NOT run"), text)
        assert.is_true(contains(text, "/console Sound_MasterVolume 0"), text)
        assert.is_true(contains(text, "/gr sound test"), text)
        -- Le rappel qui evite de croire a un bug apres l'ajout d'un fichier.
        assert.is_true(contains(text, "before a RESTART"), text)
    end)

    it("la porte autorisee : le verdict vient des reponses injectees, ligne par ligne", function()
        local lines = Diag.report({
            target = "ids 3445",
            gate = Diag.GATE.PROBE,
            results = { true, true, false, nil },
        })
        local text = table.concat(lines, "\n")
        assert.are.equal(2, countOf(text, "[OK]"), text)
        assert.are.equal(2, countOf(text, "[KO]"), text)
        assert.are.equal(0, countOf(text, "NOT TESTED"), text)
        assert.is_true(contains(text, "the check DID run for real"), text)
        assert.is_true(contains(text, "NOTHING was audible"), text)
        -- Deux fichiers sur quatre refusent : ce n'est PAS le cas « tout refuse ».
        assert.is_false(contains(text, "ALL FOUR files"), text)
    end)

    it("quand les QUATRE fichiers refusent, le rapport previent (le canal est suspect)", function()
        local lines = Diag.report({
            gate = Diag.GATE.PROBE,
            results = { false, false, nil, false },
        })
        local text = table.concat(lines, "\n")
        assert.are.equal(4, countOf(text, "[KO]"), text)
        assert.is_true(contains(text, "ALL FOUR files came back as not playable"), text)
    end)

    it("son coupe ou etat illisible : le rapport refuse de MENTIR sur les fichiers", function()
        local off = table.concat(Diag.report({ gate = Diag.GATE.SOUND_OFF }), "\n")
        assert.is_true(contains(off, "DISABLED channel answers"), off)
        assert.is_true(contains(off, "verdict would be a lie"), off)
        assert.are.equal(0, countOf(off, "[OK]"), off)
        assert.are.equal(0, countOf(off, "[KO]"), off)

        local unknown = table.concat(Diag.report({ gate = Diag.GATE.UNKNOWN }), "\n")
        assert.is_true(contains(unknown, "NOT TESTED"), unknown)
        assert.are.equal(0, countOf(unknown, "[KO]"), unknown)
    end)

    it("le rapport est TOTAL : un contexte vide ne leve pas et reste lisible", function()
        local text = table.concat(Diag.report(nil), "\n")
        assert.is_true(contains(text, "DIAGNOSTIC"), text)
        assert.is_true(contains(text, "auto-open target: none"), text)
        assert.are.equal(4, countOf(text, "Sound/"), text)
        assert.are.equal(Diag.SCHEMA_VERSION, 1)
        assert.are.equal("Master", Diag.PROBE_CHANNEL)
        assert.are.equal(Diag.PROBE_CHANNEL, ns.Sound.CHANNEL)
    end)
end)

-- ===========================================================================
-- 2. LE CABLAGE : /gr diag dans le client (stub), SANS AUCUN BRUIT
-- ===========================================================================
describe("/gr diag : le cablage (lecture seule, et muet)", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.GideonRaidPingHelpPanel = nil
        _G.SlashCmdList = nil
        _G.GetBindingKey = nil
        _G.GetCVar = nil
        _G.C_CVar = nil
        stub.install()
        ns = wowenv.loadAddon()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    local function slash(argument)
        _G.SlashCmdList["GIDEONRAID"](argument)
    end

    --- Un client dont on CHOISIT l'etat du son (les deux CVars lus par le diagnostic).
    local function setSoundState(allSound, masterVolume)
        _G.GetCVar = function(name)
            if name == "Sound_EnableAllSound" then
                return allSound
            end
            if name == "Sound_MasterVolume" then
                return masterVolume
            end
            return nil
        end
    end

    it("SON ACTIF (le cas du raid) : AUCUN son joue, et le rapport le dit", function()
        setSoundState("1", "1.000000")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")

        assert.are.equal(0, #stub.sounds, "le diagnostic ne doit jouer AUCUN son quand le son du jeu est actif")
        local text = messages()
        assert.is_true(contains(text, "NOT TESTED"), text)
        assert.is_true(contains(text, "the audio check did NOT run"), text)
        assert.is_true(contains(text, "/console Sound_MasterVolume 0"), text)
        -- ... et le reste du bilan est la : cible livree, idlog, ping.
        assert.is_true(contains(text, "3445"), text)
        assert.is_true(contains(text, "Default delivered with the addon"), text)
        assert.is_true(contains(text, "encounter id log: disabled"), text)
        assert.is_true(contains(text, "intermission ping policy: anchors"), text)
        -- Lecture seule : rien n'a ete ecrit dans la sauvegarde.
        assert.are.same({}, _G.GideonRaidDB.intermission.bossIds)
        assert.is_false(_G.GideonRaidDB.intermission.bossTargetCleared)
        assert.is_false(_G.GideonRaidDB.intermission.idlog)
    end)

    it("VOLUME A 0 (canal actif) : les quatre fichiers sont testes, SANS bruit", function()
        setSoundState("1", "0.000000")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")

        assert.are.equal(4, #stub.sounds, "les quatre fichiers doivent etre testes")
        for index = 1, #stub.sounds do
            assert.are.equal(ns.Sound.CHANNEL, stub.sounds[index].channel, "le canal sonde doit etre celui du jeu")
        end
        assert.are.equal(ns.Sound.FOLDER .. "assign-1v3r.ogg", stub.sounds[1].path)
        assert.are.equal(ns.Sound.FOLDER .. "assign-2v2r.ogg", stub.sounds[2].path)
        assert.are.equal(ns.Sound.FOLDER .. "assign-3v1r.ogg", stub.sounds[3].path)
        assert.are.equal(ns.Sound.startPath(), stub.sounds[4].path)

        local text = messages()
        assert.are.equal(4, countOf(text, "[OK]"), text)
        assert.is_true(contains(text, "the check DID run for real"), text)
        assert.is_true(contains(text, "NOTHING was audible"), text)
    end)

    it("un fichier NON jouable est designe NOMMEMENT, avec la cause probable", function()
        setSoundState("1", "0")
        local startPath = ns.Sound.startPath()
        _G.PlaySoundFile = function(path, channel)
            stub.sounds[#stub.sounds + 1] = { path = path, channel = channel }
            if path == startPath then
                return false
            end
            return true
        end
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")

        local text = messages()
        assert.is_true(contains(text, "Sound/intermission-start.ogg: NOT playable [KO]"), text)
        assert.are.equal(3, countOf(text, "[OK]"), text)
        assert.is_true(contains(text, "RESTARTED"), text)
    end)

    it("SON COUPE : le diagnostic refuse de mentir et n'appelle meme pas PlaySoundFile", function()
        setSoundState("0", "1.000000")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")

        assert.are.equal(0, #stub.sounds, "un canal desactive rendrait le verdict faux : on ne sonde pas")
        local text = messages()
        assert.is_true(contains(text, "DISABLED channel answers"), text)
        assert.is_true(contains(text, "Ctrl+S"), text)
        assert.are.equal(4, countOf(text, "NOT TESTED"), text)
    end)

    it("CVar illisible (hors client, nom refuse) : aucun son, aucun mensonge", function()
        _G.GetCVar = nil
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")
        assert.are.equal(0, #stub.sounds)
        local text = messages()
        assert.are.equal(4, countOf(text, "NOT TESTED"), text)

        -- Un client qui leve sur la lecture des CVars ne doit pas faire echouer la
        -- commande (tout est sous pcall).
        _G.GetCVar = function()
            error("CVar refusee")
        end
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")
        assert.are.equal(0, #stub.sounds)
        assert.is_true(contains(messages(), "NOT TESTED"), messages())
    end)

    it("12.x : C_CVar.GetCVar est utilise quand le global GetCVar a disparu", function()
        _G.GetCVar = nil
        _G.C_CVar = {
            GetCVar = function(name)
                if name == "Sound_EnableAllSound" then
                    return "1"
                end
                if name == "Sound_MasterVolume" then
                    return "0"
                end
                return nil
            end,
        }
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")
        assert.are.equal(4, #stub.sounds, "les deux acces au CVar doivent etre essayes")
        assert.is_true(contains(messages(), "[OK]"), messages())

        -- Un C_CVar qui leve retombe sur « pas de sonde », sans erreur Lua.
        _G.C_CVar = {
            GetCVar = function()
                error("refus")
            end,
        }
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")
        local before = #stub.sounds
        assert.is_true(contains(messages(), "DIAGNOSTIC"), messages())
        assert.are.equal(before, #stub.sounds)
    end)

    it("PlaySoundFile en echec (client qui refuse) : le bilan reste utilisable", function()
        setSoundState("1", "0")
        _G.PlaySoundFile = function()
            error("le client refuse cet appel")
        end
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")

        local text = messages()
        assert.are.equal(4, countOf(text, "verdict UNKNOWN"), text)
        assert.is_true(contains(text, "DIAGNOSTIC"), text)

        -- Un client SANS PlaySoundFile du tout : meme resultat, sans erreur Lua.
        _G.PlaySoundFile = nil
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("diag")
        assert.is_true(contains(messages(), "DIAGNOSTIC"), messages())
    end)

    it("le diagnostic ne touche NI la timeline, NI l'override, NI l'idlog", function()
        setSoundState("1", "0")
        slash("diag")
        assert.is_true(_G.GideonRaidDB.intermission.overrideEncounter == false, "l'override ne doit pas bouger")
        assert.is_false(_G.GideonRaidDB.intermission.idlog, "l'idlog ne doit pas s'activer")
        assert.are.same({}, _G.GideonRaidDB.intermission.seenEncounters, "rien ne doit etre memorise")
        -- Le panneau d'intermission ne s'ouvre pas sur un diagnostic.
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
    end)

    it("/gr diag est annonce dans l'aide (/gr help)", function()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("help")
        assert.is_true(contains(messages(), "/gr diag"), messages())
    end)
end)
