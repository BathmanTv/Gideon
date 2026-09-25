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

    ANCHORS (fifth in-game test). Every block AND every button of a row carries
    its own anchor point ("point"), i.e. the first argument of Frame:SetPoint:
    the client refuses a nil point, and an error inside the applier used to
    abort the WHOLE refresh, so every block placed after the faulty one (the
    three composition buttons, the OK button...) silently disappeared. Hence:
      - packRow() gives every row item point = "TOPLEFT" (its x is measured from
        the left edge of the frame, its top from the top edge);
      - Layout.violations() reports a block or a row item WITHOUT an anchor, and
        tests/support/wowapi_stub.lua now refuses a non-string point like the
        client does, so this can never come back unnoticed.

    BUTTON SIZING (same in-game test: "the text comes out of the button").
    A button is never given a fixed size any more: its width comes from the
    WIDEST line of its label (explicit newlines included) plus a wide inner
    margin, its height from the NUMBER OF LINES plus a vertical margin, and both
    are floored by a minimum size. Layout.buttonSize() is the single source of
    that computation, used by every panel spec here and asserted, for both
    languages, by tests/spec/layout_spec.lua.

    The text metrics below are ESTIMATES (the game font cannot be measured out
    of game): they are deliberately CONSERVATIVE (wider and taller than the real
    glyphs) so a real in-game line is never longer nor taller than the estimated
    one. Every block is measured, wrapped and stacked here, which makes the
    whole layout TESTABLE: tests/spec/layout_spec.lua asserts, for BOTH
    languages, that no two blocks overlap, that no text runs over the borders,
    that no label touches the border of its button and that nothing is drawn
    under the close cross.

    THE WORD AFTER A CLICK (raid-lead request: "5 notches bigger"). The word is
    drawn by a FontString the ADDON creates, with an EXPLICIT font file and an
    EXPLICIT size (UI applies Layout.WORD_FONT_FILE / Layout.WORD_SIZE*): no
    Blizzard font object is used, because its size cannot be read out of game -
    an inherited font object is exactly how "the biggest font of the window"
    silently stopped being the biggest one. The sizes live here, ONCE, and the
    frame is widened when the word needs it (see intermissionPanel), so
    "Chasseur" and "BOSS" are never truncated nor pushed out of the frame in
    French as in English.

    THE PLACEMENT PANEL (/gr inter place): the panel displays ONE picture - the
    illustration the raid lead delivered (Layout.placementPanel, Core/Textures.
    placement*) - and NOTHING ELSE. No button, no label, no composition: the
    picture is the visual reference of the window the player is about to place
    (its size and its spot). It stays draggable, the close cross cancels and
    `/gr inter ok` validates the position.

    WHAT A PANEL MAY WRITE (the "no leftover title" rule). Each panel built here
    carries its `panel` id, and Layout.violations() REFUSES any text block whose
    id is not in the allow-list of that panel (Layout.INTERMISSION_TEXT_IDS, which
    is the SIMULATION banner plus the one word; Layout.PLACEMENT_TEXT_IDS, which is
    EMPTY). A future release can therefore not bring
    a title back: every layout test in the suite asks for the violations of the
    panel it just built.

    THE STYLE OF A CARD IS A PARAMETER (Layout.BUTTON_STYLES). The image
    "buttons" are simple CARDS: a thin border and a discreet dark background
    behind the picture, no Blizzard button chrome, no text. ONE style is defined
    today - the raid lead is still choosing - and a richer picker only has to
    add an entry to Layout.BUTTON_STYLES and name it in Layout.CHOICE_STYLE.
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

--- Core/Textures.lua is loaded BEFORE this file by the .toc: the image buttons
--- display the raid lead's screenshots, and their SIZE is DATA (Core/ cannot open
--- a file): the fitted size of each TGA lives there, this module only fits it in
--- the box of the panel. Two modules can therefore never disagree on the size of
--- an orb button.
local Textures = assert(ns.Textures, "Core/Textures.lua must be loaded before Core/Layout.lua")

---@class Layout
local Layout = {}
ns.Layout = Layout

--[[ ---------------------------------------------------------------- metrics

     height     = one display line, in pixels (GameFontNormalHuge ... Small);
     charWidth  = average width of one character, in pixels. Deliberately
                  WIDE: a real line is never wider than the estimate, so a
                  layout validated out of game never overflows in game.
]]

--[[ THE WORD WRITTEN AFTER A CLICK: EXPLICIT font file and EXPLICIT sizes.

     WHY NOT A BLIZZARD FONT OBJECT: GameFontNormalLarge / GameFontNormalHuge
     are font OBJECTS whose real size lives inside the client - an addon cannot
     read it out of game, so "the biggest element of the window" was a promise
     nobody could verify (and the raid lead asked for a word FIVE notches
     bigger). The addon therefore creates its own FontString and calls
     SetFont(file, size, ""): the file and the size come from HERE, once, and
     both the measurement below and the rendering layer read the same numbers.
]]
Layout.WORD_FONT_FILE = "Fonts\\FRIZQT__.TTF"
--- The two survival words ("Ping" / "Chasseur"), in pixels.
Layout.WORD_SIZE = 44
--- The middle composition ("BOSS"): the BIGGEST element of the window.
Layout.WORD_SIZE_BIG = 64
--- Conservative estimate of one capital's width, as a fraction of the font
--- size (measured on FRIZQT__: a capital is never wider than 0.8 em). Used to
--- size the frame around the word so "Chasseur" is never truncated.
Layout.WORD_CHAR_RATIO = 0.8

Layout.FONTS = {
    huge = { height = 34, charWidth = 20 },
    large = { height = 18, charWidth = 9 },
    normal = { height = 15, charWidth = 7 },
    small = { height = 13, charWidth = 6 },
    -- Buttons of UIPanelButtonTemplate draw their label with GameFontNormal, so
    -- their estimate is the WIDEST one on purpose: the fifth in-game test
    -- showed labels running over the button borders with the former 6.2 px/char
    -- (the real client font is wider than that). Same reasoning for the height:
    -- a whole line, never less.
    button = { height = 16, charWidth = 7.5 },
    -- THE TWO WORD STYLES: their height IS the size handed to SetFont (one
    -- single source, asserted by tests/spec/layout_spec.lua), and their width
    -- estimate scales with it.
    word = { height = Layout.WORD_SIZE, charWidth = math.ceil(Layout.WORD_SIZE * Layout.WORD_CHAR_RATIO) },
    wordBig = { height = Layout.WORD_SIZE_BIG, charWidth = math.ceil(Layout.WORD_SIZE_BIG * Layout.WORD_CHAR_RATIO) },
}
Layout.FONT_FALLBACK = "normal"

--- Inner margin of every panel (the dialog border is 32 px wide: keep clear).
Layout.MARGIN_X = 16
Layout.MARGIN_TOP = 12
Layout.MARGIN_BOTTOM = 12
--- Space between two stacked blocks: never zero, so two blocks can never touch.
Layout.GAP = 6
--- Inner margin of a button label. BOTH sides together (so a label always keeps
--- Layout.BUTTON_PADDING_X / 2 px of real margin on each side): the fifth
--- in-game test reported labels touching the border of their button.
Layout.BUTTON_PADDING_X = 14
--- Vertical inner margin of a button label (both sides together).
Layout.BUTTON_PADDING_Y = 6
--- A button is never smaller than this, whatever its label (still clickable).
Layout.BUTTON_MIN_WIDTH = 80
Layout.BUTTON_MIN_HEIGHT = 24
--- The close cross ("X") of UI.AttachCloseCross occupies this small box in the
--- top-right corner of every panel: no block may be drawn under it.
Layout.CROSS_SIZE = 22
Layout.CROSS_OFFSET = 8

--- Side of a COLOUR CHIP of the style showcase, in pixels (a square of the
--- palette, with its role and its hex code written next to it).
Layout.SWATCH_SIZE = 22
--- Client file a colour chip is filled with (a flat white square that the game
--- tints): the rendering layer reads it here, so Core/ stays the only place that
--- names a client file for the showcase.
Layout.SWATCH_BG_FILE = "Interface\\Buttons\\WHITE8X8"
--- Gap between a chip and the text that describes it, in pixels.
Layout.SWATCH_GAP = 8
--- Width reserved for the descriptive text of a chip: the widest role + hex line
--- must fit on ONE line, so the text column is fixed and the chips line up.
Layout.SWATCH_TEXT_WIDTH = 300

--[[ -------------------------------------------------------------- animations

     THE STYLE SHOWCASE IS THE ONLY SURFACE THAT ANIMATES, and these two pure
     functions are the whole of it: a FADE-IN of the panel when it opens and a
     DISCREET PULSE of the border of one example card. They live in Core so the
     tests can assert the bounds without a client, and UI/ only feeds them a
     number of seconds:

       - Layout.fadeAlpha(elapsed)  : 0 -> 1 over FADE_SECONDS, then 1 forever;
       - Layout.pulseAlpha(elapsed) : oscillates between PULSE_MIN and PULSE_MAX.

     Both are BOUNDED by construction (no alpha is ever handed to SetAlpha
     outside 0..1, which the client would refuse), both are monotone in their
     inputs, and NOTHING in the combat path ever calls them: a fight has no
     animation at all, and tests/spec/showcase_spec.lua proves it.
]]
Layout.ANIMATION = {
    FADE_SECONDS = 0.4,
    PULSE_SECONDS = 1.8,
    PULSE_MIN = 0.55,
    PULSE_MAX = 1.0,
}

--- Alpha of the fade-in at `elapsed` seconds since the showcase opened: 0 at the
--- very first frame, exactly 1 once FADE_SECONDS are past. BOUNDED (0..1) and
--- monotone: UI/ hands it straight to Frame:SetAlpha.
--- @param elapsed number|nil seconds since the showcase was shown
--- @return number 0..1
function Layout.fadeAlpha(elapsed)
    local seconds = tonumber(elapsed) or 0
    if seconds <= 0 then
        return 0
    end
    local duration = Layout.ANIMATION.FADE_SECONDS
    if seconds >= duration then
        return 1
    end
    return seconds / duration
end

--- Alpha of the pulsing border at `elapsed` seconds: a cosine between PULSE_MIN
--- and PULSE_MAX, period PULSE_SECONDS, starting at PULSE_MAX (so the first frame
--- is the FULL border, never a dimmed one). BOUNDED by construction.
--- @param elapsed number|nil seconds since the showcase was shown
--- @return number PULSE_MIN..PULSE_MAX
function Layout.pulseAlpha(elapsed)
    local seconds = tonumber(elapsed) or 0
    local span = Layout.ANIMATION.PULSE_MAX - Layout.ANIMATION.PULSE_MIN
    local period = Layout.ANIMATION.PULSE_SECONDS
    if period <= 0 then
        return Layout.ANIMATION.PULSE_MAX
    end
    local wave = 0.5 + (0.5 * math.cos((2 * math.pi * seconds) / period))
    return Layout.ANIMATION.PULSE_MIN + (span * wave)
end

--- Are the showcase animations ON? `raw` comes from the saved variables (a
--- boolean by contract): ONLY an explicit `false` turns them off, so an older
--- profile - or a hand-edited file - keeps the reasonable default (they are ON,
--- the showcase is exactly where the raid lead wants to SEE the animations).
--- @param raw any
--- @return boolean
function Layout.animationsEnabled(raw)
    return raw ~= false
