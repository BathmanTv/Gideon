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
--- The anchor point of a block or of a row button. Core/Layout.lua ALWAYS
--- provides one (a test asserts it block by block): this fallback is a safety net
--- only, because a nil point raises in the client and the whole applier then
--- stops - which is exactly how the three composition buttons and the OK button
--- disappeared in game (fifth in-game test: an element without an anchor).
--- @param block table
--- @return string anchor point
local function anchorOf(block)
    if type(block.point) == "string" and block.point ~= "" then
        return block.point
    end
    return "TOPLEFT"
end

--[[ THE CARD: a thin border and a discreet dark background behind a picture.

     The image "buttons" of the intermission panel (and the placement
     illustration) are CARDS, not Blizzard buttons: the raid lead asked for "just
     a frame with edges". HOW a card looks is NOT decided here - it is a
     PARAMETER read from Core/Layout.BUTTON_STYLES through Layout.style(name), so
     a future style is one entry in Core and one name passed to these helpers.
]]
--- Applies the style `styleName` (Core/Layout.BUTTON_STYLES) to a card frame.
--- THE INSETS COME FROM THE STYLE TOO: the ONE place that knows them is the style
--- table in Core (a UI/ file would be a second source of truth).
--- @param frame Frame the frame to dress
--- @param styleName string|nil name of the style (Layout.CHOICE_STYLE by default)
--- @return table the style table applied (never nil)
function UI.ApplyCardStyle(frame, styleName)
    local style = ns.Layout.style(styleName)
    if type(frame.SetBackdrop) == "function" then
        local insets = type(style.insets) == "table" and style.insets or nil
        frame:SetBackdrop({
            bgFile = style.bgFile,
            edgeFile = style.edgeFile,
            edgeSize = style.edgeSize,
            insets = {
                left = tonumber(insets and insets.left) or 0,
                right = tonumber(insets and insets.right) or 0,
                top = tonumber(insets and insets.top) or 0,
                bottom = tonumber(insets and insets.bottom) or 0,
            },
        })
    end
    frame.cardStyle = style
    return style
end

--- The state of a card, for the ONLY feedback it has (the border lights up).
--- THE TABLE IS CORE'S (Layout.CARD_STATE): the showcase forces a state on the
--- three example cards of "one card, three states", and the layout is the only
--- place that names a state - this alias exists so no UI/ file ever writes
--- "rest"/"hover"/"pressed" as a literal again.
UI.CARD_STATE = ns.Layout.CARD_STATE or { REST = "rest", HOVER = "hover", PRESSED = "pressed" }

--- The card's border/background colours of a state. NOTHING else moves and
--- nothing else is drawn: no glow, no pushed texture, no label, no second frame -
--- "the border lights up, nothing more" (raid-lead request). The ONE card of the
--- addon is the 1 px border of option 1, tinted with the GIDEON palette.
--- @param frame Frame a card
--- @param state string|nil UI.CARD_STATE value (REST by default)
--- @return table { r, g, b, a } the border colour applied
function UI.CardBorder(frame, state)
    local style = frame.cardStyle or ns.Layout.style(nil)
    local border = style.border
    if state == UI.CARD_STATE.HOVER then
        border = style.borderHover
    elseif state == UI.CARD_STATE.PRESSED then
        border = style.borderPressed
    end
    if type(frame.SetBackdropBorderColor) == "function" then
        frame:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
    end
    local background = style.background
    if background ~= nil and type(frame.SetBackdropColor) == "function" then
        frame:SetBackdropColor(background.r, background.g, background.b, background.a)
    end
    -- THE STATE IS REMEMBERED ON THE CARD: a redraw (a style change, a new click in
    -- the showcase) re-applies it instead of snapping a hovered card back to rest.
    frame.cardState = state or UI.CARD_STATE.REST
    return border
end

--- A CARD ready to be dressed and filled by Core: a frame of the given type with
--- its own picture (a child texture, so the border is never covered and the
--- picture is drawn WHOLE inside the padding of the style).
--- @param frameType string "Button" (clickable) or "Frame" (decoration only)
--- @param parent Frame
--- @param styleName string|nil
--- @return Frame the card
function UI.CreateCard(frameType, parent, styleName)
    local card = CreateFrame(frameType, nil, parent, "BackdropTemplate")
    card.picture = card:CreateTexture(nil, "ARTWORK")
    UI.ApplyCardStyle(card, styleName)
    UI.CardBorder(card, UI.CARD_STATE.REST)
    return card
