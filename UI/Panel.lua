--[[--------------------------------------------------------------------------
    GideonRaid / UI / Panel.lua

    RENDERING LAYER ONLY. This file may call the WoW API (frames, fonts).
    It must contain NO business computation: everything goes through ns.Pairing
    and ns.Intermission.

    12.x prohibitions (see docs/CONVENTIONS.md):
      - never read UnitAura / UnitHealth / UnitPower of another unit and test it
        in combat: the value may be SECRET.
      - never register a COMBAT LOG event (immediate error in 12.x, see
        docs/CONVENTIONS.md section 1.2).
      - never send an addon -> addon message in an instance.
    The data displayed here comes EXCLUSIVELY from GideonRaidDB (written out of
    game by GIDEON) or from the player's manual input.

    The main panel is the pre-pull screen: it displays the prepared plan and
    offers the "PLACE INTERMISSION PANEL" button (placement mode of the
    intermission panel, step a of the evening flow).
----------------------------------------------------------------------------]]
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc (every displayed
--- string goes through it: English by default, French on a frFR client).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before UI/Panel.lua")

---@class UI
local UI = {}
ns.UI = UI

local panel

--- Shared rendering helper: UI/Panel.lua is loaded BEFORE UI/Intermission.lua, so
--- both panels (main + intermission) use this ONE close cross.
--- A standard button ("X", top right) with a SHORT readable tooltip; the label
--- (ui.closeCross) and the tooltip text (ui.closeTooltip) come from
--- Core/Locale.lua: the rendering layer writes no literal (docs/CONVENTIONS.md
--- section 11).
--- @param frame Frame the frame to decorate
--- @param onClick function run when the cross is clicked
--- @return Button the cross
function UI.AttachCloseCross(frame, onClick)
    local cross = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cross:SetSize(22, 22)
    cross:SetPoint("TOPRIGHT", -8, -8)
    cross:SetText(Locale.t("ui.closeCross"))
    cross:SetScript("OnClick", function()
        onClick()
    end)
    cross:SetScript("OnEnter", function(self)
        -- Outside the client (test harness) GameTooltip does not exist: hovering
        -- shows nothing instead of raising.
        if type(_G.GameTooltip) ~= "table" then
            return
        end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText(Locale.t("ui.closeTooltip"), 1, 1, 1)
        _G.GameTooltip:Show()
    end)
    cross:SetScript("OnLeave", function()
        if type(_G.GameTooltip) ~= "table" then
            return
        end
        _G.GameTooltip:Hide()
    end)
    return cross
end

local function ensurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "GideonRaidPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 340)
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
    panel.body:SetPoint("BOTTOMRIGHT", -16, 92)
    panel.body:SetJustifyH("LEFT")
    panel.body:SetJustifyV("TOP")
    panel.body:SetText("")

    -- Close CROSS ("X", top right): closes the main panel. Same label, same
    -- tooltip and same behaviour everywhere (shared helper).
    panel.closeCross = UI.AttachCloseCross(panel, function()
        panel:Hide()
    end)

    -- Opens the PLACEMENT MODE of the intermission panel: the player drags it
    -- where it will appear during the fight, checks how to bind the ping, then
    -- validates with OK (step a and b of the evening flow).
    panel.place = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.place:SetSize(268, 24)
    panel.place:SetPoint("BOTTOM", 0, 14)
    panel.place:SetText(Locale.t("panel.placeButton"))
    panel.place:SetScript("OnClick", function()
        UI.IntermissionSetup()
    end)

    -- The two SIMULATION entries (also reachable through /gr sim inter and
    -- /gr sim ping): rehearse ALONE, with no boss and no raid. The core logic
    -- lives in Core/Simulation.lua; this layer only calls it.
    panel.simInter = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.simInter:SetSize(268, 22)
    panel.simInter:SetPoint("BOTTOM", 0, 40)
    panel.simInter:SetText(Locale.t("panel.simInterButton"))
    panel.simInter:SetScript("OnClick", function()
        UI.SimulationInterStart()
    end)

    panel.simPing = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.simPing:SetSize(268, 22)
    panel.simPing:SetPoint("BOTTOM", 0, 64)
    panel.simPing:SetText(Locale.t("panel.simPingButton"))
    panel.simPing:SetScript("OnClick", function()
        UI.SimulationPingStart()
    end)

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

--- Injected into Core (Core/ never calls an API): reads the key the player bound
--- to a native ping keybind. Read-only, under pcall. The candidate names come
--- from Core (their exact spelling is still TO BE CONFIRMED IN GAME).
local function resolveBindingKey(bindNames)
    if type(bindNames) ~= "table" or type(_G.GetBindingKey) ~= "function" then
        return nil
    end
    for index = 1, #bindNames do
        local ok, key = pcall(_G.GetBindingKey, bindNames[index])
        if ok and type(key) == "string" and key ~= "" then
            return key
        end
    end
    return nil
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
    local assignment = ns.Config.getAssignment()
    -- The ping policy is deliberately NOT displayed permanently: it only decides
    -- WHO has to ping (by default the 1V3R ANCHOR). It stays available through
    -- /gr ping and /gr inter status.
    local intermission = ns.Config.resolveIntermission(_G.GideonRaidDB and _G.GideonRaidDB.intermission)

    if _G.GideonRaidDB and type(_G.GideonRaidDB.scale) == "number" then
        p:SetScale(_G.GideonRaidDB.scale)
    end

    if not assignment then
        -- The out-of-game plan is OPTIONAL: say so, and never point the player to
        -- a command that does not exist.
        lines[#lines + 1] = Locale.t("panel.noPlan")
    else
        local plan, planErr = ns.Intermission.buildPlan(assignment, me, intermission.pingMode, resolveBindingKey)
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

--- Re-applies the language-dependent labels of THIS panel.
function UI.ApplyStaticText()
    local p = ensurePanel()
    p.place:SetText(Locale.t("panel.placeButton"))
    p.simInter:SetText(Locale.t("panel.simInterButton"))
    p.simPing:SetText(Locale.t("panel.simPingButton"))
    p.closeCross:SetText(Locale.t("ui.closeCross"))
    UI.Refresh()
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