end

--- The word used in game for a boolean setting ("enabled"/"disabled"), so no UI/
--- file ever writes it: the SAME two keys `/gr sound` already uses, which exist in
--- both languages of Core/Locale.lua.
--- @param value any
--- @return string
function Layout.settingWord(value)
    if value == false then
        return Locale.t("ui.wordDisabled")
    end
    return Locale.t("ui.wordEnabled")
end

--- Relative tolerance of the aspect ratio of an IMAGE button against the texture
--- it draws: 5 % is far below what the eye notices on an orb, and far above the
--- rounding of a fitted size (Layout.imageButtonSize rounds to the pixel).
Layout.ASPECT_TOLERANCE = 0.05

--- Frame widths of the three surfaces (they may only GROW: a wide label always
--- wins over the nominal width, see build()).
Layout.MAIN_PANEL_WIDTH = 360
Layout.INTERMISSION_WIDTH = 560
Layout.PING_HELP_WIDTH = 520

--- Composition buttons of the intermission panel. THE THREE BUTTONS DISPLAY AN
--- IMAGE (the raid lead's screenshot of the orbs): their size is the fitted size
--- of the TGA (Core/Textures.lua), so the aspect ratio of the screenshot is
--- preserved and nothing is ever stretched.
--- LONGEST SIDE of a displayed orb button, in pixels: the TGA is 256 px wide, so
--- the client downscales it (crisp) instead of upscaling it (blurry).
Layout.CHOICE_IMAGE_MAX = 160
Layout.CHOICE_GAP = 8

--[[ THE CARD: a thin border and a discreet dark background behind a picture.

     The raid lead asked for "just a frame with edges" around every image - no
     Blizzard button chrome, no decoration, no text - and a RICHER PICKER LATER.
     The style is therefore a PARAMETER: a name in Layout.CHOICE_STYLE selects a
     table in Layout.BUTTON_STYLES, the layout carries that name on every image
     block, and the rendering layer applies whatever table it is handed
     (UI.ApplyCardStyle). Adding a style later is adding one entry here and
     naming it - nothing else in the addon knows how a card looks.
       padding        : transparent space between the border and the picture (the
                        picture is ALWAYS drawn whole, inside the border);
       bgFile/edgeFile: the client files of the background and of the border;
       edgeSize       : border thickness, in pixels (thin by design);
       insets         : inner insets of the 9-slice, as the client expects them;
       background     : the discreet dark fill behind the picture;
       border         : the border colour at rest;
       borderHover    : the border colour under the mouse (the ONLY feedback);
       borderPressed  : the border colour between press and release;
       innerEdgeSize  : OPTIONAL second, INNER border (the "double frame" style #6):
                        the rendering layer draws it on a child frame;
       innerInset     : inset of that inner border, in pixels;
       innerBorder / innerBorderHover / innerBorderPressed : its three colours.
     A style is therefore PURE DATA: no code anywhere knows the name of a style,
     and adding one is adding an entry here plus its label in Core/Locale.lua.
]]

--- THE DELIVERED STYLE: what the intermission panel uses until the raid lead
--- picks another one (`/gr style <1..6|gideon|shipped>`). `shipped` resolves to
--- exactly this key: the current card with its thin grey border.
Layout.SHIPPED_STYLE = "card"

--[[ THE GIDEON PALETTE (delivered by the raid lead, values used AS-IS).

     One named constant per colour, here and nowhere else: the GIDEON card style
     and the style showcase both read them, so the palette can not drift. They
     are 24-bit RGB integers (0xRRGGBB); Layout.hexOf() prints them and
     Layout.colorOf() converts them to the floats the client expects. The
     showcase displays each one WITH its hex code, so the raid lead can dictate a
     change without any ambiguity.
]]
Layout.GIDEON_NIGHT = 0x04050f
Layout.GIDEON_PANEL = 0x0a0c22
Layout.GIDEON_ROYAL = 0x08218e
Layout.GIDEON_CYAN = 0x7adbfa
Layout.GIDEON_GOLD = 0xd19a45
Layout.GIDEON_GOLD_HI = 0xffe982
Layout.GIDEON_CHROME = 0xffffff
Layout.GIDEON_MUTED = 0xa9b4c7

--- The GIDEON constants in a DETERMINISTIC order (the showcase lists them this
--- way), each one with the role it plays.
Layout.GIDEON_PALETTE = {
    { key = "NIGHT", value = Layout.GIDEON_NIGHT },
    { key = "PANEL", value = Layout.GIDEON_PANEL },
    { key = "ROYAL", value = Layout.GIDEON_ROYAL },
    { key = "CYAN", value = Layout.GIDEON_CYAN },
    { key = "GOLD", value = Layout.GIDEON_GOLD },
    { key = "GOLD_HI", value = Layout.GIDEON_GOLD_HI },
    { key = "CHROME", value = Layout.GIDEON_CHROME },
    { key = "MUTED", value = Layout.GIDEON_MUTED },
}

--- "#RRGGBB" (upper case) of a 24-bit RGB integer: what the raid lead reads - and
--- dictates - in the style showcase.
--- @param value number|nil 0xRRGGBB
--- @return string
function Layout.hexOf(value)
    local number = tonumber(value) or 0
    local red = math.floor(number / 65536) % 256
    local green = math.floor(number / 256) % 256
    local blue = number % 256
    return string.format("#%02X%02X%02X", red, green, blue)
end

--- The three (or four) floats the client expects, from a 24-bit RGB integer.
--- @param value number|nil 0xRRGGBB
--- @param alpha number|nil 0..1 (1 by default)
--- @return table { r, g, b, a }
function Layout.colorOf(value, alpha)
    local number = tonumber(value) or 0
    return {
        r = (math.floor(number / 65536) % 256) / 255,
        g = (math.floor(number / 256) % 256) / 255,
        b = (number % 256) / 255,
        a = tonumber(alpha) or 1,
    }
end

--- "#RRGGBB" of a colour TABLE this module serves ({ r, g, b, a } floats): the
--- palette of the showcase is written in hex, and a colour expressed in floats
--- (the panel's own palette today, every style border) must be printable too.
--- @param color table|nil { r, g, b, a }
--- @return string
function Layout.hexOfColor(color)
    if type(color) ~= "table" then
        return Layout.hexOf(0)
    end
    local function channel(value)
        local number = math.floor((tonumber(value) or 0) * 255 + 0.5)
        if number < 0 then
            number = 0
        end
        if number > 255 then
            number = 255
        end
        return number
    end
    return string.format("#%02X%02X%02X", channel(color.r), channel(color.g), channel(color.b))
end

Layout.CHOICE_STYLE = Layout.SHIPPED_STYLE

--[[ THE STYLE TABLE. Six entries come from the validated board (1 "encart nu",
     2 "encart dore", 3 "bouton Blizzard", 4 "case d'action", 5 "image nue +
     ombre", 6 "double cadre"), `gideon` is the raid lead's own direction (night
     blue + gold, halo on hover) and `card` is the DELIVERED one: the default of
     the addon, whose data never moves when a candidate is added.
]]
Layout.BUTTON_STYLES = {
    ["1"] = {
        id = "1",
        labelKey = "style.1",
        aliases = { "1", "bare", "nu", "encartnu" },
        padding = 6,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
        background = { r = 0.078, g = 0.078, b = 0.078, a = 0.85 },
        border = { r = 0.604, g = 0.604, b = 0.604, a = 1 },
        borderHover = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
        borderPressed = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
    },
    ["2"] = {
        id = "2",
        labelKey = "style.2",
        aliases = { "2", "gold", "dore", "gilded" },
        padding = 6,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
        background = { r = 0.059, g = 0.047, b = 0.024, a = 0.9 },
        border = { r = 0.788, g = 0.635, b = 0.153, a = 1 },
        borderHover = { r = 1.0, g = 0.914, b = 0.510, a = 1 },
        borderPressed = { r = 1.0, g = 0.914, b = 0.510, a = 1 },
    },
    ["3"] = {
        id = "3",
        labelKey = "style.3",
        aliases = { "3", "blizzard", "bouton" },
        padding = 8,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\UI-Panel-Button-Up",
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
        background = { r = 0.16, g = 0.16, b = 0.16, a = 1 },
        border = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
        borderHover = { r = 0.80, g = 0.80, b = 0.80, a = 1 },
        borderPressed = { r = 0.35, g = 0.35, b = 0.35, a = 1 },
    },
    ["4"] = {
        id = "4",
        labelKey = "style.4",
        aliases = { "4", "action", "case", "slot" },
        padding = 2,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\UI-Quickslot2",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
        background = { r = 0.043, g = 0.043, b = 0.043, a = 1 },
        border = { r = 0.35, g = 0.35, b = 0.35, a = 1 },
        borderHover = { r = 0.80, g = 0.75, b = 0.40, a = 1 },
        borderPressed = { r = 1.0, g = 0.82, b = 0.0, a = 1 },
    },
    ["5"] = {
        id = "5",
        labelKey = "style.5",
        aliases = { "5", "shadow", "ombre", "nue" },
        padding = 3,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        background = { r = 0, g = 0, b = 0, a = 0 },
        border = { r = 0, g = 0, b = 0, a = 0.75 },
        borderHover = { r = 0.30, g = 0.90, b = 0.30, a = 0.9 },
        borderPressed = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
    },
    ["6"] = {
        id = "6",
        labelKey = "style.6",
        aliases = { "6", "double", "doublecadre" },
        padding = 8,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        background = { r = 0, g = 0, b = 0, a = 0.7 },
        border = { r = 0.545, g = 0.545, b = 0.545, a = 1 },
        borderHover = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
        borderPressed = { r = 1.0, g = 0.82, b = 0.0, a = 1 },
        -- THE SECOND, INNER BORDER (the "passe-partout" of the board).
        innerEdgeSize = 1,
        innerInset = 4,
        innerBorder = { r = 0.545, g = 0.545, b = 0.545, a = 1 },
        innerBorderHover = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
        innerBorderPressed = { r = 1.0, g = 0.82, b = 0.0, a = 1 },
    },
    -- THE RAID LEAD'S OWN DIRECTION: night-blue glass, gold filigree, CYAN halo.
    -- Border 2 px GOLD at rest (the halo comes from the generated 9-slice
    -- texture, Texture/gideon-frame.tga, which is WHITE so the game applies the
    -- colour), CYAN on hover, GOLD_HI on press.
    gideon = {
        id = "gideon",
        labelKey = "style.gideon",
        aliases = { "gideon", "nuit", "night" },
        padding = 10,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\AddOns\\GideonRaid\\Texture\\gideon-frame.tga",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
        -- THE COLOURS ARE THE CONSTANTS THEMSELVES (Layout.colorOf of the GIDEON
        -- values above): the hex code the showcase writes next to a chip and the
        -- colour the client actually paints can never drift apart.
        background = Layout.colorOf(Layout.GIDEON_PANEL, 0.94),
        border = Layout.colorOf(Layout.GIDEON_GOLD),
        borderHover = Layout.colorOf(Layout.GIDEON_CYAN),
        borderPressed = Layout.colorOf(Layout.GIDEON_GOLD_HI),
    },
    -- THE DELIVERED STYLE (the default of the addon): a thin border and a
    -- discreet dark background. Its data does not move when a candidate is added,
    -- so the combat panel is IDENTICAL by default.
    card = {
        id = "card",
        labelKey = "style.card",
        aliases = { "card", "shipped", "livre", "default" },
        padding = 6,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
        background = { r = 0.05, g = 0.05, b = 0.07, a = 0.6 },
        border = { r = 0.45, g = 0.45, b = 0.45, a = 1 },
        borderHover = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
        borderPressed = { r = 1.0, g = 1.0, b = 1.0, a = 1 },
    },
}

--- THE CANDIDATE STYLES, in the ORDER the style showcase displays them: the six
--- of the validated board, then the GIDEON direction. The delivered style is NOT
--- part of this list (it is the default, and `/gr style shipped` brings it back).
Layout.STYLE_ORDER = { "1", "2", "3", "4", "5", "6", "gideon" }

--- The style table of a name, never nil: an unknown or missing name falls back to
--- the configured one, so a layout can always be applied (no nil handed to
--- SetBackdrop).
--- @param name string|nil
--- @return table style table
function Layout.style(name)
    local key = type(name) == "string" and name or Layout.CHOICE_STYLE
    local style = Layout.BUTTON_STYLES[key]
    if type(style) == "table" then
        return style
    end
    return Layout.BUTTON_STYLES[Layout.CHOICE_STYLE]
end

--- Canonical NAME of a style: its id or any of its aliases (case and spaces
--- insensitive), or nil when nothing matches. `shipped` (and `livre`, `default`,
--- `card`) resolve to the DELIVERED style, so the raid lead never has to know an
--- internal name. BOUNDED INPUT, UNKNOWN REFUSED: the caller refuses nil,
--- nothing is ever guessed.
--- @param raw string|number|nil
--- @return string|nil canonical style name (a key of Layout.BUTTON_STYLES)
function Layout.resolveStyle(raw)
    if type(raw) == "number" then
        raw = tostring(raw)
    end
    if type(raw) ~= "string" then
        return nil
    end
    local flat = raw:lower():gsub("%s+", "")
    if flat == "" then
        return nil
    end
    local names = { unpack(Layout.STYLE_ORDER) }
    names[#names + 1] = Layout.SHIPPED_STYLE
    for index = 1, #names do
        local name = names[index]
        local entry = Layout.BUTTON_STYLES[name]
        local aliases = entry.aliases or {}
        for alias = 1, #aliases do
            if aliases[alias] == flat then
                return name
            end
        end
    end
    return nil
end

--- Is `raw` a style the showcase can PREVIEW (`/gr sim style <1..6|gideon>`)? The
--- delivered style is accepted too: previewing "what we ship today" is a
--- legitimate comparison. An unknown value returns false.
--- @param raw string|nil
--- @return boolean
function Layout.isCandidateStyle(raw)
    local name = Layout.resolveStyle(raw)
    if name == nil then
        return false
    end
    if name == Layout.SHIPPED_STYLE then
        return true
    end
    for index = 1, #Layout.STYLE_ORDER do
        if Layout.STYLE_ORDER[index] == name then
            return true
        end
    end
    return false
end

--- The LABEL displayed for a style: its NUMBER for the six candidates ("1 -
--- encart nu"), its translated name for `gideon` and for the delivered style.
--- @param name string|nil
--- @return string
function Layout.styleLabel(name)
    local key = Layout.resolveStyle(name) or Layout.CHOICE_STYLE
    local entry = Layout.BUTTON_STYLES[key] or Layout.BUTTON_STYLES[Layout.CHOICE_STYLE]
    local label = Locale.t(entry.labelKey)
    if tonumber(entry.id) ~= nil then
        return entry.id .. " - " .. label
    end
    return label
end

--- The number of a candidate style, or nil (`gideon` and the delivered style are
--- NAMED, not numbered).
--- @param name string|nil
--- @return string|nil "1".."6"
function Layout.styleNumber(name)
    local key = Layout.resolveStyle(name)
    if key == nil or tonumber(key) == nil then
        return nil
    end
    return key
end

--- The hex codes of a style, as the showcase prints them next to its example: the
--- border at rest and the background.
--- @param name string|nil
--- @return string borderHex, string backgroundHex
function Layout.styleHexes(name)
    local entry = Layout.style(name)
    return Layout.hexOfColor(entry.border), Layout.hexOfColor(entry.background)
end

--- Padding a card of `name` keeps between its border and its picture, in pixels.
--- @param name string|nil
--- @return number
function Layout.cardPadding(name)
    local style = Layout.style(name)
    return tonumber(style.padding) or 0
end

--[[ THE PLACEMENT PANEL: the illustration, its small OK button, and nothing else.

     LONGEST SIDE of the displayed illustration, in pixels. Core/Textures.lua
     declares the file 384 px wide (its own box), so the client draws it 1:1.
]]
Layout.PLACEMENT_IMAGE_MAX = 384

--- Width floor of the OK button of the placement panel, in pixels: SMALLER than
--- Layout.BUTTON_MIN_WIDTH on purpose - the raid lead asked for a small, discreet
--- button UNDER the illustration, not a toolbar (the button is `OK`, its label is
--- two characters).
Layout.PLACEMENT_OK_MIN_WIDTH = 60

--- The illustration starts BELOW the close cross: it is wide (the frame is
--- essentially its size), so a card drawn at the usual top margin would run under
--- the "X" of the panel - which Layout.violations() refuses.
Layout.PLACEMENT_MARGIN_TOP = Layout.CROSS_OFFSET + Layout.CROSS_SIZE + Layout.GAP

--- THE FROZEN VERTICAL ORDER of the three image buttons, TOP TO BOTTOM (raid-lead
--- request): 3 green + 1 red first, then 2 green + 2 red, then 1 green + 3 red.
--- This list is the single source of the order: intermissionPanel() builds its
--- image blocks from it and tests/spec/layout_spec.lua locks it down, so a future
--- change can not silently reorder the buttons under the player's finger.
Layout.INTERMISSION_CHOICE_ORDER = { "3V1R", "2V2R", "1V3R" }

--- The frozen order covers EXACTLY the canonical states of Core/Intermission.lua:
--- a state with no image button would be UNDECLARABLE in game (the player sees
--- the composition above their head and has no button to click), so a build
--- where the two lists disagree must not even load. tests/spec/layout_spec.lua
--- asserts the same equality, with a readable failure.
assert(
    #Layout.INTERMISSION_CHOICE_ORDER == #Intermission.STATES,
    "Layout.INTERMISSION_CHOICE_ORDER must cover every canonical state of Core/Intermission.lua"
)

--- The state whose word is drawn with the BIGGEST font of the window: the MIDDLE
--- composition ("BOSS"), which the raid lead wants unmistakable.
Layout.INTERMISSION_BIG_WORD_STATE = "2V2R"

--- Font style of the word written after a click: the biggest one for the BOSS
--- state, the explicit 44 px one for the two others (see WORD_SIZE above). These
--- keys index Layout.FONTS, and their height IS the size handed to SetFont.
Layout.WORD_STYLE = "word"
Layout.WORD_STYLE_BIG = "wordBig"

--[[ WHAT A PANEL MAY WRITE, AND NOTHING ELSE.

     Every panel built below carries its own id; Layout.violations() then
     refuses, block by block, any TEXT whose id is not in the allow-list of that
     panel. This is the structural answer to the raid-lead report "there is still
     a title at the top of the intermission panel": the intermission panel may
     write the SIMULATION banner (a rehearsal only) and the ONE word, the
     placement panel may write NOTHING AT ALL, and any other text block is
     reported by the existing layout tests.
]]
Layout.PANEL = {
    MAIN = "main",
    INTERMISSION = "intermission",
    PLACEMENT = "placement",
    PING_HELP = "pingHelp",
    SHOWCASE = "showcase",
}
--- The ONLY text blocks the intermission panel may contain: the SIMULATION banner
--- (rehearsal only, it is what tells a rehearsal from a real fight) and the ONE
--- word written after a click.
Layout.INTERMISSION_TEXT_IDS = {
    simBanner = true,
    word = true,
    wordBig = true,
}
--- The placement panel writes NO prose: the illustration speaks for itself, and the
--- ONLY text it carries is the label of its OK button (the raid lead asked for it
--- back: a small discreet button UNDER the illustration).
Layout.PLACEMENT_TEXT_IDS = {
    placementOk = true,
}
--- The TWO blocks of the placement panel: the illustration, and its OK button.
--- Anything else (a composition row, a title) is refused by Layout.violations().
Layout.PLACEMENT_BLOCK_ID = "placement"
Layout.PLACEMENT_OK_BLOCK_ID = "placementOk"

--- The allow-list of text ids of a panel (nil when the panel has none: a
--- hand-made layout is never constrained). Layout.violations() applies it, so a
--- title can not silently come back on a panel that must not have one.
--- @param panel string|nil
--- @return table|nil allow-list (id -> true)
function Layout.panelTextIds(panel)
    if panel == Layout.PANEL.INTERMISSION then
        return Layout.INTERMISSION_TEXT_IDS
    end
    if panel == Layout.PANEL.PLACEMENT then
        return Layout.PLACEMENT_TEXT_IDS
    end
    if panel == Layout.PANEL.SHOWCASE then
        return Layout.SHOWCASE_TEXT_IDS
    end
    return nil
end

--- THE THEME: the ONLY color values of the addon live here. A color is never
--- written again in a UI/ file (that is how a green drifts into a different green
--- from one release to the next): the rendering layer asks for THEME.GREEN and
--- applies it as-is, and tests/spec/layout_spec.lua asserts the constant.
---   GREEN : the survival words ("Ping" / "Chasseur"), the green of the 3V1R
---           ping (|cff40ff40, i.e. 64/255 = 0.25, 255/255 = 1.0);
---   BOSS  : the big word (gold, readable on the dark dialog background);
---   ALERT : the RED ping, i.e. the colour of the "Ping" chat line announcing a
---           RELEASE (|cffff4040): shown in the style showcase next to the others
---           so the whole palette of the panel carries a hex code.
Layout.THEME = {
    GREEN = { r = 0.25, g = 1.0, b = 0.25 },
    BOSS = { r = 1.0, g = 0.82, b = 0.0 },
    -- The SIMULATION banner keeps the gold it always had, from the same table.
    SIMULATION = { r = 1.0, g = 0.82, b = 0.0 },
    ALERT = { r = 1.0, g = 0.251, b = 0.251 },
}

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

--[[ ------------------------------------------------------------ button sizing

     The single source of truth for the size of a BUTTON. The fifth in-game test
     reported labels running over their button ("augmente un peu le bouton, le
     texte sort") because the actions row and the composition buttons were given
     FIXED sizes (130 / 90 / 168 x 64) that the active language could exceed.
     From now on a button is measured exactly like a text block:
       - width  = widest EXPLICIT line of the label + 2 x BUTTON_PADDING_X
                  (a label may carry explicit newlines: every line is measured);
       - height = number of lines x font line height + 2 x BUTTON_PADDING_Y;
       - both floored by the caller's minimum size (and by the generic ones).
     A label therefore NEVER touches nor leaves the border of its button.
]]

--- One line of a button label, in pixels (same estimator as a text block).
local function linePixels(line, metrics)
    return #(type(line) == "string" and line or "") * metrics.charWidth
end

--- Size a button needs for `text`, in pixels.
--- @param text string|nil button label (explicit newlines allowed)
--- @param style string|nil font style key ("button" by default)
--- @param minWidth number|nil minimum width (Layout.BUTTON_MIN_WIDTH otherwise)
--- @param minHeight number|nil minimum height (Layout.BUTTON_MIN_HEIGHT otherwise)
--- @return number width, number height, number lines, number paddingX, number paddingY
function Layout.buttonNeeds(text, style, minWidth, minHeight)
    local metrics = font(type(style) == "string" and style or "button")
    local lines = Layout.splitLines(text)
    local paddingX = Layout.BUTTON_PADDING_X
    local paddingY = Layout.BUTTON_PADDING_Y
    local widest = 0
    for index = 1, #lines do
        local width = linePixels(lines[index], metrics)
        if width > widest then
            widest = width
        end
    end
    local width = widest + (2 * paddingX)
    local floor = tonumber(minWidth) or Layout.BUTTON_MIN_WIDTH
    if floor > width then
        width = floor
    end
    local height = (#lines * metrics.height) + (2 * paddingY)
    local heightFloor = tonumber(minHeight) or Layout.BUTTON_MIN_HEIGHT
    if heightFloor > height then
        height = heightFloor
    end
    return round(width), round(height), #lines, paddingX, paddingY
end

--- Width and height of a button, as used by the panel specs below.
--- @return number width, number height
function Layout.buttonSize(text, style, minWidth, minHeight)
    local width, height = Layout.buttonNeeds(text, style, minWidth, minHeight)
    return width, height
end

--[[ ------------------------------------------------------- image buttons

     An IMAGE button draws a texture instead of a label (the three orb
     screenshots of the intermission panel). Its size is NEVER guessed here: it is
     the declared size of the texture (Core/Textures.lua), fitted in
     Layout.CHOICE_IMAGE_MAX with the aspect ratio preserved. An unknown state
     yields 0, 0: the caller then draws nothing, and no nil is ever handed to
     Frame:SetSize.
]]

--- Size of the PICTURE of a state, fitted in Layout.CHOICE_IMAGE_MAX (the card
--- padding of the style is NOT included: this is what the client draws).
--- @param state string|nil canonical state ("3V1R" | "2V2R" | "1V3R")
--- @return number width, number height (0, 0 when the state is unknown)
function Layout.imageSize(state)
    return Textures.displaySize(state, Layout.CHOICE_IMAGE_MAX)
end

--- Size of the CARD that carries the picture of a state: the picture plus the
--- padding of the style on both sides (the picture is drawn WHOLE inside the
--- border, so the card is always a little bigger than the image it holds).
--- @param state string|nil
--- @param style string|nil style name (Layout.CHOICE_STYLE by default)
--- @return number width, number height (0, 0 when the state is unknown)
function Layout.imageButtonSize(state, style)
    local width, height = Layout.imageSize(state)
    if width <= 0 or height <= 0 then
        return 0, 0
    end
    local padding = Layout.cardPadding(style)
    return round(width + (2 * padding)), round(height + (2 * padding))
end

--- Font style of the word written after a click: the BIGGEST one for the middle
--- composition, the 44 px one for the others. An unknown state gets the standard
--- style (never a nil style the client would refuse).
--- @param state string|nil
--- @return string style key
function Layout.wordStyle(state)
    local key = Textures.resolveState(state)
    if key == Layout.INTERMISSION_BIG_WORD_STATE then
        return Layout.WORD_STYLE_BIG
    end
    return Layout.WORD_STYLE
end

--- Size, in pixels, of the word of a state: THE single source of the font size
--- (the rendering layer hands this to SetFont, and nothing else). One constant
--- per word, never a value read from the client.
--- @param state string|nil
--- @return number size in pixels
function Layout.wordFontSize(state)
    return font(Layout.wordStyle(state)).height
end

--- File and size the rendering layer hands to FontString:SetFont for the word of
--- a state. Both come from THIS file, once: no Blizzard font object (its real
--- size cannot be read out of game) and no literal in UI/.
--- @param state string|nil
--- @return string fontFile, number size
function Layout.wordFont(state)
    return Layout.WORD_FONT_FILE, Layout.wordFontSize(state)
end

--- Id of the element carrying the word: the two font sizes are two distinct
--- FontStrings in the rendering layer (a FontString is created with its font),
--- so Core names the one it wants and the applier maps it as-is.
--- @param state string|nil
--- @return string block id ("wordBig" | "word")
function Layout.wordBlockId(state)
    if Layout.wordStyle(state) == Layout.WORD_STYLE_BIG then
        return "wordBig"
    end
    return "word"
end

--- Color of the word of a state (THEME above): the two survival words are GREEN,
--- the middle composition is the gold BOSS.
--- @param state string|nil
--- @return table { r, g, b } (never nil: the fallback is the green)
function Layout.wordColor(state)
    if Layout.wordStyle(state) == Layout.WORD_STYLE_BIG then
        return Layout.THEME.BOSS
    end
    return Layout.THEME.GREEN
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
        return Layout.buttonSize(raw.text, raw.style, raw.minWidth, raw.minHeight)
    end
    if raw.kind == "image" then
        -- An image button can not be wrapped either: the frame is at least as
        -- wide as the card it draws (the picture plus its padding).
        if type(raw.width) == "number" then
            return raw.width
        end
        return Layout.imageButtonSize(raw.state, raw.style)
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
                total = total + Layout.buttonSize(item.text, item.style, item.minWidth, item.minHeight)
            end
        end
        return total + ((#items - 1) * (tonumber(raw.gap) or gap))
    end
    if raw.kind == "text" and raw.nowrap then
        -- A text that must NEVER be wrapped nor truncated (THE WORD written
        -- after a click: "Chasseur" and "BOSS" have to be readable whole). The
        -- frame grows until the widest estimated line fits, so the pure layout
        -- proves the word can not be cut in either language.
        return Layout.textWidth(raw.text, raw.style)
    end
    return nil
end

Layout.fixedWidth = fixedWidth

--- Packs the buttons of one row: "left" items from the left margin, "right"
--- items from the right margin (the FIRST right item is the rightmost one).
--- EVERY item gets point = "TOPLEFT" (its x is measured from the left edge of
--- the frame, and build() gives it its top): without that anchor the client
--- raises on Frame:SetPoint and the applier stops, which is exactly how the
--- composition buttons and the OK button disappeared in game (fifth test).
--- @param items table array of { id, text, align, width, height, style, minWidth, minHeight }
--- @param frameWidth number
--- @param marginX number
--- @param gap number
--- @return table array of items with x/width/height/top/point (top is filled later)
--[[ A CARD, MEASURED ONCE. The picture IS the content (no label at all - the raid
     lead's screenshots replaced the written composition), inside the border
     described by its style in Layout.BUTTON_STYLES. The measured block therefore
     carries:
       - imageWidth/imageHeight : the PICTURE, whose aspect ratio is the one of
         the texture on disk (asserted by violations());
       - padding                : the space the style keeps between the border and
         the picture;
       - width/height           : the CARD (picture + 2 x padding), i.e. exactly
         what Frame:SetSize receives;
       - style                  : the NAME of the style table to apply, so the
         rendering layer never decides how a card looks;
       - sourceWidth/sourceHeight : the declared size of the texture ON DISK, so
         the aspect check needs no file access.
     Shared by a STACKED card and by a card inside a ROW (the style showcase lays
     its examples out in rows): a card is the SAME size wherever it is drawn, and
     a whole row of cards is no wider than the frame.
]]
local function measureImage(raw)
    local styleName = type(raw.style) == "string" and raw.style or Layout.CHOICE_STYLE
    local padding = Layout.cardPadding(styleName)
    local state = Textures.resolveState(raw.state)
    local imageWidth, imageHeight
    if type(raw.imageWidth) == "number" and type(raw.imageHeight) == "number" then
        imageWidth, imageHeight = raw.imageWidth, raw.imageHeight
    else
        imageWidth, imageHeight = Layout.imageSize(state)
        if type(raw.imageWidth) == "number" then
            imageWidth = raw.imageWidth
        end
        if type(raw.imageHeight) == "number" then
            imageHeight = raw.imageHeight
        end
    end
    local sourceWidth, sourceHeight
    if type(raw.sourceWidth) == "number" and type(raw.sourceHeight) == "number" then
        sourceWidth, sourceHeight = raw.sourceWidth, raw.sourceHeight
    elseif state ~= nil then
        sourceWidth, sourceHeight = Textures.sizeFor(state)
    end
    local measured = {
        state = state,
        style = styleName,
        padding = padding,
        texture = type(raw.texture) == "string" and raw.texture or Textures.pathFor(state),
        sourceWidth = sourceWidth,
        sourceHeight = sourceHeight,
        -- THE CARD'S OWN STATE when the layout FORCES it ("normal / hover /
        -- pressed" side by side in the showcase): the rendering layer applies
        -- exactly this one and nothing else. nil means "live" (the mouse drives it).
        cardState = raw.cardState,
        -- WHAT A CLICK DOES, when the card is clickable ("declare" a composition,
        -- "previewStyle" a frame style): the wiring is DATA of the layout, never a
        -- rule the rendering layer guesses from an id prefix.
        action = raw.action,
        -- Both sizes are floored at 1 px so nothing can be handed as a size to
        -- Frame:SetSize.
        imageWidth = math.max(1, round(imageWidth)),
        imageHeight = math.max(1, round(imageHeight)),
    }
    measured.width = type(raw.width) == "number" and raw.width or (measured.imageWidth + (2 * padding))
    measured.height = type(raw.height) == "number" and raw.height or (measured.imageHeight + (2 * padding))
    return measured
end

--- The keys measureImage() produces, copied onto a stacked block verbatim.
local IMAGE_KEYS = {
    "state",
    "style",
    "padding",
    "texture",
    "sourceWidth",
    "sourceHeight",
    "cardState",
    "action",
    "imageWidth",
    "imageHeight",
    "width",
    "height",
}

--[[ LAYS OUT A ROW: several elements side by side, on ONE line.

     Three kinds of items are supported:
       - a BUTTON (the default): measured from its label, exactly as before;
       - a CARD (`kind = "image"`): measured by measureImage(), so a card of a row
         is the same size as the same card stacked on its own;
       - a COLOUR CHIP (`kind = "swatch"`) and a plain TEXT (`kind = "text"`),
         which the style showcase puts side by side (a chip of the palette next to
         its role and its hex code).

     `centered` (from `align = "center"` on the row) centers the whole row inside
     the frame instead of packing it from the left, and text/chip items are
     CENTERED VERTICALLY on the line (a 13 px label next to a 22 px chip must not
     sit at the bottom of it); buttons keep the historical bottom alignment.
]]
local function packRow(items, frameWidth, marginX, gap, centered)
    local packed = {}
    for index = 1, #items do
        local raw = items[index]
        local item
        if raw.kind == "image" then
            item = measureImage(raw)
            item.kind = "image"
        elseif raw.kind == "swatch" then
            item = {
                kind = "swatch",
                color = type(raw.color) == "table" and raw.color or { r = 0, g = 0, b = 0, a = 1 },
                width = math.max(1, round(tonumber(raw.width) or Layout.SWATCH_SIZE)),
                height = math.max(1, round(tonumber(raw.height) or Layout.SWATCH_SIZE)),
                centerY = true,
            }
        elseif raw.kind == "text" then
            local style = raw.style or Layout.FONT_FALLBACK
            item = {
                kind = "text",
                text = raw.text,
                style = style,
                width = math.max(1, round(tonumber(raw.width) or Layout.textWidth(raw.text, style))),
                height = math.max(1, round(tonumber(raw.height) or font(style).height)),
                nowrap = raw.nowrap == true or nil,
                color = raw.color,
                fontFile = raw.fontFile,
                fontSize = raw.fontSize,
                centerY = true,
            }
        else
            local style = raw.style or "button"
            local neededWidth, neededHeight, lines, paddingX, paddingY = Layout.buttonNeeds(raw.text, style, raw.minWidth, raw.minHeight)
            item = {
                kind = "button",
                align = raw.align == "right" and "right" or "left",
                text = raw.text,
                style = style,
                width = type(raw.width) == "number" and raw.width or neededWidth,
                height = type(raw.height) == "number" and raw.height or neededHeight,
                lines = lines,
                paddingX = paddingX,
                paddingY = paddingY,
            }
        end
        item.id = raw.id or ("item" .. index)
        item.point = "TOPLEFT"
        packed[#packed + 1] = item
    end

    local function totalWidth()
        local total = 0
        for index = 1, #packed do
            if index > 1 then
                total = total + gap
            end
            total = total + packed[index].width
        end
        return total
    end

    local leftCursor = marginX
    local rightCursor = frameWidth - marginX
    if centered then
        leftCursor = math.max(marginX, (frameWidth - totalWidth()) / 2)
        rightCursor = frameWidth - marginX
    end
    for index = 1, #packed do
        local item = packed[index]
        if item.align == "right" then
            item.x = rightCursor - item.width
            rightCursor = item.x - gap
        else
            item.x = leftCursor
            leftCursor = item.x + item.width + gap
        end
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
        -- OPTIONAL explicit font (file + size) of a text block: the rendering
        -- layer hands exactly these two values to FontString:SetFont. The ONE
        -- word written after a click uses it (Core decides the size, UI applies
        -- it): no Blizzard font object, whose size we could not verify.
        fontFile = raw.fontFile,
        fontSize = raw.fontSize,
        -- A text that must NEVER be wrapped nor truncated: the block carries the
        -- flag so the rendering layer (and the tests) can SEE that the word stays
        -- on ONE line - the frame is widened until it fits (fixedWidth above).
        nowrap = raw.nowrap == true or nil,
        -- OPTIONAL explicit colour of a text block ({ r, g, b, a }): the STYLE
        -- SHOWCASE writes the same word in several variants (the shipped green and
        -- the GIDEON cyan) side by side, so the colour has to travel WITH the
        -- block. A block without a colour is left to the rendering layer, exactly
        -- as before (the combat word keeps Layout.wordColor).
        color = raw.color,
    }
    if block.kind == "swatch" then
        -- A COLOUR CHIP of the style showcase: a plain square of the palette, with
        -- its role and its hex code written next to it (the raid lead dictates a
        -- change from a hex code). It carries no texture: the rendering layer fills
        -- a frame of this size, nothing else. Both sizes are floored at 1 px so
        -- nothing can be handed as a size to Frame:SetSize.
        block.color = type(raw.color) == "table" and raw.color or { r = 0, g = 0, b = 0, a = 1 }
        block.width = math.max(1, round(tonumber(raw.width) or Layout.SWATCH_SIZE))
        block.height = math.max(1, round(tonumber(raw.height) or Layout.SWATCH_SIZE))
        if block.align == "center" then
            block.point = "TOP"
            block.x = 0
        else
            block.point = "TOPLEFT"
            block.x = marginX
        end
        return block
    end
    if block.kind == "row" then
        block.width = frameWidth
        block.items = packRow(raw.items or {}, frameWidth, marginX, tonumber(raw.gap) or gap, raw.align == "center")
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
    if block.kind == "image" then
        -- A CARD: measured by measureImage() (ONE measurement rule for a stacked
        -- card and for a card inside a row), then anchored here.
        local measured = measureImage(raw)
        for index = 1, #IMAGE_KEYS do
            block[IMAGE_KEYS[index]] = measured[IMAGE_KEYS[index]]
        end
        if block.align == "center" then
            block.point = "TOP"
            block.x = 0
        else
            block.point = "TOPLEFT"
            block.x = marginX
        end
        return block
    end
    if block.kind == "button" then
        local style = raw.style or "button"
        local neededWidth, neededHeight, lines, paddingX, paddingY = Layout.buttonNeeds(block.text, style, raw.minWidth, raw.minHeight)
        block.style = style
        block.width = type(raw.width) == "number" and raw.width or neededWidth
        block.height = type(raw.height) == "number" and raw.height or neededHeight
        block.lines = lines
        block.paddingX = paddingX
        block.paddingY = paddingY
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
                -- A TEXT or a COLOUR CHIP is instead CENTERED VERTICALLY on the
                -- line (a 13 px label next to a 22 px chip must not sit at the
                -- bottom of it): the item carries `centerY` for that.
                local current = block.items[item]
                if current.centerY then
                    current.top = block.bottom + ((block.height + current.height) / 2)
                else
                    current.top = block.bottom + current.height
                end
                current.bottom = current.top - current.height
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
        -- The panel this layout belongs to (Layout.PANEL): violations() uses it
        -- to refuse any text block the panel is not allowed to write (the
        -- "no leftover title" rule). nil for a hand-made layout: the text rule
        -- is then simply not applied.
        panel = source.panel,
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

--- A block or a row button MUST carry the anchor point Frame:SetPoint expects
--- (a nil point raises in the client and used to abort the whole applier: the
--- fifth in-game test lost the composition buttons and the OK button that way).
--- @return boolean true when the element is anchored
local function isAnchored(block)
    return type(block.point) == "string" and block.point ~= ""
end

--- Every way a BUTTON label can fail to fit its button: too wide for the width,
--- too tall for the height (the two in-game reports of the fifth test). The
--- padding is the one the button was measured with, so "the label keeps a real
--- margin from the border" is asserted here, not only "it is not over".
--- Tolerant by design: an element handed in without a size (a hand-made layout)
--- is simply not checked on that axis, never an error.
--- @param scope string "button" or "row button"
--- @param target table button block or row item
--- @return table array of strings
local function labelProblems(scope, target)
    local out = {}
    local paddingX = tonumber(target.paddingX) or Layout.BUTTON_PADDING_X
    local paddingY = tonumber(target.paddingY) or Layout.BUTTON_PADDING_Y
    local style = target.style or "button"
    local lines = tonumber(target.lines) or #Layout.splitLines(target.text)
    local width = tonumber(target.width)
    if width ~= nil and Layout.textWidth(target.text, style) > (width - (2 * paddingX)) then
        out[#out + 1] = string.format("label of %s '%s' is wider than its button", scope, target.id)
    end
    local height = tonumber(target.height)
    if height ~= nil and (lines * font(style).height) > (height - (2 * paddingY)) then
        out[#out + 1] = string.format("label of %s '%s' is taller than its button", scope, target.id)
    end
    return out
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
--- Four rules, the four families of bugs reported in game:
---   - no block may be drawn without an anchor point (a nil point raised in the
---     client and the blocks placed after the faulty one never appeared: the
---     composition buttons and the OK button were simply missing on screen);
---   - no two blocks may share a Y band (the state must never be drawn on top of
---     the SIMULATION banner);
---   - no block may run over the borders of the frame, nor under the close
---     cross, no unbreakable word may be wider than its block, and no button
---     label may be wider or taller than the button it is drawn in;
---   - A PANEL ONLY WRITES WHAT IT IS ALLOWED TO (Layout.panelTextIds): any text
---     block out of the allow-list of the panel - a leftover title - is reported,
---     and the placement panel may contain nothing but its illustration.
--- @param layout table
--- @return table array of strings
function Layout.violations(layout)
    local problems = {}
    if type(layout) ~= "table" or type(layout.blocks) ~= "table" then
        problems[1] = "layout missing"
        return problems
    end
    local blocks = layout.blocks
    local panelTextIds = Layout.panelTextIds(layout.panel)
    local function report(message)
        problems[#problems + 1] = message
    end

    -- THE PLACEMENT PANEL: the illustration, and the small OK button UNDER it
    -- (brought back on the raid lead's explicit request: it saves the position and
    -- closes, exactly like `/gr inter ok`). NOTHING ELSE: no composition row, no
    -- title, no label. The illustration stays the only CONTENT.
    if layout.panel == Layout.PANEL.PLACEMENT then
        if #blocks < 1 or #blocks > 2 then
            report(string.format("the placement panel holds its illustration and its OK button at most (got %d blocks)", #blocks))
        end
        local seen = {}
        for index = 1, #blocks do
            local block = blocks[index]
            local known = block.id == Layout.PLACEMENT_BLOCK_ID or block.id == Layout.PLACEMENT_OK_BLOCK_ID
            if not known then
                report(string.format("unexpected block '%s' on the placement panel", block.id))
            elseif seen[block.id] then
                report(string.format("duplicated block '%s' on the placement panel", block.id))
            else
                seen[block.id] = true
                if block.id == Layout.PLACEMENT_BLOCK_ID and block.kind ~= "image" then
                    report(
                        string.format(
                            "the placement panel may only draw its illustration (block '%s' is a %s)",
                            block.id,
                            tostring(block.kind)
                        )
                    )
                end
                if block.id == Layout.PLACEMENT_OK_BLOCK_ID and block.kind ~= "button" then
                    report(
                        string.format(
                            "the OK button of the placement panel must be a button (block '%s' is a %s)",
                            block.id,
                            tostring(block.kind)
                        )
                    )
                end
            end
        end
    end

    for index = 1, #blocks do
        local block = blocks[index]
        if not isAnchored(block) then
            report(string.format("block '%s' has no anchor point", block.id))
        end
        -- A TITLE CAN NOT COME BACK: the panel only writes the text blocks its
        -- allow-list names. `layout.panel` is nil for a hand-made layout, which
        -- is then not constrained (the rule targets the real surfaces).
        if block.kind == "text" and panelTextIds ~= nil and panelTextIds[block.id] ~= true then
            report(
                string.format(
                    "text block '%s' is not allowed on the '%s' panel (a title must not come back)",
                    block.id,
                    tostring(layout.panel)
                )
            )
        end
        -- A COLOUR CHIP ONLY EXISTS IN THE STYLE SHOWCASE. No other surface may
        -- paint a square of the palette, and the showcase is the one place that
        -- has to (the raid lead reads the hex codes there): a chip somewhere else
        -- is a defect, not a decoration.
        if block.kind == "swatch" then
            if layout.panel ~= Layout.PANEL.SHOWCASE then
                report(string.format("colour chip '%s' is only allowed on the style showcase", block.id))
            end
            if type(block.color) ~= "table" then
                report(string.format("colour chip '%s' has no colour", block.id))
            end
            if tonumber(block.width) == nil or tonumber(block.height) == nil or block.width <= 0 or block.height <= 0 then
                report(string.format("colour chip '%s' has no usable size", block.id))
            end
        end
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
                local scope = "row button"
                if current.kind == "image" then
                    scope = "row card"
                elseif current.kind == "swatch" then
                    scope = "row chip"
                elseif current.kind == "text" then
                    scope = "row label"
                end
                if not isAnchored(current) then
                    report(string.format("%s '%s' has no anchor point", scope, current.id))
                end
                if current.x < 0 or (current.x + current.width) > layout.width then
                    report(string.format("%s '%s' runs over the side border", scope, current.id))
                end
                if current.kind == "text" then
                    -- A TEXT ITEM OF A ROW IS STILL A TEXT BLOCK: it obeys the
                    -- allow-list of its panel (no leftover title can hide inside a
                    -- row) and it must fit in the box it was given.
                    if panelTextIds ~= nil and panelTextIds[current.id] ~= true then
                        report(
                            string.format(
                                "%s '%s' is not allowed on the '%s' panel (a title must not come back)",
                                scope,
                                current.id,
                                tostring(layout.panel)
                            )
                        )
                    end
                    if Layout.textWidth(current.text, current.style) > current.width then
                        report(string.format("%s '%s' is wider than its box", scope, current.id))
                    end
                elseif current.kind == "image" then
                    if type(current.texture) ~= "string" or current.texture == "" then
                        report(string.format("%s '%s' has no texture", scope, current.id))
                    end
                    local declaredWidth, declaredHeight = tonumber(current.sourceWidth), tonumber(current.sourceHeight)
                    if declaredWidth ~= nil and declaredHeight ~= nil and declaredHeight > 0 and tonumber(current.imageHeight) ~= nil then
                        local drawn = current.imageWidth / current.imageHeight
                        local expected = declaredWidth / declaredHeight
                        if math.abs(drawn - expected) > Layout.ASPECT_TOLERANCE then
                            report(
                                string.format(
                                    "%s '%s' does not keep the aspect ratio of its texture (%.3f instead of %.3f)",
                                    scope,
                                    current.id,
                                    drawn,
                                    expected
                                )
                            )
                        end
                    end
                elseif current.kind == "button" then
                    local labelIssues = labelProblems(scope, current)
                    for issue = 1, #labelIssues do
                        report(labelIssues[issue])
                    end
                end
                if underCross(layout, current.x, current.x + current.width, current.top, current.bottom) then
                    report(string.format("%s '%s' runs under the close cross", scope, current.id))
                end
                for other = item + 1, #block.items do
                    local candidate = block.items[other]
                    if current.x < (candidate.x + candidate.width) and candidate.x < (current.x + current.width) then
                        report(string.format("row items '%s' and '%s' overlap", current.id, candidate.id))
                    end
                end
            end
        elseif block.kind == "button" then
            local labelIssues = labelProblems("button", block)
            for issue = 1, #labelIssues do
                report(labelIssues[issue])
            end
        elseif block.kind == "image" then
            -- A CARD with no picture is an invisible target: the player would
            -- click on an empty rectangle during an intermission. A picture
            -- whose aspect ratio no longer matches its texture is a STRETCHED
            -- orb, i.e. a composition that can be misread: both are defects.
            if type(block.texture) ~= "string" or block.texture == "" then
                report(string.format("image '%s' has no texture", block.id))
            end
            local imageWidth = tonumber(block.imageWidth)
            local imageHeight = tonumber(block.imageHeight)
            if imageWidth == nil or imageHeight == nil or imageWidth <= 0 or imageHeight <= 0 then
                report(string.format("image '%s' has no usable size", block.id))
            elseif block.width <= 0 or block.height <= 0 then
                report(string.format("card '%s' has no usable size", block.id))
            else
                -- The picture is drawn WHOLE: the card must be at least the
                -- picture plus the padding of its style, otherwise the border
                -- would eat a slice of the orb.
                local padding = tonumber(block.padding) or 0
                if block.width < (imageWidth + (2 * padding)) or block.height < (imageHeight + (2 * padding)) then
                    report(string.format("card '%s' is smaller than its picture plus its padding", block.id))
                end
                -- The PICTURE keeps the aspect ratio of the file on disk.
                local declaredWidth, declaredHeight = tonumber(block.sourceWidth), tonumber(block.sourceHeight)
                if declaredWidth ~= nil and declaredHeight ~= nil and declaredHeight > 0 then
                    local drawn = imageWidth / imageHeight
                    local expected = declaredWidth / declaredHeight
                    if math.abs(drawn - expected) > Layout.ASPECT_TOLERANCE then
                        report(
                            string.format(
                                "image '%s' does not keep the aspect ratio of its texture (%.3f instead of %.3f)",
                                block.id,
                                drawn,
                                expected
                            )
                        )
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
    -- ONE size for the four buttons: the three FLOW buttons then line up exactly
    -- (same left/right edges, regular spacing) whatever the language, and the
    -- widest label decides for all of them. The height comes from the label too
    -- (a button is never a fixed box any more): a label can not touch nor leave
    -- the border, in English as in French.
    local buttonWidth, buttonHeight = 0, 0
    for index = 1, #Layout.MAIN_PANEL_ORDER do
        local neededWidth, neededHeight = Layout.buttonSize(labels[Layout.MAIN_PANEL_ORDER[index]], "button", nil, nil)
        if neededWidth > buttonWidth then
            buttonWidth = neededWidth
        end
        if neededHeight > buttonHeight then
            buttonHeight = neededHeight
        end
    end
    for index = 1, #Layout.MAIN_PANEL_ORDER do
        local id = Layout.MAIN_PANEL_ORDER[index]
        blocks[#blocks + 1] = {
            id = id,
            kind = "button",
            align = "center",
            width = buttonWidth,
            height = buttonHeight,
            text = labels[id],
            -- The utility button is set apart from the flow buttons.
            gapBefore = id == "lock" and Layout.MAIN_PANEL_UTILITY_GAP or nil,
        }
    end
    return Layout.build({ panel = Layout.PANEL.MAIN, minWidth = Layout.MAIN_PANEL_WIDTH, blocks = blocks })
end

--- Intermission panel (the combat surface). The raid lead's request, applied
--- as-is: BEFORE a click the panel shows the three CARDS carrying the orb
--- screenshots, stacked VERTICALLY (frozen order) and NOTHING ELSE - no title,
--- no state line, no role line, no action line, no key reminder; the close cross
--- and the dragging are chrome, not blocks. AFTER a click the three cards give
--- way to the ONE word of the composition ("Ping" / "BOSS" / "Chasseur") plus
--- CORRECT.
--- The SIMULATION banner is the ONE text left, and only during a rehearsal (the
--- raid lead wants the panel unmistakably marked as a simulation).
--- The panel is WIDENED when the word needs it: `nowrap` makes the word an
--- unwrappable element for build(), so "Chasseur" (FR) and "BOSS" (the biggest
--- element of the window) are drawn whole, never truncated, in both languages.
--- @param spec table|nil {
---   bannerLines = array|nil (SIMULATION banner: only during a rehearsal),
---   showChoices = boolean|nil (the three image cards),
---   wordText = string|nil, wordState = string|nil (the one word + its state),
---   style = string|nil (the CARD STYLE of the three pictures: the raid lead's
---     choice, a key of Layout.BUTTON_STYLES; the delivered style by default),
---   showRedo = boolean|nil }
function Layout.intermissionPanel(spec)
    local opts = type(spec) == "table" and spec or {}
    local blocks = {}

    if type(opts.bannerLines) == "table" and #opts.bannerLines > 0 then
        blocks[#blocks + 1] = {
            id = "simBanner",
            kind = "text",
            align = "center",
            style = "large",
            text = table.concat(opts.bannerLines, "\n"),
        }
    end

    if opts.showChoices then
        -- THE THREE CARDS, STACKED VERTICALLY in the FROZEN order of
        -- Layout.INTERMISSION_CHOICE_ORDER (3V1R on top, then 2V2R, then 1V3R).
        -- Each one draws its OWN screenshot (the texture of its state, resolved
        -- by Core/Textures.lua) inside the bare border of Layout.CHOICE_STYLE
        -- and carries NO label: a written composition beside a picture of the
        -- same composition is exactly the noise the raid lead asked to remove.
        for index = 1, #Layout.INTERMISSION_CHOICE_ORDER do
            blocks[#blocks + 1] = {
                id = "choice" .. index,
                kind = "image",
                align = "center",
                state = Layout.INTERMISSION_CHOICE_ORDER[index],
                -- THE STYLE OF THE COMBAT CARDS: whatever the raid lead picked
                -- (`/gr style <1..6|gideon|shipped>`, persisted) or the delivered
                -- one by default. Core only NAMES it: the rendering layer applies
                -- the table, so the combat panel is byte-for-byte the same look
                -- until a style is chosen.
                style = opts.style or Layout.CHOICE_STYLE,
            }
        end
    end

    -- THE ONE WORD. Its size, its font FILE and its block id come from the STATE
    -- (the middle composition is the big one), never from the text itself: the
    -- rendering layer draws the word in the FontString Core names, with the
    -- font size Core declares - a Blizzard font object would hide that size.
    -- `nowrap` means: the frame grows until this word fits whole.
    if type(opts.wordText) == "string" and opts.wordText ~= "" then
        local fontFile, fontSize = Layout.wordFont(opts.wordState)
        blocks[#blocks + 1] = {
            id = Layout.wordBlockId(opts.wordState),
            kind = "text",
            align = "center",
            style = Layout.wordStyle(opts.wordState),
            text = opts.wordText,
            nowrap = true,
            fontFile = fontFile,
            fontSize = fontSize,
        }
    end

    -- Action row: CORRECT, and nothing else. THERE IS NO OK BUTTON ANY MORE: the
    -- raid lead asked the placement panel to show the illustration alone (no
    -- button at all), and the placement is validated by `/gr inter ok` - which
    -- saves the position exactly like the former button did. The close cross
    -- ("X", chrome, always present) closes/cancels the panel in every mode.
    local actions = {}
    if opts.showRedo then
        actions[#actions + 1] = { id = "redo", align = "left", text = Locale.t("ui.redo") }
    end
    if #actions > 0 then
        local actionWidth, actionHeight = Layout.BUTTON_MIN_WIDTH, Layout.BUTTON_MIN_HEIGHT
        for index = 1, #actions do
            local neededWidth, neededHeight = Layout.buttonSize(actions[index].text, "button", actionWidth, actionHeight)
            if neededWidth > actionWidth then
                actionWidth = neededWidth
            end
            if neededHeight > actionHeight then
                actionHeight = neededHeight
            end
        end
        for index = 1, #actions do
            actions[index].width = actionWidth
            actions[index].height = actionHeight
        end
        blocks[#blocks + 1] = { id = "actions", kind = "row", gap = Layout.CHOICE_GAP, items = actions }
    end

    return Layout.build({ panel = Layout.PANEL.INTERMISSION, minWidth = Layout.INTERMISSION_WIDTH, blocks = blocks })
end

--- PLACEMENT panel (`/gr inter place`, the PLACE button of the main panel): the
--- illustration the raid lead delivered, PLUS the small OK button UNDER it.
--- WHY the illustration: the placement step exists so the player SEES the size and
--- the spot the window will occupy during the fight. A button row and a written
--- procedure turned that screen into a form; the picture alone is the reference,
--- and the frame it is drawn in IS the frame the fight will show.
--- WHY the OK button (raid lead's explicit decision, "Remet oui ok"): it saves the
--- position and closes, exactly like the `/gr inter ok` command - which stays
--- available as a backup. It is SMALL (Layout.PLACEMENT_OK_MIN_WIDTH) and sits
--- UNDER the illustration; it carries no composition and no title.
--- The panel stays DRAGGABLE (position saved on drag stop) and the close cross
--- CANCELS the placement. Layout.violations() refuses any other block on this
--- panel, so a composition row or a title can never come back without a test
--- failing, and the OK button is NEVER part of the combat layout (the rendering
--- layer hides every element the current layout does not carry).
--- @return table the layout (the illustration, then its OK button)
--- @param styleName string|nil the card style of the illustration (the raid lead's
---   pick, a key of Layout.BUTTON_STYLES: the frame it is drawn in IS the frame the
---   fight will show, so the preview follows the real choice)
function Layout.placementPanel(styleName)
    local style = Layout.resolveStyle(styleName) or Layout.CHOICE_STYLE
    local imageWidth, imageHeight = Textures.placementDisplaySize(Layout.PLACEMENT_IMAGE_MAX)
    local padding = Layout.cardPadding(style)
    local okWidth, okHeight =
        Layout.buttonSize(Locale.t("ui.placementOk"), "button", Layout.PLACEMENT_OK_MIN_WIDTH, Layout.BUTTON_MIN_HEIGHT)
    return Layout.build({
        panel = Layout.PANEL.PLACEMENT,
        marginTop = Layout.PLACEMENT_MARGIN_TOP,
        blocks = {
            {
                id = Layout.PLACEMENT_BLOCK_ID,
                kind = "image",
                align = "center",
                style = style,
                texture = Textures.placementPath(),
                imageWidth = imageWidth,
                imageHeight = imageHeight,
                sourceWidth = Textures.PLACEMENT_SIZE[1],
                sourceHeight = Textures.PLACEMENT_SIZE[2],
                width = imageWidth + (2 * padding),
                height = imageHeight + (2 * padding),
            },
            {
                id = Layout.PLACEMENT_OK_BLOCK_ID,
                kind = "button",
                align = "center",
                text = Locale.t("ui.placementOk"),
                width = okWidth,
                height = okHeight,
            },
        },
    })
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
    local closeWidth, closeHeight = Layout.buttonSize(Locale.t("ui.close"), "button", nil, nil)
    blocks[#blocks + 1] = {
        id = "close",
        kind = "button",
        align = "right",
        text = Locale.t("ui.close"),
        width = closeWidth,
        height = closeHeight,
    }
    return Layout.build({ panel = Layout.PANEL.PING_HELP, minWidth = Layout.PING_HELP_WIDTH, blocks = blocks })
end

--=============================================================================
-- THE STYLE SHOWCASE (the in-game answer to "on voit rien pendant une
-- repetition": the raid lead judges the DESIGN in game, not on an out-of-game
-- board, and PICKS there).
--=============================================================================

--[[ WIDTH OF THE SHOWCASE PANEL, in pixels.

     Wider than the combat panel (Layout.INTERMISSION_WIDTH) ON PURPOSE: the
     showcase lays its examples out in ROWS, and a row has to hold three CARDS at
     the REAL size of the fight, so what the raid lead compares is what the player
     will see - not a shrunken thumbnail.
]]
Layout.SHOWCASE_WIDTH = 720
--- Cards per row in the showcase (3 x the widest card + 2 gaps still fit inside
--- Layout.SHOWCASE_WIDTH: the widest card is the GIDEON one, 180 px).
Layout.SHOWCASE_ROWS_OF = 3
--- Height, in pixels, of the SCROLLING WINDOW of the showcase. The content is
--- ~2400 px tall (seven style examples at the real size of a fight card, plus the
--- typography and the palette): it scrolls INSIDE this fixed window, so the frame
--- never covers the whole screen and the fixed banner strip stays visible.
Layout.SHOWCASE_WINDOW_HEIGHT = 560
--- The composition every frame style is demonstrated with: "2 green + 2 red", the
--- sample of the validated board.
Layout.SHOWCASE_SAMPLE_STATE = "2V2R"
--- THE THREE STATES a card can be drawn in when the LAYOUT forces one of them (the
--- showcase shows the three side by side). The rendering layer holds the SAME
--- table (UI.CARD_STATE IS this table), so the two can never drift apart, and
--- this list is the order of the "one card, three states" row of the showcase.
Layout.CARD_STATE = { REST = "rest", HOVER = "hover", PRESSED = "pressed" }
Layout.CARD_STATES = { Layout.CARD_STATE.REST, Layout.CARD_STATE.HOVER, Layout.CARD_STATE.PRESSED }
--- WHAT A CLICK ON A CARD OF THE SHOWCASE DOES, as DATA of the layout: the
--- rendering layer applies the action it is handed instead of guessing a rule out
--- of the block id, so a new clickable example is a Core change only.
Layout.SHOWCASE_ACTION = { DECLARE = "declare", PREVIEW_STYLE = "previewStyle" }

--- The colour a chip is painted with, with a guaranteed alpha (a colour of
--- Layout.THEME carries three channels and no alpha: the client's
--- SetBackdropColor wants four numbers, and nil is not one of them).
--- @param color table|nil { r, g, b, a }
--- @return table { r, g, b, a }
function Layout.opaque(color)
    if type(color) ~= "table" then
        return { r = 0, g = 0, b = 0, a = 1 }
    end
    return {
        r = tonumber(color.r) or 0,
        g = tonumber(color.g) or 0,
        b = tonumber(color.b) or 0,
        a = tonumber(color.a) or 1,
    }
end

--[[ THE PALETTE OF THE PANEL TODAY (section 4 of the showcase).

     ONE entry per ROLE the raid lead named - background, border, accent, main
     text, secondary text, alert - each one reading its colour from the single
     place that owns it (the shipped style for the card colours, Layout.THEME for
     the rest). Nothing is copied by hand: a colour changed in Layout.THEME moves
     in the showcase too, and tests/spec/showcase_spec.lua asserts that link.
]]
Layout.PALETTE = {
    {
        key = "background",
        roleKey = "palette.background",
        color = Layout.style(Layout.SHIPPED_STYLE).background,
    },
    {
        key = "border",
        roleKey = "palette.border",
        color = Layout.style(Layout.SHIPPED_STYLE).border,
    },
    {
        key = "accent",
        roleKey = "palette.accent",
        color = Layout.THEME.GREEN,
    },
    {
        key = "textMain",
        roleKey = "palette.textMain",
        color = Layout.THEME.BOSS,
    },
    {
        key = "textSecondary",
        roleKey = "palette.textSecondary",
        color = Layout.THEME.SIMULATION,
    },
    {
        key = "alert",
        roleKey = "palette.alert",
        color = Layout.THEME.ALERT,
    },
}

--[[ THE TWO VARIANT COLOURS OF A SURVIVAL WORD, so the raid lead can compare them
     side by side in game and CHOOSE (his earlier call was "green"; the CYAN one is
     the GIDEON palette, and the two lines are shown one above the other).
]]
Layout.TYPO_VARIANTS = {
    green = { labelKey = "showcase.typoGreen", color = Layout.THEME.GREEN },
    cyan = { labelKey = "showcase.typoCyan", color = Layout.colorOf(Layout.GIDEON_CYAN) },
    chrome = { labelKey = "showcase.typoChrome", color = Layout.colorOf(Layout.GIDEON_CHROME) },
}

--[[ SECTION 2: EVERY TYPE SIZE THE ADDON REALLY USES, one sample per line plus a
     discreet caption giving the size and WHERE THAT SIZE COMES FROM.

       - the two WORDS carry an explicit font file and an explicit size
         (Layout.WORD_SIZE / Layout.WORD_SIZE_BIG): what the caption prints IS
         what the rendering layer hands to SetFont, nothing is estimated;
       - the other lines are drawn with Blizzard font OBJECTS (the SIMULATION
         banner, a button label, a note): their size lives inside the client and
         can not be read out of game, so the caption says so instead of pretending
         to know (Layout.FONTS holds the documented estimate the layout uses).
]]
Layout.TYPOGRAPHY = {
    { id = "typoBanner", localeKey = "sim.banner", style = "large" },
    { id = "typoLabel", localeKey = "ui.redo", style = "button" },
    -- The sample of the small text is "typoSingle", NOT "typoNote": the SECTION
    -- note of this part already carries the id "typoNote", and two blocks must
    -- never share an id (the rendering layer maps its elements by id).
    { id = "typoSingle", localeKey = "sim.singleLine", style = "small" },
    { id = "typoPingGreen", state = "1V3R", style = Layout.WORD_STYLE, variant = "green" },
    { id = "typoChaserGreen", state = "3V1R", style = Layout.WORD_STYLE, variant = "green" },
    { id = "typoPingCyan", state = "1V3R", style = Layout.WORD_STYLE, variant = "cyan" },
    { id = "typoChaserCyan", state = "3V1R", style = Layout.WORD_STYLE, variant = "cyan" },
    { id = "typoBoss", state = "2V2R", style = Layout.WORD_STYLE_BIG, variant = "chrome" },
}

--[[ WHAT THE SHOWCASE IS ALLOWED TO WRITE, AND NOTHING ELSE.

     Layout.PANEL.SHOWCASE is a panel like any other: Layout.violations() refuses
     any TEXT whose id is not listed here, so the showcase can not silently grow a
     paragraph, and the combat panel can not inherit one. The list is BUILT from
     the tables above, so adding a typography sample or a style candidate adds its
     ids here automatically - forgetting one raises a test failure, not a bug in
     game.
]]
Layout.SHOWCASE_TEXT_IDS = {
    showcaseBanner = true,
    showcaseTitle = true,
    showcaseHint = true,
    liveHeader = true,
    liveNote = true,
    -- the ONE word of the live composition (the same ids as the combat panel:
    -- the showcase repeats the combat word VERBATIM)
    word = true,
    wordBig = true,
    typoHeader = true,
    typoNote = true,
    statesHeader = true,
    statesNote = true,
    paletteHeader = true,
    paletteNote = true,
    gideonPaletteHeader = true,
    gideonPaletteNote = true,
    stylesHeader = true,
    stylesNote = true,
    stylesCurrent = true,
    stylesPreview = true,
    animHeader = true,
    animLine = true,
    animNote = true,
}
--- Registers one text id of the showcase in the allow-list (idempotent).
--- @param id string
local function showcaseText(id)
    Layout.SHOWCASE_TEXT_IDS[id] = true
end

for index = 1, #Layout.TYPOGRAPHY do
    showcaseText(Layout.TYPOGRAPHY[index].id)
    showcaseText(Layout.TYPOGRAPHY[index].id .. "Size")
end
for index = 1, #Layout.PALETTE do
    showcaseText("swatchLabel" .. index)
end
for index = 1, #Layout.GIDEON_PALETTE do
    showcaseText("gideonLabel" .. index)
end
for index = 1, #Layout.STYLE_ORDER do
    showcaseText("styleCap" .. index)
end
for index = 1, #Layout.INTERMISSION_CHOICE_ORDER do
    showcaseText("stateCap" .. index)
end

--[[ THE FIXED STRIP AT THE TOP OF THE SHOWCASE: the SIMULATION banner, the title
     and the "wheel = scroll" reminder.

     IT IS A LAYOUT OF ITS OWN, drawn OUTSIDE the scrolling area, because the
     banner MUST stay visible whatever the raid lead does in the showcase: the
     showcase can never be mistaken for a fight, no matter how far he scrolled.
     It obeys the same rules as the content (same panel id, same allow-list, same
     violation checks), so nothing is written on screen without Core deciding it.

     @return table the layout of the fixed strip
]]
function Layout.showcaseBannerPanel()
    return Layout.build({
        panel = Layout.PANEL.SHOWCASE,
        width = Layout.SHOWCASE_WIDTH,
        minWidth = Layout.SHOWCASE_WIDTH,
        blocks = {
            { id = "showcaseBanner", kind = "text", align = "center", style = "large", text = Locale.t("sim.banner") },
            { id = "showcaseTitle", kind = "text", align = "center", style = "normal", text = Locale.t("ui.showcaseTitle") },
            { id = "showcaseHint", kind = "text", align = "center", style = "small", text = Locale.t("showcase.hint") },
        },
    })
end

--[[ THE STYLE SHOWCASE (the scrollable content).

     SIX SECTIONS, in the order the raid lead reads them:
       1. the THREE COMPOSITIONS, clickable, exactly as in combat (after a click:
          the ONE word in the biggest font, plus the soundboard) - the rehearsal
          that already existed, kept as it was;
       2. the TYPOGRAPHY: every size the addon uses, in one column;
       3. ONE CARD IN THREE STATES: normal / hover / pressed, side by side, with
          the exact border colour of each state;
       4. the PALETTE: the colours of the panel today AND the GIDEON constants,
          each chip with its hex code in text (so the raid lead can dictate a
          value);
       5. the FRAME STYLES: the six candidates of the validated board plus GIDEON,
          each drawn at the REAL size, with its number and its border/background
          hexes; a click previews it live;
       6. the ANIMATIONS: fade-in + border pulse, their state, and how to stop
          them.

     `style` is the PREVIEW style (what the examples are drawn with), `realStyle`
     is the style the COMBAT panel uses right now: the two are shown, so nobody
     can confuse what he is looking at with what the fight will show. NOTHING here
     is part of the combat layout: /gr sim style is the only way in, and the
     fixed strip above (Layout.showcaseBannerPanel) never leaves the screen.

     @param spec table|nil {
       style = string|nil (preview style: 1..6, gideon, card),
       realStyle = string|nil (the style the combat panel uses),
       animations = any (the persisted preference: only `false` disables),
       showChoices = boolean|nil, wordText = string|nil, wordState = string|nil }
     @return table the layout of the showcase content
]]
function Layout.showcasePanel(spec)
    local opts = type(spec) == "table" and spec or {}
    local preview = Layout.resolveStyle(opts.style) or Layout.CHOICE_STYLE
    local real = Layout.resolveStyle(opts.realStyle) or Layout.CHOICE_STYLE
    local animationsOn = Layout.animationsEnabled(opts.animations)
    local blocks = {}

    local function push(block)
        blocks[#blocks + 1] = block
    end

    local function header(id, text)
        push({ id = id, kind = "text", align = "left", style = "large", text = text })
    end

    local function note(id, text)
        push({ id = id, kind = "text", align = "left", style = "small", text = text })
    end

    -- A ROW OF COLOUR CHIPS: the chip, then its role and its hex code in text.
    local function chipRow(chipId, labelId, color, label)
        push({
            id = chipId .. "Row",
            kind = "row",
            align = "center",
            gap = Layout.SWATCH_GAP,
            items = {
                { id = chipId, kind = "swatch", color = Layout.opaque(color) },
                { id = labelId, kind = "text", style = "small", width = Layout.SWATCH_TEXT_WIDTH, text = label },
            },
        })
    end

    -- 1. THE THREE COMPOSITIONS, in a row, at the size of the fight. After a
    --    click they give way to the ONE word, exactly like the combat panel.
    --    (The SIMULATION banner is NOT here: it lives in the fixed strip above,
    --    Layout.showcaseBannerPanel, so it never scrolls away.)
    header("liveHeader", Locale.t("showcase.liveHeader"))
    note("liveNote", Locale.t("showcase.liveNote"))
    local wordText = type(opts.wordText) == "string" and opts.wordText or ""
    if opts.showChoices ~= false and wordText == "" then
        local items = {}
        for index = 1, #Layout.INTERMISSION_CHOICE_ORDER do
            items[#items + 1] = {
                id = "liveChoice" .. index,
                kind = "image",
                state = Layout.INTERMISSION_CHOICE_ORDER[index],
                style = preview,
                -- A click DECLARES the composition: the giant word + the soundboard.
                action = Layout.SHOWCASE_ACTION.DECLARE,
            }
        end
        push({ id = "liveRow", kind = "row", align = "center", gap = Layout.CHOICE_GAP, items = items })
    else
        local fontFile, fontSize = Layout.wordFont(opts.wordState)
        push({
            id = Layout.wordBlockId(opts.wordState),
            kind = "text",
            align = "center",
            style = Layout.wordStyle(opts.wordState),
            text = wordText,
            nowrap = true,
            fontFile = fontFile,
            fontSize = fontSize,
            color = Layout.wordColor(opts.wordState),
        })
        push({
            id = "liveRedoRow",
            kind = "row",
            align = "center",
            gap = Layout.CHOICE_GAP,
            items = { { id = "liveRedo", text = Locale.t("ui.redo") } },
        })
    end

    -- 2. THE TYPOGRAPHY.
    header("typoHeader", Locale.t("showcase.typoHeader"))
    note("typoNote", Locale.t("showcase.typoNote"))
    for index = 1, #Layout.TYPOGRAPHY do
        local entry = Layout.TYPOGRAPHY[index]
        local variant = entry.variant ~= nil and Layout.TYPO_VARIANTS[entry.variant] or nil
        local block = { id = entry.id, kind = "text", align = "left", style = entry.style }
        local size, sourceKey, sizeName
        if variant ~= nil then
            -- A WORD: the explicit font of the addon, at the size Core declares.
            block.text = Locale.t("state.word." .. tostring(entry.state))
            block.color = variant.color
            block.fontFile, block.fontSize = Layout.wordFont(entry.state)
            block.nowrap = true
            block.align = "center"
            size = block.fontSize
            sourceKey = "showcase.typoExplicit"
            sizeName = Locale.t(variant.labelKey)
        else
            -- A Blizzard font OBJECT: its size is not readable out of game, and
            -- the caption says so.
            block.text = Locale.t(entry.localeKey)
            size = font(entry.style).height
            sourceKey = "showcase.typoObject"
            sizeName = entry.style
        end
        push(block)
        note(entry.id .. "Size", Locale.format("showcase.typoSize", sizeName, size, Locale.t(sourceKey)))
    end

    -- 3. ONE CARD, THREE STATES: the same card three times, in a row, so the
    --    feedback (the border, and the halo of the GIDEON style) can be compared
    --    without touching anything else.
    header("statesHeader", Locale.t("showcase.statesHeader"))
    note("statesNote", Locale.t("showcase.statesNote"))
    local styleTable = Layout.style(preview)
    local stateItems = {}
    for index = 1, #Layout.INTERMISSION_CHOICE_ORDER do
        stateItems[#stateItems + 1] = {
            id = "stateCard" .. index,
            kind = "image",
            state = Layout.INTERMISSION_CHOICE_ORDER[index],
            style = preview,
            -- THE STATE IS FORCED here, one card per state, side by side: the three
            -- are drawn at once so the feedback can be COMPARED (and none of them
            -- reacts to the mouse: the picture already shows the state).
            cardState = Layout.CARD_STATES[index],
        }
    end
    push({ id = "stateRow", kind = "row", align = "center", gap = Layout.CHOICE_GAP, items = stateItems })
    note("stateCap1", Locale.format("showcase.stateRest", Layout.hexOfColor(styleTable.border)))
    note("stateCap2", Locale.format("showcase.stateHover", Layout.hexOfColor(styleTable.borderHover)))
    note("stateCap3", Locale.format("showcase.statePressed", Layout.hexOfColor(styleTable.borderPressed)))

    -- 4. THE PALETTE, in two blocks: what the panel writes today, then the GIDEON
    --    constants - each chip followed by its role and its EXACT hex code.
    header("paletteHeader", Locale.t("showcase.paletteHeader"))
    note("paletteNote", Locale.t("showcase.paletteNote"))
    for index = 1, #Layout.PALETTE do
        local entry = Layout.PALETTE[index]
        chipRow(
            "swatch" .. index,
            "swatchLabel" .. index,
            entry.color,
            string.format("%s  %s", Layout.hexOfColor(entry.color), Locale.t(entry.roleKey))
        )
    end
    header("gideonPaletteHeader", Locale.t("showcase.paletteGideonHeader"))
    note("gideonPaletteNote", Locale.t("showcase.paletteGideonNote"))
    for index = 1, #Layout.GIDEON_PALETTE do
        local entry = Layout.GIDEON_PALETTE[index]
        chipRow(
            "gideon" .. index,
            "gideonLabel" .. index,
            Layout.colorOf(entry.value),
            string.format("%s  %s", Layout.hexOf(entry.value), Locale.t("palette.gideon." .. entry.key))
        )
    end

    -- 5. THE FRAME STYLES. Every candidate is drawn at the REAL size of a fight
    --    card, in rows of Layout.SHOWCASE_ROWS_OF, with its number and the hex
    --    codes of its border and of its background underneath.
    header("stylesHeader", Locale.t("showcase.stylesHeader"))
    note("stylesNote", Locale.t("showcase.stylesNote"))
    note("stylesCurrent", Locale.format("showcase.stylesCurrent", Layout.styleLabel(real), Layout.styleNumber(real) or real))
    note("stylesPreview", Locale.format("showcase.previewOnly", Layout.styleLabel(preview), Layout.styleNumber(preview) or preview))
    for start = 1, #Layout.STYLE_ORDER, Layout.SHOWCASE_ROWS_OF do
        local items = {}
        for offset = 0, Layout.SHOWCASE_ROWS_OF - 1 do
            local name = Layout.STYLE_ORDER[start + offset]
            if name ~= nil then
                items[#items + 1] = {
                    id = "styleCard" .. (start + offset),
                    kind = "image",
                    state = Layout.SHOWCASE_SAMPLE_STATE,
                    style = name,
                    -- A click PREVIEWS this style: the whole showcase (the live row,
                    -- the states row, every example) is redrawn with it, so the raid
                    -- lead judges the style on the real size of a fight card.
                    action = Layout.SHOWCASE_ACTION.PREVIEW_STYLE,
                }
            end
        end
        push({ id = "styleRow" .. start, kind = "row", align = "center", gap = Layout.CHOICE_GAP, items = items })
        for offset = 0, Layout.SHOWCASE_ROWS_OF - 1 do
            local index = start + offset
            local name = Layout.STYLE_ORDER[index]
            if name ~= nil then
                local borderHex, backgroundHex = Layout.styleHexes(name)
                note("styleCap" .. index, Locale.format("showcase.styleCaption", Layout.styleLabel(name), borderHex, backgroundHex))
            end
        end
    end

    -- 6. THE ANIMATIONS: what they are, whether they are on, how to stop them.
    header("animHeader", Locale.t("showcase.animHeader"))
    push({
        id = "animLine",
        kind = "text",
        align = "left",
        style = "normal",
        text = Locale.format("showcase.animLine", Layout.settingWord(animationsOn)),
    })
    note("animNote", Locale.t("showcase.animNote"))

    return Layout.build({
        panel = Layout.PANEL.SHOWCASE,
        width = Layout.SHOWCASE_WIDTH,
        minWidth = Layout.SHOWCASE_WIDTH,
        blocks = blocks,
    })
end

return Layout
