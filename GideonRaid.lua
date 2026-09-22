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
    ns.UI.IntermissionApplyStaticText()
    ns.UI.Print(ns.Locale.format("cmd.lang.updated", accepted, GR.locale))
    return accepted
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
    elseif cmd == "inter macro" then
        ns.UI.IntermissionPrintMacro()
    elseif cmd == "inter on" then
        ns.UI.IntermissionSetEnabled(true)
    elseif cmd == "inter off" then
        ns.UI.IntermissionSetEnabled(false)
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
-- panel (the addon can NOT send a ping, see C_Ping.SendMacroPing #protected).
-- The two globals below provide the labels shown in Options > Keybindings.
_G.BINDING_HEADER_GIDEONRAID = "GideonRaid"
_G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = "Panneau Intermission (Entombed Sentinels)"
