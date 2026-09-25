--[[--------------------------------------------------------------------------
    GideonRaid / UI / Showcase.lua

    THE STYLE SHOWCASE: the in-game surface where the raid lead SEES the design -
    every font size, the palette with its hex codes, the three states of a card,
    the guild card at the real size of a fight, two animations - instead of
    judging on a board built outside the game. THERE IS NO STYLE PICKER ANY MORE
    (raid-lead decision 2026-09-25, "keep option 1"): the gallery of candidates is
    gone and the showcase shows the ONE delivered card.

    RENDERING LAYER ONLY. Every block, every size, every colour, every label and
    the action of every click come from Core/Layout.lua (Layout.showcasePanel and
    Layout.showcaseBannerPanel): this file copies them onto frames and computes
    NOTHING. It is loaded AFTER UI/Intermission.lua (it asks it whether a real
    fight is running) and NOTHING in the combat path ever calls it.

    IT EXISTS IN SIMULATION ONLY:
      - `/gr sim style` opens it, `/gr sim style 1` (or `shipped`) is accepted,
        anything else is refused;
      - it REFUSES to open while a real intermission is running, exactly like a
        rehearsal does (UI.IntermissionRealFlowBusy);
      - the SIMULATION banner lives in a FIXED strip above the scrolling area, so
        it is visible whatever the raid lead scrolls to: the showcase can never be
        mistaken for a fight;
      - its two animations (a fade-in of the panel and a discreet pulse of the
        border of one example card) only ever run HERE, are bounded by
        Core/Layout.fadeAlpha / Layout.pulseAlpha, and are stopped by
        `/gr sim anim off` (persisted) - no animation is wired into the combat
        panel at all.
----------------------------------------------------------------------------]]
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc: no literal string is
--- ever written here.
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before UI/Showcase.lua")
local Layout = assert(ns.Layout, "Core/Layout.lua must be loaded before UI/Showcase.lua")
local Sound = assert(ns.Sound, "Core/Sound.lua must be loaded before UI/Showcase.lua")

local UI = ns.UI

--- THE SHOWCASE FRAME (one, built on the first `/gr sim style`).
local showcase
--- The PREVIEW style (what the examples are drawn with) - Core's names only, and
--- never nil once the showcase has been opened.
local previewStyle
--- The composition currently DECLARED in the live section (nil = the three cards).
local declaredState
--- The elements of the showcase, by block id: created once, reused on every
--- redraw, so a click never builds a frame.
local elements = {}

--- The animation clock, in seconds since the showcase was OPENED (not since the
--- last redraw: clicking a card must not re-fade the panel).
local elapsed = 0

--- The client font OBJECT of every non-word style of Core/Layout.FONTS. The two
--- word styles carry an explicit font FILE and SIZE instead (Layout.wordFont), and
--- the applier overrides ours with it - a Blizzard font object hides its size and
--- an addon cannot read it out of game.
local FONT_OBJECT_BY_STYLE = {
    huge = "GameFontNormalHuge",
    large = "GameFontNormalLarge",
    normal = "GameFontNormal",
    small = "GameFontHighlightSmall",
    button = "GameFontNormal",
}

local function fontObjectOf(style)
    return FONT_OBJECT_BY_STYLE[style] or FONT_OBJECT_BY_STYLE.normal
end

--- The resolved intermission preferences of the player (Core/Config decides what a
--- missing or hand-edited value means): the style of the COMBAT panel, the
--- animation switch, the preview style.
local function config()
    local db = _G.GideonRaidDB
    return ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
end

--- Writes ONE field of the persisted intermission block, creating it when the
--- player has no save yet (exactly like GideonRaid.lua does for /gr sound).
--- @param key string
--- @param value any
local function persist(key, value)
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.intermission) ~= "table" then
        db.intermission = ns.Config.defaultIntermission()
    end
    db.intermission[key] = value
    return value
end

--- ---------------------------------------------------------------------------
--- POSITION (the showcase is draggable like the other panels)
--- ---------------------------------------------------------------------------

