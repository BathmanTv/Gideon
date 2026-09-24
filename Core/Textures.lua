--[[--------------------------------------------------------------------------
    GideonRaid / Core / Textures.lua

    PURE LOGIC (Lua 5.1). No WoW API, no file access, no clock: this file runs
    as-is under busted and under lua5.1 outside the client.

    WHAT IT IS FOR: the three composition buttons of the intermission panel no
    longer carry a WRITTEN composition ("3 green + 1 red / 3V1R / number: 1 or
    3"): they display the raid lead's SCREENSHOT of the orbs. Reading a
    screenshot is instant, reading a sentence is not - and the sentence was
    ambiguous (1 and 3 are the same number above the head), which is exactly how
    a player sends themselves to their death.

      canonical state -> texture file (screenshot -> TGA, 256 px box):

        3V1R -> Texture/3v1r.tga      2V2R -> Texture/2v2r.tga
        1V3R -> Texture/1v3r.tga

      AND, outside the states, the PLACEMENT illustration:

        placement -> Texture/placement.tga   (384 px box, one sole picture)

    The placement window shows that illustration and NOTHING else (no button, no
    text): it is the visual reference of the size the panel will have during the
    fight. It has no canonical state, so it is declared on its own
    (Textures.PLACEMENT_*) instead of being forced into the state table.

    THE THREE RULES ARE HERE, out of game, because they are rules and not
    rendering:
      1. ONE FILE PER STATE: Textures.FILES_BY_STATE / Textures.pathFor. The
         paths are CLIENT paths ("Interface\AddOns\GideonRaid\Texture\..."), and
         the three files MUST be listed in GideonRaid.toc (the retail client does
         not load a texture that is not listed - exactly like a sound) - see
         tests/spec/texture_spec.lua.
      2. THE SIZE IS DATA, NOT A GUESS: Core/ cannot open a file, so the fitted
         size of each TGA is declared here (Textures.SIZES_BY_STATE) and the test
         reads the REAL header of the file on disk to compare (a texture that no
         longer matches its declaration - someone re-exported it - is a CI
         failure, never a stretched orb in a raid).
      3. NOTHING IS DRAWN WITHOUT A SIZE: an unknown state yields nil (the caller
         then draws nothing), never a nil width handed to Frame:SetSize.

    THE FILES ARE PRODUCED BY `tools/make_textures.py` (RGBA PNG screenshot ->
    32-bit uncompressed TGA, aspect ratio preserved, alpha preserved and bled so
    the client's filtering cannot draw a dark fringe): replacing them is a FILE
    DROP with the same names, nothing else changes.
----------------------------------------------------------------------------]]
--
--
local _, ns = ...

---@class Textures
local Textures = {}
ns.Textures = Textures

--- Model version. 1 = one TGA per canonical state, fitted in a 256 px box.
Textures.SCHEMA_VERSION = 1

--- Folder of the textures, as the CLIENT spells it (backslashes, addon folder
--- name of the .toc / of `package-as` in .pkgmeta). The tests compare this
--- prefix with the entries listed in GideonRaid.toc.
Textures.FOLDER = "Interface\\AddOns\\GideonRaid\\Texture\\"

--- The folder of the repository holding the files (only used by the tests).
Textures.DIRECTORY = "Texture"

--- The box every texture is fitted in, in pixels (tools/make_textures.py
--- declares the same value and prints the fitted sizes): the longest side of
--- each file is exactly this, the other one follows the source aspect ratio.
Textures.BOX = 256

--- The THREE canonical states, in the DETERMINISTIC order of the screenshots.
--- MIRROR of Intermission.STATES (that module is loaded AFTER this one, so the
--- list cannot be read from there): tests/spec/texture_spec.lua asserts that the
--- two lists are identical, so they can never drift apart.
Textures.STATES = { "1V3R", "2V2R", "3V1R" }

--- State -> file name, DETERMINISTIC table (no pairs()): the file names are
--- lower case, without accents, stable - that is the CONTRACT with the raid
--- lead who delivers the screenshots (same names, same folder).
Textures.FILES_BY_STATE = {
    ["1V3R"] = "1v3r.tga",
    ["2V2R"] = "2v2r.tga",
    ["3V1R"] = "3v1r.tga",
}

--- The same three file names as an ORDERED list (same order as Textures.STATES):
--- used by the tests that check the .toc entries and the files on disk.
Textures.FILE_NAMES = { "1v3r.tga", "2v2r.tga", "3v1r.tga" }

--[[ ------------------------------------------------- THE PLACEMENT ILLUSTRATION

     The panel shown while the player PLACES it (`/gr inter place`, the PLACE
     button of the main panel) displays ONE thing and nothing else: the Gideon
     illustration the raid lead delivered. No button, no text, no composition -
     the picture IS the window, and it is the VISUAL REFERENCE of the size the
     window will have during the fight (that is the whole point of the
     placement step: seeing where the panel lands BEFORE the pull).

     It is NOT a state: no composition maps to it, so it lives in its own
     declaration instead of being forced into FILES_BY_STATE (an image button is
     built from a canonical state, and a fake state would be a lie the state
     machine could read back). Same rules as the three orbs: a 32-bit
     uncompressed TGA, mapped here, listed in GideonRaid.toc, produced by
     tools/make_textures.py and verified on disk by tests/spec/texture_spec.lua.
]]

--- File name of the placement illustration (lower case, no accent, stable: the
--- CONTRACT with the raid lead who delivers the PNG).
Textures.PLACEMENT_FILE = "placement.tga"

--- The box the placement illustration is fitted in, in pixels. LARGER than the
--- orb box on purpose (Textures.BOX = 256): the orbs are read at a glance, the
--- illustration is the reference the player aims the window with.
Textures.PLACEMENT_BOX = 384

--- Size of Texture/placement.tga ON DISK, MEASURED at conversion time by
--- tools/make_textures.py (it prints this exact line). The longest side is
--- exactly PLACEMENT_BOX and the aspect ratio of the source PNG (1448x1086,
--- i.e. 4:3) is preserved: nothing is stretched, nothing is padded.
Textures.PLACEMENT_SIZE = { 384, 288 }

--- State -> size of the TGA ON DISK, MEASURED at conversion time by
--- tools/make_textures.py (it prints this exact block). Both values are <= BOX
--- and the LONGEST one is exactly BOX: the aspect ratio of the screenshot is
--- preserved, nothing is stretched, nothing is padded.
Textures.SIZES_BY_STATE = {
    ["1V3R"] = { 256, 241 },
    ["2V2R"] = { 256, 246 },
    ["3V1R"] = { 256, 238 },
}

--- Symbol written by the player (or a state from anywhere else) -> canonical
--- state, built in a LOOP from Textures.STATES (no duplicated literal).
local STATE_BY_SYMBOL = {}
for index = 1, #Textures.STATES do
    local state = Textures.STATES[index]
    STATE_BY_SYMBOL[state:lower()] = state
end
Textures.STATE_BY_SYMBOL = STATE_BY_SYMBOL

--- Normalizes a state written by the player or held by the state machine into a
--- canonical key. Tolerant on case and spaces ("1v3r", "1 V 3 R", "3V1R") and
--- TOTAL: an absent, empty, mistyped or non-string value returns nil (the caller
--- refuses it, nothing is guessed).
--- @param raw string|nil
--- @return string|nil "1V3R" | "2V2R" | "3V1R"
function Textures.resolveState(raw)
    if type(raw) ~= "string" then
        return nil
    end
    local flat = raw:lower():gsub("%s+", "")
    return STATE_BY_SYMBOL[flat]
end

--- File name (without folder) of a state, or nil when the state is unknown.
--- @param state string|nil
--- @return string|nil
function Textures.fileName(state)
    local key = Textures.resolveState(state)
    if key == nil then
        return nil
    end
    return Textures.FILES_BY_STATE[key]
end

--- CLIENT path of the texture of a state ("Interface\AddOns\GideonRaid\Texture\
--- 1v3r.tga"), or nil when the state is unknown. This is exactly what the
--- rendering layer hands to Button:SetNormalTexture, and exactly what
--- GideonRaid.toc lists.
--- @param state string|nil
--- @return string|nil client path
function Textures.pathFor(state)
    local file = Textures.fileName(state)
    if file == nil then
        return nil
    end
    return Textures.FOLDER .. file
end

--- Size of the texture ON DISK for a state, as a copy (never the shared table,
--- so a caller can not mutate the declaration): nil when the state is unknown.
--- @param state string|nil
--- @return number|nil width, number|nil height
function Textures.sizeFor(state)
    local key = Textures.resolveState(state)
    if key == nil then
        return nil, nil
    end
    local size = Textures.SIZES_BY_STATE[key]
    if type(size) ~= "table" then
        return nil, nil
    end
    return size[1], size[2]
end

--- Aspect ratio (width / height) of the texture of a state, or nil when the
--- state (or its declared size) is unknown. PURE: both numbers come from the
--- table above, never from a frame.
--- @param state string|nil
--- @return number|nil
function Textures.aspectOf(state)
    local width, height = Textures.sizeFor(state)
    if width == nil or height == nil or height <= 0 then
        return nil
    end
    return width / height
end

--- CLIENT path of the PLACEMENT illustration (same folder as the three orbs).
--- Exactly what the rendering layer hands to a Texture:SetTexture, and exactly
--- what GideonRaid.toc lists.
--- @return string client path
function Textures.placementPath()
    return Textures.FOLDER .. Textures.PLACEMENT_FILE
end

--- Size of Texture/placement.tga ON DISK, as a copy (never the shared table, so
--- a caller can not mutate the declaration).
--- @return number width, number height
function Textures.placementSize()
    return Textures.PLACEMENT_SIZE[1], Textures.PLACEMENT_SIZE[2]
end

--- Fits a declared size into a square box, ASPECT RATIO PRESERVED: the longest
--- side becomes `box`, the other one follows the ratio. Local helper shared by
--- an orb and by the placement illustration: ONE fitting rule for every texture
--- of the addon, so the two can never drift apart.
--- @return number width, number height
local function fitInBox(width, height, box)
    local maxSide = tonumber(box) or Textures.BOX
    if maxSide <= 0 or width == nil or height == nil or width <= 0 or height <= 0 then
        return 0, 0
    end
    local scale = maxSide / math.max(width, height)
    local fittedWidth = math.floor(width * scale + 0.5)
    local fittedHeight = math.floor(height * scale + 0.5)
    if fittedWidth < 1 then
        fittedWidth = 1
    end
    if fittedHeight < 1 then
        fittedHeight = 1
    end
    if fittedWidth > maxSide then
        fittedWidth = maxSide
    end
    if fittedHeight > maxSide then
        fittedHeight = maxSide
    end
    return fittedWidth, fittedHeight
end

--- Fits a declared size into a square box, ASPECT RATIO PRESERVED: the longest
--- side becomes `box`, the other one follows the ratio. TOTAL and bounded: a
--- missing size or a nonsense box returns zeroes instead of a nil the caller
--- would hand to Frame:SetSize.
--- @param state string|nil
--- @param box number|nil box in pixels (Textures.BOX by default)
--- @return number width, number height (0, 0 when nothing can be drawn)
function Textures.displaySize(state, box)
    local width, height = Textures.sizeFor(state)
    if width == nil or height == nil then
        return 0, 0
    end
    return fitInBox(width, height, box)
end

--- Display size of the PLACEMENT illustration, fitted in `box` (aspect ratio
--- preserved). Bounded like displaySize: 0, 0 when nothing can be drawn.
--- @param box number|nil box in pixels (Textures.PLACEMENT_BOX by default)
--- @return number width, number height
function Textures.placementDisplaySize(box)
    -- The two values are read into locals FIRST: `fitInBox(Textures.placementSize(),
    -- box)` would hand the box as the HEIGHT (a function call that is not the last
    -- argument yields a single value), and the illustration would be fitted in the
    -- default box instead of the requested one.
    local width, height = Textures.placementSize()
    return fitInBox(width, height, box or Textures.PLACEMENT_BOX)
end

return Textures
