--[[--------------------------------------------------------------------------
    tests/spec/intermission_spec.lua   (busted)
    Tests HORS JEU du module « Intermission Coach ».

    Familles de tests :
      1. la CONNAISSANCE du module : les TROIS etats de couleur (3V1R / 2V2R /
         1V3R), les numeros affiches (2 non ambigu, 1 et 3 ambigus), la regle de
         survie en ADDITION DE COULEURS (4 verts + 4 rouges), la normalisation
         des declarations, le PING du joueur (raccourci natif, aucune macro), le
         planning pre-calcule des intermissions, la lecture du plan prepare hors
         jeu ;
      2. la MACHINE D'ETAT : phases de l'intermission (PENDING = panneau ouvert
         avant l'intermission, visibilite 3 s puis salle obscurcie, DONE =
         fermeture automatique), declaration du joueur, CORRIGER, compte a
         rebours, sortie de phase ;
      3. le PANNEAU DE PLACEMENT (avant le pull) et le contenu MINIMAL du
         panneau de combat.

    Aucun mock d'API WoW ici : Core/Intermission.lua est du Lua 5.1 pur.
    Le temps est INJECTE (dt en secondes) : le module n'appelle jamais GetTime.
    La touche de ping est INJECTEE (resolver) : le module n'appelle jamais
    GetBindingKey (c'est la couche de rendu qui lit le raccourci).
----------------------------------------------------------------------------]]
--
local wowenv = require("tests.support.wowenv")

local INTERMISSION_FIXTURE = "tests/fixtures/assignment_sample.lua"

local function loadFixture()
    local chunk = assert(loadfile(INTERMISSION_FIXTURE))
    return chunk()
end

-- Le mot interdit par docs/CONVENTIONS.md est reconstruit ici pour verifier son
-- absence dans les textes generes sans l'ecrire en clair dans le depot.
local FORBIDDEN_EVENT = "COMBAT_LOG" .. "_EVENT"

--- Recherche LITTERALE : les motifs Lua traitent « - » comme un quantificateur,
--- donc « AU-DESSUS » ne peut pas passer par assert.matches.
local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

describe("Intermission : etats de couleur (modele corrige)", function()
    local I = wowenv.loadCore().Intermission

    it("expose TROIS etats canoniques dans un ordre deterministe", function()
        assert.are.same({ "1V3R", "2V2R", "3V1R" }, I.STATES)
        assert.are.same(I.STATES, I.DECLARATIONS)
        assert.are.equal(3, #I.STATES)
    end)

    it("decrit la composition de chaque etat (verts ET rouges)", function()
        local one = I.getDeclaration("1V3R")
        assert.are.equal("1 GREEN + 3 RED", one.display)
        assert.are.equal("1 green + 3 red", one.orbs)
        assert.are.equal(1, one.greens)
        assert.are.equal(3, one.reds)
        local two = I.getDeclaration("2V2R")
        assert.are.equal("2 GREEN + 2 RED", two.display)
        assert.are.equal(2, two.greens)
        assert.are.equal(2, two.reds)
        local three = I.getDeclaration("3V1R")
        assert.are.equal("3 GREEN + 1 RED", three.display)
        assert.are.equal(3, three.greens)
        assert.are.equal(1, three.reds)
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key)
            assert.are.equal(4, rec.greens + rec.reds, "4 orbes par etat")
        end
    end)

    it("declare le numero : « 2 » non ambigu, « 1 » et « 3 » AMBIGUS", function()
        local two = I.getDeclaration("2V2R")
        assert.is_false(two.numberAmbiguous)
        assert.are.same({ "2" }, two.numbers)
        assert.are.equal("2", two.numberText)
        local one = I.getDeclaration("1V3R")
        local three = I.getDeclaration("3V1R")
        assert.is_true(one.numberAmbiguous)
        assert.is_true(three.numberAmbiguous)
        assert.are.same({ "1", "3" }, one.numbers)
        assert.are.same({ "1", "3" }, three.numbers)
        assert.are.equal("1 or 3", one.numberText)
    end)

    it("associe le ping par COULEUR DOMINANTE (guide raidstrats)", function()
        assert.are.equal("Warning", I.getDeclaration("1V3R").ping)
        assert.are.equal("RED", I.getDeclaration("1V3R").pingColor)
        assert.are.equal("OnMyWay", I.getDeclaration("2V2R").ping)
        assert.are.equal("BLUE", I.getDeclaration("2V2R").pingColor)
        assert.are.equal("Assist", I.getDeclaration("3V1R").ping)
        assert.are.equal("GREEN", I.getDeclaration("3V1R").pingColor)
    end)

    it("donne le complement, la position, le role et le libelle du bouton", function()
        assert.are.equal("3V1R", I.getDeclaration("1V3R").complement)
        assert.are.equal("2V2R", I.getDeclaration("2V2R").complement)
        assert.are.equal("1V3R", I.getDeclaration("3V1R").complement)
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key)
            assert.is_string(rec.actionLine)
            assert.is_true(#rec.actionLine > 10)
            assert.is_string(rec.roleLine)
            assert.is_string(rec.positionLabel)
            assert.is_string(rec.buttonLabel)
            assert.is_true(#rec.buttonLabel > 10)
        end
        assert.matches("HOLD", I.getDeclaration("1V3R").positionLabel)
        assert.matches("MIDDLE", I.getDeclaration("2V2R").positionLabel)
        assert.matches("1V3R", I.getDeclaration("3V1R").positionLabel)
    end)

    it("expose UNE SEULE ligne d'action, avec le GESTE REEl de l'ancre", function()
        -- Politique par defaut (« anchors ») : seule l'ANCRE ping.
        -- Retour en jeu : le ping part la ou est la SOURIS, donc l'ancre survole
        -- son PROPRE cadre de personnage pour se pinger elle-meme.
        local anchor = I.getDeclaration("1V3R").actionLine
        assert.is_true(contains(anchor, "PING: YES"))
        assert.is_true(contains(anchor, "hover YOUR OWN character frame"))
        assert.is_true(contains(anchor, "press your ping key (Warning)"))
        assert.is_true(contains(anchor, "jump on the spot"))
        assert.are.equal("DO NOT PING - go to the middle / under the boss", I.getDeclaration("2V2R").actionLine)
        assert.are.equal("DO NOT PING - run to a ping (a 1V3R)", I.getDeclaration("3V1R").actionLine)
        -- Role : une seule ligne courte, l'etat etant affiche en tres gros a part.
        assert.are.equal("ROLE: ANCHOR", I.getDeclaration("1V3R").roleLine)
        assert.are.equal("ROLE: MIDDLE", I.getDeclaration("2V2R").roleLine)
        assert.are.equal("ROLE: CHASER", I.getDeclaration("3V1R").roleLine)
    end)

    it("ne fabrique PLUS de macro de ping (API reservee a l'UI Blizzard)", function()
        -- Le test de jeu reel a tranche : la macro renvoyait « action utilisable
        -- uniquement par l'UI de Blizzard ». La generation a disparu du module.
        assert.is_nil(I.buildMacro)
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key, "color")
            for _, field in ipairs({ "macroPrimary", "macroFallback", "macroNote", "pingToken" }) do
                assert.is_nil(rec[field], key .. "." .. field)
            end
        end
    end)

    it("complementOf renvoie l'etat qui DOIT rejoindre", function()
        assert.are.equal("3V1R", I.complementOf("1V3R"))
        assert.are.equal("2V2R", I.complementOf("2V2R"))
        assert.are.equal("1V3R", I.complementOf("3 verts"))
        assert.is_nil(I.complementOf("1"))
    end)

    it("sert la variante FRANCAISE quand la langue active est fr", function()
        local nsFr = wowenv.loadCore()
        nsFr.Locale.setActive("fr")
        assert.are.equal("1 VERT + 3 ROUGES", nsFr.Intermission.getDeclaration("1V3R").display)
        assert.are.equal("1 ou 3", nsFr.Intermission.getDeclaration("3V1R").numberText)
        assert.are.equal("ROUGE", nsFr.Intermission.getDeclaration("1V3R").pingColor)
        assert.are.equal("ROLE : ANCRE", nsFr.Intermission.getDeclaration("1V3R").roleLine)
        assert.are.equal("NE PING PAS - va au milieu / sous le boss", nsFr.Intermission.getDeclaration("2V2R").actionLine)
        local _, err = nsFr.Intermission.getDeclaration("1")
        assert.matches("numero 1 ambigu", err)
    end)

    it("renvoie une copie : modifier le resultat ne casse pas la constante", function()
        local rec = I.getDeclaration("2V2R")
        rec.orbs = "corrompu"
        rec.numbers[1] = "9"
        assert.are.equal("2 green + 2 red", I.getDeclaration("2V2R").orbs)
        assert.are.same({ "2" }, I.getDeclaration("2V2R").numbers)
    end)
end)

describe("Intermission : normalisation des declarations", function()
    local I = wowenv.loadCore().Intermission

    it("accepte les compositions courtes", function()
        assert.are.equal("3V1R", I.normalizeDeclaration("3V1R"))
        assert.are.equal("2V2R", I.normalizeDeclaration("2v2r"))
        assert.are.equal("1V3R", I.normalizeDeclaration(" 1 V 3 R "))
        assert.are.equal("3V1R", I.normalizeDeclaration("3 verts + 1 rouge"))
    end)

    it("accepte les formes en lettres", function()
        assert.are.equal("3V1R", I.normalizeDeclaration("vert-vert-vert-rouge"))
        assert.are.equal("1V3R", I.normalizeDeclaration("vert rouge rouge rouge"))
        assert.are.equal("2V2R", I.normalizeDeclaration("vvrr"))
        assert.are.equal("1V3R", I.normalizeDeclaration("vrrr"))
    end)

    it("accepte un seul compte (le reste se deduit) et la couleur dominante", function()
        assert.are.equal("3V1R", I.normalizeDeclaration("3 verts"))
        assert.are.equal("1V3R", I.normalizeDeclaration("1 vert 3 rouges"))
        assert.are.equal("3V1R", I.normalizeDeclaration("vert"))
        assert.are.equal("1V3R", I.normalizeDeclaration("rouge"))
        assert.are.equal("3V1R", I.normalizeDeclaration("majorité verte"))
    end)

    it("accepte le numero 2, seul numero NON ambigu", function()
        assert.are.equal("2V2R", I.normalizeDeclaration("2"))
        assert.are.equal("2V2R", I.normalizeDeclaration(2))
        assert.are.equal("2V2R", I.normalizeDeclaration(" 2 "))
    end)

    it("REFUSE un numero ambigu (1 ou 3) et demande la couleur dominante", function()
        local key, err, info = I.normalizeDeclaration("1")
        assert.is_nil(key)
        assert.matches("ambiguous", err)
        assert.matches("color", err)
        assert.is_true(info.ambiguous)
        assert.are.equal("1", info.number)
        local key3, err3, info3 = I.normalizeDeclaration("3")
        assert.is_nil(key3)
        assert.matches("ambigu", err3)
        assert.is_true(info3.ambiguous)
        assert.is_nil(I.getDeclaration("1"))
        assert.is_nil(I.getDeclaration("3"))
        -- jamais de devinette : la couleur doit etre declaree
        assert.are.equal("1V3R", I.normalizeDeclaration("1 vert"))
    end)

    it("refuse une saisie vide, inconnue ou inexploitable", function()
        assert.is_nil(I.normalizeDeclaration(""))
        assert.is_nil(I.normalizeDeclaration(nil))
        local rec, err = I.getDeclaration("banane")
        assert.is_nil(rec)
        assert.matches("unknown", err)
        local rec2, err2 = I.getDeclaration("3 verts 3 rouges")
        assert.is_nil(rec2)
        assert.matches("not usable", err2)
    end)
end)

describe("Intermission : collisions (addition de couleurs)", function()
    local I = wowenv.loadCore().Intermission

    it("accepte 2V2R + 2V2R (= 4V4R)", function()
        local res = assert(I.checkMeeting("2V2R", "2V2R"))
        assert.is_true(res.ok)
        assert.are.equal(4, res.greens)
        assert.are.equal(4, res.reds)
        assert.are.equal("2V2R+2V2R", res.label)
        assert.are.equal("2V2R", res.required)
    end)

    it("accepte 3V1R + 1V3R (= 4V4R) dans les deux sens", function()
        local forward = assert(I.checkMeeting("3V1R", "1V3R"))
        assert.is_true(forward.ok)
        assert.are.equal(4, forward.greens)
        assert.are.equal(4, forward.reds)
        assert.are.equal("3V1R+1V3R", forward.label)
        assert.is_true(I.checkMeeting("1V3R", "3V1R").ok)
    end)

    it("interdit 3V1R + 2V2R : 5 verts = mort (le « 5g »)", function()
        local res = assert(I.checkMeeting("3V1R", "2V2R"))
        assert.is_false(res.ok)
        assert.are.equal(5, res.greens)
        assert.are.equal(3, res.reds)
        assert.are.equal("3V1R+2V2R", res.label)
        assert.matches("5 green", res.reason)
        assert.is_false(I.checkMeeting("2V2R", "3V1R").ok)
    end)

    it("interdit 1V3R + 1V3R et 3V1R + 3V1R", function()
        local both = assert(I.checkMeeting("1V3R", "1V3R"))
        assert.is_false(both.ok)
        assert.are.equal(2, both.greens)
        assert.are.equal(6, both.reds)
        assert.matches("4 green", both.reason)
        assert.is_false(I.checkMeeting("3V1R", "3V1R").ok)
        assert.are.equal(6, I.checkMeeting("3V1R", "3V1R").greens)
    end)

    it("accepte les formes texte equivalentes : c'est la COULEUR qui compte", function()
        assert.is_true(I.checkMeeting("3 verts", "1 vert 3 rouges").ok)
        assert.is_true(I.checkMeeting("2", "2V2R").ok)
        assert.is_false(I.checkMeeting("3 verts", "2").ok)
    end)

    it("REFUSE de comparer sur un numero ambigu (1 ou 3) et le dit", function()
        local res, err = I.checkMeeting("2", "1")
        assert.is_nil(res)
        assert.matches("ambiguous", err)
        local res2, err2 = I.checkMeeting("1", "3")
        assert.is_nil(res2)
        assert.matches("ambiguous", err2)
    end)

    it("refuse une declaration inconnue", function()
        local res, err = I.checkMeeting("2V2R", "x")
        assert.is_nil(res)
        assert.matches("unknown", err)
    end)
end)

describe("Intermission : ping du joueur (raccourci natif, aucune macro)", function()
    local ns = wowenv.loadCore()
    local I = ns.Intermission

    it("porte les noms de raccourci candidats par etat", function()
        assert.are.same({ "PING_WARNING", "PINGTYPE_WARNING", "PINGSUBJECTTYPE_WARNING", "BINDING_PING_WARNING" }, I.bindNames("1V3R"))
        assert.are.same({ "PING_ONMYWAY", "PING_ON_MY_WAY", "PINGTYPE_ONMYWAY", "BINDING_PING_ONMYWAY" }, I.bindNames("2V2R"))
        assert.are.same({ "PING_ASSIST", "PING_HELP", "PINGTYPE_ASSIST", "BINDING_PING_ASSIST" }, I.bindNames("3V1R"))
        -- Aucun candidat n'emprunte la touche d'un AUTRE ping ("Attaque").
        for _, key in ipairs(I.STATES) do
            for _, name in ipairs(I.bindNames(key)) do
                assert.is_nil(string.find(name, "ATTACK", 1, true), name)
            end
        end
        assert.is_nil(I.bindNames("banane"))
        -- Copie : muter le resultat ne corrompt pas la table du module.
        local list = I.bindNames("1V3R")
        list[1] = "corrompu"
        assert.are.equal("PING_WARNING", I.bindNames("1V3R")[1])
        -- Le premier candidat est aussi expose sur la fiche de l'etat.
        assert.are.equal("PING_WARNING", I.getDeclaration("1V3R").bindName)
    end)

    it("traduit le NOM du ping affiche, jamais l'identifiant canonique", function()
        -- Langue par defaut : anglais (libelles du systeme de ping).
        assert.are.equal("Warning", I.pingLabel("Warning"))
        assert.are.equal("On My Way", I.pingLabel("OnMyWay"))
        assert.are.equal("Assist", I.pingLabel("Assist"))
        -- Identifiant inconnu ou vide : jamais de chaine cassee, jamais "nil".
        assert.are.equal("Banane", I.pingLabel("Banane"))
        assert.are.equal("", I.pingLabel(""))
        assert.are.equal("", I.pingLabel(nil))
        -- Libelles FRANCAIS, mesures en jeu par le raid lead (2026-09-22,
        -- Options > Raccourcis) : « Avertissement », « En route », « Aide ».
        local fr = wowenv.loadCore()
        fr.Locale.setActive("fr")
        assert.are.equal("Avertissement", fr.Intermission.pingLabel("Warning"))
        assert.are.equal("En route", fr.Intermission.pingLabel("OnMyWay"))
        assert.are.equal("Aide", fr.Intermission.pingLabel("Assist"))
    end)

    it("la ligne de politique « color » nomme les pings dans la langue du joueur", function()
        local rec = I.getDeclaration("1V3R", "color")
        assert.is_true(contains(rec.policyLine, "Warning"))
        assert.is_true(contains(rec.policyLine, "On My Way"))
        assert.is_true(contains(rec.policyLine, "Assist"))
        -- La meme ligne, en francais, ne garde AUCUN nom anglais.
        local fr = wowenv.loadCore()
        fr.Locale.setActive("fr")
        local frRec = fr.Intermission.getDeclaration("1V3R", "color")
        assert.is_true(contains(frRec.policyLine, "Avertissement"))
        assert.is_true(contains(frRec.policyLine, "En route"))
        assert.is_true(contains(frRec.policyLine, "Aide"))
        assert.is_nil(string.find(frRec.policyLine, "OnMyWay", 1, true))
    end)

    it("sans touche bindi : nomme le ping et demande un raccourci", function()
        local hint = assert(I.pingHint("1V3R"))
        assert.are.equal("Warning", hint.ping)
        assert.is_nil(hint.key)
        assert.are.equal("PING: Warning - set a keybind in Options > Keybindings", hint.line)
        -- Une touche vide/absurde est traitee comme « pas de raccourci ».
        assert.is_nil(I.pingHint("1V3R", "anchors", "").key)
        assert.is_nil(I.pingHint("1V3R", "anchors", 42).key)
        assert.are.equal("PING: Warning - set a keybind in Options > Keybindings", I.pingHint("1V3R", nil, nil).line)
    end)

    it("avec une touche bindi : dit quelle touche presser", function()
        local hint = assert(I.pingHint("1V3R", "anchors", "Q"))
        assert.are.equal("Q", hint.key)
        assert.are.equal("Warning", hint.ping)
        assert.are.equal("PING_WARNING", hint.bindName)
        assert.are.equal("PING: Warning - press Q", hint.line)
        assert.are.equal("PING: Assist - press ALT-F", I.pingHint("3V1R", "color", "ALT-F").line)
    end)

    it("refuse un etat qui ne ping pas et un numero ambigu", function()
        local hint, err = I.pingHint("2V2R")
        assert.is_nil(hint)
        assert.matches("no ping for MIDDLE", err)
        assert.matches("anchors", err)
        assert.is_nil(I.pingHint("3V1R"))
        local ambiguous, errAmbiguous = I.pingHint("1")
        assert.is_nil(ambiguous)
        assert.matches("ambiguous", errAmbiguous)
        -- En politique « color », les trois etats ping : plus de refus.
        for _, key in ipairs(I.STATES) do
            assert.is_table(I.pingHint(key, "color", "Q"), key)
        end
        -- En politique « none », personne.
        assert.is_nil(I.pingHint("1V3R", "none", "Q"))
    end)

    it("le snapshot injecte la touche lue par la couche de rendu (resolver)", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.declare(st, "1V3R")
        local seen
        local snap = I.snapshot(st, "anchors", function(bindNames)
            seen = bindNames
            return "Q"
        end)
        assert.are.same({ "PING_WARNING", "PINGTYPE_WARNING", "PINGSUBJECTTYPE_WARNING", "BINDING_PING_WARNING" }, seen)
        assert.are.equal("Q", snap.pingHint.key)
        assert.are.equal("PING: Warning - press Q", snap.pingHint.line)
        assert.is_true(contains(table.concat(snap.lines, "\n"), "PING: Warning - press Q"))
    end)

    it("le snapshot sans resolver (ou avec un resolver en erreur) retombe sur le raccourci manquant", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.declare(st, "1V3R")
        local noResolver = I.snapshot(st, "anchors").pingHint
        assert.is_nil(noResolver.key)
        assert.are.equal("PING: Warning - set a keybind in Options > Keybindings", noResolver.line)
        local failing = I.snapshot(st, "anchors", function()
            error("GetBindingKey a leve")
        end).pingHint
        assert.is_nil(failing.key)
        assert.are.equal("PING: Warning - set a keybind in Options > Keybindings", failing.line)
        -- Un resolver qui ne renvoie pas de chaine est ignore aussi.
        local weird = I.snapshot(st, "anchors", function()
            return 42
        end).pingHint
        assert.is_nil(weird.key)
    end)

    it("ne fabrique jamais un texte d'API de ping ni un evenement interdit", function()
        for _, key in ipairs(I.STATES) do
            local hint = assert(I.pingHint(key, "color", "Q"))
            assert.is_nil(string.find(hint.line, "SendMacroPing", 1, true))
            assert.is_nil(string.find(hint.line, "C_Ping", 1, true))
            assert.is_nil(string.find(hint.line, FORBIDDEN_EVENT, 1, true))
        end
    end)
end)

describe("Intermission : timeline pre-calculee", function()
    local I = wowenv.loadCore().Intermission

    it("applique les valeurs par defaut (3 s de visibilite, 2 s de lead)", function()
        local t = assert(I.validateTimeline(nil))
        assert.are.equal(3, t.visibilitySeconds)
        assert.are.equal(I.LEAD_SECONDS, t.leadSeconds)
        assert.are.equal(I.DEFAULT_DURATION_SECONDS, t.durationSeconds)
    end)

    it("accepte une timeline preparee hors jeu", function()
        local t = assert(I.validateTimeline({ name = "Intermission 1", leadSeconds = 1, visibilitySeconds = 4, durationSeconds = 25 }))
        assert.are.equal("Intermission 1", t.name)
        assert.are.equal(1, t.leadSeconds)
        assert.are.equal(4, t.visibilitySeconds)
        assert.are.equal(25, t.durationSeconds)
    end)

    it("borne les valeurs absurdes et garde duree > visibilite", function()
        local t = assert(I.validateTimeline({ leadSeconds = -5, visibilitySeconds = -5, durationSeconds = 0 }))
        assert.are.equal(0, t.leadSeconds)
        assert.are.equal(1, t.visibilitySeconds)
        assert.is_true(t.durationSeconds > t.visibilitySeconds)
        local t2 = assert(I.validateTimeline({ leadSeconds = 99, visibilitySeconds = 99, durationSeconds = 9999 }))
        assert.are.equal(10, t2.leadSeconds)
        assert.are.equal(10, t2.visibilitySeconds)
        assert.are.equal(120, t2.durationSeconds)
    end)

    it("refuse une timeline non table mais non nil", function()
        local t, err = I.validateTimeline("3 secondes")
        assert.is_nil(t)
        assert.matches("timeline", err)
    end)
end)

describe("Intermission : planning des intermissions (machine pure)", function()
    local ns = wowenv.loadCore()
    local I, Config = ns.Intermission, ns.Config

    it("porte le planning pre-calcule du raid lead, dans l'ordre", function()
        assert.are.same({ 46.3, 148.9, 251.5, 353.2 }, I.SCHEDULE_SECONDS)
        local schedule = I.validateSchedule(nil)
        assert.are.same({ 46.3, 148.9, 251.5, 353.2 }, schedule)
        assert.are.same(Config.DEFAULT_SCHEDULE_SECONDS, I.SCHEDULE_SECONDS)
    end)

    it("normalise un planning persiste (tri, valeurs absurdes, borne)", function()
        assert.are.same({ 10, 20.5 }, I.validateSchedule({ 20.5, -3, 10, "x", 0 }))
        assert.are.same({ 5 }, I.validateSchedule({ 5 }))
        -- Un planning vide/absurde retombe sur le planning par defaut.
        assert.are.same(I.SCHEDULE_SECONDS, I.validateSchedule({}))
        assert.are.same(I.SCHEDULE_SECONDS, I.validateSchedule("nope"))
        assert.are.same(I.SCHEDULE_SECONDS, I.validateSchedule({ -1, 0 }))
        -- Plafond du nombre d'entrees (SavedVariables edite a la main).
        local huge = {}
        for index = 1, 40 do
            huge[index] = index
        end
        assert.are.equal(Config.MAX_SCHEDULE_ENTRIES, #I.validateSchedule(huge))
    end)

    it("calcule l'heure d'ouverture du panneau (lead de 2 s)", function()
        local run = I.newRun(nil, 2)
        assert.are.equal(46.3, I.runNextAt(run))
        assert.are.equal(44.3, I.runOpenAt(run))
        assert.are.equal(4, I.runRemaining(run))
        assert.is_false(I.runFinished(run))
        -- Un lead absurde est borne (jamais negatif, jamais enorme).
        assert.are.equal(0, I.newRun({ 10 }, -3).lead)
        assert.are.equal(10, I.newRun({ 10 }, 999).lead)
        -- Un lead de 0 ouvre exactement a l'intermission.
        assert.are.equal(10, I.runOpenAt(I.newRun({ 10 }, 0)))
    end)

    it("n'ouvre RIEN avant l'heure et ouvre UNE fois par intermission", function()
        local run = I.newRun({ 10, 20 }, 2)
        local _, opened = I.advanceRun(run, 7.9)
        assert.is_nil(opened)
        local _, first = I.advanceRun(run, 0.1) -- 8.0 s = 10 - 2
        assert.are.equal(1, first)
        local _, again = I.advanceRun(run, 3)
        assert.is_nil(again)
        assert.are.equal(1, I.runRemaining(run))
        local _, second = I.advanceRun(run, 8)
        assert.are.equal(2, second)
        assert.are.equal(0, I.runRemaining(run))
        assert.is_true(I.runFinished(run))
        assert.is_nil(I.runOpenAt(run))
        local _, extra = I.advanceRun(run, 100)
        assert.is_nil(extra, "un planning epuise n'ouvre plus rien")
    end)

    it("un dt enorme n'ouvre qu'UNE intermission a la fois (jamais de saut)", function()
        local run = I.newRun({ 10, 20, 30 }, 2)
        local _, first = I.advanceRun(run, 1000)
        assert.are.equal(1, first)
        assert.are.equal(2, I.runRemaining(run))
        local _, second = I.advanceRun(run, 0.1)
        assert.are.equal(2, second)
        local _, third = I.advanceRun(run, 0.1)
        assert.are.equal(3, third)
        local _, extra = I.advanceRun(run, 0.1)
        assert.is_nil(extra)
    end)

    it("ignore un dt negatif ou non numerique et reste deterministe", function()
        local run = I.newRun({ 10 }, 2)
        assert.is_nil(select(2, I.advanceRun(run, -5)))
        assert.is_nil(select(2, I.advanceRun(run, "beaucoup")))
        assert.are.equal(0, run.elapsed)
        local function replay()
            local r = I.newRun({ 10, 20 }, 2)
            local openings = {}
            for _ = 1, 400 do
                local _, opened = I.advanceRun(r, 0.1)
                if opened ~= nil then
                    openings[#openings + 1] = opened
                end
            end
            return openings
        end
        assert.are.same({ 1, 2 }, replay())
        assert.are.same(replay(), replay())
    end)

    it("resetRun repart de zero en gardant planning et lead", function()
        local run = I.newRun({ 10, 20 }, 2)
        I.advanceRun(run, 12)
        I.resetRun(run)
        assert.are.equal(0, run.elapsed)
        assert.are.equal(1, run.index)
        assert.are.equal(2, run.lead)
        assert.are.equal(10, I.runNextAt(run))
        assert.are.equal(2, I.runRemaining(run))
        assert.is_nil(I.resetRun(nil))
    end)
end)

describe("Intermission : machine d'etat", function()
    local ns = wowenv.loadCore()
    local I = ns.Intermission

    it("demarre a l'arret (IDLE) et n'affiche rien", function()
        local snap = I.snapshot(I.newState())
        assert.are.equal(I.PHASE.IDLE, snap.phase)
        assert.is_false(snap.visible)
        assert.is_false(snap.showButtons)
        assert.is_false(snap.showRedo)
        assert.are.equal("", snap.stateText)
        assert.is_nil(snap.pingBanner)
        assert.are.equal("INTERMISSION PANEL READY", snap.headline)
    end)

    it("ouvre en PENDING (lead 2 s) puis demarre l'intermission a la fin du lead", function()
        local st = I.newState({ leadSeconds = 2, visibilitySeconds = 3, durationSeconds = 20 })
        assert(I.start(st))
        assert.are.equal(I.PHASE.PENDING, st.phase)
        local snap = I.snapshot(st)
        assert.is_true(snap.visible)
        assert.is_true(snap.showButtons, "les trois choix sont visibles des l'ouverture")
        assert.are.equal("GET READY: 2 s", snap.headline)
        assert.are.equal("2", snap.countdownText)
        I.tick(st, 1)
        assert.are.equal(I.PHASE.PENDING, st.phase)
        assert.are.equal("1", I.snapshot(st).countdownText)
        I.tick(st, 1)
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
        assert.are.equal(0, st.elapsed, "le compteur de l'intermission repart de zero")
        assert.are.equal("3", I.snapshot(st).countdownText)
    end)

    it("avec un lead de 0 s, demarre directement en VISIBLE", function()
        local st = I.newState({ leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
        I.start(st)
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
        assert.are.equal("3", I.snapshot(st).countdownText)
        assert.matches("LOOK AT THE ORB COLOR", I.snapshot(st).headline)
        assert.is_true(I.snapshot(st).showButtons)
    end)

    it("decompte puis bascule en salle obscurcie a 3 s", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.tick(st, 1)
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
        assert.are.equal("2", I.snapshot(st).countdownText)
        I.tick(st, 1)
        assert.are.equal("1", I.snapshot(st).countdownText)
        I.tick(st, 1)
        assert.are.equal(I.PHASE.DARK, st.phase)
        assert.are.equal("0", I.snapshot(st).countdownText)
        assert.matches("DARKENED", I.snapshot(st).headline)
    end)

    it("garde les boutons actifs en PENDING et DARK, jamais en IDLE/DONE", function()
        local st = I.newState({ leadSeconds = 2, visibilitySeconds = 3, durationSeconds = 10 })
        I.start(st)
        assert.is_true(I.snapshot(st).showButtons, "PENDING")
        I.tick(st, 2)
        assert.is_true(I.snapshot(st).showButtons, "VISIBLE")
        I.tick(st, 5)
        assert.are.equal(I.PHASE.DARK, st.phase)
        assert.is_true(I.snapshot(st).showButtons, "DARK")
        I.tick(st, 10)
        assert.are.equal(I.PHASE.DONE, st.phase)
        assert.is_false(I.snapshot(st).showButtons, "DONE")
        assert.is_true(I.snapshot(st).autoClose, "DONE doit fermer le panneau")
    end)

    it("affiche l'ESSENTIEL apres declaration : etat, role, PING, UNE action", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        assert(I.declare(st, "2"))
        local snap = I.snapshot(st)
        assert.are.equal("2V2R", snap.declaration)
        assert.are.equal("2V2R", snap.stateText)
        assert.are.equal("2 GREEN + 2 RED", snap.stateLong)
        assert.are.equal("MID", snap.role)
        assert.are.equal("MIDDLE", snap.roleName)
        assert.are.equal("ROLE: MIDDLE", snap.roleLine)
        assert.is_false(snap.shouldPing)
        assert.are.equal("NO", snap.pingDecision)
        assert.are.equal("PING: NO", snap.pingBanner)
        assert.is_nil(snap.pingColorHex)
        assert.are.equal("DO NOT PING - go to the middle / under the boss", snap.actionLine)
        assert.is_true(snap.showRedo)
        -- Le panneau ne montre QUE le role et l'action quand ce role ne ping pas.
        assert.are.equal(2, #snap.lines)
        local text = table.concat(snap.lines, "\n")
        assert.are.equal("ROLE: MIDDLE\nDO NOT PING - go to the middle / under the boss", text)
    end)

    it("naffiche AUCUN pave technique (lignes supprimees a la demande du raid lead)", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.declare(st, "1V3R")
        local snap = I.snapshot(st)
        local text = table.concat(snap.lines, "\n")
        for _, banned in ipairs({
            "ROLE ORDER",
            "PING POLICY",
            "STATE THAT JOINS YOU",
            "STATE TO JOIN",
            "GUILD CONVENTION",
            "NUMBER ABOVE YOUR HEAD",
            "UNKNOWN",
            "caveat",
        }) do
            assert.is_false(contains(text, banned), banned)
        end
        assert.is_true(#snap.lines <= 3, "au plus 3 lignes courtes")
        assert.is_false(contains(text, FORBIDDEN_EVENT))
    end)

    it("affiche l'ANCRE et sa touche de ping en politique par defaut", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.declare(st, "1V3R")
        local snap = I.snapshot(st, "anchors", function()
            return "Q"
        end)
        assert.are.equal("ANCHOR", snap.role)
        assert.are.equal("ROLE: ANCHOR", snap.roleLine)
        assert.is_true(snap.shouldPing)
        assert.are.equal("YES", snap.pingDecision)
        assert.are.equal("PING: YES", snap.pingBanner)
        assert.are.equal("|cffff4040", snap.pingColorHex)
        assert.are.equal("PING: Warning - press Q", snap.pingHint.line)
        assert.is_true(contains(snap.actionLine, "hover YOUR OWN character frame"))
        assert.are.equal(3, #snap.lines)
    end)

    it("en politique « color », les trois etats ping et nomment leur ping", function()
        local expected = { ["1V3R"] = "Warning", ["2V2R"] = "On My Way", ["3V1R"] = "Assist" }
        local canonical = { ["1V3R"] = "Warning", ["2V2R"] = "OnMyWay", ["3V1R"] = "Assist" }
        for _, key in ipairs(I.STATES) do
            local st = I.newState({ leadSeconds = 0 })
            I.start(st)
            I.declare(st, key)
            local snap = I.snapshot(st, "color")
            assert.is_true(snap.shouldPing, key)
            assert.are.equal("PING: YES", snap.pingBanner, key)
            assert.are.equal(canonical[key], snap.pingHint.ping, key)
            assert.are.equal(expected[key], snap.pingHint.label, key)
            assert.is_true(contains(snap.actionLine, expected[key]), key)
        end
        local red = I.getDeclaration("1V3R", "color")
        assert.are.equal("RED", red.pingColor)
        assert.matches("Warning", red.pingLine)
        local blue = I.getDeclaration("2V2R", "color")
        assert.matches("On My Way", blue.pingLine)
        local green = I.getDeclaration("3V1R", "color")
        assert.matches("Assist", green.pingLine)
    end)

    it("en politique « none », PERSONNE ne ping et la consigne reste survivable", function()
        for _, key in ipairs(I.STATES) do
            local st = I.newState({ leadSeconds = 0 })
            I.start(st)
            I.declare(st, key)
            local snap = I.snapshot(st, "none")
            assert.is_false(snap.shouldPing, key)
            assert.are.equal("PING: NO", snap.pingBanner, key)
            assert.is_nil(snap.pingHint, key)
            assert.is_nil(snap.pingColorHex, key)
        end
        -- L'ANCRE garde malgre tout sa consigne de survie : sur place.
        local anchor = I.snapshot(
            (function()
                local st = I.newState({ leadSeconds = 0 })
                I.start(st)
                I.declare(st, "1V3R")
                return st
            end)(),
            "none"
        )
        assert.is_true(contains(anchor.actionLine, "STAY WHERE YOU ARE"))
        assert.is_false(contains(anchor.actionLine, "ping yourself"))
        -- Le CHASSEUR et le MILIEU ne recoivent jamais un ordre contradictoire.
        assert.is_false(contains(anchor.pingBanner, "YES"))
        local chaser = I.getDeclaration("3V1R", "none")
        assert.is_true(contains(chaser.actionLine, "run to a ping"))
        assert.is_true(contains(chaser.actionLine, "DO NOT PING"))
        local mid = I.getDeclaration("2V2R", "none")
        assert.is_true(contains(mid.actionLine, "middle"))
        assert.is_true(contains(mid.actionLine, "DO NOT PING"))
    end)

    it("CORRIGER (clearDeclaration) ramene aux trois choix, autant de fois qu'on veut", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.declare(st, "3V1R")
        local snap = I.snapshot(st)
        assert.are.equal("3V1R", snap.stateText)
        assert.is_true(snap.showRedo)
        assert(I.clearDeclaration(st))
        assert.is_nil(st.declaration)
        local after = I.snapshot(st)
        assert.are.equal("", after.stateText)
        assert.is_false(after.showRedo)
        assert.is_nil(after.pingBanner)
        assert.are.equal(1, #after.lines, "le panneau redemande la composition")
        assert.are.equal("Click the composition you see above your head.", after.lines[1])
        -- Deuxieme puis troisieme correction : la correction est idempotente.
        I.declare(st, "1V3R")
        assert(I.clearDeclaration(st))
        I.declare(st, "2V2R")
        assert(I.clearDeclaration(st))
        assert.is_nil(st.declaration)
        assert.are.equal(0, st.elapsed, "la correction ne relance pas le chrono")
    end)

    it("refuse CORRIGER quand rien n'est declare ou hors intermission", function()
        local st = I.newState({ leadSeconds = 0 })
        local res, err = I.clearDeclaration(st)
        assert.is_nil(res)
        assert.matches("not started", err)
        I.start(st)
        local res2, err2 = I.clearDeclaration(st)
        assert.is_nil(res2)
        assert.matches("nothing to correct", err2)
        assert.is_nil(I.clearDeclaration(nil))
    end)

    it("refuse une declaration invalide, ambigue, ou hors intermission", function()
        local st = I.newState()
        local res, err = I.declare(st, "2")
        assert.is_nil(res)
        assert.matches("not started", err)
        I.start(st)
        local res2, err2 = I.declare(st, "9")
        assert.is_nil(res2)
        assert.matches("unknown", err2)
        -- un numero ambigu est REFUSE : la couleur doit etre declaree
        local res3, err3 = I.declare(st, "1")
        assert.is_nil(res3)
        assert.matches("ambiguous", err3)
        assert.is_nil(st.declaration)
    end)

    it("termine (DONE) a la fin de la timeline en gardant la consigne", function()
        local st = I.newState({ leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 6 })
        I.start(st)
        I.declare(st, "3V1R")
        I.tick(st, 5)
        assert.are.equal(I.PHASE.DARK, st.phase)
        I.tick(st, 2)
        assert.are.equal(I.PHASE.DONE, st.phase)
        local snap = I.snapshot(st)
        assert.is_false(snap.showButtons)
        assert.is_true(snap.autoClose)
        assert.are.equal("3V1R", snap.stateText)
        assert.matches("INTERMISSION OVER", snap.headline)
        local res, err = I.declare(st, "1V3R")
        assert.is_nil(res)
        assert.matches("over", err)
    end)

    it("remet tout a zero avec reset", function()
        local st = I.newState()
        I.start(st)
        I.declare(st, "2")
        I.reset(st)
        assert.are.equal(I.PHASE.IDLE, st.phase)
        assert.is_nil(st.declaration)
        assert.are.equal(0, st.elapsed)
        assert.is_nil(I.reset("pas une table"))
    end)

    it("ignore un dt negatif ou non numerique", function()
        local st = I.newState({ leadSeconds = 0 })
        I.start(st)
        I.tick(st, -5)
        I.tick(st, "beaucoup")
        assert.are.equal(0, st.elapsed)
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
    end)

    it("est deterministe : memes entrees, meme rapport", function()
        local function run()
            local st = I.newState({ leadSeconds = 1 })
            I.start(st)
            I.tick(st, 1.5)
            I.declare(st, "2")
            I.tick(st, 2)
            return I.snapshot(st, "color", function()
                return "Q"
            end)
        end
        assert.are.same(run(), run())
    end)
end)

describe("Intermission : panneau de placement (avant le pull)", function()
    local I = wowenv.loadCore().Intermission

    it("explique le placement, le raccourci de ping et la suite du flux", function()
        local view = I.setupView({ leadSeconds = 2, pairs = 2 })
        assert.are.equal("BEFORE THE PULL - PLACE THE PANEL", view.headline)
        assert.are.equal("OK", view.okLabel)
        assert.are.equal("Close", view.closeLabel)
        local text = table.concat(view.lines, "\n")
        assert.is_true(contains(text, "Drag this frame"))
        assert.is_true(contains(text, "Options > Keybindings"))
        assert.is_true(contains(text, "2 s before each intermission"))
        assert.is_true(contains(text, "Out-of-game plan loaded (2 pairs)."))
    end)

    it("dit que le plan hors jeu est optionnel quand il n'y en a pas", function()
        local view = I.setupView({})
        local text = table.concat(view.lines, "\n")
        assert.is_true(contains(text, "No out-of-game plan loaded (optional)."))
        assert.is_true(contains(text, "2 s before each intermission"), "lead par defaut")
        local zero = I.setupView({ leadSeconds = 0, pairs = 0 })
        assert.is_true(contains(table.concat(zero.lines, "\n"), "0 s before each intermission"))
        -- Aucun argument : jamais d'erreur.
        assert.is_table(I.setupView(nil).lines)
    end)
end)

describe("Intermission : plan prepare hors jeu", function()
    local ns = wowenv.loadCore()
    local I, Pairing = ns.Intermission, ns.Pairing

    it("accepte le bloc ecrit par GIDEON (fixture de contrat)", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        assert.are.equal(2, #clean.pairs)
        assert.is_table(clean.plan)
    end)

    it("affiche le partenaire, le role et la position du joueur", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Torgh"))
        assert.are.equal("Velna", plan.partner)
        assert.are.equal("2V2R", plan.me.role)
        assert.are.equal("MIDDLE", plan.me.position)
        local text = table.concat(plan.lines, "\n")
        assert.matches("Your partner: Velna", text)
        assert.matches("Your role", text)
        assert.matches("MIDDLE", text)
    end)

    it("verifie la rencontre preparee (addition de couleurs)", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Torgh"))
        assert.is_true(plan.meeting.ok)
        assert.are.equal("2V2R+2V2R", plan.meeting.label)
        assert.matches("2V2R%+2V2R", table.concat(plan.lines, "\n"))
        local plan2 = assert(I.buildPlan(clean, "Bathman"))
        assert.is_true(plan2.meeting.ok)
        assert.are.equal("1V3R+3V1R", plan2.meeting.label)
        assert.matches("1V3R%+3V1R", table.concat(plan2.lines, "\n"))
    end)

    it("deduit le ROLE de ping du role prepare, avec le ping a utiliser", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        -- Bathman is prepared as 1V3R = ANCHOR: under the default policy it is
        -- the one that pings, and its ping/key are named (no macro any more).
        local anchor = assert(I.buildPlan(clean, "Bathman", "anchors", function()
            return "Q"
        end))
        assert.are.equal("ANCHOR", anchor.pingRole)
        local anchorText = table.concat(anchor.lines, "\n")
        assert.matches("Your intermission role: ANCHOR", anchorText)
        assert.matches("ping: YES", anchorText)
        assert.is_true(contains(anchorText, "PING: Warning - press Q"))
        assert.is_false(contains(anchorText, "SendMacroPing"))
        assert.are.equal("anchors", anchor.pingPolicy)
        assert.matches("ANCHORS: only the 1V3R anchors ping", anchorText)
        -- Sans touche bindi, la ligne demande un raccourci.
        local noKey = assert(I.buildPlan(clean, "Bathman"))
        assert.is_true(contains(table.concat(noKey.lines, "\n"), "set a keybind in Options > Keybindings"))
        -- Velna is prepared as 2V2R = MIDDLE: no ping under "anchors".
        local mid = assert(I.buildPlan(clean, "Velna"))
        assert.are.equal("MID", mid.pingRole)
        assert.is_false(mid.shouldPing)
        assert.is_nil(mid.pingHint)
        local midText = table.concat(mid.lines, "\n")
        assert.matches("Your intermission role: MIDDLE", midText)
        assert.matches("ping: NO", midText)
        -- Under "color" the MIDDLE pings too and its ping is named.
        local colored = assert(I.buildPlan(clean, "Velna", "color"))
        assert.is_true(colored.shouldPing)
        assert.are.equal("OnMyWay", colored.pingHint.ping)
        -- Under "none" nobody pings, not even the anchor.
        local none = assert(I.buildPlan(clean, "Bathman", "none"))
        assert.is_false(none.shouldPing)
        assert.is_nil(none.pingHint)
        assert.is_false(contains(table.concat(none.lines, "\n"), "PING: Warning"))
    end)

    it("signale une rencontre mortelle (3V1R + 2V2R = 5 verts)", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "A", b = "B" } },
            plan = {
                { name = "A", role = "2V2R", position = "MIDDLE" },
                { name = "B", role = "3V1R", position = "PURSUE" },
            },
        }))
        local plan = assert(I.buildPlan(clean, "A"))
        assert.is_false(plan.meeting.ok)
        assert.are.equal(5, plan.meeting.greens)
        local text = table.concat(plan.lines, "\n")
        assert.matches("DEAD", text)
        assert.matches("5 green", text)
    end)

    it("signale un role AMBIGU (« 1 » ou « 3 » seul) au lieu de le deviner", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "A", b = "B" } },
            plan = {
                { name = "A", role = "1", position = "HOLD" },
                { name = "B", role = "3V1R", position = "PURSUE" },
            },
        }))
        local plan = assert(I.buildPlan(clean, "A"))
        assert.is_nil(plan.meeting)
        local text = table.concat(plan.lines, "\n")
        assert.matches("cannot be verified", text)
        assert.matches("ambiguous", text)
    end)

    it("liste les paires triees par nom", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Velna"))
        assert.are.equal("Bathman", plan.pairs[1].a)
        assert.are.equal("Velna", plan.pairs[2].a)
        assert.is_nil(plan.pairs[1].extra)
        assert.are.equal("1V3R", plan.pairs[1].roleA)
        assert.are.equal("3V1R", plan.pairs[1].roleB)
    end)

    it("est deterministe : l'ordre d'entree des paires et du plan ne change rien", function()
        local source = loadFixture()
        local reversed = {
            schema = 1,
            pairs = { source.pairs[2], source.pairs[1] },
            plan = { source.plan[4], source.plan[3], source.plan[2], source.plan[1] },
        }
        local a = assert(I.buildPlan(assert(Pairing.validateAssignment(source)), "Bathman"))
        local b = assert(I.buildPlan(assert(Pairing.validateAssignment(reversed)), "Bathman"))
        assert.are.same(a.lines, b.lines)
        assert.are.same(a.pairs, b.pairs)
    end)

    it("fonctionne sans bloc plan (champ optionnel)", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "Velna", b = "Torgh" } },
        }))
        local plan = assert(I.buildPlan(clean, "Velna"))
        assert.are.equal("Torgh", plan.partner)
        assert.is_nil(plan.me)
        assert.matches("Your partner: Torgh", table.concat(plan.lines, "\n"))
    end)

    it("signale un joueur absent de l'appariement", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Inconnu"))
        assert.is_nil(plan.partner)
        assert.matches("not in the GIDEON pairing", table.concat(plan.lines, "\n"))
    end)

    it("ignore un plan malforme sans casser le reste", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "A", b = "B" } },
            plan = { { role = "2" } },
        }))
        local plan = assert(I.buildPlan(clean, "A"))
        assert.are.equal(1, #plan.planErrors)
        assert.matches("name", plan.planErrors[1])
        assert.are.equal("B", plan.partner)
    end)

    it("refuse un assignment invalide", function()
        local plan, err = I.buildPlan(nil, "A")
        assert.is_nil(plan)
        assert.matches("invalid", err)
        local plan2, err2 = I.buildPlan({ pairs = "non" }, "A")
        assert.is_nil(plan2)
        assert.matches("invalid", err2)
    end)
