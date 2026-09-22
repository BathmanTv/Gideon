--[[--------------------------------------------------------------------------
    GideonRaid / UI / Intermission.lua

    RENDERING LAYER ONLY ("Intermission Coach"). This file may call the WoW API
    (frames, fonts, C_Timer, GetBindingKey). It contains NO business computation:
    everything comes from ns.Intermission (snapshot / setupView / run machine).

    12.x prohibitions (see docs/CONVENTIONS.md):
      - no read of aura / health / resource (possible SECRET value);
      - no combat log event;
      - no addon -> addon message in an instance.

    PING: THE PLAYER PINGS, WITH THE NATIVE BLIZZARD PING KEYBIND. Measured in
    game by the raid lead: an addon CANNOT ping at all - neither from a macro nor
    from a binding - the ping API is restricted to Blizzard's own UI ("action
    usable only by the Blizzard UI"). This file therefore:
      - READS the key the player bound (GetBindingKey, under pcall) to tell them
        which key to press;
      - NEVER pings and NEVER prepares a macro: no ping call exists here;
      - shows "set a keybind in Options > Keybindings" as long as no key is bound
        (the exact binding names are still TO BE CONFIRMED IN GAME: the candidate
        list comes from Core/Intermission.lua, PING_BINDINGS).
    MEASURED IN GAME TOO: the ping lands WHERE THE MOUSE IS, so hovering YOUR OWN
    character frame pings YOURSELF - the exact ANCHOR (1V3R) gesture. The ping
    training teaches that gesture; nothing here detects a ping (no API does).

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

    CLOSE CROSS ("X", top right) on BOTH panels (the main one, UI/Panel.lua, and
    this one). During the placement it CANCELS the placement (same effect as the
    existing Close button); during the real flow it only HIDES the panel: the
    intermission clock keeps running, the panel still closes by itself at the end
    and opens again at the next intermission (nothing is disarmed).

    SIMULATION MODE (two entries, reachable from the main panel AND from the
    chat): see the dedicated block below and Core/Simulation.lua. It never arms,
    disarms or advances the ENCOUNTER_START timeline, never touches the live
    intermission state, never publishes a decision into the SavedVariables and
    never reads a combat event.
----------------------------------------------------------------------------]]
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

local UI = ns.UI or {}
ns.UI = UI

--- Constant local time step (never read from the client): Core/ stays pure and
--- deterministic, testable with an injected dt.
local TICK_SECONDS = 0.1

local panel, ticker, state, run, setupMode

--- SIMULATION MODE owns its OWN run and state (see the block further down): the
--- rehearsal can therefore never arm, disarm or move the real flow.
local simRun, simState, pingRun, pingPanel

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

