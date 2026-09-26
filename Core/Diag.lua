--[[--------------------------------------------------------------------------
    GideonRaid / Core / Diag.lua

    HEALTH REPORT OF THE ADDON (`/gideon diag`) - PURE LOGIC (Lua 5.1). This file
    touches NO WoW API, plays NOTHING, reads no CVar and no SavedVariables: it runs
    as-is under busted and under lua5.1 outside the client. Everything it needs is
    INJECTED by the rendering layer (UI/Panel.lua), which alone is allowed to call
    the client.

    WHY IT EXISTS: the raid lead wants ONE command that answers "is the addon
    healthy right now?" before a pull - are the four sound files really loaded and
    playable, what is the effective auto-open target, is the idlog on, which ping
    policy is active. Everything is READ-ONLY: nothing is written, nothing is sent,
    no macro is built, no ping is placed, and the diagnostic NEVER plays a sound in
    a client whose sound is on (see the audio gate below).

    THE AUDIO CHECK (documented trick): `PlaySoundFile` (API:PlaySoundFile)
    returns `willPlay` - TRUE when the client will really play the file, nil/false
    otherwise (file missing, file added after the client started, refused
    playback). This is the ONLY way to know, IN GAME, whether a sound file is
    loaded, because a file that is not listed in `GideonRaid.toc` is never loaded
    and the client then fails silently.

    BUT A CALL TO PlaySoundFile IS A PLAYBACK. The gate below is therefore the
    core rule of this module:

      - the probe may run ONLY when the Master channel is ENABLED (so the answer
        means something: a DISABLED channel answers "nothing will play" even for a
        file that is really there, which would be a LIE) AND its volume is exactly
        0 (so the playback is mathematically inaudible: the raid hears nothing);
      - in every other case the probe is NOT started and the report says so, with
        the exact procedure to make the check possible (mute the master volume,
        run `/gideon diag`, restore it) or to hear the files on purpose
        (`/gideon sound test 1v3r|2v2r|3v1r|start`, which DOES play a sound).

    The gate is PURE: `Diag.probeGate(cvars)` receives the raw CVar strings read by
    the rendering layer and returns an ASCII decision. That is why the whole rule
    is provable out of game (tests/spec/diag_spec.lua), including the case "the
    client must not make any noise".

    WHAT THE REPORT CONTAINS: the four sound files with a verdict per line
    (`playable` / `not playable` / `not tested` / `unknown`), the effective
    auto-open target and WHERE it comes from, the delivered default of the addon,
    the idlog state and the ping policy. Its lines go through Core/Locale.lua like
    every other displayed string; the "[OK]" / "[KO]" markers are ASCII on purpose
    (the default game font renders accented glyphs badly).
----------------------------------------------------------------------------]]
--
--
--
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: every line of the
--- report is built from it (English by default, French on a frFR client).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Diag.lua")

--- Core/Sound.lua is loaded BEFORE this file by the .toc, and it is the ONE owner
--- of the sound file names: the report lists exactly what the client loads, so a
--- new file can never be forgotten here.
local Sound = assert(ns.Sound, "Core/Sound.lua must be loaded before Core/Diag.lua")

---@class Diag
local Diag = {}
ns.Diag = Diag

--- Model version of the health report. 1 = four sound files probed through
--- PlaySoundFile behind a silence gate + the effective target / idlog / ping
--- reminder.
Diag.SCHEMA_VERSION = 1

--- Channel of the probe. It is the SAME channel the addon really uses to play its
--- soundboards (`Sound.CHANNEL`), so the check covers the real playback path.
Diag.PROBE_CHANNEL = Sound.CHANNEL

--- Verdict of ONE sound file. ASCII identifiers, never displayed: the rendering
---   PLAYABLE     : the client answered that it WILL play the file;
---   NOT_PLAYABLE : the client answered that it will NOT play it (missing file,
---                  file added after the client started, playback refused);
---   NOT_TESTED   : the silence gate refused to probe (nothing was played);
---   UNKNOWN      : the probe could not be interpreted (PlaySoundFile absent or
---                  raising): we say so instead of inventing a verdict.
Diag.STATUS = {
    PLAYABLE = "playable",
    NOT_PLAYABLE = "notPlayable",
    NOT_TESTED = "notTested",
    UNKNOWN = "unknown",
}

--- Outcome of the SILENCE GATE (see the header). ASCII identifiers, never
--- displayed:
---   PROBE     : the Master channel is ENABLED and its volume is 0 -> the probe is
---               MEANINGFUL and INAUDIBLE, it may run;
---   SOUND_ON  : the volume is not 0 -> a probe would be HEARD, it does not run;
---   SOUND_OFF : the channel is disabled (or the sound is off in the client) -> a
---               probe would answer "nothing will play" for a file that IS there:
---               it does not run either (the verdict would be a lie);
---   UNKNOWN   : the sound state could not be read (no GetCVar, refused CVar) ->
---               we never probe on an unknown state.
Diag.GATE = {
    PROBE = "probe",
    SOUND_ON = "soundOn",
    SOUND_OFF = "soundOff",
    UNKNOWN = "unknown",
}