--- Applies the PERSISTED position of the showcase (centered by default). The
--- stored block goes through the pure resolver of Core/Config, so an unknown
--- anchor point can never reach SetPoint.
function UI.ShowcaseApplyPosition()
    if showcase == nil then
        return nil
    end
    local db = _G.GideonRaidDB
    local pos = ns.Config.resolvePosition(type(db) == "table" and db.showcasePosition or nil)
    showcase:ClearAllPoints()
    showcase:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    return pos
end

--- Saves the position of the showcase (drag stop). Same mechanics as the main
--- panel: the player never has to confirm anything.
function UI.ShowcaseSavePosition()
    if showcase == nil or type(_G.GideonRaidDB) ~= "table" then
        return nil
    end
    _G.GideonRaidDB.showcasePosition = UI.CapturePosition(showcase)
    return _G.GideonRaidDB.showcasePosition
end

--- ---------------------------------------------------------------------------
--- THE FRAME AND ITS ELEMENTS
--- ---------------------------------------------------------------------------

--- Creates the ONE showcase frame (lazily): a dialog frame like the others, a
--- FIXED banner strip at the top, a scrolling content frame below it, the shared
--- close cross and the wheel scrolling.
--- @return Frame
local function ensureShowcase()
    if showcase ~= nil then
        return showcase
    end
    local s = CreateFrame("Frame", "GideonRaidStyleShowcase", UIParent, "BackdropTemplate")
    s:SetMovable(true)
    s:EnableMouse(true)
    s:RegisterForDrag("LeftButton")
    s:SetClampedToScreen(true)
    s:SetScript("OnDragStart", function(self)
        if UI.IsPanelLocked() then
            UI.Print(Locale.t("panel.lockedHint"))
            return
        end
        self:StartMoving()
    end)
    s:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.ShowcaseSavePosition()
    end)
    s:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- THE FIXED STRIP: three FontStrings the LAYOUT fills (Core decides the text
    -- and the position, exactly like everywhere else).
    s.banner = s:CreateFontString(nil, "OVERLAY", fontObjectOf("large"))
    s.banner:SetJustifyH("CENTER")
    s.banner:SetText("")
    s.banner:Hide()

    s.bannerTitle = s:CreateFontString(nil, "OVERLAY", fontObjectOf("normal"))
    s.bannerTitle:SetJustifyH("CENTER")
    s.bannerTitle:SetText("")
    s.bannerTitle:Hide()

    s.bannerHint = s:CreateFontString(nil, "OVERLAY", fontObjectOf("small"))
    s.bannerHint:SetJustifyH("CENTER")
    s.bannerHint:SetText("")
    s.bannerHint:Hide()

    -- THE SCROLLING CONTENT: the showcase is taller than the window (typography,
    -- palette, and the ONE guild card example at the real size of a fight card), so
    -- the content is a
    -- child of a ScrollFrame and the wheel scrolls it.
    s.scroll = CreateFrame("ScrollFrame", "GideonRaidStyleShowcaseScroll", s)
    s.scroll:EnableMouseWheel(true)
    s.scroll:SetScript("OnMouseWheel", function(self, delta)
        local step = Layout.MARGIN_TOP + Layout.GAP
        self:SetVerticalScroll(math.max(0, self:GetVerticalScroll() - (delta * step)))
    end)
    s.content = CreateFrame("Frame", "GideonRaidStyleShowcaseContent", s.scroll)
    s.content:SetPoint("TOPLEFT")
    if type(s.scroll.SetScrollChild) == "function" then
        s.scroll:SetScrollChild(s.content)
    end

    s.closeCross = UI.AttachCloseCross(s, function()
        UI.ShowcaseClose()
    end)

    s:Hide()
    showcase = s
    return s
end

