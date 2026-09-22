--[[--------------------------------------------------------------------------
    GideonRaid / UI / Panel.lua

    RENDERING LAYER ONLY. This file may call the WoW API (frames, fonts).
    It must contain NO business computation: everything goes through ns.Pairing.

    12.x prohibitions (see docs/CONVENTIONS.md):
      - never read UnitAura / UnitHealth / UnitPower of another unit and test it
        in combat: the value may be SECRET.
      - never register a COMBAT LOG event (immediate error in 12.x, see
        docs/CONVENTIONS.md section 1.2).
      - never send an addon -> addon message in an instance.
    The data displayed here comes EXCLUSIVELY from GideonRaidDB (written out of
    game by GIDEON) or from the player's manual input.
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc (every displayed
--- string goes through it: English by default, French on a frFR client).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before UI/Panel.lua")

---@class UI
local UI = {}
ns.UI = UI

local panel

local function ensurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "GideonRaidPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 260)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not _G.GideonRaidDB or not _G.GideonRaidDB.lockPanel then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -16)
    panel.title:SetText("GideonRaid")

    panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.body:SetPoint("TOPLEFT", 16, -44)
    panel.body:SetPoint("BOTTOMRIGHT", -16, 16)
    panel.body:SetJustifyH("LEFT")
    panel.body:SetJustifyV("TOP")
    panel.body:SetText("")

    panel:Hide()
    return panel
end

function UI.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GideonRaid|r: " .. tostring(msg))
end

function UI.Toggle()
    local p = ensurePanel()
    if p:IsShown() then
        p:Hide()
    else
        UI.Refresh()
        p:Show()
    end
end

--- Rebuilds the display from non-secret data only.
--- The content (partner, roles, positions, pairs) is computed by
--- Core/Intermission.buildPlan: this layer only renders lines.
function UI.Refresh()
    local p = ensurePanel()
    --- API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
    --- Constraint: only the NAME of our own unit ("player") is read, never a
    --- unit value (health, aura, resource) that could be secret.
    local me = UnitName("player")
    local lines = {}
    local assignment, err = ns.Config.getAssignment()
    -- Ping policy of the "Intermission Coach" (persisted preference): displayed
    -- BEFORE the plan, because it decides which role pings and therefore whether
    -- a ping macro is needed at all.
    local intermission = ns.Config.resolveIntermission(_G.GideonRaidDB and _G.GideonRaidDB.intermission)

    if _G.GideonRaidDB and type(_G.GideonRaidDB.scale) == "number" then
        p:SetScale(_G.GideonRaidDB.scale)
    end

    lines[#lines + 1] = Locale.format("panel.pingPolicy", Locale.t("pingMode." .. intermission.pingMode))
    lines[#lines + 1] = ""

    if not assignment then
        lines[#lines + 1] = Locale.t("panel.noAssignment")
        lines[#lines + 1] = "|cff808080(" .. tostring(err) .. ")|r"
        lines[#lines + 1] = ""
        lines[#lines + 1] = Locale.t("panel.askGideon")
        lines[#lines + 1] = "!g roster assign"
    else
        local plan, planErr = ns.Intermission.buildPlan(assignment, me, intermission.pingMode)
        if not plan then
            lines[#lines + 1] = Locale.t("panel.unreadablePlan") .. " (" .. tostring(planErr) .. ")"
        else
            for _, line in ipairs(plan.lines) do
                lines[#lines + 1] = line
            end
        end
    end

    p.body:SetText(table.concat(lines, "\n"))
end

function UI.PrintStatus()
    local assignment, err = ns.Config.getAssignment()
    if not assignment then
        UI.Print(Locale.format("status.noAssignment", tostring(err)))
        return
    end
    UI.Print(Locale.format("status.ok", #assignment.pairs))
end

function UI.Initialize()
    ensurePanel()
end
