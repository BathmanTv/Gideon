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
        en = "Commands: /gideon | /gideon plan | /gideon status | /gideon reset | /gideon lang [auto|en|fr]\n"
            .. "  /gideon ping [anchors|color|none]"
            .. "  /gideon inter [start|stop|place|ok|on|off|status|3V1R|2V2R|1V3R]\n"
            .. "  (place = the panel shows the illustration and its small OK button; ok = save the position and close)\n"
            .. "  /gideon sound [on|off] | /gideon sound test 1v3r|2v2r|3v1r | /gideon sound test start\n"
            .. "  /gideon boss | /gideon boss <id> | /gideon boss name <text> | /gideon boss list | /gideon boss clear\n"
            .. "  /gideon idlog [on|off]\n"
            .. "  /gideon diag (health report: the 4 sound files, the target boss, the idlog, the ping)\n"
            .. "  /gideon style [1|shipped] (CARD STYLE of the intermission panel - one single style, persisted)\n"
            .. "  /gideon sim inter|group|groupe (rehearsal, YOU close it) | /gideon sim ping (= /gideon pinghelp) | /gideon sim stop\n"
            .. "  /gideon sim style [1|shipped] (STYLE SHOWCASE: every font size, the palette, the guild card)\n"
            .. "  /gideon sim anim [on|off] (showcase animations: fade-in + border pulse, persisted)\n"
            .. "  /gideon lock | /gideon unlock | /gideon resetposition",
        fr = "Commandes : /gideon | /gideon plan | /gideon status | /gideon reset | /gideon lang [auto|en|fr]\n"
            .. "  /gideon ping [anchors|color|none]"
            .. "  /gideon inter [start|stop|place|ok|on|off|status|3V1R|2V2R|1V3R]\n"
            .. "  (place = le panneau affiche l'illustration et son petit bouton OK ; ok = enregistre la position et ferme)\n"
            .. "  /gideon sound [on|off] | /gideon sound test 1v3r|2v2r|3v1r | /gideon sound test start\n"
            .. "  /gideon boss | /gideon boss <id> | /gideon boss name <texte> | /gideon boss list | /gideon boss clear\n"
            .. "  /gideon idlog [on|off]\n"
            .. "  /gideon diag (bilan de sante : les 4 fichiers de son, le boss cible, l'idlog, le ping)\n"
            .. "  /gideon style [1|shipped] (STYLE DES ENCARTS du panneau d'intermission - un seul style, persiste)\n"
            .. "  /gideon sim inter|group|groupe (repetition, c'est TOI qui la fermes) | /gideon sim ping (= /gideon pinghelp)\n"
            .. "  /gideon sim stop\n"
            .. "  /gideon sim style [1|shipped] (VITRINE DE STYLE : toutes les tailles, la palette, l'encart de la guilde)\n"
            .. "  /gideon sim anim [on|off] (animations de la vitrine : fondu + pulsation, persiste)\n"
            .. "  /gideon lock | /gideon unlock | /gideon resetposition",
    },
    ["cmd.sim.help"] = {
        en = "Simulation (alone, no boss, no raid): /gideon sim inter (alias group, groupe) = the intermission "
            .. "panel opens RIGHT AWAY, you click your composition and YOU close it (X or Close); /gideon sim ping = "
            .. "ping help window (how to bind a key per ping and how to ping yourself); /gideon sim stop = close it; "
            .. "/gideon sim style [1|shipped] = the STYLE SHOWCASE (fonts, palette with hex codes, card states, the "
            .. "guild card, the animations); /gideon sim anim on|off = its animations.",
        fr = "Simulation (seul, sans boss, sans raid) : /gideon sim inter (alias group, groupe) = le panneau "
            .. "d'intermission s'ouvre TOUT DE SUITE, tu cliques ta composition et c'est TOI qui le fermes "
            .. "(croix ou Fermer) ; /gideon sim ping = fenetre d'aide au ping (comment binder une touche par ping et "
            .. "comment te pinger toi-meme) ; /gideon sim stop = le fermer ; /gideon sim style [1|shipped] = la VITRINE "
            .. "DE STYLE (polices, palette avec codes hexa, etats d'un encart, l'encart de la guilde, "
            .. "animations) ; /gideon sim anim on|off = ses animations.",
    },
    -- Panel lock: the main panel is MOVABLE by default (in-game feedback); these
    -- three commands are the lock / unlock / reset entry points.
    ["cmd.panelLocked"] = {
        en = "Panel locked: it can no longer be dragged (/gideon unlock to move it again).",
        fr = "Panneau verrouille : il ne peut plus etre deplace (/gideon unlock pour le deplacer a nouveau).",
    },
    ["cmd.panelUnlocked"] = {
        en = "Panel unlocked: drag it where you want, the position is saved automatically.",
        fr = "Panneau deverrouille : deplace-le ou tu veux, la position est enregistree automatiquement.",
    },
    ["cmd.positionReset"] = {
        en = "Panel positions reset to the center of the screen (main panel, intermission panel, ping training).",
        fr = "Positions des panneaux remises au centre de l'ecran (panneau principal, panneau intermission, " .. "entrainement au ping).",
    },
    ["cmd.sim.unknown"] = {
        en = "Unknown simulation '%s': accepted values are inter (group, groupe), ping, stop.",
        fr = "Simulation inconnue '%s' : valeurs acceptees inter (group, groupe), ping, stop.",
    },
    ["cmd.sim.inter"] = {
        en = "SIMULATION (no boss, no raid): the intermission panel opens RIGHT AWAY. Click your composition, "
            .. "then close it yourself (X or Close button). The ENCOUNTER_START timeline is NOT armed.",
        fr = "SIMULATION (sans boss, sans raid) : le panneau d'intermission s'ouvre TOUT DE SUITE. Clique ta "
            .. "composition, puis ferme-le toi-meme (croix ou bouton Fermer). Le planning ENCOUNTER_START n'est "
            .. "PAS arme.",
    },
    ["cmd.sim.closed"] = {
        en = "Simulation closed (no boss, no raid, nothing was published).",
        fr = "Simulation fermee (sans boss, sans raid, rien n'a ete publie).",
    },
    ["cmd.sim.none"] = {
        en = "No simulation running.",
        fr = "Aucune simulation en cours.",
    },
    ["cmd.sim.pingStart"] = {
        en = "PING HELP (no simulation, no boss): bind one key per ping (Options > Keybindings > Ping, %s) and, "
            .. "when the panel says PING: YES, ping YOURSELF (hover YOUR OWN character frame, then press the "
            .. "key). A ping only shows in a group or a raid, and this addon detects nothing.",
        fr = "AIDE AU PING (aucune simulation, aucun boss) : bind une touche par ping (Options > Raccourcis > "
            .. "Ping, %s) et, quand le panneau dit PING : OUI, pinge-toi TOI-MEME (survole TON propre cadre de "
            .. "personnage, puis appuie sur la touche). Un ping ne s'affiche qu'en groupe ou raid, et cet addon "
            .. "ne detecte rien.",
    },
    ["cmd.lang.status"] = {
        en = "Language: client detected = %s, effective = %s, preference = %s (/gideon lang auto|en|fr to change).",
        fr = "Langue : client detecte = %s, effective = %s, preference = %s (/gideon lang auto|en|fr pour changer).",
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
        en = "Ping policy: %s - %s (/gideon ping anchors|color|none to change).",
        fr = "Politique de ping : %s - %s (/gideon ping anchors|color|none pour changer).",
    },
    ["cmd.ping.updated"] = {
        en = "Ping policy = %s - %s",
        fr = "Politique de ping = %s - %s",
    },
    ["cmd.ping.unknown"] = {
        en = "Unknown ping policy '%s': accepted values are anchors, color, none.",
        fr = "Politique de ping inconnue '%s' : valeurs acceptees anchors, color, none.",
    },

    -- ------------------------------------------------- assignment soundboards
    -- ONE sound per canonical state (1V3R / 2V2R / 3V1R), played ONCE when the
    -- player declares their composition. The file names are never displayed as
    -- paths: only the short name of the file is shown, so a player can tell the
    -- raid lead WHICH soundboard they heard (or did not hear).
    ["cmd.sound.status"] = {
        en = "Assignment sound: %s - one soundboard per composition (1V3R / 2V2R / 3V1R), played once "
            .. "when you click your composition. /gideon sound on|off to change it, /gideon sound test 1v3r|2v2r|3v1r "
            .. "to hear one now, /gideon sound test start for the intermission start sound.",
        fr = "Son d'assignation : %s - un son par composition (1V3R / 2V2R / 3V1R), joue une fois quand tu "
            .. "cliques ta composition. /gideon sound on|off pour changer, /gideon sound test 1v3r|2v2r|3v1r pour en "
            .. "ecouter un maintenant, /gideon sound test start pour le son de debut d'intermission.",
    },
    ["cmd.sound.updated"] = {
        en = "Assignment sound = %s.",
        fr = "Son d'assignation = %s.",
    },
    ["cmd.sound.unknown"] = {
        en = "Unknown value '%s': accepted values are on, off.",
        fr = "Valeur inconnue '%s' : valeurs acceptees on, off.",
    },
    ["cmd.sound.unknownState"] = {
        en = "Unknown sound '%s': accepted values are 1v3r, 2v2r, 3v1r, start.",
        fr = "Son inconnu '%s' : valeurs acceptees 1v3r, 2v2r, 3v1r, start.",
    },
    ["cmd.sound.test"] = {
        en = "Sound test: %s (%s) should have played. If you heard nothing, check that the file was replaced "
            .. "correctly (same name, Ogg Vorbis) and that the game volume is up.",
        fr = "Test du son : %s (%s) devrait avoir ete joue. Si tu n'as rien entendu, verifie que le fichier a "
            .. "bien ete remplace (meme nom, Ogg Vorbis) et que le volume du jeu est monte.",
    },
    ["cmd.sound.testDisabled"] = {
        en = "Assignment sound is disabled: /gideon sound on, then /gideon sound test again.",
        fr = "Le son d'assignation est desactive : /gideon sound on, puis /gideon sound test a nouveau.",
    },
    ["cmd.sound.failed"] = {
        en = "Sound %s could not be played (file missing or PlaySoundFile unavailable): the addon stays "
            .. "silent, nothing else is affected.",
        fr = "Le son %s n'a pas pu etre joue (fichier manquant ou PlaySoundFile indisponible) : l'addon reste "
            .. "silencieux, rien d'autre n'est affecte.",
    },
    -- THE INTERMISSION START SOUND (the raid lead's own recording, played ONCE at
    -- the very beginning of every intermission - i.e. when the panel opens by
    -- itself 2 s before the intermission - and once per `/gideon sim inter`).
    ["cmd.sound.testStart"] = {
        en = "Intermission start sound: %s should have played (once at the beginning of every intermission). "
            .. "If you heard nothing, check that the file is there (Sound/intermission-start.ogg, Ogg Vorbis) "
            .. "and that the game volume is up.",
        fr = "Son de debut d'intermission : %s devrait avoir ete joue (une fois au debut de chaque "
            .. "intermission). Si tu n'as rien entendu, verifie que le fichier est bien la "
            .. "(Sound/intermission-start.ogg, Ogg Vorbis) et que le volume du jeu est monte.",
    },

    -- ------------------------------------------- WHICH BOSS MAY OPEN THE PANEL
    -- CRITICAL BUG fixed here: the panel used to open on ANY ENCOUNTER_START. The
    -- auto-open target is an ALLOW-LIST of encounter ids (ENCOUNTER_START arg1: an
    -- integer, identical in every language) plus an optional list of NAMES (arg2,
    -- which depends on the client language, hence EMPTY by default and never
    -- guessed). SAFE DEFAULT: an empty list opens NOTHING.
    ["cmd.boss.status"] = {
        en = "Auto-open target boss: %s. Encounter id log: %s. /gideon boss <id> sets it, /gideon boss list shows it, "
            .. "/gideon boss clear removes it.",
        fr = "Boss cible de l'ouverture auto : %s. Journal des ids d'encounter : %s. /gideon boss <id> pour la "
            .. "definir, /gideon boss list pour l'afficher, /gideon boss clear pour l'effacer.",
    },
    ["cmd.boss.target.none"] = {
        en = "NONE - SAFE DEFAULT: the panel will NOT open by itself",
        fr = "AUCUNE - DEFAUT SUR : le panneau ne s'ouvrira PAS tout seul",
    },
    -- `/gideon boss clear` is a DIFFERENT state from "no target at all": the player
    -- explicitly dropped the target, including the one the addon ships with. Saying
    -- so avoids reading a deliberate choice as a lost configuration.
    ["cmd.boss.target.cleared"] = {
        en = "NONE - cleared ON PURPOSE (/gideon boss clear): the panel will NOT open by itself",
        fr = "AUCUNE - effacee EXPRES (/gideon boss clear) : le panneau ne s'ouvrira PAS tout seul",
    },
    -- WHERE the effective target comes from (`/gideon boss`, `/gideon boss list`, `/gideon diag`):
    -- a save that was never configured gets the target DELIVERED with the addon
    -- (encounter id + the two names), a player who added ids gets both, and an
    -- explicit `/gideon boss clear` drops the delivered one.
    ["cmd.boss.source.default"] = {
        en = "Target source: the default DELIVERED with the addon (no player ever added anything).",
        fr = "Origine de la cible : le defaut LIVRE avec l'addon (aucun joueur n'a rien ajoute).",
    },
    ["cmd.boss.source.mixed"] = {
        en = "Target source: the default delivered with the addon PLUS the entries added by a player.",
        fr = "Origine de la cible : le defaut livre avec l'addon PLUS les entrees ajoutees par un joueur.",
    },
    ["cmd.boss.source.own"] = {
        en = "Target source: ONLY the entries added by a player (the delivered default was dropped by " .. "/gideon boss clear).",
        fr = "Origine de la cible : SEULEMENT les entrees ajoutees par un joueur (le defaut livre a ete "
            .. "retire par /gideon boss clear).",
    },
    ["cmd.boss.source.cleared"] = {
        en = "Target source: cleared ON PURPOSE (/gideon boss clear): the panel will NOT open by itself until "
            .. "/gideon boss <id> names a target again.",
        fr = "Origine de la cible : effacee EXPRES (/gideon boss clear) : le panneau ne s'ouvrira PAS tout seul "
            .. "tant que /gideon boss <id> ne nomme pas une cible.",
    },
    -- Provenance of ONE entry of `/gideon boss list`.
    ["cmd.boss.sourceDefault"] = {
        en = "addon default",
        fr = "defaut de l'addon",
    },
    ["cmd.boss.sourceOwn"] = {
        en = "added by you",
        fr = "ajoute par toi",
    },
    -- THE TARGET THE ADDON SHIPS WITH: printed by `/gideon boss` and `/gideon diag` so the
    -- raid lead always sees what a fresh guild member gets WITHOUT typing anything.
    -- %s = the encounter id(s), %s = the name(s) (the French one keeps its accent).
    ["cmd.boss.delivered"] = {
        en = "Default delivered with the addon (it needs NO command and NO SavedVariables): id %s, names %s.",
        fr = "Defaut livre avec l'addon (il ne demande AUCUNE commande et AUCUNE sauvegarde) : id %s, " .. "noms %s.",
    },
    ["cmd.boss.target.ids"] = {
        en = "ids %s",
        fr = "ids %s",
    },
    ["cmd.boss.target.names"] = {
        en = "names %s (they depend on the client language)",
        fr = "noms %s (ils dependent de la langue du client)",
    },
    ["cmd.boss.added"] = {
        en = "Target encounter id %d added (%d id(s) configured). Auto-open target: %s",
        fr = "Id d'encounter cible %d ajoute (%d id(s) configure(s)). Cible de l'ouverture auto : %s",
    },
    ["cmd.boss.unknown"] = {
        en = "Unknown encounter id '%s': a POSITIVE INTEGER is expected, the id ENCOUNTER_START reports "
            .. "(/gideon idlog on captures it in game). Nothing was saved.",
        fr = "Id d'encounter inconnu '%s' : un ENTIER POSITIF est attendu, l'id que rapporte ENCOUNTER_START "
            .. "(/gideon idlog on le capture en jeu). Rien n'a ete enregistre.",
    },
    ["cmd.boss.nameAdded"] = {
        en = "Target encounter name '%s' added. Auto-open target: %s",
        fr = "Nom d'encounter cible '%s' ajoute. Cible de l'ouverture auto : %s",
    },
    ["cmd.boss.nameUnknown"] = {
        en = "Empty encounter name '%s': write the exact name your client displays (/gideon idlog on shows it), or "
            .. "use /gideon boss <id> instead.",
        fr = "Nom d'encounter vide '%s' : ecris le nom exact affiche par ton client (/gideon idlog on l'affiche), "
            .. "ou utilise plutot /gideon boss <id>.",
    },
    -- Printed when a pull is refused because the player CLEARED the target on purpose
    -- (`/gideon boss clear`): short, actionable, and the delivered default is named so the
    -- id can be typed back as-is.
    ["cmd.boss.clearedHint"] = {
        en = "Auto-open target cleared on purpose (/gideon boss clear): the panel does not open by itself. "
            .. "/gideon boss 3445 puts the target of the addon back, /gideon boss <id> names another one, /gideon inter on "
            .. "opens the panel for the NEXT encounter.",
        fr = "Cible de l'ouverture auto effacee expres (/gideon boss clear) : le panneau ne s'ouvre pas tout "
            .. "seul. /gideon boss 3445 remet la cible de l'addon, /gideon boss <id> en nomme une autre, /gideon inter on "
            .. "ouvre le panneau au PROCHAIN encounter.",
    },
    ["cmd.boss.cleared"] = {
        en = "Auto-open target cleared: the default DELIVERED with the addon is dropped too, so the panel "
            .. "will NOT open by itself any more. /gideon boss <id> names a target again (the delivered id can "
            .. "be typed back: /gideon boss 3445), /gideon inter on opens the panel on the next encounter.",
        fr = "Cible de l'ouverture auto effacee : le defaut LIVRE avec l'addon est retire lui aussi, donc "
            .. "le panneau ne s'ouvrira plus tout seul. /gideon boss <id> nomme une cible a nouveau (l'id livre "
            .. "peut etre retape : /gideon boss 3445), /gideon inter on ouvre le panneau au prochain encounter.",
    },
    ["cmd.boss.list.ids"] = {
        en = "Auto-open target ids: %s",
        fr = "Ids cibles de l'ouverture auto : %s",
    },
    ["cmd.boss.list.names"] = {
        en = "Auto-open target names (SECONDARY criterion - the id decides; the addon DELIVERS the English "
            .. "and French names of the target boss, and `/gideon boss name <text>` adds the exact text YOUR "
            .. "client displays): %s",
        fr = "Noms cibles de l'ouverture auto (critere SECONDAIRE - c'est l'id qui decide ; l'addon LIVRE "
            .. "les noms anglais et francais du boss cible, et `/gideon boss name <texte>` ajoute le texte exact "
            .. "affiche par TON client) : %s",
    },
    ["cmd.boss.list.override"] = {
        en = "Manual override: %s (/gideon inter on arms the panel for the NEXT encounter, whatever the boss; it "
            .. "is consumed at the end of that encounter).",
        fr = "Override manuel : %s (/gideon inter on arme le panneau pour le PROCHAIN encounter, quel que soit le "
            .. "boss ; il est consomme a la fin de cet encounter).",
    },
    ["cmd.boss.list.seen"] = {
        en = "Encounters memorized by the idlog (%d, newest first):",
        fr = "Encounters memorises par l'idlog (%d, du plus recent au plus ancien) :",
    },
    -- THE IDLOG LINE. Read by the raid lead at the pull of the target boss: it is
    -- the ONLY source of the real id (nothing is invented). Each value is read
    -- under pcall, and a value that cannot be read says so instead of showing a
    -- fake number.
    ["cmd.boss.seen"] = {
        en = "encounter seen: id=%s name=%s difficulty=%s group=%s",
        fr = "encounter vu : id=%s name=%s difficulty=%s group=%s",
    },
    ["cmd.boss.value.unreadable"] = {
        en = "unreadable",
        fr = "illisible",
    },
    ["cmd.boss.value.absent"] = {
        en = "none",
        fr = "aucun",
    },
    -- Load-time warning and reminder at every encounter that opens nothing: the
    -- SAFE DEFAULT is a panel that stays closed, so the chat says HOW to configure
    -- the right boss (or to force the next encounter once).
    ["cmd.boss.noTarget"] = {
        en = "No target boss configured: the intermission panel will NOT open by itself (SAFE DEFAULT - a "
            .. "panel that does not open is better than a panel on the wrong boss). The addon DELIVERS a "
            .. "target (encounter id 3445, Entombed Sentinels) unless it was cleared with /gideon boss clear, and "
            .. "/gideon boss <id> names one (the real id is measured in game with /gideon idlog on). /gideon inter on "
            .. "opens the panel for the NEXT encounter, whatever the boss.",
        fr = "Aucun boss cible configure : le panneau d'intermission ne s'ouvrira PAS tout seul (DEFAUT SUR - "
            .. "mieux vaut un panneau qui ne s'ouvre pas qu'un panneau sur le mauvais boss). L'addon LIVRE "
            .. "une cible (id d'encounter 3445, Entombed Sentinels) sauf si elle a ete effacee avec /gideon boss "
            .. "clear, et /gideon boss <id> en nomme une (l'id reel se mesure en jeu avec /gideon idlog on). /gideon inter "
            .. "on ouvre le panneau au PROCHAIN encounter, quel que soit le boss.",
    },
    ["cmd.boss.notTarget"] = {
        en = "Encounter %s is NOT the configured target: the panel stays closed. /gideon boss <id> to change the "
            .. "target (the id just reported can be copied), /gideon inter on to open the panel for the next "
            .. "encounter.",
        fr = "L'encounter %s n'est PAS la cible configuree : le panneau reste ferme. /gideon boss <id> pour "
            .. "changer la cible (l'id qui vient d'etre affiche peut etre recopie), /gideon inter on pour ouvrir "
            .. "le panneau au prochain encounter.",
    },
    ["cmd.boss.notTargetNoId"] = {
        en = "This encounter is NOT the configured target (no usable id was read on it): the panel stays "
            .. "closed. /gideon idlog on shows what ENCOUNTER_START reports, /gideon boss <id> sets the target, /gideon "
            .. "inter on opens the panel for the next encounter.",
        fr = "Cet encounter n'est PAS la cible configuree (aucun id exploitable n'a ete lu) : le panneau "
            .. "reste ferme. /gideon idlog on affiche ce que rapporte ENCOUNTER_START, /gideon boss <id> definit la "
            .. "cible, /gideon inter on ouvre le panneau au prochain encounter.",
    },
    ["cmd.boss.unreadable"] = {
        en = "The encounter id could not be read (secret value?): no automatic opening. /gideon inter on opens the "
            .. "panel for the next encounter.",
        fr = "L'id de l'encounter n'a pas pu etre lu (valeur secrete ?) : aucune ouverture automatique. /gideon "
            .. "inter on ouvre le panneau au prochain encounter.",
    },
    ["cmd.boss.overrideArmed"] = {
        en = "Manual override armed: the panel opens for the NEXT encounter, whatever the boss (consumed at "
            .. "the end of that encounter).",
        fr = "Override manuel arme : le panneau s'ouvre au PROCHAIN encounter, quel que soit le boss "
            .. "(consomme a la fin de cet encounter).",
    },
    ["cmd.boss.overrideUsed"] = {
        en = "Encounter started: the MANUAL OVERRIDE (/gideon inter on) opens the panel for it, whatever the boss; "
            .. "it is consumed at the end of this encounter.",
        fr = "Combat commence : l'OVERRIDE MANUEL (/gideon inter on) ouvre le panneau pour cet encounter, quel "
            .. "que soit le boss ; il est consomme a la fin de ce combat.",
    },
    ["cmd.boss.overrideConsumed"] = {
        en = "Manual override consumed: the panel only opens again for the configured target.",
        fr = "Override manuel consomme : le panneau ne s'ouvre a nouveau que pour la cible configuree.",
    },
    ["cmd.idlog.status"] = {
        en = "Encounter id log: %s. When on, every ENCOUNTER_START prints 'encounter seen: id=<id> "
            .. "name=<name> difficulty=<d> group=<n>' ('unreadable' when a value cannot be read) and the last "
            .. "%d encounters are memorized in the SavedVariables (/gideon boss list).",
        fr = "Journal des ids d'encounter : %s. Quand il est actif, chaque ENCOUNTER_START affiche "
            .. "'encounter vu : id=<id> name=<nom> difficulty=<d> group=<n>' ('illisible' quand une valeur ne "
            .. "peut pas etre lue) et les %d derniers encounters sont memorises dans les SavedVariables "
            .. "(/gideon boss list).",
    },
    ["cmd.idlog.updated"] = {
        en = "Encounter id log = %s.",
        fr = "Journal des ids d'encounter = %s.",
    },
    ["cmd.idlog.unknown"] = {
        en = "Unknown value '%s': accepted values are on, off.",
        fr = "Valeur inconnue '%s' : valeurs acceptees on, off.",
    },

    -- ------------------------------------------------------------- /gideon diag ---
    -- THE HEALTH REPORT, in ONE command: are the four sound files really loaded and
    -- playable, what is the effective auto-open target, is the idlog on, which ping
    -- policy is active. READ-ONLY: nothing is written, nothing is sent, no macro, no
    -- ping, and NOTHING IS PLAYED in a client whose sound is on (see the two gate
    -- lines below). The verdict markers are ASCII ("[OK]", "[KO]") on purpose: the
    -- default game font renders accented glyphs badly.
    ["cmd.diag.header"] = {
        en = "--- DIAGNOSTIC (read-only: nothing is written, nothing is sent, nothing is played) ---",
        fr = "--- DIAGNOSTIC (lecture seule : rien n'est ecrit, rien n'est envoye, rien n'est joue) ---",
    },
    ["cmd.diag.target"] = {
        en = "auto-open target: %s",
        fr = "cible de l'ouverture auto : %s",
    },
    ["cmd.diag.idlog"] = {
        en = "encounter id log: %s",
        fr = "journal des ids d'encounter : %s",
    },
    ["cmd.diag.ping"] = {
        en = "intermission ping policy: %s - %s",
        fr = "politique de ping intermission : %s - %s",
    },
    ["cmd.diag.soundPref"] = {
        en = "assignment sound preference: %s",
        fr = "preference de son d'assignation : %s",
    },
    ["cmd.diag.sounds"] = {
        en = "sound files of the addon (%d) - each one checked for being LOADED and PLAYABLE:",
        fr = "fichiers de son de l'addon (%d) - chacun verifie comme CHARGE et JOUABLE :",
    },
    ["cmd.diag.sound.playable"] = {
        en = "  %s: present and playable [OK]",
        fr = "  %s: present et jouable [OK]",
    },
    ["cmd.diag.sound.notPlayable"] = {
        en = "  %s: NOT playable [KO] - the file is missing from Sound/, or not listed in GideonRaid.toc "
            .. "(an unlisted file is NEVER loaded), or it was added AFTER the client started (WoW must be "
            .. "RESTARTED: a /reload does not load a new sound file)",
        fr = "  %s: NON jouable [KO] - le fichier manque dans Sound/, ou n'est pas liste dans "
            .. "GideonRaid.toc (un fichier non liste n'est JAMAIS charge), ou il a ete ajoute APRES le "
            .. "lancement du client (WoW doit etre RELANCE : un /reload ne charge pas un nouveau fichier de son)",
    },
    ["cmd.diag.sound.notTested"] = {
        en = "  %s: NOT TESTED (the check would have made noise: see the reason below)",
        fr = "  %s: NON TESTE (le test aurait fait du bruit : voir la raison ci-dessous)",
    },
    ["cmd.diag.sound.unknown"] = {
        en = "  %s: verdict UNKNOWN (the client refused the test call)",
        fr = "  %s: verdict INCONNU (le client a refuse l'appel de test)",
    },
    -- All four files "not playable" at once: the channel probably refuses every
    -- playback (a muted channel answers the same thing for a file that IS there).
    ["cmd.diag.caveat"] = {
        en = "careful: ALL FOUR files came back as not playable. Before hunting four files, check that the "
            .. "Master channel really accepts a playback (put the master volume back above 0 and hear one "
            .. "with /gideon sound test 1v3r): a channel that refuses everything answers 'not playable' even for "
            .. "a file that is there.",
        fr = "attention : les QUATRE fichiers reviennent comme non jouables. Avant de chercher quatre "
            .. "fichiers, verifie que le canal Master accepte vraiment une lecture (remonte le volume "
            .. "general au-dessus de 0 et ecoutes-en un avec /gideon sound test 1v3r) : un canal qui refuse tout "
            .. "repond 'non jouable' meme pour un fichier present.",
    },
    ["cmd.diag.gate.probe"] = {
        en = "the check DID run for real: the Master channel was ENABLED with its volume at 0, so the client "
            .. "answered for every file while NOTHING was audible.",
        fr = "le test a VRAIMENT tourne : le canal Master etait ACTIF avec un volume a 0, donc le client a "
            .. "repondu pour chaque fichier sans que RIEN soit audible.",
    },
    ["cmd.diag.gate.soundOn"] = {
        en = "the audio check did NOT run: the game sound is ON, and this diagnostic NEVER plays a sound (no "
            .. "noise during a fight). To check the four files WITHOUT noise: set the master volume to 0 "
            .. "(Options > Sound, or /console Sound_MasterVolume 0), run /gideon diag again, then put it back "
            .. "(/console Sound_MasterVolume 1). To HEAR a file on purpose: /gideon sound test 1v3r|2v2r|3v1r|start.",
        fr = "le test audio n'a PAS tourne : le son du jeu est ACTIF, et ce diagnostic ne joue JAMAIS de son "
            .. "(aucun bruit pendant un combat). Pour verifier les quatre fichiers SANS bruit : mets le "
            .. "volume general a 0 (Options > Son, ou /console Sound_MasterVolume 0), relance /gideon diag, puis "
            .. "remets-le (/console Sound_MasterVolume 1). Pour ENTENDRE un fichier expres : "
            .. "/gideon sound test 1v3r|2v2r|3v1r|start.",
    },
    ["cmd.diag.gate.soundOff"] = {
        en = "the audio check did NOT run: the sound is OFF (or unreadable) in this client, and a DISABLED "
            .. "channel answers 'nothing will play' even for a file that is really there - the verdict would "
            .. "be a lie. Turn the sound on (Ctrl+S, or Options > Sound) and run /gideon diag again, or hear the "
            .. "files on purpose with /gideon sound test 1v3r|2v2r|3v1r|start.",
        fr = "le test audio n'a PAS tourne : le son est COUPE (ou illisible) dans ce client, et un canal "
            .. "DESACTIVE repond 'rien ne sera joue' meme pour un fichier bien present - le verdict serait un "
            .. "mensonge. Remets le son (Ctrl+S, ou Options > Son) et relance /gideon diag, ou ecoute les "
            .. "fichiers expres avec /gideon sound test 1v3r|2v2r|3v1r|start.",
    },
    ["cmd.diag.reminders"] = {
        en = "reminder: a sound file added AFTER the client started is NOT loaded before a RESTART, and a "
            .. "file that is not listed in GideonRaid.toc is NEVER loaded. The four files of this addon ARE "
            .. "listed there (checked out of game by make check, and by tests/spec/sound_spec.lua).",
        fr = "rappel : un fichier de son ajoute APRES le lancement du client n'est pas charge avant un "
            .. "REDEMARRAGE, et un fichier non liste dans GideonRaid.toc n'est JAMAIS charge. Les quatre "
            .. "fichiers de cet addon y SONT listes (verifie hors jeu par make check et par "
            .. "tests/spec/sound_spec.lua).",
    },
    ["cmd.diag.howToTest"] = {
        en = "to hear a file on purpose: /gideon sound test 1v3r | 2v2r | 3v1r | start - those DO play a sound, "
            .. "/gideon diag never does.",
        fr = "pour entendre un fichier expres : /gideon sound test 1v3r | 2v2r | 3v1r | start - eux JOUENT un "
            .. "son, /gideon diag jamais.",
    },

    -- -------------------------------------------------------------- ping policy
    -- One line per policy, used by /gideon ping and by /gideon inter status. The policy
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
    -- SHORT labels on purpose (fourth in-game test: the French labels ran over
    -- the borders of the main panel). The layout module measures them and grows
    -- the frame when needed, but a short label stays readable in a small panel.
    ["panel.placeButton"] = {
        en = "PLACE INTERMISSION PANEL",
        fr = "PLACER LE PANNEAU",
    },
    -- Two SIMULATION entries, also reachable by command (/gideon sim inter, /gideon sim
    -- ping): a rehearsal alone, with no boss and no raid.
    ["panel.simInterButton"] = {
        en = "SIM: INTERMISSION GROUP",
        fr = "SIMULATION : GROUPE INTER",
    },
    ["panel.simPingButton"] = {
        en = "SIM: PING YOURSELF",
        fr = "SIMULATION : TE PINGER",
    },
    -- Lock / unlock of the panels. The main panel is DRAGGABLE by default (the
    -- player can move it); this button freezes the position, and the label always
    -- names the ACTION the click performs.
    ["panel.lockButton"] = {
        en = "LOCK PANEL",
        fr = "VERROUILLER",
    },
    ["panel.unlockButton"] = {
        en = "UNLOCK PANEL",
        fr = "DEVERROUILLER",
    },
    ["panel.lockedHint"] = {
        en = "Panel locked: /gideon unlock (or the UNLOCK PANEL button) to move it.",
        fr = "Panneau verrouille : /gideon unlock (ou le bouton DEVERROUILLER) pour le deplacer.",
    },
    ["status.noAssignment"] = {
        en = "no assignment (%s)",
        fr = "pas d'assignation (%s)",
    },
    ["status.ok"] = {
        en = "assignment OK, %d pairs",
        fr = "assignation OK, %d paires",
    },

    -- ------------------------------------------------ intermission UI chrome
    -- NO WINDOW TITLE KEY ANY MORE (ui.panelTitle was "GideonRaid - Intermission
    -- Coach" and ui.ok was the label of the placement button). Both usages were
    -- removed with the title block and the OK button; the KEYS are gone too, so
    -- there is no string left to display by accident. The intermission panel
    -- writes the ONE word after a click (state.word.*) and, in rehearsal, the
    -- SIMULATION banner (sim.banner) - nothing else.
    ["ui.mainTitle"] = {
        en = "GideonRaid",
        fr = "GideonRaid",
    },
    ["ui.close"] = {
        en = "Close",
        fr = "Fermer",
    },
    -- Close CROSS ("X", top right) of the main panel and of the intermission
    -- panel, plus its short tooltip. The label is translated here, never written
    -- as a literal in the rendering layer.
    ["ui.closeCross"] = {
        en = "X",
        fr = "X",
    },
    ["ui.closeTooltip"] = {
        en = "Close",
        fr = "Fermer",
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
        en = "Intermission Coach disabled (/gideon inter on to enable it).",
        fr = "Intermission Coach desactive (/gideon inter on pour l'activer).",
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
    ["ui.soundLine"] = {
        en = "assignment sound: %s (one soundboard per composition, /gideon sound on|off)",
        fr = "son d'assignation : %s (un son par composition, /gideon sound on|off)",
    },
    -- WHICH BOSS opens the panel by itself (`/gideon inter status`): the auto-open
    -- target of the allow-list and the state of the idlog. The safe default (no
    -- target) reads as is: NOTHING opens by itself.
    ["ui.bossLine"] = {
        en = "auto-open target: %s (encounter id log: %s, /gideon boss)",
        fr = "cible de l'ouverture auto : %s (journal des ids d'encounter : %s, /gideon boss)",
    },

    -- -------------------------------------------- placement mode (before pull)
    -- NO KEY HERE ANY MORE. The placement panel used to carry a title
    -- ("BEFORE THE PULL - PLACE THE PANEL"), a drag reminder, the ping keybind
    -- procedure and the plan line, plus the "OK" label of its validation button.
    -- The raid lead asked for the panel to show the ILLUSTRATION and nothing
    -- else, so the whole block was DELETED (with ui.panelTitle and ui.ok): a
    -- string that no longer exists can not come back on screen by accident.
    -- The placement is validated by `/gideon inter ok` (ui.setupDone says so).

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
    --   1V3R = ANCHOR  : does not move, PINGS ITSELF with the native keybind by
    --                    hovering ITS OWN character frame (measured in game: the
    --                    ping lands under the mouse, so hovering your own frame
    --                    pings yourself) - or is pinged by another player;
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
    -- The ANCHOR action line states the REAL gesture, step by step, and it is now
    -- a MEASURED fact: hovering your own character frame (the unit frame with
    -- your health bar) then pressing the ping key displays the ping ON YOURSELF
    -- (confirmed in game by the raid lead, fifth in-game test: "the ping on the
    -- health bar works fine to show it on myself"). The line stays SHORT and
    -- actionable: what to hover, which key, what it does, what to do next.
    -- %s = the label of the ping to use (Warning / Avertissement).
    ["state.actionPing.1V3R"] = {
        en = "PING: YES - hover YOUR OWN character frame (your health bar) then press your ping key (%s): you ping "
            .. "yourself, stay put and jump on the spot",
        fr = "PING : OUI - survole TON propre cadre de personnage (ta barre de vie) puis appuie sur ta touche de ping "
            .. "(%s) : tu te pinges toi-meme, reste sur place et saute sur place",
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

    -- THE ONE WORD the intermission panel writes after a click (raid-lead
    -- wording, EN = the official labels, FR = the raid lead's own words). It is
    -- the ONLY text of the panel: no state line, no role line, no action line,
    -- no key reminder. "BOSS" is upper case in BOTH languages on purpose (the
    -- raid lead's convention), and it is drawn with the biggest font of the
    -- window; "Ping" and "Chasseur" are drawn in the theme green.
    ["state.word.1V3R"] = {
        en = "Ping",
        fr = "Ping",
    },
    ["state.word.2V2R"] = {
        en = "Boss",
        fr = "BOSS",
    },
    ["state.word.3V1R"] = {
        en = "Chaser",
        fr = "Chasseur",
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

    -- ------------------------------------------------------------- simulation
    -- SIMULATION MODE (rehearsal alone, no boss, no raid). The banner is
    -- displayed on every simulation surface so a rehearsal is never mistaken for
    -- a real fight. Honest wording: the addon NEVER claims to have detected a
    -- ping (no API reports one) and never claims an automatic action.
    ["sim.banner"] = {
        en = "SIMULATION - NO BOSS, NO RAID",
        fr = "SIMULATION - SANS BOSS, SANS RAID",
    },
    -- The rehearsal is a SINGLE cycle and the PLAYER closes it (fourth in-game
    -- test): the banner keeps two lines so it can never be mistaken for a fight,
    -- and no line counts anything down any more.
    ["sim.singleLine"] = {
        en = "SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF",
        fr = "REPETITION UNIQUE - TU FERMES LE PANNEAU TOI-MEME",
    },
    -- The rehearsal REPLACES the combat headline ("LOOK AT THE ORB COLOR...: 3 s").
    -- Without a boss there is no orb to read and no clock: the line stays useful
    -- instead of contradicting what the player sees.
    ["sim.rehearsal.headline"] = {
        en = "SIMULATION: NO ORB TO READ - CLICK THE COMPOSITION YOU SEE ABOVE YOUR HEAD",
        fr = "SIMULATION : AUCUN ORBE A LIRE - CLIQUE LA COMPOSITION AU-DESSUS DE TA TETE",
    },
    ["sim.rehearsal.note"] = {
        en = "Rehearsal: in a real fight this line counts the seconds left to read the orb color. Here there "
            .. "is no boss: close this panel yourself (X or Close) when you are done.",
        fr = "Repetition : en vrai combat cette ligne compte les secondes restantes pour lire la couleur des "
            .. "orbes. Ici il n'y a pas de boss : ferme ce panneau toi-meme (croix ou Fermer) quand tu as fini.",
    },
    ["sim.notOpen"] = {
        en = "the rehearsal is not open any more: start it again with /gideon sim inter",
        fr = "la repetition n'est plus ouverte : relance-la avec /gideon sim inter",
    },
    ["sim.refused.live"] = {
        en = "Simulation refused: the real flow is running (intermission in progress or ENCOUNTER_START "
            .. "timeline armed). Finish it first (/gideon inter stop).",
        fr = "Simulation refusee : le flux reel tourne (intermission en cours ou planning ENCOUNTER_START "
            .. "arme). Termine-le d'abord (/gideon inter stop).",
    },
    ["sim.refused.running"] = {
        en = "Refused: a simulation is already running (/gideon sim stop).",
        fr = "Refuse : une simulation tourne deja (/gideon sim stop).",
    },
    ["sim.stoppedByEncounter"] = {
        en = "Encounter started: the simulation is stopped. No boss was simulated.",
        fr = "Combat commence : la simulation est arretee. Aucun boss n'a ete simule.",
    },
    -- PING HELP: a SHORT information window (no sequence, no countdown, no
    -- "ping placed" button). It explains how to bind the keys (Options >
    -- Keybindings > Ping) and the operational reminder: during the boss, when the
    -- panel says PING: YES, you ping YOURSELF by hovering your own character
    -- frame. HONESTY: the addon never sends a ping, can NOT detect one (no game
    -- API reports it), and a ping only shows on screen while the player is in a
    -- group or a raid.
    ["sim.ping.title"] = {
        en = "GideonRaid - Ping help (ping yourself)",
        fr = "GideonRaid - Aide au ping (te pinger)",
    },
    ["sim.ping.helpHeadline"] = {
        en = "PING: YES = PING YOURSELF",
        fr = "PING : OUI = PINGE-TOI TOI-MEME",
    },
    ["sim.ping.helpBind"] = {
        en = "1. Bind one key per ping: Options > Keybindings > Ping " .. "(Ping, Warning, On My Way, Assist).",
        fr = "1. Bind une touche par ping : Options > Raccourcis > Ping " .. "(Ping, Attaque, Avertissement, En route, Aide).",
    },
    ["sim.ping.helpGesture"] = {
        en = "2. During the boss, when this panel says PING: YES, hover YOUR OWN character frame (the one with "
            .. "your health bar) then press your key: you ping yourself, where you stand.",
        fr = "2. Pendant le boss, quand ce panneau dit PING : OUI, survole TON propre cadre de personnage "
            .. "(celui avec ta barre de vie) puis appuie sur ta touche : tu te pinges toi-meme, sur place.",
    },
    ["sim.ping.keysHeader"] = {
        en = "Keys found for your pings:",
        fr = "Touches trouvees pour tes pings :",
    },
    ["sim.ping.keyLine"] = {
        en = "%s = %s",
        fr = "%s = %s",
    },
    ["sim.ping.noKeyLine"] = {
        en = "%s = no key bound (Options > Keybindings > Ping)",
        fr = "%s = aucune touche bindee (Options > Raccourcis > Ping)",
    },
    ["sim.ping.anchorNote"] = {
        en = "This is exactly the ANCHOR (1V3R) gesture during the intermission: ping yourself where you stand.",
        fr = "C'est exactement le geste de l'ANCRE (1V3R) pendant l'intermission : ping-toi la ou tu te tiens.",
    },
    ["sim.ping.group"] = {
        en = "REMINDER: pings only show on screen while you are in a GROUP or a RAID. Alone, nothing appears.",
        fr = "RAPPEL : les pings ne s'affichent a l'ecran que si tu es en GROUPE ou en RAID. Seul, rien n'apparait.",
    },
    ["sim.ping.noDetection"] = {
        en = "The addon CANNOT detect a ping: no game API reports one. Only you can check your screen.",
        fr = "L'addon NE PEUT PAS detecter un ping : aucune API du jeu ne le rapporte. Toi seul peux verifier ton ecran.",
    },

    -- --------------------------------------------------------------- errors
    ["err.invalidSimulation"] = {
        en = "invalid simulation (table expected)",
        fr = "simulation invalide (table attendue)",
    },
    -- The intermission rehearsal no longer takes ANY option: it opens right away
    -- and the PLAYER closes it (fourth in-game test). A trailing token is
    -- therefore REFUSED, never silently ignored.
    ["err.simNoOption"] = {
        en = "no option here: the rehearsal opens right away and YOU close it (the former cycles=N is gone)",
        fr = "aucune option ici : la repetition s'ouvre tout de suite et c'est TOI qui la fermes (l'ancien cycles=N a disparu)",
    },
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

    -- ============================================================ STYLE SHOWCASE
    -- The in-game SURFACE where the raid lead sees what the design can do
    -- (typography, palette, states, frame styles, animations) and CHOOSES. It
    -- only exists in SIMULATION mode: the combat panel never shows it.
    ["ui.placementOk"] = {
        en = "OK",
        fr = "OK",
    },
    ["ui.showcaseTitle"] = {
        en = "STYLE SHOWCASE - SIMULATION ONLY",
        fr = "VITRINE DE STYLE - SIMULATION SEULEMENT",
    },
    ["showcase.hint"] = {
        en = "Wheel = scroll. Click a composition to get the giant word + the sound.",
        fr = "Molette = defiler. Clique une composition pour le mot geant + le son.",
    },
    ["showcase.liveHeader"] = {
        en = "1 - THE THREE COMPOSITIONS (as in combat)",
        fr = "1 - LES TROIS COMPOSITIONS (comme en combat)",
    },
    ["showcase.liveNote"] = {
        en = "Click one: the three cards give way to ONE word in the biggest font, and the assignment " .. "soundboard plays once.",
        fr = "Clique : les trois encarts laissent la place a UN seul mot dans la plus grosse police, et le "
            .. "son d'assignation part une fois.",
    },
    ["showcase.typoHeader"] = {
        en = "2 - TYPOGRAPHY (every size the addon really uses)",
        fr = "2 - TYPOGRAPHIE (toutes les tailles reellement utilisees)",
    },
    ["showcase.typoNote"] = {
        en = "The line under each sample gives the real size and where it comes from.",
        fr = "La ligne sous chaque exemple donne la taille reelle et son origine.",
    },
    ["showcase.typoSize"] = {
        en = "%s %d px - %s",
        fr = "%s %d px - %s",
    },
    ["showcase.typoExplicit"] = {
        en = "explicit SetFont (FRIZQT__.TTF)",
        fr = "SetFont explicite (FRIZQT__.TTF)",
    },
    ["showcase.typoObject"] = {
        en = "Blizzard font object (size estimated out of game)",
        fr = "objet de police Blizzard (taille estimee hors jeu)",
    },
    ["showcase.typoGreen"] = {
        en = "GREEN variant (shipped)",
        fr = "variante VERTE (livree)",
    },
    ["showcase.typoCyan"] = {
        en = "GIDEON CYAN variant (to decide)",
        fr = "variante CYAN GIDEON (a trancher)",
    },
    ["showcase.typoChrome"] = {
        en = "GIDEON CHROME",
        fr = "CHROME GIDEON",
    },
    ["showcase.statesHeader"] = {
        en = "3 - ONE CARD, THREE STATES",
        fr = "3 - UN ENCART, TROIS ETATS",
    },
    ["showcase.statesNote"] = {
        en = "Hover the second card and press-and-hold the third one: the BORDER lights up and nothing else moves.",
        fr = "Survole le deuxieme encart et maintiens le clic sur le troisieme : la BORDURE s'allume, rien d'autre ne bouge.",
    },
    ["showcase.stateRest"] = {
        en = "NORMAL - at rest, border #%s",
        fr = "NORMAL - au repos, bordure #%s",
    },
    ["showcase.stateHover"] = {
        en = "HOVER - move the mouse over this card, border #%s",
        fr = "SURVOL - passe la souris sur cet encart, bordure #%s",
    },
    ["showcase.statePressed"] = {
        en = "PRESSED - click and hold this card, border #%s",
        fr = "APPUI - clique et maintiens cet encart, bordure #%s",
    },
    ["showcase.paletteHeader"] = {
        en = "4 - PALETTE OF THE PANEL TODAY",
        fr = "4 - PALETTE DU PANNEAU AUJOURD'HUI",
    },
    ["showcase.paletteNote"] = {
        en = "Role + exact hex of every colour the intermission panel writes today: dictate a change, "
            .. "it is ONE constant in Core/Layout.lua.",
        fr = "Role + code hexadecimal exact de chaque couleur ecrite par le panneau : dicte un changement, "
            .. "c'est UNE constante dans Core/Layout.lua.",
    },
    ["showcase.paletteGideonHeader"] = {
        en = "4b - GIDEON PALETTE (delivered constants)",
        fr = "4b - PALETTE GIDEON (constantes livrees)",
    },
    ["showcase.paletteGideonNote"] = {
        en = "Same roles, GIDEON values: dictate a change and it is ONE constant in Core/Layout.lua.",
        fr = "Memes roles, valeurs GIDEON : dicte un changement, c'est UNE constante dans Core/Layout.lua.",
    },
    ["showcase.stylesHeader"] = {
        en = "5 - THE GUILD CARD (the only style)",
        fr = "5 - L'ENCART DE LA GUILDE (le seul style)",
    },
    ["showcase.stylesNote"] = {
        en = "Option 1 of your board became the guild card: a 1 px border, a discreet dark fill, and the "
            .. "GIDEON palette - gold at rest, cyan under the mouse, bright gold while pressed. The candidate "
            .. "gallery is gone; what is shown here is exactly what a fight draws.",
        fr = "L'option 1 de ta planche est devenue l'encart de la guilde : bordure de 1 px, fond sombre "
            .. "discret et palette GIDEON - or au repos, cyan au survol, or vif a l'appui. La galerie de "
            .. "candidats a disparu ; ce qui est montre ici est exactement ce qu'un combat dessine.",
    },
    ["showcase.stylesCurrent"] = {
        en = "The COMBAT panel draws exactly this card right now: %s.",
        fr = "Le panneau de COMBAT dessine exactement cet encart maintenant : %s.",
    },
    ["showcase.styleCaption"] = {
        en = "%s (border #%s, background #%s)",
        fr = "%s (bordure #%s, fond #%s)",
    },
    ["showcase.animHeader"] = {
        en = "6 - ANIMATIONS",
        fr = "6 - ANIMATIONS",
    },
    ["showcase.animLine"] = {
        en = "showcase animations: %s (fade-in of the panel + pulse of the first card border) - " .. "/gideon sim anim on|off",
        fr = "animations de la vitrine : %s (fondu d'apparition du panneau + pulsation de la bordure du "
            .. "premier encart) - /gideon sim anim on|off",
    },
    ["showcase.animNote"] = {
        en = "They only ever run HERE: no animation is wired into the combat panel (/gideon inter, /gideon sim inter).",
        fr = "Elles ne tournent QUE ici : aucune animation n'est branchee sur le panneau de combat (/gideon inter, /gideon sim inter).",
    },
    ["showcase.opened"] = {
        en = "SIMULATION (no boss, no raid): STYLE SHOWCASE open. Wheel = scroll, click a composition.",
        fr = "SIMULATION (pas de boss, pas de raid) : VITRINE DE STYLE ouverte. Molette = defiler, clique une composition.",
    },
    ["showcase.closed"] = {
        en = "Style showcase closed.",
        fr = "Vitrine de style fermee.",
    },
    ["showcase.notOpen"] = {
        en = "the style showcase is not open (/gideon sim style).",
        fr = "la vitrine de style n'est pas ouverte (/gideon sim style).",
    },
    ["showcase.animUpdated"] = {
        en = "Showcase animations: %s (persisted).",
        fr = "Animations de la vitrine : %s (persiste).",
    },
    -- THE ONE CARD OF THE GUILD. The candidate gallery (2..6, `card`, `gideon`) is
    -- gone: `style.1` is the thin card of option 1, painted with the GIDEON palette.
    ["style.1"] = {
        en = "guild card (thin border)",
        fr = "encart de la guilde (bordure fine)",
    },
    ["palette.background"] = {
        en = "BACKGROUND - fill of the cards",
        fr = "FOND - interieur des encarts",
    },
    ["palette.border"] = {
        en = "BORDER - card edge at rest",
        fr = "BORDURE - bord de l'encart au repos",
    },
    ["palette.accent"] = {
        en = "ACCENT - PING / CHASER words",
        fr = "ACCENT - mots PING / CHASSEUR",
    },
    ["palette.textMain"] = {
        en = "MAIN TEXT - the BOSS word",
        fr = "TEXTE PRINCIPAL - le mot BOSS",
    },
    ["palette.textSecondary"] = {
        en = "SECONDARY TEXT - SIMULATION banner",
        fr = "TEXTE SECONDAIRE - bandeau SIMULATION",
    },
    ["palette.alert"] = {
        en = "ALERT - the RED ping",
        fr = "ALERTE - le ping ROUGE",
    },
    ["palette.gideon.NIGHT"] = {
        en = "NIGHT - darkest fill",
        fr = "NIGHT - fond le plus sombre",
    },
    ["palette.gideon.PANEL"] = {
        en = "PANEL - night-blue glass",
        fr = "PANEL - verre bleu nuit",
    },
    ["palette.gideon.ROYAL"] = {
        en = "ROYAL - shaded flats",
        fr = "ROYAL - aplats ombres",
    },
    ["palette.gideon.CYAN"] = {
        en = "CYAN - glow, hover, PING / CHASER",
        fr = "CYAN - lueur, survol, PING / CHASSEUR",
    },
    ["palette.gideon.GOLD"] = {
        en = "GOLD - filigree, border at rest",
        fr = "GOLD - filigrane, bordure au repos",
    },
    ["palette.gideon.GOLD_HI"] = {
        en = "GOLD_HI - highlight, hover, pressed",
        fr = "GOLD_HI - eclat, survol, appui",
    },
    ["palette.gideon.CHROME"] = {
        en = "CHROME - main text, BOSS",
        fr = "CHROME - texte principal, BOSS",
    },
    ["palette.gideon.MUTED"] = {
        en = "MUTED - secondary text",
        fr = "MUTED - texte secondaire",
    },
    ["cmd.style.status"] = {
        en = "intermission panel style: %s - the guild card is the ONLY style (%s), there is nothing left to choose.",
        fr = "style du panneau d'intermission : %s - l'encart de la guilde est le SEUL style (%s), il n'y a plus rien a choisir.",
    },
    ["cmd.style.updated"] = {
        en = "Intermission panel style set to %s (persisted - it is the only style).",
        fr = "Style du panneau d'intermission regle sur %s (persiste - c'est le seul style).",
    },
    ["cmd.style.unknown"] = {
        en = "unknown style: %s (the guild card is the only style: expected 1 or shipped)",
        fr = "style inconnu : %s (l'encart de la guilde est le seul style : attendu 1 ou shipped)",
    },
    ["cmd.style.help"] = {
        en = "/gideon style [1|shipped]: style of the COMBAT intermission panel - ONE single style, nothing to choose (persisted)",
        fr = "/gideon style [1|shipped] : style du panneau d'intermission en COMBAT - UN SEUL style, rien a choisir (persiste)",
    },
    ["cmd.sim.style"] = {
        en = "/gideon sim style [1|shipped]: opens the STYLE SHOWCASE (simulation only, no boss)",
        fr = "/gideon sim style [1|shipped] : ouvre la VITRINE DE STYLE (simulation seulement, sans boss)",
    },
    ["cmd.sim.anim"] = {
        en = "/gideon sim anim on|off: showcase animations (fade-in + pulse), persisted",
        fr = "/gideon sim anim on|off : animations de la vitrine (fondu + pulsation), persiste",
    },
    ["cmd.sim.animState"] = {
        en = "showcase animations: %s (persisted, default on)",
        fr = "animations de la vitrine : %s (persistees, actives par defaut)",
    },
    ["cmd.sim.styleUnknown"] = {
        en = "unknown style: %s (the guild card is the only style: expected 1 or shipped)",
        fr = "style inconnu : %s (l'encart de la guilde est le seul style : attendu 1 ou shipped)",
    },
    ["cmd.sim.animUsage"] = {
        en = "usage: /gideon sim anim on|off (unknown value refused)",
        fr = "usage : /gideon sim anim on|off (valeur inconnue refusee)",
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
