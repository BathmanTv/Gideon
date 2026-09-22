--[[--------------------------------------------------------------------------
    GideonRaid / UI / Intermission.lua

    RENDERING LAYER ONLY ("Intermission Coach"). This file may call the WoW API
    (frames, fonts, C_Timer). It contains NO business computation: everything
    comes from ns.Intermission.snapshot() / ns.Intermission.buildPlan().

    12.x prohibitions (see docs/CONVENTIONS.md):
      - no read of aura / health / resource (possible SECRET value);
      - no combat log event;
      - no addon -> addon message in an instance;
      - no ping sent by the addon: C_Ping.SendMacroPing is #protected
        (https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing). The addon only
        DISPLAYS the text of a macro that the player triggers.

    What the player sees here is LOCAL to their client: the addon cannot know
    what other players see or what they declare.
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc (every string
--- displayed in game goes through it: English by default, French on frFR).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before UI/Intermission.lua")

local UI = ns.UI or {}
ns.UI = UI

local TICK_SECONDS = 0.1

--- API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
--- Constraint: this panel only displays strings written by the player
--- (1/2/3 click) or prepared out of game (GIDEON SavedVariables). No unit value
--- is read, hence no comparison on a secret value.
local function config()
    local db = _G.GideonRaidDB
    return ns.Config.resolveIntermission(db and db.intermission)
end

local panel, ticker, state

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function ensureTicker()
    if ticker then
        return ticker
    end
    -- The time step is a LOCAL CONSTANT: no value read from the client, so the
    --- Core module stays pure and deterministic (testable with an injected dt).
    ticker = C_Timer.NewTicker(TICK_SECONDS, function()
        UI.IntermissionTick(TICK_SECONDS)
    end)
    return ticker
end

local function ensurePanel()
    if panel then
        return panel
    end

    local p = CreateFrame("Frame", "GideonRaidIntermissionPanel", UIParent, "BackdropTemplate")
    p:SetSize(560, 400)
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetClampedToScreen(true)
    p:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.IntermissionSavePosition()
    end)
    p:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", 0, -14)
    p.title:SetText(Locale.t("ui.panelTitle"))

    -- The convention reminder, in very large type (module requirement).
    p.headline = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.headline:SetPoint("TOP", 0, -40)
    p.headline:SetText("")

    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetPoint("TOPLEFT", 24, -96)
    p.body:SetWidth(492)
    p.body:SetJustifyH("LEFT")
    p.body:SetJustifyV("TOP")
    p.body:SetText("")

    p.buttons = {}
    -- Three buttons: the player clicks the ORB COMPOSITION seen above their
    -- head. The label comes from Core ("3 verts + 1 rouge / 3V1R /
    -- numero : 1 ou 3"): the UI layer computes nothing.
    -- The number is only a HINT: 1 and 3 are AMBIGUOUS about the color, only 2
    -- is unambiguous (2 verts + 2 rouges).
    for index = 1, #ns.Intermission.STATES do
        local key = ns.Intermission.STATES[index]
        local rec = ns.Intermission.getDeclaration(key)
        local button = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        button:SetSize(168, 64)
        button:SetPoint("TOPLEFT", 20 + ((index - 1) * 176), -208)
        button:SetText(rec ~= nil and rec.buttonLabel or key)
        button:SetScript("OnClick", function()
            UI.IntermissionDeclare(key)
        end)
        p.buttons[index] = button
    end

    p.macroLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.macroLabel:SetPoint("TOPLEFT", 24, -284)
    p.macroLabel:SetText(Locale.t("ui.macroLabel"))

    p.macroBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    p.macroBox:SetSize(492, 24)
    p.macroBox:SetPoint("TOPLEFT", 24, -302)
    p.macroBox:SetAutoFocus(false)
    p.macroBox:SetText("")
    p.macroBox:SetTextInsets(6, 6, 0, 0)
    p.macroBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    p.macroBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    p.note = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", 24, -334)
    p.note:SetWidth(492)
    p.note:SetJustifyH("LEFT")
    p.note:SetText("")

    p.close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetSize(90, 22)
    p.close:SetPoint("BOTTOMRIGHT", -16, 14)
    p.close:SetText(Locale.t("ui.close"))
    p.close:SetScript("OnClick", function()
        UI.IntermissionHide()
    end)

    p:Hide()
    panel = p
    return panel
end

--- Applies the configured scale + position (no business computation).
function UI.IntermissionApplyConfig()
    local p = ensurePanel()
    local c = config()
    local pos = c.position
    p:SetScale(c.scale)
    p:ClearAllPoints()
    p:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

--- Saves the current panel position into the SavedVariables.
function UI.IntermissionSavePosition()
    local p = ensurePanel()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" or type(db.intermission) ~= "table" then
        return
    end
    local point, _, relativePoint, x, y = p:GetPoint(1)
    db.intermission.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

--- Rebuilds the display from the state computed by Core/.
function UI.IntermissionRefresh()
    local p = ensurePanel()
    local snap = ns.Intermission.snapshot(state)
    p.headline:SetText(snap.headline)
    p.body:SetText(table.concat(snap.lines, "\n"))
    for _, button in ipairs(p.buttons) do
        -- Label already set at creation (it comes from Core and never changes):
        -- here we only show/hide.
        button:SetShown(snap.showButtons)
    end
    p.macroBox:SetText(snap.macroPrimary or "")
    if snap.macroPrimary then
        p.note:SetText(Locale.format("ui.macroFallback", tostring(snap.macroFallback), tostring(snap.macroNote)))
    else
        p.note:SetText(Locale.t("ui.macroPrompt"))
    end
    return snap
end

function UI.IntermissionShow()
    local p = ensurePanel()
    UI.IntermissionApplyConfig()
    UI.IntermissionRefresh()
    p:Show()
end

function UI.IntermissionHide()
    local p = ensurePanel()
    p:Hide()
end

--- Manual key/button: shows (or hides) the intermission panel.
function UI.IntermissionToggle()
    local p = ensurePanel()
    if p:IsShown() then
        p:Hide()
        return
    end
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if state == nil or state.phase == ns.Intermission.PHASE.IDLE then
        UI.IntermissionStart()
        return
    end
    UI.IntermissionShow()
end

--- Starts the intermission (trigger: key, button, or ENCOUNTER_START).
function UI.IntermissionStart()
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if state == nil then
        state = ns.Intermission.newState()
    end
    local started, err = ns.Intermission.start(state, {
        visibilitySeconds = c.visibilitySeconds,
        durationSeconds = c.durationSeconds,
    })
    if not started then
        UI.Print(Locale.format("ui.intermissionError", tostring(err)))
        return
    end
    ensureTicker()
    UI.Print(Locale.format("ui.started", c.visibilitySeconds))
    if c.autoShowPanel then
        UI.IntermissionShow()
    end
end

function UI.IntermissionStop()
    stopTicker()
    if state ~= nil then
        ns.Intermission.reset(state)
    end
    local p = ensurePanel()
    p:Hide()
end

function UI.IntermissionReset()
    stopTicker()
    if state ~= nil then
        ns.Intermission.reset(state)
    end
    UI.IntermissionRefresh()
end

--- Advances by one tick. dt is injected by the ticker (local constant): Core
--- never reads the client clock.
function UI.IntermissionTick(dt)
    if state == nil then
        return
    end
    ns.Intermission.tick(state, dt)
    UI.IntermissionRefresh()
    if state.phase == ns.Intermission.PHASE.DONE then
        stopTicker()
    end
end

--- Player declaration: click on a COMPOSITION button (3V1R / 2V2R / 1V3R).
--- A bare ambiguous number ("1" or "3" alone) is refused by Core with a message
--- asking for the dominant color.
function UI.IntermissionDeclare(declaration)
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if state == nil or state.phase == ns.Intermission.PHASE.IDLE then
        UI.IntermissionStart()
    end
    local _, err = ns.Intermission.declare(state, declaration)
    if err ~= nil then
        UI.Print(Locale.format("ui.declarationRefused", tostring(err)))
        return
    end
    -- We PUBLISH the timestamped decision into the SavedVariables: the
    -- diagnostic kit (GideonDiagAddon) reads it afterwards, with no chat input
    -- during combat and no inter-addon communication.
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        local clock
        if type(date) == "function" then
            clock = date("%Y-%m-%d %H:%M:%S")
        end
        ns.Config.recordDecision(db, {
            composition = state.declaration,
            at = (type(time) == "function") and time() or nil,
            clock = clock,
            source = "coach-panel",
        })
    end
    UI.IntermissionRefresh()
end

--- ENCOUNTER_START is an instance event, not a combat log one. Its arguments
--- are NOT read (no secret value risk): only the trigger is used.
function UI.IntermissionOnEncounterStart()
    local c = config()
    if not c.enabled or not c.startOnEncounterStart then
        return
    end
    UI.IntermissionStart()
end

function UI.IntermissionOnEncounterEnd()
    UI.IntermissionStop()
end

function UI.IntermissionSetEnabled(enabled)
    local db = _G.GideonRaidDB
    if type(db) ~= "table" or type(db.intermission) ~= "table" then
        UI.Print(Locale.t("ui.noSavedVariables"))
        return
    end
    db.intermission.enabled = enabled and true or false
    UI.Print(Locale.t(enabled and "ui.enabled" or "ui.disabledState"))
end

function UI.IntermissionStatus()
    local c = config()
    local snap = ns.Intermission.snapshot(state)
    UI.Print(
        Locale.format(
            "ui.statusLine",
            Locale.t(c.enabled and "ui.wordEnabled" or "ui.wordDisabled"),
            snap.phase,
            tostring(snap.declaration)
        )
    )
    UI.Print(Locale.format("ui.timelineLine", c.visibilitySeconds, c.durationSeconds, c.scale))
end

function UI.IntermissionPrintMacro()
    local snap = ns.Intermission.snapshot(state)
    if not snap.macroPrimary then
        UI.Print(Locale.t("ui.noMacro"))
        return
    end
    UI.Print(Locale.format("ui.macroToPaste", snap.macroPrimary))
    UI.Print(Locale.format("ui.macroFallbackLine", tostring(snap.macroFallback), tostring(snap.macroNote)))
end

--- Prints the plan prepared out of game into the chat (same source as the panel).
function UI.PrintPlan()
    local me = UnitName("player")
    local assignment, err = ns.Config.getAssignment()
    if not assignment then
        UI.Print(Locale.format("status.noAssignment", tostring(err)))
        return
    end
    local plan, planErr = ns.Intermission.buildPlan(assignment, me)
    if not plan then
        UI.Print(Locale.format("ui.unreadablePlan", tostring(planErr)))
        return
    end
    for _, line in ipairs(plan.lines) do
        UI.Print(line)
    end
end

--- Re-applies every LANGUAGE-DEPENDENT label (panel chrome + composition
--- buttons). Called at initialization and after a language change (/gr lang):
--- the strings come from Core, so the UI only copies them.
function UI.IntermissionApplyStaticText()
    local p = ensurePanel()
    p.title:SetText(Locale.t("ui.panelTitle"))
    p.macroLabel:SetText(Locale.t("ui.macroLabel"))
    p.close:SetText(Locale.t("ui.close"))
    for index = 1, #ns.Intermission.STATES do
        local key = ns.Intermission.STATES[index]
        local rec = ns.Intermission.getDeclaration(key)
        local button = p.buttons[index]
        if button ~= nil then
            button:SetText(rec ~= nil and rec.buttonLabel or key)
        end
    end
    UI.IntermissionRefresh()
end

function UI.IntermissionInitialize()
    ensurePanel()
    UI.IntermissionApplyConfig()
    UI.IntermissionApplyStaticText()
end