--- The engine ticks only while something is timed: a SIMULATION (rehearsal or
--- ping test), the encounter clock (waiting for the next intermission) or the
--- intermission itself.
local function engineActive()
    if simRun ~= nil then
        return true
    end
    if Simulation.pingTestActive(pingRun) then
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

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", 0, -14)
    p.title:SetText(Locale.t("ui.panelTitle"))

    -- CLOSE CROSS ("X", top right). Label and tooltip come from Core/Locale.lua
    -- (ui.closeCross / ui.closeTooltip), shared with the main panel.
    p.closeCross = UI.AttachCloseCross(p, function()
        UI.IntermissionCloseCross()
    end)

    -- The SIMULATION banner: displayed ONLY while a rehearsal drives the panel.
    -- It is the guarantee that a player never mistakes a simulation for a real
    -- fight ("SIMULATION - NO BOSS, NO RAID", see Core/Simulation.lua).
    p.simBanner = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.simBanner:SetPoint("TOP", 0, -30)
    p.simBanner:SetText("")
    p.simBanner:SetTextColor(1.0, 0.82, 0.0)
    p.simBanner:Hide()

    -- The STATE, in very large type: the only thing to read first in combat
    -- ("3V1R"). It stays empty until the player declares.
    p.state = p:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p.state:SetPoint("TOP", 0, -50)
    p.state:SetText("")

    -- The phase line: "GET READY: 2 s", "LOOK AT THE ORB COLOR...: 3 s",
    -- "ROOM DARKENED...", or the placement headline before the pull.
    p.headline = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.headline:SetPoint("TOP", 0, -90)
    p.headline:SetText("")

    -- The ping banner: the SECOND thing to read ("PING: YES/NO"), colored with
    -- the ping color of the state. Text and color come from Core.
    p.pingBanner = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.pingBanner:SetPoint("TOPLEFT", 24, -126)
    p.pingBanner:SetText("")
    p.pingBanner:Hide()

    -- The essential, at most three short lines (role, ping/key, action).
    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetPoint("TOPLEFT", 24, -156)
    p.body:SetWidth(512)
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
    -- snapshot.showButtons): the panel then shows the result (state / role /
    -- PING / action) and the CORRECT button alone, so a second click by accident
    -- is impossible. CORRECT brings the three choices back.
    for index = 1, #ns.Intermission.STATES do
        local key = ns.Intermission.STATES[index]
        local rec = ns.Intermission.getDeclaration(key)
        local button = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        button:SetSize(168, 64)
        button:SetPoint("TOPLEFT", 20 + ((index - 1) * 176), -230)
        button:SetText(rec ~= nil and rec.buttonLabel or key)
        button:SetScript("OnClick", function()
            UI.IntermissionDeclare(key)
        end)
        p.buttons[index] = button
    end

    -- REDO / CORRECT: forgets the declaration and brings the three choices back.
    -- Usable as many times as needed (the state machine stays untouched).
    p.redo = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.redo:SetSize(130, 22)
    p.redo:SetPoint("BOTTOMLEFT", 16, 14)
    p.redo:SetText(Locale.t("ui.redo"))
    p.redo:SetScript("OnClick", function()
        UI.IntermissionRedo()
    end)
    p.redo:Hide()

    -- OK: validates the placement (step b of the flow) and closes the panel.
    p.ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.ok:SetSize(90, 22)
    p.ok:SetPoint("BOTTOMRIGHT", -114, 14)
    p.ok:SetText(Locale.t("ui.ok"))
    p.ok:SetScript("OnClick", function()
        UI.IntermissionConfirmSetup()
    end)
    p.ok:Hide()

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

--- Rebuilds the display from what Core/ computed. The panel NEVER shows more
--- than the essential during a fight (state, role, PING: YES/NO, ONE action
--- line): the long explanations live in docs/, not on screen.
--- ONCE A COMPOSITION IS CLICKED Core hides the three choice buttons
--- (snapshot.showButtons = false) and shows CORRECT: the panel then shows the
--- result only, so the choice cannot be clicked twice by accident.
function UI.IntermissionRefresh()
    local p = ensurePanel()
    local c = config()

    if setupMode then
        -- Placement mode (before the pull): drag + ping keybind reminder + OK.
        -- Never a simulation (the two modes never overlap).
        local view = ns.Intermission.setupView({ leadSeconds = c.leadSeconds, pairs = preparedPairs() })
        p.state:SetText("")
        p.headline:SetText(view.headline)
        p.body:SetText(table.concat(view.lines, "\n"))
        p.pingBanner:Hide()
        p.simBanner:Hide()
        for _, button in ipairs(p.buttons) do
            button:Hide()
        end
        p.redo:Hide()
        p.ok:SetText(view.okLabel)
        p.ok:Show()
        return view
    end

    -- The ping policy is INJECTED into Core (Core never reads the SavedVariables)
    -- and decides the role order, the "PING: YES/NO" banner and the ping line.
    -- The binding resolver is injected too: Core stays free of any API call.
    -- During a rehearsal the panel shows the SIMULATION state: the live
    -- intermission (`state`) is left untouched (see displayedState()).
    local snap = ns.Intermission.snapshot(displayedState(), c.pingMode, resolveBindingKey)
    p.state:SetText(snap.stateText)
    p.headline:SetText(snap.headline)
    p.body:SetText(table.concat(snap.lines, "\n"))
    -- The three choices are hidden as soon as a composition is clicked
    -- (snap.showButtons); CORRECT is then the only button (snap.showRedo).
    for _, button in ipairs(p.buttons) do
        button:SetShown(snap.showButtons)
    end
    if snap.pingBanner ~= nil then
        p.pingBanner:SetText(snap.pingBanner)
        p.pingBanner:SetTextColor(parseColor(snap.pingColorHex))
        p.pingBanner:Show()
    else
        p.pingBanner:Hide()
    end
    p.redo:SetShown(snap.showRedo)
    p.ok:Hide()
    UI.IntermissionRefreshSimBanner()
    return snap
