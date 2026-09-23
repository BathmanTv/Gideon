--[[--------------------------------------------------------------------------
    GideonRaid / Core / Sound.lua

    ASSIGNMENT SOUNDBOARDS - PURE LOGIC (Lua 5.1). This file touches NO WoW API:
    it plays NOTHING (the only audio call of the addon lives in UI/, under pcall),
    reads no unit value, registers no event and calls no clock. It runs as-is
    under busted and under lua5.1 outside the client.

    WHAT IT IS FOR: as soon as the player has DECLARED their orb composition
    (click on one of the three buttons of the intermission panel - real flow or
    `/gr sim inter` rehearsal), the raid lead wants the soundboard OF THAT STATE
    to be heard, ONCE. One file per canonical state of Core/Intermission.lua:

        1V3R -> Sound/assign-1v3r.ogg      2V2R -> Sound/assign-2v2r.ogg
        3V1R -> Sound/assign-3v1r.ogg

    THE THREE BUSINESS RULES ARE ENFORCED HERE, out of game, because they are
    rules and not rendering:
      1. ONE FILE PER STATE: Sound.STATES / Sound.FILES_BY_STATE / Sound.pathFor.
         The paths are client paths ("Interface\AddOns\GideonRaid\Sound\..."),
         and the three files MUST be listed in GideonRaid.toc (the client does
         not load a sound that is not listed) - see tests/spec/sound_spec.lua.
      2. ONE PLAYBACK PER ASSIGNMENT: Sound.newAssigner + Sound.takeAssignSound
         return a request ONLY for a declared state that has not already been
         sounded. A refresh, a panel tick or a repeated declaration of the SAME
         composition therefore cannot double the sound. Sound.resetAssigner
         re-arms the gate: CORRECT (then a new click) and every new intermission
         replay the sound - the natural behaviour, documented in
         docs/INTERMISSION-COACH.md and docs/TESTPLAN.md.
      3. THE PREFERENCE IS BOUNDED: Sound.resolveSwitch is STRICT (`/gr sound
         on|off`, anything else yields nil and the CALLER refuses it without
         persisting anything) and Sound.resolveEnabled is TOTAL: only an exact
         `false` disables the sound, everything else - absent, a string, a
         number, a hand-edited SavedVariables - falls back to the DEFAULT
         (enabled), exactly like Config.resolvePingMode falls back to "anchors".

    NO SOUND WITHOUT A DECLARATION: takeAssignSound refuses an unknown state
    (nil, "unknown"), so the panel stays silent until the player clicks one of
    the three compositions.

    THE FILES ARE REPLACED WITHOUT TOUCHING THE CODE: the raid lead drops three
    Ogg Vorbis recordings with the SAME names in Sound/ (see README.md, section
    "Replacing the three sounds"), and nothing else changes - the table above is
    the only place the file names appear.
----------------------------------------------------------------------------]]
--
--
--
local _, ns = ...

---@class Sound
local Sound = {}
ns.Sound = Sound

--- Model version of the assignment soundboards. 1 = one file per state, one
--- playback per assignment, bounded on/off preference.
Sound.SCHEMA_VERSION = 1

--- Folder of the soundboards, as the CLIENT spells it (backslashes, addon folder
--- name of the .toc / of `package-as` in .pkgmeta). The tests compare this
--- prefix with the entries listed in GideonRaid.toc.
Sound.FOLDER = "Interface\\AddOns\\GideonRaid\\Sound\\"

--- Channel the sound is played on: the player's MASTER volume still applies, so
--- the soundboard follows the sound settings of the client instead of escaping
--- them.
Sound.CHANNEL = "Master"

--- The THREE canonical states, in the DETERMINISTIC display order of the panel.
--- MIRROR of Intermission.STATES (that module is loaded AFTER this one, so the
--- list cannot be read from there): tests/spec/sound_spec.lua asserts that the
--- two lists are identical, so they can never drift apart.
Sound.STATES = { "1V3R", "2V2R", "3V1R" }

--- State -> file name, DETERMINISTIC table (no pairs()): the file names are
--- lower case, without accents, stable - that is the CONTRACT with the raid
--- lead who records the real sounds (same names, same folder).
Sound.FILES_BY_STATE = {
    ["1V3R"] = "assign-1v3r.ogg",
    ["2V2R"] = "assign-2v2r.ogg",
    ["3V1R"] = "assign-3v1r.ogg",
}

--- The same three file names as an ORDERED list (same order as Sound.STATES):
--- used by the tests that check the .toc entries and the files on disk.
Sound.FILE_NAMES = { "assign-1v3r.ogg", "assign-2v2r.ogg", "assign-3v1r.ogg" }

--- Default of the player preference: the sound is ENABLED (the raid lead
--- requested it; `/gr sound off` mutes it).
Sound.DEFAULT_ENABLED = true

--- Values accepted by `/gr sound on|off` and their meaning. STRICT and bounded:
--- anything else is refused by the caller (see resolveSwitch).
Sound.SWITCHES = { on = true, off = false }

--- Why takeAssignSound returned (or refused) a request. ASCII identifiers, never
--- displayed: the rendering layer decides which message (if any) to print.
Sound.REASON = {
    PLAY = "play",
    UNKNOWN = "unknown",
    DISABLED = "disabled",
    ALREADY = "already",
}