end)

describe("Config : bloc intermission", function()
    local ns = wowenv.loadCore()
    local Config = ns.Config

    it("cree des valeurs par defaut fraiches (pas d'alias entre comptes)", function()
        local a = Config.defaultIntermission()
        local b = Config.defaultIntermission()
        assert.are_not.equal(a, b)
        assert.are_not.equal(a.position, b.position)
        assert.are_not.equal(a.scheduleSeconds, b.scheduleSeconds)
        a.scale = 3
        a.position.x = 99
        a.scheduleSeconds[1] = 1
        assert.are.equal(1.0, Config.defaultIntermission().scale)
        assert.are.equal(0, Config.defaultIntermission().position.x)
        assert.are.equal(46.3, Config.defaultIntermission().scheduleSeconds[1])
    end)

    it("remplit le bloc au chargement de l'addon sans ecraser l'existant", function()
        local db = Config.ensureDB({ intermission = { scale = 2.0 } })
        assert.is_table(db.intermission)
        assert.are.equal(2.0, db.intermission.scale)
        -- Les cles absentes ne sont PAS ecrites d'office : les defaults sont
        -- appliques a la lecture par resolveIntermission (fichier SavedVariables
        -- minimal, lisible par un humain).
        assert.is_nil(db.intermission.visibilitySeconds)
        local resolved = Config.resolveIntermission(db.intermission)
        assert.is_true(resolved.enabled)
        assert.are.equal(2.0, resolved.scale)
        assert.are.equal(3, resolved.visibilitySeconds)
        assert.are.equal(2, resolved.leadSeconds)
        assert.are.same({ 46.3, 148.9, 251.5, 353.2 }, resolved.scheduleSeconds)
        assert.are.equal(0, resolved.position.x)
        -- Un bloc absent est cree frais, et jamais partage avec les defaults.
        local db2 = Config.ensureDB({})
        assert.is_table(db2.intermission)
        assert.are_not.equal(db2.intermission, db.intermission)
    end)

    it("borne l'echelle, les durees et le lead", function()
        local c = Config.resolveIntermission({ scale = 99, leadSeconds = 99, visibilitySeconds = 0, durationSeconds = 1 })
        assert.are.equal(3.0, c.scale)
        assert.are.equal(10, c.leadSeconds)
        assert.are.equal(1, c.visibilitySeconds)
        assert.is_true(c.durationSeconds > c.visibilitySeconds)
        local c2 = Config.resolveIntermission({ scale = 0.01, leadSeconds = -4 })
        assert.are.equal(0.5, c2.scale)
        assert.are.equal(0, c2.leadSeconds)
    end)

    it("ignore les types incoherents et normalise le planning", function()
        local c = Config.resolveIntermission({
            enabled = "oui",
            scale = "grand",
            leadSeconds = "deux",
            durationSeconds = {},
            scheduleSeconds = { 30, "x", -1 },
        })
        assert.is_true(c.enabled)
        assert.are.equal(1.0, c.scale)
        assert.are.equal(20, c.durationSeconds)
        assert.are.equal(2, c.leadSeconds)
        assert.are.same({ 30 }, c.scheduleSeconds)
    end)

    it("accepte une valeur explicite valide", function()
        local c = Config.resolveIntermission({
            enabled = false,
            startOnEncounterStart = false,
            autoShowPanel = false,
            scale = 1.25,
            leadSeconds = 1,
            visibilitySeconds = 5,
            durationSeconds = 30,
            scheduleSeconds = { 40, 90.5 },
            position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = -120, y = -40 },
        })
        assert.is_false(c.enabled)
        assert.is_false(c.startOnEncounterStart)
        assert.is_false(c.autoShowPanel)
        assert.are.equal(1.25, c.scale)
        assert.are.equal(1, c.leadSeconds)
        assert.are.equal(5, c.visibilitySeconds)
        assert.are.equal(30, c.durationSeconds)
        assert.are.same({ 40, 90.5 }, c.scheduleSeconds)
        assert.are.equal("TOPLEFT", c.position.point)
        assert.are.equal(-120, c.position.x)
    end)

    it("retombe sur les defaults si le bloc est absent", function()
        local c = Config.resolveIntermission(nil)
        assert.is_true(c.enabled)
        assert.is_true(c.startOnEncounterStart)
        assert.are.equal(3, c.visibilitySeconds)
        assert.are.equal(2, c.leadSeconds)
        assert.are.equal("CENTER", c.position.point)
        -- L'ancien champ de macro a disparu : plus aucune trace dans les defaults.
        assert.is_nil(c.macroTargetToken)
    end)

    -- ------------------------------------------------------------------
    -- CIBLE DE BOSS LIVREE AVEC L'ADDON (mesuree en jeu par le raid lead)
    -- ------------------------------------------------------------------
    it("livre la cible mesuree EN JEU : id 3445 + les deux noms du boss", function()
        -- La mesure reelle (raid lead, 2026-09-24, pull heroique 20 joueurs) :
        --   encounter seen: id=3445 name=Sentinelles inhumées difficulty=15 group=20
        assert.are.same({ 3445 }, Config.DEFAULT_BOSS_IDS)
        assert.are.same({ "Entombed Sentinels", "Sentinelles inhumées" }, Config.DEFAULT_BOSS_NAMES)
        -- L'ACCENT du nom francais est preserve, caractere pour caractere : c'est la
        -- chaine exacte affichee par le client du raid lead (fichier UTF-8).
        assert.are.equal("Sentinelles inhumées", Config.DEFAULT_BOSS_NAMES[2])
        -- 21 OCTETS pour 20 caracteres : le "é" final est encode sur deux octets en
        -- UTF-8, et il fait partie de la chaine comparee (jamais re-accentue).
        assert.are.equal(21, #Config.DEFAULT_BOSS_NAMES[2])
        assert.are.equal("é", string.sub(Config.DEFAULT_BOSS_NAMES[2], 18, 19))
        assert.are.equal("3445", Config.deliveredIdsText())
        assert.are.equal("Entombed Sentinels, Sentinelles inhumées", Config.deliveredNamesText())

        -- Les difficultes du boss sont documentees et le filtre n'en depend PAS :
        -- le raid lead joue Heroique (15) aujourd'hui, Mythique (16) plus tard.
        assert.are.same({ 14, 15, 16, 17 }, Config.BOSS_DIFFICULTIES)
        assert.is_nil(Config.resolveIntermission({})["BOSS_DIFFICULTIES"])
    end)

    it("JAMAIS CONFIGURE : la cible effective est celle livree, sans rien ecrire", function()
        for _, raw in ipairs({ nil, {}, { bossIds = {} }, { bossIds = "bidon", bossNames = 12 } }) do
            local c = Config.resolveIntermission(raw)
            assert.are.same({ 3445 }, c.bossIds)
            assert.are.same({ "entombed sentinels", "sentinelles inhumées" }, c.bossNames)
            assert.are.same({}, c.bossIdsOwn, "aucune entree de joueur")
            assert.is_false(c.bossTargetCleared)
            assert.are.equal("default", c.bossTargetSource)
        end
    end)

    it("VIDE EXPLICITEMENT (/gr boss clear) : plus de cible, et le defaut ne revient pas", function()
        local c = Config.resolveIntermission({ bossIds = {}, bossNames = {}, bossTargetCleared = true })
        assert.are.same({}, c.bossIds, "efface = aucune cible : le panneau ne s'ouvre sur rien")
        assert.are.same({}, c.bossNames)
        assert.is_true(c.bossTargetCleared)
        assert.are.equal("cleared", c.bossTargetSource)

        -- Seul un `true` EXACT compte : une sauvegarde bricolee a la main ne peut pas
        -- desactiver le defaut livre par accident.
        for _, junk in ipairs({ "oui", 1, 0, "true" }) do
            local j = Config.resolveIntermission({ bossTargetCleared = junk })
            assert.are.same({ 3445 }, j.bossIds, "valeur douteuse = le defaut livre s'applique")
            assert.is_false(j.bossTargetCleared)
        end
    end)

    it("AJOUT D'UN JOUEUR : union avec le defaut livre, et provenance distincte", function()
        local c = Config.resolveIntermission({ bossIds = { 2594 }, bossNames = { "Autre Boss" } })
        assert.are.same({ 2594, 3445 }, c.bossIds, "l'union est triee")
        assert.are.same({ 2594 }, c.bossIdsOwn, "l'entree du joueur est conservee telle quelle")
        assert.are.same({ "autre boss" }, c.bossNamesOwn)
        assert.are.same({ 3445 }, Config.DEFAULT_BOSS_IDS, "les constantes livrees ne bougent pas")
        assert.are.equal("mixed", c.bossTargetSource)

        -- Apres un clear explicite, un ajout ne fait PAS revenir le defaut livre :
        -- c'est le joueur qui reprend la main.
        local after = Config.resolveIntermission({
            bossIds = { 2594 },
            bossTargetCleared = true,
        })
        assert.are.same({ 2594 }, after.bossIds)
        assert.are.equal("own", after.bossTargetSource)
        assert.is_true(after.bossTargetCleared, "le marqueur reste : le defaut ne revient pas en douce")

        -- Un doublon de l'id livre n'en cree pas deux.
        local dup = Config.resolveIntermission({ bossIds = { 3445 } })
        assert.are.same({ 3445 }, dup.bossIds)
        assert.are.equal("mixed", dup.bossTargetSource)
    end)
end)

