--[[--------------------------------------------------------------------------
    GideonRaid / Core / Pairing.lua

    LOGIQUE PURE. Interdit dans ce fichier :
      - tout appel a l'API WoW (CreateFrame, UnitAura, C_*, ...)
      - toute lecture d'une valeur secrete (issecretvalue / canaccessvalue)
      - toute dependance a l'etat global du client

    Ce fichier est charge de deux facons :
      1. par le client WoW, via le .toc  -> (addonName, ns)
      2. par busted / le CLI hors jeu    -> tests/support/wowenv.lua
    Il ne doit donc JAMAIS toucher a _G directement.

    Ref API 12.x : https://warcraft.wiki.gg/wiki/Secret_Values
    Source contrainte : "Combat API functions may now return secret values ...
    Tainted code is not allowed to perform arithmetic on secret values /
    is not allowed to compare or perform boolean tests on secret values."
    => Ce module ne traite QUE des donnees fournies par le joueur ou par GIDEON
       (chaines de texte non secretes), jamais des valeurs d'unite.
----------------------------------------------------------------------------]]
local _, ns = ...

---@class Pairing
local Pairing = {}
ns.Pairing = Pairing

Pairing.SCHEMA_VERSION = 1

local DEFAULT_RULES = {
    -- Un joueur "ember" doit etre apparie a un joueur "frost" et reciproquement.
    -- Table symetrique : compatible[d] = d'
    compatible = {
        ember = "frost",
        frost = "ember",
    },
}

Pairing.DEFAULT_RULES = DEFAULT_RULES

-- Normalise un identifiant de debuff saisi par un joueur ("  Frost " -> "frost").
-- Retourne nil si la valeur n'est pas une chaine exploitable.
function Pairing.normalizeDebuff(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local s = raw:lower():gsub("%s+", "")
    if s == "" then
        return nil
    end
    return s
end

-- Copie triee par NOM (jamais par position d'entree) : le resultat ne depend
-- donc pas de l'ordre du roster envoye par GIDEON -> reproductible et testable.
local function sortedCopy(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return out
end

--- Construit les paires a partir d'une liste de joueurs.
--- @param players table  liste { { name = "Tank1", debuff = "ember" }, ... }
--- @param rules   table|nil  { compatible = { ember = "frost", ... } }
--- @return table|nil result { pairs = { {a=,b=,debuffA=,debuffB=}, ... }, unpaired = { {name=,reason=}, ... }, schema = 1 }
--- @return string|nil erreur
function Pairing.buildPairs(players, rules)
    if type(players) ~= "table" then
        return nil, "players doit etre une table"
    end

    rules = rules or DEFAULT_RULES
    local compatible = rules.compatible or DEFAULT_RULES.compatible

    -- 1. Indexation : un bucket par debuff normalise.
    local buckets, unpaired, seenNames = {}, {}, {}
    for index = 1, #players do
        local p = players[index]
        if type(p) ~= "table" or type(p.name) ~= "string" or p.name == "" then
            return nil, "joueur #" .. tostring(index) .. " invalide (name manquant)"
        end
        if seenNames[p.name] then
            return nil, "nom en double : " .. p.name
        end
        seenNames[p.name] = true

        local d = Pairing.normalizeDebuff(p.debuff)
        if d == nil then
            unpaired[#unpaired + 1] = { name = p.name, reason = "missing_debuff" }
        elseif type(compatible[d]) ~= "string" then
            unpaired[#unpaired + 1] = { name = p.name, reason = "unknown_debuff:" .. d }
        else
            buckets[d] = buckets[d] or {}
            local b = buckets[d]
            b[#b + 1] = { name = p.name, key = d, index = index }
        end
    end

    -- 2. Parcours deterministe des buckets (ordre alphabetique des debuffs).
    local debuffNames = {}
    for d in pairs(buckets) do
        debuffNames[#debuffNames + 1] = d
    end
    table.sort(debuffNames)

    -- 3. Appariement. On ne traite chaque paire de debuffs qu'une seule fois
    --    (d < compatible[d]) pour ne pas apparier deux fois.
    local pairsOut, consumed = {}, {}
    for _, d in ipairs(debuffNames) do
        local other = compatible[d]
        if not consumed[d] and not consumed[other] then
            consumed[d], consumed[other] = true, true
            local left, right = sortedCopy(buckets[d]), sortedCopy(buckets[other] or {})
            local n = math.min(#left, #right)
            for i = 1, n do
                pairsOut[#pairsOut + 1] = {
                    a = left[i].name,
                    b = right[i].name,
                    debuffA = d,
                    debuffB = other,
                }
            end
            for i = n + 1, #left do
                unpaired[#unpaired + 1] = { name = left[i].name, reason = "no_partner:" .. other }
            end
            for i = n + 1, #right do
                unpaired[#unpaired + 1] = { name = right[i].name, reason = "no_partner:" .. d }
            end
        end
    end

    table.sort(unpaired, function(a, b)
        return a.name < b.name
    end)

    return { pairs = pairsOut, unpaired = unpaired, schema = Pairing.SCHEMA_VERSION }
end

--- Retourne le partenaire d'un joueur, ou nil.
function Pairing.findPartner(result, playerName)
    if type(result) ~= "table" or type(result.pairs) ~= "table" then
        return nil
    end
    for _, pair in ipairs(result.pairs) do
        if pair.a == playerName then
            return pair.b, pair
        end
        if pair.b == playerName then
            return pair.a, pair
        end
    end
    return nil
end

--- Validateur du bloc recu de GIDEON (SavedVariables ecrites hors jeu).
--- Aucune API WoW : on ne lit que des chaines et des nombres.
function Pairing.validateAssignment(block)
    if type(block) ~= "table" then
        return nil, "assignment absent"
    end
    if type(block.pairs) ~= "table" then
        return nil, "assignment.pairs manquant"
    end
    local clean = {}
    for i, pair in ipairs(block.pairs) do
        if type(pair.a) ~= "string" or type(pair.b) ~= "string" then
            return nil, "paire #" .. i .. " invalide"
        end
        clean[#clean + 1] = { a = pair.a, b = pair.b }
    end
    local out = { pairs = clean, schema = tonumber(block.schema) or 1 }
    -- Champ OPTIONNEL `plan` (role / position par joueur) : il est repris tel quel
    -- et valide par Intermission.validatePlan / buildPlan (voir la doc du module).
    -- On ne le filtre pas ici pour ne pas dupliquer le contrat a deux endroits.
    if type(block.plan) == "table" then
        out.plan = block.plan
    end
    return out
end
