--[[--------------------------------------------------------------------------
    GideonRaid / UI / Intermission.lua

    RENDERING LAYER ONLY ("Intermission Coach"). This file may call the WoW API
    (frames, fonts, C_Timer, GetBindingKey). It contains NO business computation:
    everything comes from ns.Intermission (snapshot / setupView / run machine),
    from ns.Simulation (rehearsal view, ping help view) and from ns.Layout (the
    DISPOSITION of the panel: frame size, every offset, every label).

    THE DISPOSITION IS PURE (Core/Layout.lua). History: the fourth in-game test
    showed the big state ("2V2R") drawn ON TOP of the SIMULATION banner, because
    every element was placed with a FIXED Y offset. Here, no element carries a
    literal offset any more: UI.IntermissionRefresh() builds a spec (the current
    texts), Core measures and STACKS the blocks, and UI.ApplyLayout applies the
    result as-is. Two blocks can therefore never share a Y, in English as in
    French (tests/spec/layout_spec.lua locks it down for both languages).

    12.x prohibitions (see docs/CONVENTIONS.md):
      - no read of aura / health / resource (possible SECRET value);
      - no combat log event;
      - no addon -> addon message in an instance.

    PING: THE PLAYER PINGS, WITH THE NATIVE BLIZZARD PING KEYBIND. Measured in
    game by the raid lead: an addon CANNOT ping at all - neither from a macro nor
    from a binding ("action usable only by the Blizzard UI"). This file therefore
    READS the key the player bound (GetBindingKey, under pcall) only to DISPLAY
    it, and never pings, never prepares a macro.

    FLOW OF A RAID EVENING (no argument of any combat event is ever read):
      a. before the pull, /gr -> "PLACE INTERMISSION PANEL": the frame is shown
         in placement mode, dragged where the player wants it and the position is
         saved in the SavedVariables;
      b. the player prepares the ping keybind and confirms with OK -> panel closed;
      c. ENCOUNTER_START arms the pre-computed schedule (it is only a starting
         gun): the panel opens BY ITSELF shortly before each intermission;
      d. the player clicks the composition they see (REDO corrects a mistake);
      e. at the end of the intermission the panel closes BY ITSELF;
      f. the next intermission follows the same cycle, automatically.
    THIS REAL FLOW IS UNCHANGED by the simulation mode below.

    CLOSE CROSS ("X", top right) on BOTH panels (the main one, UI/Panel.lua, and
    this one). During the placement it CANCELS the placement (same effect as the
    existing Close button); during a REHEARSAL it CLOSES the rehearsal (the
    player is the one who closes it); during the real flow it only HIDES the
    panel: the intermission clock keeps running, the panel still closes by itself
    at the end and opens again at the next intermission (nothing is disarmed).

    ASSIGNMENT SOUNDBOARDS (raid-lead request): the moment the player DECLARES
    their orb composition - a click on one of the three buttons, in the REAL flow
    as in a rehearsal - the soundboard OF THAT STATE is played ONCE, on the
    Master channel. Core/Sound.lua owns the pure table state -> file, the
    one-playback-per-assignment gate and the bounded preference (/gr sound
    on|off); THIS file is the only one that calls PlaySoundFile, under pcall, so a
    missing file or a refused call leaves the addon silent without a Lua error and
    without blocking the rest of the rendering. CORRECT re-arms the gate (the next
    click plays the sound of the new composition) and so does every new
    intermission. The three files are SILENT PLACEHOLDERS until the raid lead
    delivers the real recordings (README.md, "Replacing the three sounds").

    SIMULATION MODE (two entries, reachable from the main panel AND from the
    chat): see the dedicated block below. It never arms, disarms or advances the
    ENCOUNTER_START timeline, never touches the live intermission state, never
    publishes a decision into the SavedVariables and never reads a combat event.
    Fourth in-game test: the rehearsal OPENS IMMEDIATELY and is closed by the
    player (no delay, no automatic close, one single cycle), and the ping entry
    is a plain HELP WINDOW (no guided sequence).
----------------------------------------------------------------------------]]
--
--
--
local _, ns = ...

--- Core/Locale.lua is loaded BEFORE this file by the .toc (every string
--- displayed in game goes through it: English by default, French on frFR).
local Locale = assert(ns.Locale, "Core/Locale.lua must be loaded before UI/Intermission.lua")

--- Core/Simulation.lua is loaded BEFORE this file by the .toc: the pure logic of
--- the two simulations (sequences, bounds, refusals) lives there, this layer only
--- renders it and feeds it the injected time step.
local Simulation = assert(ns.Simulation, "Core/Simulation.lua must be loaded before UI/Intermission.lua")

--- Core/Sound.lua is loaded BEFORE this file by the .toc: it owns the PURE table
--- "canonical state -> soundboard file", the one-playback-per-assignment gate and
--- the bounded preference. THIS layer is the only one that plays anything.
local Sound = assert(ns.Sound, "Core/Sound.lua must be loaded before UI/Intermission.lua")

local UI = ns.UI or {}
ns.UI = UI

--- Constant local time step (never read from the client): Core/ stays pure and
--- deterministic, testable with an injected dt.
local TICK_SECONDS = 0.1