describe("Config : panneau principal (position persistee + verrou)", function()
    local ns = wowenv.loadCore()
    local Config = ns.Config

    it("cree une position par defaut FRAICHE (aucun alias entre comptes)", function()
        local a = Config.defaultPanelPosition()
        local b = Config.defaultPanelPosition()
        assert.are_not.equal(a, b)
        assert.are.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, a)
        a.x = 99
        a.point = "TOPLEFT"
        assert.are.equal(0, Config.defaultPanelPosition().x)
        assert.are.equal("CENTER", Config.defaultPanelPosition().point)
    end)

    it("resout le verrou : seul un vrai booleen verrouille", function()
        assert.is_false(Config.resolveLockPanel(nil))
        assert.is_false(Config.resolveLockPanel(false))
        assert.is_true(Config.resolveLockPanel(true))
        for _, bad in ipairs({ "true", 1, 0, {}, "oui" }) do
            assert.is_false(Config.resolveLockPanel(bad), tostring(bad))
        end
    end)

    it("resout une position persistee : listes blanches, jamais d'erreur", function()
        local plain = Config.resolvePosition(nil)
        assert.are.same({ point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }, plain)
        assert.are.equal(0, Config.resolvePosition({}).y)
        local pos = Config.resolvePosition({ point = "topleft", relativePoint = "TOPLEFT", x = -120, y = -40 })
        assert.are.equal("TOPLEFT", pos.point)
        assert.are.equal("TOPLEFT", pos.relativePoint)
        assert.are.equal(-120, pos.x)
        assert.are.equal(-40, pos.y)
        -- Un point INCONNU ne doit JAMAIS atteindre SetPoint (le client leverait).
        local bad = Config.resolvePosition({ point = "BANANA", relativePoint = 42, x = "x", y = {} })
        assert.are.equal("CENTER", bad.point)
        assert.are.equal("CENTER", bad.relativePoint)
        assert.are.equal(0, bad.x)
        assert.are.equal(0, bad.y)
        assert.are.equal("CENTER", Config.resolvePosition("pas une table").point)
    end)

    it("deverrouille par defaut et MIGRE une fois les SavedVariables existantes", function()
        -- Fichier neuf : panneau deplacable, marqueur de schema pose.
        local fresh = Config.ensureDB({})
        assert.is_false(fresh.lockPanel, "le panneau doit etre deplacable par defaut")
        assert.are.equal(Config.PANEL_SCHEMA, fresh.panelSchema)
        assert.are.equal("CENTER", fresh.panelPosition.point)
        assert.are.equal("CENTER", fresh.pingPanelPosition.point)
        -- Ancien fichier : `lockPanel = true` etait l'ANCIEN defaut, qu'aucun
        -- joueur ne pouvait changer -> deverrouille UNE fois.
        local legacy = Config.ensureDB({ lockPanel = true })
        assert.is_false(legacy.lockPanel)
        assert.are.equal(Config.PANEL_SCHEMA, legacy.panelSchema)
        -- Une fois le marqueur pose, le choix du joueur est RESPECTE.
        local locked = Config.ensureDB({ lockPanel = true, panelSchema = Config.PANEL_SCHEMA })
        assert.is_true(locked.lockPanel)
        assert.is_true(Config.ensureDB({ lockPanel = false, panelSchema = Config.PANEL_SCHEMA }).lockPanel == false)
        -- Valeur incoherente : jamais d'erreur, on retombe sur « deplacable ».
        local odd = Config.ensureDB({ lockPanel = "oui", panelSchema = Config.PANEL_SCHEMA })
        assert.is_false(odd.lockPanel)
    end)
end)
