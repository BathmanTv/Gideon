--[[--------------------------------------------------------------------------
    GideonRaid / Core / Config.lua

    Default values + SavedVariables initialization + resolution of the
    "Intermission Coach" module configuration. No business logic.

    No WoW API here: this file reads only tables and numbers, and
    `resolveIntermission` receives the raw table as a PARAMETER (the wiring
    passes it GideonRaidDB.intermission).
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: the language layer is
--- a hard dependency (the persisted preference is normalized against it).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Config.lua")

--- Core/Sound.lua is loaded BEFORE this file by the .toc: it owns the pure table
--- "canonical state -> soundboard file", the one-playback-per-assignment gate
--- and the BOUNDED resolvers of the assignment-sound preference (/gr sound).
local Sound = assert(ns.Sound, "Core/Sound.lua must be loaded before Core/Config.lua")

--- Core/BossFilter.lua is loaded BEFORE this file by the .toc: it owns the
--- allow-list of encounter ids (PRIMARY criterion, `/gr boss <id>`) and of names
--- (SECONDARY, language dependent), the bounded resolvers of the auto-open filter
--- and the SAFE DEFAULT (an empty list opens nothing).
local BossFilter = assert(ns.BossFilter, "Core/BossFilter.lua must be loaded before Core/Config.lua")

local Config = {}
ns.Config = Config

Config.MIN_SCALE = 0.5
Config.MAX_SCALE = 3.0

--- PING POLICIES accepted by the module (persisted preference `pingMode`).
--- SORTED list, no pairs() anywhere (determinism):
---   "anchors" (DEFAULT, raid-lead decision): only the 1V3R ANCHORS ping, one
---      ping per anchor -> about 8 pings per raid instead of ~20. 3V1R CHASERS
---      and 2V2R MIDDLE players never ping;
---   "color": raidstrats guide variant, every state pings with its own color
---      (1V3R = red/Warning, 2V2R = blue/OnMyWay, 3V1R = green/Assist);
---   "none": nobody pings at all, the raid plays on positions only.
Config.PING_MODES = { "anchors", "color", "none" }

--- Default ping policy: the raid lead's decision ("anchors").
Config.DEFAULT_PING_MODE = "anchors"

--- Pre-computed intermission timeline, in SECONDS SINCE ENCOUNTER_START (the pull
--- is the time origin). Values measured on the real encounter by the raid lead:
--- the first intermission lands ~46 s after the pull, then every ~102.6 s.
--- Prepared by hand and persisted: GIDEON can overwrite it out of game.
--- https://warcraft.wiki.gg/wiki/ENCOUNTER_START (arguments never read).
Config.DEFAULT_SCHEDULE_SECONDS = { 46.3, 148.9, 251.5, 353.2 }

--- How many seconds BEFORE each intermission the panel opens by itself.
Config.DEFAULT_LEAD_SECONDS = 2

--- Maximum number of intermissions kept from a persisted schedule (a hand-edited
--- SavedVariables must never produce an unbounded loop).
Config.MAX_SCHEDULE_ENTRIES = 12

--- ENCOUNTER ID OF THE TARGET BOSS, DELIVERED WITH THE ADDON (raid-lead decision):
--- the intermission panel opens on this boss for EVERY player of the guild, with no
--- command to type. MEASURED IN GAME by the raid lead on 2026-09-24, heroic pull
--- with 20 players (`/gr idlog on`):
---   encounter seen: id=3445  name=Sentinelles inhumées  difficulty=15  group=20
--- `ENCOUNTER_START` arg1 is an INTEGER, identical on every client whatever the
--- game language: it is the PRIMARY criterion of the auto-open filter
--- (`Core/BossFilter.lua`, `/gr boss <id>` adds more ids).
Config.DEFAULT_BOSS_IDS = { 3445 }

--- NAMES OF THE TARGET BOSS, as a SECONDARY criterion (a SAFETY NET: the id above
--- is what decides, a name never opens the panel on its own when the id of the
--- encounter is readable). TWO names, because the encounter name is translated by
--- the client and both clients are served:
---   - "Entombed Sentinels"   : the official English name;
---   - "Sentinelles inhumées" : the FRENCH name, copied EXACTLY from the idlog line
---     measured in game on 2026-09-24 (cf. Config.DEFAULT_BOSS_IDS). THE ACCENT IS
---     PART OF THE STRING: this file is UTF-8 and the name is compared
---     case-insensitively as-is, never translated nor re-accented.
--- `/gr boss name <text>` adds more names.
Config.DEFAULT_BOSS_NAMES = { "Entombed Sentinels", "Sentinelles inhumées" }

--- The DIFFICULTY IDS of the target boss, documented for the raid lead. The addon
--- DELIBERATELY does not filter on the difficulty: the raid lead plays Heroic (15)
--- today and Mythic (16) later, and EVERY difficulty must open the panel. The
--- difficulty an encounter was pulled on is only LOGGED by the idlog - it NEVER
--- takes part in the decision. If a difficulty filter is ever asked for,
--- `BossFilter.evaluate` is the ONE place to add it.
---   https://warcraft.wiki.gg/wiki/DifficultyID  (retail)
---   14 = Raid Normal      15 = Raid Heroic     16 = Raid Mythic     17 = Raid LFR
Config.BOSS_DIFFICULTIES = { 14, 15, 16, 17 }

--- Anchor points accepted when reading a PERSISTED panel position. A hand-edited
--- SavedVariables holding an unknown point name would make the client raise on
--- SetPoint: the resolver only ever returns a value from this list.
Config.POSITION_POINTS = {
    "CENTER",
    "TOP",
    "BOTTOM",
    "LEFT",
    "RIGHT",
    "TOPLEFT",
    "TOPRIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
}

--- Default of the BOUNDED auto-close safety delay (seconds), MEASURED on the
--- real timings of the target boss: 2 s of lead (the panel opens before the
--- intermission) + 3 s of visibility + 20 s of intermission = a 25 s window,
--- plus a 5 s margin. MIRROR of Intermission.DEFAULT_AUTO_CLOSE_SECONDS and of
--- Intermission.AUTO_CLOSE_MARGIN_SECONDS (tests/spec/intermission_spec.lua
--- asserts the two modules agree, so they can never drift apart).
Config.DEFAULT_AUTO_CLOSE_SECONDS = 30

--- Bounds of the resolved auto-close delay. Below the minimum the panel could
--- vanish in the MIDDLE of a real intermission; above the maximum a hand-edited
--- SavedVariables could park it on screen for minutes.
Config.MIN_AUTO_CLOSE_SECONDS = 5
Config.MAX_AUTO_CLOSE_SECONDS = 300

--- SavedVariables schema of the PANEL preferences (position + lock). Bumped when
--- a migration has to run once: see Config.ensureDB.
Config.PANEL_SCHEMA = 1

Config.DEFAULTS = {
    enabled = true,
    autoShow = true,
    scale = 1.0,
    -- The main panel is MOVABLE BY DEFAULT (in-game feedback: a panel the player
    -- cannot move is unusable). /gr lock freezes it, /gr unlock frees it again.
    -- Any other value than a boolean counts as "not locked".
    lockPanel = false,
    -- Language preference of the player: "auto" (follow the client), "en", "fr".
    locale = Locale.AUTO,
    -- Block published by GIDEON out of game (see docs/TESTPLAN.md, step 4).
    assignment = nil,
}

--- Default values of the "Intermission Coach" module.
--- This is a FUNCTION, not a constant: returning the same table shared between
--- two characters (or between two /reload) would create a SavedVariables alias,
--- hence a silent bug as soon as a player moves the panel.
--- The ns.Intermission module (loaded AFTER this file in the .toc) documents the
--- same duration: Core/Intermission.lua -> VISIBILITY_SECONDS = 3.
function Config.defaultIntermission()
    return {
        enabled = true,
        startOnEncounterStart = true,
        autoShowPanel = true,
        scale = 1.0,
        -- The panel opens `leadSeconds` BEFORE the intermission so the player
        -- reads the three choices before the orbs appear.
        leadSeconds = Config.DEFAULT_LEAD_SECONDS,
        visibilitySeconds = 3,
        durationSeconds = 20,
        -- BOUNDED AUTO-CLOSE (see Core/Intermission.newCloseGuard): the safety
        -- delay after which the panel is hidden even when the intermission clock
        -- never reached DONE. Measured on the real timings of the target boss
        -- (2 s of lead + 3 s of visibility + 20 s of intermission = 25 s, plus a
        -- 5 s margin). It is CONFIGURABLE (this field) and CLAMPED by
        -- resolveIntermission, so a hand-edited SavedVariables can neither make
        -- the panel vanish during a real intermission nor park it on screen.
        autoCloseSeconds = Config.DEFAULT_AUTO_CLOSE_SECONDS,
        -- Pre-computed intermission schedule, in seconds since ENCOUNTER_START.
        scheduleSeconds = Config.defaultScheduleSeconds(),
        -- Ping policy (see Config.PING_MODES): the raid-lead decision, persisted
        -- and changeable in game with /gr ping anchors|color|none.
        pingMode = Config.DEFAULT_PING_MODE,
        -- CARD STYLE of this panel (raid-lead picker, `/gr style [1|shipped]`): the
        -- guild card by default, and the ONLY style there is. Core/Layout.
        -- BUTTON_STYLES owns the styles, this field only NAMES the one in use.
        style = Config.DEFAULT_STYLE,
        -- STYLE SHOWCASE (`/gr sim style`): the style its examples are drawn with -
        -- the guild card (there is no candidate left), and its two animations. The
        -- animations are ON by default (the raid lead asked to SEE them) and only
        -- an explicit false stops them.
        showcaseStyle = Config.DEFAULT_STYLE,
        showcaseAnimations = true,
        -- ASSIGNMENT SOUNDBOARD (see Core/Sound.lua): enabled by default, one
        -- sound per canonical state, played ONCE when the player declares their
        -- composition. /gr sound on|off, /gr sound test 1v3r|2v2r|3v1r.
        soundEnabled = Sound.DEFAULT_ENABLED,
        -- AUTO-OPEN FILTER (see Core/BossFilter.lua): WHICH boss may open the
        -- panel by itself. The DELIVERED default (Config.DEFAULT_BOSS_IDS /
        -- Config.DEFAULT_BOSS_NAMES: encounter id 3445 + the two names of the
        -- target boss) applies as soon as the player has NOT explicitly cleared the
        -- target, so the panel opens on Entombed Sentinels for the whole guild with
        -- no command typed at all.
        -- These two lists hold ONLY what a PLAYER added (`/gr boss <id>`, `/gr boss
        -- name <text>`); the EFFECTIVE target (delivered default + these entries)
        -- is computed at read time by Config.resolveIntermission.
        bossIds = {},
        bossNames = {},
        -- `/gr boss clear` MARKER. An exact `true` means the player EXPLICITLY
        -- emptied the target, so the DELIVERED default must NOT come back: only
        -- what the player adds afterwards counts (an explicit clear always wins
        -- over the delivered default). An ABSENT field (a fresh install, an older
        -- SavedVariables) is `false`: never configured = the delivered default
        -- applies.
        bossTargetCleared = false,
        -- `/gr idlog on|off`: prints and memorizes the encounters seen, which is
        -- how the real id of the target boss is captured in game.
        idlog = false,
        -- MANUAL OVERRIDE (`/gr inter on`): arms the panel for the NEXT encounter
        -- whatever the boss; consumed at the end of that encounter.
        overrideEncounter = false,
        -- The last encounters seen by the idlog (newest first, bounded).
        seenEncounters = {},
        position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    }
end

--- Fresh copy of the default schedule (never a shared table: a caller mutating
--- the returned list must not corrupt the defaults of the next character).
function Config.defaultScheduleSeconds()
    local out = {}
    for index = 1, #Config.DEFAULT_SCHEDULE_SECONDS do
        out[index] = Config.DEFAULT_SCHEDULE_SECONDS[index]
    end
    return out
end

--- PURE normalization of a prepared schedule: keeps positive numbers only,
--- sorts them ASCENDING (deterministic, no pairs()) and caps the number of
--- entries. A missing/absurd value never raises and never yields an empty list
--- (fallback: the default schedule).
--- @param raw table|nil persisted schedule (seconds since ENCOUNTER_START)
--- @return table sorted copy of numbers
function Config.resolveSchedule(raw)
    local out = {}
    if type(raw) == "table" then
        for index = 1, #raw do
            local value = tonumber(raw[index])
            if value ~= nil and value > 0 then
                out[#out + 1] = value
            end
        end
    end
    if #out == 0 then
        return Config.defaultScheduleSeconds()
    end
    table.sort(out)
    while #out > Config.MAX_SCHEDULE_ENTRIES do
        table.remove(out)
    end
    return out
end

--- Fresh copy of the DEFAULT panel position (never a shared table: two characters
--- must not alias the same position). Used by the main panel, the intermission
--- panel and the ping-training frame.
--- @return table { point, relativePoint, x, y }
function Config.defaultPanelPosition()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
end

--- PURE resolution of the persisted LOCK preference (GideonRaidDB.lockPanel).
--- true = the player froze the panels, false = they can be dragged. Anything else
--- - absent, string, number, table, hand-edited SavedVariables - means NOT
--- locked: the resolver is total, it never raises and never returns nil.
--- @param raw boolean|any
--- @return boolean
function Config.resolveLockPanel(raw)
    return raw == true
end

--- PURE normalization of a persisted panel position (point / relativePoint / x /
--- y). Only a KNOWN anchor point is kept (an unknown name would make the client
--- raise on SetPoint), the coordinates must be numbers: anything else falls back
--- to the centered default. Total: never raises, never returns nil.
--- @param raw table|nil raw position block
--- @return table { point, relativePoint, x, y }
function Config.resolvePosition(raw)
    local out = Config.defaultPanelPosition()
    if type(raw) ~= "table" then
        return out
    end
    local wanted = type(raw.point) == "string" and raw.point:upper() or nil
    for index = 1, #Config.POSITION_POINTS do
        if wanted == Config.POSITION_POINTS[index] then
            out.point = wanted
            break
        end
    end
    local relative = type(raw.relativePoint) == "string" and raw.relativePoint:upper() or nil
    for index = 1, #Config.POSITION_POINTS do
        if relative == Config.POSITION_POINTS[index] then
            out.relativePoint = relative
            break
        end
    end
    if type(raw.x) == "number" then
        out.x = raw.x
    end
    if type(raw.y) == "number" then
        out.y = raw.y
    end
    return out
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

--- Creates the SavedVariables table with the default values (non-destructive call).
--- Also runs the ONE-TIME soft migration of the panel preferences:
---   - a SavedVariables written by an older version carries `lockPanel = true`
---     (the old hard-coded default, which no player could change: no command
---     existed then), and no `panelSchema` marker. It is unlocked ONCE, then the
---     player's own choice (/gr lock, /gr unlock, the panel button) is preserved;
---   - a value that is not a boolean never raises: it counts as "not locked".
--- The panel positions are created fresh (never aliased between characters).
function Config.ensureDB(db)
    db = db or {}
    for k, v in pairs(Config.DEFAULTS) do
        if db[k] == nil then
            db[k] = v
        end
    end
    if db.panelSchema ~= Config.PANEL_SCHEMA then
        db.lockPanel = false
        db.panelSchema = Config.PANEL_SCHEMA
    else
        db.lockPanel = Config.resolveLockPanel(db.lockPanel)
    end
    if type(db.panelPosition) ~= "table" then
        db.panelPosition = Config.defaultPanelPosition()
    end
    if type(db.pingPanelPosition) ~= "table" then
        db.pingPanelPosition = Config.defaultPanelPosition()
    end
    -- The STYLE SHOWCASE is draggable too (it is a window like the others): its
    -- position is created fresh here, so two characters never share one.
    if type(db.showcasePosition) ~= "table" then
        db.showcasePosition = Config.defaultPanelPosition()
    end
    if type(db.intermission) ~= "table" then
        db.intermission = Config.defaultIntermission()
    end
    return db
end

--- Resolves the persisted language preference (GideonRaidDB.locale).
--- Accepted values: "auto" (default), "en", "fr". Anything else - absent,
--- mistyped, hand-edited SavedVariables - falls back to "auto".
--- Pure: no API, no clock.
--- @param raw string|nil raw GideonRaidDB.locale value
--- @return string "auto", "en" or "fr"
function Config.resolveLocale(raw)
    local wanted = (type(raw) == "string") and raw:lower() or ""
    for index = 1, #Locale.PREFERENCES do
        local candidate = Locale.PREFERENCES[index]
        if wanted == candidate then
            return candidate
        end
    end
    return Locale.AUTO
end

--- THE STYLE OF THE INTERMISSION CARDS: the DELIVERED default, and a MIRROR of the
--- style names of Core/Layout.BUTTON_STYLES.
--- WHY A MIRROR: the .toc loads Core/Layout.lua LAST among the Core modules (it
--- measures the strings of Locale and Config), so this file cannot ask it for the
--- list. tests/spec/showcase_spec.lua asserts that this mirror is EXACTLY the key
--- set of Layout.BUTTON_STYLES: a style added in Core and forgotten here fails a
--- test instead of becoming silently unusable - and, since 2026-09-25, it also
--- asserts that BOTH hold exactly ONE entry (the guild card), so no surface can
--- ever offer a choice again.
Config.DEFAULT_STYLE = "1" -- delivered style: the guild card (thin border + GIDEON palette, raid-lead decision 2026-09-25)
Config.STYLE_NAMES = { "1" }

--- Resolves a PERSISTED style name. Accepted: one of Config.STYLE_NAMES, case and
--- spaces insensitive. Anything else - absent, empty, mistyped, a number, a table,
--- a hand-edited SavedVariables, or an OLD style that no longer exists (`gideon`,
--- `card`, `2`..`6`) - falls back to the DELIVERED style: PURE and TOTAL, it never
--- raises and never returns nil, so the layout is always handed a style it knows
--- and an old save rolls back on the guild card without an error.
--- @param raw string|nil raw GideonRaidDB.intermission.style value
--- @return string canonical style name
function Config.resolveStyleName(raw)
    local wanted = type(raw) == "string" and raw:lower():gsub("%s+", "") or ""
    for index = 1, #Config.STYLE_NAMES do
        if wanted == Config.STYLE_NAMES[index] then
            return wanted
        end
    end
    return Config.DEFAULT_STYLE
end

--- Resolves the PERSISTED PING POLICY (GideonRaidDB.intermission.pingMode).
--- Accepted values: "anchors" (default), "color", "none". Anything else -
--- absent, mistyped, hand-edited SavedVariables, a number, a table - falls back
--- to "anchors": the resolver is PURE and TOTAL, it never raises and never
--- returns nil. The comparison is case-insensitive.
--- @param raw string|nil raw GideonRaidDB.intermission.pingMode value
--- @return string "anchors", "color" or "none"
function Config.resolvePingMode(raw)
    local wanted = (type(raw) == "string") and raw:lower() or ""
    for index = 1, #Config.PING_MODES do
        local candidate = Config.PING_MODES[index]
        if wanted == candidate then
            return candidate
        end
    end
    return Config.DEFAULT_PING_MODE
end

--- Returns (assignment, err). Validates the block before use.
function Config.getAssignment()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil, "GideonRaidDB absent"
    end
    return ns.Pairing.validateAssignment(db.assignment)
end

--- Publishes the player's LAST decision (click on a composition button) into the
--- SavedVariables. This is THE FIELD the diagnostic kit (GideonDiagAddon) reads
--- to timestamp the choice WITHOUT any chat input: we publish data, we send NO
--- message (no inter-addon communication, which is forbidden in instances).
---
--- Published shape: db.intermission.lastDecision =
---   { composition = "3V1R", at = <client epoch>, clock = "YYYY-MM-DD HH:MM:SS",
---     source = "coach-panel" }
--- The timestamp comes from the UI layer (it alone may call time()).
--- @param db table SavedVariables
--- @param record table { composition, at, clock, source }
--- @return table|nil published entry (nil if the composition is refused)
function Config.recordDecision(db, record)
    if type(db) ~= "table" or type(record) ~= "table" then
        return nil
    end
    local key = ns.Intermission.normalizeDeclaration(record.composition)
    if key == nil then
        return nil
    end
    if type(db.intermission) ~= "table" then
        db.intermission = Config.defaultIntermission()
    end
    local entry = {
        composition = key,
        at = tonumber(record.at),
        clock = record.clock,
        source = tostring(record.source or "coach-panel"),
    }
    db.intermission.lastDecision = entry
    return entry
end

--- Publishes ONE encounter observation into the SavedVariables (the IDLOG,
--- `/gr idlog on`): `db.intermission.seenEncounters` keeps the LAST observations,
--- NEWEST FIRST, bounded to `BossFilter.MAX_SEEN`. This is the field the raid
--- lead reads back after a pull to get the REAL encounter id of the target boss -
--- nothing is invented, nothing is sent.
--- The entry is normalized (Core/BossFilter.toEntry): only known fields, checked
--- values, so a hand-edited or malformed entry can never break the list.
--- @param db table SavedVariables
--- @param entry table observation { id, idStatus, name, ..., at, clock }
--- @return table|nil stored entry
function Config.recordSeen(db, entry)
    if type(db) ~= "table" or type(entry) ~= "table" then
        return nil
    end
    if type(db.intermission) ~= "table" then
        db.intermission = Config.defaultIntermission()
    end
    local stored = BossFilter.toEntry(entry)
    db.intermission.seenEncounters = BossFilter.rememberSeen(db.intermission.seenEncounters, stored)
    return stored
end

--- Raw text of the DELIVERED default target, for the chat (`/gr boss`, `/gr diag`):
--- "3445" and "Entombed Sentinels, Sentinelles inhumées". NO display literal here:
--- the labels around these strings come from Core/Locale.lua.
--- @param list table|nil list of ids or names
--- @return string
local function joinText(list)
    local parts = {}
    if type(list) == "table" then
        for index = 1, #list do
            parts[#parts + 1] = tostring(list[index])
        end
    end
    return table.concat(parts, ", ")
end

--- The DELIVERED encounter id(s) of the target boss, as text.
--- @return string
function Config.deliveredIdsText()
    return joinText(Config.DEFAULT_BOSS_IDS)
end

--- The DELIVERED names of the target boss, as text (accents preserved).
--- @return string
function Config.deliveredNamesText()
    return joinText(Config.DEFAULT_BOSS_NAMES)
end

--- PURE resolution of the module configuration: clamps, filters inconsistent
--- types, never keeps a value that cannot be rendered.
--- @param raw table|nil raw content of GideonRaidDB.intermission
--- @return table usable configuration
function Config.resolveIntermission(raw)
    local out = Config.defaultIntermission()
    -- AUTO-OPEN FILTER - THE EFFECTIVE TARGET, resolved FIRST and even when the
    -- whole block is absent, because it is what the panel opens on: the DELIVERED
    -- default of the addon (`Config.DEFAULT_BOSS_IDS` / `Config.DEFAULT_BOSS_NAMES`)
    -- added to the entries a player typed (`/gr boss <id>`, `/gr boss name <text>`),
    -- UNLESS the player explicitly cleared the target (`/gr boss clear` sets
    -- `bossTargetCleared`, which drops the delivered default). Nothing is invented
    -- here: every value comes from the constants above or from the SavedVariables.
    --   out.bossIds / out.bossNames ......... EFFECTIVE target (what decides)
    --   out.bossIdsOwn / out.bossNamesOwn ... what the PLAYER added (provenance)
    --   out.bossTargetCleared ............... explicit `/gr boss clear` marker
    --   out.bossTargetSource ................ where the target comes from
    local target = BossFilter.resolveTarget(raw, {
        ids = Config.DEFAULT_BOSS_IDS,
        names = Config.DEFAULT_BOSS_NAMES,
    })
    out.bossIds = target.ids
    out.bossNames = target.names
    out.bossIdsOwn = target.ownIds
    out.bossNamesOwn = target.ownNames
    out.bossTargetCleared = target.cleared
    out.bossTargetSource = target.source
    if type(raw) ~= "table" then
        return out
    end

    if type(raw.enabled) == "boolean" then
        out.enabled = raw.enabled
    end
    if type(raw.startOnEncounterStart) == "boolean" then
        out.startOnEncounterStart = raw.startOnEncounterStart
    end
    if type(raw.autoShowPanel) == "boolean" then
        out.autoShowPanel = raw.autoShowPanel
    end
    if type(raw.scale) == "number" then
        out.scale = clampNumber(raw.scale, Config.MIN_SCALE, Config.MAX_SCALE)
    end
    if type(raw.visibilitySeconds) == "number" then
        out.visibilitySeconds = math.floor(clampNumber(raw.visibilitySeconds, 1, 10) + 0.5)
    end
    if type(raw.durationSeconds) == "number" then
        out.durationSeconds = math.floor(clampNumber(raw.durationSeconds, out.visibilitySeconds + 1, 120) + 0.5)
    end
    -- Lead time (the panel opens BEFORE the intermission): bounded, an absurd
    -- value falls back to the default instead of showing the panel way too early.
    if type(raw.leadSeconds) == "number" then
        out.leadSeconds = math.floor(clampNumber(raw.leadSeconds, 0, 10) + 0.5)
    end
    -- BOUNDED AUTO-CLOSE: the safety delay after which the panel is hidden even
    -- when the intermission clock never reached DONE. Bounded HERE (5 s..300 s):
    -- a hand-edited SavedVariables can neither make the panel disappear during a
    -- real intermission nor park it on screen for minutes. The value is only a
    -- LOWER bound: Core/Intermission.closeDelay stretches it to the whole real
    -- window of the intermission when that is longer.
    if type(raw.autoCloseSeconds) == "number" then
        out.autoCloseSeconds =
            math.floor(clampNumber(raw.autoCloseSeconds, Config.MIN_AUTO_CLOSE_SECONDS, Config.MAX_AUTO_CLOSE_SECONDS) + 0.5)
    end
    out.scheduleSeconds = Config.resolveSchedule(raw.scheduleSeconds)
    -- Ping policy: pure and bounded resolution, an unknown value falls back to
    -- "anchors" (never an error, never nil).
    out.pingMode = Config.resolvePingMode(raw.pingMode)
    -- Assignment soundboard: TOTAL resolution (only an exact `false` mutes the
    -- sound, everything else - an older SavedVariables without the field, a
    -- hand-edited value - falls back to the default: ENABLED). The soft
    -- migration of the existing saves is exactly this: a missing field means
    -- "enabled", no schema bump is needed.
    out.soundEnabled = Sound.resolveEnabled(raw.soundEnabled)
    -- STYLE OF THE INTERMISSION CARDS (the raid lead's picker): the resolved value
    -- is a canonical name - a key of Core/Layout.BUTTON_STYLES - and an unknown,
    -- missing or OLD value (a save that still says `gideon`, `card`, `2`..) falls
    -- back to the DELIVERED style. A hand-edited or outdated SavedVariables can
    -- therefore never hand an unknown style to the layout, nor break anything.
    out.style = Config.resolveStyleName(raw.style)
    -- SHOWCASE ANIMATIONS: only an exact `false` stops them (the showcase is
    -- exactly where the raid lead wants to SEE the animations, so the default is
    -- ON). Same rule as the sound preference, mirrored from
    -- Layout.animationsEnabled (asserted equal by tests/spec/showcase_spec.lua).
    out.showcaseAnimations = raw.showcaseAnimations ~= false
    -- THE PREVIEW STYLE OF THE SHOWCASE (`/gr sim style <n>`): transient by nature,
    -- but persisted like the rest of the panel preferences so a /reload does not
    -- send the raid lead back to square one.
    out.showcaseStyle = Config.resolveStyleName(raw.showcaseStyle)

    -- AUTO-OPEN FILTER: the EFFECTIVE allow-lists were computed at the very top of
    -- this function (delivered default + the entries of the player, or the entries
    -- of the player alone after an explicit `/gr boss clear`): nothing to redo here,
    -- and nothing is ever invented.
    -- IDLOG: only an exact `true` turns it on (it WRITES on every encounter).
    out.idlog = BossFilter.enabledOf(raw.idlog)
    -- MANUAL OVERRIDE: only an exact `true` arms it; it is consumed (set back to
    -- false) at the end of the encounter it opened.
    out.overrideEncounter = raw.overrideEncounter == true

    local pos = raw.position
    if type(pos) == "table" then
        if type(pos.point) == "string" and pos.point ~= "" then
            out.position.point = pos.point
        end
        if type(pos.relativePoint) == "string" and pos.relativePoint ~= "" then
            out.position.relativePoint = pos.relativePoint
        end
        if type(pos.x) == "number" then
            out.position.x = pos.x
        end
        if type(pos.y) == "number" then
            out.position.y = pos.y
        end
    end

    if out.durationSeconds <= out.visibilitySeconds then
        out.durationSeconds = out.visibilitySeconds + 1
    end
    return out
end