--- Maximum number of sound files the report accepts to probe: it guards the loop
--- against a hand-edited Sound.STATES/ALL_FILE_NAMES (same spirit as
--- BossFilter.MAX_IDS).
Diag.MAX_FILES = 12

--- PURE: the sound files of the addon, in the CANONICAL order of Core/Sound.lua
--- (the three soundboards, then the intermission start sound), each with the client
--- path the probe must use. Built from Sound.ALL_FILE_NAMES, so a file added there
--- appears here with no other change - the report can never forget one of them.
--- @return table array of { fileName = string, path = string }
function Diag.soundEntries()
    local out = {}
    for index = 1, #Sound.ALL_FILE_NAMES do
        if #out >= Diag.MAX_FILES then
            break
        end
        local fileName = Sound.ALL_FILE_NAMES[index]
        local path = Sound.FOLDER .. fileName
        if fileName == Sound.START_FILE then
            -- The intermission start sound owns its canonical path in Core/Sound.lua
            -- (startPath()): it must be the one that is really played.
            path = Sound.startPath()
        end
        out[#out + 1] = { fileName = fileName, path = path }
    end
    return out
end

--- How many sound files the report covers (4 today: the start sound + the three
--- soundboards). Used by the tests and by the report heading.
--- @return number
function Diag.count()
    return #Diag.soundEntries()
end

--- PURE: is a raw CVar value an ENABLED switch? The client writes booleans as
--- "0"/"1"; ONLY an exact "1" counts, so an absent or unexpected value (a refused
--- CVar, an out-of-game harness) never starts a probe on an unknown state.
--- @param raw string|nil
--- @return boolean
function Diag.isEnabled(raw)
    return raw == "1"
end

--- PURE: is a raw volume CVar worth ZERO? The client writes volumes as decimal
--- strings ("0", "0.000000", "1.000000"). A value that cannot be parsed is NOT
--- zero: we never ASSUME silence, we only use a value that proves it.
--- @param raw string|nil
--- @return boolean
function Diag.isSilentVolume(raw)
    if type(raw) ~= "string" then
        return false
    end
    return tonumber(raw) == 0
end

--- PURE: MAY THE AUDIO PROBE RUN WITHOUT MAKING ANY NOISE? (see the header)
--- `cvars` is read by the rendering layer: { allSound = <Sound_EnableAllSound>,
--- masterVolume = <Sound_MasterVolume> }.
--- @param cvars table|nil raw CVar strings
--- @return string Diag.GATE.*
function Diag.probeGate(cvars)
    local data = type(cvars) == "table" and cvars or {}
    if type(data.allSound) ~= "string" then
        return Diag.GATE.UNKNOWN
    end
    if not Diag.isEnabled(data.allSound) then
        return Diag.GATE.SOUND_OFF
    end
    if Diag.isSilentVolume(data.masterVolume) then
        return Diag.GATE.PROBE
    end
    return Diag.GATE.SOUND_ON
end

--- The value the rendering layer injects when the CLIENT GAVE NO USABLE ANSWER
--- (PlaySoundFile absent, or the call raised). It is distinct from nil on purpose:
--- `nil` returned by a REAL call means "the client will not play the file", while
--- this sentinel means "we know nothing" - the report says UNKNOWN instead of
--- accusing a file that may be perfectly fine.
Diag.NO_ANSWER = "noAnswer"

--- PURE: the verdict of ONE probe. `PlaySoundFile` returns `willPlay`: TRUE means
--- the client WILL play the file (it is loaded), nil/false means it will not
--- (missing file, file added after the client started, refused playback).
--- Diag.NO_ANSWER (the call could not be interpreted) and any unexpected value are
--- UNKNOWN - never a verdict.
--- @param willPlay any value injected by the rendering layer
--- @return string Diag.STATUS.*
function Diag.verdict(willPlay)
    if willPlay == true then
        return Diag.STATUS.PLAYABLE
    end
    if willPlay == false or willPlay == nil then
        return Diag.STATUS.NOT_PLAYABLE
    end
    return Diag.STATUS.UNKNOWN
end

--- PURE: did EVERY probed file come back "not playable"? A channel that refuses
--- every playback gives that answer for a file that IS there, so the report adds a
--- caveat instead of letting the player believe the four files are missing.
--- @param results table|nil array of verdict sources (the values of the probes)
--- @return boolean
function Diag.allRefused(results)
    local list = type(results) == "table" and results or {}
    local probe = {}
    for index = 1, #list do
        probe[#probe + 1] = list[index]
    end
    if #probe == 0 then
        return false
    end
    for index = 1, #probe do
        if Diag.verdict(probe[index]) ~= Diag.STATUS.NOT_PLAYABLE then
            return false
        end
    end
    return true
end

--- PURE: the localized line of ONE sound file. `status` is normalized: anything
--- that is not a known verdict reads as UNKNOWN, so a report can never show a
--- blank or a raw identifier.
--- @param fileName string|nil file name ("assign-1v3r.ogg")
--- @param status string|nil Diag.STATUS.*
--- @return string
function Diag.soundLine(fileName, status)
    local resolved = status
    if resolved ~= Diag.STATUS.PLAYABLE and resolved ~= Diag.STATUS.NOT_PLAYABLE and resolved ~= Diag.STATUS.NOT_TESTED then
        resolved = Diag.STATUS.UNKNOWN
    end
    return Locale.format("cmd.diag.sound." .. resolved, "Sound/" .. tostring(fileName))
end

--- PURE: why the audio probe ran (or not) - the ONE line that keeps the report
--- honest: it says what a "not playable" really means and how to get the missing
--- verdict. nil when the gate is unknown AND the rendering layer already told the
--- story (a report built by hand).
--- @param gate string|nil Diag.GATE.*
--- @return string|nil
function Diag.gateLine(gate)
    if gate == Diag.GATE.PROBE then
        return Locale.t("cmd.diag.gate.probe")
    end
    if gate == Diag.GATE.SOUND_ON then
        return Locale.t("cmd.diag.gate.soundOn")
    end
    return Locale.t("cmd.diag.gate.soundOff")
end

--- THE REPORT of `/gideon diag`: PURE and TOTAL - every value it displays is INJECTED
--- by the rendering layer (which alone reads the SavedVariables, the CVars and the
--- client), so the whole content is provable out of game.
--- @param context table|nil {
---   target    = string  effective auto-open target (BossFilter.targetSummary)
---   source    = string  where it comes from (BossFilter.sourceLine)
---   delivered = string  the default built into the addon (Config.delivered*Text)
---   idlog     = string  enabled/disabled word
---   pingMode  = string  ping policy identifier
---   ping      = string  what the policy means (Intermission.pingPolicyLine)
---   sound     = string  enabled/disabled word of the soundboard preference
---   gate      = string  Diag.GATE.* decision of the silence gate
---   results   = table   raw PlaySoundFile results, in soundEntries() order
--- }
--- @return table array of localized lines, ready to print as-is
function Diag.report(context)
    local ctx = type(context) == "table" and context or {}
    local entries = Diag.soundEntries()
    local results = type(ctx.results) == "table" and ctx.results or {}
    local lines = {}

    lines[#lines + 1] = Locale.t("cmd.diag.header")
    lines[#lines + 1] = Locale.format("cmd.diag.target", tostring(ctx.target or Locale.t("cmd.boss.value.absent")))
    if type(ctx.source) == "string" and ctx.source ~= "" then
        lines[#lines + 1] = ctx.source
    end
    if type(ctx.delivered) == "string" and ctx.delivered ~= "" then
        lines[#lines + 1] = ctx.delivered
    end
    lines[#lines + 1] = Locale.format("cmd.diag.idlog", tostring(ctx.idlog or "?"))
    lines[#lines + 1] = Locale.format("cmd.diag.ping", tostring(ctx.pingMode or "?"), tostring(ctx.ping or "?"))
    lines[#lines + 1] = Locale.format("cmd.diag.soundPref", tostring(ctx.sound or "?"))

    lines[#lines + 1] = Locale.format("cmd.diag.sounds", #entries)
    for index = 1, #entries do
        local status = Diag.STATUS.NOT_TESTED
        if ctx.gate == Diag.GATE.PROBE then
            status = Diag.verdict(results[index])
        end
        lines[#lines + 1] = Diag.soundLine(entries[index].fileName, status)
    end
    if ctx.gate == Diag.GATE.PROBE and Diag.allRefused(results) then
        -- Every file "not playable" smells like a channel that refuses every
        -- playback: say it instead of letting the player hunt four files.
        lines[#lines + 1] = Locale.t("cmd.diag.caveat")
    end
    local gate = Diag.gateLine(ctx.gate)
    if gate ~= nil then
        lines[#lines + 1] = gate
    end
    lines[#lines + 1] = Locale.t("cmd.diag.reminders")
    lines[#lines + 1] = Locale.t("cmd.diag.howToTest")
    return lines
end

return Diag
