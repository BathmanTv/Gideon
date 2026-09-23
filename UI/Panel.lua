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

    The main panel is the pre-pull screen: it displays the prepared plan and its
    four buttons, IN THE ORDER computed by Core/Layout.lua
    (Layout.MAIN_PANEL_ORDER: place the intermission panel, the ping help window,
    the rehearsal, then the LOCK/UNLOCK utility, set apart). The geometry (frame
    size, every offset, every label) comes from that PURE module too: this file
    applies it as-is through UI.ApplyLayout and computes NOTHING.
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

--- The elements of the main panel, in the ORDER of Core/Layout.MAIN_PANEL_ORDER:
--- this list only tells the shared applier (UI.ApplyLayout) which frame carries
--- which block id. The geometry, the labels and the ORDER come from Core/.
--- @return table array of { id = string, frame = Frame|FontString }
--- Applies ONE block of a PURE layout (Core/Layout.lua) to its element: the
--- rendering layer copies the geometry and the text, it computes NOTHING.
--- @param frame Frame|FontString|nil
--- @param block table
local function applyBlock(frame, block)
    if frame == nil then
        return nil
    end
    frame:ClearAllPoints()
    frame:SetPoint(block.point, block.x, block.top)
    if block.kind == "button" then
        frame:SetSize(block.width, block.height)
    else
        -- A FontString has no SetSize: only its width is constrained (the height
        -- follows the text).
        frame:SetWidth(block.width)
    end
    frame:SetText(block.text)
    frame:Show()
    return frame
end

--- Applies a whole layout to a set of elements.
--- EVERY element handed in is hidden first: only the blocks the Core computed
--- are shown, so an element that is not part of the current layout (the three
--- composition buttons once a click hides them) can NEVER be drawn on top of
--- another one.
--- @param target Frame the panel
--- @param layout table computed by Core/Layout.lua
--- @param elements table array of { id = string, frame = Frame|FontString }
--- @return table the layout
function UI.ApplyLayout(target, layout, elements)
    local byId = {}
    for index = 1, #elements do
        local entry = elements[index]
        byId[entry.id] = entry.frame
        entry.frame:Hide()
        -- ... and it keeps NO stale text: the layout is the ONLY source of what
        -- is written on screen (a hidden "1V3R" must not survive a CORRIGER).
        entry.frame:SetText("")
    end
    target:SetSize(layout.width, layout.height)
    for index = 1, #layout.blocks do
        local block = layout.blocks[index]
        if block.kind == "row" then
            for item = 1, #block.items do
                applyBlock(byId[block.items[item].id], block.items[item])
            end
        else
            applyBlock(byId[block.id], block)
        end
    end
    return layout
end

local function panelElements(p)
    return {
        { id = "title", frame = p.title },
        { id = "body", frame = p.body },
        { id = "place", frame = p.place },
        { id = "simPing", frame = p.simPing },
        { id = "simInter", frame = p.simInter },
        { id = "lock", frame = p.lock },
    }
end