local panel, ticker, state, run, setupMode

--- ONE-PLAYBACK-PER-ASSIGNMENT gate of the assignment soundboards (Core/Sound.lua).
--- It is reset at every new intermission, at every rehearsal and by CORRECT: a
--- repeated declaration of the SAME composition is sounded once, and a new
--- declaration plays the sound of the NEW composition (documented behaviour).
local soundAssigner = Sound.newAssigner()

--- SIMULATION MODE owns its OWN run and state (see the block further down): the
--- rehearsal can therefore never arm, disarm or move the real flow. The ping
--- entry owns no state at all any more: it is a plain INFORMATION window.
local simRun, simState, pingPanel

--- API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
--- Constraint: this panel only displays strings written by the player (a click
--- on a composition) or prepared out of game (GIDEON SavedVariables). No unit
--- value is read, hence no comparison on a secret value.
local function config()
    local db = _G.GideonRaidDB
    return ns.Config.resolveIntermission(db and db.intermission)
end

--- Reads the key the PLAYER bound to one of the native ping keybinds
--- (Options > Keybindings > ping system) - API:
--- https://warcraft.wiki.gg/wiki/API_GetBindingKey
--- READ ONLY, under pcall, and it is the ONLY ping-related API this addon
--- touches: it never sends a ping (the ping API is restricted to Blizzard's UI).
--- The candidates come from Core (their exact names are still to be confirmed in
--- game); a wrong candidate or a missing API simply means "no key known", and the
--- panel then asks for a keybind instead of showing a shortcut that does not
--- exist.
--- @param bindNames table|nil candidate binding names, ordered
--- @return string|nil key ("Q", "ALT-F", ...)
local function resolveBindingKey(bindNames)
    if type(bindNames) ~= "table" then
        return nil
    end
    if type(_G.GetBindingKey) ~= "function" then
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

--- ---------------------------------------------------------------------------
--- ASSIGNMENT SOUNDBOARDS: the ONLY audio call of the whole addon.
--- ---------------------------------------------------------------------------

--- Plays one sound file on the MASTER channel. The FILE and the CHANNEL are
--- decided by Core/Sound.lua; this layer only hands them to the client.
--- API ref 12.x: https://warcraft.wiki.gg/wiki/API_PlaySoundFile
--- Constraint: a file that does not exist, a path the client refuses or an API
--- that is not there must leave the addon SILENT, without an error and without
--- interrupting the rest of the rendering: hence the type() guard and the pcall,
--- exactly like the ping keybind read above (GetBindingKey).
--- @param path string|nil client path ("Interface\AddOns\GideonRaid\Sound\...")
--- @param channel string|nil sound channel ("Master")
--- @return boolean played
local function playSoundFile(path, channel)
    if type(path) ~= "string" or path == "" then
        return false
    end
    if type(_G.PlaySoundFile) ~= "function" then
        return false
    end
    local ok = pcall(_G.PlaySoundFile, path, channel)
    return ok == true
end

--- THE ASSIGNMENT SOUNDBOARD of the composition the player just declared (real
--- flow as in a rehearsal). Core decides: one file per canonical state, ONE
--- playback per assignment, and the player preference; an unknown declaration, a
--- disabled preference or an already sounded assignment simply stays silent.
--- @param declaration string|nil canonical state ("1V3R" | "2V2R" | "3V1R")
--- @return boolean played
function UI.PlayAssignSound(declaration)
    local c = config()
    local request = Sound.takeAssignSound(soundAssigner, declaration, c.soundEnabled)
    if request == nil then
        return false
    end
    return playSoundFile(request.path, request.channel)
end

--- Forgets the current assignment (CORRECT, `/gr inter stop`, every new
--- intermission and every rehearsal): the NEXT click plays the sound of the
--- composition it declares - the natural behaviour after a correction.
function UI.ResetAssignSound()
    Sound.resetAssigner(soundAssigner)
    return soundAssigner
end

--- `/gr sound test <1v3r|2v2r|3v1r>`: plays ONE soundboard on request, so the
--- raid lead can hear and identify the three files WITHOUT waiting for a fight.
--- BOUNDED: an unknown state is REFUSED (nothing is played), and the player
--- preference is honoured - a muted sound stays silent and says so, so a test can
--- never contradict the setting.
--- @param raw string|nil state written by the player ("1v3r", "2V2R", ...)
--- @return boolean played
function UI.SoundTest(raw)
    local resolved = Sound.resolveState(raw)
    if resolved == nil then
        UI.Print(Locale.format("cmd.sound.unknownState", tostring(raw)))
        return false
    end
    local c = config()
    if not c.soundEnabled then
        UI.Print(Locale.t("cmd.sound.testDisabled"))
        return false
    end
    local played = playSoundFile(Sound.pathFor(resolved), Sound.CHANNEL)
    if not played then
        UI.Print(Locale.format("cmd.sound.failed", tostring(Sound.fileName(resolved))))
        return false
    end
    UI.Print(Locale.format("cmd.sound.test", resolved, tostring(Sound.fileName(resolved))))
    return true
end

--- The engine ticks only while something is timed: a SIMULATION (rehearsal or
--- ping test), the encounter clock (waiting for the next intermission) or the
--- intermission itself.
local function engineActive()
    if simRun ~= nil then
        return true
    end
    if run ~= nil then
        return true
    end
    local phase = state ~= nil and state.phase or nil
    return phase == ns.Intermission.PHASE.PENDING or phase == ns.Intermission.PHASE.VISIBLE or phase == ns.Intermission.PHASE.DARK
end

--- The state the panel is CURRENTLY showing. During a rehearsal the panel shows
--- the SIMULATION state: the live intermission (`state`) is never read nor
--- modified by a simulation.
local function displayedState()
    if simRun ~= nil then
        return simState
    end
    return state
end

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
    p:SetSize(560, 360)
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

    -- NO fixed offset anywhere: the size, the position and the label of every
    -- element below come from Core/Layout.intermissionPanel(), applied as-is by
    -- UI.ApplyLayout. See the header: the "big state on top of the banner" bug
    -- came from literal Y offsets.
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetJustifyH("CENTER")
    p.title:SetText(Locale.t("ui.panelTitle"))

    -- CLOSE CROSS ("X", top right). Label and tooltip come from Core/Locale.lua
    -- (ui.closeCross / ui.closeTooltip), shared with the main panel.
    p.closeCross = UI.AttachCloseCross(p, function()
        UI.IntermissionCloseCross()
    end)

    -- The SIMULATION banner: displayed ONLY while a rehearsal drives the panel.
    -- Two lines (banner + "you close the panel yourself"), computed by Core and
    -- STACKED under the title: it can never overlap the state any more.
    p.simBanner = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.simBanner:SetJustifyH("CENTER")
    p.simBanner:SetText("")
    p.simBanner:SetTextColor(1.0, 0.82, 0.0)
    p.simBanner:Hide()

    -- The STATE, in very large type: the only thing to read first in combat
    -- ("3V1R"). It stays empty until the player declares.
    p.state = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.state:SetJustifyH("CENTER")
    p.state:SetText("")

    -- The headline: "GET READY: 2 s", "LOOK AT THE ORB COLOR...: 3 s", or the
    -- placement headline before the pull. During a REHEARSAL Core replaces it by
    -- the rehearsal line (no boss, no orb to read, no countdown).
    p.headline = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.headline:SetJustifyH("CENTER")
    p.headline:SetText("")

    -- The ping banner: the SECOND thing to read ("PING: YES/NO"), colored with
    -- the ping color of the state. Text and color come from Core.
    p.pingBanner = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.pingBanner:SetJustifyH("LEFT")
    p.pingBanner:SetText("")
    p.pingBanner:Hide()

    -- The essential, at most three short lines (role, ping/key, action).
    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetJustifyH("LEFT")
    p.body:SetJustifyV("TOP")
    p.body:SetText("")

    p.buttons = {}
    -- Three buttons: the player clicks the ORB COMPOSITION seen above their
    -- head. The label comes from Core ("3 verts + 1 rouge / 3V1R /
    -- numero : 1 ou 3"): the UI layer computes nothing.
    -- The number is only a HINT: 1 and 3 are AMBIGUOUS about the color, only 2
    -- is unambiguous (2 verts + 2 rouges).
    -- ONCE THE CHOICE IS CLICKED the three buttons DISAPPEAR (Core decides:
    -- snapshot.showButtons): the layout no longer contains them, so they are
    -- HIDDEN and can never be drawn on top of the SIMULATION banner. CORRECT
    -- brings the three choices back.
    for index = 1, #ns.Intermission.STATES do
        local key = ns.Intermission.STATES[index]
        local button = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        button:SetScript("OnClick", function()
            UI.IntermissionDeclare(key)
        end)
        p.buttons[index] = button
    end

    -- REDO / CORRECT: forgets the declaration and brings the three choices back.
    -- Usable as many times as needed (the state machine stays untouched).
    p.redo = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.redo:SetScript("OnClick", function()
        UI.IntermissionRedo()
    end)
    p.redo:Hide()

    -- OK: validates the placement (step b of the flow) and closes the panel.
    p.ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.ok:SetScript("OnClick", function()
        UI.IntermissionConfirmSetup()
    end)
    p.ok:Hide()

    -- Close: in the real flow it hides the panel (the clock keeps running); in
    -- placement mode it cancels the placement; during a REHEARSAL it CLOSES the
    -- rehearsal (the player owns it).
    p.close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetScript("OnClick", function()
        UI.IntermissionClosePanel()
    end)

    p:Hide()
    panel = p
    return panel
end

--- The elements of the intermission panel, by block id (Core/Layout.lua names
--- every block). The rendering layer only maps an id to its frame.
--- @return table array of { id = string, frame = Frame|FontString }
local function panelElements(p)
    return {
        { id = "title", frame = p.title },
        { id = "simBanner", frame = p.simBanner },
        { id = "state", frame = p.state },
        { id = "headline", frame = p.headline },
        { id = "pingBanner", frame = p.pingBanner },
        { id = "body", frame = p.body },
        { id = "choice1", frame = p.buttons[1] },
        { id = "choice2", frame = p.buttons[2] },
        { id = "choice3", frame = p.buttons[3] },
        { id = "redo", frame = p.redo },
        { id = "ok", frame = p.ok },
        { id = "close", frame = p.close },
    }
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
    db.intermission.position = UI.CapturePosition(p)
end

--- Applies the PERSISTED position of the ping-training frame (centered by
--- default). Called before the frame is shown, so the player always finds it
--- where they left it. Does nothing while the frame does not exist yet (it is
--- built lazily, on the first simulation).
function UI.PingPanelApplyPosition()
    if pingPanel == nil then
        return nil
    end
    local db = _G.GideonRaidDB
    local pos = ns.Config.resolvePosition(type(db) == "table" and db.pingPanelPosition or nil)
    pingPanel:ClearAllPoints()
    pingPanel:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    return pos
end

--- Saves the position of the ping-training frame (drag stop).
function UI.SavePingPanelPosition()
    if pingPanel == nil or type(_G.GideonRaidDB) ~= "table" then
        return nil
    end
    _G.GideonRaidDB.pingPanelPosition = UI.CapturePosition(pingPanel)
    return _G.GideonRaidDB.pingPanelPosition
end

--- Parses a Core color code ("|cff40ff40") into RGB floats.
--- Rendering helper only: the color itself comes from Core (ping by dominant
--- color); a missing/invalid code falls back to the "no ping" red.
local function parseColor(hex)
    if type(hex) == "string" and #hex >= 10 and hex:sub(1, 2) == "|c" then
        local r = tonumber(hex:sub(5, 6), 16)
        local g = tonumber(hex:sub(7, 8), 16)
        local b = tonumber(hex:sub(9, 10), 16)
        if r and g and b then
            return r / 255, g / 255, b / 255
        end
    end
    return 1.0, 0.33, 0.33
end

--- Number of pairs prepared out of game (0 when there is no assignment block).
--- Trivial data presence, no business rule.
local function preparedPairs()
    local assignment = ns.Config.getAssignment()
    if type(assignment) == "table" and type(assignment.pairs) == "table" then
        return #assignment.pairs
    end
    return 0
end

--- Rebuilds the display from what Core/ computed AND applies the PURE layout.
--- The panel NEVER shows more than the essential during a fight (state, role,
--- PING: YES/NO, ONE action line): the long explanations live in docs/, not on
--- screen.
--- ONCE A COMPOSITION IS CLICKED Core hides the three choice buttons
--- (snapshot.showButtons = false) and shows CORRECT: the layout then simply does
--- not contain them, so the applier HIDES them (they can never be drawn on top
--- of the banner) and only the result stays.
--- UI APPLIES, CORE DECIDES: every block of the layout - its order, its size,
--- its offsets, its label - is computed by ns.Layout.intermissionPanel.
--- @return table the snapshot currently displayed
function UI.IntermissionRefresh()
    local p = ensurePanel()
    local c = config()
    local spec = {}

    if setupMode then
        -- Placement mode (before the pull): drag + ping keybind reminder + OK.
        -- Never a simulation (the two modes never overlap).
        local view = ns.Intermission.setupView({ leadSeconds = c.leadSeconds, pairs = preparedPairs() })
        spec.headline = view.headline
        spec.bodyLines = view.lines
        spec.showOk = true
        return UI.ApplyLayout(p, ns.Layout.intermissionPanel(spec), panelElements(p))
    end

    -- The ping policy is INJECTED into Core (Core never reads the SavedVariables)
    -- and decides the role order, the "PING: YES/NO" banner and the ping line.
    -- The binding resolver is injected too: Core stays free of any API call.
    -- During a rehearsal the panel shows the SIMULATION view: the live
    -- intermission (`state`) is left untouched (see displayedState()).
    local snap = ns.Intermission.snapshot(displayedState(), c.pingMode, resolveBindingKey)
    if simRun ~= nil then
        -- Rehearsal: the SIMULATION banner AND a headline adapted to "no boss,
        -- no orb to read, no countdown" (Core/Simulation.forRehearsal).
        snap = Simulation.forRehearsal(snap, simRun)
        spec.bannerLines = snap.simBannerLines
    end
    spec.stateText = snap.stateText
    spec.headline = snap.headline
    spec.pingBanner = snap.pingBanner
    spec.bodyLines = snap.lines
    spec.showChoices = snap.showButtons
    spec.showRedo = snap.showRedo

    local layout = ns.Layout.intermissionPanel(spec)
    UI.ApplyLayout(p, layout, panelElements(p))
    -- The ping banner carries the ping color of the state (Core gives the code).
    if snap.pingBanner ~= nil then
        p.pingBanner:SetTextColor(parseColor(snap.pingColorHex))
    end
    return snap
end

function UI.IntermissionShow()
    local p = ensurePanel()
    setupMode = false
    UI.IntermissionApplyConfig()
    p:Show()
    UI.IntermissionRefresh()
end

function UI.IntermissionHide()
    local p = ensurePanel()
    setupMode = false
    p:Hide()
    if simRun ~= nil then
        -- Hiding the panel ENDS a rehearsal: a rehearsal that is no longer on
        -- screen must not stay "running" (the next /gr sim inter would be refused
        -- and the player would be stuck with a hidden simulation).
        simRun = nil
        simState = nil
    end
end

--[[ SIMULATION MODE (rehearsal alone, with no boss and no raid) ----------------

     Two entries, reachable from the MAIN panel (two buttons) and from the chat
     (/gr sim inter | group | groupe, /gr sim ping, /gr sim stop):

       1. "INTERMISSION GROUP": the intermission panel opens RIGHT AWAY (fourth
          in-game test: the former 3 s delay is gone), the player clicks their
          composition, corrects it (CORRECT) and CLOSES THE PANEL THEMSELVES
          (close cross or Close button). ONE single cycle: nothing closes it
          automatically and nothing relaunches it. No boss, no raid, no
          ENCOUNTER_START, no combat event ever read;
       2. "PING HELP": a SHORT information window: how to bind one key per ping
          (Options > Keybindings > Ping) and what to do during the boss ("when
          the panel says PING: YES, hover YOUR OWN character frame and press
          your key: you ping yourself"). The former GUIDED SEQUENCE (countdown,
          three announced pings, "ping placed" button) is REMOVED: measured in
          game, the addon can neither send nor detect a ping, so there was
          nothing to sequence.

     ISOLATION: the rehearsal owns its own run (`simRun`) and state (`simState`),
     never touches `run` (the pre-computed ENCOUNTER_START timeline) nor `state`
     (the live intermission), never arms/disarms the timeline and never publishes
     a decision into the SavedVariables (a rehearsal must never be read by the
     diagnostic kit as a real choice).
]]
--

--- True while the REAL flow is running (live intermission, or the
--- ENCOUNTER_START timeline armed): a rehearsal is then REFUSED, so a simulation
--- can never be mistaken for a real fight.
local function realFlowBusy()
    if run ~= nil then
        return true
    end
    if type(state) ~= "table" then
        return false
    end
    local phase = state.phase
    return phase == ns.Intermission.PHASE.PENDING or phase == ns.Intermission.PHASE.VISIBLE or phase == ns.Intermission.PHASE.DARK
end

--- True while the INTERMISSION REHEARSAL is running. The ping help window is NOT
--- a simulation: it owns no state, times nothing and never blocks anything.
local function simulationRunning()
    return simRun ~= nil
end

--- Forgets every simulation (SILENT) and hides what they own. Idempotent.
local function clearSimulation()
    simRun = nil
    simState = nil
    -- The rehearsal is over: its assignment soundboard is forgotten too.
    UI.ResetAssignSound()
    if pingPanel ~= nil then
        pingPanel:Hide()
    end
    if panel ~= nil and panel:IsShown() then
        panel:Hide()
    end
    if not engineActive() then
        stopTicker()
    end
end

--- The PING HELP window (an information frame, not an intermission: the two can
--- never overlap on screen conceptually, and the intermission panel always
--- wins). Like the main panel it is DRAGGABLE and its position is persisted
--- (GideonRaidDB.pingPanelPosition).
local function ensurePingPanel()
    if pingPanel then
        return pingPanel
    end
    local p = CreateFrame("Frame", "GideonRaidPingHelpPanel", UIParent, "BackdropTemplate")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetClampedToScreen(true)
    p:SetScript("OnDragStart", function(self)
        if UI.IsPanelLocked() then
            UI.Print(Locale.t("panel.lockedHint"))
            return
        end
        self:StartMoving()
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        UI.SavePingPanelPosition()
    end)
    p:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    -- No fixed offset: Core/Layout.pingHelpPanel() lays the window out.
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetJustifyH("CENTER")
    p.title:SetText("")

    p.closeCross = UI.AttachCloseCross(p, function()
        UI.PingHelpHide()
    end)

    -- The BIG reminder, in large type: what to do, not a countdown.
    p.headline = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.headline:SetJustifyH("CENTER")
    p.headline:SetText("")

    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetJustifyH("LEFT")
    p.body:SetJustifyV("TOP")
    p.body:SetText("")

    -- The keys the player really bound, when they are known (read by the
    -- rendering layer under pcall and injected into Core).
    p.keys = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.keys:SetJustifyH("LEFT")
    p.keys:SetJustifyV("TOP")
    p.keys:SetText("")

    -- Leaving the window: nothing is simulated and nothing is timed, so this
    -- button only closes an information frame.
    p.close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetScript("OnClick", function()
        UI.PingHelpHide()
    end)

    p:Hide()
    pingPanel = p
    return pingPanel
end

--- The elements of the ping help window, by block id (Core/Layout names them).
--- @return table array of { id = string, frame = Frame|FontString }
local function pingHelpElements(p)
    return {
        { id = "title", frame = p.title },
        { id = "headline", frame = p.headline },
        { id = "body", frame = p.body },
        { id = "keys", frame = p.keys },
        { id = "close", frame = p.close },
    }
end

--- Rebuilds the ping help window from the PURE view computed by Core (the key of
--- each ping is INJECTED: Core never calls an API).
--- @return table the applied layout
function UI.PingHelpRefresh()
    local p = ensurePingPanel()
    local view = Simulation.pingHelpView(resolveBindingKey)
    local layout = ns.Layout.pingHelpPanel({ lines = view.lines, keyLines = view.keyLines })
    return UI.ApplyLayout(p, layout, pingHelpElements(p))
end

--- Shows the ping help window (`/gr sim ping`, the main-panel button), where the
--- player left it (persisted position).
function UI.PingHelpShow()
    local p = ensurePingPanel()
    UI.PingPanelApplyPosition()
    p:Show()
    UI.PingHelpRefresh()
end

--- Hides the ping help window. Nothing to disarm: this frame simulates nothing.
function UI.PingHelpHide()
    if pingPanel ~= nil then
        pingPanel:Hide()
    end
end

--- `/gr sim` with no argument and the main-panel SIMULATION buttons land here.
--- The whole argument is parsed by Core (mode + no option any more); an unknown
--- sub-command or a trailing option is REFUSED with a message, nothing is
--- guessed and nothing is launched.
function UI.SimulationCommand(raw)
    local mode, options, err = Simulation.parseCommand(raw)
    if mode == nil then
        if err ~= nil then
            UI.Print(tostring(err))
        end
        UI.Print(Locale.format("cmd.sim.unknown", tostring(raw)))
        UI.Print(Locale.t("cmd.sim.help"))
        return
    end
    if mode == "inter" then
        UI.SimulationInterStart(options)
    elseif mode == "ping" then
        UI.SimulationPingStart()
    else
        UI.SimulationStop()
    end
end

--- Starts the "INTERMISSION GROUP" rehearsal (`/gr sim inter`, aliases group and
--- groupe, plus the main-panel button): the panel opens IMMEDIATELY and the
--- PLAYER closes it (fourth in-game test). ONE cycle, no automatic close, no
--- relaunch, no boss, and the ENCOUNTER_START timeline is left alone.
--- @param options table|nil any option is REFUSED by Core
function UI.SimulationInterStart(options)
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if realFlowBusy() then
        UI.Print(Locale.t("sim.refused.live"))
        return
    end
    if simulationRunning() then
        UI.Print(Locale.t("sim.refused.running"))
        return
    end
    local newRun, err = Simulation.newRun(options)
    if newRun == nil then
        UI.Print(Locale.format("ui.intermissionError", tostring(err)))
        return
    end
    clearSimulation()
    simRun = newRun
    simState = ns.Intermission.newState()
    -- NO lead time: the simulated intermission starts VISIBLE at once, and it is
    -- never ticked: without a boss there is no clock, the player closes it.
    local started, startErr = ns.Intermission.start(simState, {
        leadSeconds = 0,
        visibilitySeconds = c.visibilitySeconds,
        durationSeconds = c.durationSeconds,
    })
    if not started then
        simRun = nil
        simState = nil
        UI.Print(Locale.format("ui.intermissionError", tostring(startErr)))
        return
    end
    -- NEW REHEARSAL: the soundboard gate is re-armed (see beginIntermission).
    UI.ResetAssignSound()
    UI.IntermissionShow()
    UI.Print(Locale.t("cmd.sim.inter"))
end

--- Starts... rather, SHOWS the PING HELP window (`/gr sim ping`, main-panel
--- button): how to bind the keys and the operational reminder. The addon never
--- pings and detects nothing.
function UI.SimulationPingStart()
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if realFlowBusy() then
        UI.Print(Locale.t("sim.refused.live"))
        return
    end
    UI.PingHelpShow()
    UI.Print(Locale.format("cmd.sim.pingStart", Simulation.pingSequenceLine()))
end

--- Stops the REHEARSAL (`/gr sim stop`, the close cross, the Close button) and
--- hides the ping help window. Idempotent: with nothing running it says so.
function UI.SimulationStop()
    local stopped = false
    if simRun ~= nil then
        Simulation.closeRun(simRun)
        stopped = true
    end
    if pingPanel ~= nil and pingPanel:IsShown() then
        stopped = true
    end
    clearSimulation()
    if stopped then
        UI.Print(Locale.t("cmd.sim.closed"))
    else
        UI.Print(Locale.t("cmd.sim.none"))
    end
end

--- Close cross of the INTERMISSION panel:
---   - in PLACEMENT mode it CANCELS the placement (same effect as the existing
---     Close button: the mode is left, the panel is hidden);
---   - during a REHEARSAL it CLOSES the rehearsal (the player owns it);
---   - during the REAL flow it only hides the panel: the intermission clock keeps
---     running, the panel still closes by itself at the end of the intermission
---     and opens again at the next one (nothing is disarmed).
function UI.IntermissionCloseCross()
    if setupMode then
        UI.IntermissionHide()
        return
    end
    UI.IntermissionClosePanel()
end

--- Close button AND close cross of the intermission panel: ONE behaviour for
--- both. A rehearsal is CLOSED BY THE PLAYER (nothing else ends it); the real
--- flow is only hidden (its clock keeps running).
function UI.IntermissionClosePanel()
    if simRun ~= nil then
        UI.SimulationStop()
        return
    end
    UI.IntermissionHide()
end

--- Enters PLACEMENT MODE: the intermission panel is shown before the pull so the
--- player can drag it where they want it (position saved) and read how to
--- prepare the ping keybind. Pressing OK closes it (step b of the flow).
function UI.IntermissionSetup()
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if simulationRunning() then
        -- A rehearsal is showing: the placement would fight it for the panel.
        UI.Print(Locale.t("sim.refused.running"))
        return
    end
    local p = ensurePanel()
    UI.IntermissionApplyConfig()
    setupMode = true
    p:Show()
    UI.IntermissionRefresh()
end

--- OK button of the placement panel: saves the position and closes.
function UI.IntermissionConfirmSetup()
    if not setupMode then
        return
    end
    UI.IntermissionSavePosition()
    UI.IntermissionHide()
    UI.Print(Locale.t("ui.setupDone"))
end

--- Manual key/button: shows (or hides) the intermission panel.
function UI.IntermissionToggle()
    local p = ensurePanel()
    if p:IsShown() then
        UI.IntermissionHide()
        return
    end
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    UI.IntermissionShow()
end

--- Starts ONE intermission (silent): state machine in PENDING, then VISIBLE...
--- Used by the schedule (step c) and by the manual commands.
--- @return boolean started
local function beginIntermission(c)
    if state == nil then
        state = ns.Intermission.newState()
    end
    local started, err = ns.Intermission.start(state, {
        leadSeconds = c.leadSeconds,
        visibilitySeconds = c.visibilitySeconds,
        durationSeconds = c.durationSeconds,
    })
    if not started then
        UI.Print(Locale.format("ui.intermissionError", tostring(err)))
        return false
    end
    -- NEW INTERMISSION: the assignment soundboard gate is re-armed, so the SAME
    -- composition declared at the next intermission plays its sound again.
    UI.ResetAssignSound()
    ensureTicker()
    UI.IntermissionShow()
    return true
end

--- Manual start (`/gr inter start`): verbose, the player asked for it.
function UI.IntermissionStart()
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    if simulationRunning() then
        -- A rehearsal is running: stop it first (/gr sim stop) so a simulated
        -- intermission is never mistaken for a real one.
        UI.Print(Locale.t("sim.refused.running"))
        return
    end
    if beginIntermission(c) then
        UI.Print(Locale.format("ui.started", c.visibilitySeconds))
    end
end

function UI.IntermissionStop()
    stopTicker()
    if state ~= nil then
        ns.Intermission.reset(state)
    end
    UI.ResetAssignSound()
    UI.IntermissionHide()
end

function UI.IntermissionReset()
    stopTicker()
    if state ~= nil then
        ns.Intermission.reset(state)
    end
    UI.IntermissionRefresh()
end

--- Advances by one tick. dt is injected by the engine (local constant): Core
--- never reads the client clock.
---   0. the SIMULATIONS (intermission rehearsal, guided ping test): they own their
---      own run/state and never touch the two clocks below;
---   1. the encounter clock (ENCOUNTER_START is the origin, its arguments are
---      never read) opens the panel shortly before each pre-computed intermission;
---   2. the intermission clock counts the lead time, the visibility window, the
---      darkened room, then DONE -> the panel CLOSES BY ITSELF.
function UI.IntermissionTick(dt)
    -- The SIMULATION owns NO clock of its own any more: the panel opens right
    -- away and the player closes it (fourth in-game test), so nothing is ticked
    -- here. The two clocks below are the REAL flow's, untouched by a rehearsal.
    if run ~= nil then
        local _, opened = ns.Intermission.advanceRun(run, dt)
        if opened ~= nil then
            beginIntermission(config())
        end
        if ns.Intermission.runFinished(run) then
            run = nil
        end
    end
    if state ~= nil then
        local phase = state.phase
        if phase == ns.Intermission.PHASE.PENDING or phase == ns.Intermission.PHASE.VISIBLE or phase == ns.Intermission.PHASE.DARK then
            ns.Intermission.tick(state, dt)
            if state.phase == ns.Intermission.PHASE.DONE then
                UI.IntermissionHide()
            end
        end
    end
    -- Rendering: only the intermission panel is redrawn (the ping help window is
    -- static: it shows the same text until it is closed).
    if panel ~= nil and panel:IsShown() then
        UI.IntermissionRefresh()
    end
    if not engineActive() then
        stopTicker()
    end
end

--- Player declaration: click on a COMPOSITION button (3V1R / 2V2R / 1V3R).
--- A bare ambiguous number ("1" or "3" alone) is refused by Core with a message
--- asking for the dominant color.
--- The ASSIGNMENT SOUNDBOARD of the declared state is played HERE, once, the
--- moment the declaration is accepted (real flow and rehearsal alike): nothing is
--- played without a declaration, and Core/Sound.lua refuses a second playback of
--- the same assignment (CORRECT re-arms it).
function UI.IntermissionDeclare(declaration)
    local c = config()
    if not c.enabled then
        UI.Print(Locale.t("ui.disabled"))
        return
    end
    -- SIMULATION: the click belongs to the REHEARSAL state, and NOTHING is
    -- published into the SavedVariables: the diagnostic kit must never read a
    -- rehearsal as a real decision.
    if simRun ~= nil then
        if simState == nil then
            UI.Print(Locale.t("sim.notOpen"))
            return
        end
        local _, simErr = ns.Intermission.declare(simState, declaration)
        if simErr ~= nil then
            UI.Print(Locale.format("ui.declarationRefused", tostring(simErr)))
            return
        end
        UI.PlayAssignSound(simState.declaration)
        UI.IntermissionRefresh()
        return
    end
    if state == nil or state.phase == ns.Intermission.PHASE.IDLE or state.phase == ns.Intermission.PHASE.DONE then
        -- Manual use outside a scheduled intermission (key, button, command).
        if not beginIntermission(c) then
            return
        end
    end
    local _, err = ns.Intermission.declare(state, declaration)
    if err ~= nil then
        UI.Print(Locale.format("ui.declarationRefused", tostring(err)))
        return
    end
    -- The soundboard of the state just declared, played ONCE (see Core/Sound.lua).
    UI.PlayAssignSound(state.declaration)
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

--- REDO / CORRECT button: forgets the declaration and shows the three
--- composition choices again. Usable as many times as the player wants.
--- It also RE-ARMS the assignment soundboard: the next click plays the sound of
--- the composition it declares, even when it is the same one (documented).
function UI.IntermissionRedo()
    -- The state CURRENTLY shown: during a rehearsal it is the simulation state, so
    -- REDO corrects the simulated declaration and never the live one.
    local target = displayedState()
    if target == nil then
        return
    end
    local _, err = ns.Intermission.clearDeclaration(target)
    if err ~= nil then
        UI.Print(Locale.format("ui.redoFailed", tostring(err)))
        return
    end
    UI.ResetAssignSound()
    UI.IntermissionRefresh()
end

--- ENCOUNTER_START is an instance event, not a combat log one. Its arguments
--- are NOT read (no secret value risk): it is only the STARTING GUN of the
--- pre-computed schedule. The panel then opens by itself shortly before each
--- intermission and closes at the end of each one.
function UI.IntermissionOnEncounterStart()
    -- A rehearsal must NEVER compete with a real fight: it is stopped the moment
    -- the encounter starts. This arms/disarms nothing by itself: the timeline
    -- below is armed exactly as before.
    if simRun ~= nil or (pingPanel ~= nil and pingPanel:IsShown()) then
        clearSimulation()
        UI.Print(Locale.t("sim.stoppedByEncounter"))
    end
    local c = config()
    if not c.enabled or not c.startOnEncounterStart then
        return
    end
    run = ns.Intermission.newRun(c.scheduleSeconds, c.leadSeconds)
    ensureTicker()
    UI.Print(Locale.format("ui.armed", ns.Intermission.runRemaining(run), c.leadSeconds))
end

function UI.IntermissionOnEncounterEnd()
    run = nil
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
    local snap = ns.Intermission.snapshot(displayedState(), c.pingMode, resolveBindingKey)
    UI.Print(
        Locale.format(
            "ui.statusLine",
            Locale.t(c.enabled and "ui.wordEnabled" or "ui.wordDisabled"),
            snap.phase,
            tostring(snap.declaration)
        )
    )
    UI.Print(Locale.format("ui.timelineLine", c.visibilitySeconds, c.durationSeconds, c.scale))
    UI.Print(Locale.format("ui.pingPolicyLine", c.pingMode, snap.policyLine))
    UI.Print(Locale.format("ui.scheduleLine", #c.scheduleSeconds, c.leadSeconds))
    UI.Print(Locale.format("ui.soundLine", Locale.t(c.soundEnabled and "ui.wordEnabled" or "ui.wordDisabled")))
end

--- `/gr inter ping`: which ping to use and which key to press, plus the binding
--- names tried (that is exactly what the in-game confirmation has to check).
function UI.IntermissionPrintPing()
    local c = config()
    local snap = ns.Intermission.snapshot(displayedState(), c.pingMode, resolveBindingKey)
    if snap.declaration == nil then
        UI.Print(Locale.t("ui.noDeclaration"))
        return
    end
    if snap.pingHint == nil then
        UI.Print(Locale.format("err.pingNotAllowed", tostring(snap.roleName), tostring(c.pingMode)))
        return
    end
    UI.Print(snap.pingHint.line)
    UI.Print(Locale.format("ui.pingCandidates", table.concat(snap.pingHint.bindNames, ", ")))
end

--- Prints the plan prepared out of game into the chat (same source as the panel).
function UI.PrintPlan()
    local me = UnitName("player")
    local c = config()
    local assignment, err = ns.Config.getAssignment()
    if not assignment then
        UI.Print(Locale.format("status.noAssignment", tostring(err)))
        return
    end
    local plan, planErr = ns.Intermission.buildPlan(assignment, me, c.pingMode, resolveBindingKey)
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
    -- The close cross is NOT part of a layout (it is chrome shared by the two
    -- panels): its label is refreshed here.
    p.closeCross:SetText(Locale.t("ui.closeCross"))
    -- The ping help window is built lazily: only refresh it when it exists.
    if pingPanel ~= nil then
        pingPanel.closeCross:SetText(Locale.t("ui.closeCross"))
        if pingPanel:IsShown() then
            UI.PingHelpRefresh()
        end
    end
    -- Everything else (title, buttons, disposition) is rebuilt from Core by a
    -- plain refresh: the labels live in Core/Layout.lua, in both languages.
    UI.IntermissionRefresh()
end

function UI.IntermissionInitialize()
    ensurePanel()
    UI.IntermissionApplyConfig()
    UI.IntermissionApplyStaticText()
end
