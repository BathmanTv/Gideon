--[[--------------------------------------------------------------------------
    tests/spec/sound_spec.lua   (busted)

    SONDES D'ASSIGNATION (demande du raid lead) : UN son par composition
    canonique (1V3R / 2V2R / 3V1R), joue UNE SEULE FOIS quand le joueur declare
    sa composition - flux reel comme repetition `/gideon sim inter`.

    Trois familles de verifications, toutes HORS JEU :

      1. Core/Sound.lua (PUR) : table etat -> fichier, chemins client, resolveur
         STRICT de `/gideon sound on|off`, resolveur TOTAL de la preference
         persistee, et la garde « un seul son par assignation » ;
      2. les FICHIERS et le PACKAGING : les trois chemins sont listes dans
         GideonRaid.toc (le client ne charge pas un son non liste), les trois
         fichiers existent sur disque et sont de vrais Ogg Vorbis, et rien dans
         .pkgmeta ne les exclut du zip ;
      3. le CABLAGE (stub) : le son n'est joue QUE pour la composition declaree et
         une seule fois, jamais sans declaration, jamais quand la preference est
         off, et le rendu continue si PlaySoundFile leve ou disparait.

    PlaySoundFile est stubbe par tests/support/wowapi_stub.lua (il enregistre
    chaque appel) : c'est la garde anti-appel audio dans Core/, verifiee en plus
    par tests/spec/guard_spec.lua.
----------------------------------------------------------------------------]]
--
--
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(tostring(text), needle, 1, true) ~= nil
end

--- Le boss CIBLE du harness : le filtre d'ouverture auto est une allow-list d'ids
--- persistee et VIDE par defaut (defaut sur : aucune ouverture automatique). Un
--- test qui veut le flux REEL nomme donc la cible, puis tire ce boss, avec les
--- arguments reels d'ENCOUNTER_START (id, nom, difficulte, taille de groupe).
local BOSS_ID = 1234
local function pullTargetBoss()
    _G.GideonRaidDB.intermission.bossIds = { BOSS_ID }
    stub.mainFrame():Fire("ENCOUNTER_START", BOSS_ID, "Entombed Sentinels", 16, 20)
end

