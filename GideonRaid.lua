--[[--------------------------------------------------------------------------
    GideonRaid / GideonRaid.lua
    Entry point. Event registration, slash command, wiring.

    No combat API, no combat log event, no addon -> addon message:
    see docs/CONVENTIONS.md.
----------------------------------------------------------------------------]]
local addonName, ns = ...

GideonRaid = GideonRaid or {}
local GR = GideonRaid
ns.GR = GR

GR.NAME = addonName
GR.DISPLAY = "GideonRaid"
GR.VERSION = "0.2.0"

--- ---------------------------------------------------------------------------
--- LANGUAGE LAYER (wiring only: Core/ never calls an API).
--- GetLocale is the reference for the client language:
--- https://warcraft.wiki.gg/wiki/API:GetLocale  ->  "enUS", "frFR", "deDE", ...
--- English is the OFFICIAL language of the addon; French is served
--- automatically on a frFR client (see Core/Locale.lua and /gr lang).
--- ---------------------------------------------------------------------------
--- Reads the client language. Called under pcall: if GetLocale is missing
--- (out-of-game harness) or returns something unusable, the result is nil and
--- the effective language falls back to English.
local function detectLocale()
    local ok, value = pcall(GetLocale)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

--- Resolves and publishes the effective language:
---   db.locale (preference: "auto" | "en" | "fr")  +  GetLocale()  ->  "en"|"fr"
--- Publishes it in ns.Locale (string lookup) and in GR.locale (rest of the code).
local function applyLanguage()
    local db = _G.GideonRaidDB
    GR.detectedLocale = detectLocale()
    GR.localePreference = ns.Config.resolveLocale(type(db) == "table" and db.locale or nil)
    GR.locale = ns.Locale.setActive(ns.Locale.resolve(GR.localePreference, GR.detectedLocale))
    return GR.locale
end

