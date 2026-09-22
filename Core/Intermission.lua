--[[--------------------------------------------------------------------------
    GideonRaid / Core / Intermission.lua

    « Intermission Coach » - boss Entombed Sentinels (mythique), raid
    The Venomous Abyss (WoW Midnight 12.1.0).

    LOGIQUE PURE (Lua 5.1). Ce fichier ne touche a AUCUNE API WoW, ne lit aucune
    valeur d'unite, n'enregistre aucun evenement. Il tourne tel quel sous busted
    et sous lua5.1 hors du client.

    MECANIQUE DE REFERENCE (modele CORRIGE, autoritaire)
    https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview
      - le NUMERO affiche au-dessus de la tete ne determine PAS les couleurs :
          « 2 » = TOUJOURS 2 verts + 2 rouges, sans ambiguite ;
          « 1 » ou « 3 » = soit 3 verts + 1 rouge, soit 1 vert + 3 rouges :
          c'est la COULEUR des orbes qui tranche, jamais le numero.
        Il n'existe donc que TROIS etats reels : 3V1R, 2V2R, 1V3R.
      - la regle de survie est une ADDITION DE COULEURS : la somme des deux
        joueurs doit faire 4 VERTS et 4 ROUGES. Appariements valides :
        3V1R + 1V3R (= 4V4R) et 2V2R + 2V2R (= 4V4R). Toute autre combinaison
        tue : 3V1R + 2V2R = 5 verts = le « 5g » du guide.
      - environ 3 s apres le debut, la salle est obscurcie : chaque joueur ne
        voit plus que SES propres orbes (son numero seul ne suffit pas).

    REFUS DE L'ANCIEN MODELE : le code liait « 1 » a « 1 vert + 3 rouges » et
    « 3 » a « 3 verts + 1 rouge », avec une position et un ping deduits du
    numero. C'est FAUX : 1 et 3 sont ambigus sur les couleurs, seul 2 ne l'est
    pas. Une declaration reduite a « 1 » ou « 3 » est donc REFUSEE avec un
    message demandant la couleur dominante (jamais devinee).

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

--- Version du modele d'intermission. 2 = modele par COULEURS (3V1R/2V2R/1V3R),
--- les numeros 1/2/3 n'etant que des indices (1 et 3 ambigus).
Intermission.SCHEMA_VERSION = 2

--- Duree de la fenetre ou les indicateurs des autres joueurs sont visibles (guide).
Intermission.VISIBILITY_SECONDS = 3

--- Duree par defaut de l'intermission si la timeline preparee n'en fournit pas.
Intermission.DEFAULT_DURATION_SECONDS = 20

--- Jeton de cible par defaut de la macro de ping (se ping soi-meme).
Intermission.DEFAULT_TARGET_TOKEN = "player"

--- Trois ETATS canoniques, ordre d'affichage DETERMINISTE (verts croissants,
--- jamais pairs()) : 1V3R, 2V2R, 3V1R.
Intermission.STATES = { "1V3R", "2V2R", "3V1R" }

--- Alias historique : le module parlait de « declarations 1/2/3 ». Ce sont
--- desormais des COMPOSITIONS d'orbes ; l'alias evite de casser les appelants.
Intermission.DECLARATIONS = Intermission.STATES

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

--[[ Les TROIS etats de couleur (aucune lecture d'API en jeu).

     key            : cle courte utilisee partout (3V1R / 2V2R / 1V3R)
     display        : libelle visuel (« 3 VERTS + 1 ROUGE »)
     orbs / greens / reds : composition ; greens et reds sont la SEULE base de
                      la regle de survie (somme 4 verts + 4 rouges = survie)
     numbers        : numero(s) pouvant etre affiche(s) au-dessus de la tete
     numberAmbiguous: true quand le numero ne permet PAS de connaitre la couleur
     dominant       : couleur dominante (celle du ping)
     position       : code de position ; positionLabel : texte affiche
     ping           : valeur de Enum.PingSubjectType (source API 12.1.0)
     pingToken      : jeton utilisable dans une macro /ping (a confirmer)
     pingColor / pingColorHex : couleur du ping, VERIFIEE sur la galerie du wiki
                      https://warcraft.wiki.gg/wiki/Ping_System :
                      Warning = rouge, OnMyWay = bleu, Assist = vert.
                      Convention du guide raidstrats, PAR COULEUR DOMINANTE :
                      3 verts -> Assist (vert), 2-2 -> OnMyWay (bleu),
                      3 rouges -> Warning (rouge).
     action         : consigne operationnelle (ce que le joueur FAIT)
     find           : quel etat peut le rejoindre + le calcul de somme
     complement     : l'etat qui DOIT le rejoindre (4 verts + 4 rouges)
     numberRule     : convention de guilde rappelee pour ce numero
     buttonLabel    : libelle du bouton de declaration (composition, numero en
                      indice). Calcule ICI : la couche UI ne calcule rien.

     POSITIONS : les lignes positionnelles du guide se CONTREDISENT (elles
     donnent a la fois « 1 vert 3 rouges -> gauche » et « 3 rouges 1 vert ->
     droite »). Notre convention est donc EXPLICITE et CONFIGURABLE ici : par
     defaut le point FIXE est l'etat a majorite ROUGE (1V3R, ping ROUGE) et le
     COUREUR est l'etat a majorite VERTE (3V1R, ping VERT), les 2V2R allant au
     milieu. C'est la seule convention coherente avec « la couleur tranche ».
]]
local CONVENTION = {
    ["1V3R"] = {
        key = "1V3R",
        display = "1 VERT + 3 ROUGES",
        orbs = "1 vert + 3 rouges",
        greens = 1,
        reds = 3,
        numbers = { "1", "3" },
        numberText = "1 ou 3",
        numberAmbiguous = true,
        dominant = "ROUGE (3 orbes sur 4)",
        position = "HOLD",
        positionLabel = "SUR PLACE, la ou tu es",
        ping = "Warning",
        pingToken = "Warning",
        pingColor = "ROUGE",
        pingColorHex = "|cffff4040",
        action = "RESTE SUR PLACE et ping ROUGE (Warning) pour etre localise : un joueur en 3V1R vient a toi.",
        find = "Seul un 3V1R peut te rejoindre : 1+3 verts = 4 verts, 3+1 rouges = 4 rouges.",
        complement = "3V1R",
        numberRule = "convention de guilde : '1' = sur place + ping. C'est ta dominante ROUGE qui te fait reconnaitre.",
        buttonLabel = "1 vert + 3 rouges\n1V3R\nnumero : 1 ou 3",
    },
    ["2V2R"] = {
        key = "2V2R",
        display = "2 VERTS + 2 ROUGES",
        orbs = "2 verts + 2 rouges",
        greens = 2,
        reds = 2,
        numbers = { "2" },
        numberText = "2",
        numberAmbiguous = false,
        dominant = "AUCUNE (2-2)",
        position = "MIDDLE",
        positionLabel = "MILIEU / SOUS LE BOSS",
        ping = "OnMyWay",
        pingToken = "OnMyWay",
        pingColor = "BLEU",
        pingColorHex = "|cff40a0ff",
        action = "COURS te placer sous le milieu / sous le boss, puis ping BLEU (OnMyWay).",
        find = "Seul un autre 2V2R peut te rejoindre : 2+2 verts = 4 verts, 2+2 rouges = 4 rouges.",
        complement = "2V2R",
        numberRule = "le '2' est le SEUL numero non ambigu : 2 verts + 2 rouges, toujours.",
        buttonLabel = "2 verts + 2 rouges\n2V2R\nnumero : 2 (non ambigu)",
    },
    ["3V1R"] = {
        key = "3V1R",
        display = "3 VERTS + 1 ROUGE",
        orbs = "3 verts + 1 rouge",
        greens = 3,
        reds = 1,
        numbers = { "1", "3" },
        numberText = "1 ou 3",
        numberAmbiguous = true,
        dominant = "VERT (3 orbes sur 4)",
        position = "PURSUE",
        positionLabel = "VA TE COLLER A UN ETAT 1V3R (3 ROUGES)",
        ping = "Assist",
        pingToken = "Assist",
        pingColor = "VERT",
        pingColorHex = "|cff40ff40",
        action = "FONCE sur un joueur en 1V3R (3 ROUGES) : il reste sur place et t'attend.",
        find = "Seul un 1V3R peut te rejoindre : 3+1 verts = 4 verts, 1+3 rouges = 4 rouges.",
        complement = "1V3R",
        numberRule = "convention de guilde : '3' = tu rejoins un '1' de couleur complementaire. Tes 3 verts disent LAQUELLE.",
        buttonLabel = "3 verts + 1 rouge\n3V1R\nnumero : 1 ou 3",
    },
}

-- La table est exposee en lecture (UI : couleurs, libelles) mais jamais renvoyee
-- directement : getDeclaration() renvoie une copie.
Intermission.CONVENTION = CONVENTION

local D_PROMPT = "Regarde la COULEUR de tes 4 orbes au-dessus de ta tete, puis clique la composition que tu vois."
local D_AMBIGUITY = "1 ou 3 NE SUFFIT PAS : le numero ne dit pas la couleur. Seul le numero 2 est non ambigu (2 verts + 2 rouges)."
local D_CAVEAT = "INCONNU : personne ne peut lire ton numero ni te dire qui a declare quoi."
local D_CHANNEL = "Le seul signal visible par les autres joueurs : TON ping."

--- Correspondance compter-de-verts -> etat canonique (aucun etat a 0 ou 4 verts).
local GREENS_TO_STATE = { [1] = "1V3R", [2] = "2V2R", [3] = "3V1R" }

--- Formes symboliques collees : « 3v1r », « 3 v 1 r » (une fois les espaces retires).
local STATE_BY_SYMBOLS = { ["3v1r"] = "3V1R", ["2v2r"] = "2V2R", ["1v3r"] = "1V3R" }

--- Numeros SEULS qui sont ambigus sur la couleur : refus explicite, jamais devine.
local AMBIGUOUS_NUMBERS = { ["1"] = true, ["3"] = true }

--- Mots acceptes pour chaque couleur (forme « v » / « r » comprise).
local GREEN_WORDS = {
    ["vert"] = true,
    ["verts"] = true,
    ["verte"] = true,
    ["vertes"] = true,
    ["green"] = true,
    ["greens"] = true,
    ["v"] = true,
}
local RED_WORDS = {
    ["rouge"] = true,
    ["rouges"] = true,
    ["red"] = true,
    ["reds"] = true,
    ["r"] = true,
}

--- Remplacements UTF-8 -> ASCII, liste TRIEE (aucun pairs(), determinisme).
--- Permet de taper « majorité verte » sans accents : la saisie reste toleree.
local ACCENT_MAP = {
    { "\195\168", "e" },
    { "\195\169", "e" },
    { "\195\170", "e" },
    { "\195\167", "c" },
    { "\195\174", "i" },
    { "\195\180", "o" },
    { "\195\185", "u" },
    { "\195\187", "u" },
    { "\195\160", "a" },
    { "\195\162", "a" },
}

local function deaccent(text)
    local out = text
    for index = 1, #ACCENT_MAP do
        out = out:gsub(ACCENT_MAP[index][1], ACCENT_MAP[index][2])
    end
    return out
end

local function flatten(raw)
    local text = deaccent(tostring(raw)):lower()
    -- espaces insecables + tous les separateurs usuels -> espace simple
    text = text:gsub("[\194\160]", " ")
    text = text:gsub("[%-_+/,;:%.]+", " ")
    text = text:gsub("%s+", " ")
    return text:gsub("^%s*(.-)%s*$", "%1")
end

local function ambiguousMessage(number)
    return "numero "
        .. number
        .. " ambigu : le numero affiche ne dit PAS la couleur des orbes. "
        .. "Dis ce que tu VOIS : 3 verts (etat 3V1R) ou 1 vert (etat 1V3R). "
        .. "Seul le numero 2 est non ambigu (2V2R)."
end

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
    local numbers = {}
    for index = 1, #rec.numbers do
        numbers[#numbers + 1] = rec.numbers[index]
    end
    return {
        key = rec.key,
        display = rec.display,
        orbs = rec.orbs,
        greens = rec.greens,
        reds = rec.reds,
        numbers = numbers,
        numberText = rec.numberText,
        numberAmbiguous = rec.numberAmbiguous,
        dominant = rec.dominant,
        position = rec.position,
        positionLabel = rec.positionLabel,
        ping = rec.ping,
        pingToken = rec.pingToken,
        pingColor = rec.pingColor,
        pingColorHex = rec.pingColorHex,
        action = rec.action,
        find = rec.find,
        complement = rec.complement,
        numberRule = rec.numberRule,
        buttonLabel = rec.buttonLabel,
    }
end

--- « vvvr » / « vvrr » / « vrrr » : 4 lettres de couleur, on compte les verts.
local function stateFromLetters(compact)
    if #compact ~= 4 or compact:match("^[vr]+$") == nil then
        return nil
    end
    local greens = 0
    for index = 1, 4 do
        if compact:sub(index, index) == "v" then
            greens = greens + 1
        end
    end
    return GREENS_TO_STATE[greens]
end

--- Compte les couleurs citees en texte : « 3 verts + 1 rouge », « vert-vert-vert-rouge ».
--- `explicit` compte les couleurs precedees d'un nombre ; `words` le nombre total
--- de mots de couleur (sert a distinguer « vert » seul = couleur dominante de
--- « vert vert vert rouge » = 3 verts + 1 rouge).
local function analyzeColors(flat)
    local greens, reds, explicit, words = 0, 0, 0, 0
    local hasGreenWord, hasRedWord = false, false
    for number, word in flat:gmatch("(%d*)%s*([a-z]+)") do
        local isGreen = GREEN_WORDS[word] ~= nil
        local isRed = RED_WORDS[word] ~= nil
        if isGreen or isRed then
            local count = tonumber(number)
            if count == nil then
                count = 1
            else
                explicit = explicit + 1
            end
            words = words + 1
            if isGreen then
                greens = greens + count
                hasGreenWord = true
            else
                reds = reds + count
                hasRedWord = true
            end
        end
    end
    return {
        greens = greens,
        reds = reds,
        explicit = explicit,
        words = words,
        hasGreenWord = hasGreenWord,
        hasRedWord = hasRedWord,
    }
end

--- Normalise la saisie du joueur en cle d'etat : « 3V1R » | « 2V2R » | « 1V3R ».
---
--- Formes acceptees (tolerantes : casse, espaces, accents, separateurs) :
---   composition courte : « 3V1R », « 2V2R », « 1V3R » (y compris « 3 v 1 r ») ;
---   lettres            : « vvvr », « vvrr », « vrrr », « vert-vert-vert-rouge » ;
---   texte              : « 3 verts + 1 rouge », « 3 verts », « 1 vert 3 rouges » ;
---   couleur dominante  : « vert » (= 3V1R), « rouge » (= 1V3R) ;
---   numero seul        : « 2 » (= 2V2R, NON ambigu).
---
--- REFUS EXPLICITE : « 1 » et « 3 » SEULS sont AMBIGUS (le numero ne dit pas la
--- couleur) -> (nil, message demandant la couleur dominante,
--- { ambiguous = true, number = ... }). Le code ne devine JAMAIS la couleur.
--- @return string|nil key, string|nil erreur, table|nil info
function Intermission.normalizeDeclaration(raw)
    if type(raw) == "number" then
        raw = tostring(raw)
    end
    if type(raw) ~= "string" then
        return nil, "declaration invalide (attendu une composition : 3V1R, 2V2R ou 1V3R)"
    end
    local flat = flatten(raw)
    local compact = flat:gsub("%s+", "")
    if compact == "" then
        return nil, "declaration vide (attendu une composition : 3V1R, 2V2R ou 1V3R)"
    end
    if compact == "2" then
        return "2V2R"
    end
    if AMBIGUOUS_NUMBERS[compact] then
        return nil, ambiguousMessage(compact), { ambiguous = true, number = compact }
    end
    local bySymbol = STATE_BY_SYMBOLS[compact]
    if bySymbol ~= nil then
        return bySymbol
    end
    local byLetters = stateFromLetters(compact)
    if byLetters ~= nil then
        return byLetters
    end

    local colors = analyzeColors(flat)
    -- Un SEUL mot de couleur sans nombre = la couleur dominante annoncee :
    -- « vert » -> 3 verts, « rouge » -> 3 rouges (les seules compositions a
    -- dominante sont 3-1).
    if colors.words == 1 and colors.explicit == 0 then
        if colors.hasGreenWord then
            return "3V1R"
        end
        return "1V3R"
    end
    local total = colors.greens + colors.reds
    if total == 4 and colors.reds == 4 - colors.greens and GREENS_TO_STATE[colors.greens] ~= nil then
        return GREENS_TO_STATE[colors.greens]
    end
    if total > 0 and colors.reds == 0 and GREENS_TO_STATE[colors.greens] ~= nil then
        -- un seul compte donne : le reste se deduit (4 orbes au total)
        return GREENS_TO_STATE[colors.greens]
    end
    if total > 0 then
        return nil,
            "composition non exploitable (" .. colors.greens .. " verts + " .. colors.reds .. " rouges) : dis la couleur dominante",
            { ambiguous = true }
    end
    return nil, "declaration inconnue : " .. raw .. " (attendu 3V1R, 2V2R ou 1V3R)", { ambiguous = false }
end

--- Retourne (copie de l'etat canonique, nil) ou (nil, erreur, info).
--- L'info porte { ambiguous = true } quand la saisie ne permettait PAS de
--- connaitre la couleur : l'appelant doit alors DEMANDER la couleur dominante.
function Intermission.getDeclaration(raw)
    local key, err, info = Intermission.normalizeDeclaration(raw)
    if key == nil then
        return nil, err, info
    end
    return copyRecord(CONVENTION[key])
end

--- L'etat qui DOIT rejoindre `raw` pour faire 4 verts + 4 rouges.
--- @return string|nil key, string|nil erreur
function Intermission.complementOf(raw)
    local rec, err = Intermission.getDeclaration(raw)
    if rec == nil then
        return nil, err
    end
    return rec.complement
end

--- Verifie si deux declarations peuvent se rejoindre SANS MOURIR.
--- Regle (ADDITION de couleurs) : la somme doit faire 4 VERTS et 4 ROUGES.
---   3V1R + 1V3R = 4V4R : sur ;
---   2V2R + 2V2R = 4V4R : sur ;
---   3V1R + 2V2R = 5 verts = « 5g » : mort ;
---   1V3R + 1V3R = 2 verts + 6 rouges : mort.
--- @return table|nil result { ok, label, greens, reds, reason, required }, string|nil erreur
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
    local reds = a.reds + b.reds
    local label = a.key .. "+" .. b.key
    local ok = (greens == 4 and reds == 4)
    local reason
    if ok then
        reason = "combinaison sure (" .. greens .. " verts + " .. reds .. " rouges)"
    elseif greens == 5 then
        reason = "5 verts = 5g : MORT"
    else
        reason = "combinaison interdite (" .. greens .. " verts + " .. reds .. " rouges) : il faut 4 verts ET 4 rouges"
    end
    return { ok = ok, label = label, greens = greens, reds = reds, reason = reason, required = a.complement }
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

--- Enregistre la declaration du joueur : la COMPOSITION d'orbes qu'il voit
--- (« 3V1R », « 2V2R », « 1V3R », ou une forme toleree comme « 3 verts »).
--- Un numero seul « 1 » ou « 3 » est REFUSE (ambigu) : voir normalizeDeclaration.
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
        ambiguity = D_AMBIGUITY,
    }

    local lines = snap.lines
    if phase == PHASE_IDLE then
        snap.headline = "INTERMISSION : PAS LANCEE"
        lines[#lines + 1] = "Timeline pre-calculee : " .. timeline.visibilitySeconds .. " s visibles puis salle obscurcie."
        lines[#lines + 1] = "Declenchement : debut de combat sur le boss, ou touche/bouton."
        lines[#lines + 1] = D_PROMPT
        lines[#lines + 1] = D_AMBIGUITY
        return snap
    end

    if phase == PHASE_VISIBLE then
        local left = Intermission.remainingVisibility({ timeline = timeline, elapsed = elapsed })
        snap.countdownText = tostring(left)
        snap.headline = "REGARDE LA COULEUR DES ORBES AU-DESSUS DES TETES : " .. left .. " s"
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
        lines[#lines + 1] = "TU VOIS : " .. rec.display .. "  (" .. rec.key .. ")"
        lines[#lines + 1] = "NUMERO AU-DESSUS DE TA TETE : "
            .. rec.numberText
            .. (rec.numberAmbiguous and "  -> il ne dit PAS la couleur" or "  -> non ambigu")
        lines[#lines + 1] = "FAIS : " .. rec.action
        lines[#lines + 1] = "POSITION : " .. rec.positionLabel
        lines[#lines + 1] = "ETAT A REJOINDRE : " .. rec.complement .. " - " .. rec.find
        lines[#lines + 1] = "PING A ENVOYER : " .. rec.pingColor .. " (" .. rec.ping .. ")"
        lines[#lines + 1] = "CONVENTION DE GUILDE : " .. rec.numberRule
        local macro = Intermission.buildMacro(rec.key, nil)
        if macro ~= nil then
            snap.macroPrimary = macro.primary
            snap.macroFallback = macro.fallback
            snap.macroNote = macro.note
        end
    end
    lines[#lines + 1] = D_AMBIGUITY
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

     `role` peut contenir la COMPOSITION d'orbes preparee (« 3V1R », « 2V2R »,
     « 1V3R », ou encore « 3 verts ») ou un role de raid libre (« Tank »,
     « Heal »). Un numero seul « 1 » ou « 3 » est AMBIGU : il est signale comme
     tel, jamais devine. Rien n'est invente : si GIDEON ne l'ecrit pas, l'addon
     ne l'affiche pas.
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
            local meeting, meetingErr = Intermission.checkMeeting(out.me.role, plan.byName[partner].role)
            if meeting ~= nil then
                out.meeting = meeting
                if meeting.ok then
                    lines[#lines + 1] = "Rencontre " .. meeting.label .. " : OK (" .. meeting.reason .. ")"
                else
                    lines[#lines + 1] = "|cffff5555Rencontre " .. meeting.label .. " : MORT (" .. meeting.reason .. ")|r"
                end
            else
                -- Un role prepare « 1 » ou « 3 » seul est AMBIGU : on le dit, on ne devine pas.
                lines[#lines + 1] = "|cffff8080Rencontre non verifiable : " .. tostring(meetingErr) .. "|r"
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
