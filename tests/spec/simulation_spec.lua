--[[--------------------------------------------------------------------------
    tests/spec/simulation_spec.lua   (busted)

    Tests HORS JEU du MODE SIMULATION (Core/Simulation.lua, logique PURE), apres
    le 4e test en jeu :

      1. "Groupe inter" : la repetition d'intermission s'ouvre IMMEDIATEMENT
         (plus de delai de 3 s) et c'est le JOUEUR qui la ferme (croix ou bouton
         Fermer) : un seul cycle, aucune fermeture automatique, aucune relance ;
      2. "Aide au ping" : une FENETRE D'INFORMATION courte (comment binder les
         pings + « pendant le boss, quand le panneau dit PING : OUI, tu te pinges
         toi-meme »). La sequence guidee (compte a rebours, trois pings annonces,
         bouton « ping pose ») a disparu.

    Ce que ces tests verrouillent :
      - des VALEURS INCONNUES REFUSEES : sous-commande inconnue, option collee a
        la sous-commande (l'ancien `cycles=N`), argument non tableau -> refus
        explicite, jamais devine ;
      - l'HONNETETE : l'addon ne peut PAS detecter un ping (aucune API ne le
        rapporte) et ne l'affirmera jamais ; un ping ne s'affiche qu'en groupe ;
      - la REPETITION ne montre JAMAIS de compte a rebours contradictoire (sans
        boss il n'y a pas d'orbe a lire) et ne publie rien.
----------------------------------------------------------------------------]]
--
--
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

describe("Simulation : constantes, resolution des commandes et des pings (pur)", function()
    local ns = wowenv.loadCore()
    local S = ns.Simulation

    before_each(function()
        -- La langue ACTIVE est un etat de module : on repart toujours de
        -- l'anglais (langue officielle) pour que les tests soient independants.
        ns.Locale.setActive("en")
    end)

    it("expose les constantes du mode simulation", function()
        assert.are.equal(3, S.SCHEMA_VERSION)
        assert.are.same({ "Warning", "OnMyWay", "Assist" }, S.PING_SEQUENCE)
        assert.are.equal("OPEN", S.RUN_PHASE.OPEN)
        assert.are.equal("DONE", S.RUN_PHASE.DONE)
        assert.are.same({
            inter = "inter",
            group = "inter",
            groupe = "inter",
            ping = "ping",
            stop = "stop",
            -- LA VITRINE DE STYLE : `style` ouvre la vitrine (option facultative :
            -- le candidat a previsualiser) et `anim` coupe/active ses animations.
            style = "style",
            styles = "style",
            anim = "anim",
            animation = "anim",
            animations = "anim",
        }, S.COMMANDS)
        -- LES SOUS-COMMANDES A OPTION, et elles seules : tout le reste refuse un
        -- mot de trop (Core ne devine jamais).
        assert.is_true(S.OPTION_COMMANDS.style and S.OPTION_COMMANDS.anim)
        assert.is_nil(S.OPTION_COMMANDS.inter)
        assert.is_nil(S.OPTION_COMMANDS.stop)
    end)

    it("annonce les TROIS pings dans un ordre EXPLICITE et lisible", function()
        assert.are.equal("Warning -> On My Way -> Assist", S.pingSequenceLine())
        ns.Locale.setActive("fr")
        assert.are.equal("Avertissement -> En route -> Aide", S.pingSequenceLine())
    end)

    it("relie chaque ping a SON etat canonique, et refuse le reste", function()
        assert.are.equal("1V3R", S.stateKeyForPing("Warning"))
        assert.are.equal("2V2R", S.stateKeyForPing("OnMyWay"))
        assert.are.equal("3V1R", S.stateKeyForPing("Assist"))
        for _, bad in ipairs({ "warning", "Attack", "", "Avertissement", "3V1R" }) do
            assert.is_nil(S.stateKeyForPing(bad), tostring(bad))
        end
        assert.is_nil(S.stateKeyForPing(nil))
        assert.is_nil(S.stateKeyForPing(42))
        assert.is_nil(S.stateKeyForPing({}))
    end)

    it("resout les sous-commandes /gideon sim et REFUSE toute valeur inconnue", function()
        assert.are.equal("inter", S.resolveCommand("inter"))
        assert.are.equal("inter", S.resolveCommand("group"))
        assert.are.equal("inter", S.resolveCommand("groupe"))
        assert.are.equal("inter", S.resolveCommand("  INTER "))
        assert.are.equal("ping", S.resolveCommand("ping"))
        assert.are.equal("ping", S.resolveCommand("Ping"))
        assert.are.equal("stop", S.resolveCommand("stop"))
        for _, bad in ipairs({ "bidon", "", "   ", "inter 3", "groupes", "ping2" }) do
            assert.is_nil(S.resolveCommand(bad), tostring(bad))
        end
        assert.is_nil(S.resolveCommand(nil))
        assert.is_nil(S.resolveCommand(42))
        assert.is_nil(S.resolveCommand({}))
    end)

    it("parse /gideon sim : la sous-commande SEULE, toute option est REFUSEE", function()
        local mode, options = S.parseCommand("inter")
        assert.are.equal("inter", mode)
        assert.are.same({}, options)
        local alias, aliasOptions = S.parseCommand("  GROUPE  ")
        assert.are.equal("inter", alias)
        assert.are.same({}, aliasOptions)
        assert.are.equal("ping", S.parseCommand("ping"))
        assert.are.equal("stop", S.parseCommand("stop"))
        -- L'ancien `cycles=N` n'existe plus : il est REFUSE avec un message,
        -- jamais ignore en silence (le joueur doit le savoir).
        for _, raw in ipairs({ "inter cycles=3", "inter 3", "ping cycles=1", "groupe cycles=abc" }) do
            local refused, refusedOptions, err = S.parseCommand(raw)
            assert.is_nil(refused, raw)
            assert.is_nil(refusedOptions, raw)
            assert.are.equal(ns.Locale.t("err.simNoOption"), err, raw)
            assert.is_true(contains(err, "no option here"), err)
        end
        -- Une sous-commande inconnue reste SANS erreur : l'appelant affiche l'aide.
        local unknown, unknownOptions, unknownErr = S.parseCommand("bidon")
        assert.is_nil(unknown)
        assert.is_nil(unknownOptions)
        assert.is_nil(unknownErr)
        assert.is_nil(S.parseCommand(""))
        assert.is_nil(S.parseCommand(nil))
        assert.is_nil(S.parseCommand(42))
    end)
end)

