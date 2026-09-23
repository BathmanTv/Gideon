--[[--------------------------------------------------------------------------
    GideonRaid / Core / Layout.lua

    PURE LOGIC (Lua 5.1). No WoW API, no event, no clock, no random: this file
    runs as-is under busted and under lua5.1 outside the client.

    WHY: the in-game layout of the panels must be PROVABLE out of game. The
    fourth in-game test reported (a) labels running over the borders of the main
    panel and (b) the big state ("2V2R") drawn ON TOP of the SIMULATION banner:
    every element was positioned with a FIXED Y offset, so the blocks collided
    as soon as a line was added or translated.

    RULE enforced here: every element is a BLOCK of an ORDERED LIST, anchored
    BELOW the previous one by construction (top = previous bottom - gap). Two
    blocks can therefore NEVER share the same Y, in English as in French, and
    the frame is exactly as wide as the widest unwrappable element (buttons and
    button rows) requires. The rendering layer applies the list AS-IS
    (UI.ApplyLayout) and computes nothing.

    The text metrics below are ESTIMATES (the game font cannot be measured out
    of game): they are deliberately CONSERVATIVE (wider and taller than the real
    glyphs) so a real in-game line is never longer nor taller than the estimated
    one. Every block is measured, wrapped and stacked here, which makes the
    whole layout TESTABLE: tests/spec/layout_spec.lua asserts, for BOTH
    languages, that no two blocks overlap, that no text runs over the borders
    and that nothing is drawn under the close cross.
----------------------------------------------------------------------------]]
--
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc (the panel builders
--- name the labels through it: no in-game literal is written here).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before Core/Layout.lua")

--- Core/Intermission.lua is loaded BEFORE this file by the .toc: the three
--- composition buttons and their labels come from the canonical states (no
--- duplicated table, they cannot drift).
local Intermission = assert(ns.Intermission, "Core/Intermission.lua must be loaded before Core/Layout.lua")

---@class Layout
local Layout = {}
ns.Layout = Layout

--[[ ---------------------------------------------------------------- metrics

     height     = one display line, in pixels (GameFontNormalHuge ... Small);
     charWidth  = average width of one character, in pixels. Deliberately
                  WIDE: a real line is never wider than the estimate, so a
                  layout validated out of game never overflows in game.
]]
Layout.FONTS = {
    huge = { height = 34, charWidth = 20 },
    large = { height = 18, charWidth = 9 },
    normal = { height = 15, charWidth = 7 },
    small = { height = 13, charWidth = 6 },
    -- Buttons of UIPanelButtonTemplate: a little narrower than GameFontNormal.
    button = { height = 15, charWidth = 6.2 },
}
Layout.FONT_FALLBACK = "normal"

--- Inner margin of every panel (the dialog border is 32 px wide: keep clear).
Layout.MARGIN_X = 16
Layout.MARGIN_TOP = 12
Layout.MARGIN_BOTTOM = 12
--- Space between two stacked blocks: never zero, so two blocks can never touch.
Layout.GAP = 6
--- Horizontal padding of a button label (both sides together).
Layout.BUTTON_PADDING_X = 12
--- The close cross ("X") of UI.AttachCloseCross occupies this small box in the
--- top-right corner of every panel: no block may be drawn under it.
Layout.CROSS_SIZE = 22
Layout.CROSS_OFFSET = 8

--- Frame widths of the three surfaces (they may only GROW: a wide label always
--- wins over the nominal width, see build()).
Layout.MAIN_PANEL_WIDTH = 360
Layout.INTERMISSION_WIDTH = 560
Layout.PING_HELP_WIDTH = 520

--- Composition buttons of the intermission panel (fixed in game: their three
--- line labels were validated in game, they are not measured here).
Layout.CHOICE_WIDTH = 168
Layout.CHOICE_HEIGHT = 64
Layout.CHOICE_GAP = 8

Layout.DEFAULT_WIDTH = 320

local function font(style)
    return Layout.FONTS[style] or Layout.FONTS[Layout.FONT_FALLBACK]
end

Layout.font = font

local function round(n)
    return math.floor(n + 0.5)
end

--[[ ------------------------------------------------------------- measuring
]]