--- Les sons d'ASSIGNATION (assign-*.ogg) reellement joues. Le son de DEBUT
--- d'intermission (intermission-start.ogg) est compte a PART : il part a
--- l'ouverture du panneau, pas au clic (voir le bloc dedie plus bas).
local function assignSounds()
    local out = {}
    for index = 1, #stub.sounds do
        if contains(stub.sounds[index].path, "assign-") then
            out[#out + 1] = stub.sounds[index]
        end
    end
    return out
end

local function startSounds()
    local out = {}
    for index = 1, #stub.sounds do
        if contains(stub.sounds[index].path, "intermission-start") then
            out[#out + 1] = stub.sounds[index]
        end
    end
    return out
end

local function readFile(path)
    local handle = assert(io.open(path, "r"), path .. " introuvable")
    local content = handle:read("*a")
    handle:close()
    return content
end

local function fileExists(path)
    local handle = io.open(path, "rb")
    if handle == nil then
        return false, 0, nil
    end
    local content = handle:read("*a")
    handle:close()
    return true, #content, content
end

--- Entrees d' `ignore:` de .pkgmeta, normalisees (sans "- " ni slash final) :
--- sert a prouver que le dossier Sound/ n'est pas exclu du zip.
local function pkgmetaIgnores()
    local out = {}
    local lines = {}
    for line in readFile(".pkgmeta"):gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    local inIgnore = false
    for index = 1, #lines do
        local line = lines[index]
        if line:match("^ignore:%s*$") ~= nil then
            inIgnore = true
        elseif inIgnore then
            local entry = line:match("^%s+%-%s*(.-)%s*$")
            if entry == nil then
                break
            end
            out[#out + 1] = entry:gsub("^%./", ""):gsub("/+$", "")
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 1. Core/Sound.lua : table pure, chemins, preference bornee, garde « un son »
-- ---------------------------------------------------------------------------
describe("Sound : table pure etat -> fichier de son", function()
    local ns = wowenv.loadCore()
    local Sound = ns.Sound

    it("couvre les TROIS etats canoniques, sans derive avec Intermission", function()
        assert.are.same(ns.Intermission.STATES, Sound.STATES)
        for index = 1, #Sound.STATES do
            local state = Sound.STATES[index]
            assert.is_string(Sound.fileName(state), state)
            assert.is_string(Sound.pathFor(state), state)
        end
        assert.are.equal(3, #Sound.FILE_NAMES)
        -- Le son de DEBUT d'intermission est un QUATRIEME fichier, hors des trois
        -- etats canoniques : il est liste AVEC eux (ALL_FILE_NAMES), ce que
        -- verifient le .toc, le disque et le packaging plus bas.
        assert.are.equal("intermission-start.ogg", Sound.START_FILE)
        assert.are.equal(4, #Sound.ALL_FILE_NAMES)
        assert.are.equal("Sound/intermission-start.ogg", "Sound/" .. Sound.START_FILE)
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\intermission-start.ogg", Sound.startPath())
    end)

    it("donne a chaque etat SON fichier (minuscules, sans accents, stables)", function()
        assert.are.equal("assign-1v3r.ogg", Sound.fileName("1V3R"))
        assert.are.equal("assign-2v2r.ogg", Sound.fileName("2V2R"))
        assert.are.equal("assign-3v1r.ogg", Sound.fileName("3V1R"))
        -- Aucun des trois fichiers ne peut etre confondu avec un autre.
        local seen = {}
        for index = 1, #Sound.STATES do
            local file = Sound.fileName(Sound.STATES[index])
            assert.is_nil(seen[file], "deux etats partagent " .. tostring(file))
            seen[file] = Sound.STATES[index]
        end
    end)

    it("construit les CHEMINS CLIENT sous Interface\\AddOns\\GideonRaid\\Sound\\", function()
        for index = 1, #Sound.STATES do
            local state = Sound.STATES[index]
            local expected = "Interface\\AddOns\\GideonRaid\\Sound\\" .. Sound.fileName(state)
            assert.are.equal(expected, Sound.pathFor(state))
        end
        -- Tolerance sur la casse : la forme canonique reste celle du module
        -- Intermission.
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-2v2r.ogg", Sound.pathFor("2v2r"))
    end)

    it("est TOTAL : un etat absent, vide, inconnu ou non-chaine ne leve pas", function()
        for _, raw in ipairs({ nil, "", "4V0R", "bidon", 3, true, {} }) do
            assert.is_nil(Sound.resolveState(raw))
            assert.is_nil(Sound.fileName(raw))
            assert.is_nil(Sound.pathFor(raw))
        end
        -- Tolerance : espaces et casse ("1 V 3 R"), la forme canonique restant
        -- celle du module Intermission.
        assert.are.equal("3V1R", Sound.resolveState(" 3 v 1 r "))
        assert.are.equal("1V3R", Sound.resolveState("1v3r"))
    end)
end)

describe("Sound : preference bornee (on|off)", function()
    local Sound = wowenv.loadCore().Sound

    it("resolveSwitch est STRICT : on / off seulement, tout le reste est refuse", function()
        assert.are.equal(true, Sound.resolveSwitch("on"))
        assert.are.equal(false, Sound.resolveSwitch("off"))
        assert.are.equal(true, Sound.resolveSwitch(" ON "))
        assert.are.equal(false, Sound.resolveSwitch("Off"))
        for _, raw in ipairs({ nil, "", "yes", "true", "1", "actif", 1, true, {} }) do
            assert.is_nil(Sound.resolveSwitch(raw), "valeur acceptee a tort : " .. tostring(raw))
        end
    end)

    it("resolveEnabled est TOTAL : seul un false exact coupe le son", function()
        assert.is_true(Sound.resolveEnabled(nil), "une sauvegarde sans champ = son actif")
        assert.is_true(Sound.resolveEnabled(true))
        assert.is_false(Sound.resolveEnabled(false))
        assert.is_true(Sound.resolveEnabled("off"), "valeur bricolee = defaut, jamais de coupure silencieuse")
        assert.is_true(Sound.resolveEnabled(0))
    end)

    it("Config materialise le defaut et le resout sans jamais lever", function()
        local ns = wowenv.loadCore()
        assert.is_true(ns.Config.defaultIntermission().soundEnabled)
        assert.is_true(ns.Config.resolveIntermission(nil).soundEnabled)
        assert.is_false(ns.Config.resolveIntermission({ soundEnabled = false }).soundEnabled)
        assert.is_true(ns.Config.resolveIntermission({ soundEnabled = "off" }).soundEnabled)
        -- Le son d'assignation vit dans la meme table de configuration que la
        -- politique de ping : les autres champs restent intacts.
        assert.are.equal("anchors", ns.Config.resolveIntermission({ soundEnabled = false }).pingMode)
    end)
end)

describe("Sound : UN SEUL son par assignation (garde pure)", function()
    local Sound = wowenv.loadCore().Sound

    it("ne demande AUCUN son sans composition declaree", function()
        local assigner = Sound.newAssigner()
        for _, raw in ipairs({ nil, "", "bidon", "2", "5" }) do
            local request, reason = Sound.takeAssignSound(assigner, raw, true)
            assert.is_nil(request, tostring(raw))
            assert.are.equal(Sound.REASON.UNKNOWN, reason)
        end
        assert.is_nil(assigner.lastState, "aucune assignation ne doit etre memorisee")
    end)

    it("demande le fichier de l'etat declare, sur le canal Master", function()
        local assigner = Sound.newAssigner()
        local request, reason = Sound.takeAssignSound(assigner, "3V1R", true)
        assert.are.equal(Sound.REASON.PLAY, reason)
        assert.are.equal("3V1R", request.state)
        assert.are.equal("assign-3v1r.ogg", request.fileName)
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-3v1r.ogg", request.path)
        assert.are.equal("Master", request.channel)
        assert.are.equal(Sound.CHANNEL, request.channel)
    end)

    it("refuse une SECONDE lecture de la meme assignation (pas de double son)", function()
        local assigner = Sound.newAssigner()
        assert.is_not_nil(Sound.takeAssignSound(assigner, "2V2R", true))
        for _ = 1, 5 do
            local request, reason = Sound.takeAssignSound(assigner, "2V2R", true)
            assert.is_nil(request, "le meme etat ne doit pas etre rejoue")
            assert.are.equal(Sound.REASON.ALREADY, reason)
        end
        -- Un AUTRE etat declare dans la meme session est un nouveau choix : son
        -- son doit partir.
        assert.is_not_nil(Sound.takeAssignSound(assigner, "1V3R", true))
    end)

    it("rearme la garde apres CORRECT (nouvelle composition = nouveau son)", function()
        local assigner = Sound.newAssigner()
        assert.is_not_nil(Sound.takeAssignSound(assigner, "1V3R", true))
        assert.is_nil(Sound.takeAssignSound(assigner, "1V3R", true))
        Sound.resetAssigner(assigner)
        local request, reason = Sound.takeAssignSound(assigner, "1V3R", true)
        assert.are.equal(Sound.REASON.PLAY, reason)
        assert.are.equal("assign-1v3r.ogg", request.fileName)
        -- resetAssigner est TOTAL : un argument non-table rend une garde neuve.
        assert.is_table(Sound.resetAssigner(nil))
    end)

    it("ne joue RIEN quand la preference est off (meme sur un etat valide)", function()
        local assigner = Sound.newAssigner()
        local request, reason = Sound.takeAssignSound(assigner, "1V3R", false)
        assert.is_nil(request)
        assert.are.equal(Sound.REASON.DISABLED, reason)
        -- Rien n'a ete joue : rien n'est memorise non plus.
        assert.is_nil(assigner.lastState)
    end)
end)

-- ---------------------------------------------------------------------------
-- 2. Fichiers et packaging : .toc, disque, .pkgmeta
-- ---------------------------------------------------------------------------
describe("Sound : fichiers livres et packaging", function()
    local ns = wowenv.loadCore()
    local Sound = ns.Sound

    it("liste les QUATRE sons livres dans le .toc (un son non liste n'est pas charge)", function()
        local entries = wowenv.tocEntries()
        for index = 1, #Sound.ALL_FILE_NAMES do
            local file = Sound.ALL_FILE_NAMES[index]
            local expected = "Sound/" .. file
            local found = false
            for entry = 1, #entries do
                if entries[entry] == expected then
                    found = true
                end
            end
            assert.is_true(found, expected .. " doit etre liste dans GideonRaid.toc")
        end
        -- Le son de DEBUT d'intermission est bien liste lui aussi : sans entree au
        -- .toc, le client ne le charge pas et PlaySoundFile echoue en silence.
        assert.is_true(#entries >= 14, "le .toc doit lister 11 fichiers lua + 4 sons")
        -- Le chemin CLIENT et l'entree du .toc decrivent le meme fichier.
        assert.are.equal("Interface\\AddOns\\GideonRaid\\" .. "Sound\\assign-1v3r.ogg", Sound.pathFor("1V3R"))
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\intermission-start.ogg", Sound.startPath())
    end)

    it("les fichiers livres existent sur disque et sont de vrais Ogg Vorbis", function()
        for index = 1, #Sound.ALL_FILE_NAMES do
            local file = Sound.ALL_FILE_NAMES[index]
            local exists, size, content = fileExists("Sound/" .. file)
            assert.is_true(exists, "Sound/" .. file .. " est absent du depot")
            assert.is_true(size > 0, "Sound/" .. file .. " est vide")
            assert.are.equal("OggS", content:sub(1, 4), "Sound/" .. file .. " n'est pas un fichier Ogg")
        end
    end)

    it("les noms livres sont en minuscules, sans accent ni espace", function()
        for index = 1, #Sound.ALL_FILE_NAMES do
            local file = Sound.ALL_FILE_NAMES[index]
            assert.is_truthy(file:match("^[a-z0-9%.%-]+$") ~= nil, file .. " : nom non conforme")
            assert.are.equal(file:lower(), file, file)
        end
    end)

    it("rien dans .pkgmeta n'exclut Sound/ du zip BigWigs", function()
        local ignores = pkgmetaIgnores()
        -- Le parseur lit bien le bloc ignore: du .pkgmeta (tests/, tools/...).
        assert.is_true(#ignores >= 8, "bloc ignore: illisible dans .pkgmeta")
        local sawTests = false
        for index = 1, #ignores do
            local entry = ignores[index]
            if entry == "tests" then
                sawTests = true
            end
            assert.is_false(entry == "Sound" or entry:match("^Sound/") ~= nil, ".pkgmeta exclut le dossier des sons : " .. entry)
        end
        assert.is_true(sawTests, "le bloc ignore: n'a pas ete lu correctement")
    end)
end)

-- ---------------------------------------------------------------------------
-- 3. Cablage : commandes, flux reel, repetition, robustesse
-- ---------------------------------------------------------------------------
describe("Sound : preference persistee et commandes /gideon sound", function()
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
        stub.install()
        ns = wowenv.loadAddon()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    it("active le son par defaut et materialise la preference dans les SavedVariables", function()
        assert.is_true(_G.GideonRaidDB.intermission.soundEnabled)
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound")
        assert.is_true(contains(messages(), "Assignment sound: enabled"))
        assert.is_true(contains(messages(), "/gideon sound test 1v3r|2v2r|3v1r"))
    end)

    it("/gideon sound off puis on persiste la valeur et l'affiche", function()
        _G.SlashCmdList["GIDEONRAID"]("sound off")
        assert.is_false(_G.GideonRaidDB.intermission.soundEnabled)
        assert.is_true(contains(messages(), "Assignment sound = disabled"))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound")
        assert.is_true(contains(messages(), "Assignment sound: disabled"))
        _G.SlashCmdList["GIDEONRAID"]("sound ON")
        assert.is_true(_G.GideonRaidDB.intermission.soundEnabled)
        assert.is_true(contains(messages(), "Assignment sound = enabled"))
    end)

    it("REFUSE une valeur inconnue sans rien persister (meme mecanique que /gideon lang)", function()
        _G.SlashCmdList["GIDEONRAID"]("sound off")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound yes")
        assert.is_true(contains(messages(), "Unknown value 'yes'"))
        assert.is_false(_G.GideonRaidDB.intermission.soundEnabled, "rien ne doit etre ecrit")
        _G.SlashCmdList["GIDEONRAID"]("sound test 1v3r") -- 'test' + etat n'est PAS une valeur de bascule
        assert.is_false(_G.GideonRaidDB.intermission.soundEnabled)
    end)

    it("migre en douceur une sauvegarde sans le champ (son actif)", function()
        _G.GideonRaidDB.intermission.soundEnabled = nil
        assert.is_true(ns.Config.resolveIntermission(_G.GideonRaidDB.intermission).soundEnabled)
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound")
        assert.is_true(contains(messages(), "Assignment sound: enabled"))
    end)

    it("/gideon sound test joue le son demande et dit lequel", function()
        _G.SlashCmdList["GIDEONRAID"]("sound test 2v2r")
        assert.are.equal(1, #stub.sounds)
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-2v2r.ogg", stub.sounds[1].path)
        assert.are.equal("Master", stub.sounds[1].channel)
        assert.is_true(contains(messages(), "Sound test: 2V2R (assign-2v2r.ogg)"))
        -- Rejouable autant de fois que voulu, et independant de la garde
        -- d'assignation.
        _G.SlashCmdList["GIDEONRAID"]("sound test 1v3r")
        _G.SlashCmdList["GIDEONRAID"]("sound test 1v3r")
        assert.are.equal(3, #stub.sounds)
    end)

    it("/gideon sound test refuse un etat inconnu SANS jouer, et respecte la preference off", function()
        _G.SlashCmdList["GIDEONRAID"]("sound test bidon")
        assert.are.equal(0, #stub.sounds, "aucun son ne doit partir")
        assert.is_true(contains(messages(), "Unknown sound 'bidon'"))
        _G.SlashCmdList["GIDEONRAID"]("sound test")
        assert.is_true(contains(messages(), "Assignment sound: enabled"), "/gideon sound test seul rappelle l'etat")
        _G.SlashCmdList["GIDEONRAID"]("sound off")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound test 3v1r")
        assert.are.equal(0, #stub.sounds)
        assert.is_true(contains(messages(), "disabled: /gideon sound on"))
    end)

    it("documente /gideon sound dans l'aide", function()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        assert.is_true(contains(messages(), "/gideon sound [on|off] | /gideon sound test 1v3r|2v2r|3v1r"))
    end)

    it("dit si PlaySoundFile ne peut pas jouer le fichier (sans lever)", function()
        _G.PlaySoundFile = nil
        _G.SlashCmdList["GIDEONRAID"]("sound test 1v3r")
        assert.is_true(contains(messages(), "could not be played"))
        _G.PlaySoundFile = function()
            error("PlaySoundFile a leve")
        end
        _G.SlashCmdList["GIDEONRAID"]("sound test 1v3r")
        assert.is_true(contains(messages(), "could not be played"))
    end)
end)

describe("Sound : le son part au clic, une seule fois", function()
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
        stub.install()
        ns = wowenv.loadAddon()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    --- Le bouton d'IMAGE d'une composition : l'ordre VERTICAL est fige par Core
    --- (3V1R en haut, 2V2R au milieu, 1V3R en bas). Un test ne passe JAMAIS par un
    --- index en dur : c'est ce qui garantit que le clic declara bien ce que le
    --- joueur voit sous son doigt.
    local function buttonFor(panel, stateKey)
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            if ns.Layout.INTERMISSION_CHOICE_ORDER[index] == stateKey then
                return panel.buttons[index]
            end
        end
        return nil
    end

    --- Le mot affiche par le panneau (l'une des deux FontStrings du mot).
    local function shownWord(panel)
        if panel.wordBig:IsShown() then
            return panel.wordBig:GetText()
        end
        return panel.word:GetText()
    end

    it("AUCUN son ne part tout seul : ouverture, re-rendu et fermeture sont silencieux", function()
        -- Regle en jeu (raid lead) : « le son ne doit s'activer seulement quand on
        -- clique sur un des boutons ». Le son de debut d'intermission reste dans le
        -- paquet (et /gideon sound test start le joue a la demande) mais PLUS AUCUNE
        -- lecture automatique n'existe.
        pullTargetBoss()
        stub.fireTickers(450) -- ouverture automatique avant la 1re intermission
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.are.equal(0, #stub.sounds, "l'ouverture automatique doit etre silencieuse")
        assert.are.equal(0, #startSounds(), "le son de debut ne part plus a l'ouverture")
        -- Un re-rendu (changement de langue, tick) ne joue rien non plus.
        _G.SlashCmdList["GIDEONRAID"]("lang fr")
        stub.fireTickers(30)
        assert.are.equal(0, #stub.sounds)
        -- La fermeture (croix) est silencieuse.
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
        assert.are.equal(0, #stub.sounds, "la fermeture doit etre silencieuse")
        assert.are.equal(0, #startSounds())
    end)

    it("flux reel : aucun son d'assignation avant la declaration, puis UNE fois le bon fichier", function()
        pullTargetBoss()
        stub.fireTickers(450) -- le panneau s'ouvre avant la 1re intermission
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.are.equal(0, #assignSounds(), "aucun son tant qu'aucune composition n'est declaree")

        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(1, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-1v3r.ogg", assignSounds()[1].path)
        assert.are.equal("Master", assignSounds()[1].channel)
        assert.are.equal("Ping", shownWord(panel))

        -- Ni les ticks du panneau, ni un re-rendu ne rejouent quoi que ce soit.
        stub.fireTickers(30)
        assert.are.equal(1, #assignSounds(), "pas de double lecture")

        -- Redeclarer la MEME composition (commande, sans CORRIGER) ne rejoue pas.
        _G.SlashCmdList["GIDEONRAID"]("inter 1V3R")
        assert.are.equal(1, #assignSounds())

        -- Une AUTRE composition est un nouveau choix : son son part.
        _G.SlashCmdList["GIDEONRAID"]("inter 3V1R")
        assert.are.equal(2, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-3v1r.ogg", assignSounds()[2].path)
        assert.are.equal(ns.Locale.t("state.word.3V1R"), shownWord(panel))
    end)

    it("CORRIGER puis recliquer rejoue le son de la nouvelle composition", function()
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(1, #assignSounds())
        panel.redo:Click() -- CORRIGER
        assert.are.equal(1, #assignSounds(), "CORRIGER ne joue aucun son")
        buttonFor(panel, "2V2R"):Click()
        assert.are.equal(2, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-2v2r.ogg", assignSounds()[2].path)
        -- La MEME composition apres CORRIGER est un nouveau choix : elle rejoue.
        panel.redo:Click()
        buttonFor(panel, "2V2R"):Click()
        assert.are.equal(3, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-2v2r.ogg", assignSounds()[3].path)
    end)

    it("rejoue a l'intermission SUIVANTE (la garde est rearmee)", function()
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "3V1R"):Click() -- 1re intermission
        assert.are.equal(1, #assignSounds())
        stub.fireTickers(260) -- fin de l'intermission : fermeture automatique
        assert.is_false(panel:IsShown())
        stub.fireTickers(760) -- 2e intermission : reouverture
        assert.is_true(panel:IsShown())
        buttonFor(panel, "3V1R"):Click() -- la MEME composition, nouvelle intermission
        assert.are.equal(2, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-3v1r.ogg", assignSounds()[2].path)
        -- ... et AUCUN son de debut n'a accompagne les deux intermissions : plus
        -- aucune lecture automatique (regle en jeu du raid lead).
        assert.are.equal(0, #startSounds())
    end)

    it("repetition /gideon sim inter : silencieuse, puis le son du bouton clique", function()
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.are.equal(0, #assignSounds(), "la repetition ne joue rien avant le clic")
        assert.are.equal(0, #startSounds(), "plus de son de debut a l'ouverture d'une repetition")
        assert.are.equal(0, #stub.sounds)
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(1, #assignSounds())
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\assign-1v3r.ogg", assignSounds()[1].path)
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision, "une repetition ne publie rien")
        assert.are.equal("Ping", shownWord(panel))
        -- Les trois choix sont masques apres le clic : un clic force sur un bouton
        -- cache ne double pas la lecture (la garde d'assignation tient).
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(1, #assignSounds())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        -- Une NOUVELLE repetition rearme la garde : le meme clic rejoue son son,
        -- toujours SANS aucune lecture automatique.
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        buttonFor(_G.GideonRaidIntermissionPanel, "1V3R"):Click()
        assert.are.equal(2, #assignSounds())
        assert.are.equal(0, #startSounds())
    end)

    it("preference off : le clic ne joue plus rien, le rendu reste complet", function()
        _G.SlashCmdList["GIDEONRAID"]("sound off")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(0, #stub.sounds, "son coupe = silence")
        -- Le rendu reste COMPLET : un seul mot, celui de la composition cliquee.
        assert.are.equal(ns.Locale.t("state.word.1V3R"), shownWord(panel))
        assert.is_true(panel.word:IsShown())
        assert.is_true(panel.redo:IsShown())
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            assert.is_false(panel.buttons[index]:IsShown(), "les images disparaissent apres le clic")
        end
        -- /gideon inter status rapporte l'etat du reglage.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        assert.is_true(contains(messages(), "assignment sound: disabled"))
    end)

    it("survit a un PlaySoundFile qui leve : la declaration et le rendu continuent", function()
        _G.PlaySoundFile = function()
            error("PlaySoundFile a leve")
        end
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "2V2R"):Click()
        assert.are.equal(ns.Locale.t("state.word.2V2R"), shownWord(panel))
        assert.is_true(panel.wordBig:IsShown())
        assert.is_false(panel.buttons[1]:IsShown())
        -- ... et le flux continue : CORRIGER, puis un autre choix.
        panel.redo:Click()
        buttonFor(panel, "3V1R"):Click()
        assert.are.equal(ns.Locale.t("state.word.3V1R"), shownWord(panel))
    end)

    it("survit a un PlaySoundFile absent (harnais hors client)", function()
        _G.PlaySoundFile = nil
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "3V1R"):Click()
        assert.are.equal(ns.Locale.t("state.word.3V1R"), shownWord(panel))
        assert.is_true(panel.word:IsShown())
    end)
end)
