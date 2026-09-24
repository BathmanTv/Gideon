--[[--------------------------------------------------------------------------
    tests/spec/pingpolicy_spec.lua   (busted)

    Tests HORS JEU de la POLITIQUE DE PING et des ROLES PAR ETAT.

    Decision du raid lead : un etat canonique (1V3R / 2V2R / 3V1R) ne porte plus
    un « role par numero » mais un ROLE :
      - 1V3R = ANCRE  (ANCHOR) : sur place, ping avec SON raccourci natif ;
      - 2V2R = MILIEU (MID)    : milieu / sous le boss, s'apparie a un 2V2R ;
      - 3V1R = CHASSEUR (CHASER) : fonce sur un ping, ne ping pas.
    La politique de ping est CONFIGURABLE (GideonRaidDB.intermission.pingMode,
    commande /gr ping) :
      - "anchors" (defaut) : seule l'ANCRE ping (~8 pings par raid au lieu de ~20) ;
      - "color"            : chaque etat ping son propre ping ;
      - "none"             : personne ne ping, on joue en positions.

    Depuis le test en jeu reel : AUCUNE MACRO. La macro etait refusee par
    Blizzard (« action utilisable uniquement par l'UI de Blizzard »). L'addon
    affiche QUEL ping utiliser et, si le joueur a bindi une touche, LAQUELLE
    presser (touche lue par la couche de rendu, injectee ici).

    La logique testee ici est PURE (Core/), puis le cablage en jeu (/gr ping).
----------------------------------------------------------------------------]]
--
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
            if expected then
                assert.is_string(rec.pingLine)
                assert.matches("Warning", rec.pingLine)
            else
                assert.is_nil(rec.pingLine, key .. " ne doit porter AUCUNE consigne de ping")
            end
        end
        assert.are.equal("ANCHOR", I.getDeclaration("1V3R").role)
        assert.are.equal("MID", I.getDeclaration("2V2R").role)
        assert.are.equal("CHASER", I.getDeclaration("3V1R").role)
    end)

    it("politique « color » : les trois etats ping avec LEUR ping", function()
        local expected = {
            ["1V3R"] = { "RED", "Warning", "Warning" },
            ["2V2R"] = { "BLUE", "OnMyWay", "On My Way" },
            ["3V1R"] = { "GREEN", "Assist", "Assist" },
        }
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key, "color")
            assert.is_true(rec.shouldPing, key)
            assert.are.equal("YES", rec.pingDecision, key)
            assert.are.equal(expected[key][1], rec.pingColor, key)
            assert.are.equal(expected[key][2], rec.ping, key)
            assert.is_true(contains(rec.pingLine, expected[key][3]), key)
            assert.is_true(contains(rec.pingLine, "Options > Keybindings"), key)
        end
    end)

    it("politique « none » : PERSONNE ne ping ni ne porte de consigne de ping", function()
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key, "none")
            assert.is_false(rec.shouldPing, key)
            assert.are.equal("NO", rec.pingDecision, key)
            assert.are.equal("none", rec.pingPolicy, key)
            assert.is_nil(rec.pingLine, key)
            assert.is_nil(I.pingHint(key, "none", "Q"), key)
        end
        assert.is_false(I.shouldPing("1V3R", "none"))
        assert.is_true(I.shouldPing("1V3R", "anchors"))
        assert.is_true(I.shouldPing("3V1R", "color"))
    end)

    it("consigne operationnelle de l'ANCRE : survoler SON cadre, ping, ne pas bouger", function()
        local anchor = I.getDeclaration("1V3R") -- anchors
        assert.are.equal("ROLE: ANCHOR", anchor.roleLine)
        -- Retour en jeu : le ping part la ou est la souris, donc l'ancre survole
        -- son PROPRE cadre de personnage (le geste est ecrit, plus « place un
        -- ping sur toi »).
        assert.is_true(contains(anchor.actionLine, "PING: YES"))
        assert.is_true(contains(anchor.actionLine, "hover YOUR OWN character frame"))
        assert.is_true(contains(anchor.actionLine, "press your ping key (Warning)"))
        assert.is_true(contains(anchor.actionLine, "jump on the spot"))
        assert.is_true(anchor.shouldPing)
        local hint = assert(I.pingHint("1V3R", "anchors", "Q"))
        assert.are.equal("PING: Warning - press Q", hint.line)
        -- Sans ping (politique none), la consigne reste « ne bouge pas » et ne
        -- demande plus un ping impossible.
        local noPing = I.getDeclaration("1V3R", "none")
        assert.is_true(contains(noPing.actionLine, "STAY WHERE YOU ARE"))
        assert.is_true(contains(noPing.actionLine, "jump on the spot"))
        assert.is_false(contains(noPing.actionLine, "ping yourself"))
        assert.is_false(contains(noPing.actionLine, "hover YOUR OWN"))
        assert.are.equal("3V1R", anchor.complement)
    end)

    it("consigne du CHASSEUR : ne ping pas, fonce sur un ping", function()
        local chaser = I.getDeclaration("3V1R") -- anchors
        assert.are.equal("DO NOT PING - run to a ping (a 1V3R)", chaser.actionLine)
        assert.is_false(chaser.shouldPing)
        assert.are.equal("1V3R", chaser.complement)
        -- En politique color il ping AUSSI, mais garde sa course vers un ping.
        local colored = I.getDeclaration("3V1R", "color")
        assert.is_true(colored.shouldPing)
        assert.is_false(contains(colored.actionLine, "DO NOT PING"))
        assert.is_true(contains(colored.actionLine, "run to a ping"))
        assert.is_true(contains(colored.actionLine, "Assist"))
    end)

    it("consigne du MILIEU : ne ping pas, va au milieu et trouve un 2V2R", function()
        local mid = I.getDeclaration("2V2R") -- anchors
        assert.is_false(mid.shouldPing)
        assert.are.equal("DO NOT PING - go to the middle / under the boss", mid.actionLine)
        assert.is_true(contains(mid.actionLine, "middle"))
        assert.are.equal("2V2R", mid.complement)
        -- Le MILIEU aussi garde sa consigne en politique color, avec son ping.
        local colored = I.getDeclaration("2V2R", "color")
        assert.is_true(colored.shouldPing)
        assert.is_true(contains(colored.actionLine, "PING (On My Way)"))
        assert.is_true(contains(colored.actionLine, "middle"))
    end)

    it("sert les consignes en FRANCAIS quand la langue active est fr", function()
        local fr = wowenv.loadCore()
        fr.Locale.setActive("fr")
        local anchor = fr.Intermission.getDeclaration("1V3R")
        assert.are.equal("ANCRE", anchor.roleName)
        assert.are.equal("ROLE : ANCRE", anchor.roleLine)
        assert.is_true(contains(anchor.actionLine, "survole TON propre cadre de personnage"))
        -- Le libelle du ping suit la langue du client : « Avertissement » (mesure
        -- en jeu par le raid lead), pas le nom canonique anglais.
        assert.is_true(contains(anchor.actionLine, "ta touche de ping (Avertissement)"))
        assert.is_true(contains(anchor.actionLine, "reste sur place"))
        assert.are.equal("Avertissement", fr.Intermission.pingLabel("Warning"))
        assert.are.equal("En route", fr.Intermission.pingLabel("OnMyWay"))
        assert.are.equal("Aide", fr.Intermission.pingLabel("Assist"))
        assert.is_true(contains(fr.Intermission.pingHint("1V3R").line, "PING : Avertissement"))
        assert.are.equal("CHASSEUR", fr.Intermission.getDeclaration("3V1R").roleName)
        assert.is_true(contains(fr.Intermission.getDeclaration("3V1R").actionLine, "fonce sur un ping"))
        assert.are.equal("MILIEU", fr.Intermission.getDeclaration("2V2R").roleName)
        assert.is_true(contains(fr.Intermission.getDeclaration("2V2R").actionLine, "NE PING PAS"))
        assert.are.equal("OUI", fr.Intermission.getDeclaration("1V3R").pingDecision)
        assert.are.equal("NON", fr.Intermission.getDeclaration("2V2R").pingDecision)
        -- La touche non bindi est dite en francais aussi.
        assert.is_true(contains(fr.Intermission.pingHint("1V3R").line, "Options > Raccourcis"))
    end)

    it("n'affiche PLUS la politique de ping en permanence sur le panneau", function()
        for _, mode in ipairs(I.PING_MODES) do
            local snap = I.snapshot(I.newState(), mode)
            assert.are.equal(mode, snap.pingPolicy, mode)
            assert.is_string(snap.policyLine, mode)
            local text = table.concat(snap.lines, "\n")
            assert.is_false(contains(text, "PING POLICY"), mode)
            assert.is_false(contains(text, "ANCHORS:"), mode)
            assert.is_false(contains(text, "COLOR:"), mode)
        end
        -- La politique reste interrogeable a la demande (/gr ping).
        assert.matches("ANCHORS", I.pingPolicyLine("anchors"))
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

    --- Le bouton d'image d'une composition : l'ordre vertical est fige par Core
    --- (3V1R en haut, 2V2R au milieu, 1V3R en bas), un test ne passe donc JAMAIS
    --- par un index en dur.
    local function buttonFor(panel, stateKey)
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            if ns.Layout.INTERMISSION_CHOICE_ORDER[index] == stateKey then
                return panel.buttons[index]
            end
        end
        return nil
    end

    --- L'etat de combat d'une composition, tel que Core le calcule (le panneau de
    --- combat n'affiche PLUS la consigne de ping : elle reste disponible ici, dans
    --- le snapshot lu par /gr inter ping et par le kit de diagnostic).
    local function snapFor(stateKey, pingMode)
        local state = ns.Intermission.newState()
        ns.Intermission.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
        ns.Intermission.declare(state, stateKey)
        return ns.Intermission.snapshot(state, pingMode)
    end

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

    it("/gr ping color persiste la politique et le panneau ne dit plus rien", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping color")
        assert.are.equal("color", _G.GideonRaidDB.intermission.pingMode)
        assert.matches("Ping policy = color", messages())
        assert.matches("every state pings with its own ping", messages())
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "3V1R"):Click()
        -- Le panneau de combat n'affiche plus AUCUNE consigne de ping (raid lead :
        -- « enleve tout le blabla ») : UN SEUL mot, celui du clic.
        assert.is_nil(panel.pingBanner)
        assert.is_nil(panel.body)
        assert.are.equal(ns.Locale.t("state.word.3V1R"), panel.word:GetText())
        -- La politique reste CALCULEE par Core : un CHASSEUR ping en mode color.
        local snap = snapFor("3V1R", "color")
        assert.is_true(snap.shouldPing)
        assert.are.equal("PING: YES", snap.pingBanner)
        assert.is_true(contains(snap.actionLine, "PING (Assist)"))
    end)

    it("/gr ping none persistee : Core ne fait plus pinger personne", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("ping none")
        assert.are.equal("none", _G.GideonRaidDB.intermission.pingMode)
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click() -- l'ANCRE, pourtant sans ping ici
        assert.is_nil(panel.pingBanner)
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        -- Cote Core : personne ne ping, et la consigne dit de rester sur place.
        local snap = snapFor("1V3R", "none")
        assert.is_false(snap.shouldPing)
        assert.are.equal("PING: NO", snap.pingBanner)
        assert.is_false(contains(snap.actionLine, "PING: Warning"))
        assert.is_true(contains(snap.actionLine, "STAY WHERE YOU ARE"))
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
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "2V2R"):Click()
        assert.are.equal(ns.Locale.t("state.word.2V2R"), panel.wordBig:GetText())
        -- ... et la politique relue par Core vaut bien « color ».
        local snap = snapFor("2V2R", ns.Config.resolveIntermission(_G.GideonRaidDB.intermission).pingMode)
        assert.is_true(snap.shouldPing)
        assert.is_true(contains(snap.actionLine, "PING (On My Way)"))
    end)

    it("/gr inter status rappelle la politique de ping et le planning", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        local text = messages()
        assert.matches("intermission ping policy: anchors", text)
        assert.matches("schedule: 4 intermission", text)
    end)

    it("/gr inter ping dit quel ping et quelle touche (et ce qui a ete essaye)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter ping")
        assert.matches("No composition declared yet", messages())
        _G.GetBindingKey = function(name)
            if name == "PING_WARNING" then
                return "Q"
            end
            return nil
        end
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        buttonFor(_G.GideonRaidIntermissionPanel, "1V3R"):Click()
        _G.SlashCmdList["GIDEONRAID"]("inter ping")
        local text = messages()
        assert.matches("PING: Warning %- press Q", text)
        assert.is_true(contains(text, "PING_WARNING"), "les noms essayes sont listes")
        -- Une ANCRE peut aussi etre pingee par quelqu'un d'autre : rien n'est
        -- obligatoire, la touche est un confort.
        assert.is_false(contains(text, "SendMacroPing"))
    end)
end)