--- The element of ONE block of the showcase: created on first use (a card, a
--- colour chip, a button or a FontString) and REUSED afterwards. It also stamps on
--- the frame what a click has to do, so the wiring stays DATA of the layout.
--- @param block table a block (or a row item) of the showcase layout
--- @return Frame|FontString|nil the element (nil for a row, which owns no frame)
local function elementFor(block)
    local existing = elements[block.id]
    if existing ~= nil then
        return existing
    end
    local parent = showcase.content
    local frame
    if block.kind == "row" then
        return nil
    elseif block.kind == "image" then
        -- A CARD: clickable in the showcase (a composition declares itself), so it
        -- is built as a Button and never as a plain Frame (which has no label and
        -- no click).
        frame = UI.CreateCard("Button", parent, block.style)
        frame:RegisterForClicks("LeftButtonUp")
        frame:SetScript("OnEnter", function(self)
            UI.CardBorder(self, UI.CARD_STATE.HOVER)
        end)
        frame:SetScript("OnLeave", function(self)
            UI.CardBorder(self, UI.CARD_STATE.REST)
        end)
        frame:SetScript("OnMouseDown", function(self)
            UI.CardBorder(self, UI.CARD_STATE.PRESSED)
        end)
        frame:SetScript("OnMouseUp", function(self)
            UI.CardBorder(self, UI.CARD_STATE.HOVER)
        end)
        frame:SetScript("OnClick", function(self)
            -- DECLARE is the ONLY action a card can carry now: there is no
            -- candidate style left to preview.
            if self.showcaseAction == Layout.SHOWCASE_ACTION.DECLARE then
                UI.ShowcaseDeclare(self.showcaseState)
            end
        end)
    elseif block.kind == "swatch" then
        frame = UI.CreateSwatch(parent)
    elseif block.kind == "button" then
        frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        frame:SetScript("OnClick", function()
            UI.ShowcaseRedo()
        end)
    else
        frame = parent:CreateFontString(nil, "OVERLAY", fontObjectOf(block.style))
        frame:SetJustifyH(block.align == "center" and "CENTER" or "LEFT")
        frame:SetText("")
    end
    frame.showcaseKind = block.kind
    elements[block.id] = frame
    return frame
end

--- Walks a layout (blocks + row items), creating the element of each one and
--- stamping what a click must do. Returns nothing: the applier draws them all
--- afterwards, and EVERY element ever created is hidden first, so a block that
--- left the layout (the three cards once a composition is declared) can never
--- survive on screen.
local function collectElements(layout)
    for index = 1, #layout.blocks do
        local block = layout.blocks[index]
        local frame = elementFor(block)
        if frame ~= nil then
            if block.action ~= nil then
                frame.showcaseAction = block.action
            end
            if block.state ~= nil then
                frame.showcaseState = block.state
            end
            if block.cardState ~= nil then
                frame.showcaseForcedState = block.cardState
            end
        end
        for item = 1, #(block.items or {}) do
            local current = block.items[item]
            local itemFrame = elementFor(current)
            if itemFrame ~= nil then
                if current.action ~= nil then
                    itemFrame.showcaseAction = current.action
                end
                if current.state ~= nil then
                    itemFrame.showcaseState = current.state
                end
                if current.cardState ~= nil then
                    itemFrame.showcaseForcedState = current.cardState
                end
            end
        end
    end
end

