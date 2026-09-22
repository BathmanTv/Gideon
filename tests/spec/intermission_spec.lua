--[[--------------------------------------------------------------------------
    tests/spec/intermission_spec.lua   (busted)
    Tests HORS JEU du module « Intermission Coach ».

    Deux familles de tests :
      1. la CONNAISSANCE du module : les TROIS etats de couleur (3V1R / 2V2R /
         1V3R), les numeros affiches (2 non ambigu, 1 et 3 ambigus), la regle de
         survie en ADDITION DE COULEURS (4 verts + 4 rouges), la normalisation
         des declarations, la generation de la macro de ping, la lecture du plan
         prepare hors jeu ;
      2. la MACHINE D'ETAT : phases de l'intermission (visibilite 3 s puis salle
         obscurcie), declaration du joueur, compte a rebours, sortie de phase.

    Aucun mock d'API WoW ici : Core/Intermission.lua est du Lua 5.1 pur.
    Le temps est INJECTE (dt en secondes) : le module n'appelle jamais GetTime.
----------------------------------------------------------------------------]]
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

    it("donne le complement, la position et la consigne de chaque etat", function()
        assert.are.equal("3V1R", I.getDeclaration("1V3R").complement)
        assert.are.equal("2V2R", I.getDeclaration("2V2R").complement)
        assert.are.equal("1V3R", I.getDeclaration("3V1R").complement)
        for _, key in ipairs(I.STATES) do
            local rec = I.getDeclaration(key)
            assert.is_string(rec.action)
            assert.is_true(#rec.action > 10)
            assert.is_string(rec.find)
            assert.is_true(#rec.find > 10)
            assert.is_string(rec.positionLabel)
            assert.is_string(rec.numberRule)
            assert.is_string(rec.buttonLabel)
            assert.is_true(#rec.buttonLabel > 10)
        end
        assert.matches("HOLD", I.getDeclaration("1V3R").positionLabel)
        assert.matches("MIDDLE", I.getDeclaration("2V2R").positionLabel)
        assert.matches("1V3R", I.getDeclaration("3V1R").positionLabel)
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

describe("Intermission : macro de ping", function()
    local I = wowenv.loadCore().Intermission

    it("genere l'appel API documente pour chaque etat (par couleur dominante)", function()
        local m1 = assert(I.buildMacro("1V3R"))
        assert.matches("C_Ping%.SendMacroPing", m1.primary)
        assert.matches("Enum%.PingSubjectType%.Warning", m1.primary)
        assert.matches('targetToken = "player"', m1.primary)
        local m2 = assert(I.buildMacro("2V2R"))
        assert.matches("Enum%.PingSubjectType%.OnMyWay", m2.primary)
        local m3 = assert(I.buildMacro("3V1R"))
        assert.matches("Enum%.PingSubjectType%.Assist", m3.primary)
    end)

    it("refuse un numero ambigu : aucune macro inventee", function()
        local m, err = I.buildMacro("1")
        assert.is_nil(m)
        assert.matches("ambiguous", err)
        local m3, err3 = I.buildMacro("3")
        assert.is_nil(m3)
        assert.matches("ambiguous", err3)
    end)

    it("fournit une variante /ping et une note « a confirmer »", function()
        local m = assert(I.buildMacro("3V1R"))
        assert.matches("^/ping ", m.fallback)
        assert.matches("Assist", m.fallback)
        assert.matches("confirmed", m.note)
    end)

    it("accepte un autre jeton de cible", function()
        local m = assert(I.buildMacro("2V2R", "target"))
        assert.matches('targetToken = "target"', m.primary)
    end)

    it("refuse une declaration inconnue et ne fabrique jamais de texte interdit", function()
        local m, err = I.buildMacro("banane")
        assert.is_nil(m)
        assert.matches("unknown", err)
        for _, key in ipairs(I.DECLARATIONS) do
            local ok = I.buildMacro(key)
            assert.is_nil(string.find(ok.primary, FORBIDDEN_EVENT, 1, true))
            assert.is_nil(string.find(ok.fallback, FORBIDDEN_EVENT, 1, true))
        end
    end)
end)

describe("Intermission : timeline pre-calculee", function()
    local I = wowenv.loadCore().Intermission

    it("applique les valeurs par defaut (3 s de visibilite)", function()
        local t = assert(I.validateTimeline(nil))
        assert.are.equal(3, t.visibilitySeconds)
        assert.are.equal(I.DEFAULT_DURATION_SECONDS, t.durationSeconds)
    end)

    it("accepte une timeline preparee hors jeu", function()
        local t = assert(I.validateTimeline({ name = "Intermission 1", visibilitySeconds = 4, durationSeconds = 25 }))
        assert.are.equal("Intermission 1", t.name)
        assert.are.equal(4, t.visibilitySeconds)
        assert.are.equal(25, t.durationSeconds)
    end)

    it("borne les valeurs absurdes et garde duree > visibilite", function()
        local t = assert(I.validateTimeline({ visibilitySeconds = -5, durationSeconds = 0 }))
        assert.are.equal(1, t.visibilitySeconds)
        assert.is_true(t.durationSeconds > t.visibilitySeconds)
        local t2 = assert(I.validateTimeline({ visibilitySeconds = 99, durationSeconds = 9999 }))
        assert.are.equal(10, t2.visibilitySeconds)
        assert.are.equal(120, t2.durationSeconds)
    end)

    it("refuse une timeline non table mais non nil", function()
        local t, err = I.validateTimeline("3 secondes")
        assert.is_nil(t)
        assert.matches("timeline", err)
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
    end)

    it("passe en phase VISIBLE au demarrage avec un compte a rebours de 3 s", function()
        local st = I.newState()
        assert(I.start(st))
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
        local snap = I.snapshot(st)
        assert.is_true(snap.visible)
        assert.is_true(snap.showButtons)
        assert.are.equal("3", snap.countdownText)
        assert.are.equal(3, I.remainingVisibility(st))
    end)

    it("decompte puis bascule en salle obscurcie a 3 s", function()
        local st = I.newState()
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

    it("garde les boutons actifs en phase DARK", function()
        local st = I.newState()
        I.start(st)
        I.tick(st, 5)
        assert.are.equal(I.PHASE.DARK, st.phase)
        assert.is_true(I.snapshot(st).showButtons)
    end)

    it("affiche la consigne complete apres declaration", function()
        local st = I.newState()
        I.start(st)
        assert(I.declare(st, "2"))
        local snap = I.snapshot(st)
        local text = table.concat(snap.lines, "\n")
        assert.matches("YOU SEE: 2 GREEN %+ 2 RED", text)
        assert.is_true(contains(text, "NUMBER ABOVE YOUR HEAD: 2"))
        assert.matches("unambiguous", text)
        assert.matches("MIDDLE", text)
        assert.matches("BLUE", text)
        assert.matches("OnMyWay", text)
        assert.matches("STATE TO JOIN: 2V2R", text)
        assert.are.equal("2V2R", snap.declaration)
        assert.matches("C_Ping%.SendMacroPing", snap.macroPrimary)
    end)

    it("dit ce qu'il FAIT, QUI rejoindre, le PING et que 1/3 ne suffit pas", function()
        local st = I.newState()
        I.start(st)
        I.declare(st, "3 verts")
        local snap = I.snapshot(st)
        local text = table.concat(snap.lines, "\n")
        assert.are.equal("3V1R", snap.declaration)
        assert.matches("YOU SEE: 3 GREEN %+ 1 RED", text)
        assert.is_true(contains(text, "NUMBER ABOVE YOUR HEAD: 1 or 3"))
        assert.matches("it does NOT reveal the color", text)
        assert.matches("DO:", text)
        assert.matches("STATE TO JOIN: 1V3R", text)
        assert.matches("PING TO SEND: GREEN", text)
        assert.matches("1 or 3 IS NOT ENOUGH", text)
        assert.are.equal("1V3R", snap.instruction.complement)
    end)

    it("rappelle explicitement ce qui n'est PAS transmissible", function()
        local st = I.newState()
        I.start(st)
        I.declare(st, "1V3R")
        local text = table.concat(I.snapshot(st).lines, "\n")
        assert.matches("UNKNOWN", text)
        assert.matches("ping", text)
        assert.is_nil(string.find(text, FORBIDDEN_EVENT, 1, true))
    end)

    it("change de declaration sans redemarrer l'intermission", function()
        local st = I.newState()
        I.start(st)
        I.tick(st, 1)
        I.declare(st, "3V1R")
        I.declare(st, "1V3R")
        assert.are.equal("1V3R", st.declaration)
        assert.are.equal(1, st.elapsed)
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
        local st = I.newState({ visibilitySeconds = 3, durationSeconds = 6 })
        I.start(st)
        I.declare(st, "3V1R")
        I.tick(st, 5)
        assert.are.equal(I.PHASE.DARK, st.phase)
        I.tick(st, 2)
        assert.are.equal(I.PHASE.DONE, st.phase)
        local snap = I.snapshot(st)
        assert.is_false(snap.showButtons)
        assert.matches("3 GREEN %+ 1 RED", table.concat(snap.lines, "\n"))
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
    end)

    it("ignore un dt negatif ou non numerique", function()
        local st = I.newState()
        I.start(st)
        I.tick(st, -5)
        I.tick(st, "beaucoup")
        assert.are.equal(0, st.elapsed)
        assert.are.equal(I.PHASE.VISIBLE, st.phase)
    end)

    it("est deterministe : memes entrees, meme rapport", function()
        local function run()
            local st = I.newState()
            I.start(st)
            I.tick(st, 1.5)
            I.declare(st, "2")
            I.tick(st, 2)
            return I.snapshot(st)
        end
        assert.are.same(run(), run())
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
        a.scale = 3
        a.position.x = 99
        assert.are.equal(1.0, Config.defaultIntermission().scale)
        assert.are.equal(0, Config.defaultIntermission().position.x)
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
        assert.are.equal(0, resolved.position.x)
        -- Un bloc absent est cree frais, et jamais partage avec les defaults.
        local db2 = Config.ensureDB({})
        assert.is_table(db2.intermission)
        assert.are_not.equal(db2.intermission, db.intermission)
    end)

    it("borne l'echelle et les durees", function()
        local c = Config.resolveIntermission({ scale = 99, visibilitySeconds = 0, durationSeconds = 1 })
        assert.are.equal(3.0, c.scale)
        assert.are.equal(1, c.visibilitySeconds)
        assert.is_true(c.durationSeconds > c.visibilitySeconds)
        local c2 = Config.resolveIntermission({ scale = 0.01 })
        assert.are.equal(0.5, c2.scale)
    end)

    it("ignore les types incoherents", function()
        local c = Config.resolveIntermission({
            enabled = "oui",
            scale = "grand",
            durationSeconds = {},
            macroTargetToken = 12,
        })
        assert.is_true(c.enabled)
        assert.are.equal(1.0, c.scale)
        assert.are.equal(20, c.durationSeconds)
        assert.are.equal("player", c.macroTargetToken)
    end)

    it("accepte une valeur explicite valide", function()
        local c = Config.resolveIntermission({
            enabled = false,
            startOnEncounterStart = false,
            autoShowPanel = false,
            scale = 1.25,
            visibilitySeconds = 5,
            durationSeconds = 30,
            macroTargetToken = "target",
            position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = -120, y = -40 },
        })
        assert.is_false(c.enabled)
        assert.is_false(c.startOnEncounterStart)
        assert.is_false(c.autoShowPanel)
        assert.are.equal(1.25, c.scale)
        assert.are.equal(5, c.visibilitySeconds)
        assert.are.equal(30, c.durationSeconds)
        assert.are.equal("target", c.macroTargetToken)
        assert.are.equal("TOPLEFT", c.position.point)
        assert.are.equal(-120, c.position.x)
    end)

    it("retombe sur les defaults si le bloc est absent", function()
        local c = Config.resolveIntermission(nil)
        assert.is_true(c.enabled)
        assert.is_true(c.startOnEncounterStart)
        assert.are.equal(3, c.visibilitySeconds)
        assert.are.equal("player", c.macroTargetToken)
        assert.are.equal("CENTER", c.position.point)
    end)
end)