end

--- A COLOUR CHIP of the style showcase: a plain frame filled with a flat white
--- texture, so a single SetBackdropColor paints it. The FILE comes from
--- Core/Layout.SWATCH_BG_FILE (Core/ remains the only place that names a client
--- file for the showcase), and the colour itself arrives with the block.
--- @param parent Frame
--- @return Frame the chip
function UI.CreateSwatch(parent)
    local chip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if type(chip.SetBackdrop) == "function" then
        chip:SetBackdrop({ bgFile = ns.Layout.SWATCH_BG_FILE })
    end
    return chip
end

--- Applies ONE block of a PURE layout (Core/Layout.lua) to its element: the
--- rendering layer copies the geometry and the text, it computes NOTHING.
--- An IMAGE block (the three orb cards of the intermission panel and the
--- placement illustration) is handled FIRST and differently: it draws a
--- PICTURE inside its border and carries no label at all - not even an empty one
--- (the raid lead asked for the picture INSTEAD of the written composition,
--- never next to it).
--- @param frame Frame|FontString|nil
--- @param block table
local function applyBlock(frame, block)
    if frame == nil then
        return nil
    end
    frame:ClearAllPoints()
    frame:SetPoint(anchorOf(block), block.x, block.top)
    if block.kind == "image" then
        frame:SetSize(block.width, block.height)
        -- The style is a DATA of the layout (Core named it): whatever table Core
        -- serves is applied as-is.
        UI.ApplyCardStyle(frame, block.style)
        -- A FORCED STATE (the "one card, three states" row of the showcase) wins
        -- over the remembered one: the three examples must show their state at the
        -- same time, next to each other.
        UI.CardBorder(frame, block.cardState or frame.cardState or UI.CARD_STATE.REST)
        if type(block.texture) == "string" and block.texture ~= "" then
            local picture = frame.picture
            if picture ~= nil and type(picture.SetTexture) == "function" then
                -- THE PICTURE IS DRAWN WHOLE: it is inset by the padding of the
                -- style, so the border never eats a slice of the orb.
                local padding = tonumber(block.padding) or 0
                picture:ClearAllPoints()
                picture:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
                picture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -padding, padding)
                picture:SetTexture(block.texture)
            elseif type(frame.SetNormalTexture) == "function" then
                -- Safety net for a frame built by another code path (no picture
                -- child): the picture is then the button's own texture.
                frame:SetNormalTexture(block.texture)
            end
        end
        frame:Show()
        return frame
    end
    if block.kind == "swatch" then
        -- A COLOUR CHIP of the style showcase: a plain tinted square, no texture,
        -- no label. Its colour is DATA of the layout (Core owns the palette).
        frame:SetSize(block.width, block.height)
        local color = block.color or {}
        if type(frame.SetBackdropColor) == "function" then
            frame:SetBackdropColor(color.r, color.g, color.b, color.a)
        end
        frame:Show()
        return frame
    end
    if block.kind == "button" then
        frame:SetSize(block.width, block.height)
    else
        -- A FontString has no SetSize: only its width is constrained (the height
        -- follows the text).
        frame:SetWidth(block.width)
    end
    frame:SetText(block.text)
    if block.kind == "text" then
        -- AN OPTIONAL EXPLICIT FONT, handed by Core (the two word sizes: an
        -- addon-created FontString with a file and a size we can verify, instead
        -- of a Blizzard font object whose size is unreadable out of game).
        if type(block.fontFile) == "string" and type(block.fontSize) == "number" and type(frame.SetFont) == "function" then
            frame:SetFont(block.fontFile, block.fontSize, "")
        end
        -- AN OPTIONAL EXPLICIT COLOUR, handed by Core too (the showcase writes the
        -- same word in the shipped green and in the GIDEON cyan, one above the
        -- other, so the raid lead can choose).
        if type(block.color) == "table" and type(frame.SetTextColor) == "function" then
            frame:SetTextColor(block.color.r, block.color.g, block.color.b, block.color.a or 1)
        end
    end
    frame:Show()
    return frame
end