--- EVERY element of the showcase, as the applier wants it ({ id, frame }), in a
--- DETERMINISTIC order: the map is walked by sorted id, so a redraw lays the same
--- frames out in the same order.
--- @return table array
local function allElements()
    local ids = {}
    for id in pairs(elements) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    local list = {}
    for index = 1, #ids do
        list[#list + 1] = { id = ids[index], frame = elements[ids[index]] }
    end
    return list
end

--- ---------------------------------------------------------------------------
--- ANIMATIONS (fade-in of the panel + pulse of one border)
--- ---------------------------------------------------------------------------

--- Stops every animation: NO update script is left on the frame (nothing runs at
--- all, not even an idle callback) and the panel is fully opaque again. The
--- pulsing card is put back to its rest border.
local function stopAnimations()
    if showcase == nil then
        return false
    end
    showcase:SetScript("OnUpdate", nil)
    showcase:SetAlpha(1)
    local target = showcase.pulseTarget
    if target ~= nil then
        UI.CardBorder(target, target.showcaseForcedState or UI.CARD_STATE.REST)
    end
    return true
end

--- Arms the animation clock: the fade-in starts at 0 alpha and the pulsing border
--- is driven by the SAME OnUpdate, so there is ONE clock and one place to stop it.
local function startAnimations()
    if showcase == nil then
        return false
    end
    elapsed = 0
    showcase:SetScript("OnUpdate", function(_, dt)
        UI.ShowcaseOnUpdate(dt)
    end)
    return true
end

--- ONE animation frame, driven by the OnUpdate script of the showcase (the only
--- place it is ever armed). Core decides the two alphas: this function only hands
--- them to the client, and it does NOTHING once the showcase is hidden.
--- @param dt number seconds since the previous frame
function UI.ShowcaseOnUpdate(dt)
    if showcase == nil or not showcase:IsShown() then
        return nil
    end
    elapsed = elapsed + (tonumber(dt) or 0)
    showcase:SetAlpha(Layout.fadeAlpha(elapsed))
    -- THE PULSE: the border of ONE example card, and only while it is at rest (a
    -- hovered card keeps its hover colour: the feedback wins over the animation).
    local target = showcase.pulseTarget
    if target ~= nil and (target.cardState == nil or target.cardState == UI.CARD_STATE.REST) then
        local style = target.cardStyle
        local border = style ~= nil and style.border or nil
        if border ~= nil and type(target.SetBackdropBorderColor) == "function" then
            target:SetBackdropBorderColor(border.r, border.g, border.b, Layout.pulseAlpha(elapsed))
        end
    end
    return elapsed
end

--- ---------------------------------------------------------------------------
--- PUBLIC API
--- ---------------------------------------------------------------------------

--- True while the showcase frame exists and is shown.
function UI.ShowcaseIsShown()
    return showcase ~= nil and showcase:IsShown()
end

--- The frames of the showcase, keyed by BLOCK ID: the scrolling content AND the
--- three blocks of the fixed strip, so a caller (or a test) can reach every element
--- of the surface without poking at the client. Read-only: nothing outside this
--- file ever replaces an element.
--- @return table map id -> Frame
function UI.ShowcaseElements()
    local merged = {}
    for id, frame in pairs(elements) do
        merged[id] = frame
    end
    if showcase ~= nil then
        merged.showcaseBanner = showcase.banner
        merged.showcaseTitle = showcase.bannerTitle
        merged.showcaseHint = showcase.bannerHint
    end
    return merged
end

--- The style the examples are currently drawn with (Core's canonical name).
--- @return string
function UI.ShowcasePreviewStyle()
    if previewStyle == nil then
        previewStyle = config().showcaseStyle
    end
    return previewStyle
end

--- Redraws the whole showcase from the PURE layouts of Core: the fixed strip (the
--- SIMULATION banner never scrolls away) and the scrolling content. Every element
--- is created once, hidden by the applier and re-drawn from the layout.
--- @return table the content layout applied
function UI.ShowcaseRefresh()
    local s = ensureShowcase()
    local c = config()

    -- THE FIXED STRIP.
    local strip = Layout.showcaseBannerPanel()
    UI.ApplyLayout(s, strip, {
        { id = "showcaseBanner", frame = s.banner },
        { id = "showcaseTitle", frame = s.bannerTitle },
        { id = "showcaseHint", frame = s.bannerHint },
    })

    -- THE SCROLLING CONTENT, right under the strip. Its height is the strip's real
    -- height (Core measured it), so nothing can overlap the banner.
    s.scroll:ClearAllPoints()
    s.scroll:SetPoint("TOPLEFT", s, "TOPLEFT", 8, -(strip.height + 8))
    s.scroll:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -8, 8)

    local layout = Layout.showcasePanel({
        style = UI.ShowcasePreviewStyle(),
        realStyle = c.style,
        animations = c.showcaseAnimations,
        showChoices = declaredState == nil,
        wordText = declaredState ~= nil and Locale.t("state.word." .. declaredState) or nil,
        wordState = declaredState,
    })
    collectElements(layout)
    UI.ApplyLayout(s.content, layout, allElements())

    -- The frame wraps the ribbon AND the scrolling window (a fixed window height:
    -- the content scrolls INSIDE it, it is never stretched to 2400 px on screen).
    s:SetSize(strip.width, Layout.SHOWCASE_WINDOW_HEIGHT + strip.height)
    -- THE PULSING CARD: the first composition of the live row (visible as soon as
    -- the showcase opens). Once a composition is declared the live row is gone, so
    -- the pulse moves to the first style example instead of animating a hidden
    -- frame.
    s.pulseTarget = elements["liveChoice1"]
    if declaredState ~= nil then
        s.pulseTarget = elements["styleCard1"]
    end

    if Layout.animationsEnabled(c.showcaseAnimations) then
        startAnimations()
    else
        stopAnimations()
    end
    return layout
end

--- OPENS the style showcase (`/gr sim style`, and `/gr sim style 1|shipped`).
--- REFUSED while a real fight is running or a timeline is armed: the showcase is a
--- SIMULATION surface, and nothing in it may ever appear during an intermission.
--- @param raw string|nil style written by the player (the delivered card only)
--- @return Frame|nil the showcase frame (nil when it was refused)
function UI.ShowcaseOpen(raw)
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return nil
    end
    -- THE SHOWCASE IS A SIMULATION SURFACE: it is REFUSED while a real fight is
    -- running, BEFORE anything is created - the window does not even exist. An
    -- unknown style is refused the same way: nothing is built, nothing is shown.
    if UI.IntermissionRealFlowBusy() then
        UI.Print(Locale.t("sim.refused.live"))
        return nil
    end
    if raw ~= nil then
        local name = Layout.resolveStyle(raw)
        if name == nil or not Layout.isCandidateStyle(name) then
            UI.Print(Locale.format("cmd.sim.styleUnknown", tostring(raw)))
            return nil
        end
        previewStyle = name
        persist("showcaseStyle", name)
    end
    local s = ensureShowcase()
    if previewStyle == nil then
        previewStyle = c.showcaseStyle
    end
    UI.ShowcaseApplyPosition()
    s:Show()
    elapsed = 0
    UI.ShowcaseRefresh()
    UI.Print(Locale.t("showcase.opened"))
    return s
end

--- CLOSES the showcase (the close cross): the frame is hidden AND every animation
--- is stopped - a hidden showcase runs nothing at all.
--- @return boolean true when something was shown
function UI.ShowcaseClose()
    if showcase == nil then
        return false
    end
    local wasShown = showcase:IsShown()
    stopAnimations()
    showcase:Hide()
    return wasShown
end

--- `/gr sim anim on|off` (and `/gr sim anim` alone, which recalls the setting):
--- the two showcase animations, PERSISTED. An unknown value is REFUSED (nothing
--- is written, nothing is guessed): same mechanics as `/gr sound on|off`.
--- @param raw string|nil
--- @return boolean|nil the accepted value
function UI.ShowcaseAnimationsCommand(raw)
    local c = config()
    if raw == nil then
        UI.Print(Locale.format("cmd.sim.animState", Layout.settingWord(c.showcaseAnimations)))
        return nil
    end
    local wanted = Sound.resolveSwitch(raw)
    if wanted == nil then
        UI.Print(Locale.t("cmd.sim.animUsage"))
        return nil
    end
    persist("showcaseAnimations", wanted)
    if UI.ShowcaseIsShown() then
        UI.ShowcaseRefresh()
    end
    UI.Print(Locale.format("showcase.animUpdated", Layout.settingWord(wanted)))
    return wanted
end

--- DECLARES a composition in the live section of the showcase: the three cards
--- give way to the ONE giant word and the assignment soundboard plays - EXACTLY the
--- combat behaviour, through the SAME rendering functions (UI.PlayAssignSound).
--- The assignment gate is re-armed first: a showcase is a DEMONSTRATION, so every
--- click must make a sound (in a fight, one sound per declaration is the rule).
--- @param state string|nil canonical state ("1V3R" | "2V2R" | "3V1R")
--- @return boolean played
function UI.ShowcaseDeclare(state)
    local key = ns.Textures.resolveState(state)
    if key == nil then
        return false
    end
    declaredState = key
    UI.ResetAssignSound()
    local played = UI.PlayAssignSound(key)
    if UI.ShowcaseIsShown() then
        UI.ShowcaseRefresh()
    end
    return played
end

--- BACK TO THE THREE CARDS (the CORRECT button of the live section), exactly like
--- UI.IntermissionRedo does on the combat panel: the word is forgotten and the
--- soundboard gate is re-armed.
--- @return boolean
function UI.ShowcaseRedo()
    declaredState = nil
    UI.ResetAssignSound()
    if UI.ShowcaseIsShown() then
        UI.ShowcaseRefresh()
    end
    return true
end

--- The composition currently declared in the showcase (nil = the three cards).
--- Exported for the tests and for the diagnostic messages.
--- @return string|nil
function UI.ShowcaseDeclaredState()
    return declaredState
end
