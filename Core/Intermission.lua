--[[--------------------------------------------------------------------------
    GideonRaid / Core / Intermission.lua

    « Intermission Coach » - boss Entombed Sentinels (mythique), raid
    The Venomous Abyss (WoW Midnight 12.1.0).

    LOGIQUE PURE (Lua 5.1). Ce fichier ne touche a AUCUNE API WoW, ne lit aucune
    valeur d'unite, n'enregistre aucun evenement. Il tourne tel quel sous busted
    et sous lua5.1 hors du client.

    MECANIQUE DE REFERENCE
    https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview
      - a l'intermission, chaque joueur recoit une combinaison d'orbes indiquee
        au-dessus de sa tete : 1 vert + 3 rouges (« 1 »), 2 verts + 2 rouges
        (« 2 »), 3 verts + 1 rouge (« 3 ») ;
      - les combinaisons qui sauvent sont 2+2 et 1+3 ; toute autre collision tue,
        et 2+3 fait 5 verts (« 5g ») ;
      - environ 3 s apres le debut, la salle est obscurcie : chaque joueur ne
        voit plus que SON propre numero.

    Ref API 12.x : https://warcraft.wiki.gg/wiki/Secret_Values
    Source contrainte : "Combat API functions may now return secret values ...
    Tainted code is not allowed to compare or perform boolean tests on secret
    values."
    => ce module ne compare JAMAIS une valeur d'unite. Tout ce qu'il manipule
       vient du joueur (clic) ou d'un fichier prepare hors jeu (SavedVariables).

    Ref API 12.1.0 : https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing
    Source contrainte : "#protected - This can only be called from secure code."
    => l'addon ne peut PAS envoyer de ping lui-meme : il genere le TEXTE d'une
       macro que le joueur colle puis declenche (une macro est du code securise).

    AUCUN GetTime, AUCUN math.random, AUCUN ordre non deterministe : le temps est
    injecte dans tick(state, dt) par la couche de cablage.
----------------------------------------------------------------------------]]
local _, ns = ...

---@class Intermission
local Intermission = {}
ns.Intermission = Intermission

Intermission.SCHEMA_VERSION = 1

--- Duree de la fenetre ou les indicateurs des autres joueurs sont visibles (guide).
Intermission.VISIBILITY_SECONDS = 3

--- Duree par defaut de l'intermission si la timeline preparee n'en fournit pas.
Intermission.DEFAULT_DURATION_SECONDS = 20

--- Jeton de cible par defaut de la macro de ping (se ping soi-meme).
Intermission.DEFAULT_TARGET_TOKEN = "player"

--- Ordre d'affichage des declarations : « 1 », « 2 », « 3 » (jamais pairs()).
Intermission.DECLARATIONS = { "1", "2", "3" }

--- Phases de l'intermission.
Intermission.PHASE = {
    IDLE = "IDLE",
    VISIBLE = "VISIBLE",
    DARK = "DARK",
    DONE = "DONE",
}

local PHASE_IDLE = Intermission.PHASE.IDLE
local PHASE_VISIBLE = Intermission.PHASE.VISIBLE
local PHASE_DARK = Intermission.PHASE.DARK
local PHASE_DONE = Intermission.PHASE.DONE

