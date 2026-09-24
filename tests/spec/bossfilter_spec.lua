--[[--------------------------------------------------------------------------
    tests/spec/bossfilter_spec.lua   (busted)

    BUG CRITIQUE SIGNALE PAR LE RAID LEAD : « la fenetre s'ouvre toute seule
    pendant n'importe quelle boss fight ! On doit la limiter au boss qu'on veut. »
    L'ouverture automatique se declenchait sur TOUT `ENCOUNTER_START`.

    Ce que ces tests verrouillent, HORS JEU :

      1. Core/BossFilter.lua (PUR) : la DECISION « ce combat est-il le boss
         cible ? » - allow-list d'IDS d'encounter (critere PRINCIPAL, entier,
         identique dans toutes les langues) + allow-list de NOMS (critere
         SECONDAIRE, dependant de la langue du client), liste vide = AUCUNE
         ouverture, et la lecture des arguments sous pcall (une valeur SECRETE en
         12.x leve au moindre acces : une valeur illisible ne correspond a RIEN) ;
      2. le CABLAGE (stub) : le DEFAUT LIVRE (encounter id 3445 + les deux noms, il
         ouvre le panneau sans qu'aucun joueur ne tape une commande), la
         persistance des commandes (`/gr boss <id>`, `/gr boss list`,
         `/gr boss clear`, refus sans rien ecrire), l'IDLOG (`/gr idlog on|off`)
         qui MESURE l'id reel du boss en jeu, et l'override manuel `/gr inter on`
         (un encounter, consomme a la fin).

    L'id de la CIBLE est MESURE EN JEU (raid lead, 2026-09-24, pull heroique 20
    joueurs) : `encounter seen: id=3445 name=Sentinelles inhumées difficulty=15
    group=20`. Il est donc LIVRE avec l'addon, en dur, dans Core/Config.lua
    (Config.DEFAULT_BOSS_IDS), avec les DEUX noms du boss (anglais officiel +
    francais du client du raid lead) comme filet SECONDAIRE. DEUX etats ne sont
    JAMAIS confondus : « jamais configure » (le defaut livre s'applique) et
    « vide explicitement par /gr boss clear » (rien ne s'ouvre, et le defaut livre
    ne revient pas tout seul : c'est le marqueur `bossTargetCleared`).
----------------------------------------------------------------------------]]
--
--
--
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(tostring(text), needle, 1, true) ~= nil
end

--- Simule un argument SECRET (12.x) : le LECTEUR injecte leve sur l'appel numero
--- `n`. En 12.x le moindre acces a une valeur secrete leve, et c'est exactement
--- pour cela que le lecteur est INJECTE par la couche de cablage (le harnais, en
--- Lua 5.1, ne peut pas fabriquer une vraie valeur secrete).
local function probeBlindOn(n)
    local calls = 0
    return function(value)
        calls = calls + 1
        if calls == n then
            error("This value is secret")
        end
        return type(value), value
    end
end

--- L'id du boss CIBLE du harness : un entier POSITIF, tel que le rapporte
--- `ENCOUNTER_START` arg1 (l'id reel viendra de `/gr idlog on` en jeu).
local TARGET_ID = 2594
local OTHER_ID = 9999
local TARGET_NAME = "Entombed Sentinels"

-- ===========================================================================
-- 1. LA DECISION EST UNE FONCTION PURE DE Core/
-- ===========================================================================
describe("BossFilter : la decision d'ouverture est PURE (Core/)", function()
    local ns = wowenv.loadCore()
    local BossFilter = ns.BossFilter

    it("expose la couche et ses bornes", function()
        assert.is_table(BossFilter)
        assert.are.equal(1, BossFilter.SCHEMA_VERSION)
        assert.is_true(BossFilter.MAX_IDS > 0)
        assert.is_true(BossFilter.MAX_NAMES > 0)
        assert.are.equal(10, BossFilter.MAX_SEEN)
        assert.is_nil(_G.GideonRaidBossFilter, "Core/ n'expose rien dans _G")
    end)

    -- ---------------------------------------------------------------- IDs ---
    it("resolveId : ENTIER POSITIF ecrit en chaine ou en nombre, sinon nil", function()
        assert.are.equal(2594, BossFilter.resolveId("2594"))
        assert.are.equal(2594, BossFilter.resolveId("  2594  "))
        assert.are.equal(2594, BossFilter.resolveId(2594))
        assert.are.equal(TARGET_ID, BossFilter.resolveId(tostring(TARGET_ID)))
        for _, bad in ipairs({ nil, "", "  ", "Entombed Sentinels", "0", "-3", "12.5", "1e3", {}, true, "0x10" }) do
            assert.is_nil(BossFilter.resolveId(bad), "resolveId doit refuser " .. tostring(bad))
        end
    end)

    it("resolveIds : TOTAL, trie, dedoublonne et borne (liste vide = defaut sur)", function()
        assert.are.same({}, BossFilter.resolveIds(nil))
        assert.are.same({}, BossFilter.resolveIds("pas une table"))
        assert.are.same({}, BossFilter.resolveIds({ "abc", -1, 0, 3.5, {} }))
        assert.are.same({ 12, 2594, 9999 }, BossFilter.resolveIds({ 9999, "2594", 12, 12, "abc" }))
        -- Une liste editee a la main ne peut ni lever ni grandir sans borne.
        local huge = {}
        for index = 1, 40 do
            huge[index] = index
        end
        assert.are.equal(BossFilter.MAX_IDS, #BossFilter.resolveIds(huge))
    end)

    it("addId : renvoie une liste NORMALISEE, sans doublon", function()
        local list = BossFilter.addId({}, TARGET_ID)
        assert.are.same({ TARGET_ID }, list)
        list = BossFilter.addId(list, TARGET_ID)
        assert.are.same({ TARGET_ID }, list, "pas de doublon")
        list = BossFilter.addId(list, OTHER_ID)
        assert.are.same({ TARGET_ID, OTHER_ID }, list, "tri croissant")
        assert.is_nil(BossFilter.resolveIds({})[1])
    end)

    -- -------------------------------------------------------------- NOMS ---
    it("resolveName / resolveNames : SECONDARY, vide par defaut, jamais traduit", function()
        assert.is_nil(BossFilter.resolveName(nil))
        assert.is_nil(BossFilter.resolveName("   "))
        assert.are.equal("entombed sentinels", BossFilter.resolveName("  Entombed Sentinels  "))
        assert.are.same({}, BossFilter.resolveNames(nil))
        assert.are.same({}, BossFilter.resolveNames({ "", "  ", 42 }))
        assert.are.same({ "entombed sentinels" }, BossFilter.resolveNames({ "Entombed Sentinels", "ENTOMBED SENTINELS" }))
        -- Le resolveur ne connait AUCUNE traduction : ce qui est ecrit est ce qui
        -- est compare.
        assert.is_true(BossFilter.resolveIds(nil) ~= nil)
        assert.are.equal("entombed sentinels", BossFilter.addName({}, "Entombed Sentinels")[1])
    end)

    -- ----------------------------------------------------------- BASCULES ---
    it("resolveSwitch / enabledOf : STRICT pour la commande, TOTAL pour la sauvegarde", function()
        assert.is_true(BossFilter.resolveSwitch("on"))
        assert.is_true(BossFilter.resolveSwitch(" ON "))
        assert.is_false(BossFilter.resolveSwitch("off"))
        for _, bad in ipairs({ nil, "", "yes", "1", "on off", 3 }) do
            assert.is_nil(BossFilter.resolveSwitch(bad), "resolveSwitch doit refuser " .. tostring(bad))
        end
        -- Persistance : seul un `true` exact allume (rien ne s'active tout seul).
        assert.is_true(BossFilter.enabledOf(true))
        assert.is_false(BossFilter.enabledOf(nil))
        assert.is_false(BossFilter.enabledOf(false))
        assert.is_false(BossFilter.enabledOf("on"))
        assert.is_false(BossFilter.enabledOf(1))
    end)

    -- ------------------------------------------------------- OBSERVATION ---
    it("observeEncounter : lit chaque argument SOUS pcall, ne lit que le necessaire", function()
        local seen = BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20)
        assert.are.equal(TARGET_ID, seen.id)
        assert.are.equal(TARGET_NAME, seen.name)
        assert.are.equal(16, seen.difficulty)
        assert.are.equal(20, seen.groupSize)
        assert.are.equal(BossFilter.READ.OK, seen.idStatus)
        assert.are.equal(BossFilter.READ.OK, seen.nameStatus)

        -- VALEUR SECRETE (12.x) : le moindre acces leve. La lecture est
        -- ABANDONNEE (et signalee), jamais comparee - et les autres arguments
        -- restent lisibles.
        local blind = BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(1))
        assert.is_nil(blind.id)
        assert.are.equal(BossFilter.READ.UNREADABLE, blind.idStatus)
        assert.are.equal(TARGET_NAME, blind.name)
        assert.are.equal(BossFilter.READ.OK, blind.nameStatus)
        assert.are.equal(BossFilter.READ.OK, blind.difficultyStatus)

        -- Un id qui n'est pas un entier exploitable est signale comme tel.
        local float = BossFilter.observeEncounter(12.5, TARGET_NAME, 16, 20)
        assert.is_nil(float.id)
        assert.are.equal(BossFilter.READ.NOT_INTEGER, float.idStatus)
        -- Un argument d'un autre type (une table) est ABSENT, pas "presque bon".
        local junk = BossFilter.observeEncounter({ "pas un id" }, nil, 16, 20)
        assert.is_nil(junk.id)
        assert.are.equal(BossFilter.READ.ABSENT, junk.idStatus)
        assert.is_nil(junk.name)
        assert.are.equal(BossFilter.READ.ABSENT, junk.nameStatus)
    end)

    it("toEntry : TOTAL, seulement les champs connus, statut derive de la valeur", function()
        local entry = BossFilter.toEntry({ id = TARGET_ID, name = "  Boss  ", difficulty = 16.5, junk = "ignore" })
        assert.are.equal(TARGET_ID, entry.id)
        assert.are.equal("Boss", entry.name)
        assert.is_nil(entry.difficulty, "16.5 n'est pas un id de difficulte exploitable")
        assert.are.equal(BossFilter.READ.NOT_INTEGER, entry.difficultyStatus)
        assert.is_nil(entry.junk)
        assert.is_table(BossFilter.toEntry(nil))
        -- Un id ecrit en CHAINE dans une sauvegarde editee a la main n'est pas un
        -- id exploitable : rien n'est devine.
        assert.is_nil(BossFilter.toEntry({ id = "2594" }).id)
        -- at / clock (horodatage du client) sont conserves quand ils sont valides.
        local stamped = BossFilter.toEntry({ id = 1, at = 1758500000, clock = "2026-09-22 21:00:00" })
        assert.are.equal(1758500000, stamped.at)
        assert.are.equal("2026-09-22 21:00:00", stamped.clock)
        -- isEmptyObservation : une observation vide ne dit rien, une observation
        -- dont la lecture a ECHOUE dit quelque chose.
        assert.is_true(BossFilter.isEmptyObservation(BossFilter.toEntry(nil)))
        assert.is_false(BossFilter.isEmptyObservation(BossFilter.toEntry({ id = TARGET_ID })))
        assert.is_false(BossFilter.isEmptyObservation(BossFilter.observeEncounter(1, 2, 3, 4, probeBlindOn(1))))
    end)

    -- ---------------------------------------------------------- DECISION ---
    it("evaluate : LISTE VIDE = AUCUNE ouverture (defaut sur)", function()
        local decision = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20), nil)
        assert.is_false(decision.shouldOpen)
        assert.are.equal(BossFilter.REASON.NO_TARGET, decision.reason)
        assert.are.equal(TARGET_ID, decision.id, "l'id lu est quand meme rapporte (pour l'avertissement)")
    end)

    it("evaluate : le BON id ouvre, un AUTRE id ne fait rien", function()
        local config = { bossIds = { TARGET_ID } }
        local good = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20), config)
        assert.is_true(good.shouldOpen)
        assert.are.equal(BossFilter.REASON.MATCH_ID, good.reason)

        -- LE BUG CRITIQUE : n'importe quel autre boss de n'importe quel raid.
        local other = BossFilter.evaluate(BossFilter.observeEncounter(OTHER_ID, "Some Other Boss", 16, 20), config)
        assert.is_false(other.shouldOpen)
        assert.are.equal(BossFilter.REASON.NO_MATCH, other.reason)
    end)

    it("evaluate : id ILLISIBLE (valeur secrete) = aucune correspondance, jamais une erreur", function()
        -- Cible par ID seulement : l'id illisible ne peut donc correspondre a rien.
        local config = { bossIds = { TARGET_ID } }
        local decision = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(1)), config)
        assert.is_false(decision.shouldOpen)
        assert.are.equal(BossFilter.REASON.UNREADABLE, decision.reason)
        assert.is_nil(decision.id)
        -- ... meme quand l'id lu est justement celui qu'on cherche : une valeur
        -- illisible n'a JAMAIS l'air de correspondre.
        local target =
            BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(1)), { bossIds = { TARGET_ID } })
        assert.is_false(target.shouldOpen)
        -- Le nom lisible, lui, reste un critere SECONDAIRE utilisable : c'est
        -- documente et explicite (la liste est vide par defaut).
        local byName = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(1)), {
            bossIds = { TARGET_ID },
            bossNames = { TARGET_NAME },
        })
        assert.is_true(byName.shouldOpen)
        assert.are.equal(BossFilter.REASON.MATCH_NAME, byName.reason)
    end)

    it("evaluate : un id non entier (12.5) ou absent ne correspond a rien", function()
        local config = { bossIds = { TARGET_ID } }
        assert.is_false(BossFilter.evaluate(BossFilter.observeEncounter(12.5, "Boss", 16, 20), config).shouldOpen)
        assert.is_false(BossFilter.evaluate(BossFilter.observeEncounter(nil, "Boss", 16, 20), config).shouldOpen)
        -- Une entree de sauvegarde bricolee ne fait pas ouvrir non plus.
        assert.is_false(BossFilter.evaluate({ id = 12.5, name = "Boss" }, config).shouldOpen)
    end)

    it("evaluate : le NOM est un critere SECONDAIRE, insensible a la casse", function()
        local config = { bossNames = { "entombed sentinels" } }
        local decision = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, "ENTOMBED SENTINELS", 16, 20), config)
        assert.is_true(decision.shouldOpen)
        assert.are.equal(BossFilter.REASON.MATCH_NAME, decision.reason)
        -- La liste de noms est VIDE par defaut : elle n'ouvre rien.
        assert.is_false(BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20), {}).shouldOpen)
        -- ... et un nom vide (client sans nom) ne correspond a rien.
        assert.is_false(BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, "   ", 16, 20), config).shouldOpen)
    end)

    it("evaluate : la DIFFICULTE ne decide jamais (log seulement)", function()
        local config = { bossIds = { TARGET_ID } }
        local easy = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 14, 10), config)
        local hard = BossFilter.evaluate(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20), config)
        assert.is_true(easy.shouldOpen)
        assert.is_true(hard.shouldOpen)
        assert.are.equal(easy.reason, hard.reason)
        -- ... et une difficulte ILLISIBLE (3e argument secret) ne bloque pas
        -- l'ouverture du bon id : elle n'est la que pour l'idlog.
        local seen = BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(3))
        assert.is_nil(seen.difficulty)
        assert.are.equal(BossFilter.READ.UNREADABLE, seen.difficultyStatus)
        assert.is_true(BossFilter.evaluate(seen, config).shouldOpen)
    end)

    it("evaluate : l'OVERRIDE MANUEL ouvre quel que soit le boss, meme sans cible", function()
        local overridden = { bossIds = {}, overrideEncounter = true }
        local decision = BossFilter.evaluate(BossFilter.observeEncounter(OTHER_ID, "Some Other Boss", 16, 20), overridden)
        assert.is_true(decision.shouldOpen)
        assert.are.equal(BossFilter.REASON.OVERRIDE, decision.reason)
        -- ... meme quand RIEN n'est lisible : c'est le joueur qui l'a demande.
        assert.is_true(BossFilter.evaluate(BossFilter.observeEncounter(1, 2, 3, 4, probeBlindOn(1)), overridden).shouldOpen)
        -- Un override a `false` (ou absent) ne change rien.
        assert.is_false(BossFilter.evaluate(BossFilter.observeEncounter(OTHER_ID, "X", 16, 20), { overrideEncounter = false }).shouldOpen)
    end)

    -- --------------------------------------------------------- IDLOG/RESUME ---
    it("seenLine : la ligne d'idlog, avec une mention LISIBLE si la lecture echoue", function()
        local line = BossFilter.seenLine(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20))
        assert.are.equal("encounter seen: id=2594 name=Entombed Sentinels difficulty=16 group=20", line)
        local blind = BossFilter.seenLine(BossFilter.observeEncounter(TARGET_ID, TARGET_NAME, 16, 20, probeBlindOn(1)))
        assert.is_true(contains(blind, "id=unreadable"), blind)
        assert.is_true(contains(blind, "name=Entombed Sentinels"), blind)
        assert.is_true(contains(blind, "difficulty=16"), blind)
        -- Un argument absent se dit "none" (jamais un blanc, jamais un faux nombre).
        local empty = BossFilter.seenLine(BossFilter.observeEncounter(nil, nil, 16, 20))
        assert.is_true(contains(empty, "id=none name=none"), empty)
    end)

    it("rememberSeen / toList : les derniers encounters vus, du plus recent, bornes", function()
        local list = nil
        for index = 1, BossFilter.MAX_SEEN + 4 do
            list = BossFilter.rememberSeen(list, BossFilter.observeEncounter(index, "Boss " .. index, 16, 20))
        end
        local resolved = BossFilter.toList(list)
        assert.are.equal(BossFilter.MAX_SEEN, #resolved)
        assert.are.equal(BossFilter.MAX_SEEN + 4, resolved[1].id, "le plus recent est en tete")
        assert.are.equal(5, resolved[BossFilter.MAX_SEEN].id)
        -- TOTAL : une sauvegarde bricolee ne leve pas.
        assert.are.same({}, BossFilter.toList(nil))
        assert.are.same({}, BossFilter.toList("pas une table"))
        assert.are.same({}, BossFilter.toList({ "abc", 12, {} }))
    end)

    it("targetSummary / describe* / idText : ce qui s'affiche, jamais un vide ambigu", function()
        assert.is_false(BossFilter.hasTarget({}))
        assert.is_false(BossFilter.hasTarget(nil))
        assert.is_true(BossFilter.hasTarget({ bossIds = { TARGET_ID } }))
        assert.is_true(BossFilter.hasTarget({ bossNames = { "boss" } }))

        local none = BossFilter.targetSummary({})
        assert.is_true(contains(none, "NONE"), none)
        assert.is_true(contains(none, "SAFE DEFAULT"), none)

        local both = BossFilter.targetSummary({ bossIds = { TARGET_ID, OTHER_ID }, bossNames = { "entombed sentinels" } })
        assert.is_true(contains(both, "2594"), both)
        assert.is_true(contains(both, "9999"), both)
        assert.is_true(contains(both, "entombed sentinels"), both)

        assert.are.equal("", BossFilter.describeIds({}))
        assert.are.equal("2594, 9999", BossFilter.describeIds({ TARGET_ID, OTHER_ID }))
        assert.are.equal("", BossFilter.describeNames(nil))
        assert.are.equal("2594", BossFilter.idText(2594))
        assert.are.equal("none", BossFilter.idText(nil))
        assert.are.equal("none", BossFilter.fieldText(nil, BossFilter.READ.ABSENT))
        assert.are.equal("unreadable", BossFilter.fieldText(nil, BossFilter.READ.UNREADABLE))
        assert.are.equal("16", BossFilter.fieldText(16, BossFilter.READ.OK))
    end)
end)

