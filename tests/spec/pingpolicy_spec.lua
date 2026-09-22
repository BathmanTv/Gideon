--[[--------------------------------------------------------------------------
    tests/spec/pingpolicy_spec.lua   (busted)

    Tests HORS JEU de la POLITIQUE DE PING et des ROLES PAR ETAT.

    Decision du raid lead : un etat canonique (1V3R / 2V2R / 3V1R) ne porte plus
    un « role par numero » mais un ROLE :
      - 1V3R = ANCRE  (ANCHOR) : sur place, ping (macro) ou se fait pinger ;
      - 2V2R = MILIEU (MID)    : milieu / sous le boss, s'apparie a un 2V2R ;
      - 3V1R = CHASSEUR (CHASER) : fonce sur un ping, ne ping pas.
    La politique de ping est CONFIGURABLE (GideonRaidDB.intermission.pingMode,
    commande /gr ping) :
      - "anchors" (defaut) : seule l'ANCRE ping (~8 pings par raid au lieu de ~20) ;
      - "color"            : chaque etat ping de sa propre couleur (guide raidstrats) ;
      - "none"             : personne ne ping, on joue en positions.
    La logique testee ici est PURE (Core/), puis le cablage en jeu (/gr ping).
----------------------------------------------------------------------------]]
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

