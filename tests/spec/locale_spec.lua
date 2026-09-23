--[[--------------------------------------------------------------------------
    tests/spec/locale_spec.lua   (busted)
    Tests HORS JEU de la COUCHE DE LANGUE :

      1. Core/Locale.lua (pure) : Locale.resolve, Locale.t, Locale.format ;
         l'anglais est la langue OFFICIELLE (defaut), le francais est servi
         automatiquement sur un client frFR, et rien ne leve jamais ;
      2. le cablage (GideonRaid.lua) : detection GetLocale(), preference
         persistee (GideonRaidDB.locale) et commande en jeu /gr lang.

    Aucun mock d'API de combat : GetLocale est la SEULE API appelee, par le
    cablage uniquement (Core/ reste pur).
----------------------------------------------------------------------------]]
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

describe("Locale : resolution de la langue (pure)", function()
    local L = wowenv.loadCore().Locale

    it("a l'anglais comme langue officielle par defaut", function()
        assert.are.equal("en", L.DEFAULT)
        assert.are.equal("en", L.getActive())
        assert.are.equal("en", L.resolve(nil, nil))
        assert.are.equal("en", L.resolve("auto", nil))
    end)

    it("suit le client quand la preference est auto ou nil", function()
        assert.are.equal("fr", L.resolve("auto", "frFR"))
        assert.are.equal("fr", L.resolve(nil, "frFR"))
        assert.are.equal("en", L.resolve("auto", "enUS"))
        assert.are.equal("fr", L.normalizeLanguage("frFR"))
        assert.are.equal("en", L.normalizeLanguage("enUS"))
        assert.is_nil(L.normalizeLanguage("deDE"))
        assert.is_nil(L.normalizeLanguage(nil))
    end)

    it("un override explicite gagne sur la detection", function()
        assert.are.equal("fr", L.resolve("fr", "enUS"))
        assert.are.equal("en", L.resolve("en", "frFR"))
    end)

    it("retombe sur l'anglais pour toute valeur inconnue", function()
        assert.are.equal("en", L.resolve("auto", "deDE"))
        assert.are.equal("en", L.resolve("auto", 42))
        assert.are.equal("en", L.resolve("deDE", "enUS"))
        assert.are.equal("en", L.resolve("", nil))
        assert.are.equal("en", L.resolve(true, "frFR"))
    end)
end)

