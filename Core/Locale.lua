--[[--------------------------------------------------------------------------
    GideonRaid / Core / Locale.lua

    PURE LOGIC (Lua 5.1). No WoW API, no event, no client clock: this file runs
    as-is under busted and under lua5.1 outside the client.

    In-game text is BILINGUAL. English is the official/default language; French
    is served automatically on a frFR client (see Locale.resolve). Every string
    displayed in game comes from Locale.STRINGS through Locale.t/Locale.format:
    no in-game literal is hard-coded in the modules any more.

    The DETECTION of the client language is NOT done here: Core/ never calls an
    API. The wiring layer (GideonRaid.lua) calls GetLocale
    (https://warcraft.wiki.gg/wiki/API:GetLocale) and hands the raw value to
    Locale.resolve.

    Spell, orb and color NAMES (3V1R, Warning, OnMyWay, Assist) are identical in
    both languages and are therefore not translated.
----------------------------------------------------------------------------]]
local _, ns = ...

---@class Locale
local Locale = {}
ns.Locale = Locale

--- Official default language: used when nothing else can be decided.
Locale.DEFAULT = "en"

--- Accepted values of the persisted preference (GideonRaidDB.locale).
Locale.AUTO = "auto"
Locale.PREFERENCES = { "auto", "en", "fr" }

--- Languages served by this addon. SORTED: no pairs() anywhere (determinism).
Locale.LANGUAGES = { "en", "fr" }

--- STRINGS[key] = { en = "...", fr = "..." }.
--- Keys are stable identifiers; a key that is missing never raises (Locale.t
--- returns the key itself). "%s" / "%d" placeholders are meant for
--- Locale.format. Text is ASCII only (the client font handles accents badly in
--- the default game font).
Locale.STRINGS = {
    -- ---------------------------------------------------------------- commands
    ["cmd.reset"] = {
        en = "Configuration reset.",
        fr = "Configuration reinitialisee.",
    },
    ["cmd.help"] = {
        en = "Commands: /gr | /gr plan | /gr status | /gr reset | /gr lang [auto|en|fr]\n"
            .. "  /gr inter [start|stop|on|off|status|macro|3V1R|2V2R|1V3R]",
        fr = "Commandes : /gr | /gr plan | /gr status | /gr reset | /gr lang [auto|en|fr]\n"
            .. "  /gr inter [start|stop|on|off|status|macro|3V1R|2V2R|1V3R]",
    },
    ["cmd.lang.status"] = {
        en = "Language: client detected = %s, effective = %s, preference = %s (/gr lang auto|en|fr to change).",
        fr = "Langue : client detecte = %s, effective = %s, preference = %s (/gr lang auto|en|fr pour changer).",
    },
    ["cmd.lang.updated"] = {
        en = "Language preference = %s, effective language = %s.",
        fr = "Preference de langue = %s, langue effective = %s.",
    },
    ["cmd.lang.unknown"] = {
        en = "Unknown language '%s': accepted values are auto, en, fr.",
        fr = "Langue inconnue '%s' : valeurs acceptees auto, en, fr.",
    },
    ["cmd.lang.undetected"] = {
        en = "unknown (GetLocale unavailable)",
        fr = "inconnue (GetLocale indisponible)",
    },

    -- ------------------------------------------------------------- main panel
    ["panel.noAssignment"] = {
        en = "No GIDEON assignment.",
        fr = "Aucune assignation GIDEON.",
    },
    ["panel.askGideon"] = {
        en = "Ask GIDEON:",
        fr = "Demande a GIDEON :",
    },
    ["panel.unreadablePlan"] = {
        en = "|cffff5555Unreadable plan|r",
        fr = "|cffff5555Plan illisible|r",
    },
    ["status.noAssignment"] = {
        en = "no assignment (%s)",
        fr = "pas d'assignation (%s)",
    },
    ["status.ok"] = {
        en = "assignment OK, %d pairs",
        fr = "assignation OK, %d paires",
    },

    -- -------------------------------------------------- intermission UI chrome
    ["ui.panelTitle"] = {
        en = "GideonRaid - Intermission Coach",
        fr = "GideonRaid - Intermission Coach",
    },
    ["ui.macroLabel"] = {
        en = "Ping macro (click = select all, then Ctrl+C):",
        fr = "Macro de ping (clic = tout selectionner, puis Ctrl+C) :",
    },
    ["ui.close"] = {
        en = "Close",
        fr = "Fermer",
    },
    ["ui.macroFallback"] = {
        en = "Fallback: %s - %s",
        fr = "Secours : %s - %s",
    },
    ["ui.macroPrompt"] = {
        en = "Click the COMPOSITION you see (3 green + 1 red, 2-2, 1 green + 3 red): the macro appears here.",
        fr = "Clique la COMPOSITION que tu vois (3 verts + 1 rouge, 2-2, 1 vert + 3 rouges) : la macro apparait ici.",
    },
    ["ui.disabled"] = {
        en = "Intermission Coach disabled (/gr inter on to enable it).",
        fr = "Intermission Coach desactive (/gr inter on pour l'activer).",
    },
    ["ui.started"] = {
        en = "Intermission started: %d s of visibility, then the room goes dark.",
        fr = "Intermission lancee : %d s de visibilite, puis salle obscurcie.",
    },
    ["ui.declarationRefused"] = {
        en = "Declaration refused: %s",
        fr = "Declaration refusee : %s",
    },
    ["ui.noSavedVariables"] = {
        en = "SavedVariables not initialized.",
        fr = "SavedVariables non initialisees.",
    },
    ["ui.enabled"] = {
        en = "Intermission Coach enabled.",
        fr = "Intermission Coach active.",
    },
    ["ui.disabledState"] = {
        en = "Intermission Coach disabled.",
        fr = "Intermission Coach desactive.",
    },
    ["ui.wordEnabled"] = {
        en = "enabled",
        fr = "active",
    },
    ["ui.wordDisabled"] = {
        en = "disabled",
        fr = "desactive",
    },
    ["ui.statusLine"] = {
        en = "intermission: %s, phase %s, declaration %s",
        fr = "intermission : %s, phase %s, declaration %s",
    },
    ["ui.timelineLine"] = {
        en = "timeline: %d s visible, %d s in total, scale %.2f",
        fr = "timeline : %d s visibles, %d s au total, echelle %.2f",
    },
    ["ui.noMacro"] = {
        en = "No macro: declare your composition first (/gr inter 3V1R).",
        fr = "Aucune macro : declare d'abord ta composition (/gr inter 3V1R).",
    },
    ["ui.macroToPaste"] = {
        en = "macro to paste: %s",
        fr = "macro a coller : %s",
    },
    ["ui.macroFallbackLine"] = {
        en = "fallback: %s (%s)",
        fr = "secours : %s (%s)",
    },
    ["ui.intermissionError"] = {
        en = "Intermission: %s",
        fr = "Intermission : %s",
    },
    ["ui.unreadablePlan"] = {
        en = "unreadable plan (%s)",
        fr = "plan illisible (%s)",
    },

    -- ------------------------------------------- intermission headlines/lines
    ["inter.headline.idle"] = {
        en = "INTERMISSION: NOT STARTED",
        fr = "INTERMISSION : PAS LANCEE",
    },
    ["inter.line.idleTimeline"] = {
        en = "Pre-computed timeline: %d s visible, then the room goes dark.",
        fr = "Timeline pre-calculee : %d s visibles puis salle obscurcie.",
    },
    ["inter.line.idleTrigger"] = {
        en = "Trigger: combat start on the boss, or key/button.",
        fr = "Declenchement : debut de combat sur le boss, ou touche/bouton.",
    },
    ["inter.headline.visible"] = {
        en = "LOOK AT THE ORB COLOR ABOVE THE HEADS: %d s",
        fr = "REGARDE LA COULEUR DES ORBES AU-DESSUS DES TETES : %d s",
    },
    ["inter.line.visibleIndicators"] = {
        en = "The indicators of the other players are still visible.",
        fr = "Les indicateurs des autres joueurs sont encore visibles.",
    },
    ["inter.headline.dark"] = {
        en = "ROOM DARKENED: YOU ONLY SEE YOURSELF",
        fr = "SALLE OBSCURCIE : TU NE VOIS PLUS QUE TOI",
    },
    ["inter.line.darkIndicators"] = {
        en = "The indicators of the other players are invisible.",
        fr = "Les indicateurs des autres joueurs sont invisibles.",
    },
    ["inter.headline.done"] = {
        en = "INTERMISSION OVER",
        fr = "INTERMISSION TERMINEE",
    },
    ["inter.line.youSee"] = {
        en = "YOU SEE: %s  (%s)",
        fr = "TU VOIS : %s  (%s)",
    },
    ["inter.line.number"] = {
        en = "NUMBER ABOVE YOUR HEAD: %s%s",
        fr = "NUMERO AU-DESSUS DE TA TETE : %s%s",
    },
    ["inter.suffix.ambiguous"] = {
        en = "  -> it does NOT reveal the color",
        fr = "  -> il ne dit PAS la couleur",
    },
    ["inter.suffix.unambiguous"] = {
        en = "  -> unambiguous",
        fr = "  -> non ambigu",
    },
    ["inter.line.action"] = {
        en = "DO: %s",
        fr = "FAIS : %s",
    },
    ["inter.line.position"] = {
        en = "POSITION: %s",
        fr = "POSITION : %s",
    },
    ["inter.line.join"] = {
        en = "STATE TO JOIN: %s - %s",
        fr = "ETAT A REJOINDRE : %s - %s",
    },
    ["inter.line.ping"] = {
        en = "PING TO SEND: %s (%s)",
        fr = "PING A ENVOYER : %s (%s)",
    },
    ["inter.line.guildRule"] = {
        en = "GUILD CONVENTION: %s",
        fr = "CONVENTION DE GUILDE : %s",
    },
    ["inter.prompt"] = {
        en = "Look at the COLOR of your 4 orbs above your head, then click the composition you see.",
        fr = "Regarde la COULEUR de tes 4 orbes au-dessus de ta tete, puis clique la composition que tu vois.",
    },
    ["inter.ambiguity"] = {
        en = "1 or 3 IS NOT ENOUGH: the number does not reveal the color. Only number 2 is unambiguous (2 green + 2 red).",
        fr = "1 ou 3 NE SUFFIT PAS : le numero ne dit pas la couleur. Seul le numero 2 est non ambigu (2 verts + 2 rouges).",
    },
    ["inter.caveat"] = {
        en = "UNKNOWN: nobody can read your number or tell you who declared what.",
        fr = "INCONNU : personne ne peut lire ton numero ni te dire qui a declare quoi.",
    },
    ["inter.channel"] = {
        en = "The only signal visible to the other players: YOUR ping.",
        fr = "Le seul signal visible par les autres joueurs : TON ping.",
    },

    -- ------------------------------------------------------- color state texts
    ["state.display.1V3R"] = {
        en = "1 GREEN + 3 RED",
        fr = "1 VERT + 3 ROUGES",
    },
    ["state.orbs.1V3R"] = {
        en = "1 green + 3 red",
        fr = "1 vert + 3 rouges",
    },
    ["state.dominant.1V3R"] = {
        en = "RED (3 orbs out of 4)",
        fr = "ROUGE (3 orbes sur 4)",
    },
    ["state.positionLabel.1V3R"] = {
        en = "HOLD, where you are",
        fr = "SUR PLACE, la ou tu es",
    },
    ["state.action.1V3R"] = {
        en = "STAY WHERE YOU ARE and ping RED (Warning) to be located: a 3V1R player comes to you.",
        fr = "RESTE SUR PLACE et ping ROUGE (Warning) pour etre localise : un joueur en 3V1R vient a toi.",
    },
    ["state.find.1V3R"] = {
        en = "Only a 3V1R can join you: 1+3 green = 4 green, 3+1 red = 4 red.",
        fr = "Seul un 3V1R peut te rejoindre : 1+3 verts = 4 verts, 3+1 rouges = 4 rouges.",
    },
    ["state.numberRule.1V3R"] = {
        en = "guild convention: '1' = stay in place + ping. Your RED majority is what gets you recognized.",
        fr = "convention de guilde : '1' = sur place + ping. C'est ta dominante ROUGE qui te fait reconnaitre.",
    },
    ["state.buttonLabel.1V3R"] = {
        en = "1 green + 3 red\n1V3R\nnumber: 1 or 3",
        fr = "1 vert + 3 rouges\n1V3R\nnumero : 1 ou 3",
    },
    ["state.pingColor.1V3R"] = {
        en = "RED",
        fr = "ROUGE",
    },
    ["state.numberText.1V3R"] = {
        en = "1 or 3",
        fr = "1 ou 3",
    },
    ["state.display.2V2R"] = {
        en = "2 GREEN + 2 RED",
        fr = "2 VERTS + 2 ROUGES",
    },
    ["state.orbs.2V2R"] = {
        en = "2 green + 2 red",
        fr = "2 verts + 2 rouges",
    },
    ["state.dominant.2V2R"] = {
        en = "NONE (2-2)",
        fr = "AUCUNE (2-2)",
    },
    ["state.positionLabel.2V2R"] = {
        en = "MIDDLE / UNDER THE BOSS",
        fr = "MILIEU / SOUS LE BOSS",
    },
    ["state.action.2V2R"] = {
        en = "RUN to the middle / under the boss, then ping BLUE (OnMyWay).",
        fr = "COURS te placer sous le milieu / sous le boss, puis ping BLEU (OnMyWay).",
    },
    ["state.find.2V2R"] = {
        en = "Only another 2V2R can join you: 2+2 green = 4 green, 2+2 red = 4 red.",
        fr = "Seul un autre 2V2R peut te rejoindre : 2+2 verts = 4 verts, 2+2 rouges = 4 rouges.",
    },
    ["state.numberRule.2V2R"] = {
        en = "the '2' is the ONLY unambiguous number: 2 green + 2 red, always.",
        fr = "le '2' est le SEUL numero non ambigu : 2 verts + 2 rouges, toujours.",
    },
    ["state.buttonLabel.2V2R"] = {
        en = "2 green + 2 red\n2V2R\nnumber: 2 (unambiguous)",
        fr = "2 verts + 2 rouges\n2V2R\nnumero : 2 (non ambigu)",
    },
    ["state.pingColor.2V2R"] = {
        en = "BLUE",
        fr = "BLEU",
    },
    ["state.numberText.2V2R"] = {
        en = "2",
        fr = "2",
    },
    ["state.display.3V1R"] = {
        en = "3 GREEN + 1 RED",
        fr = "3 VERTS + 1 ROUGE",
    },
    ["state.orbs.3V1R"] = {
        en = "3 green + 1 red",
        fr = "3 verts + 1 rouge",
    },
    ["state.dominant.3V1R"] = {
        en = "GREEN (3 orbs out of 4)",
        fr = "VERT (3 orbes sur 4)",
    },
    ["state.positionLabel.3V1R"] = {
        en = "GO AND STICK TO A 1V3R STATE (3 RED)",
        fr = "VA TE COLLER A UN ETAT 1V3R (3 ROUGES)",
    },
    ["state.action.3V1R"] = {
        en = "DASH to a 1V3R player (3 RED): they stay where they are and wait for you.",
        fr = "FONCE sur un joueur en 1V3R (3 ROUGES) : il reste sur place et t'attend.",
    },
    ["state.find.3V1R"] = {
        en = "Only a 1V3R can join you: 3+1 green = 4 green, 1+3 red = 4 red.",
        fr = "Seul un 1V3R peut te rejoindre : 3+1 verts = 4 verts, 1+3 rouges = 4 rouges.",
    },
    ["state.numberRule.3V1R"] = {
        en = "guild convention: '3' = you join a '1' with the complementary color. Your 3 green say WHICH one.",
        fr = "convention de guilde : '3' = tu rejoins un '1' de couleur complementaire. Tes 3 verts disent LAQUELLE.",
    },
    ["state.buttonLabel.3V1R"] = {
        en = "3 green + 1 red\n3V1R\nnumber: 1 or 3",
        fr = "3 verts + 1 rouge\n3V1R\nnumero : 1 ou 3",
    },
    ["state.pingColor.3V1R"] = {
        en = "GREEN",
        fr = "VERT",
    },
    ["state.numberText.3V1R"] = {
        en = "1 or 3",
        fr = "1 ou 3",
    },

    -- ------------------------------------------------------------- meetings
    ["meeting.safe"] = {
        en = "safe combination (%d green + %d red)",
        fr = "combinaison sure (%d verts + %d rouges)",
    },
    ["meeting.fiveGreen"] = {
        en = "5 green = 5g: DEAD",
        fr = "5 verts = 5g : MORT",
    },
    ["meeting.forbidden"] = {
        en = "forbidden combination (%d green + %d red): you need 4 green AND 4 red",
        fr = "combinaison interdite (%d verts + %d rouges) : il faut 4 verts ET 4 rouges",
    },
    ["meeting.labelOk"] = {
        en = "Meeting %s: OK (%s)",
        fr = "Rencontre %s : OK (%s)",
    },
    ["meeting.labelDead"] = {
        en = "|cffff5555Meeting %s: DEAD (%s)|r",
        fr = "|cffff5555Rencontre %s : MORT (%s)|r",
    },
    ["meeting.unverifiable"] = {
        en = "|cffff8080Meeting cannot be verified: %s|r",
        fr = "|cffff8080Rencontre non verifiable : %s|r",
    },

    -- ------------------------------------------------------------- macro
    ["macro.note"] = {
        en = "Syntax to be confirmed in game (see docs/INTERMISSION-COACH.md).",
        fr = "Syntaxe a confirmer en jeu (voir docs/INTERMISSION-COACH.md).",
    },

    -- ------------------------------------------------------------- pre-pull view
    ["plan.notPaired"] = {
        en = "You are not in the GIDEON pairing.",
        fr = "Tu n'es pas dans l'appariement GIDEON.",
    },
    ["plan.partner"] = {
        en = "Your partner: %s",
        fr = "Ton partenaire : %s",
    },
    ["plan.yourRole"] = {
        en = "Your role (prepared out of game): %s",
        fr = "Ton role (prepare hors jeu) : %s",
    },
    ["plan.yourPosition"] = {
        en = "Your position (prepared out of game): %s",
        fr = "Ta position (preparee hors jeu) : %s",
    },
    ["plan.roleWord"] = {
        en = "role %s",
        fr = "role %s",
    },
    ["plan.positionWord"] = {
        en = "position %s",
        fr = "position %s",
    },
    ["plan.playerInfo"] = {
        en = "%s: %s",
        fr = "%s : %s",
    },
    ["plan.pairsHeader"] = {
        en = "Pairs (%d):",
        fr = "Paires (%d) :",
    },
    ["plan.errorsLine"] = {
        en = "|cffff8080Plan: %d ignored entry(ies).|r",
        fr = "|cffff8080Plan : %d entree(s) ignoree(s).|r",
    },
    ["plan.disclaimer"] = {
        en = "Plan prepared out of game: no aura read, no combat log.",
        fr = "Plan prepare hors jeu : aucune aura lue, aucun journal de combat.",
    },

    -- --------------------------------------------------------------- errors
    ["err.declarationInvalid"] = {
        en = "invalid declaration (expected a composition: 3V1R, 2V2R or 1V3R)",
        fr = "declaration invalide (attendu une composition : 3V1R, 2V2R ou 1V3R)",
    },
    ["err.declarationEmpty"] = {
        en = "empty declaration (expected a composition: 3V1R, 2V2R or 1V3R)",
        fr = "declaration vide (attendu une composition : 3V1R, 2V2R ou 1V3R)",
    },
    ["err.numberAmbiguous"] = {
        en = "number %s is ambiguous: the displayed number does NOT reveal the orb color. "
            .. "Say what you SEE: 3 green (state 3V1R) or 1 green (state 1V3R). "
            .. "Only number 2 is unambiguous (2V2R).",
        fr = "numero %s ambigu : le numero affiche ne dit PAS la couleur des orbes. "
            .. "Dis ce que tu VOIS : 3 verts (etat 3V1R) ou 1 vert (etat 1V3R). "
            .. "Seul le numero 2 est non ambigu (2V2R).",
    },
    ["err.compositionUnusable"] = {
        en = "composition not usable (%d green + %d red): state the dominant color",
        fr = "composition non exploitable (%d verts + %d rouges) : dis la couleur dominante",
    },
    ["err.declarationUnknown"] = {
        en = "unknown declaration: %s (expected 3V1R, 2V2R or 1V3R)",
        fr = "declaration inconnue : %s (attendu 3V1R, 2V2R ou 1V3R)",
    },
    ["err.invalidState"] = {
        en = "invalid state",
        fr = "etat invalide",
    },
    ["err.notStarted"] = {
        en = "intermission not started",
        fr = "intermission non demarree",
    },
    ["err.finished"] = {
        en = "intermission over",
        fr = "intermission terminee",
    },
    ["err.invalidTimeline"] = {
        en = "invalid timeline (table expected)",
        fr = "timeline invalide (table attendue)",
    },
    ["err.invalidAssignment"] = {
        en = "invalid assignment",
        fr = "assignment invalide",
    },
    ["err.invalidPlayerName"] = {
        en = "invalid player name",
        fr = "nom de joueur invalide",
    },
    ["err.planInvalid"] = {
        en = "invalid plan (table expected)",
        fr = "plan invalide (table attendue)",
    },
    ["err.planEntryNoName"] = {
        en = "plan #%s ignored (missing name)",
        fr = "plan #%s ignore (name manquant)",
    },
    ["err.planEntryDuplicate"] = {
        en = "plan #%s ignored (duplicate name: %s)",
        fr = "plan #%s ignore (nom en double : %s)",
    },
}

--- Language currently served by Locale.t when no language is passed explicitly.
--- Set by the wiring layer through Locale.setActive (pure assignment, no API).
Locale.ACTIVE = Locale.DEFAULT

--- Reduces a client locale code ("frFR", "enUS", "deDE") to a served language.
--- Pure and total: anything unknown (nil, a number, "deDE") returns nil, and the
--- caller decides the fallback.
--- @param code string|nil raw value coming from GetLocale() (wiring layer)
--- @return string|nil "en", "fr" or nil
local function normalizeLanguage(code)
    if type(code) ~= "string" or code == "" then
        return nil
    end
    local lower = code:lower()
    for index = 1, #Locale.LANGUAGES do
        local lang = Locale.LANGUAGES[index]
        if lower:sub(1, #lang) == lang then
            return lang
        end
    end
    return nil
end

Locale.normalizeLanguage = normalizeLanguage

--- Pure resolution of the language to serve.
---   requested == "fr"          -> "fr"
---   requested == "en"          -> "en"
---   requested == "auto" or nil -> "fr" if `detected` starts with "fr", else "en"
---   anything else (unknown)    -> "en" (Locale.DEFAULT)
--- @param requested string|nil persisted preference (GideonRaidDB.locale)
--- @param detected string|nil raw GetLocale() value provided by the wiring layer
--- @return string "en" or "fr"
function Locale.resolve(requested, detected)
    if requested == "fr" then
        return "fr"
    end
    if requested == "en" then
        return "en"
    end
    if requested == nil or requested == Locale.AUTO then
        if normalizeLanguage(detected) == "fr" then
            return "fr"
        end
        return "en"
    end
    -- Unknown preference (hand-edited SavedVariables, typo): safe default.
    return Locale.DEFAULT
end

--- Sets the language served by Locale.t. Unknown values fall back to "en".
--- Pure: a simple assignment, callable from Core/ and from tests.
--- @param lang string|nil
--- @return string the effective language
function Locale.setActive(lang)
    local resolved = normalizeLanguage(lang)
    if resolved == nil then
        resolved = Locale.DEFAULT
    end
    Locale.ACTIVE = resolved
    return resolved
end

--- @return string the language currently served
function Locale.getActive()
    return Locale.ACTIVE
end

--- Translates a key. NEVER raises:
---   1. the requested language, if the key has it;
---   2. otherwise the other language (a key available in one language only is
---      still served);
---   3. otherwise the key itself.
--- @param key string stable key of Locale.STRINGS
--- @param lang string|nil "en" / "fr" / "frFR"; nil uses Locale.ACTIVE
--- @return string
function Locale.t(key, lang)
    if type(key) ~= "string" then
        return tostring(key)
    end
    local entry = Locale.STRINGS[key]
    if type(entry) ~= "table" then
        return key
    end
    local target = normalizeLanguage(lang) or Locale.ACTIVE
    local value = entry[target]
    if type(value) == "string" then
        return value
    end
    for index = 1, #Locale.LANGUAGES do
        local candidate = entry[Locale.LANGUAGES[index]]
        if type(candidate) == "string" then
            return candidate
        end
    end
    return key
end

--- Locale.t + string.format, safe by construction: a missing key (or a template
--- whose placeholders do not match the arguments) returns the template instead of
--- raising.
--- @param key string
--- @param ... any values for the "%s" / "%d" placeholders
--- @return string
function Locale.format(key, ...)
    local template = Locale.t(key)
    local ok, formatted = pcall(string.format, template, ...)
    if ok and type(formatted) == "string" then
        return formatted
    end
    return template
end

return Locale