describe("Ping : politiques (logique pure)", function()
    local ns = wowenv.loadCore()
    local I, Config = ns.Intermission, ns.Config

    it("expose les TROIS politiques et la meme liste que Config (aucune derive)", function()
        assert.are.same({ "anchors", "color", "none" }, I.PING_MODES)
        assert.are.same(Config.PING_MODES, I.PING_MODES)
        assert.are.equal("anchors", I.DEFAULT_PING_MODE)
        assert.are.equal("anchors", Config.DEFAULT_PING_MODE)
    end)

    it("resout toute valeur inconnue vers « anchors », sans jamais lever", function()
        assert.are.equal("anchors", Config.resolvePingMode("anchors"))
        assert.are.equal("anchors", Config.resolvePingMode("ANCHORS"))
        assert.are.equal("color", Config.resolvePingMode("Color"))
        assert.are.equal("none", Config.resolvePingMode("NONE"))
        for _, bad in ipairs({ "", "magenta", "colours", "aucun", "3" }) do
            assert.are.equal("anchors", Config.resolvePingMode(bad), tostring(bad))
        end
        assert.are.equal("anchors", Config.resolvePingMode(nil))
        assert.are.equal("anchors", Config.resolvePingMode(42))
        assert.are.equal("anchors", Config.resolvePingMode(true))
        assert.are.equal("anchors", Config.resolvePingMode({}))
        assert.are.equal("anchors", I.resolvePingMode("n'importe quoi"))
        local line, mode = I.pingPolicyLine("bidon")
        assert.are.equal("anchors", mode)
        assert.matches("ANCHORS", line)
    end)

    it("porte un ROLE explicite par etat, jamais deduit du numero", function()
        assert.are.equal("ANCHOR", I.getDeclaration("1V3R").role)
        assert.are.equal("MID", I.getDeclaration("2V2R").role)
        assert.are.equal("CHASER", I.getDeclaration("3V1R").role)
        assert.are.equal("ANCHOR", I.ROLE_BY_STATE["1V3R"])
        assert.are.equal("MID", I.ROLE_BY_STATE["2V2R"])
        assert.are.equal("CHASER", I.ROLE_BY_STATE["3V1R"])
        assert.are.equal("ANCHOR", I.ROLES.ANCHOR)
        -- Le role ne depend PAS de la politique : seuls le ping et la consigne
        -- operationnelle en dependent.
        for _, mode in ipairs(I.PING_MODES) do
            assert.are.equal("ANCHOR", I.getDeclaration("1V3R", mode).role, mode)
            assert.are.equal("MID", I.getDeclaration("2V2R", mode).role, mode)
            assert.are.equal("CHASER", I.getDeclaration("3V1R", mode).role, mode)
        end
        -- Le numero reste un INDICE ambigu : il ne donne jamais le role.
        assert.is_true(I.getDeclaration("1V3R").numberAmbiguous)
        assert.are.same({ "1", "3" }, I.getDeclaration("3V1R").numbers)
    end)

    it("politique par defaut : SEULE l'ANCRE (1V3R) doit pinger", function()
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key) -- politique par defaut = "anchors"
            local expected = (key == "1V3R")
            assert.are.equal(expected, rec.shouldPing, key)
            assert.are.equal("anchors", rec.pingPolicy)
            assert.are.equal(expected and "YES" or "NO", rec.pingDecision)
            assert.are.equal(expected, I.shouldPing(key))
            assert.matches(expected and "ping yourself" or "does not ping", rec.pingLine)
        end
        assert.are.equal("ANCHOR", I.getDeclaration("1V3R").role)
        assert.are.equal("MID", I.getDeclaration("2V2R").role)
        assert.are.equal("CHASER", I.getDeclaration("3V1R").role)
    end)

    it("politique « color » : les trois etats ping avec LEUR couleur", function()
        local expected = {
            ["1V3R"] = { "RED", "Warning" },
            ["2V2R"] = { "BLUE", "OnMyWay" },
            ["3V1R"] = { "GREEN", "Assist" },
        }
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key, "color")
            assert.is_true(rec.shouldPing, key)
            assert.are.equal("YES", rec.pingDecision, key)
            assert.are.equal(expected[key][1], rec.pingColor, key)
            assert.are.equal(expected[key][2], rec.ping, key)
            assert.is_true(contains(rec.pingLine, expected[key][1]), key)
            assert.is_true(contains(rec.pingLine, expected[key][2]), key)
        end
    end)

    it("politique « none » : PERSONNE ne ping", function()
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key, "none")
            assert.is_false(rec.shouldPing, key)
            assert.are.equal("NO", rec.pingDecision, key)
            assert.are.equal("none", rec.pingPolicy, key)
        end
        assert.is_false(I.shouldPing("1V3R", "none"))
        assert.is_true(I.shouldPing("1V3R", "anchors"))
        assert.is_true(I.shouldPing("3V1R", "color"))
    end)

    it("consigne operationnelle de l'ANCRE : sur place, ping, ne bouge pas", function()
        local anchor = I.getDeclaration("1V3R") -- anchors
        assert.matches("STAY WHERE YOU ARE", anchor.roleOrder)
        assert.is_true(contains(anchor.roleOrder, "DO NOT MOVE"))
        assert.matches("ping", anchor.roleOrder)
        -- Un AUTRE joueur du raid peut pinger l'ancre : la consigne le dit.
        assert.is_true(contains(anchor.pingLine, "or let another player ping you"))
        assert.is_true(contains(anchor.pingLine, "you are the ANCHOR"))
        -- Sans ping (politique none), la consigne reste "ne bouge pas" et ne
        -- demande plus un ping impossible.
        local noPing = I.getDeclaration("1V3R", "none")
        assert.matches("STAY WHERE YOU ARE", noPing.roleOrder)
        assert.is_true(contains(noPing.roleOrder, "DO NOT MOVE"))
        assert.is_false(contains(noPing.roleOrder, "place a ping"))
        -- La ligne "rejoins" est adaptee : c'est l'autre etat qui rejoint l'ancre.
        assert.are.equal("3V1R", anchor.complement)
        assert.matches(
            "STATE THAT JOINS YOU: 3V1R",
            table.concat(
                I.snapshot({ phase = I.PHASE.VISIBLE, elapsed = 0, declaration = "1V3R", timeline = I.validateTimeline(nil) }).lines,
                "\n"
            )
        )
    end)

    it("consigne du CHASSEUR : ne ping pas, fonce sur un ping", function()
        local chaser = I.getDeclaration("3V1R") -- anchors
        assert.matches("Do NOT ping", chaser.roleOrder)
        assert.is_true(contains(chaser.roleOrder, "run to it"))
        assert.is_true(contains(chaser.roleOrder, "any 1V3R works"))
        assert.is_false(chaser.shouldPing)
        assert.are.equal("1V3R", chaser.complement)
        -- En politique color il ping AUSSI, mais garde sa course vers un ping.
        local colored = I.getDeclaration("3V1R", "color")
        assert.is_true(colored.shouldPing)
        assert.is_false(contains(colored.roleOrder, "Do NOT ping"))
        assert.is_true(contains(colored.roleOrder, "run to it"))
    end)

    it("consigne du MILIEU : ne ping pas, va au milieu et trouve un 2V2R", function()
        local mid = I.getDeclaration("2V2R") -- anchors
        assert.is_false(mid.shouldPing)
        assert.is_true(contains(mid.roleOrder, "Do NOT ping"))
        assert.is_true(contains(mid.roleOrder, "MIDDLE"))
        assert.is_true(contains(mid.roleOrder, "another 2V2R"))
        assert.are.equal("2V2R", mid.complement)
        assert.matches(
            "STATE TO JOIN: 2V2R",
            table.concat(
                I.snapshot({ phase = I.PHASE.VISIBLE, elapsed = 0, declaration = "2V2R", timeline = I.validateTimeline(nil) }).lines,
                "\n"
            )
        )
    end)

    it("sert les consignes en FRANCAIS quand la langue active est fr", function()
        local fr = wowenv.loadCore()
        fr.Locale.setActive("fr")
        local anchor = fr.Intermission.getDeclaration("1V3R")
        assert.are.equal("ANCRE", anchor.roleName)
        assert.matches("RESTE SUR PLACE", anchor.roleOrder)
        assert.is_true(contains(anchor.roleOrder, "NE BOUGE PAS"))
        assert.is_true(contains(anchor.roleOrder, "fais-toi pinger"))
        assert.are.equal("CHASSEUR", fr.Intermission.getDeclaration("3V1R").roleName)
        assert.is_true(contains(fr.Intermission.getDeclaration("3V1R").roleOrder, "fonce dessus"))
        assert.are.equal("MILIEU", fr.Intermission.getDeclaration("2V2R").roleName)
        assert.is_true(contains(fr.Intermission.getDeclaration("2V2R").roleOrder, "MILIEU"))
        assert.are.equal("OUI", fr.Intermission.getDeclaration("1V3R").pingDecision)
        assert.are.equal("NON", fr.Intermission.getDeclaration("2V2R").pingDecision)
    end)

    it("rappelle la politique courante dans le panneau, meme sans declaration", function()
        local snap = I.snapshot(I.newState(), "none")
        local text = table.concat(snap.lines, "\n")
        assert.matches("PING POLICY: NONE", text)
        assert.are.equal("none", snap.pingPolicy)
        local colored = I.snapshot(I.newState(), "color")
        assert.matches("PING POLICY: COLOR", table.concat(colored.lines, "\n"))
    end)
