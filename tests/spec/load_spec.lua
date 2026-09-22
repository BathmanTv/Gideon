--[[--------------------------------------------------------------------------
    tests/spec/load_spec.lua   (busted)
    ETAPE 2 du plan de test : l'addon se charge sans erreur, DANS L'ORDRE DU .TOC,
    et les evenements ADDON_LOADED / PLAYER_LOGIN / ENCOUNTER_START ne levent pas.

    Le chargement passe par wowenv.loadAddon() : la liste des fichiers vient du
    .toc lui-meme, donc un fichier oublie, renomme ou mal ordonne fait echouer ce
    fichier de test (c'est le bug n°1 des addons).
----------------------------------------------------------------------------]]
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

describe("chargement de l'addon", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.SlashCmdList = nil
        stub.install()

        -- Meme ordre que le client : celui du .toc.
        ns = wowenv.loadAddon()
    end)

    it("charge tous les fichiers listes dans le .toc, dans l'ordre", function()
        local files = wowenv.tocFiles()
        assert.are.equal(7, #files)
        assert.are.equal("GideonRaid.lua", files[1])
        -- Core/Locale.lua d'abord : la couche de langue est une dependance.
        assert.are.equal("Core/Locale.lua", files[2])
        assert.are.equal("Core/Config.lua", files[3])
        assert.are.equal("UI/Intermission.lua", files[7])
    end)

    it("expose toutes les couches attendues", function()
        assert.is_table(ns.Locale)
        assert.is_table(ns.Pairing)
        assert.is_table(ns.Config)
        assert.is_table(ns.Intermission)
        assert.is_table(ns.UI)
        assert.is_table(ns.GR)
    end)

    it("ADDON_LOADED initialise les SavedVariables", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_table(_G.GideonRaidDB)
        assert.is_true(_G.GideonRaidDB.enabled)
        assert.is_table(_G.GideonRaidCharDB)
        assert.is_table(_G.GideonRaidDB.intermission)
    end)

    it("ADDON_LOADED ignore les autres addons", function()
        stub.mainFrame():Fire("ADDON_LOADED", "UnAutreAddon")
        assert.is_nil(_G.GideonRaidDB)
    end)

    it("PLAYER_LOGIN sans assignation n'echoue pas", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("PLAYER_LOGIN")
        assert.is_true(true)
    end)

    it("PLAYER_LOGIN affiche le plan si l'assignation existe", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidDB.assignment = {
            schema = 1,
            pairs = { { a = "Testeur", b = "Partenaire" } },
            plan = {
                { name = "Testeur", role = "2V2R", position = "MIDDLE" },
                { name = "Partenaire", role = "2V2R", position = "MIDDLE" },
            },
        }
        stub.mainFrame():Fire("PLAYER_LOGIN")
        local text = _G.GideonRaidPanel.body:GetText()
        assert.matches("Partenaire", text)
        assert.matches("Your partner", text)
        assert.matches("MIDDLE", text)
        assert.matches("2V2R%+2V2R", text)
    end)

    it("le slash handler repond et ne leve pas", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("show")
        _G.SlashCmdList["GIDEONRAID"]("status")
        _G.SlashCmdList["GIDEONRAID"]("plan")
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        local msgs = _G.DEFAULT_CHAT_FRAME.messages
        assert.is_truthy(#msgs >= 1)
    end)

    it("ENCOUNTER_START lance l'intermission sans lire ses arguments", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START", 1234, "Entombed Sentinels", 16, 20)
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.matches("LOOK AT THE ORB COLOR", panel.headline:GetText())
    end)

    it("le clic sur un bouton du panneau affiche la consigne", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        -- Les boutons sont les TROIS etats de couleur, dans l'ordre deterministe
        -- 1V3R / 2V2R / 3V1R : le bouton 2 est donc 2V2R.
        assert.matches("2 green %+ 2 red", panel.buttons[2]:GetText())
        assert.matches("1 or 3", panel.buttons[1]:GetText())
        assert.matches("2 green %+ 2 red", panel.buttons[2]:GetText())
        assert.matches("1 or 3", panel.buttons[3]:GetText())
        panel.buttons[2]:Click()
        local text = panel.body:GetText()
        assert.matches("YOU SEE: 2 GREEN %+ 2 RED", text)
        assert.matches("MIDDLE", text)
        -- Politique par defaut ("anchors") : le MILIEU ne ping pas -> banniere
        -- PING: NO et AUCUNE macro proposee (la zone macro est masquee).
        assert.are.equal("PING: NO", panel.pingBanner:GetText())
        assert.is_true(panel.pingBanner:IsShown())
        assert.is_false(panel.macroBox:IsShown())
        assert.matches("PING: NO %- the MIDDLE does not ping", text)
        assert.are.equal("", panel.macroBox:GetText())
        assert.matches("No ping for this role", panel.note:GetText())
    end)

    it("/gr ping color fait apparaitre la macro du MILIEU", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping color")
        assert.equals("color", _G.GideonRaidDB.intermission.pingMode)
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[2]:Click() -- 2V2R
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        assert.matches("C_Ping%.SendMacroPing", panel.macroBox:GetText())
        assert.matches("OnMyWay", panel.macroBox:GetText())
        assert.is_true(panel.macroBox:IsShown())
    end)

    it("/gr ping none masque la macro meme pour une ANCRE", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping none")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click() -- 1V3R = ANCRE
        assert.are.equal("PING: NO", panel.pingBanner:GetText())
        assert.are.equal("", panel.macroBox:GetText())
        assert.is_false(panel.macroBox:IsShown())
        assert.matches("PING POLICY: NONE", panel.body:GetText())
    end)

    it("/gr ping refuse une valeur inconnue et n'ecrit rien", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping magenta")
        assert.equals("anchors", _G.GideonRaidDB.intermission.pingMode)
        local messages = table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
        assert.matches("Unknown ping policy", messages)
    end)

    it("les trois boutons portent le numero affiche en indice", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("1 green %+ 3 red", panel.buttons[1]:GetText())
        assert.matches("1V3R", panel.buttons[1]:GetText())
        assert.matches("3 green %+ 1 red", panel.buttons[3]:GetText())
        assert.matches("3V1R", panel.buttons[3]:GetText())
    end)

    it("publie la decision du joueur dans les SavedVariables (lue par le kit diag)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[3]:Click() -- 3V1R
        local decision = _G.GideonRaidDB.intermission.lastDecision
        assert.is_not_nil(decision)
        assert.equals("3V1R", decision.composition)
        assert.equals(1758500000, decision.at)
        assert.equals("2026-09-22 21:00:00", decision.clock)
        assert.equals("coach-panel", decision.source)
    end)

    it("une declaration ambigue n'est ni acceptee ni publiee (aucune saisie de chat)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        _G.SlashCmdList["GIDEONRAID"]("inter 1")
        local messages = table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
        assert.matches("ambiguous", messages)
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision)
    end)

    it("le ticker fait basculer la salle en obscurci apres 3 s", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("LOOK AT THE ORB COLOR", panel.headline:GetText())
        -- 35 ticks de 0,1 s = 3,5 s : au-dela de la fenetre de 3 s.
        stub.fireTickers(35)
        assert.matches("DARKENED", panel.headline:GetText())
    end)

    it("ENCOUNTER_END ferme le panneau", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.mainFrame():Fire("ENCOUNTER_END")
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
    end)

    it("respecte la desactivation du module", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter off")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        local messages = _G.DEFAULT_CHAT_FRAME.messages
        assert.matches("disabled", messages[#messages])
    end)

    it("le panneau reste lisible et n'affiche aucune valeur dynamique", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local text = _G.GideonRaidIntermissionPanel.body:GetText()
        assert.is_nil(string.find(text, "UnitHealth", 1, true))
        assert.is_nil(string.find(text, "UnitAura", 1, true))
    end)
end)