local function ensurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "GideonRaidPanel", UIParent, "BackdropTemplate")
    -- The size is NOT set here: Core/Layout.mainPanel() measures the content
    -- (labels included, in the active language) and UI.ApplyLayout applies it.
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetClampedToScreen(true)
    -- DRAGGING. The panel is movable BY DEFAULT (GideonRaidDB.lockPanel = false):
    -- in-game feedback showed that a panel the player cannot move is unusable.
    -- /gr lock (or the LOCK PANEL button) freezes the position; /gr unlock frees
    -- it again. The position is saved on every drag stop.
    panel:SetScript("OnDragStart", function(self)
        if UI.IsPanelLocked() then
            UI.Print(Locale.t("panel.lockedHint"))
            return
        end
        self:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePanelPosition()
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- NO fixed position anywhere: every element is anchored by the applier, one
    -- block BELOW the previous one (Core/Layout.lua), so no label can ever run
    -- over another one or over the borders, in English as in French.
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetJustifyH("CENTER")
    panel.title:SetText("")

    panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.body:SetJustifyH("LEFT")
    panel.body:SetJustifyV("TOP")
    panel.body:SetText("")

    -- Close CROSS ("X", top right): closes the main panel. Same label, same
    -- tooltip and same behaviour everywhere (shared helper).
    panel.closeCross = UI.AttachCloseCross(panel, function()
        panel:Hide()
    end)

    -- LOCK / UNLOCK of the panels: the label always names the ACTION the click
    -- performs (LOCK PANEL when the panel is movable, UNLOCK PANEL when it is
    -- frozen). Same mechanism as /gr lock and /gr unlock.
    panel.lock = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.lock:SetScript("OnClick", function()
        UI.SetPanelLocked(not UI.IsPanelLocked())
    end)

    -- Opens the PLACEMENT MODE of the intermission panel: the player drags it
    -- where it will appear during the fight, checks how to bind the ping, then
    -- validates with OK (step a and b of the evening flow).
    panel.place = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.place:SetScript("OnClick", function()
        UI.IntermissionSetup()
    end)

    -- The two SIMULATION entries (also reachable through /gr sim inter and
    -- /gr sim ping): rehearse ALONE, with no boss and no raid. The core logic
    -- lives in Core/Simulation.lua; this layer only calls it.
    panel.simInter = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.simInter:SetScript("OnClick", function()
        UI.SimulationInterStart()
    end)

    panel.simPing = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.simPing:SetScript("OnClick", function()
        UI.SimulationPingStart()
    end)

    panel:Hide()
    return panel
end

function UI.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GideonRaid|r: " .. tostring(msg))
end

--- True when the player froze the panels (persisted `lockPanel`). The resolving
--- is PURE (Core/Config.resolveLockPanel): an absent or mistyped value means NOT
--- locked, so a hand-edited SavedVariables can never lock the player out.
function UI.IsPanelLocked()
    local db = _G.GideonRaidDB
    return ns.Config.resolveLockPanel(type(db) == "table" and db.lockPanel or nil)
end

--- Reads the CURRENT anchor of a frame and returns a persistable position.
--- Pure data copy (no computation): shared by the main panel, the intermission
--- panel and the ping-training frame.
--- @param frame Frame
--- @return table { point, relativePoint, x, y }
function UI.CapturePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    return {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

--- Applies the PERSISTED position of the main panel (centered by default). The
--- stored block goes through the PURE resolver, so an unknown anchor point can
--- never reach SetPoint.
function UI.ApplyPanelPosition()
    local p = ensurePanel()
    local db = _G.GideonRaidDB
    local pos = ns.Config.resolvePosition(type(db) == "table" and db.panelPosition or nil)
    p:ClearAllPoints()
    p:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    return pos
end

--- Saves the current position of the main panel into the SavedVariables (called
--- on every drag stop: the player never has to confirm anything).
function UI.SavePanelPosition()
    if type(_G.GideonRaidDB) ~= "table" then
        return nil
    end
    _G.GideonRaidDB.panelPosition = UI.CapturePosition(ensurePanel())
    return _G.GideonRaidDB.panelPosition
end

--- Locks / unlocks the panels (/gr lock, /gr unlock, the LOCK PANEL button).
--- The choice is PERSISTED: it survives a /reload. The panel positions are kept.
--- @param locked boolean
--- @return boolean|nil effective value (nil when nothing could be written)
function UI.SetPanelLocked(locked)
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        UI.Print(Locale.t("ui.noSavedVariables"))
        return nil
    end
    local value = ns.Config.resolveLockPanel(locked and true or false)
    db.lockPanel = value
    UI.ApplyStaticText()
    UI.Print(Locale.t(value and "cmd.panelLocked" or "cmd.panelUnlocked"))
    return value
end

--- `/gr resetposition`: brings the main panel, the intermission panel and the
--- ping-training frame back to the center of the screen, and persists it.
function UI.ResetPositions()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        UI.Print(Locale.t("ui.noSavedVariables"))
        return nil
    end
    db.panelPosition = ns.Config.defaultPanelPosition()
    db.pingPanelPosition = ns.Config.defaultPanelPosition()
    if type(db.intermission) == "table" then
        db.intermission.position = ns.Config.defaultPanelPosition()
    end
    UI.ApplyPanelPosition()
    UI.IntermissionApplyConfig()
    UI.PingPanelApplyPosition()
    UI.Print(Locale.t("cmd.positionReset"))
    return true
end

function UI.Toggle()
    local p = ensurePanel()
    if p:IsShown() then
        p:Hide()
    else
        UI.ApplyPanelPosition()
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

--- Lays the main panel out: the WHOLE disposition (frame size, every offset,
--- every label and the button ORDER) comes from Core/Layout.lua, so it is proven
--- out of game in both languages (tests/spec/layout_spec.lua).
--- @param lines table body lines already computed by Core
--- @return table the applied layout
local function applyMainLayout(lines)
    local p = ensurePanel()
    local layout = ns.Layout.mainPanel({ bodyLines = lines, locked = UI.IsPanelLocked() })
    return UI.ApplyLayout(p, layout, panelElements(p))
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

    -- The DISPOSITION is computed by Core/Layout.lua from these real lines and
    -- applied as-is: the body is measured, wrapped and stacked under the title,
    -- and the frame grows to fit (no literal offset can collide).
    return applyMainLayout(lines)
end

--- Re-applies the language-dependent labels of THIS panel (the labels come from
--- Core/Layout.mainPanel, so a language change is a simple refresh).
function UI.ApplyStaticText()
    local p = ensurePanel()
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
    -- The persisted position is applied as soon as the panel exists: the player
    -- finds their panel where they left it, at the first /gr of the session.
    UI.ApplyPanelPosition()
    -- Labels + disposition come from Core/Layout.lua (nothing is hard-coded here).
    UI.ApplyStaticText()
end