-- ===========================================================================
-- 2. LE CABLAGE : le panneau ne s'ouvre QUE sur le boss cible
-- ===========================================================================
describe("BossFilter : le panneau ne s'ouvre plus sur n'importe quel boss", function()
    local BOSS_ARGS = { TARGET_ID, TARGET_NAME, 16, 20 }
    -- LE DEFAUT LIVRE DE L'ADDON, mesure en jeu par le raid lead le 2026-09-24 sur un
    -- pull heroique a 20 joueurs : id=3445, nom du client FRANCAIS du raid lead,
    -- difficulte 15 (Heroique). Le nom anglais officiel est l'autre filet.
    local DELIVERED_ID = 3445
    local DELIVERED_EN_NAME = "Entombed Sentinels"
    local DELIVERED_FR_NAME = "Sentinelles inhumées"
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

    local function lastMessage()
        return _G.DEFAULT_CHAT_FRAME.messages[#_G.DEFAULT_CHAT_FRAME.messages]
    end

    local function slash(argument)
        _G.SlashCmdList["GIDEONRAID"](argument)
    end

    local function panel()
        return _G.GideonRaidIntermissionPanel
    end

    local function fire(event, ...)
        stub.mainFrame():Fire(event, ...)
    end

    -- ------------------------------------------------- DEFAUT LIVRE / CLEAR ---
    it("JAMAIS CONFIGURE : le defaut LIVRE ouvre le panneau, sans aucune commande", function()
        -- Rien n'a jamais ete configure par un joueur : la sauvegarde est vierge.
        assert.are.same({}, _G.GideonRaidDB.intermission.bossIds)
        assert.are.same({}, _G.GideonRaidDB.intermission.bossNames)
        assert.is_false(_G.GideonRaidDB.intermission.overrideEncounter)
        assert.is_false(_G.GideonRaidDB.intermission.idlog)
        assert.is_false(_G.GideonRaidDB.intermission.bossTargetCleared)

        -- ... et pourtant le panneau S'OUVRE sur le boss cible, tel qu'il a ete
        -- MESURE en jeu (pull heroique : id 3445, nom francais du client, 15, 20).
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_FR_NAME, 15, 20)
        assert.is_true(contains(messages(), "armed: 4 intermission"), messages())
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "le defaut livre doit ouvrir le panneau sans commande")
    end)

    it("le defaut LIVRE couvre les DEUX langues et TOUTES les difficultes", function()
        -- Nom ANGLAIS officiel, difficulte Mythique (16).
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_EN_NAME, 16, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "le nom anglais et la difficulte 16 doivent ouvrir")
        fire("ENCOUNTER_END")

        -- Nom FRANCAIS du client du raid lead, difficulte Heroique (15) : c'est la
        -- ligne REELLE mesuree en jeu, caractere pour caractere.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_FR_NAME, 15, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "la ligne mesuree en jeu doit ouvrir")
        fire("ENCOUNTER_END")

        -- L'id seul suffit (nom vide ou different) : c'est le critere PRINCIPAL.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", DELIVERED_ID, "Nom totalement different", 17, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "l'id decide, le nom n'est qu'un filet")
    end)

    it("un AUTRE boss n'ouvre pas, meme avec le defaut livre (aucune ouverture aveugle)", function()
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown(), "BUG CRITIQUE : le panneau s'ouvre sur n'importe quel boss")
        assert.is_true(contains(messages(), "is NOT the configured target"), messages())
        assert.is_true(contains(messages(), "/gr boss <id>"), messages())
    end)

    it("/gr boss 3445 (l'id du defaut livre) est IDEMPOTENT : le panneau reste ouvert", function()
        slash("boss " .. tostring(DELIVERED_ID))
        assert.are.same({ DELIVERED_ID }, _G.GideonRaidDB.intermission.bossIds, "l'ajout du joueur est persiste")
        -- Rejouer la MEME commande ne cree aucun doublon (idempotent).
        slash("boss " .. tostring(DELIVERED_ID))
        assert.are.same({ DELIVERED_ID }, _G.GideonRaidDB.intermission.bossIds, "aucun doublon")
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_FR_NAME, 15, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "la cible explicite reste la cible du defaut livre")
    end)

    it("le defaut livre est ANNONCE (jamais un mystere) et aucun faux avertissement", function()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("PLAYER_LOGIN")
        -- Rien a signaler : la cible existe (elle est livree), donc pas d'avertissement.
        assert.is_false(contains(messages(), "No target boss configured"), messages())

        -- `/gr boss` montre la cible EFFECTIVE et son ORIGINE, plus le defaut livre.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss")
        assert.is_true(contains(messages(), "3445"), messages())
        assert.is_true(contains(messages(), "delivered with the addon"), messages())
        assert.is_true(contains(messages(), "Encounter id log: disabled"), messages())

        -- `/gr boss list` dit d'ou chaque entree vient.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Auto-open target ids: 3445 (addon default)"), messages())
        assert.is_true(contains(messages(), "Target source: the default DELIVERED with the addon"), messages())
    end)

    it("CLEAR EXPLICITE : /gr boss clear neutralise le defaut livre (les deux etats sont distincts)", function()
        -- Un joueur efface la cible expres : le defaut livre ne doit PAS revenir.
        slash("boss clear")
        assert.is_true(_G.GideonRaidDB.intermission.bossTargetCleared, "l'effacement explicite doit etre marque")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss")
        assert.is_true(contains(messages(), "cleared ON PURPOSE"), messages())
        assert.is_true(contains(messages(), "No target boss configured"), messages())

        -- Le boss du defaut livre n'ouvre PLUS rien, et le refus dit pourquoi.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_FR_NAME, 15, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown(), "efface = aucune ouverture, meme sur le boss du defaut livre")
        assert.is_true(contains(messages(), "cleared on purpose"), messages())
        assert.is_true(contains(messages(), "/gr boss 3445"), messages())

        -- ... et `/gr boss list` le dit AUSSI.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Auto-open target ids: none"), messages())
        assert.is_true(contains(messages(), "cleared ON PURPOSE"), messages())

        -- Un id ajoute APRES le clear redonne une cible (au joueur, pas au defaut).
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Auto-open target ids: 2594 (added by you)"), messages())
        assert.is_true(contains(messages(), "Target source: ONLY the entries added by a player"), messages())
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown())
    end)

    it("avec une cible ajoutee par un joueur, le defaut livre RESTE (union, jamais un ecrasement)", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "2594 (added by you)"), messages())
        assert.is_true(contains(messages(), "3445 (addon default)"), messages())
        assert.is_true(contains(messages(), "Target source: the default delivered with the addon PLUS"), messages())
        -- Les deux cibles ouvrent : la cible du joueur ne remplace pas celle livree.
        fire("ENCOUNTER_START", DELIVERED_ID, DELIVERED_FR_NAME, 16, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "le defaut livre reste actif")
    end)

    it("avec une cible configuree, l'avertissement de chargement disparait", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("PLAYER_LOGIN")
        assert.is_false(contains(messages(), "No target boss configured"), messages())
    end)

    -- ----------------------------------------------------------- /gr boss ---
    it("/gr boss <id> persiste la cible et /gr boss l'affiche", function()
        slash("boss " .. tostring(TARGET_ID))
        assert.are.same({ TARGET_ID }, _G.GideonRaidDB.intermission.bossIds, "la cible doit etre persistee")
        assert.is_true(contains(messages(), "Target encounter id 2594 added"), messages())

        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss")
        assert.is_true(contains(messages(), "Auto-open target boss:"), messages())
        assert.is_true(contains(messages(), "2594"), messages())
        assert.is_true(contains(messages(), "Encounter id log: disabled"), messages())
        assert.is_false(contains(messages(), "No target boss configured"), messages())
    end)

    it("/gr boss <id> : le BON boss ouvre le panneau (planning arme + ouverture)", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", BOSS_ARGS[1], BOSS_ARGS[2], BOSS_ARGS[3], BOSS_ARGS[4])
        assert.is_true(contains(messages(), "armed: 4 intermission"), messages())
        assert.is_false(panel():IsShown(), "le panneau ouvre 2 s avant l'intermission")
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "le boss cible doit ouvrir le panneau")
    end)

    it("/gr boss <id> : un AUTRE boss n'arme rien et ne desarme pas le reste", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown())
        assert.is_true(contains(messages(), "is NOT the configured target"), messages())
        assert.is_true(contains(messages(), "/gr boss <id>"), messages())
        -- ... et le boss CIBLE ouvre toujours (le refus n'a rien casse).
        fire("ENCOUNTER_END")
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown())
    end)

    it("/gr boss refuse une valeur inconnue SANS rien persister", function()
        for _, bad in ipairs({ "abc", "0", "-3", "12.5", "1e3" }) do
            _G.DEFAULT_CHAT_FRAME.messages = {}
            slash("boss " .. bad)
            assert.is_true(
                contains(lastMessage(), "Unknown encounter id '" .. bad .. "'"),
                tostring(lastMessage()) .. " (valeur : " .. bad .. ")"
            )
            assert.are.same({}, _G.GideonRaidDB.intermission.bossIds, "rien ne doit etre ecrit")
        end
        -- Un id deja present n'est pas duplique (mais est accepte).
        slash("boss " .. tostring(TARGET_ID))
        slash("boss " .. tostring(TARGET_ID))
        assert.are.same({ TARGET_ID }, _G.GideonRaidDB.intermission.bossIds)
    end)

    it("/gr boss list montre les deux listes, l'override et les encounters vus", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Auto-open target ids: 2594"), messages())
        assert.is_true(contains(messages(), "Auto-open target names"), messages())
        assert.is_true(contains(messages(), "Manual override: disabled"), messages())
        assert.is_true(contains(messages(), "Encounters memorized by the idlog (0"), messages())
        -- Sans cible, la liste vide se dit "none" (un vide ambigu n'est pas un etat).
        slash("boss clear")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Auto-open target ids: none"), messages())
    end)

    it("/gr boss clear revient au defaut sur (aucune ouverture)", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss clear")
        assert.are.same({}, _G.GideonRaidDB.intermission.bossIds)
        assert.are.same({}, _G.GideonRaidDB.intermission.bossNames)
        assert.is_true(contains(lastMessage(), "Auto-open target cleared"), tostring(lastMessage()))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown(), "efface = plus aucune ouverture automatique")
    end)

    it("/gr boss name <texte> : le critere SECONDAIRE, ecrit tel quel", function()
        slash("boss name Entombed Sentinels")
        assert.are.same({ "entombed sentinels" }, _G.GideonRaidDB.intermission.bossNames)
        assert.is_true(contains(messages(), "Target encounter name 'entombed sentinels' added"), messages())
        fire("ENCOUNTER_START", TARGET_ID, "ENTOMBED SENTINELS", 16, 20)
        stub.fireTickers(450)
        assert.is_true(panel():IsShown(), "le nom est compare sans tenir compte de la casse")
    end)

    it("/gr boss name sans texte : refuse, rien n'est persiste", function()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss name")
        assert.is_true(contains(lastMessage(), "Empty encounter name"), tostring(lastMessage()))
        assert.are.same({}, _G.GideonRaidDB.intermission.bossNames)
    end)

    -- ------------------------------------------------------------ IDLOG ---
    it("/gr idlog on|off se persiste et refuse une valeur inconnue", function()
        slash("idlog on")
        assert.is_true(_G.GideonRaidDB.intermission.idlog)
        assert.is_true(contains(messages(), "Encounter id log = enabled"), messages())
        assert.is_true(contains(messages(), "encounter seen: id="), messages(), "la procedure est rappelee")

        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("idlog off")
        assert.is_false(_G.GideonRaidDB.intermission.idlog)
        assert.is_true(contains(messages(), "Encounter id log = disabled"), messages())

        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("idlog peut-etre")
        assert.is_true(contains(lastMessage(), "Unknown value 'peut-etre'"), tostring(lastMessage()))
        assert.is_false(_G.GideonRaidDB.intermission.idlog, "rien ne doit etre ecrit")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("idlog")
        assert.is_true(contains(messages(), "Encounter id log: disabled"), messages())
        assert.is_true(contains(messages(), "/gr boss list"), messages())
    end)

    it("/gr idlog on : CHAQUE encounter est affiche ET memorise (mesure de l'id reel)", function()
        slash("idlog on")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        assert.is_true(contains(messages(), "encounter seen: id=2594 name=Entombed Sentinels difficulty=16 group=20"), messages())
        -- ... meme quand aucun boss cible n'est configure (c'est un outil de mesure).
        assert.is_false(panel():IsShown())
        local seen = _G.GideonRaidDB.intermission.seenEncounters
        assert.are.equal(1, #seen)
        assert.are.equal(TARGET_ID, seen[1].id)
        assert.are.equal(TARGET_NAME, seen[1].name)
        assert.are.equal(16, seen[1].difficulty)
        assert.are.equal(20, seen[1].groupSize)
        assert.is_number(seen[1].at, "l'horodatage du client est joint a l'observation")
        assert.are.equal("2026-09-22 21:00:00", seen[1].clock)

        -- Les derniers vus restent consultables, du plus recent au plus ancien.
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("boss list")
        assert.is_true(contains(messages(), "Encounters memorized by the idlog (2"), messages())
        assert.is_true(contains(messages(), "id=9999 name=Some Other Boss"), messages())
        assert.is_true(contains(messages(), "id=2594 name=Entombed Sentinels"), messages())
    end)

    it("idlog off : plus aucune ligne, plus rien de memorise", function()
        slash("idlog off")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        assert.is_false(contains(messages(), "encounter seen: id=2594"), messages())
        assert.are.equal(0, #_G.GideonRaidDB.intermission.seenEncounters)
    end)

    -- -------------------------------------------------- OVERRIDE MANUEL ---
    it("/gr inter on : override MANUEL, un encounter quel que soit le boss", function()
        slash("inter on")
        assert.is_true(_G.GideonRaidDB.intermission.enabled)
        assert.is_true(_G.GideonRaidDB.intermission.overrideEncounter)
        assert.is_true(contains(messages(), "Manual override armed"), messages())

        -- Un boss INCONNU du tout : le panneau s'ouvre quand meme, parce que le
        -- joueur l'a demande explicitement.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        assert.is_true(contains(messages(), "MANUAL OVERRIDE"), messages())
        stub.fireTickers(450)
        assert.is_true(panel():IsShown())

        -- ... et l'override est CONSOMME a la fin de cet encounter.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_END")
        assert.is_false(_G.GideonRaidDB.intermission.overrideEncounter, "l'override doit etre consomme")
        assert.is_true(contains(messages(), "Manual override consumed"), messages())
        assert.is_false(panel():IsShown())

        -- L'encounter suivant repart du filtre : un boss inconnu n'ouvre plus (le
        -- defaut livre est bien la, mais ce n'est pas lui).
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown())
        assert.is_true(contains(messages(), "is NOT the configured target"), messages())
    end)

    it("/gr inter off desarme aussi l'override (rien ne peut s'ouvrir plus tard)", function()
        slash("inter on")
        slash("inter off")
        assert.is_false(_G.GideonRaidDB.intermission.enabled)
        assert.is_false(_G.GideonRaidDB.intermission.overrideEncounter)
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown(), "desactive = aucune ouverture")
    end)

    -- ------------------------------------------- VALEUR ILLISIBLE EN JEU ---
    it("une panne de la decision (Core qui leve) reste un REFUS, sans erreur Lua", function()
        slash("boss " .. tostring(TARGET_ID))
        -- La decision est appelee SOUS pcall : une erreur de comparaison (valeur
        -- secrete) ne doit ni ouvrir le panneau ni casser le flux.
        local original = ns.BossFilter.evaluate
        ns.BossFilter.evaluate = function()
            error("This value is secret")
        end
        local ok = pcall(function()
            fire("ENCOUNTER_START", TARGET_ID, TARGET_NAME, 16, 20)
            stub.fireTickers(2000)
        end)
        ns.BossFilter.evaluate = original
        assert.is_true(ok, "la couche de rendu ne doit pas laisser remonter l'erreur")
        assert.is_false(panel():IsShown(), "une lecture impossible = aucune ouverture automatique")
        assert.is_true(contains(messages(), "could not be read"), messages())
    end)

    it("un argument non exploitable (table) n'ouvre pas non plus", function()
        slash("boss " .. tostring(TARGET_ID))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        fire("ENCOUNTER_START", { "pas un id" }, { "pas un nom" }, 16, 20)
        stub.fireTickers(2000)
        assert.is_false(panel():IsShown())
        assert.is_true(contains(messages(), "is NOT the configured target"), messages())
    end)

    -- ------------------------------------------------------------- AIDE ---
    it("documente /gr boss et /gr idlog dans l'aide et dans /gr inter status", function()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("inconnu")
        assert.is_true(contains(messages(), "/gr boss <id>"), messages())
        assert.is_true(contains(messages(), "/gr idlog [on|off]"), messages())
        assert.is_true(contains(messages(), "/gr sound test start"), messages())

        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("inter status")
        assert.is_true(contains(messages(), "auto-open target:"), messages())
        assert.is_true(contains(messages(), "encounter id log: disabled"), messages())
    end)

    it("les acquis du panneau restent intacts apres un refus (placement, croix)", function()
        fire("ENCOUNTER_START", OTHER_ID, "Some Other Boss", 16, 20)
        -- Le placement manuel fonctionne toujours, et le panneau de combat aussi.
        slash("inter place")
        assert.is_true(panel():IsShown())
        panel().close:Click()
        assert.is_false(panel():IsShown())
    end)