--[[ Convention preparee hors jeu (aucune lecture d'API en jeu).

     position   : la position spatiale a tenir (convention de guilde)
     ping       : la valeur de Enum.PingSubjectType (voir la source API 12.1.0)
     pingColor  : la couleur du ping, VERIFIEE sur les captures du wiki
                  https://warcraft.wiki.gg/wiki/Ping_System (galerie) :
                  Warning = rouge, OnMyWay = bleu, Assist = vert.
                  La convention de la guilde est : vert = « 3 », bleu = « 2 »,
                  rouge = « 1 ».
     pingToken  : le jeton utilisable dans une macro /ping (variante a confirmer).
]]
local CONVENTION = {
    ["1"] = {
        n = "1",
        orbs = "1 vert + 3 rouges",
        greens = 1,
        position = "LEFT",
        positionLabel = "GAUCHE du boss",
        ping = "Warning",
        pingToken = "Warning",
        pingColor = "ROUGE",
        pingColorHex = "|cffff4040",
        action = "SAUTE SUR PLACE puis ping ROUGE.",
        find = "Rejoins un joueur 3 (1+3 = sauf), jamais un 2.",
    },
    ["2"] = {
        n = "2",
        orbs = "2 verts + 2 rouges",
        greens = 2,
        position = "MIDDLE",
        positionLabel = "MILIEU / SOUS LE BOSS",
        ping = "OnMyWay",
        pingToken = "OnMyWay",
        pingColor = "BLEU",
        pingColorHex = "|cff40a0ff",
        action = "COURS SOUS LE BOSS et reste au milieu, puis ping BLEU.",
        find = "Rejoins un autre 2 (2+2 = sauf).",
    },
    ["3"] = {
        n = "3",
        orbs = "3 verts + 1 rouge",
        greens = 3,
        position = "RIGHT",
        positionLabel = "DROITE du boss",
        ping = "Assist",
        pingToken = "Assist",
        pingColor = "VERT",
        pingColorHex = "|cff40ff40",
        action = "FONCE sur un joueur 1, puis ping VERT.",
        find = "Trouve un joueur 1 (3+1 = sauf).",
    },
}

-- La table est exposee en lecture (UI : couleurs, libelles) mais jamais renvoyee
-- directement : getDeclaration() renvoie une copie.
Intermission.CONVENTION = CONVENTION

local D_PROMPT = "Compte TES orbes au-dessus de ta tete (1, 2 ou 3) et clique."
local D_CAVEAT = "INCONNU : personne ne peut lire ton numero ni te dire qui a declare quoi."
local D_CHANNEL = "Le seul signal visible par les autres joueurs : TON ping."

local function round(n)
    return math.floor(n + 0.5)
end

local function clampNumber(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function clampInt(value, min, max)
    return round(clampNumber(tonumber(value) or min, min, max))
end

local function copyRecord(rec)
    return {
        n = rec.n,
        orbs = rec.orbs,
        greens = rec.greens,
        position = rec.position,
        positionLabel = rec.positionLabel,
        ping = rec.ping,
        pingToken = rec.pingToken,
        pingColor = rec.pingColor,
        pingColorHex = rec.pingColorHex,
        action = rec.action,
        find = rec.find,
    }
end

--- Normalise la saisie du joueur (« 2 », « 3 », 1, ...) en "1"|"2"|"3".
--- @return string|nil declaration, string|nil erreur
function Intermission.normalizeDeclaration(raw)
    if type(raw) == "number" then
        raw = tostring(raw)
    end
    if type(raw) ~= "string" then
        return nil, "declaration invalide (attendu 1, 2 ou 3)"
    end
    local trimmed = raw:gsub("%s+", "")
    if CONVENTION[trimmed] == nil then
        if trimmed == "" then
            return nil, "declaration vide (attendu 1, 2 ou 3)"
        end
        return nil, "declaration inconnue : " .. trimmed
    end
    return trimmed
end

--- Retourne (copie de la convention, nil) ou (nil, erreur).
function Intermission.getDeclaration(raw)
    local n, err = Intermission.normalizeDeclaration(raw)
    if n == nil then
        return nil, err
    end
    return copyRecord(CONVENTION[n])
end

--- Verifie si deux declarations peuvent se rejoindre sans mourir.
--- Regle du guide : 2+2 et 1+3 sauvent ; le reste tue (2+3 = 5 verts = « 5g »).
--- @return table|nil result { ok, label, greens, reds, reason }, string|nil erreur
function Intermission.checkMeeting(rawA, rawB)
    local a, errA = Intermission.getDeclaration(rawA)
    if a == nil then
        return nil, errA
    end
    local b, errB = Intermission.getDeclaration(rawB)
    if b == nil then
        return nil, errB
    end
    local greens = a.greens + b.greens
    local reds = (4 - a.greens) + (4 - b.greens)
    local label = a.n .. "+" .. b.n
    local ok = (a.n == "2" and b.n == "2") or (a.n == "1" and b.n == "3") or (a.n == "3" and b.n == "1")
    local reason
    if ok then
        reason = "combinaison sure (" .. greens .. " verts + " .. reds .. " rouges)"
    elseif greens == 5 then
        reason = "5 verts = 5g : MORT"
    else
        reason = "combinaison interdite (" .. greens .. " verts + " .. reds .. " rouges)"
    end
    return { ok = ok, label = label, greens = greens, reds = reds, reason = reason }
end

--- Genere le texte de macro a coller (le joueur la declenche : une macro est du
--- code securise, seule façon d'appeler l'API #protected).
--- @return table|nil { primary, fallback, ping, target, note }, string|nil erreur
function Intermission.buildMacro(raw, targetToken)
    local rec, err = Intermission.getDeclaration(raw)
    if rec == nil then
        return nil, err
    end
    local target = targetToken
    if type(target) ~= "string" or target == "" then
        target = Intermission.DEFAULT_TARGET_TOKEN
    end
    return {
        primary = "/run C_Ping.SendMacroPing({type = Enum.PingSubjectType." .. rec.ping .. ', targetToken = "' .. target .. '"})',
        fallback = "/ping " .. rec.pingToken,
        ping = rec.ping,
        target = target,
        note = "Syntaxe a confirmer en jeu (voir docs/INTERMISSION-COACH.md).",
    }
end

--- Valide une timeline preparee hors jeu (SavedVariables).
--- @return table|nil { name, visibilitySeconds, durationSeconds }, string|nil erreur
function Intermission.validateTimeline(entry)
    if entry == nil then
        return {
            name = "Intermission",
            visibilitySeconds = Intermission.VISIBILITY_SECONDS,
            durationSeconds = Intermission.DEFAULT_DURATION_SECONDS,
        }
    end
    if type(entry) ~= "table" then
        return nil, "timeline invalide (table attendue)"
    end
    local visibility = Intermission.VISIBILITY_SECONDS
    if type(entry.visibilitySeconds) == "number" then
        visibility = clampInt(entry.visibilitySeconds, 1, 10)
    end
    local duration = Intermission.DEFAULT_DURATION_SECONDS
    if type(entry.durationSeconds) == "number" then
        duration = clampInt(entry.durationSeconds, visibility + 1, 120)
    end
    if duration <= visibility then
        duration = visibility + 1
    end
    local name = "Intermission"
    if type(entry.name) == "string" and entry.name ~= "" then
        name = entry.name
    end
    return { name = name, visibilitySeconds = visibility, durationSeconds = duration }
end

--- Cree un etat neuf (IDLE).
function Intermission.newState(timeline)
    local resolved = Intermission.validateTimeline(timeline) or Intermission.validateTimeline(nil)
    return {
        phase = PHASE_IDLE,
        elapsed = 0,
        declaration = nil,
        timeline = resolved,
    }
end

--- Demarre l'intermission (déclencheur : ENCOUNTER_START ou action du joueur).
--- @return table|nil state, string|nil erreur
function Intermission.start(state, timeline)
    if type(state) ~= "table" then
        return nil, "etat invalide"
    end
    if timeline ~= nil then
        local resolved, err = Intermission.validateTimeline(timeline)
        if resolved == nil then
            return nil, err
        end
        state.timeline = resolved
    end
    state.phase = PHASE_VISIBLE
    state.elapsed = 0
    state.declaration = nil
    return state
end

--- Avance l'horloge de l'intermission. dt est fourni par la couche de cablage :
--- ce module n'appelle jamais GetTime (interdit dans Core/, voir CONVENTIONS 7).
function Intermission.tick(state, dt)
    if type(state) ~= "table" then
        return state
    end
    if state.phase ~= PHASE_VISIBLE and state.phase ~= PHASE_DARK then
        return state
    end
    local step = tonumber(dt)
    if step == nil or step < 0 then
        return state
    end
    state.elapsed = state.elapsed + step
    local timeline = state.timeline
    if state.elapsed >= timeline.durationSeconds then
        state.phase = PHASE_DONE
    elseif state.elapsed >= timeline.visibilitySeconds then
        state.phase = PHASE_DARK
    else
        state.phase = PHASE_VISIBLE
    end
    return state
end

--- Enregistre la declaration du joueur (clic sur 1, 2 ou 3).
--- @return table|nil state, string|nil erreur
function Intermission.declare(state, raw)
    if type(state) ~= "table" then
        return nil, "etat invalide"
    end
    if state.phase == PHASE_IDLE then
        return nil, "intermission non demarree"
    end
    if state.phase == PHASE_DONE then
        return nil, "intermission terminee"
    end
    local n, err = Intermission.normalizeDeclaration(raw)
    if n == nil then
        return nil, err
    end
    state.declaration = n
    return state
end

--- Remet l'etat a zero (IDLE).
function Intermission.reset(state)
    if type(state) ~= "table" then
        return nil, "etat invalide"
    end
    state.phase = PHASE_IDLE
    state.elapsed = 0
    state.declaration = nil
    return state
end

--- Secondes restantes de la fenetre de visibilite (0 une fois obscurci).
function Intermission.remainingVisibility(state)
    if type(state) ~= "table" or type(state.timeline) ~= "table" then
        return 0
    end
    local left = state.timeline.visibilitySeconds - state.elapsed
    if left < 0 then
        left = 0
    end
    return round(left)
end

--- Etat affichable, entierement calcule ici : la couche UI ne fait que rendre.
function Intermission.snapshot(state)
    local phase = PHASE_IDLE
    local declaration, elapsed, timeline = nil, 0, Intermission.validateTimeline(nil)
    if type(state) == "table" then
        phase = state.phase or PHASE_IDLE
        declaration = state.declaration
        elapsed = state.elapsed or 0
        timeline = state.timeline or timeline
    end

    local snap = {
        phase = phase,
        visible = phase ~= PHASE_IDLE,
        showButtons = phase == PHASE_VISIBLE or phase == PHASE_DARK,
        declaration = declaration,
        countdownText = "0",
        headline = "",
        lines = {},
        macroPrimary = nil,
        macroFallback = nil,
        macroNote = nil,
        caveat = D_CAVEAT,
        prompt = D_PROMPT,
    }

    local lines = snap.lines
    if phase == PHASE_IDLE then
        snap.headline = "INTERMISSION : PAS LANCEE"
        lines[#lines + 1] = "Timeline pre-calculee : " .. timeline.visibilitySeconds .. " s visibles puis salle obscurcie."
        lines[#lines + 1] = "Declenchement : debut de combat sur le boss, ou touche/bouton."
        lines[#lines + 1] = D_PROMPT
        return snap
    end

    if phase == PHASE_VISIBLE then
        local left = Intermission.remainingVisibility({ timeline = timeline, elapsed = elapsed })
        snap.countdownText = tostring(left)
        snap.headline = "REGARDE AU-DESSUS DES TETES : " .. left .. " s"
        if declaration == nil then
            lines[#lines + 1] = "Les indicateurs des autres joueurs sont encore visibles."
            lines[#lines + 1] = D_PROMPT
        end
    elseif phase == PHASE_DARK then
        snap.headline = "SALLE OBSCURCIE : TU NE VOIS PLUS QUE TOI"
        if declaration == nil then
            lines[#lines + 1] = "Les indicateurs des autres joueurs sont invisibles."
            lines[#lines + 1] = D_PROMPT
        end
    else
        snap.headline = "INTERMISSION TERMINEE"
    end

    local rec = declaration and CONVENTION[declaration] or nil
    if rec ~= nil then
        snap.instruction = copyRecord(rec)
        lines[#lines + 1] = "TU ES " .. rec.n .. "  (" .. rec.orbs .. ")"
        lines[#lines + 1] = "POSITION : " .. rec.positionLabel
        lines[#lines + 1] = "PING : " .. rec.pingColor .. " (" .. rec.ping .. ")"
        lines[#lines + 1] = "FAIS : " .. rec.action
        lines[#lines + 1] = "REJOINS : " .. rec.find
        local macro = Intermission.buildMacro(rec.n, nil)
        if macro ~= nil then
            snap.macroPrimary = macro.primary
            snap.macroFallback = macro.fallback
            snap.macroNote = macro.note
        end
    end
    lines[#lines + 1] = D_CAVEAT
    lines[#lines + 1] = D_CHANNEL
    return snap
end

--[[ Plan prepare hors jeu.

     Bloc OPTIONNEL ecrit par GIDEON dans les SavedVariables :

       assignment = {
           schema = 1,
           pairs = { { a = "Velna", b = "Torgh" }, ... },
           plan  = {                                  -- optionnel
               { name = "Velna", role = "2", position = "MIDDLE", note = "..." },
               ...
           },
       }

     `role` peut contenir la declaration preparee ("1" / "2" / "3") ou un role de
     raid libre ("Tank", "Heal"). Rien n'est devine : si GIDEON ne l'ecrit pas,
     l'addon ne l'affiche pas.
]]

--- Valide le bloc `plan` : entrees malformees ecartees et listees, jamais de crash.
--- @return table { byName = {}, order = {}, errors = {} }
function Intermission.validatePlan(plan)
    local out = { byName = {}, order = {}, errors = {} }
    if plan == nil then
        return out
    end
    if type(plan) ~= "table" then
        out.errors[#out.errors + 1] = "plan invalide (table attendue)"
        return out
    end
    for index = 1, #plan do
        local entry = plan[index]
        if type(entry) ~= "table" or type(entry.name) ~= "string" or entry.name == "" then
            out.errors[#out.errors + 1] = "plan #" .. tostring(index) .. " ignore (name manquant)"
        elseif out.byName[entry.name] ~= nil then
            out.errors[#out.errors + 1] = "plan #" .. tostring(index) .. " ignore (nom en double : " .. entry.name .. ")"
        else
            local rec = { name = entry.name }
            if type(entry.role) == "string" and entry.role ~= "" then
                rec.role = entry.role
            end
            if type(entry.position) == "string" and entry.position ~= "" then
                rec.position = entry.position
            end
            if type(entry.note) == "string" and entry.note ~= "" then
                rec.note = entry.note
            end
            out.byName[entry.name] = rec
            out.order[#out.order + 1] = entry.name
        end
    end
    table.sort(out.order)
    table.sort(out.errors)
    return out
end

local function sortedPairs(assignment)
    local list = {}
    for index = 1, #assignment.pairs do
        local pair = assignment.pairs[index]
        list[#list + 1] = { a = pair.a, b = pair.b }
    end
    table.sort(list, function(left, right)
        if left.a ~= right.a then
            return left.a < right.a
        end
        return left.b < right.b
    end)
    return list
end

local function describePlayer(plan, name)
    local rec = plan.byName[name]
    if rec == nil then
        return nil
    end
    local parts = {}
    if rec.role ~= nil then
        parts[#parts + 1] = "role " .. rec.role
    end
    if rec.position ~= nil then
        parts[#parts + 1] = "position " .. rec.position
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, ", ")
end

--- Construit la vue pre-pull : partenaire, role/position prepares, paires triees.
--- Aucune lecture d'API : tout vient du bloc GIDEON deja valide.
--- @param assignment table bloc valide par Pairing.validateAssignment
--- @param playerName string nom du joueur courant (chaine fournie par le cablage)
--- @return table|nil plan, string|nil erreur
function Intermission.buildPlan(assignment, playerName)
    if type(assignment) ~= "table" or type(assignment.pairs) ~= "table" then
        return nil, "assignment invalide"
    end
    if type(playerName) ~= "string" or playerName == "" then
        return nil, "nom de joueur invalide"
    end

    local plan = Intermission.validatePlan(assignment.plan)
    local pairsList = sortedPairs(assignment)
    for index = 1, #pairsList do
        local pair = pairsList[index]
        pair.roleA = plan.byName[pair.a] and plan.byName[pair.a].role or nil
        pair.roleB = plan.byName[pair.b] and plan.byName[pair.b].role or nil
        pair.positionA = plan.byName[pair.a] and plan.byName[pair.a].position or nil
        pair.positionB = plan.byName[pair.b] and plan.byName[pair.b].position or nil
    end

    local out = {
        partner = nil,
        me = plan.byName[playerName],
        pairs = pairsList,
        planErrors = plan.errors,
        planCount = #plan.order,
        meeting = nil,
        lines = {},
    }

    local lines = out.lines
    local partner = ns.Pairing.findPartner(assignment, playerName)
    if partner == nil then
        lines[#lines + 1] = "Tu n'es pas dans l'appariement GIDEON."
    else
        out.partner = partner
        lines[#lines + 1] = "Ton partenaire : " .. partner
        if out.me ~= nil and out.me.role ~= nil then
            lines[#lines + 1] = "Ton role (prepare hors jeu) : " .. out.me.role
        end
        if out.me ~= nil and out.me.position ~= nil then
            lines[#lines + 1] = "Ta position (preparee hors jeu) : " .. out.me.position
        end
        local partnerInfo = describePlayer(plan, partner)
        if partnerInfo ~= nil then
            lines[#lines + 1] = partner .. " : " .. partnerInfo
        end
        if out.me ~= nil and out.me.role ~= nil and plan.byName[partner] ~= nil then
            local meeting = Intermission.checkMeeting(out.me.role, plan.byName[partner].role)
            if meeting ~= nil then
                out.meeting = meeting
                if meeting.ok then
                    lines[#lines + 1] = "Rencontre " .. meeting.label .. " : OK (" .. meeting.reason .. ")"
                else
                    lines[#lines + 1] = "|cffff5555Rencontre " .. meeting.label .. " : MORT (" .. meeting.reason .. ")|r"
                end
            end
        end
    end

    lines[#lines + 1] = "Paires (" .. #pairsList .. ") :"
    for index = 1, #pairsList do
        local pair = pairsList[index]
        local suffix = ""
        local roles = {}
        if pair.roleA ~= nil then
            roles[#roles + 1] = pair.a .. "=" .. pair.roleA
        end
        if pair.roleB ~= nil then
            roles[#roles + 1] = pair.b .. "=" .. pair.roleB
        end
        if #roles > 0 then
            suffix = "  [" .. table.concat(roles, " / ") .. "]"
        end
        lines[#lines + 1] = "  " .. index .. ". " .. pair.a .. " - " .. pair.b .. suffix
    end
    if #plan.errors > 0 then
        lines[#lines + 1] = "|cffff8080Plan : " .. tostring(#plan.errors) .. " entree(s) ignoree(s).|r"
    end
    lines[#lines + 1] = "Plan prepare hors jeu : aucune aura lue, aucun journal de combat."
    return out
end
