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
        assert.are.equal(6, #files)
        assert.are.equal("GideonRaid.lua", files[1])
        assert.are.equal("Core/Config.lua", files[2])
        assert.are.equal("UI/Intermission.lua", files[6])
    end)

    it("expose toutes les couches attendues", function()
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
        assert.matches("Ton partenaire", text)
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
        assert.matches("REGARDE", panel.headline:GetText())
    end)

    it("le clic sur un bouton du panneau affiche la consigne", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        -- Les boutons sont les TROIS etats de couleur, dans l'ordre deterministe
        -- 1V3R / 2V2R / 3V1R : le bouton 2 est donc 2V2R.
        assert.matches("2 verts %+ 2 rouges", panel.buttons[2]:GetText())
        assert.matches("1 ou 3", panel.buttons[1]:GetText())
        assert.matches("2 verts %+ 2 rouges", panel.buttons[2]:GetText())
        assert.matches("1 ou 3", panel.buttons[3]:GetText())
        panel.buttons[2]:Click()
        local text = panel.body:GetText()
        assert.matches("TU VOIS : 2 VERTS %+ 2 ROUGES", text)
        assert.matches("MILIEU", text)
        assert.matches("PING A ENVOYER : BLEU", text)
        assert.matches("C_Ping%.SendMacroPing", panel.macroBox:GetText())
    end)

    it("les trois boutons portent le numero affiche en indice", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("1 vert %+ 3 rouges", panel.buttons[1]:GetText())
        assert.matches("1V3R", panel.buttons[1]:GetText())
        assert.matches("3 verts %+ 1 rouge", panel.buttons[3]:GetText())
        assert.matches("3V1R", panel.buttons[3]:GetText())
    end)

    it("le ticker fait basculer la salle en obscurci apres 3 s", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("REGARDE", panel.headline:GetText())
        -- 35 ticks de 0,1 s = 3,5 s : au-dela de la fenetre de 3 s.
        stub.fireTickers(35)
        assert.matches("OBSCUR", panel.headline:GetText())
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
        assert.matches("desactive", messages[#messages])
    end)

    it("le panneau reste lisible et n'affiche aucune valeur dynamique", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local text = _G.GideonRaidIntermissionPanel.body:GetText()
        assert.is_nil(string.find(text, "UnitHealth", 1, true))
        assert.is_nil(string.find(text, "UnitAura", 1, true))
    end)
end)