--- The layout is the ONLY source of what is written on screen: an element that
--- is not part of the current layout is emptied, so a hidden "1V3R" can never
--- survive a CORRECT. AND IT IS A RESET, NOT A DRAW:
---   - a FontString and a Button carry a label, so they are emptied;
---   - A PLAIN FRAME CARRIES NO LABEL AT ALL (`Frame:SetText` does not exist in
---     the client: only Button / EditBox / FontString have it), and CALLING IT
---     RAISES. That call used to sit in the loop below, and the placement
---     illustration card - a plain Frame built by UI.CreateCard("Frame", ...) -
---     was enough to abort the WHOLE applier in game: every element had already
---     been hidden, no block had been applied yet, and the player was left in
---     front of an EMPTY panel with its border and its close cross (in-game
---     report: "on voit rien").
--- The capability is therefore TESTED, never assumed, exactly like the anchor
--- point above - and tests/support/wowapi_stub.lua refuses SetText on a plain
--- Frame like the client does, so this can never come back unnoticed.
--- @param frame Frame|FontString|nil
--- @return boolean true when the element was emptied
local function resetElement(frame)
    if frame == nil then
        return false
    end
    if type(frame.SetText) ~= "function" then
        -- No label to empty (a card, a plain Frame): nothing to reset. The
        -- element is still hidden by the caller.
        return false
    end
    frame:SetText("")
    return true
end

--- Applies a whole layout to a set of elements.
--- EVERY element handed in is hidden first: only the blocks the Core computed
--- are shown, so an element that is not part of the current layout (the three
--- composition buttons once a click hides them) can NEVER be drawn on top of
--- another one.
--- @param target Frame the panel
--- @param layout table computed by Core/Layout.lua
--- @param elements table array of { id = string, frame = Frame|FontString,
---   reset = function|nil } (reset: for a COMPOSITE element whose text lives in
---   a child, e.g. a palette swatch; it takes precedence over SetText)
--- @return table the layout
function UI.ApplyLayout(target, layout, elements)
    local byId = {}
    for index = 1, #elements do
        local entry = elements[index]
        byId[entry.id] = entry.frame
        entry.frame:Hide()
        if type(entry.reset) == "function" then
            entry.reset()
        else
            -- ... and it keeps NO stale text (see resetElement: a plain Frame has
            -- no SetText in the client, and calling it aborted the applier).
            resetElement(entry.frame)
        end
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
    db.showcasePosition = ns.Config.defaultPanelPosition()
    if type(db.intermission) == "table" then
        db.intermission.position = ns.Config.defaultPanelPosition()
    end
    UI.ApplyPanelPosition()
    UI.IntermissionApplyConfig()
    UI.PingPanelApplyPosition()
    if type(UI.ShowcaseApplyPosition) == "function" then
        UI.ShowcaseApplyPosition()
    end
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

--- ---------------------------------------------------------------------------
--- /gr diag - HEALTH REPORT OF THE ADDON (read-only)
---
--- ONE command that answers "is the addon healthy right now?" before a pull: the
--- four sound files (loaded and playable?), the EFFECTIVE auto-open target and
--- where it comes from, the idlog state and the ping policy. The content and every
--- rule live in Core/Diag.lua (PURE); this layer only READS the client (two sound
--- CVars, one PlaySoundFile per file) and prints the lines Core computed.
---
--- NO NOISE, EVER: the audio probe is started ONLY when Core/Diag's silence gate
--- proves it cannot be heard (Master channel ENABLED + volume exactly 0). With the
--- sound on, `/gr diag` plays NOTHING and says so, with the exact procedure to make
--- the check possible - an addon must never make noise in a raid.
--- ---------------------------------------------------------------------------

--- Client CVars the silence gate needs (API:GetCVar). They are READ ONLY: this
--- diagnostic never changes a setting of the player.
local DIAG_ALL_SOUND_CVAR = "Sound_EnableAllSound"
local DIAG_VOLUME_CVAR = "Sound_MasterVolume"