describe("Simulation : repetition d'intermission (logique pure)", function()
    local ns = wowenv.loadCore()
    local S, I = ns.Simulation, ns.Intermission

    before_each(function()
        ns.Locale.setActive("en")
    end)

    it("cree une repetition OUVERTE tout de suite, sans aucune option", function()
        local run = S.newRun()
        assert.is_table(run)
        assert.are.equal(S.RUN_PHASE.OPEN, run.phase)
        assert.is_false(run.closed)
        assert.is_false(S.runFinished(run))
        -- Un tableau vide est accepte (aucune option), un non-tableau est REFUSE.
        assert.is_table(S.newRun({}))
        local refused, err = S.newRun("inter")
        assert.is_nil(refused)
        assert.are.equal(ns.Locale.t("err.invalidSimulation"), err)
        -- Un tableau qui porte une option est REFUSE (l'ancien cycles=N) : plus
        -- aucune repetition longue n'est possible, la demande a change.
        local withOption, optionErr = S.newRun({ cycles = 3 })
        assert.is_nil(withOption)
        assert.are.equal(ns.Locale.t("err.simNoOption"), optionErr)
    end)

    it("ne se ferme JAMAIS tout seul : c'est le joueur qui ferme", function()
        local run = S.newRun()
        -- Aucune fonction de ce module ne fait avancer le temps : la seule
        -- transition possible est closeRun (la main du joueur).
        assert.is_true(S.closeRun(run) ~= nil)
        assert.is_true(S.runFinished(run))
        assert.is_true(run.closed)
        assert.are.equal(S.RUN_PHASE.DONE, run.phase)
        -- Idempotent : une seconde fermeture ne change rien et ne leve pas.
        S.closeRun(run)
        assert.is_true(run.closed)
        -- Un run invalide est refuse explicitement.
        assert.is_nil(S.closeRun(nil))
        assert.are.equal(ns.Locale.t("err.invalidSimulation"), select(2, S.closeRun(nil)))
    end)

    it("rend un instantane affichable, avec le bandeau SIMULATION", function()
        local run = S.newRun()
        local snap = S.snapshot(run)
        assert.is_table(snap)
        assert.is_true(snap.open)
        assert.is_false(snap.done)
        assert.are.equal(2, #snap.bannerLines)
        assert.are.equal(ns.Locale.t("sim.banner"), snap.bannerLines[1])
        assert.are.equal(ns.Locale.t("sim.singleLine"), snap.bannerLines[2])
        assert.is_true(contains(snap.bannerLines[1], "SIMULATION"))
        assert.is_true(contains(snap.bannerLines[2], "YOU CLOSE THE PANEL YOURSELF"))
        assert.are.equal(ns.Locale.t("sim.rehearsal.headline"), snap.headline)
        -- Aucun compte a rebours nulle part : sans boss il n'y a rien a compter.
        assert.is_false(contains(snap.headline, "%"))
        local refused, err = S.snapshot(nil)
        assert.is_nil(refused)
        assert.are.equal(ns.Locale.t("err.invalidSimulation"), err)
    end)

    it("remplace le titre de combat par un titre de repetition, sans compter", function()
        local run = S.newRun()
        local state = I.newState()
        I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
        I.tick(state, 1)
        local combat = I.snapshot(state, "anchors")
        -- Le titre REEL du combat compte les secondes restantes...
        assert.is_true(contains(combat.headline, "LOOK AT THE ORB COLOR"))

        local view = S.forRehearsal(combat, run)
        assert.is_true(view.rehearsal)
        -- ... la repetition le remplace : aucun orbe a lire, aucun compte a
        -- rebours contradictoire, et la note explique pourquoi.
        assert.is_false(contains(view.headline, "LOOK AT THE ORB COLOR"))
        assert.is_false(contains(view.headline, "%"))
        assert.are.equal(ns.Locale.t("sim.rehearsal.headline"), view.headline)
        assert.are.equal(#combat.lines + 1, #view.lines)
        assert.are.equal(ns.Locale.t("sim.rehearsal.note"), view.lines[#view.lines])
        -- Le reste du panneau est INTACT (l'etat, le ping, les boutons).
        assert.are.equal(combat.stateText, view.stateText)
        assert.are.equal(combat.showButtons, view.showButtons)
        assert.are.equal(combat.pingBanner, view.pingBanner)
        assert.is_true(view.showButtons)
        -- L'instantane de combat n'a PAS ete modifie (copie explicite).
        assert.is_true(contains(combat.headline, "LOOK AT THE ORB COLOR"))
        -- Sans repetition, la vue est rendue telle quelle.
        assert.are.equal(combat, S.forRehearsal(combat, nil))
        assert.is_nil(S.forRehearsal(nil, run))
    end)

    it("est deterministe : memes entrees, memes chaines", function()
        local function once()
            local run = S.newRun()
            local state = I.newState()
            I.start(state, { leadSeconds = 0 })
            I.declare(state, "2V2R")
            local view = S.forRehearsal(I.snapshot(state, "color"), run)
            return { view.headline, view.lines[1], view.simBannerLines[1], view.simBannerLines[2], view.stateText }
        end
        assert.are.same(once(), once())
    end)

    it("respecte les bornes de la machinerie d'intermission (aucune derive)", function()
        -- La timeline de la repetition passe par le MEME validateur que le flux
        -- reel : pas de temps d'avance, la fenetre de visibilite et la duree
        -- configurees (le panneau est simplement VISIBLE tout de suite).
        local state = I.newState()
        assert.is_table(I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 }))
        assert.are.equal("VISIBLE", state.phase)
        I.declare(state, "2V2R")
        assert.are.equal("2V2R", state.declaration)
        -- Tant que rien ne fait avancer la repetition, elle reste OUVERTE : c'est
        -- le joueur qui ferme (jamais DONE par le temps).
        assert.are.equal("VISIBLE", state.phase)
    end)
end)

describe("Simulation : fenetre d'aide au ping (logique pure)", function()
    local ns = wowenv.loadCore()
    local S, I = ns.Simulation, ns.Intermission

    before_each(function()
        ns.Locale.setActive("en")
    end)

    it("explique le binding, le geste, le groupe et l'honnetete (EN + FR)", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local view = S.pingHelpView(nil)
            assert.are.equal(ns.Locale.t("sim.ping.title"), view.title)
            assert.are.equal(ns.Locale.t("sim.ping.helpHeadline"), view.headline)
            assert.are.equal(ns.Locale.t("ui.close"), view.closeLabel)
            -- 1er point : comment binder (une touche par ping, dans les Options).
            assert.is_true(contains(view.lines[1], "Options > Keybindings") or contains(view.lines[1], "Options > Raccourcis"))
            assert.is_true(contains(view.lines[1], I.pingLabel("Warning")))
            -- 2e point : le geste operationnel (se pinger soi-meme, sous le boss).
            local gesture = view.lines[2]
            assert.is_true(contains(gesture, "YOUR OWN") or contains(gesture, "TON propre"))
            assert.is_true(contains(gesture, "PING: YES") or contains(gesture, "PING : OUI"))
            assert.is_true(contains(gesture, "press your key") or contains(gesture, "appuie sur ta touche"))
            -- Le geste de l'ANCRE, le rappel groupe et l'honnetete.
            assert.is_true(contains(view.lines[3], "1V3R"))
            assert.is_true(contains(view.lines[4], "GROUP or a RAID") or contains(view.lines[4], "GROUPE ou en RAID"))
            assert.is_true(contains(view.lines[5], "CANNOT detect") or contains(view.lines[5], "NE PEUT PAS detecter"))
            -- Les trois pings, dans l'ordre explicite, sans touche connue ici.
            assert.are.equal(3, #view.keyLines)
            for index = 1, #view.keyLines do
                assert.is_true(contains(view.keyLines[index], I.pingLabel(S.PING_SEQUENCE[index])))
                assert.is_true(contains(view.keyLines[index], "no key bound") or contains(view.keyLines[index], "aucune touche"))
            end
        end
    end)

    it("affiche la touche reellement bindee (resolveur INJECTE, sous pcall)", function()
        ns.Locale.setActive("fr")
        local asked = 0
        local view = S.pingHelpView(function(bindNames)
            asked = asked + 1
            assert.is_table(bindNames)
            return "Q"
        end)
        assert.are.equal(3, asked)
        for index = 1, #view.keyLines do
            assert.is_true(contains(view.keyLines[index], "= Q"), view.keyLines[index])
        end
        -- Core/ n'appelle JAMAIS l'API de raccourci : le resolveur est injecte et
        -- appele sous pcall (un resolveur fautif ne casse rien).
        local broken = S.pingHelpView(function()
            error("boom")
        end)
        assert.are.equal(3, #broken.keyLines)
        assert.is_true(contains(broken.keyLines[1], "aucune touche"))
        -- Sans resolveur du tout, la fenetre reste complete.
        assert.is_table(S.pingHelpView(nil))
    end)

    it("n'utilise que des cles de langue existantes (aucun trou, EN + FR)", function()
        local Locale = ns.Locale
        local keys = {
            "sim.banner",
            "sim.singleLine",
            "sim.rehearsal.headline",
            "sim.rehearsal.note",
            "sim.notOpen",
            "sim.refused.live",
            "sim.refused.running",
            "sim.stoppedByEncounter",
            "sim.ping.title",
            "sim.ping.helpHeadline",
            "sim.ping.helpBind",
            "sim.ping.helpGesture",
            "sim.ping.keysHeader",
            "sim.ping.keyLine",
            "sim.ping.noKeyLine",
            "sim.ping.anchorNote",
            "sim.ping.group",
            "sim.ping.noDetection",
            "cmd.sim.help",
            "cmd.sim.unknown",
            "cmd.sim.inter",
            "cmd.sim.closed",
            "cmd.sim.none",
            "cmd.sim.pingStart",
            "panel.simInterButton",
            "panel.simPingButton",
            "panel.placeButton",
            "panel.lockButton",
            "panel.unlockButton",
            "ui.mainTitle",
            "ui.closeCross",
            "ui.closeTooltip",
            "err.invalidSimulation",
            "err.simNoOption",
        }
        for index = 1, #keys do
            local key = keys[index]
            assert.is_string(Locale.t(key, "en"), key)
            assert.is_string(Locale.t(key, "fr"), key)
            assert.are_not.equal(key, Locale.t(key, "en"), key .. " (en manquant)")
            assert.are_not.equal(key, Locale.t(key, "fr"), key .. " (fr manquant)")
        end
    end)
end)
