--[[--------------------------------------------------------------------------
    GideonRaid / Core / BossFilter.lua

    WHICH BOSS MAY OPEN THE PANEL - PURE LOGIC (Lua 5.1). No WoW API, no clock,
    no SavedVariables access: this file runs as-is under busted and under lua5.1
    outside the client.

    WHY IT EXISTS (critical bug reported by the raid lead): the intermission panel
    used to open on ANY `ENCOUNTER_START`, i.e. on any boss of any raid. It must
    open ONLY for the target boss (Entombed Sentinels). The criterion is an
    ALLOW-LIST OF ENCOUNTER IDS, persisted in `GideonRaidDB.intermission.bossIds`:

      - the ID is `ENCOUNTER_START` arg1: an INTEGER, identical on every client
        whatever the game language. It is the PRIMARY criterion, and it is the
        ONLY one the raid lead has to provide (`/gr boss <id>`);
      - a NAME (arg2) is accepted as a SECONDARY criterion, but it depends on the
        CLIENT LANGUAGE (the raid lead plays on a French client, so the name the
        client displays is French): the name list is EMPTY by default, no
        translation is ever guessed, and `/gr boss name <text>` fills it with the
        exact text the player sees.

    SAFE DEFAULT (raid-lead decision): an EMPTY allow-list means NO automatic
    opening at all. A panel that does not open is better than a panel that opens
    on the wrong boss. `evaluate` therefore answers REFUSED, and the chat hands
    the player the way to configure the right boss (`/gr idlog on` + `/gr boss
    <id>`) - or to force the next encounter once (`/gr inter on`).

    BECAUSE THE ID IS NOT KNOWN YET, THE ADDON NEVER INVENTS ONE: `observeEncounter`
    turns the raw event arguments into a plain, persistable OBSERVATION and the
    idlog (`/gr idlog on`) prints it and memorizes the last
    `BossFilter.MAX_SEEN` ones, so the raid lead can read the real id in game and
    enter it (`docs/TESTPLAN.md`, in-game protocol 3.5e).

    SECRET VALUES (12.x, https://warcraft.wiki.gg/wiki/Secret_Values): an argument
    of an instance event may be a SECRET value, and the smallest operation on it -
    `type()` included - raises. Every argument is therefore read through an
    INJECTED probe, ALWAYS under `pcall`, and anything that cannot be read is
    reported as `READ.UNREADABLE`: nothing is compared, the value is simply not a
    match. The worst case is a refused automatic opening, never a Lua error and
    never the wrong boss.
----------------------------------------------------------------------------]]
--
--
--
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: every string this
--- module builds (the status summary, the idlog line) goes through it, so the
--- messages follow the language the player reads.
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/BossFilter.lua")

---@class BossFilter
local BossFilter = {}
ns.BossFilter = BossFilter

--- Model version of the auto-open filter. 1 = allow-list of encounter ids
--- (PRIMARY) + optional allow-list of names (SECONDARY), empty by default.
BossFilter.SCHEMA_VERSION = 1

--- Maximum number of encounter ids kept in the allow-list. A hand-edited
--- SavedVariables must never produce an unbounded list (same spirit as
--- Config.MAX_SCHEDULE_ENTRIES).
BossFilter.MAX_IDS = 12

--- Maximum number of encounter NAMES kept in the secondary allow-list.
BossFilter.MAX_NAMES = 12

--- How many encounters the idlog memorizes (newest first).
BossFilter.MAX_SEEN = 10

--- Outcome of reading ONE event argument. ASCII identifiers, never displayed:
---   OK          : a usable plain value was read;
---   ABSENT      : nothing there (no argument, or a value of another type);
---   UNREADABLE  : the read had to be abandoned - a SECRET value raises on the
---                 smallest operation, `type()` included;
---   NOT_INTEGER : a number that is not a usable integer (an encounter id is an
---                 integer: 16.5 is not an id).
BossFilter.READ = {
    OK = "ok",
    ABSENT = "absent",
    UNREADABLE = "unreadable",
    NOT_INTEGER = "notInteger",
}

--- Why `evaluate` did (or did not) decide to open the panel. ASCII identifiers,
--- never displayed: the rendering layer picks the message.
BossFilter.REASON = {
    OVERRIDE = "override",
    MATCH_ID = "matchId",
    MATCH_NAME = "matchName",
    NO_TARGET = "noTarget",
    NO_MATCH = "noMatch",
    UNREADABLE = "unreadable",
}

--- Values accepted by `/gr idlog on|off` (STRICT: anything else yields nil and
--- the caller refuses it without persisting anything).
BossFilter.SWITCHES = { on = true, off = false }

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function clampList(list, max)
    while #list > max do
        table.remove(list)
    end
    return list
end

--- A POSITIVE integer, or nil. TOTAL: never raises, whatever the input type
--- (nil, a string, a float, a table, a hand-edited SavedVariables).
local function positiveInt(value)
    if type(value) == "string" then
        -- ONLY DIGITS: an encounter id is written like an id, so "1e3", "+5",
        -- "0x10" or "12.5" are REFUSED instead of being reinterpreted as a
        -- number the player never typed.
        local text = trim(value)
        if text:match("^%d+$") == nil then
            return nil
        end
        value = tonumber(text)
    end
    if type(value) ~= "number" or value ~= value then
        return nil
    end
    if value % 1 ~= 0 or value < 1 then
        return nil
    end
    return value
end

--- A NON-NEGATIVE integer (the difficulty id and the group size are read for the
--- idlog only: they never decide anything, so 0 is tolerated).
local function plainInt(value)
    if type(value) ~= "number" or value ~= value then
        return nil
    end
    if value % 1 ~= 0 or value < 0 then
        return nil
    end
    return value
end

--- A non-empty string, trimmed, or nil.
local function plainText(value)
    if type(value) ~= "string" then
        return nil
    end
    local text = trim(value)
    if text == "" then
        return nil
    end
    return text
end

--- STRICT resolution of the value typed after `/gr boss` (`/gr boss <id>`).
--- Accepted: a positive integer written as a string ("1234", " 1234 ") or as a
--- number. Anything else - absent, empty, "Entombed Sentinels", "12.5", "-3",
--- "0", a table - returns nil: the CALLER refuses it and persists NOTHING (same
--- mechanics as `/gr lang`, `/gr ping` and `/gr sound`).
--- @param raw string|number|nil value typed by the player
--- @return number|nil id
function BossFilter.resolveId(raw)
    return positiveInt(raw)
end

--- TOTAL resolution of the PERSISTED allow-list of ids: positive integers only,
--- de-duplicated, SORTED ASCENDING (deterministic, no pairs()) and bounded.
--- A missing, malformed or hand-edited value never raises and yields an EMPTY
--- list, which is the SAFE DEFAULT: no automatic opening.
--- @param raw table|nil persisted GideonRaidDB.intermission.bossIds
--- @return table sorted copy of positive integers
function BossFilter.resolveIds(raw)
    local out = {}
    if type(raw) ~= "table" then
        return out
    end
    for index = 1, #raw do
        local id = positiveInt(raw[index])
        if id ~= nil then
            local known = false
            for seen = 1, #out do
                if out[seen] == id then
                    known = true
                    break
                end
            end
            if not known then
                out[#out + 1] = id
            end
        end
    end
    table.sort(out)
    return clampList(out, BossFilter.MAX_IDS)
end

--- Adds ONE id to the allow-list and returns a NEW, normalized list (the caller
--- persists it): the persisted list can never contain a duplicate or a non
--- integer, whatever the player typed.
--- @param list table|nil current list (raw or already resolved)
--- @param id number id accepted by resolveId
--- @return table normalized copy
function BossFilter.addId(list, id)
    local out = BossFilter.resolveIds(list)
    local wanted = positiveInt(id)
    if wanted == nil then
        return out
    end
    local known = false
    for index = 1, #out do
        if out[index] == wanted then
            known = true
            break
        end
    end
    if not known and #out < BossFilter.MAX_IDS then
        out[#out + 1] = wanted
    end
    table.sort(out)
    return out
end

--- Normalizes ONE name of the secondary criterion: trimmed, non-empty. The list
--- is compared CASE-INSENSITIVELY (the client may capitalize differently) and it
--- is NEVER translated nor guessed here.
--- @param raw string|nil
--- @return string|nil
function BossFilter.resolveName(raw)
    local text = plainText(raw)
    if text == nil then
        return nil
    end
    return text:lower()
end

--- TOTAL resolution of the PERSISTED allow-list of names: trimmed, lower case,
--- de-duplicated, SORTED, bounded. EMPTY by default (the name is the
--- language-dependent criterion: nothing is invented).
--- @param raw table|nil persisted GideonRaidDB.intermission.bossNames
--- @return table sorted copy of lower-case names
function BossFilter.resolveNames(raw)
    local out = {}
    if type(raw) ~= "table" then
        return out
    end
    for index = 1, #raw do
        local name = BossFilter.resolveName(raw[index])
        if name ~= nil then
            local known = false
            for seen = 1, #out do
                if out[seen] == name then
                    known = true
                    break
                end
            end
            if not known then
                out[#out + 1] = name
            end
        end
    end
    table.sort(out)
    return clampList(out, BossFilter.MAX_NAMES)
end

--- Adds ONE name and returns a NEW normalized list (see addId).
--- @param list table|nil
--- @param raw string|nil
--- @return table normalized copy
function BossFilter.addName(list, raw)
    local out = BossFilter.resolveNames(list)
    local wanted = BossFilter.resolveName(raw)
    if wanted == nil then
        return out
    end
    local known = false
    for index = 1, #out do
        if out[index] == wanted then
            known = true
            break
        end
    end
    if not known and #out < BossFilter.MAX_NAMES then
        out[#out + 1] = wanted
    end
    table.sort(out)
    return out
end

--- STRICT resolution of the value typed after `/gr idlog` (`on` / `off`):
--- accepted case-insensitively, anything else yields nil (the caller refuses it,
--- nothing is persisted).
--- @param raw string|nil
--- @return boolean|nil
function BossFilter.resolveSwitch(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local value = BossFilter.SWITCHES[trim(raw):lower()]
    if value == nil then
        return nil
    end
    return value
end

--- TOTAL resolution of the PERSISTED idlog switch: only an exact `true` turns the
--- log on, everything else (absent - an older SavedVariables - a string, a
--- number, a hand-edited value) means OFF. The log writes into the SavedVariables
--- on every encounter, so the safe default is OFF.
--- @param raw any
--- @return boolean
function BossFilter.enabledOf(raw)
    return raw == true
end

--- Is a target configured at all (id(s) or name(s))? The SAFE DEFAULT is an EMPTY
--- allow-list, i.e. no automatic opening.
--- @param config table|nil resolved configuration
--- @return boolean
function BossFilter.hasTarget(config)
    local cfg = type(config) == "table" and config or {}
    return #BossFilter.resolveIds(cfg.bossIds) > 0 or #BossFilter.resolveNames(cfg.bossNames) > 0
end

--- Reads ONE event argument through the injected probe, ALWAYS under `pcall`.
--- `probe` is INJECTED by the wiring layer (Core/ never touches an event and
--- never calls a client API): it receives the raw argument and returns
--- (kind, plainValue). `defaultProbe` is the out-of-game implementation (and the
--- one the client uses: `type()` is plain Lua).
--- A probe that raises - a SECRET value in 12.x raises on `type()` itself - yields
--- READ.UNREADABLE: the value is then NEVER compared.
--- @param read function probe
--- @param value any raw argument
--- @return any plain value or nil, string status (BossFilter.READ.*)
local function readField(read, value)
    local ok, kind, plain = pcall(read, value)
    if not ok then
        return nil, BossFilter.READ.UNREADABLE
    end
    if plain == nil then
        if kind == "number" then
            return nil, BossFilter.READ.NOT_INTEGER
        end
        return nil, BossFilter.READ.ABSENT
    end
    return plain, BossFilter.READ.OK
end

--- The out-of-game (and out-of-combat) probe: a plain integer or a non-empty
--- string is usable, everything else is absent. It never invents a value.
--- @param value any
--- @return string kind, any plain value or nil
local function defaultProbe(value)
    local kind = type(value)
    if kind == "number" then
        if plainInt(value) == nil then
            return kind, nil
        end
        return kind, value
    end
    if kind == "string" then
        if plainText(value) == nil then
            return kind, nil
        end
        return kind, value
    end
    return kind, nil
end

--- Derives the status of ONE observation field: OK when a usable value was read,
--- otherwise the reason it is missing - and a NUMBER that is not an integer says
--- NOT_INTEGER (16.5 is not an encounter id), which the missing value could not
--- tell anymore.
--- @param raw any raw field of the source
--- @param value any normalized value (nil when unusable)
--- @param status string|nil status already known
--- @return string
local function deriveStatus(raw, value, status)
    if value ~= nil then
        return BossFilter.READ.OK
    end
    if status == BossFilter.READ.UNREADABLE then
        return BossFilter.READ.UNREADABLE
    end
    if status == BossFilter.READ.NOT_INTEGER or type(raw) == "number" then
        return BossFilter.READ.NOT_INTEGER
    end
    return BossFilter.READ.ABSENT
end

--- PURE and TOTAL: a persistable observation built from an observed encounter (or
--- from a hand-edited SavedVariables entry). Only the known fields are kept, each
--- value is checked, and a status is DERIVED from the value: an entry can never
--- claim to hold an id it does not have (same spirit as Config.resolvePosition).
--- @param source table|nil
--- @return table observation
function BossFilter.toEntry(source)
    local raw = type(source) == "table" and source or {}
    local id = plainInt(raw.id)
    local name = plainText(raw.name)
    local difficulty = plainInt(raw.difficulty)
    local groupSize = plainInt(raw.groupSize)
    local entry = {
        id = id,
        idStatus = deriveStatus(raw.id, id, raw.idStatus),
        name = name,
        nameStatus = deriveStatus(raw.name, name, raw.nameStatus),
        difficulty = difficulty,
        difficultyStatus = deriveStatus(raw.difficulty, difficulty, raw.difficultyStatus),
        groupSize = groupSize,
        groupSizeStatus = deriveStatus(raw.groupSize, groupSize, raw.groupSizeStatus),
    }
    if type(raw.at) == "number" then
        entry.at = raw.at
    end
    if type(raw.clock) == "string" then
        entry.clock = raw.clock
    end
    return entry
end

--- An observation that carries NOTHING: no id, no name, and nothing that FAILED to
--- read either (an unreadable value is information, an absent one is not). Such an
--- entry is dropped instead of being displayed as "id=none name=none" or pushing a
--- useful observation out of the idlog ring.
--- @param entry table|nil observation (or raw observation data)
--- @return boolean
function BossFilter.isEmptyObservation(entry)
    local data = type(entry) == "table" and entry or {}
    return data.id == nil and data.name == nil and data.idStatus == BossFilter.READ.ABSENT
end

--- The status carried by an observation field: a value that is there is OK, and a
--- missing value keeps the REASON it is missing (UNREADABLE and NOT_INTEGER carry
--- information no value can).
--- @param value any
--- @param status string|nil
--- @return string
function BossFilter.statusOf(value, status)
    if value ~= nil then
        return BossFilter.READ.OK
    end
    if status == BossFilter.READ.UNREADABLE then
        return BossFilter.READ.UNREADABLE
    end
    if status == BossFilter.READ.NOT_INTEGER then
        return BossFilter.READ.NOT_INTEGER
    end
    return BossFilter.READ.ABSENT
end

--- Turns the FOUR arguments of `ENCOUNTER_START` into the plain observation of
--- Core (and of the idlog). Every read goes through `readField`, i.e. under
--- `pcall`: a value that cannot be read is reported, never compared.
--- Only what is needed is read: the encounter id (PRIMARY criterion), the name
--- (SECONDARY, language dependent) and the difficulty + group size (LOG ONLY -
--- they never take part in the decision).
--- API ref 12.x: https://warcraft.wiki.gg/wiki/ENCOUNTER_START
--- @param arg1 any encounterID
--- @param arg2 any encounterName
--- @param arg3 any difficultyID
--- @param arg4 any groupSize
--- @param probe function|nil injected reader (defaults to the plain-Lua one)
--- @return table observation { id, idStatus, name, nameStatus, difficulty, ... }
function BossFilter.observeEncounter(arg1, arg2, arg3, arg4, probe)
    local read = type(probe) == "function" and probe or defaultProbe
    local id, idStatus = readField(read, arg1)
    local name, nameStatus = readField(read, arg2)
    local difficulty, difficultyStatus = readField(read, arg3)
    local groupSize, groupSizeStatus = readField(read, arg4)
    return BossFilter.toEntry({
        id = id,
        idStatus = idStatus,
        name = name,
        nameStatus = nameStatus,
        difficulty = difficulty,
        difficultyStatus = difficultyStatus,
        groupSize = groupSize,
        groupSizeStatus = groupSizeStatus,
    })
end

--- THE DECISION: must the intermission panel open BY ITSELF on this encounter?
--- PURE, TOTAL, DETERMINISTIC - this is the function that fixes the critical bug.
--- Order of the rules (it matters):
---   1. the MANUAL OVERRIDE (`/gr inter on`): the player asked for the NEXT
---      encounter, whatever the boss -> OPEN (reason OVERRIDE);
---   2. an EMPTY allow-list: SAFE DEFAULT, NOTHING opens (reason NO_TARGET);
---   3. the ID read on the encounter is in the allow-list -> OPEN (MATCH_ID). It
---      is the PRIMARY criterion: an integer, identical in every language;
---   4. the NAME read on the encounter is in the secondary list (case-insensitive)
---      -> OPEN (MATCH_NAME). Language dependent, empty by default;
---   5. otherwise REFUSED: reason UNREADABLE when something could not be read
---      (a SECRET value in 12.x), NO_MATCH otherwise.
--- @param encounter table|nil observation built by observeEncounter
--- @param config table|nil resolved configuration (GideonRaidDB.intermission)
--- @return table decision { shouldOpen, reason, id, name }
function BossFilter.evaluate(encounter, config)
    local data = type(encounter) == "table" and encounter or {}
    local cfg = type(config) == "table" and config or {}
    local id = plainInt(data.id)
    local name = plainText(data.name)

    local refusal = { shouldOpen = false, id = id, name = name }
    if cfg.overrideEncounter == true then
        return { shouldOpen = true, reason = BossFilter.REASON.OVERRIDE, id = id, name = name }
    end

    local ids = BossFilter.resolveIds(cfg.bossIds)
    local names = BossFilter.resolveNames(cfg.bossNames)
    if #ids == 0 and #names == 0 then
        refusal.reason = BossFilter.REASON.NO_TARGET
        return refusal
    end

    for index = 1, #ids do
        if ids[index] == id then
            return { shouldOpen = true, reason = BossFilter.REASON.MATCH_ID, id = id, name = name }
        end
    end

    local wanted = BossFilter.resolveName(name)
    if wanted ~= nil then
        for index = 1, #names do
            if names[index] == wanted then
                return { shouldOpen = true, reason = BossFilter.REASON.MATCH_NAME, id = id, name = name }
            end
        end
    end

    if data.idStatus == BossFilter.READ.UNREADABLE or data.nameStatus == BossFilter.READ.UNREADABLE then
        refusal.reason = BossFilter.REASON.UNREADABLE
    else
        refusal.reason = BossFilter.REASON.NO_MATCH
    end
    return refusal
end

--- Localized text of one observation field, for the idlog line: the value itself,
--- or a READABLE mention when the value could not be read (SECRET value) / was
--- not usable. Never a blank, never a lie.
--- @param value any
--- @param status string|nil
--- @return string
function BossFilter.fieldText(value, status)
    if status == BossFilter.READ.UNREADABLE then
        return Locale.t("cmd.boss.value.unreadable")
    end
    if value == nil then
        return Locale.t("cmd.boss.value.absent")
    end
    return tostring(value)
end

--- THE IDLOG LINE of one observation (requested by the raid lead: this is how the
--- REAL id of Entombed Sentinels is captured, without inventing anything):
---   "encounter seen: id=1234 name=Entombed Sentinels difficulty=16 group=20"
--- @param encounter table|nil
--- @return string line
function BossFilter.seenLine(encounter)
    local data = type(encounter) == "table" and encounter or {}
    return Locale.format(
        "cmd.boss.seen",
        BossFilter.fieldText(data.id, data.idStatus),
        BossFilter.fieldText(data.name, data.nameStatus),
        BossFilter.fieldText(data.difficulty, data.difficultyStatus),
        BossFilter.fieldText(data.groupSize, data.groupSizeStatus)
    )
end

--- PURE: the idlog keeps the LAST observed encounters, NEWEST FIRST, bounded to
--- `MAX_SEEN`. Returns a NEW list (the caller persists it): the ring can never
--- grow unbounded, whatever happens in game.
--- @param list table|nil current list (newest first)
--- @param entry table|nil observation to remember
--- @return table new list
function BossFilter.rememberSeen(list, entry)
    local out = {}
    local added = BossFilter.toEntry(entry)
    if BossFilter.isEmptyObservation(added) then
        -- Nothing was read at all: remembering an empty line would only push a
        -- useful observation out of the ring.
        if type(list) == "table" then
            return BossFilter.toList(list)
        end
        return out
    end
    out[1] = added
    if type(list) == "table" then
        for index = 1, #list do
            if #out >= BossFilter.MAX_SEEN then
                break
            end
            local older = BossFilter.toEntry(list[index])
            if not BossFilter.isEmptyObservation(older) then
                out[#out + 1] = older
            end
        end
    end
    return out
end

--- TOTAL resolution of the PERSISTED idlog ring (newest first, bounded).
--- @param raw table|nil
--- @return table list
function BossFilter.toList(raw)
    local out = {}
    if type(raw) ~= "table" then
        return out
    end
    for index = 1, #raw do
        if #out >= BossFilter.MAX_SEEN then
            break
        end
        local entry = BossFilter.toEntry(raw[index])
        -- An entry that carries NOTHING (no id, no name, nothing that failed to
        -- read) says nothing: it is dropped instead of showing "id=none name=none".
        if not BossFilter.isEmptyObservation(entry) then
            out[#out + 1] = entry
        end
    end
    return out
end

--- `"1234, 5678"` (or `""` when the list is empty): display helper of `/gr boss`,
--- `""` included so the caller never has to special-case a missing list.
--- @param list table|nil ids
--- @return string
function BossFilter.describeIds(list)
    local ids = BossFilter.resolveIds(list)
    local parts = {}
    for index = 1, #ids do
        parts[#parts + 1] = tostring(ids[index])
    end
    return table.concat(parts, ", ")
end

--- Same for the (language-dependent) names.
--- @param list table|nil names
--- @return string
function BossFilter.describeNames(list)
    local names = BossFilter.resolveNames(list)
    return table.concat(names, ", ")
end

--- One-line summary of the configured target, used by `/gr boss` and by the
--- information messages: "ids 1234, 5678, names sentinelles ensevelies" or the
--- explicit "NONE" of the safe default.
--- @param config table|nil resolved configuration
--- @return string
function BossFilter.targetSummary(config)
    local cfg = type(config) == "table" and config or {}
    local ids = BossFilter.resolveIds(cfg.bossIds)
    local names = BossFilter.resolveNames(cfg.bossNames)
    local parts = {}
    if #ids > 0 then
        parts[#parts + 1] = Locale.format("cmd.boss.target.ids", BossFilter.describeIds(ids))
    end
    if #names > 0 then
        parts[#parts + 1] = Locale.format("cmd.boss.target.names", BossFilter.describeNames(names))
    end
    if #parts == 0 then
        return Locale.t("cmd.boss.target.none")
    end
    return table.concat(parts, ", ")
end

--- Localized text of an id for a message (`/gr boss` refusals), "none" when there
--- is nothing to name.
--- @param value any
--- @return string
function BossFilter.idText(value)
    local id = plainInt(value)
    if id == nil then
        return Locale.t("cmd.boss.value.absent")
    end
    return tostring(id)
end

return BossFilter