--- Splits a text on its EXPLICIT newlines (a button label may carry them).
--- @param text string|nil
--- @return table array of lines (never empty: "" yields one empty line)
function Layout.splitLines(text)
    local value = type(text) == "string" and text or ""
    local out = {}
    if value == "" then
        out[1] = ""
        return out
    end
    local start = 1
    while true do
        local first, last = value:find("\n", start, true)
        if first == nil then
            out[#out + 1] = value:sub(start)
            return out
        end
        out[#out + 1] = value:sub(start, first - 1)
        start = last + 1
    end
end

--- Estimated width of the WIDEST explicit line (no wrapping), in pixels.
--- @param text string|nil
--- @param style string|nil font style key
--- @return number
function Layout.textWidth(text, style)
    local metrics = font(style)
    local widest = 0
    local lines = Layout.splitLines(text)
    for index = 1, #lines do
        local width = #lines[index] * metrics.charWidth
        if width > widest then
            widest = width
        end
    end
    return widest
end

--- Estimated width of the widest single WORD: a word cannot be wrapped, so a
--- block narrower than its widest word would push text over the border in game.
--- @return number
function Layout.wordWidth(text, style)
    local metrics = font(style)
    local widest = 0
    local lines = Layout.splitLines(text)
    for index = 1, #lines do
        for word in lines[index]:gmatch("%S+") do
            local width = #word * metrics.charWidth
            if width > widest then
                widest = width
            end
        end
    end
    return widest
end

--- How many DISPLAY lines an explicit line occupies in a `width` px block.
--- @return number (never below 1)
function Layout.wrapCount(line, style, width)
    local limit = tonumber(width) or 0
    if limit <= 0 then
        return 1
    end
    local metrics = font(style)
    local pixels = #(type(line) == "string" and line or "") * metrics.charWidth
    if pixels <= 0 then
        return 1
    end
    local count = math.ceil(pixels / limit)
    if count < 1 then
        count = 1
    end
    return count
end

--- Height of a text block once wrapped to `width` (pixels).
--- @return number
function Layout.textHeight(text, style, width)
    local metrics = font(style)
    local lines = 0
    local parts = Layout.splitLines(text)
    for index = 1, #parts do
        lines = lines + Layout.wrapCount(parts[index], style, width)
    end
    if lines < 1 then
        lines = 1
    end
    return lines * metrics.height
end

--[[ --------------------------------------------------------------- packing
]]

--- Width a block needs when it can NOT wrap (button, row of buttons). nil for a
--- plain text block (it wraps to whatever width it is given).
--- @return number|nil
local function fixedWidth(raw, gap)
    if raw.kind == "button" then
        if type(raw.width) == "number" then
            return raw.width
        end
        local padding = tonumber(raw.paddingX) or Layout.BUTTON_PADDING_X
        return Layout.textWidth(raw.text, raw.style or "button") + (2 * padding)
    end
    if raw.kind == "row" then
        local items = raw.items or {}
        if #items == 0 then
            return 0
        end
        local total = 0
        for index = 1, #items do
            local item = items[index]
            if type(item.width) == "number" then
                total = total + item.width
            else
                local padding = tonumber(item.paddingX) or Layout.BUTTON_PADDING_X
                total = total + Layout.textWidth(item.text, item.style or "button") + (2 * padding)
            end
        end
        return total + ((#items - 1) * (tonumber(raw.gap) or gap))
    end
    return nil
end

Layout.fixedWidth = fixedWidth

--- Packs the buttons of one row: "left" items from the left margin, "right"
--- items from the right margin (the FIRST right item is the rightmost one).
--- @param items table array of { id, text, align, width, height, style }
--- @param frameWidth number
--- @param marginX number
--- @param gap number
--- @return table array of items with x/width/height/top (top is filled later)
local function packRow(items, frameWidth, marginX, gap)
    local packed = {}
    local leftCursor = marginX
    local rightCursor = frameWidth - marginX
    for index = 1, #items do
        local raw = items[index]
        local style = raw.style or "button"
        local metrics = font(style)
        local width = raw.width
        if type(width) ~= "number" then
            local padding = tonumber(raw.paddingX) or Layout.BUTTON_PADDING_X
            width = Layout.textWidth(raw.text, style) + (2 * padding)
        end
        local height = raw.height
        if type(height) ~= "number" then
            height = metrics.height + 6
        end
        local item = {
            id = raw.id or ("item" .. index),
            kind = "button",
            align = raw.align == "right" and "right" or "left",
            text = raw.text,
            style = style,
            width = width,
            height = height,
        }
        if item.align == "right" then
            item.x = rightCursor - width
            rightCursor = item.x - gap
        else
            item.x = leftCursor
            leftCursor = item.x + width + gap
        end
        packed[#packed + 1] = item
    end
    return packed
end

--- Lays one block out: its size (and its point/x anchor) for a frame of
--- `frameWidth`. Does NOT set top/bottom (build() stacks the blocks).
--- @param raw table block description
--- @param frameWidth number
--- @param marginX number
--- @param gap number
--- @return table measured block
local function measureBlock(raw, frameWidth, marginX, gap)
    local inner = frameWidth - (2 * marginX)
    local block = {
        id = raw.id or "block",
        kind = raw.kind or "text",
        align = raw.align or "left",
        style = raw.style or Layout.FONT_FALLBACK,
        text = raw.text,
    }
    if block.kind == "row" then
        block.width = frameWidth
        block.items = packRow(raw.items or {}, frameWidth, marginX, tonumber(raw.gap) or gap)
        block.height = 0
        for index = 1, #block.items do
            if block.items[index].height > block.height then
                block.height = block.items[index].height
            end
        end
        if block.height <= 0 then
            block.height = font("button").height
        end
        block.point = "TOPLEFT"
        block.x = 0
        return block
    end
    if block.kind == "button" then
        local style = raw.style or "button"
        local metrics = font(style)
        local padding = tonumber(raw.paddingX) or Layout.BUTTON_PADDING_X
        block.style = style
        block.height = type(raw.height) == "number" and raw.height or (metrics.height + 6)
        block.width = type(raw.width) == "number" and raw.width or (Layout.textWidth(block.text, style) + (2 * padding))
        if block.align == "center" then
            block.point = "TOP"
            block.x = 0
        elseif block.align == "right" then
            block.point = "TOPRIGHT"
            block.x = -marginX
        else
            block.point = "TOPLEFT"
            block.x = marginX
        end
        return block
    end
    -- Plain text: it wraps inside the width it is given. `textWidth` is the
    -- width really DRAWN (the widest line, capped by the block): a CENTERED text
    -- is centered on it, and the "under the close cross" check uses it too.
    block.width = type(raw.width) == "number" and raw.width or inner
    block.textWidth = Layout.textWidth(block.text, block.style)
    block.height = type(raw.height) == "number" and raw.height or Layout.textHeight(block.text, block.style, block.width)
    if block.align == "center" then
        block.point = "TOP"
        block.x = 0
    else
        block.point = "TOPLEFT"
        block.x = marginX
    end
    return block
end

--- Builds a full layout: an ORDERED list of blocks, each one anchored BELOW the
--- previous one. The frame height is derived from the last block, so no element
--- can ever be pushed out of the frame.
--- @param spec table { blocks = array, width = number|nil, minWidth = number|nil,
---                     marginX/marginTop/marginBottom/gap = number|nil }
--- @return table { width, height, marginX, gap, blocks }
function Layout.build(spec)
    local source = type(spec) == "table" and spec or {}
    local marginX = tonumber(source.marginX) or Layout.MARGIN_X
    local marginTop = tonumber(source.marginTop) or Layout.MARGIN_TOP
    local marginBottom = tonumber(source.marginBottom) or Layout.MARGIN_BOTTOM
    local gap = tonumber(source.gap) or Layout.GAP
    local blocks = source.blocks or {}

    -- 1. The frame is NEVER narrower than what the unwrappable blocks need.
    local width = tonumber(source.minWidth) or Layout.DEFAULT_WIDTH
    if type(source.width) == "number" and source.width > width then
        width = source.width
    end
    for index = 1, #blocks do
        local needed = fixedWidth(blocks[index], gap)
        if needed ~= nil and (needed + (2 * marginX)) > width then
            width = needed + (2 * marginX)
        end
    end

    -- 2. Stack the blocks: each top is the previous bottom minus the gap, minus
    --    the optional EXTRA space of the block (gapBefore: a utility button, such
    --    as LOCK PANEL, is separated from the flow buttons without breaking the
    --    "each block below the previous one" rule).
    local measured = {}
    local cursor = -marginTop
    for index = 1, #blocks do
        local block = measureBlock(blocks[index], width, marginX, gap)
        local extra = tonumber(blocks[index].gapBefore) or 0
        if extra < 0 then
            extra = 0
        end
        block.gapBefore = extra
        block.top = cursor - extra
        block.bottom = block.top - block.height
        if block.kind == "row" then
            for item = 1, #block.items do
                -- Bottom-aligned inside the row (buttons of different heights).
                block.items[item].top = block.bottom + block.items[item].height
                block.items[item].bottom = block.items[item].top - block.items[item].height
            end
        end
        cursor = block.bottom - gap
        measured[#measured + 1] = block
    end

    local height = marginTop + marginBottom
    if #measured > 0 then
        height = -measured[#measured].bottom + marginBottom
    end

    return {
        width = round(width),
        height = round(height),
        marginX = marginX,
        marginTop = marginTop,
        marginBottom = marginBottom,
        gap = gap,
        blocks = measured,
    }
end

--- Width really DRAWN by a block: a left/right-aligned text uses its whole box,
--- a CENTERED text only as much as its widest line (a centered short title must
--- not be reported as if it covered the whole frame width).
--- @return number
function Layout.drawnWidth(block)
    if block.kind == "text" and type(block.textWidth) == "number" then
        if block.textWidth < block.width then
            return block.textWidth
        end
    end
    return block.width
end

--- Horizontal extent of a block inside its frame (for the bounds checks).
--- @return number left, number right
function Layout.bounds(block, layout)
    local marginX = tonumber(layout.marginX) or Layout.MARGIN_X
    local width = Layout.drawnWidth(block)
    local left
    if block.align == "center" then
        left = (layout.width - width) / 2
    elseif block.align == "right" then
        left = layout.width - marginX - width
    else
        left = tonumber(block.x) or 0
    end
    return left, left + width
end

--- An unbreakable word wider than its block: the only way a wrapped text can
--- still run over the border in game.
local function blockIsWide(block)
    return Layout.wordWidth(block.text, block.style) > block.width
end

--- True when a rectangle (block or row item) is drawn under the close cross.
--- @param top number top edge (negative offsets from the frame top)
--- @param bottom number bottom edge
local function underCross(layout, left, right, top, bottom)
    local crossLeft = layout.width - Layout.CROSS_OFFSET - Layout.CROSS_SIZE
    local crossRight = layout.width - Layout.CROSS_OFFSET
    local crossTop = -Layout.CROSS_OFFSET
    local crossBottom = crossTop - Layout.CROSS_SIZE
    local shareX = left < crossRight and crossLeft < right
    local shareY = bottom < crossTop and crossBottom < top
    return shareX and shareY
end

--- Every layout defect, as readable strings (empty table = the layout is sound).
--- Two rules, the two bugs reported in game:
---   - no two blocks may share a Y band (the state must never be drawn on top of
---     the SIMULATION banner);
---   - no block may run over the borders of the frame, nor under the close
---     cross, and no unbreakable word may be wider than its block.
--- @param layout table
--- @return table array of strings
function Layout.violations(layout)
    local problems = {}
    if type(layout) ~= "table" or type(layout.blocks) ~= "table" then
        problems[1] = "layout missing"
        return problems
    end
    local blocks = layout.blocks
    local function report(message)
        problems[#problems + 1] = message
    end

    for index = 1, #blocks do
        local block = blocks[index]
        local left, right = Layout.bounds(block, layout)
        if left < 0 or right > layout.width then
            report(string.format("block '%s' runs over the side border (%.1f..%.1f of %d)", block.id, left, right, layout.width))
        end
        if block.top > 0 or block.bottom < -layout.height then
            report(
                string.format(
                    "block '%s' runs over the top/bottom border (%.1f..%.1f of %d)",
                    block.id,
                    block.top,
                    block.bottom,
                    layout.height
                )
            )
        end
        if underCross(layout, left, right, block.top, block.bottom) then
            report(string.format("block '%s' runs under the close cross", block.id))
        end
        if block.kind == "row" then
            for item = 1, #block.items do
                local current = block.items[item]
                if current.x < 0 or (current.x + current.width) > layout.width then
                    report(string.format("row button '%s' runs over the side border", current.id))
                end
                if current.text ~= nil and Layout.wordWidth(current.text, current.style) > current.width then
                    report(string.format("label of row button '%s' is wider than its button", current.id))
                end
                if underCross(layout, current.x, current.x + current.width, current.top, current.bottom) then
                    report(string.format("row button '%s' runs under the close cross", current.id))
                end
                for other = item + 1, #block.items do
                    local candidate = block.items[other]
                    if current.x < (candidate.x + candidate.width) and candidate.x < (current.x + current.width) then
                        report(string.format("row buttons '%s' and '%s' overlap", current.id, candidate.id))
                    end
                end
            end
        elseif block.text ~= nil then
            if blockIsWide(block) then
                report(string.format("text of block '%s' is wider than its block", block.id))
            end
        end
        -- No two blocks in the same column band may overlap vertically.
        for other = index + 1, #blocks do
            local candidate = blocks[other]
            local otherLeft, otherRight = Layout.bounds(candidate, layout)
            local shareX = left < otherRight and otherLeft < right
            local overlapY = block.bottom < candidate.top and candidate.bottom < block.top
            if shareX and overlapY then
                report(string.format("blocks '%s' and '%s' overlap vertically", block.id, candidate.id))
            end
        end
    end
    return problems
end

--[[ ------------------------------------------------------------ panel specs

     The three surfaces of the addon. The order of the blocks IS the order on
     screen (top to bottom): the rendering layer copies it.
]]

--- Main panel (/gr) BUTTON ORDER, top to bottom (raid lead's request, fourth
--- in-game test): the three buttons of the EVENING FLOW first - place the panel,
--- the ping explanation window, then the rehearsal - and the LOCK/UNLOCK utility
--- LAST, set apart by an extra space (it is not a step of the flow).
--- This list is the single source of the order: mainPanel() builds its blocks
--- from it and tests/spec/layout_spec.lua locks it down.
Layout.MAIN_PANEL_ORDER = { "place", "simPing", "simInter", "lock" }

--- Extra space above the utility button, so it reads as a separate tool.
Layout.MAIN_PANEL_UTILITY_GAP = 14

--- Main panel (/gr): title, body, then the four buttons IN THE ORDER of
--- MAIN_PANEL_ORDER.
--- @param spec table|nil { bodyLines = array of strings, locked = boolean|nil }
function Layout.mainPanel(spec)
    local opts = type(spec) == "table" and spec or {}
    local bodyLines = opts.bodyLines or {}
    local labels = {
        place = Locale.t("panel.placeButton"),
        simPing = Locale.t("panel.simPingButton"),
        simInter = Locale.t("panel.simInterButton"),
        lock = Locale.t(opts.locked and "panel.unlockButton" or "panel.lockButton"),
    }
    local blocks = {
        { id = "title", kind = "text", align = "center", style = "normal", text = Locale.t("ui.mainTitle") },
        { id = "body", kind = "text", align = "left", style = "small", text = table.concat(bodyLines, "\n") },
    }
    -- ONE width for the four buttons: the three FLOW buttons then line up exactly
    -- (same left/right edges, regular spacing) whatever the language, and the
    -- widest label decides for all of them.
    local buttonWidth = 0
    for index = 1, #Layout.MAIN_PANEL_ORDER do
        local width = Layout.textWidth(labels[Layout.MAIN_PANEL_ORDER[index]], "button") + (2 * Layout.BUTTON_PADDING_X)
        if width > buttonWidth then
            buttonWidth = width
        end
    end
    for index = 1, #Layout.MAIN_PANEL_ORDER do
        local id = Layout.MAIN_PANEL_ORDER[index]
        blocks[#blocks + 1] = {
            id = id,
            kind = "button",
            align = "center",
            width = buttonWidth,
            height = id == "place" and 24 or nil,
            text = labels[id],
            -- The utility button is set apart from the flow buttons.
            gapBefore = id == "lock" and Layout.MAIN_PANEL_UTILITY_GAP or nil,
        }
    end
    return Layout.build({ minWidth = Layout.MAIN_PANEL_WIDTH, blocks = blocks })
end

--- Intermission panel (combat surface): title, SIMULATION banner, state,
--- headline, ping banner, body, composition buttons, action row.
--- @param spec table|nil {
---   bannerLines = array|nil (SIMULATION banner: only during a rehearsal),
---   stateText = string|nil, headline = string|nil, pingBanner = string|nil,
---   bodyLines = array|nil, showChoices = boolean|nil, showRedo = boolean|nil,
---   showOk = boolean|nil }
function Layout.intermissionPanel(spec)
    local opts = type(spec) == "table" and spec or {}
    local blocks = {}

    blocks[#blocks + 1] = { id = "title", kind = "text", align = "center", style = "normal", text = Locale.t("ui.panelTitle") }
    if type(opts.bannerLines) == "table" and #opts.bannerLines > 0 then
        blocks[#blocks + 1] = {
            id = "simBanner",
            kind = "text",
            align = "center",
            style = "large",
            text = table.concat(opts.bannerLines, "\n"),
        }
    end
    if type(opts.stateText) == "string" and opts.stateText ~= "" then
        blocks[#blocks + 1] = { id = "state", kind = "text", align = "center", style = "huge", text = opts.stateText }
    end
    if type(opts.headline) == "string" and opts.headline ~= "" then
        blocks[#blocks + 1] = { id = "headline", kind = "text", align = "center", style = "large", text = opts.headline }
    end
    if type(opts.pingBanner) == "string" and opts.pingBanner ~= "" then
        blocks[#blocks + 1] = { id = "pingBanner", kind = "text", align = "left", style = "large", text = opts.pingBanner }
    end
    local bodyLines = opts.bodyLines or {}
    if #bodyLines > 0 then
        blocks[#blocks + 1] = { id = "body", kind = "text", align = "left", style = "normal", text = table.concat(bodyLines, "\n") }
    end
    if opts.showChoices then
        local items = {}
        for index = 1, #Intermission.STATES do
            local key = Intermission.STATES[index]
            local rec = Intermission.getDeclaration(key)
            items[#items + 1] = {
                id = "choice" .. index,
                text = rec ~= nil and rec.buttonLabel or key,
                width = Layout.CHOICE_WIDTH,
                height = Layout.CHOICE_HEIGHT,
            }
        end
        blocks[#blocks + 1] = { id = "choices", kind = "row", gap = Layout.CHOICE_GAP, items = items }
    end
    -- Action row: CORRECT on the left, then (right to left) Close, OK.
    local actions = {}
    if opts.showRedo then
        actions[#actions + 1] = { id = "redo", align = "left", text = Locale.t("ui.redo"), width = 130, height = 22 }
    end
    actions[#actions + 1] = { id = "close", align = "right", text = Locale.t("ui.close"), width = 90, height = 22 }
    if opts.showOk then
        actions[#actions + 1] = { id = "ok", align = "right", text = Locale.t("ui.ok"), width = 90, height = 22 }
    end
    blocks[#blocks + 1] = { id = "actions", kind = "row", gap = Layout.CHOICE_GAP, items = actions }

    return Layout.build({ minWidth = Layout.INTERMISSION_WIDTH, blocks = blocks })
end

--- Ping help window (a SHORT information frame: how to bind the ping keys and
--- the operational reminder "you ping yourself when the panel says PING: YES").
--- @param spec table|nil { lines = array, keyLines = array|nil }
function Layout.pingHelpPanel(spec)
    local opts = type(spec) == "table" and spec or {}
    local blocks = {
        { id = "title", kind = "text", align = "center", style = "normal", text = Locale.t("sim.ping.title") },
        { id = "headline", kind = "text", align = "center", style = "large", text = Locale.t("sim.ping.helpHeadline") },
        { id = "body", kind = "text", align = "left", style = "normal", text = table.concat(opts.lines or {}, "\n") },
    }
    if type(opts.keyLines) == "table" and #opts.keyLines > 0 then
        blocks[#blocks + 1] = { id = "keys", kind = "text", align = "left", style = "small", text = table.concat(opts.keyLines, "\n") }
    end
    blocks[#blocks + 1] = { id = "close", kind = "button", align = "right", text = Locale.t("ui.close"), width = 90, height = 22 }
    return Layout.build({ minWidth = Layout.PING_HELP_WIDTH, blocks = blocks })
end

return Layout
