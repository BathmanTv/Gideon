--[[--------------------------------------------------------------------------
    tests/spec/intermission_spec.lua   (busted)
    Tests HORS JEU du module « Intermission Coach ».

    Deux familles de tests :
      1. la CONNAISSANCE du module : convention des orbes (qui va ou, quel ping),
         regles de collision (2+2 et 1+3 sauvent, 2+3 = 5 verts = mort),
         generation de la macro de ping, lecture du plan prepare hors jeu ;
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

describe("Intermission : convention des orbes", function()
    local I = wowenv.loadCore().Intermission

    it("liste les 3 declarations dans un ordre deterministe", function()
        assert.are.same({ "1", "2", "3" }, I.DECLARATIONS)
    end)

    it("decrit les orbes de chaque declaration", function()
        assert.are.equal("1 vert + 3 rouges", I.getDeclaration("1").orbs)
        assert.are.equal("2 verts + 2 rouges", I.getDeclaration("2").orbs)
        assert.are.equal("3 verts + 1 rouge", I.getDeclaration("3").orbs)
        assert.are.equal(1, I.getDeclaration("1").greens)
        assert.are.equal(2, I.getDeclaration("2").greens)
        assert.are.equal(3, I.getDeclaration("3").greens)
    end)

    it("associe la position spatiale preparee par la guilde", function()
        assert.are.equal("LEFT", I.getDeclaration("1").position)
        assert.are.equal("MIDDLE", I.getDeclaration("2").position)
        assert.are.equal("RIGHT", I.getDeclaration("3").position)
        assert.matches("GAUCHE", I.getDeclaration("1").positionLabel)
        assert.matches("MILIEU", I.getDeclaration("2").positionLabel)
        assert.matches("DROITE", I.getDeclaration("3").positionLabel)
    end)

    it("associe le ping de la convention (vert = 3, bleu = 2, rouge = 1)", function()
        assert.are.equal("Warning", I.getDeclaration("1").ping)
        assert.are.equal("ROUGE", I.getDeclaration("1").pingColor)
        assert.are.equal("OnMyWay", I.getDeclaration("2").ping)
        assert.are.equal("BLEU", I.getDeclaration("2").pingColor)
        assert.are.equal("Assist", I.getDeclaration("3").ping)
        assert.are.equal("VERT", I.getDeclaration("3").pingColor)
    end)

    it("donne une consigne et une cible de regroupement par declaration", function()
        for _, n in ipairs(I.DECLARATIONS) do
            local rec = I.getDeclaration(n)
            assert.is_string(rec.action)
            assert.is_true(#rec.action > 10)
            assert.is_string(rec.find)
            assert.is_true(#rec.find > 10)
        end
        assert.matches("1", I.getDeclaration("1").find)
        assert.matches("2", I.getDeclaration("2").find)
        assert.matches("1", I.getDeclaration("3").find)
    end)

    it("renvoie une copie : modifier le resultat ne casse pas la constante", function()
        local rec = I.getDeclaration("2")
        rec.orbs = "corrompu"
        assert.are.equal("2 verts + 2 rouges", I.getDeclaration("2").orbs)
    end)

    it("normalise la saisie du joueur et refuse le reste", function()
        assert.are.equal("1", I.normalizeDeclaration(" 1 "))
        assert.are.equal("3", I.normalizeDeclaration(3))
        assert.is_nil(I.normalizeDeclaration("4"))
        assert.is_nil(I.normalizeDeclaration(""))
        assert.is_nil(I.normalizeDeclaration(nil))
        local rec, err = I.getDeclaration("9")
        assert.is_nil(rec)
        assert.matches("inconnue", err)
    end)
end)

describe("Intermission : regles de collision", function()
    local I = wowenv.loadCore().Intermission

    it("accepte 2+2", function()
        local ok = assert(I.checkMeeting("2", "2"))
        assert.is_true(ok.ok)
        assert.are.equal(4, ok.greens)
        assert.are.equal("2+2", ok.label)
    end)

    it("accepte 1+3 dans les deux sens", function()
        assert.is_true(I.checkMeeting("1", "3").ok)
        assert.is_true(I.checkMeeting("3", "1").ok)
        assert.are.equal(4, I.checkMeeting("1", "3").greens)
    end)

    it("refuse 2+3 et nomme la mort 5 verts", function()
        local res = assert(I.checkMeeting("2", "3"))
        assert.is_false(res.ok)
        assert.are.equal(5, res.greens)
        assert.are.equal("2+3", res.label)
        assert.matches("5 verts", res.reason)
    end)

    it("refuse 1+1 et 3+3", function()
        assert.is_false(I.checkMeeting("1", "1").ok)
        assert.is_false(I.checkMeeting("3", "3").ok)
        assert.are.equal(2, I.checkMeeting("1", "1").greens)
        assert.are.equal(6, I.checkMeeting("3", "3").greens)
    end)

    it("refuse une declaration inconnue", function()
        local res, err = I.checkMeeting("2", "x")
        assert.is_nil(res)
        assert.matches("inconnue", err)
    end)
end)

describe("Intermission : macro de ping", function()
    local I = wowenv.loadCore().Intermission

    it("genere l'appel API documente pour chaque declaration", function()
        local m1 = assert(I.buildMacro("1"))
        assert.matches("C_Ping%.SendMacroPing", m1.primary)
        assert.matches("Enum%.PingSubjectType%.Warning", m1.primary)
        assert.matches('targetToken = "player"', m1.primary)
        local m2 = assert(I.buildMacro("2"))
        assert.matches("Enum%.PingSubjectType%.OnMyWay", m2.primary)
        local m3 = assert(I.buildMacro("3"))
        assert.matches("Enum%.PingSubjectType%.Assist", m3.primary)
    end)

    it("fournit une variante /ping et une note « a confirmer »", function()
        local m = assert(I.buildMacro("3"))
        assert.matches("^/ping ", m.fallback)
        assert.matches("Assist", m.fallback)
        assert.matches("confirmer", m.note)
    end)

    it("accepte un autre jeton de cible", function()
        local m = assert(I.buildMacro("2", "target"))
        assert.matches('targetToken = "target"', m.primary)
    end)

    it("refuse une declaration inconnue et ne fabrique jamais de texte interdit", function()
        local m, err = I.buildMacro("7")
        assert.is_nil(m)
        assert.matches("inconnue", err)
        for _, n in ipairs(I.DECLARATIONS) do
            local ok = I.buildMacro(n)
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
        assert.matches("OBSCUR", I.snapshot(st).headline)
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
        assert.matches("TU ES 2", text)
        assert.matches("2 verts %+ 2 rouges", text)
        assert.matches("MILIEU", text)
        assert.matches("BLEU", text)
        assert.matches("OnMyWay", text)
        assert.are.equal(snap.declaration, "2")
        assert.matches("C_Ping%.SendMacroPing", snap.macroPrimary)
    end)

    it("rappelle explicitement ce qui n'est PAS transmissible", function()
        local st = I.newState()
        I.start(st)
        I.declare(st, "1")
        local text = table.concat(I.snapshot(st).lines, "\n")
        assert.matches("INCONNU", text)
        assert.matches("ping", text)
        assert.is_nil(string.find(text, FORBIDDEN_EVENT, 1, true))
    end)

    it("change de declaration sans redemarrer l'intermission", function()
        local st = I.newState()
        I.start(st)
        I.tick(st, 1)
        I.declare(st, "3")
        I.declare(st, "1")
        assert.are.equal("1", st.declaration)
        assert.are.equal(1, st.elapsed)
    end)

    it("refuse une declaration invalide ou hors intermission", function()
        local st = I.newState()
        local res, err = I.declare(st, "2")
        assert.is_nil(res)
        assert.matches("non demarree", err)
        I.start(st)
        local res2, err2 = I.declare(st, "9")
        assert.is_nil(res2)
        assert.matches("inconnue", err2)
        assert.is_nil(st.declaration)
    end)

    it("termine (DONE) a la fin de la timeline en gardant la consigne", function()
        local st = I.newState({ visibilitySeconds = 3, durationSeconds = 6 })
        I.start(st)
        I.declare(st, "3")
        I.tick(st, 5)
        assert.are.equal(I.PHASE.DARK, st.phase)
        I.tick(st, 2)
        assert.are.equal(I.PHASE.DONE, st.phase)
        local snap = I.snapshot(st)
        assert.is_false(snap.showButtons)
        assert.matches("TU ES 3", table.concat(snap.lines, "\n"))
        local res, err = I.declare(st, "1")
        assert.is_nil(res)
        assert.matches("terminee", err)
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
        assert.are.equal("2", plan.me.role)
        assert.are.equal("MIDDLE", plan.me.position)
        local text = table.concat(plan.lines, "\n")
        assert.matches("Ton partenaire : Velna", text)
        assert.matches("Ton role", text)
        assert.matches("MIDDLE", text)
    end)

    it("verifie la rencontre preparee (2+2 sauf)", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Torgh"))
        assert.is_true(plan.meeting.ok)
        assert.matches("2%+2", table.concat(plan.lines, "\n"))
        local plan2 = assert(I.buildPlan(clean, "Bathman"))
        assert.is_true(plan2.meeting.ok)
        assert.matches("1%+3", table.concat(plan2.lines, "\n"))
    end)

    it("signale une rencontre mortelle (2+3)", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "A", b = "B" } },
            plan = {
                { name = "A", role = "2", position = "MIDDLE" },
                { name = "B", role = "3", position = "RIGHT" },
            },
        }))
        local plan = assert(I.buildPlan(clean, "A"))
        assert.is_false(plan.meeting.ok)
        assert.matches("MORT", table.concat(plan.lines, "\n"))
    end)

    it("liste les paires triees par nom", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Velna"))
        assert.are.equal("Bathman", plan.pairs[1].a)
        assert.are.equal("Velna", plan.pairs[2].a)
        assert.is_nil(plan.pairs[1].extra)
        assert.are.equal("1", plan.pairs[1].roleA)
        assert.are.equal("3", plan.pairs[1].roleB)
    end)

    it("fonctionne sans bloc plan (champ optionnel)", function()
        local clean = assert(Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "Velna", b = "Torgh" } },
        }))
        local plan = assert(I.buildPlan(clean, "Velna"))
        assert.are.equal("Torgh", plan.partner)
        assert.is_nil(plan.me)
        assert.matches("Ton partenaire : Torgh", table.concat(plan.lines, "\n"))
    end)

    it("signale un joueur absent de l'appariement", function()
        local clean = assert(Pairing.validateAssignment(loadFixture()))
        local plan = assert(I.buildPlan(clean, "Inconnu"))
        assert.is_nil(plan.partner)
        assert.matches("pas dans l'appariement", table.concat(plan.lines, "\n"))
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
        assert.matches("invalide", err)
        local plan2, err2 = I.buildPlan({ pairs = "non" }, "A")
        assert.is_nil(plan2)
        assert.matches("invalide", err2)
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