--- Label of the keybinding shown in Options > Keybindings ("Panneau
--- Intermission" in French, English by default). The client reads these globals
--- when it builds the keybinding list, so they are refreshed with /gr lang.
local function applyBindingLabel()
    _G.BINDING_HEADER_GIDEONRAID = GR.DISPLAY
    _G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = ns.Locale.t("ui.bindingLabel")
end

local frame = CreateFrame("Frame")

local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    -- SavedVariables are assigned BEFORE ADDON_LOADED: safe to read here.
    _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
    _G.GideonRaidCharDB = _G.GideonRaidCharDB or {}
    -- Language BEFORE the UI is built: the static labels are created from the
    -- effective language.
    applyLanguage()
    applyBindingLabel()
    ns.UI.Initialize()
    ns.UI.IntermissionInitialize()
end

local function onPlayerLogin()
    ns.UI.Refresh()
end

-- API ref 12.x: https://warcraft.wiki.gg/wiki/Events
-- Constraint: ENCOUNTER_START / ENCOUNTER_END are instance events, NOT combat
-- log events. Their ARGUMENTS are not read: they only act as a TRIGGER for the
-- pre-computed timeline, which avoids handling any potentially secret value.
local function onEncounterStart()
    ns.UI.IntermissionOnEncounterStart()
end

local function onEncounterEnd()
    ns.UI.IntermissionOnEncounterEnd()
end

--- /gr lang (no argument): detected language, effective language and how to
--- change the preference.
local function printLanguage()
    local detected = GR.detectedLocale or ns.Locale.t("cmd.lang.undetected")
    ns.UI.Print(ns.Locale.format("cmd.lang.status", detected, GR.locale or ns.Locale.getActive(), GR.localePreference or ns.Locale.AUTO))
end

--- /gr lang <auto|en|fr>: rules on the preference, persists it in the
--- SavedVariables, re-applies the language and refreshes the panel labels.
--- An unknown value is REFUSED (nothing is persisted, nothing is guessed).
local function setLanguage(mode)
    local wanted = type(mode) == "string" and mode:lower() or ""
    local accepted = ns.Config.resolveLocale(wanted)
    if accepted ~= wanted then
        ns.UI.Print(ns.Locale.format("cmd.lang.unknown", tostring(mode)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        db.locale = accepted
    end
    applyLanguage()
    applyBindingLabel()
    ns.UI.ApplyStaticText()
    ns.UI.IntermissionApplyStaticText()
    ns.UI.Print(ns.Locale.format("cmd.lang.updated", accepted, GR.locale))
    return accepted
end

--- /gr ping (no argument): current ping policy and what it means for the roles.
local function printPingMode()
    local db = _G.GideonRaidDB
    local resolved = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil).pingMode
    ns.UI.Print(ns.Locale.format("cmd.ping.status", resolved, ns.Intermission.pingPolicyLine(resolved)))
end

--- /gr ping <anchors|color|none>: rules on the PING POLICY of the intermission
--- module, persists it in the SavedVariables and re-applies the panel labels.
--- An unknown value is REFUSED (nothing is persisted, nothing is guessed):
--- same mechanics as /gr lang.
local function setPingMode(mode)
    local wanted = type(mode) == "string" and mode:lower() or ""
    local accepted = ns.Config.resolvePingMode(wanted)
    if accepted ~= wanted then
        ns.UI.Print(ns.Locale.format("cmd.ping.unknown", tostring(mode)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        if type(db.intermission) ~= "table" then
            db.intermission = ns.Config.defaultIntermission()
        end
        db.intermission.pingMode = accepted
    end
    ns.UI.IntermissionApplyStaticText()
    ns.UI.Print(ns.Locale.format("cmd.ping.updated", accepted, ns.Intermission.pingPolicyLine(accepted)))
    return accepted
end

--- /gr sound (no argument): state of the ASSIGNMENT SOUNDBOARD preference and
--- how to change it. The sound itself is played by the rendering layer the moment
--- a composition is declared; Core/ owns the bounded resolution (only an exact
--- `false` mutes it).
local function printSoundSetting()
    local db = _G.GideonRaidDB
    local resolved = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
    local word = ns.Locale.t(resolved.soundEnabled and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.sound.status", word))
end

--- /gr sound on|off: rules on the ASSIGNMENT SOUNDBOARD preference, persists it in
--- the SavedVariables and says the new state. An unknown value is REFUSED
--- (nothing is persisted, nothing is guessed): same mechanics as /gr lang and
--- /gr ping.
local function setSoundSetting(raw)
    local wanted = type(raw) == "string" and raw:lower() or ""
    local accepted = ns.Sound.resolveSwitch(wanted)
    if accepted == nil then
        ns.UI.Print(ns.Locale.format("cmd.sound.unknown", tostring(raw)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        if type(db.intermission) ~= "table" then
            db.intermission = ns.Config.defaultIntermission()
        end
        db.intermission.soundEnabled = accepted
    end
    local word = ns.Locale.t(accepted and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.sound.updated", word))
    return accepted
end

--- /gr sound test <1v3r|2v2r|3v1r> (and `/gr sound test` alone, which recalls the
--- setting): plays ONE soundboard on request so the three files can be checked
--- without waiting for a fight. An unknown state is REFUSED and nothing is played.
local function soundCommand(argument)
    local tested = argument:match("^test%s+(.+)$")
    if tested ~= nil then
        ns.UI.SoundTest(tested)
        return
    end
    if argument == "test" then
        -- The state is missing: recall the setting (its text names the three
        -- accepted test values) instead of guessing which sound to play.
        printSoundSetting()
        return
    end
    setSoundSetting(argument)
end

local function slashHandler(cmd)
    cmd = (cmd or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Intermission declaration: any form accepted by Core ("3V1R", "2V2R",
    -- "1V3R", "3 verts", "2"). Subcommands (start/stop/on/off/status/macro/
    -- reset) are handled BEFORE, so everything else is a declaration.
    -- "1" or "3" ALONE is refused by Core (ambiguous): it asks for the color.
    local declaration = cmd:match("^inter%s+(.+)$")
    -- /gr lang <mode> : le mode est normalise en minuscules par l'appelant, donc
    -- le motif accepte n'importe quelle valeur et setLanguage() la juge.
    local langMode = cmd:match("^lang%s+(.+)$")
    -- /gr ping <mode> : same mechanics (the pattern accepts anything and
    -- setPingMode() judges it: an unknown value is refused).
    local pingMode = cmd:match("^ping%s+(.+)$")
    -- /gr sound <on|off|test ETA> : ASSIGNMENT SOUNDBOARD preference and its test
    -- entry. The pattern accepts anything and soundCommand() judges it: an unknown
    -- value is REFUSED (nothing is persisted, nothing is played).
    local soundArg = cmd:match("^sound%s+(.+)$")
    -- /gr sim <mode> : SIMULATION MODE (rehearsal alone, no boss, no raid).
    -- The pattern accepts anything and Core/Simulation.resolveCommand() judges it:
    -- an unknown value is REFUSED (nothing is guessed, nothing is launched).
    local simMode = cmd:match("^sim%s+(.+)$")
    if cmd == "" or cmd == "show" then
        ns.UI.Toggle()
    elseif cmd == "reset" then
        _G.GideonRaidDB = nil
        _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
        ns.UI.Refresh()
        ns.UI.Print(ns.Locale.t("cmd.reset"))
    elseif cmd == "status" then
        ns.UI.PrintStatus()
    elseif cmd == "plan" then
        ns.UI.PrintPlan()
    elseif cmd == "lang" then
        printLanguage()
    elseif langMode ~= nil then
        setLanguage(langMode)
    elseif cmd == "ping" then
        printPingMode()
    elseif pingMode ~= nil then
        setPingMode(pingMode)
    elseif cmd == "sound" then
        printSoundSetting()
    elseif soundArg ~= nil then
        soundCommand(soundArg)
    elseif cmd == "lock" then
        -- The main panel is movable by default; these three commands are the
        -- lock / unlock / reset-position entry points (same effect as the
        -- LOCK PANEL / UNLOCK PANEL button of the main panel).
        ns.UI.SetPanelLocked(true)
    elseif cmd == "unlock" then
        ns.UI.SetPanelLocked(false)
    elseif cmd == "resetposition" or cmd == "resetpos" then
        ns.UI.ResetPositions()
    elseif cmd == "inter" or cmd == "intermission" then
        ns.UI.IntermissionToggle()
    elseif cmd == "inter start" then
        ns.UI.IntermissionStart()
    elseif cmd == "inter stop" then
        ns.UI.IntermissionStop()
    elseif cmd == "inter reset" then
        ns.UI.IntermissionReset()
    elseif cmd == "inter status" then
        ns.UI.IntermissionStatus()
    elseif cmd == "inter ping" then
        ns.UI.IntermissionPrintPing()
    elseif cmd == "inter place" or cmd == "inter setup" then
        ns.UI.IntermissionSetup()
    elseif cmd == "inter on" then
        ns.UI.IntermissionSetEnabled(true)
    elseif cmd == "inter off" then
        ns.UI.IntermissionSetEnabled(false)
    elseif cmd == "sim" then
        ns.UI.Print(ns.Locale.t("cmd.sim.help"))
    elseif cmd == "pinghelp" then
        -- Alias of /gr sim ping: the SHORT help window (how to bind the keys and
        -- how to ping yourself). It simulates nothing and detects nothing.
        ns.UI.SimulationPingStart()
    elseif simMode ~= nil then
        ns.UI.SimulationCommand(simMode)
    elseif declaration ~= nil then
        ns.UI.IntermissionDeclare(declaration)
    else
        ns.UI.Print(ns.Locale.t("cmd.help"))
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        onAddonLoaded(arg1)
    elseif event == "PLAYER_LOGIN" then
        onPlayerLogin()
    elseif event == "ENCOUNTER_START" then
        onEncounterStart()
    elseif event == "ENCOUNTER_END" then
        onEncounterEnd()
    end
end)

_G.SLASH_GIDEONRAID1 = "/gr"
_G.SLASH_GIDEONRAID2 = "/gideonraid"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["GIDEONRAID"] = slashHandler

-- API ref 12.1.0: https://warcraft.wiki.gg/wiki/Creating_key_bindings
-- Bindings.xml is loaded AUTOMATICALLY by the client and must NOT be listed in
-- the .toc. The body of a binding is Lua executed insecurely: it only opens the
-- panel. This addon NEVER pings (the ping API is restricted to Blizzard's own
-- UI): the player pings themselves with the native ping keybind (Options >
-- Keybindings > ping system), and the addon only READS that key to display it.
-- The two globals below provide the labels shown in Options > Keybindings. They
-- are set in ENGLISH here (GideonRaid.lua is the FIRST file of the .toc, before
-- Core/Locale.lua) and refreshed in the effective language after ADDON_LOADED
-- and on every /gr lang through applyBindingLabel().
_G.BINDING_HEADER_GIDEONRAID = GR.DISPLAY
_G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = "Intermission panel (Entombed Sentinels)"