end)

-- ===========================================================================
-- 3. /gr sound test start (le son de DEBUT d'intermission, a la demande)
-- ===========================================================================
describe("BossFilter : /gr sound test start", function()
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
        wowenv.loadAddon()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
    end)
    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    it("joue le fichier de depart, une seule fois, sur le canal Master", function()
        _G.SlashCmdList["GIDEONRAID"]("sound test start")
        assert.are.equal(1, #stub.sounds)
        assert.are.equal("Interface\\AddOns\\GideonRaid\\Sound\\intermission-start.ogg", stub.sounds[1].path)
        assert.are.equal("Master", stub.sounds[1].channel)
        assert.is_true(contains(messages(), "Intermission start sound: intermission-start.ogg"), messages())
    end)

    it("respecte /gr sound off et un etat inconnu reste refuse", function()
        _G.SlashCmdList["GIDEONRAID"]("sound off")
        _G.SlashCmdList["GIDEONRAID"]("sound test start")
        assert.are.equal(0, #stub.sounds, "son coupe = silence, meme pour un test")
        assert.is_true(contains(messages(), "disabled"), messages())
        -- Un etat d'assignation reste refuse comme avant.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sound test bidon")
        assert.is_true(contains(messages(), "Unknown sound 'bidon'"), messages())
        assert.is_true(contains(messages(), "1v3r, 2v2r, 3v1r, start"), messages())
    end)
end)
