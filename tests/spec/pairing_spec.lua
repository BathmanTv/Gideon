--[[--------------------------------------------------------------------------
    tests/spec/pairing_spec.lua   (busted)
    Tests HORS JEU de la logique d'appariement. Aucun mock d'API WoW.
    Lancement :  busted  (depuis la racine du depot)
----------------------------------------------------------------------------]]
local wowenv = require("tests.support.wowenv")

describe("Pairing.buildPairs", function()
    local ns, Pairing

    setup(function()
        ns = wowenv.loadCore()
        Pairing = ns.Pairing
    end)

    it("apparie 3 ember avec 3 frost (cas nominal)", function()
        local players = {
            { name = "Tank1", debuff = "ember" },
            { name = "Tank2", debuff = "ember" },
            { name = "Heal1", debuff = "frost" },
            { name = "Heal2", debuff = "frost" },
            { name = "Dps1", debuff = "ember" },
            { name = "Dps2", debuff = "frost" },
        }
        local res, err = Pairing.buildPairs(players)
        assert.is_nil(err)
        assert.are.equal(3, #res.pairs)
        assert.are.equal(0, #res.unpaired)
        -- Ordre deterministe : ember trie vs frost trie
        assert.are.same({ a = "Dps1", b = "Dps2" }, { a = res.pairs[1].a, b = res.pairs[1].b })
        assert.are.same({ a = "Tank1", b = "Heal1" }, { a = res.pairs[2].a, b = res.pairs[2].b })
        assert.are.same({ a = "Tank2", b = "Heal2" }, { a = res.pairs[3].a, b = res.pairs[3].b })
    end)

    it("est insensible a l'ordre d'entree (determinisme)", function()
        -- Memes joueurs, ordres d'entree inverses -> resultat identique.
        local a = {
            { name = "Zoe", debuff = "frost" },
            { name = "Alice", debuff = "ember" },
            { name = "Yann", debuff = "ember" },
            { name = "Bob", debuff = "frost" },
        }
        local b = {
            { name = "Bob", debuff = "frost" },
            { name = "Yann", debuff = "ember" },
            { name = "Zoe", debuff = "frost" },
            { name = "Alice", debuff = "ember" },
        }
        local ra = assert(Pairing.buildPairs(a))
        local rb = assert(Pairing.buildPairs(b))
        assert.are.same(ra.pairs, rb.pairs)
        -- Appariement alphabetique : Alice-Bob puis Yann-Zoe
        assert.are.equal("Alice", ra.pairs[1].a)
        assert.are.equal("Bob", ra.pairs[1].b)
    end)

    it("normalise la casse et les espaces", function()
        local res = assert(Pairing.buildPairs({
            { name = "A", debuff = "  Ember " },
            { name = "B", debuff = "FROST" },
        }))
        assert.are.equal(1, #res.pairs)
        assert.are.equal("A", res.pairs[1].a)
        assert.are.equal("B", res.pairs[1].b)
    end)

    it("renvoie les surnumeraires comme non-apparies avec une raison", function()
        local res = assert(Pairing.buildPairs({
            { name = "E1", debuff = "ember" },
            { name = "E2", debuff = "ember" },
            { name = "E3", debuff = "ember" },
            { name = "F1", debuff = "frost" },
        }))
        assert.are.equal(1, #res.pairs)
        assert.are.equal(2, #res.unpaired)
        assert.are.equal("E2", res.unpaired[1].name)
        assert.are.equal("no_partner:frost", res.unpaired[1].reason)
    end)

    it("signale les joueurs sans debuff", function()
        local res = assert(Pairing.buildPairs({
            { name = "A", debuff = "ember" },
            { name = "B", debuff = "frost" },
            { name = "C" },
        }))
        assert.are.equal(1, #res.pairs)
        assert.are.equal(1, #res.unpaired)
        assert.are.equal("missing_debuff", res.unpaired[1].reason)
    end)

    it("signale un debuff inconnu du mapping", function()
        local res = assert(Pairing.buildPairs({
            { name = "A", debuff = "poison" },
        }))
        assert.are.equal(0, #res.pairs)
        assert.are.equal("unknown_debuff:poison", res.unpaired[1].reason)
    end)

    it("refuse une entree invalide", function()
        local res, err = Pairing.buildPairs("pas une table")
        assert.is_nil(res)
        assert.matches("players", err)
    end)

    it("refuse un nom en double", function()
        local res, err = Pairing.buildPairs({
            { name = "A", debuff = "ember" },
            { name = "A", debuff = "frost" },
        })
        assert.is_nil(res)
        assert.matches("double", err)
    end)
end)

describe("Pairing.findPartner", function()
    local ns = wowenv.loadCore()

    it("trouve le partenaire dans les deux sens", function()
        local res = assert(ns.Pairing.buildPairs({
            { name = "A", debuff = "ember" },
            { name = "B", debuff = "frost" },
        }))
        assert.are.equal("B", ns.Pairing.findPartner(res, "A"))
        assert.are.equal("A", ns.Pairing.findPartner(res, "B"))
        assert.is_nil(ns.Pairing.findPartner(res, "Z"))
    end)
end)

describe("Pairing.validateAssignment", function()
    local ns = wowenv.loadCore()

    it("accepte un bloc valide et filtre les champs", function()
        local clean = assert(ns.Pairing.validateAssignment({
            schema = 1,
            pairs = { { a = "A", b = "B", extra = 42 } },
        }))
        assert.are.equal(1, #clean.pairs)
        assert.is_nil(clean.pairs[1].extra)
    end)

    it("rejette un bloc malforme", function()
        local clean, err = ns.Pairing.validateAssignment({ pairs = { { a = 1, b = "B" } } })
        assert.is_nil(clean)
        assert.matches("invalide", err)
    end)
end)