end)

describe("Ping : configuration persistee", function()
    local ns = wowenv.loadCore()
    local Config = ns.Config

    it("utilise « anchors » par defaut", function()
        assert.are.equal("anchors", Config.defaultIntermission().pingMode)
        assert.are.equal("anchors", Config.resolveIntermission(nil).pingMode)
        assert.are.equal("anchors", Config.resolveIntermission({}).pingMode)
    end)

    it("accepte une politique explicite et borne toute valeur inconnue", function()
        assert.are.equal("color", Config.resolveIntermission({ pingMode = "color" }).pingMode)
        assert.are.equal("none", Config.resolveIntermission({ pingMode = "NONE" }).pingMode)
        assert.are.equal("anchors", Config.resolveIntermission({ pingMode = "magenta" }).pingMode)
        assert.are.equal("anchors", Config.resolveIntermission({ pingMode = 3 }).pingMode)
        assert.are.equal("anchors", Config.resolveIntermission({ pingMode = {} }).pingMode)
        -- Une politique explicite ne perturbe pas le reste de la configuration.
        local c = Config.resolveIntermission({ pingMode = "color", scale = 2, visibilitySeconds = 5 })
        assert.are.equal(2, c.scale)
        assert.are.equal(5, c.visibilitySeconds)
        assert.are.equal("color", c.pingMode)
    end)
end)

describe("Ping : commande en jeu /gr ping", function()
    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.SlashCmdList = nil
        stub.install()
        wowenv.loadAddon()
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    it("/gr ping affiche la politique courante et sa regle", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping")
        local text = messages()
        assert.matches("Ping policy: anchors", text)
        assert.matches("only the 1V3R anchors ping", text)
        assert.matches("/gr ping anchors|color|none", text)
    end)

    it("/gr ping color persiste la politique et rafraichit le panneau", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping color")
        assert.are.equal("color", _G.GideonRaidDB.intermission.pingMode)
        assert.matches("Ping policy = color", messages())
        assert.matches("every state pings with its own color", messages())
        stub.mainFrame():Fire("ENCOUNTER_START")
        _G.GideonRaidIntermissionPanel.buttons[3]:Click() -- 3V1R
        assert.matches("PING: YES", _G.GideonRaidIntermissionPanel.pingBanner:GetText())
        assert.matches("C_Ping%.SendMacroPing", _G.GideonRaidIntermissionPanel.macroBox:GetText())
    end)

    it("/gr ping none persistee : plus aucune macro", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping none")
        assert.are.equal("none", _G.GideonRaidDB.intermission.pingMode)
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click() -- 1V3R = ANCRE, pourtant sans ping ici
        assert.are.equal("PING: NO", panel.pingBanner:GetText())
        assert.is_false(panel.macroBox:IsShown())
    end)

    it("/gr ping avec une valeur inconnue est refuse et ne persiste rien", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping magenta")
        assert.are.equal("anchors", _G.GideonRaidDB.intermission.pingMode)
        assert.is_nil(string.find(messages(), "Ping policy =", 1, true))
        assert.matches("Unknown ping policy", messages())
    end)

    it("persiste la politique dans les SavedVariables, relue apres /reload", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping color")
        local db = _G.GideonRaidDB
        -- Simulation d'un /reload : le bloc persiste est relu tel quel.
        local ns2 = wowenv.loadAddon()
        _G.GideonRaidDB = db
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.are.equal("color", ns2.Config.resolveIntermission(_G.GideonRaidDB.intermission).pingMode)
        stub.mainFrame():Fire("ENCOUNTER_START")
        _G.GideonRaidIntermissionPanel.buttons[2]:Click()
        assert.matches("C_Ping%.SendMacroPing", _G.GideonRaidIntermissionPanel.macroBox:GetText())
    end)

    it("/gr inter status rappelle la politique de ping", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        assert.matches("intermission ping policy: anchors", messages())
    end)
end)