end

--- Shows/hides the SIMULATION banner of the panel. It is displayed as long as a
--- rehearsal drives the panel: it is the guarantee that the player never mistakes
--- a simulation for a real fight.
function UI.IntermissionRefreshSimBanner()
    local p = ensurePanel()
    if simRun == nil then
        p.simBanner:Hide()
        return nil
    end
    local simSnap = Simulation.snapshot(simRun)
    if simSnap == nil then
        p.simBanner:Hide()
        return nil
    end
    p.simBanner:SetText(simSnap.banner .. "\n" .. simSnap.cycleLine)
    p.simBanner:Show()
    return simSnap
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
end

--[[ SIMULATION MODE (rehearsal alone, with no boss and no raid) ----------------

     Two entries, reachable from the MAIN panel (two buttons) and from the chat
     (/gr sim inter [cycles=N] | group | groupe, /gr sim ping, /gr sim stop):

       1. "INTERMISSION GROUP": the intermission panel opens by itself after 3 s,
          the player clicks their composition, corrects it (REDO), the panel
          closes by itself after ~20 s. ONE cycle by default (in-game feedback:
          one test intermission is enough); a longer rehearsal is available with
          `/gr sim inter cycles=N` (1..9). No boss, no raid, no ENCOUNTER_START,
          no combat event ever read;
       2. "PING TRAINING": the ANCHOR gesture, taught step by step - hover YOUR
          OWN character frame, then press the native ping key (the ping lands
          under the mouse, so you ping yourself). The three native pings
          (Warning -> En route -> Aide) are announced one after the other, with
          the key the player really bound (read HERE, under pcall, and injected
          into Core) and a visible countdown. The player presses the key for real
          and validates with a button. The addon can NOT detect a ping and never
          says it did.

     ISOLATION: the simulations own their own run (`simRun`) and state
     (`simState`), never touch `run` (the pre-computed ENCOUNTER_START timeline)
     nor `state` (the live intermission), never arm/disarm the timeline and never
     publish a decision into the SavedVariables (a rehearsal must never be read by
     the diagnostic kit as a real choice).
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

--- True while ANY simulation is running (rehearsal or ping test).
local function simulationRunning()
    return simRun ~= nil or Simulation.pingTestActive(pingRun)
end

--- Forgets every simulation (SILENT) and hides what they own. Idempotent.
local function clearSimulation()
    simRun = nil
    simState = nil
    pingRun = nil
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

--- The frame of the guided PING TRAINING. Deliberately separate from the
--- intermission panel: a ping training is not an intermission and the two must
--- never overlap on screen. Like the main panel it is DRAGGABLE and its position
--- is persisted (GideonRaidDB.pingPanelPosition).
local function ensurePingPanel()
    if pingPanel then
        return pingPanel
    end
    local p = CreateFrame("Frame", "GideonRaidPingTestPanel", UIParent, "BackdropTemplate")
    p:SetSize(540, 340)
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

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", 0, -14)
    p.title:SetText(Locale.t("sim.ping.title"))

    p.closeCross = UI.AttachCloseCross(p, function()
        UI.SimulationStop()
    end)

    -- The SIMULATION banner: never a doubt about what is being tested.
    p.simBanner = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.simBanner:SetPoint("TOP", 0, -32)
    p.simBanner:SetText(Locale.t("sim.banner"))
    p.simBanner:SetTextColor(1.0, 0.82, 0.0)

    p.step = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.step:SetPoint("TOP", 0, -58)
    p.step:SetText("")

    -- The BIG instruction, step by step: "1. Hover YOUR OWN character frame.
    -- 2. Press <key> (<ping>) -> you ping yourself". Three lines at most (the
    -- WAIT phase shows "GET READY: <ping>").
    p.press = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.press:SetPoint("TOP", 0, -82)
    p.press:SetWidth(512)
    p.press:SetJustifyH("CENTER")
    p.press:SetText("")

    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.body:SetPoint("TOPLEFT", 24, -158)
    p.body:SetWidth(492)
    p.body:SetJustifyH("LEFT")
    p.body:SetJustifyV("TOP")
    p.body:SetText("")

    -- "PING PLACED": the player validates the step THEMSELVES. The addon detects
    -- nothing (no API reports a ping) and says so on the panel.
    p.ok = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.ok:SetSize(150, 24)
    p.ok:SetPoint("BOTTOMRIGHT", -180, 16)
    p.ok:SetText(Locale.t("sim.ping.ok"))
    p.ok:SetScript("OnClick", function()
        UI.SimulationPingConfirm()
    end)

    -- Leave the test at any moment.
    p.quit = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.quit:SetSize(160, 24)
    p.quit:SetPoint("BOTTOMRIGHT", -16, 16)
    p.quit:SetText(Locale.t("sim.ping.quit"))
    p.quit:SetScript("OnClick", function()
        UI.SimulationStop()
    end)

    p:Hide()
    pingPanel = p
    return pingPanel
end

--- Rebuilds the ping-test display from what Core/Simulation computed (the key to
--- press is read here and injected: Core/ never calls GetBindingKey).
local function pingPanelRefresh()
    local p = ensurePingPanel()
    local snap = Simulation.pingTestSnapshot(pingRun, resolveBindingKey)
    if snap == nil then
        -- No run (already left): never an error on screen, just an empty frame.
        p.press:SetText("")
        p.body:SetText("")
        p.ok:Hide()
        return nil
    end
    p.simBanner:SetText(snap.banner)
    p.step:SetText(snap.stepLine)
    p.press:SetText(snap.headline)
    p.body:SetText(table.concat(snap.lines, "\n"))
    p.ok:SetText(snap.stepLabel)
    p.ok:SetShown(not snap.done)
    p.quit:SetText(snap.quitLabel)
    return snap
end

--- Advances the guided ping test by one tick: ONLY the countdown between two
--- pings is timed by the engine (the step itself waits for the player's OK).
local function pingTestTick(dt)
    if pingRun == nil then
        return
    end
    Simulation.advancePingTest(pingRun, dt)
    pingPanelRefresh()
end

--- Advances the INTERMISSION REHEARSAL by one tick. SEPARATE from the real flow:
--- `run` (ENCOUNTER_START timeline) and `state` (live intermission) are never
--- touched here.
local function simulationInterTick(dt)
    if simRun == nil then
        return
    end
    local _, event = Simulation.advance(simRun, dt)
    if event == Simulation.EVENT.OPEN then
        if simState == nil then
            simState = ns.Intermission.newState()
        end
        ns.Intermission.start(simState, Simulation.cycleTimeline(simRun))
        UI.IntermissionShow()
    elseif event == Simulation.EVENT.CLOSE then
        simState = nil
        UI.IntermissionHide()
        if Simulation.runFinished(simRun) then
            local replayed = simRun.closed or 0
            clearSimulation()
            UI.Print(Locale.format("cmd.sim.finished", replayed))
            return
        end
    end
    if simState ~= nil then
        ns.Intermission.tick(simState, dt)
    end
end

--- `/gr sim` with no argument and the main-panel SIMULATION buttons land here.
--- The whole argument is parsed by Core (mode + optional `cycles=N`); an unknown
--- sub-command or a malformed option is REFUSED with a message, nothing is
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
--- groupe, plus the main-panel button): ONE accelerated intermission by default
--- (in-game feedback), no boss. A longer rehearsal is available through
--- `/gr sim inter cycles=N` (bounded 1..9 by Core).
--- @param options table|nil { cycles = number|nil }
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
    local opts = {
        openDelaySeconds = Simulation.DEFAULT_OPEN_DELAY_SECONDS,
        visibilitySeconds = c.visibilitySeconds,
        durationSeconds = c.durationSeconds,
    }
    if type(options) == "table" and options.cycles ~= nil then
        opts.cycles = options.cycles
    end
    local newRun, err = Simulation.newRun(opts)
    if newRun == nil then
        UI.Print(Locale.format("ui.intermissionError", tostring(err)))
        return
    end
    clearSimulation()
    simRun = newRun
    simState = nil
    ensureTicker()
    UI.Print(Locale.format("cmd.sim.inter", simRun.cycles, simRun.openDelay))
end

--- Starts the guided PING TRAINING (`/gr sim ping`, main-panel button): the
--- ANCHOR gesture (hover your own character frame, press the key) rehearsed on
--- the three native pings, with the key the player really bound when it is known.
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
    if simulationRunning() then
        UI.Print(Locale.t("sim.refused.running"))
        return
    end
    local newTest, err = Simulation.newPingTest({})
    if newTest == nil then
        UI.Print(Locale.format("ui.intermissionError", tostring(err)))
        return
    end
    clearSimulation()
    pingRun = newTest
    local p = ensurePingPanel()
    -- The frame reopens where the player left it (persisted position).
    UI.PingPanelApplyPosition()
    p:Show()
    pingPanelRefresh()
    ensureTicker()
    UI.Print(Locale.format("cmd.sim.pingStart", Simulation.pingTestTotal(pingRun), Simulation.pingSequenceLine()))
end

--- "PING PLACED" button of the ping test: the player validates the step
--- THEMSELVES. The addon records no ping: it only announces them (no API reports
--- a ping, so pretending otherwise would be a lie).
function UI.SimulationPingConfirm()
    if pingRun == nil then
        return
    end
    local _, err = Simulation.confirmPingTest(pingRun)
    if err ~= nil then
        UI.Print(tostring(err))
        return
    end
    if not Simulation.pingTestActive(pingRun) then
        UI.Print(Locale.format("cmd.sim.pingFinished", Simulation.pingTestTotal(pingRun)))
    end
    pingPanelRefresh()
end

--- Stops every simulation (`/gr sim stop`, QUIT TEST, the close crosses).
function UI.SimulationStop()
    local stopped = false
    if simRun ~= nil then
        local snap = Simulation.snapshot(simRun)
        UI.Print(Locale.format("cmd.sim.stopped", snap ~= nil and snap.closed or 0))
        stopped = true
    end
    if pingRun ~= nil then
        local snap = Simulation.pingTestSnapshot(pingRun, nil)
        UI.Print(Locale.format("cmd.sim.pingStopped", snap ~= nil and snap.confirmed or 0, snap ~= nil and snap.total or 0))
        Simulation.cancelPingTest(pingRun)
        stopped = true
    end
    clearSimulation()
    if not stopped then
        UI.Print(Locale.t("cmd.sim.none"))
    end
end

--- Close cross of the INTERMISSION panel:
---   - in PLACEMENT mode it CANCELS the placement (same effect as the existing
---     Close button: the mode is left, the panel is hidden);
---   - during a SIMULATION it leaves the rehearsal;
---   - during the REAL flow it only hides the panel: the intermission clock keeps
---     running, the panel still closes by itself at the end of the intermission
---     and opens again at the next one (nothing is disarmed).
function UI.IntermissionCloseCross()
    if setupMode then
        UI.IntermissionHide()
        return
    end
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
    if simRun ~= nil then
        simulationInterTick(dt)
    end
    if pingRun ~= nil then
        pingTestTick(dt)
    end
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
    -- Rendering: the ping-test frame first (it is the surface of its own test).
    if pingPanel ~= nil and pingPanel:IsShown() and pingRun ~= nil then
        pingPanelRefresh()
    elseif panel ~= nil and panel:IsShown() then
        UI.IntermissionRefresh()
    end
    if not engineActive() then
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
    if simRun ~= nil or pingRun ~= nil then
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
    p.title:SetText(Locale.t("ui.panelTitle"))
    p.close:SetText(Locale.t("ui.close"))
    p.ok:SetText(Locale.t("ui.ok"))
    p.redo:SetText(Locale.t("ui.redo"))
    p.closeCross:SetText(Locale.t("ui.closeCross"))
    for index = 1, #ns.Intermission.STATES do
        local key = ns.Intermission.STATES[index]
        local rec = ns.Intermission.getDeclaration(key)
        local button = p.buttons[index]
        if button ~= nil then
            button:SetText(rec ~= nil and rec.buttonLabel or key)
        end
    end
    -- The ping-test frame is built lazily: only refresh its labels when it exists.
    if pingPanel ~= nil then
        pingPanel.title:SetText(Locale.t("sim.ping.title"))
        pingPanel.simBanner:SetText(Locale.t("sim.banner"))
        pingPanel.ok:SetText(Locale.t("sim.ping.ok"))
        pingPanel.quit:SetText(Locale.t("sim.ping.quit"))
        pingPanel.closeCross:SetText(Locale.t("ui.closeCross"))
        if pingRun ~= nil then
            pingPanelRefresh()
        end
    end
    UI.IntermissionRefresh()
end

function UI.IntermissionInitialize()
    ensurePanel()
    UI.IntermissionApplyConfig()
    UI.IntermissionApplyStaticText()
end
