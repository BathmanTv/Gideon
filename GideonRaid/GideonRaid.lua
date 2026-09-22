--[[--------------------------------------------------------------------------
    GideonRaid / GideonRaid.lua
    Point d'entree. Enregistrement des evenements, slash command, cablage.
----------------------------------------------------------------------------]]
local addonName, ns = ...

GideonRaid = GideonRaid or {}
local GR = GideonRaid
ns.GR = GR

GR.NAME = addonName
GR.DISPLAY = "GideonRaid"
GR.VERSION = "0.1.0"

local frame = CreateFrame("Frame")

local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    -- SavedVariables sont affectees AVANT ADDON_LOADED : on peut lire ici.
    _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
    _G.GideonRaidCharDB = _G.GideonRaidCharDB or {}
    ns.UI.Initialize()
end

local function onPlayerLogin()
    ns.UI.Refresh()
end

local function slashHandler(cmd)
    cmd = (cmd or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if cmd == "" or cmd == "show" then
        ns.UI.Toggle()
    elseif cmd == "reset" then
        _G.GideonRaidDB = nil
        _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
        ns.UI.Refresh()
        ns.UI.Print("Configuration reinitialisee.")
    elseif cmd == "status" then
        ns.UI.PrintStatus()
    else
        ns.UI.Print("Commandes : /gr show | /gr status | /gr reset")
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        onAddonLoaded(arg1)
    elseif event == "PLAYER_LOGIN" then
        onPlayerLogin()
    end
end)

_G.SLASH_GIDEONRAID1 = "/gr"
_G.SLASH_GIDEONRAID2 = "/gideonraid"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["GIDEONRAID"] = slashHandler