describe("Locale : traductions", function()
    local ns = wowenv.loadCore()
    local L = ns.Locale

    it("sert la variante anglaise par defaut et la francaise sur demande", function()
        assert.are.equal("Close", L.t("ui.close"))
        assert.are.equal("Fermer", L.t("ui.close", "fr"))
        -- Un code client complet ("frFR") est accepte aussi.
        assert.are.equal("Fermer", L.t("ui.close", "frFR"))
        assert.are.equal("ROLE: %s", L.t("ui.roleLine", "en"))
        assert.are.equal("ROLE : %s", L.t("ui.roleLine", "fr"))
    end)

    it("sert la langue disponible quand la cle n'existe que dans l'autre", function()
        L.STRINGS["spec.only_fr"] = { fr = "seulement en francais" }
        assert.are.equal("seulement en francais", L.t("spec.only_fr", "en"))
        L.STRINGS["spec.only_fr"] = nil
    end)

    it("renvoie la cle elle-meme si elle n'existe pas (jamais d'erreur)", function()
        assert.are.equal("spec.unknown.key", L.t("spec.unknown.key"))
        assert.are.equal("spec.unknown.key", L.t("spec.unknown.key", "fr"))
        assert.are.equal("spec.unknown.key", L.format("spec.unknown.key", 1, 2))
        assert.are.equal("true", L.t(true))
    end)

    it("Locale.format est total : jamais d'erreur, meme sans argument", function()
        assert.are.equal("Close", L.format("ui.close"))
        -- Placeholders sans argument : le gabarit est renvoye tel quel.
        assert.are.equal("timeline: %d s visible, %d s in total, scale %.2f", L.format("ui.timelineLine"))
        assert.are.equal("PING: %s - press %s", L.format("ping.press"))
        assert.are.equal("PING: Warning - press Q", L.format("ping.press", "Warning", "Q"))
    end)

    it("sert TOUTES les cles dans les deux langues (aucun trou de traduction)", function()
        local missing = {}
        for key, entry in pairs(L.STRINGS) do
            assert.is_string(entry.en, key .. " (en)")
            assert.is_string(entry.fr, key .. " (fr)")
            if entry.en == "" or entry.fr == "" then
                missing[#missing + 1] = key
            end
        end
        assert.are.same({}, missing)
    end)

    it("setActive accepte les langues servies et retombe sur l'anglais", function()
        assert.are.equal("fr", L.setActive("fr"))
        assert.are.equal("fr", L.getActive())
        assert.are.equal("Fermer", L.t("ui.close"))
        assert.are.equal("en", L.setActive("deDE"))
        assert.are.equal("Close", L.t("ui.close"))
        assert.are.equal("en", L.setActive(nil))
    end)

    it("est deterministe : memes entrees, memes chaines", function()
        local function snapshot()
            return {
                L.t("state.display.3V1R"),
                L.t("state.display.3V1R", "fr"),
                L.t("ui.close", "frFR"),
                L.resolve("auto", "frFR"),
            }
        end
        assert.are.same(snapshot(), snapshot())
    end)
end)

describe("Langue : detection du client, preference persistee et /gr lang", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.SlashCmdList = nil
        _G.GetBindingKey = nil
        stub.install()
        ns = wowenv.loadAddon()
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    it("est en anglais par defaut (langue officielle)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.are.equal("auto", _G.GideonRaidDB.locale)
        assert.are.equal("enUS", _G.GideonRaid.detectedLocale)
        assert.are.equal("en", _G.GideonRaid.locale)
        assert.are.equal("en", ns.Locale.getActive())
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("GET READY", panel.headline:GetText())
        -- Fermer est toujours la ; CORRIGER n'apparait qu'apres un clic (la
        -- disposition ne montre que ce qui est utile dans la phase en cours).
        assert.matches("Close", panel.close:GetText())
        assert.matches("1 green %+ 3 red", panel.buttons[1]:GetText())
        panel.buttons[1]:Click()
        assert.matches("REDO", panel.redo:GetText())
        assert.matches("PING: YES", panel.pingBanner:GetText())
    end)

    it("sert le francais automatiquement sur un client frFR", function()
        _G.GetLocale = function()
            return "frFR"
        end
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.are.equal("fr", _G.GideonRaid.locale)
        assert.are.equal("auto", _G.GideonRaidDB.locale)
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_truthy(string.find(panel.headline:GetText(), "TIENS-TOI PRET", 1, true))
        assert.matches("Fermer", panel.close:GetText())
        assert.matches("1 vert %+ 3 rouges", panel.buttons[1]:GetText())
        panel.buttons[1]:Click()
        assert.matches("CORRIGER", panel.redo:GetText())
        assert.matches("PING : OUI", panel.pingBanner:GetText())
    end)

    it("sert l'anglais sur un client enUS et sur toute autre locale", function()
        for _, code in ipairs({ "enUS", "deDE", "esES" }) do
            _G.GetLocale = function()
                return code
            end
            stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
            assert.are.equal("en", _G.GideonRaid.locale, code)
            assert.are.equal(code, _G.GideonRaid.detectedLocale, code)
        end
    end)

    it("survit a un GetLocale absent (harnais hors client)", function()
        _G.GetLocale = nil
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_nil(_G.GideonRaid.detectedLocale)
        assert.are.equal("en", _G.GideonRaid.locale)
    end)

    it("/gr lang affiche la langue detectee, la langue effective et la regle", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("lang")
        local text = messages()
        assert.matches("client detected = enUS", text)
        assert.matches("effective = en", text)
        assert.matches("preference = auto", text)
        assert.matches("/gr lang auto|en|fr", text)
    end)

    it("/gr lang fr persiste la preference et bascule le panneau en francais", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("lang fr")
        assert.are.equal("fr", _G.GideonRaidDB.locale)
        assert.are.equal("fr", _G.GideonRaid.locale)
        assert.matches("langue effective = fr", messages())
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_truthy(string.find(panel.headline:GetText(), "TIENS-TOI PRET", 1, true))
        assert.matches("Fermer", panel.close:GetText())
    end)

    it("/gr lang en gagne sur un client frFR", function()
        _G.GetLocale = function()
            return "frFR"
        end
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("lang en")
        assert.are.equal("en", _G.GideonRaidDB.locale)
        assert.are.equal("en", _G.GideonRaid.locale)
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        assert.matches("GET READY", _G.GideonRaidIntermissionPanel.headline:GetText())
    end)

    it("/gr lang auto revient a la langue du client", function()
        _G.GetLocale = function()
            return "frFR"
        end
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("lang en")
        _G.SlashCmdList["GIDEONRAID"]("lang auto")
        assert.are.equal("auto", _G.GideonRaidDB.locale)
        assert.are.equal("fr", _G.GideonRaid.locale)
    end)

    it("/gr lang avec une valeur inconnue est refuse et ne persiste rien", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("lang deDE")
        assert.are.equal("auto", _G.GideonRaidDB.locale)
        assert.are.equal("en", _G.GideonRaid.locale)
        assert.matches("Unknown language", messages())
    end)

    it("ne devine jamais une preference incoherente : repli sur auto", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidDB.locale = "Klingon"
        _G.SlashCmdList["GIDEONRAID"]("lang")
        assert.are.equal("auto", _G.GideonRaid.localePreference)
        assert.are.equal("en", _G.GideonRaid.locale)
        assert.matches("preference = auto", messages())
    end)
end)
