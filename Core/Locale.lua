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

    The ping is placed by the PLAYER through the native Blizzard ping keybinds
    (Options > Keybindings): the addon only says WHICH ping to use and, when the
    player has bound a key, WHICH key to press (read with GetBindingKey by the
    rendering layer, never by Core/).
----------------------------------------------------------------------------]]
--
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
            .. "  /gr ping [anchors|color|none]"
            .. "  /gr inter [start|stop|place|on|off|status|3V1R|2V2R|1V3R]",
        fr = "Commandes : /gr | /gr plan | /gr status | /gr reset | /gr lang [auto|en|fr]\n"
            .. "  /gr ping [anchors|color|none]"
            .. "  /gr inter [start|stop|place|on|off|status|3V1R|2V2R|1V3R]",
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
    ["cmd.ping.status"] = {
        en = "Ping policy: %s - %s (/gr ping anchors|color|none to change).",
        fr = "Politique de ping : %s - %s (/gr ping anchors|color|none pour changer).",
    },
    ["cmd.ping.updated"] = {
        en = "Ping policy = %s - %s",
        fr = "Politique de ping = %s - %s",
    },
    ["cmd.ping.unknown"] = {
        en = "Unknown ping policy '%s': accepted values are anchors, color, none.",
        fr = "Politique de ping inconnue '%s' : valeurs acceptees anchors, color, none.",
    },

    -- -------------------------------------------------------------- ping policy
    -- One line per policy, used by /gr ping and by /gr inter status. The policy
    -- is NOT displayed permanently on screen any more: it only decides WHO has
    -- to ping (by default the 1V3R ANCHOR alone).
    ["pingMode.anchors"] = {
        en = "ANCHORS: only the 1V3R anchors ping (one ping per anchor, ~8 pings per raid instead of ~20).",
        fr = "ANCRES : seules les ancres 1V3R ping (un ping par ancre, ~8 pings par raid au lieu de ~20).",
    },
    ["pingMode.color"] = {
        en = "COLOR: every state pings with its own ping (1V3R %s, 2V2R %s, 3V1R %s).",
        fr = "COULEUR : chaque etat ping avec son propre ping (1V3R %s, 2V2R %s, 3V1R %s).",
    },
    ["pingMode.none"] = {
        en = "NONE: nobody pings, the raid plays on positions only.",
        fr = "AUCUN : personne ne ping, le raid joue uniquement en positions.",
    },

    -- ------------------------------------------------------------- main panel
    ["panel.noPlan"] = {
        en = "No out-of-game plan loaded (optional).",
        fr = "Aucun plan hors jeu charge (optionnel).",
    },
    ["panel.unreadablePlan"] = {
        en = "|cffff5555Unreadable plan|r",
        fr = "|cffff5555Plan illisible|r",
    },
    ["panel.placeButton"] = {
        en = "PLACE INTERMISSION PANEL",
        fr = "PLACER LE PANNEAU INTERMISSION",
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
    ["ui.close"] = {
        en = "Close",
        fr = "Fermer",
    },
    ["ui.ok"] = {
        en = "OK",
        fr = "OK",
    },
    ["ui.redo"] = {
        en = "REDO",
        fr = "CORRIGER",
    },
    ["ui.pingBanner"] = {
        en = "PING: %s",
        fr = "PING : %s",
    },
    ["ui.roleLine"] = {
        en = "ROLE: %s",
        fr = "ROLE : %s",
    },
    ["ui.bindingLabel"] = {
        en = "Intermission panel (Entombed Sentinels)",
        fr = "Panneau Intermission (Entombed Sentinels)",
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
    ["ui.pingPolicyLine"] = {
        en = "intermission ping policy: %s - %s",
        fr = "politique de ping intermission : %s - %s",
    },
    ["ui.intermissionError"] = {
        en = "Intermission: %s",
        fr = "Intermission : %s",
    },
    ["ui.unreadablePlan"] = {
        en = "unreadable plan (%s)",
        fr = "plan illisible (%s)",
    },
    ["ui.setupDone"] = {
        en = "Placement saved. Pull when you want: the panel opens by itself before each intermission.",
        fr = "Placement enregistre. Pull quand tu veux : le panneau s'ouvre tout seul avant chaque intermission.",
    },
    ["ui.armed"] = {
        en = "Intermission coach armed: %d intermission(s) scheduled, the panel opens %d s before each one.",
        fr = "Coach intermission arme : %d intermission(s) planifiee(s), le panneau s'ouvre %d s avant chacune.",
    },
    ["ui.redoFailed"] = {
        en = "Cannot correct: %s",
        fr = "Correction impossible : %s",
    },
    ["ui.noDeclaration"] = {
        en = "No composition declared yet.",
        fr = "Aucune composition declaree pour l'instant.",
    },
    ["ui.pingCandidates"] = {
        en = "Binding names tried (to be confirmed in game): %s",
        fr = "Noms de raccourci essayes (a confirmer en jeu) : %s",
    },
    ["ui.scheduleLine"] = {
        en = "schedule: %d intermission(s), panel opens %d s before each one",
        fr = "planning : %d intermission(s), le panneau s'ouvre %d s avant chacune",
    },

    -- -------------------------------------------- placement mode (before pull)
    ["ui.setup.headline"] = {
        en = "BEFORE THE PULL - PLACE THE PANEL",
        fr = "AVANT LE PULL - PLACE LE PANNEAU",
    },
    ["ui.setup.drag"] = {
        en = "Drag this frame where you want it during the fight (position saved).",
        fr = "Deplace ce cadre la ou tu le veux pendant le combat (position enregistree).",
    },
    ["ui.setup.keys"] = {
        en = "Prepare your ping: Options > Keybindings > ping system, one key per ping.",
        fr = "Prepare ton ping : Options > Raccourcis > systeme de ping, une touche par ping.",
    },
    ["ui.setup.ready"] = {
        en = "Press OK: the panel opens by itself %d s before each intermission and closes at the end.",
        fr = "Appuie sur OK : le panneau s'ouvre tout seul %d s avant chaque intermission et se ferme a la fin.",
    },
    ["ui.setup.plan"] = {
        en = "Out-of-game plan loaded (%d pairs).",
        fr = "Plan hors jeu charge (%d paires).",
    },
    ["ui.setup.noPlan"] = {
        en = "No out-of-game plan loaded (optional).",
        fr = "Aucun plan hors jeu charge (optionnel).",
    },

    -- ------------------------------------------- intermission headlines/lines
    -- The panel shows the ESSENTIAL only: state, role, PING: YES/NO and ONE
    -- action line. Long explanations live in docs/INTERMISSION-COACH.md.
    ["inter.headline.idle"] = {
        en = "INTERMISSION PANEL READY",
        fr = "PANNEAU INTERMISSION PRET",
    },
    ["inter.line.idle"] = {
        en = "The panel opens by itself before each intermission; you can also click your composition now.",
        fr = "Le panneau s'ouvre tout seul avant chaque intermission ; tu peux aussi cliquer ta composition maintenant.",
    },
    ["inter.headline.getReady"] = {
        en = "GET READY: %d s",
        fr = "TIENS-TOI PRET : %d s",
    },
    ["inter.headline.visible"] = {
        en = "LOOK AT THE ORB COLOR ABOVE THE HEADS: %d s",
        fr = "REGARDE LA COULEUR DES ORBES AU-DESSUS DES TETES : %d s",
    },
    ["inter.headline.dark"] = {
        en = "ROOM DARKENED: YOU ONLY SEE YOURSELF",
        fr = "SALLE OBSCURCIE : TU NE VOIS PLUS QUE TOI",
    },
    ["inter.headline.done"] = {
        en = "INTERMISSION OVER",
        fr = "INTERMISSION TERMINEE",
    },
    ["inter.prompt"] = {
        en = "Click the composition you see above your head.",
        fr = "Clique la composition que tu vois au-dessus de ta tete.",
    },

    -- -------------------------------------------------- ping instruction lines
    -- The player pings THEMSELVES with the native Blizzard ping keybind (the
    -- addon can NOT ping: C_Ping.SendMacroPing is #protected). The key is read
    -- by the rendering layer with GetBindingKey; when no key is bound, the line
    -- says so instead of showing a shortcut that does not exist.
    ["ping.press"] = {
        en = "PING: %s - press %s",
        fr = "PING : %s - appuie sur %s",
    },
    ["ping.noKey"] = {
        en = "PING: %s - set a keybind in Options > Keybindings",
        fr = "PING : %s - definis un raccourci dans Options > Raccourcis",
    },

    -- NAME OF EACH PING, as displayed to the player. The canonical identifier
    -- stays English ("Warning", "OnMyWay", "Assist": configuration, binding
    -- candidates, tests) and ONLY the display label is translated, because the
    -- player reads the label of their own client.
    --   - French labels MEASURED in game by the raid lead (2026-09-22,
    --     Options > Raccourcis): « Ping », « Attaque », « Avertissement »
    --     (= Warning), « En route » (= On My Way), « Aide » (= Assist/Help),
    --     plus « Activer le ciblage de ping » ;
    --   - English labels: Warning / On My Way / Assist
    --     (<https://warcraft.wiki.gg/wiki/Ping_System>).
    ["ping.name.Warning"] = {
        en = "Warning",
        fr = "Avertissement",
    },
    ["ping.name.OnMyWay"] = {
        en = "On My Way",
        fr = "En route",
    },
    ["ping.name.Assist"] = {
        en = "Assist",
        fr = "Aide",
    },

    -- -------------------------------------------------------- ping role texts
    -- PING ROLES BY STATE (raid-lead decision). The number displayed above the
    -- head does NOT choose the role: the ORB COMPOSITION does.
    --   1V3R = ANCHOR  : does not move, pings itself with the native keybind (or
    --                    is pinged by another player);
    --   2V2R = MIDDLE  : does not ping, goes to the middle and pairs with a 2V2R;
    --   3V1R = CHASER  : does not ping, runs to a ping (any 1V3R works).
    -- `state.actionPing.<state>` / `state.actionNoPing.<state>` are the two
    -- variants of the ONE action line, selected by the ping policy: the same
    -- role never receives a contradictory order in any policy.
    ["state.roleName.1V3R"] = {
        en = "ANCHOR",
        fr = "ANCRE",
    },
    ["state.roleName.2V2R"] = {
        en = "MIDDLE",
        fr = "MILIEU",
    },
    ["state.roleName.3V1R"] = {
        en = "CHASER",
        fr = "CHASSEUR",
    },
    ["state.actionPing.1V3R"] = {
        en = "STAY WHERE YOU ARE - ping yourself (%s) and jump on the spot",
        fr = "RESTE SUR PLACE - ping-toi (%s) et saute sur place",
    },
    ["state.actionNoPing.1V3R"] = {
        en = "STAY WHERE YOU ARE - jump on the spot (no ping in this policy)",
        fr = "RESTE SUR PLACE - saute sur place (aucun ping dans cette politique)",
    },
    ["state.actionPing.2V2R"] = {
        en = "PING (%s), then go to the middle / under the boss",
        fr = "PING (%s), puis va au milieu / sous le boss",
    },
    ["state.actionNoPing.2V2R"] = {
        en = "DO NOT PING - go to the middle / under the boss",
        fr = "NE PING PAS - va au milieu / sous le boss",
    },
    ["state.actionPing.3V1R"] = {
        en = "PING (%s), then run to a ping (a 1V3R)",
        fr = "PING (%s), puis fonce sur un ping (un 1V3R)",
    },
    ["state.actionNoPing.3V1R"] = {
        en = "DO NOT PING - run to a ping (a 1V3R)",
        fr = "NE PING PAS - fonce sur un ping (un 1V3R)",
    },
    ["state.ping.yes"] = {
        en = "YES",
        fr = "OUI",
    },
    ["state.ping.no"] = {
        en = "NO",
        fr = "NON",
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
        en = "RUN TO A PING, ANY 1V3R ANCHOR",
        fr = "FONCE SUR UN PING, N'IMPORTE QUELLE ANCRE 1V3R",
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
    -- Pre-pull view: the ping role deduced from the prepared composition, under
    -- the current ping policy (the ping to use is named, never a macro).
    ["plan.yourPingRole"] = {
        en = "Your intermission role: %s (%s) - ping: %s",
        fr = "Ton role d'intermission : %s (%s) - ping : %s",
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
    ["err.pingNotAllowed"] = {
        en = "no ping for %s under the %s policy",
        fr = "aucun ping pour %s dans la politique %s",
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
    ["err.nothingToRedo"] = {
        en = "nothing to correct (no composition declared)",
        fr = "rien a corriger (aucune composition declaree)",
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