--- Reads ONE client CVar, read-only and under pcall. Out of game (no GetCVar, test
--- harness) or on a client that refuses the name, the value is nil and the probe is
--- then NOT started: an unknown sound state never makes us play anything.
--- 12.x still exposes the global `GetCVar` alias AND `C_CVar.GetCVar`: both are
--- tried, so the diagnostic works whichever one this client serves. Nothing is ever
--- SET (no SetCVar anywhere in the addon): the player's settings are only read.
--- @param name string CVar name
--- @return string|nil
local function readCVar(name)
    if type(_G.GetCVar) == "function" then
        local ok, value = pcall(_G.GetCVar, name)
        if ok and type(value) == "string" then
            return value
        end
    end
    local handle = _G.C_CVar
    if type(handle) == "table" and type(handle.GetCVar) == "function" then
        local ok, value = pcall(handle.GetCVar, name)
        if ok and type(value) == "string" then
            return value
        end
    end
    return nil
end

--- Probes ONE sound file WITHOUT emitting any noise, and reports whether the client
--- WOULD have played it. `PlaySoundFile` returns `willPlay`
--- (https://warcraft.wiki.gg/wiki/API:PlaySoundFile): true when the file is loaded
--- and the channel accepts the playback, nil/false otherwise (missing file, file
--- added after the client started, refused playback).
--- THE CALL ONLY EVER HAPPENS ON A SILENT CHANNEL: Core/Diag.probeGate has already
--- proven that the Master channel is ENABLED (so the answer means something) AND
--- that its volume is 0 (so nothing can be heard). Under pcall, like every other
--- client call of this addon.
--- @param path string|nil client sound path
--- @return boolean|string true/false = the client's answer, Diag.NO_ANSWER = no usable answer
local function probeSoundFile(path)
    if type(path) ~= "string" or path == "" then
        return ns.Diag.NO_ANSWER
    end
    if type(_G.PlaySoundFile) ~= "function" then
        return ns.Diag.NO_ANSWER
    end
    local ok, willPlay = pcall(_G.PlaySoundFile, path, ns.Diag.PROBE_CHANNEL)
    if not ok or type(willPlay) ~= "boolean" then
        -- The client refused the call (or answered something we cannot read): we say
        -- "unknown", we NEVER accuse a file that may be perfectly fine.
        return ns.Diag.NO_ANSWER
    end
    return willPlay
end

--- Runs the audio part of the diagnostic and returns the INJECTED context Core
--- needs: the gate decision and one raw answer per sound file.
--- @return table { gate = string, results = table }
function UI.DiagSoundProbe()
    local gate = ns.Diag.probeGate({
        allSound = readCVar(DIAG_ALL_SOUND_CVAR),
        masterVolume = readCVar(DIAG_VOLUME_CVAR),
    })
    local results = {}
    if gate == ns.Diag.GATE.PROBE then
        local entries = ns.Diag.soundEntries()
        for index = 1, #entries do
            results[index] = probeSoundFile(entries[index].path)
        end
    end
    return { gate = gate, results = results }
end

--- `/gr diag`: the whole HEALTH REPORT in one command (see the block above).
--- READ-ONLY: it writes nothing in the SavedVariables, sends nothing, pings
--- nothing and - unless the client is already muted - plays nothing.
--- @return table the lines printed (also handed back for the tests)
function UI.PrintDiag()
    local db = _G.GideonRaidDB
    local c = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
    local probe = UI.DiagSoundProbe()
    local lines = ns.Diag.report({
        target = ns.BossFilter.targetSummary(c),
        source = ns.BossFilter.sourceLine(c),
        delivered = Locale.format("cmd.boss.delivered", ns.Config.deliveredIdsText(), ns.Config.deliveredNamesText()),
        idlog = Locale.t(c.idlog and "ui.wordEnabled" or "ui.wordDisabled"),
        pingMode = tostring(c.pingMode),
        ping = ns.Intermission.pingPolicyLine(c.pingMode),
        sound = Locale.t(c.soundEnabled and "ui.wordEnabled" or "ui.wordDisabled"),
        gate = probe.gate,
        results = probe.results,
    })
    for index = 1, #lines do
        UI.Print(lines[index])
    end
    return lines
end

function UI.Initialize()
    ensurePanel()
    -- The persisted position is applied as soon as the panel exists: the player
    -- finds their panel where they left it, at the first /gr of the session.
    UI.ApplyPanelPosition()
    -- Labels + disposition come from Core/Layout.lua (nothing is hard-coded here).
    UI.ApplyStaticText()
end