--- Symbol written by the player -> canonical state. Built from Sound.STATES in a
--- LOOP (no duplicated literal, no pairs()): "1v3r" -> "1V3R".
local STATE_BY_SYMBOL = {}
for index = 1, #Sound.STATES do
    local state = Sound.STATES[index]
    STATE_BY_SYMBOL[state:lower()] = state
end
Sound.STATE_BY_SYMBOL = STATE_BY_SYMBOL

--- Normalizes a state written by the player or held by the state machine into a
--- canonical key. Tolerant on case and spaces ("1v3r", "1 V 3 R", "3V1R") and
--- TOTAL: an absent, empty, mistyped or non-string value returns nil (the caller
--- refuses it, nothing is guessed).
--- @param raw string|nil
--- @return string|nil "1V3R" | "2V2R" | "3V1R"
function Sound.resolveState(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local flat = raw:lower():gsub("%s+", "")
    return STATE_BY_SYMBOL[flat]
end

--- File name (without folder) of a state, or nil when the state is unknown.
--- @param state string|nil
--- @return string|nil
function Sound.fileName(state)
    local key = Sound.resolveState(state)
    if key == nil then
        return nil
    end
    return Sound.FILES_BY_STATE[key]
end

--- CLIENT path of the soundboard of a state ("Interface\AddOns\GideonRaid\
--- Sound\assign-1v3r.ogg"), or nil when the state is unknown. This is exactly
--- what the rendering layer hands to PlaySoundFile, and exactly what
--- GideonRaid.toc lists.
--- @param state string|nil
--- @return string|nil client path
function Sound.pathFor(state)
    local file = Sound.fileName(state)
    if file == nil then
        return nil
    end
    return Sound.FOLDER .. file
end

--- STRICT resolution of the value typed after `/gr sound` (`on` / `off`).
--- Accepted (case-insensitive, surrounding spaces ignored): "on" -> true,
--- "off" -> false. Anything else - absent, empty, "yes", a number, a table -
--- returns nil: the CALLER refuses it and persists NOTHING (same mechanics as
--- `/gr lang` and `/gr ping`).
--- @param raw string|nil
--- @return boolean|nil
function Sound.resolveSwitch(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local wanted = raw:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local value = Sound.SWITCHES[wanted]
    if value == nil then
        return nil
    end
    return value
end

--- TOTAL resolution of the PERSISTED preference (GideonRaidDB.intermission.
--- soundEnabled). Only an exact `false` disables the sound; everything else -
--- absent (an older SavedVariables), a string, a number, a table - falls back to
--- the default (ENABLED). The resolver never raises and never returns nil, so a
--- hand-edited SavedVariables can never mute a player silently.
--- @param raw any
--- @return boolean
function Sound.resolveEnabled(raw)
    return raw ~= false
end

--- Creates the ONE-PLAYBACK-PER-ASSIGNMENT gate. It is plain data (no API, no
--- clock): it survives as long as the panel session does, and the wiring resets
--- it when a new intermission, a rehearsal or a CORRECT starts another
--- declaration.
--- @return table assigner { lastState = nil }
function Sound.newAssigner()
    return { lastState = nil }
end

--- Re-arms the gate: the next declared composition plays its sound again.
--- Called on CORRECT, on every new intermission and on every rehearsal.
--- @param assigner table|nil
--- @return table
function Sound.resetAssigner(assigner)
    if type(assigner) ~= "table" then
        return Sound.newAssigner()
    end
    assigner.lastState = nil
    return assigner
end

--- PURE decision: must the soundboard of `declaration` be played NOW?
--- Refusals (nil + reason), in this order:
---   - "unknown"  : the declaration is not one of the three canonical states
---                  (no sound without a declaration, nothing is guessed);
---   - "disabled" : the player turned the sound off (`/gr sound off`);
---   - "already"  : this SAME state has already been sounded for the current
---                  assignment (ONE playback per assignment: a refresh, a tick
---                  or a repeated declaration cannot double the sound).
--- ACCEPTED: returns the request to hand to PlaySoundFile (file path + channel,
--- both computed HERE) and records the state in the gate.
--- `enabled` is the RESOLVED preference, injected by the wiring (Core/ never
--- reads the SavedVariables): nil counts as enabled.
--- @param assigner table|nil gate created by newAssigner
--- @param declaration string|nil canonical state declared by the player
--- @param enabled boolean|nil resolved preference (false = muted)
--- @return table|nil request { state, fileName, path, channel }
--- @return string reason (Sound.REASON.*)
function Sound.takeAssignSound(assigner, declaration, enabled)
    local state = Sound.resolveState(declaration)
    if state == nil then
        return nil, Sound.REASON.UNKNOWN
    end
    if enabled == false then
        return nil, Sound.REASON.DISABLED
    end
    if type(assigner) == "table" and assigner.lastState == state then
        return nil, Sound.REASON.ALREADY
    end
    if type(assigner) == "table" then
        assigner.lastState = state
    end
    return {
        state = state,
        fileName = Sound.FILES_BY_STATE[state],
        path = Sound.pathFor(state),
        channel = Sound.CHANNEL,
    },
        Sound.REASON.PLAY
end

return Sound
