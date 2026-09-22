--[[--------------------------------------------------------------------------
    tests/spec/simulation_spec.lua   (busted)

    Tests HORS JEU du MODE SIMULATION (Core/Simulation.lua, logique PURE) :

      1. "Groupe inter" : repetition complete d'intermissions en accelere
         (ouverture apres 3 s, fermeture apres ~20 s, 1 cycle par defaut depuis
         le retour en jeu du raid lead, jusqu'a 9 avec `cycles=N`), sans boss,
         sans raid, sans ENCOUNTER_START et sans jamais lire d'evenement de
         combat ;
      2. "Entrainement au ping" : sequence GUIDEe des 3 pings natifs
         (Warning -> OnMyWay -> Assist) qui enseigne le geste de l'ANCRE
         (survoler SON PROPRE cadre de personnage = se pinger soi-meme), avec la
         touche reellement bindee INJECTEE (Core/ n'appelle aucune API) et un
         compte a rebours visible.

    Ce que ces tests verrouillent :
      - des ENTREES BORNEES : toute option numerique est bornee (jamais de
        sequence infinie ni vide) ;
      - des VALEURS INCONNUES REFUSEES : option non numerique, ping inconnu,
        sequence vide, sous-commande inconnue -> refus explicite, jamais devine ;
      - l'ORDRE EXPLICITE des pings et l'invariant "au plus UNE transition par
        appel" (un enorme dt ne saute jamais un cycle ni un ping) ;
      - l'HONNETETE : l'addon ne peut PAS detecter un ping (aucune API ne le
        rapporte) et le dit ; rien n'est jamais invente.
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

    it("expose les bornes et les valeurs par defaut du raid lead", function()
        -- Retour en jeu : UN seul cycle par defaut (« garde la simulation sur
        -- 1 test intermission »). Les bornes 1..9 restent.
        assert.are.equal(1, S.DEFAULT_CYCLES)
        assert.are.equal(1, S.MIN_CYCLES)
        assert.are.equal(9, S.MAX_CYCLES)
        assert.are.equal(3, S.DEFAULT_OPEN_DELAY_SECONDS)
        assert.are.equal(30, S.MAX_OPEN_DELAY_SECONDS)
        assert.are.equal(ns.Intermission.DEFAULT_DURATION_SECONDS, S.DEFAULT_INTERMISSION_SECONDS)
        assert.are.equal(20, S.DEFAULT_INTERMISSION_SECONDS)
        assert.are.equal(15, S.DEFAULT_PING_STEP_SECONDS)
        assert.are.equal(5, S.DEFAULT_PING_GAP_SECONDS)
        assert.are.equal(2, S.SCHEMA_VERSION)
    end)

    it("annonce les TROIS pings dans un ordre EXPLICITE et lisible", function()
        assert.are.same({ "Warning", "OnMyWay", "Assist" }, S.PING_SEQUENCE)
        -- La sequence affichee porte les LIBELLES (comme le client du joueur).
        assert.are.equal("Warning -> On My Way -> Assist", S.pingSequenceLine())
        ns.Locale.setActive("fr")
        assert.are.equal("Avertissement -> En route -> Aide", S.pingSequenceLine())
        ns.Locale.setActive("en")
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

    it("resout les sous-commandes /gr sim et REFUSE toute valeur inconnue", function()
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

    it("parse l'argument complet de /gr sim : mode + option bornee cycles=N", function()
        local mode, options = S.parseCommand("inter")
        assert.are.equal("inter", mode)
        assert.are.same({}, options)
        local alias, aliasOptions = S.parseCommand("  GROUPE  ")
        assert.are.equal("inter", alias)
        assert.are.same({}, aliasOptions)
        -- Option explicite : un test LONG reste possible (bornes 1..9 cote newRun).
        local long, longOptions = S.parseCommand("inter cycles=5")
        assert.are.equal("inter", long)
        assert.are.equal(5, longOptions.cycles)
        local spaced, spacedOptions = S.parseCommand("inter cycles = 2")
        assert.are.equal("inter", spaced)
        assert.are.equal(2, spacedOptions.cycles)
        -- Valeurs inconnues REFUSEES avec un message explicite, jamais devinees.
        local bad, badOptions, badErr = S.parseCommand("inter cycles=abc")
        assert.is_nil(bad)
        assert.is_nil(badOptions)
        assert.matches("cycles=abc", badErr)
        assert.matches("invalid simulation option", badErr)
        assert.is_nil(select(1, S.parseCommand("ping cycles=3")))
        assert.matches("cycles=3", select(3, S.parseCommand("ping cycles=3")))
        assert.is_nil(select(1, S.parseCommand("inter 3")))
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
        -- La langue ACTIVE est un etat de module : on repart toujours de
        -- l'anglais (langue officielle) pour que les tests soient independants.
        ns.Locale.setActive("en")
    end)

    --- Rejoue la repetition complete et renvoie la suite des transitions.
    local function playAll(run, step)
        local events = {}
        for _ = 1, 100000 do
            if S.runFinished(run) then
                break
            end
            local _, event = S.advance(run, step)
            if event ~= nil then
                events[#events + 1] = event
            end
        end
        return events
    end

    it("cree une repetition aux valeurs par defaut (1 cycle, 3 s, 20 s)", function()
        local run = S.newRun()
        assert.is_table(run)
        -- Retour en jeu : UN cycle par defaut, pas trois.
        assert.are.equal(S.DEFAULT_CYCLES, run.cycles)
        assert.are.equal(1, run.cycles)
        assert.are.equal(3, run.openDelay)
        assert.are.equal(20, run.duration)
        assert.are.equal(I.VISIBILITY_SECONDS, run.visibility)
        assert.are.equal("WAIT", run.phase)
        assert.are.equal(1, run.index)
        assert.is_false(S.runFinished(run))
        -- Un tableau vide est accepte (tout par defaut), un non-tableau est refusE.
        assert.is_table(S.newRun({}))
        local refused, err = S.newRun("inter")
        assert.is_nil(refused)
        assert.are.equal(ns.Locale.t("err.invalidSimulation"), err)
    end)

    it("repetition par DEFAUT : un seul cycle, une ouverture, une fermeture", function()
        local run = S.newRun()
        local events = playAll(run, 0.25)
        assert.are.same({ "open", "close" }, events)
        assert.is_true(S.runFinished(run))
        assert.are.equal(1, run.closed)
        assert.are.equal("SIMULATED INTERMISSION 1/1", S.snapshot(run).cycleLine)
        -- Termine : plus rien, meme avec un enorme dt.
        assert.is_nil(select(2, S.advance(run, 1000)))
    end)

    it("BORNE les options numeriques et REFUSE les valeurs non numeriques", function()
        local low = S.newRun({ cycles = 0, openDelaySeconds = -5, visibilitySeconds = -3, durationSeconds = 1 })
        assert.are.equal(1, low.cycles)
        assert.are.equal(0, low.openDelay)
        assert.are.equal(1, low.visibility)
        -- La duree doit rester STRICTEMENT superieure a la fenetre de visibilite.
        assert.are.equal(2, low.duration)

        local high = S.newRun({ cycles = 99, openDelaySeconds = 999, visibilitySeconds = 500, durationSeconds = 999 })
        assert.are.equal(9, high.cycles)
        assert.are.equal(30, high.openDelay)
        assert.are.equal(10, high.visibility)
        assert.are.equal(120, high.duration)

        local refused, err = S.newRun({ cycles = "3" })
        assert.is_nil(refused)
        assert.matches("cycles", err)
        assert.matches("invalid simulation option", err)
        assert.is_nil(S.newRun({ openDelaySeconds = true }))
        assert.is_nil(S.newRun({ durationSeconds = {} }))
    end)

    it("ouvre apres le delai, ferme apres la duree et enchaine les cycles", function()
        local run = S.newRun({ cycles = 3, openDelaySeconds = 3, visibilitySeconds = 3, durationSeconds = 20 })
        -- 2,75 s : toujours rien a l'ecran (pas a la limite exacte du delai).
        for _ = 1, 11 do
            local _, event = S.advance(run, 0.25)
            assert.is_nil(event)
        end
        assert.are.equal("WAIT", run.phase)
        -- 3 s : le panneau doit s'ouvrir (1re transition).
        local _, opened = S.advance(run, 0.25)
        assert.are.equal("open", opened)
        assert.are.equal("OPEN", run.phase)
        -- 19,75 s plus tard : toujours ouvert, rien a signaler.
        for _ = 1, 79 do
            local _, event = S.advance(run, 0.25)
            assert.is_nil(event)
        end
        assert.are.equal("OPEN", run.phase)
        -- Fin de l'intermission : fermeture, puis cycle suivant.
        local _, closed = S.advance(run, 0.25)
        assert.are.equal("close", closed)
        assert.are.equal("WAIT", run.phase)
        assert.are.equal(2, run.index)
        assert.are.equal(1, run.closed)

        -- Suite COMPLETE : open/close x3, dans cet ordre, puis TERMINE.
        local events = playAll(run, 0.25)
        assert.are.same({ "open", "close", "open", "close" }, events)
        assert.is_true(S.runFinished(run))
        assert.are.equal(3, run.closed)
        -- Termine : plus aucune transition, meme avec un enorme dt.
        local _, aucun = S.advance(run, 1000)
        assert.is_nil(aucun)
        assert.is_true(S.runFinished(run))
    end)

    it("ne saute JAMAIS une transition, meme avec un enorme dt (1 par appel)", function()
        local run = S.newRun({ cycles = 3, openDelaySeconds = 3, visibilitySeconds = 3, durationSeconds = 20 })
        local events = playAll(run, 1000)
        assert.are.same({ "open", "close", "open", "close", "open", "close" }, events)
        assert.is_true(S.runFinished(run))
        assert.are.equal(3, run.closed)
    end)

    it("ignore les dt invalides (nil, negatif) et reste deterministe", function()
        local function play()
            local run = S.newRun({ cycles = 3 })
            local events = {}
            assert.is_nil(select(2, S.advance(run, -1)))
            assert.is_nil(select(2, S.advance(run, "x")))
            for _, event in ipairs(playAll(run, 0.1)) do
                events[#events + 1] = event
            end
            return events, run.closed
        end
        local first, closedA = play()
        local second, closedB = play()
        assert.are.same(first, second)
        assert.are.equal(closedA, closedB)
        assert.are.equal(3, closedA)
    end)

    it("rend un instantane affichable, avec le bandeau SIMULATION", function()
        local run = S.newRun({ cycles = 3, openDelaySeconds = 3 })
        local snap = S.snapshot(run)
        assert.is_table(snap)
        assert.are.equal(ns.Locale.t("sim.banner"), snap.banner)
        assert.matches("SIMULATION", snap.banner)
        assert.are.equal("SIMULATED INTERMISSION 1/3", snap.cycleLine)
        assert.are.equal("3", snap.countdownText)
        assert.matches("opens in 3 s", snap.headline)
        assert.is_false(snap.done)

        -- Panneau ouvert : le compte a rebours descend, le bandeau reste.
        S.advance(run, 3)
        snap = S.snapshot(run)
        assert.are.equal("OPEN", snap.phase)
        assert.are.equal("20", snap.countdownText)
        S.advance(run, 5)
        snap = S.snapshot(run)
        assert.are.equal("15", snap.countdownText)
        assert.matches("SIMULATION", snap.banner)

        -- Fin de repetition : etat TERMINE, toujours avec le bandeau.
        local _, _ = S.advance(run, 15)
        snap = S.snapshot(run)
        assert.are.equal("WAIT", snap.phase)
        assert.are.equal("SIMULATED INTERMISSION 2/3", snap.cycleLine)

        local refused, err = S.snapshot(nil)
        assert.is_nil(refused)
        assert.are.equal(ns.Locale.t("err.invalidSimulation"), err)
    end)

    it("donne a l'intermission simulee une timeline SANS temps d'avance", function()
        local run = S.newRun({ cycles = 3, visibilitySeconds = 4, durationSeconds = 30 })
        local timeline = S.cycleTimeline(run)
        assert.are.equal(0, timeline.leadSeconds)
        assert.are.equal(4, timeline.visibilitySeconds)
        assert.are.equal(30, timeline.durationSeconds)
        assert.is_nil(S.cycleTimeline(nil))
    end)

    it("respecte les bornes de la machinerie d'intermission (aucune derive)", function()
        -- La timeline simulee passe par le MEME validateur que le flux reel.
        local run = S.newRun({ cycles = 1, visibilitySeconds = 3, durationSeconds = 20 })
        local state = I.newState()
        assert.is_table(I.start(state, S.cycleTimeline(run)))
        assert.are.equal("VISIBLE", state.phase)
        I.tick(state, 3)
        assert.are.equal("DARK", state.phase)
        I.tick(state, 17)
        assert.are.equal("DONE", state.phase)
    end)
end)

describe("Simulation : test des pings natifs (logique pure)", function()
    local ns = wowenv.loadCore()
    local S = ns.Simulation

    before_each(function()
        -- La langue ACTIVE est un etat de module : on repart toujours de
        -- l'anglais (langue officielle) pour que les tests soient independants.
        ns.Locale.setActive("en")
    end)

    local function keyResolver(key)
        return function()
            return key
        end
    end

    it("cree la sequence guidee par defaut (3 pings, 15 s, 5 s)", function()
        local run = S.newPingTest()
        assert.is_table(run)
        assert.are.equal(3, S.pingTestTotal(run))
        assert.are.equal(1, run.index)
        assert.are.equal(15, run.stepSeconds)
        assert.are.equal(5, run.gapSeconds)
        assert.are.equal("STEP", run.phase)
        assert.is_true(S.pingTestActive(run))
        assert.are.equal("Warning", S.currentPing(run))
        assert.is_false(S.pingTestOverdue(run))
        assert.is_nil(S.newPingTest("ping"))
    end)

    it("REFUSE un ping inconnu, une sequence vide ou non numerique", function()
        local refused, err = S.newPingTest({ sequence = { "Warning", "Danger" } })
        assert.is_nil(refused)
        assert.matches("unknown ping", err)
        assert.matches("Danger", err)
        assert.is_nil(S.newPingTest({ sequence = {} }))
        assert.matches("ping sequence", select(2, S.newPingTest({ sequence = {} })))
        assert.is_nil(S.newPingTest({ sequence = "Warning" }))
        assert.is_nil(S.newPingTest({ stepSeconds = "15" }))
        assert.matches("stepSeconds", select(2, S.newPingTest({ stepSeconds = "15" })))
        assert.is_nil(S.newPingTest({ gapSeconds = true }))
        -- Les bornes s'appliquent aux nombres.
        local bounded = S.newPingTest({ stepSeconds = 0, gapSeconds = 999 })
        assert.are.equal(1, bounded.stepSeconds)
        assert.are.equal(30, bounded.gapSeconds)
        -- Une sequence personnalisee valide est acceptee (ordre explicite).
        local custom = S.newPingTest({ sequence = { "Assist", "Warning" } })
        assert.are.equal("Assist", S.currentPing(custom))
        assert.is_nil(S.newPingTest({ sequence = { nil } }))
    end)

    it("n'avance JAMAIS un ping tout seul : seul le OK du joueur avance", function()
        local run = S.newPingTest({ stepSeconds = 15, gapSeconds = 5 })
        for _ = 1, 500 do
            local _, event = S.advancePingTest(run, 1)
            assert.is_nil(event)
        end
        -- 500 s plus tard : toujours sur le meme ping, en retard, jamais valide.
        assert.are.equal("STEP", run.phase)
        assert.are.equal(1, run.index)
        assert.is_true(S.pingTestOverdue(run))
        assert.are.equal(0, S.pingTestRemaining(run))
        assert.are.equal(0, run.confirmed)
    end)

    it("enchaine les trois pings apres validation, avec compte a rebours", function()
        local run = S.newPingTest({ stepSeconds = 15, gapSeconds = 5 })
        -- Validation du 1er ping : attente entre les deux pings.
        assert.is_table(S.confirmPingTest(run))
        assert.are.equal(1, run.confirmed)
        assert.are.equal("WAIT", run.phase)
        assert.are.equal(2, run.index)
        assert.are.equal("OnMyWay", S.currentPing(run))
        assert.are.equal(5, S.pingTestRemaining(run))
        -- 4,75 s : toujours en attente ; 5,0 s : le ping suivant est annonce.
        for _ = 1, 19 do
            assert.is_nil(select(2, S.advancePingTest(run, 0.25)))
        end
        assert.are.equal("WAIT", run.phase)
        local _, announced = S.advancePingTest(run, 0.25)
        assert.are.equal("next", announced)
        assert.are.equal("STEP", run.phase)
        assert.are.equal(15, S.pingTestRemaining(run))
        -- Une validation pendant l'attente est REFUSEE (rien a valider).
        local waiting = S.newPingTest()
        S.confirmPingTest(waiting)
        local refused, err = S.confirmPingTest(waiting)
        assert.is_nil(refused)
        assert.are.equal(ns.Locale.t("err.nothingToConfirm"), err)
        -- Suite complete : 3 pings annonces puis TERMINE.
        S.confirmPingTest(run)
        S.advancePingTest(run, 5)
        S.confirmPingTest(run)
        assert.are.equal("DONE", run.phase)
        assert.is_false(S.pingTestActive(run))
        assert.are.equal(3, run.confirmed)
        assert.is_nil(S.currentPing(run))
        assert.is_nil(S.confirmPingTest(run))
        assert.is_false(S.pingTestOverdue(run))
        assert.are.equal(0, S.pingTestRemaining(run))
    end)

    it("ne saute jamais un ping, meme avec un enorme dt", function()
        local run = S.newPingTest({ stepSeconds = 1, gapSeconds = 1 })
        S.confirmPingTest(run) -- 1er ping valide -> WAIT
        local _, first = S.advancePingTest(run, 1000)
        assert.are.equal("next", first)
        assert.are.equal("STEP", run.phase)
        assert.are.equal(2, run.index)
        local _, second = S.advancePingTest(run, 1000)
        assert.is_nil(second)
        assert.are.equal("STEP", run.phase)
        assert.are.equal(2, run.index)
    end)

    it("affiche en gros le GESTE (survoler SON cadre + touche bindee), jamais une touche inventee", function()
        local run = S.newPingTest()
        -- Touche INJECTEE : c'est la couche de rendu qui lit GetBindingKey.
        local snap = S.pingTestSnapshot(run, keyResolver("Q"))
        assert.is_true(contains(snap.headline, "1. Hover YOUR OWN character frame"))
        assert.is_true(contains(snap.headline, "2. Press Q (Warning)"))
        assert.is_true(contains(snap.headline, "you ping yourself"))
        assert.are.equal("Q", snap.key)
        assert.are.equal("1V3R", snap.stateKey)
        assert.are.equal("Warning", snap.label)
        assert.are.equal("PING 1/3", snap.stepLine)
        assert.is_true(contains(table.concat(snap.lines, "\n"), "Options > Keybindings"))

        -- Sans touche connue : la touche est DESIGNEE, jamais inventee.
        local sans = S.pingTestSnapshot(run, nil)
        assert.is_true(contains(sans.headline, "1. Hover YOUR OWN character frame"))
        assert.is_true(contains(sans.headline, "2. Press your ping key (Warning)"))
        assert.is_nil(sans.key)
        assert.are.equal(ns.Locale.t("sim.ping.yourKey"), sans.yourKey)
        assert.is_true(contains(table.concat(sans.lines, "\n"), "no keybind found"))

        -- Un resolveur qui leve ou renvoie autre chose qu'une chaine : aucune touche.
        local raising = function()
            error("GetBindingKey a leve")
        end
        assert.is_nil(S.pingTestSnapshot(run, raising).key)
        assert.is_nil(S.pingTestSnapshot(run, keyResolver(42)).key)
        assert.is_nil(S.pingTestSnapshot(run, keyResolver("")).key)
        assert.is_nil(S.pingTestSnapshot(nil, keyResolver("Q")))
    end)

    it("enseigne le geste de l'ANCRE : se pinger soi-meme sur son propre cadre", function()
        local run = S.newPingTest()
        local snap = S.pingTestSnapshot(run, keyResolver("Q"))
        local text = table.concat(snap.lines, "\n")
        assert.are.equal(ns.Locale.t("sim.ping.anchorNote"), snap.anchorNote)
        assert.is_true(contains(snap.anchorNote, "1V3R"))
        assert.is_true(contains(snap.anchorNote, "ping yourself where you stand"))
        assert.is_true(contains(text, snap.anchorNote))
        -- La sequence des trois pings reste la verification des raccourcis.
        assert.are.equal(3, snap.total)
        assert.are.equal(1, snap.index)
    end)

    it("rappelle qu'il faut etre en groupe et que l'addon NE PEUT PAS detecter", function()
        local run = S.newPingTest()
        local snap = S.pingTestSnapshot(run, nil)
        local text = table.concat(snap.lines, "\n")
        assert.are.equal(ns.Locale.t("sim.banner"), snap.banner)
        assert.matches("SIMULATION", snap.banner)
        assert.matches("GROUP or a RAID", snap.groupReminder)
        assert.matches("CANNOT detect a ping", snap.noDetection)
        assert.is_true(contains(text, "CANNOT detect a ping"))
        assert.is_true(contains(text, "GROUP or a RAID"))
        assert.is_true(contains(text, "NATIVE ping keybind"))
        assert.matches("time left: 15 s", text)
        -- La touche n'est jamais presentee comme detectee, et le nom du ping suit.
        assert.is_true(contains(snap.headline, "Warning"))
    end)

    it("sert le libelle traduit et le compte a rebours entre les etapes", function()
        local run = S.newPingTest({ stepSeconds = 15, gapSeconds = 5 })
        ns.Locale.setActive("fr")
        local snap = S.pingTestSnapshot(run, keyResolver("A"))
        assert.is_true(contains(snap.headline, "1. Survole TON propre cadre de personnage"))
        assert.is_true(contains(snap.headline, "2. Appuie sur A (Avertissement)"))
        assert.is_true(contains(snap.headline, "tu te pinges toi-meme"))
        assert.is_true(contains(table.concat(snap.lines, "\n"), "temps restant : 15 s"))
        assert.is_true(contains(snap.anchorNote, "geste de l'ANCRE"))
        assert.is_true(contains(snap.groupReminder, "GROUPE ou en RAID"))
        assert.is_true(contains(snap.noDetection, "NE PEUT PAS detecter"))
        S.confirmPingTest(run)
        snap = S.pingTestSnapshot(run, keyResolver("A"))
        assert.are.equal("TIENS-TOI PRET : En route", snap.headline)
        assert.is_true(contains(table.concat(snap.lines, "\n"), "prochain ping dans 5 s"))
        ns.Locale.setActive("en")
    end)

    it("affiche un etat TERMINE honnete (aucun ping detecte)", function()
        local run = S.newPingTest()
        S.confirmPingTest(run)
        S.advancePingTest(run, 5)
        S.confirmPingTest(run)
        S.advancePingTest(run, 5)
        S.confirmPingTest(run)
        local snap = S.pingTestSnapshot(run, nil)
        assert.is_true(snap.done)
        assert.are.equal(ns.Locale.t("sim.ping.finished"), snap.headline)
        assert.matches("PING TRAINING OVER", snap.headline)
        assert.is_true(contains(table.concat(snap.lines, "\n"), "3/3"))
        assert.is_true(contains(table.concat(snap.lines, "\n"), "detected none"))
        assert.are.equal(ns.Locale.t("sim.ping.quit"), snap.quitLabel)
    end)

    it("se quitte a tout moment, proprement et de facon idempotente", function()
        local run = S.newPingTest()
        S.confirmPingTest(run)
        assert.is_table(S.cancelPingTest(run))
        assert.are.equal("DONE", run.phase)
        assert.is_true(run.cancelled)
        assert.is_false(S.pingTestActive(run))
        assert.is_table(S.cancelPingTest(run))
        assert.is_nil(S.cancelPingTest(nil))
        local snap = S.pingTestSnapshot(run, nil)
        assert.is_true(snap.done)
        assert.is_true(snap.cancelled)
        assert.are.equal(1, snap.confirmed)
    end)

    it("n'utilise que des cles de langue existantes (aucun trou)", function()
        local Locale = ns.Locale
        local keys = {
            "sim.banner",
            "sim.cycleLine",
            "sim.running",
            "sim.opens",
            "sim.finished",
            "sim.notOpen",
            "sim.refused.live",
            "sim.refused.running",
            "sim.stoppedByEncounter",
            "sim.ping.title",
            "sim.ping.stepLine",
            "sim.ping.selfSteps",
            "sim.ping.yourKey",
            "sim.ping.anchorNote",
            "sim.ping.ready",
            "sim.ping.nextIn",
            "sim.ping.countdown",
            "sim.ping.overdue",
            "sim.ping.noKey",
            "sim.ping.native",
            "sim.ping.group",
            "sim.ping.noDetection",
            "sim.ping.ok",
            "sim.ping.quit",
            "sim.ping.finished",
            "sim.ping.finishedLine",
            "cmd.sim.help",
            "cmd.sim.unknown",
            "cmd.sim.inter",
            "cmd.sim.finished",
            "cmd.sim.stopped",
            "cmd.sim.none",
            "cmd.sim.pingStart",
            "cmd.sim.pingFinished",
            "cmd.sim.pingStopped",
            "panel.simInterButton",
            "panel.simPingButton",
            "ui.closeCross",
            "ui.closeTooltip",
            "err.invalidSimulation",
            "err.simulationOption",
            "err.pingSequenceEmpty",
            "err.unknownPing",
            "err.nothingToConfirm",
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
