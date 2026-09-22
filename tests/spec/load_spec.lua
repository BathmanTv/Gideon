--[[--------------------------------------------------------------------------
    tests/spec/load_spec.lua   (busted)
    ETAPE 2 du plan de test : l'addon se charge sans erreur, dans l'ordre du
    .toc, et les evenements ADDON_LOADED / PLAYER_LOGIN ne levent pas.
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
        stub.install()

        -- Reproduit l'ordre du .toc.
        ns = wowenv.newNamespace()
        wowenv.load("GideonRaid.lua", ns)
        wowenv.load("Core/Config.lua", ns)
        wowenv.load("Core/Pairing.lua", ns)
        wowenv.load("UI/Panel.lua", ns)
    end)

    it("expose toutes les couches attendues", function()
        assert.is_table(ns.Pairing)
        assert.is_table(ns.Config)
        assert.is_table(ns.UI)
        assert.is_table(ns.GR)
    end)

    it("ADDON_LOADED initialise les SavedVariables", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_table(_G.GideonRaidDB)
        assert.is_true(_G.GideonRaidDB.enabled)
        assert.is_table(_G.GideonRaidCharDB)
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

    it("PLAYER_LOGIN affiche le partenaire si l'assignation existe", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidDB.assignment = {
            schema = 1,
            pairs = { { a = "Testeur", b = "Partenaire" } },
        }
        stub.mainFrame():Fire("PLAYER_LOGIN")
        assert.matches("Partenaire", _G.GideonRaidPanel.body:GetText())
    end)

    it("le slash handler repond et ne leve pas", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("show")
        _G.SlashCmdList["GIDEONRAID"]("status")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        local msgs = _G.DEFAULT_CHAT_FRAME.messages
        assert.is_truthy(#msgs >= 1)
    end)
end)
