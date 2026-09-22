--[[--------------------------------------------------------------------------
    GideonRaid / GideonRaid.lua
    Point d'entree. Enregistrement des evenements, slash command, cablage.

    Aucune API de combat, aucun evenement de journal de combat, aucun message
    addon -> addon : voir docs/CONVENTIONS.md.
----------------------------------------------------------------------------]]
local addonName, ns = ...

GideonRaid = GideonRaid or {}
local GR = GideonRaid
ns.GR = GR

GR.NAME = addonName
GR.DISPLAY = "GideonRaid"
GR.VERSION = "0.2.0"

local frame = CreateFrame("Frame")

local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    -- SavedVariables sont affectees AVANT ADDON_LOADED : on peut lire ici.
    _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
    _G.GideonRaidCharDB = _G.GideonRaidCharDB or {}
    ns.UI.Initialize()
    ns.UI.IntermissionInitialize()
end

local function onPlayerLogin()
    ns.UI.Refresh()
end

-- Ref API 12.x : https://warcraft.wiki.gg/wiki/Events
-- Contrainte : ENCOUNTER_START / ENCOUNTER_END sont des evenements d'instance,
-- PAS des evenements de journal de combat. Leurs ARGUMENTS ne sont pas lus :
-- ils ne servent que de DECLENCHEUR de la timeline pre-calculee, ce qui evite
-- toute manipulation d'une valeur potentiellement secrete.
local function onEncounterStart()
    ns.UI.IntermissionOnEncounterStart()
end

local function onEncounterEnd()
    ns.UI.IntermissionOnEncounterEnd()
end

local function slashHandler(cmd)
    cmd = (cmd or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Declaration d'intermission : toute forme acceptee par Core (« 3V1R », « 2V2R »,
    -- « 1V3R », « 3 verts », « 2 »). Les sous-commandes (start/stop/on/off/status/
    -- macro/reset) sont traitees AVANT, donc tout le reste est une declaration.
    -- « 1 » ou « 3 » SEUL est refuse par Core (ambigu) : il demandera la couleur.
    local declaration = cmd:match("^inter%s+(.+)$")
    if cmd == "" or cmd == "show" then
        ns.UI.Toggle()
    elseif cmd == "reset" then
        _G.GideonRaidDB = nil
        _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
        ns.UI.Refresh()
        ns.UI.Print("Configuration reinitialisee.")
    elseif cmd == "status" then
        ns.UI.PrintStatus()
    elseif cmd == "plan" then
        ns.UI.PrintPlan()
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
        ns.UI.Print("Commandes : /gr | /gr plan | /gr status | /gr reset | /gr inter [start|stop|on|off|status|macro|3V1R|2V2R|1V3R]")
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

-- Ref API 12.1.0 : https://warcraft.wiki.gg/wiki/Creating_key_bindings
-- Bindings.xml est charge AUTOMATIQUEMENT par le client et ne doit PAS etre
-- liste dans le .toc. Le corps de la binding est du Lua execute insecurement :
-- il se contente d'ouvrir le panneau (l'addon ne peut PAS envoyer de ping, voir
-- C_Ping.SendMacroPing #protected). Les deux globales ci-dessous fournissent les
-- libelles affiches dans Options > Raccourcis.
_G.BINDING_HEADER_GIDEONRAID = "GideonRaid"
_G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = "Panneau Intermission (Entombed Sentinels)"
