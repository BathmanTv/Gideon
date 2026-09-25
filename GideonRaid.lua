--[[--------------------------------------------------------------------------
    GideonRaid / GideonRaid.lua
    Entry point. Event registration, slash command, wiring.

    No combat API, no combat log event, no addon -> addon message:
    see docs/CONVENTIONS.md.
----------------------------------------------------------------------------]]
local addonName, ns = ...

GideonRaid = GideonRaid or {}
local GR = GideonRaid
ns.GR = GR

GR.NAME = addonName
GR.DISPLAY = "GideonRaid"
GR.VERSION = "0.2.0"

--- ---------------------------------------------------------------------------
--- LANGUAGE LAYER (wiring only: Core/ never calls an API).
--- GetLocale is the reference for the client language:
--- https://warcraft.wiki.gg/wiki/API:GetLocale  ->  "enUS", "frFR", "deDE", ...
--- English is the OFFICIAL language of the addon; French is served
--- automatically on a frFR client (see Core/Locale.lua and /gr lang).
--- ---------------------------------------------------------------------------
--- Reads the client language. Called under pcall: if GetLocale is missing
--- (out-of-game harness) or returns something unusable, the result is nil and
--- the effective language falls back to English.
local function detectLocale()
    local ok, value = pcall(GetLocale)
    if ok and type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

--- Resolves and publishes the effective language:
---   db.locale (preference: "auto" | "en" | "fr")  +  GetLocale()  ->  "en"|"fr"
--- Publishes it in ns.Locale (string lookup) and in GR.locale (rest of the code).
local function applyLanguage()
    local db = _G.GideonRaidDB
    GR.detectedLocale = detectLocale()
    GR.localePreference = ns.Config.resolveLocale(type(db) == "table" and db.locale or nil)
    GR.locale = ns.Locale.setActive(ns.Locale.resolve(GR.localePreference, GR.detectedLocale))
    return GR.locale
end

--- Label of the keybinding shown in Options > Keybindings ("Panneau
--- Intermission" in French, English by default). The client reads these globals
--- when it builds the keybinding list, so they are refreshed with /gr lang.
local function applyBindingLabel()
    _G.BINDING_HEADER_GIDEONRAID = GR.DISPLAY
    _G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = ns.Locale.t("ui.bindingLabel")
end

local frame = CreateFrame("Frame")

local function onAddonLoaded(loadedName)
    if loadedName ~= addonName then
        return
    end
    -- SavedVariables are assigned BEFORE ADDON_LOADED: safe to read here.
    _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
    _G.GideonRaidCharDB = _G.GideonRaidCharDB or {}
    -- Language BEFORE the UI is built: the static labels are created from the
    -- effective language.
    applyLanguage()
    applyBindingLabel()
    ns.UI.Initialize()
    ns.UI.IntermissionInitialize()
end

local function onPlayerLogin()
    ns.UI.Refresh()
    -- SAFE DEFAULT of the auto-open filter: with NO target boss configured the
    -- intermission panel never opens by itself, so the player MUST be told (once
    -- per login, and only while no target is configured) - otherwise the fix looks
    -- like a broken addon. `/gr boss <id>` or `/gr inter on` is the way out.
    ns.UI.PrintBossFilterWarning()
end

-- API ref 12.x: https://warcraft.wiki.gg/wiki/Events
-- Constraint: ENCOUNTER_START / ENCOUNTER_END are instance events, NOT combat
-- log events. The arguments of ENCOUNTER_START ARE read - they are the ONLY way
-- to know WHICH boss was pulled - and they are read by Core/BossFilter.lua ALWAYS
-- under pcall: in 12.x an argument may be a SECRET value, and the smallest
-- operation on it (`type()` included) raises. A value that cannot be read is
-- reported as unreadable and is NEVER compared, so the worst case is a panel that
-- does not open by itself - never a Lua error and never the wrong boss.
-- Only what is needed is read: the encounter id (PRIMARY criterion), the name
-- (SECONDARY, depends on the client language) and the difficulty + group size
-- (LOG ONLY, for `/gr idlog on`).
local function onEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    ns.UI.IntermissionOnEncounterStart(ns.BossFilter.observeEncounter(encounterID, encounterName, difficultyID, groupSize))
end

local function onEncounterEnd()
    ns.UI.IntermissionOnEncounterEnd()
end

--- /gr lang (no argument): detected language, effective language and how to
--- change the preference.
local function printLanguage()
    local detected = GR.detectedLocale or ns.Locale.t("cmd.lang.undetected")
    ns.UI.Print(ns.Locale.format("cmd.lang.status", detected, GR.locale or ns.Locale.getActive(), GR.localePreference or ns.Locale.AUTO))
end

--- /gr lang <auto|en|fr>: rules on the preference, persists it in the
--- SavedVariables, re-applies the language and refreshes the panel labels.
--- An unknown value is REFUSED (nothing is persisted, nothing is guessed).
local function setLanguage(mode)
    local wanted = type(mode) == "string" and mode:lower() or ""
    local accepted = ns.Config.resolveLocale(wanted)
    if accepted ~= wanted then
        ns.UI.Print(ns.Locale.format("cmd.lang.unknown", tostring(mode)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        db.locale = accepted
    end
    applyLanguage()
    applyBindingLabel()
    ns.UI.ApplyStaticText()
    ns.UI.IntermissionApplyStaticText()
    ns.UI.Print(ns.Locale.format("cmd.lang.updated", accepted, GR.locale))
    return accepted
end

--- /gr ping (no argument): current ping policy and what it means for the roles.
local function printPingMode()
    local db = _G.GideonRaidDB
    local resolved = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil).pingMode
    ns.UI.Print(ns.Locale.format("cmd.ping.status", resolved, ns.Intermission.pingPolicyLine(resolved)))
end

--- /gr ping <anchors|color|none>: rules on the PING POLICY of the intermission
--- module, persists it in the SavedVariables and re-applies the panel labels.
--- An unknown value is REFUSED (nothing is persisted, nothing is guessed):
--- same mechanics as /gr lang.
local function setPingMode(mode)
    local wanted = type(mode) == "string" and mode:lower() or ""
    local accepted = ns.Config.resolvePingMode(wanted)
    if accepted ~= wanted then
        ns.UI.Print(ns.Locale.format("cmd.ping.unknown", tostring(mode)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        if type(db.intermission) ~= "table" then
            db.intermission = ns.Config.defaultIntermission()
        end
        db.intermission.pingMode = accepted
    end
    ns.UI.IntermissionApplyStaticText()
    ns.UI.Print(ns.Locale.format("cmd.ping.updated", accepted, ns.Intermission.pingPolicyLine(accepted)))
    return accepted
end

--- /gr sound (no argument): state of the ASSIGNMENT SOUNDBOARD preference and
--- how to change it. The sound itself is played by the rendering layer the moment
--- a composition is declared; Core/ owns the bounded resolution (only an exact
--- `false` mutes it).
local function printSoundSetting()
    local db = _G.GideonRaidDB
    local resolved = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
    local word = ns.Locale.t(resolved.soundEnabled and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.sound.status", word))
end

--- /gr sound on|off: rules on the ASSIGNMENT SOUNDBOARD preference, persists it in
--- the SavedVariables and says the new state. An unknown value is REFUSED
--- (nothing is persisted, nothing is guessed): same mechanics as /gr lang and
--- /gr ping.
local function setSoundSetting(raw)
    local wanted = type(raw) == "string" and raw:lower() or ""
    local accepted = ns.Sound.resolveSwitch(wanted)
    if accepted == nil then
        ns.UI.Print(ns.Locale.format("cmd.sound.unknown", tostring(raw)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        if type(db.intermission) ~= "table" then
            db.intermission = ns.Config.defaultIntermission()
        end
        db.intermission.soundEnabled = accepted
    end
    local word = ns.Locale.t(accepted and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.sound.updated", word))
    return accepted
end

--- /gr sound test <1v3r|2v2r|3v1r> (and `/gr sound test` alone, which recalls the
--- setting): plays ONE soundboard on request so the three files can be checked
--- without waiting for a fight. An unknown state is REFUSED and nothing is played.
--- `/gr sound test start` also plays the INTERMISSION START sound on request.
local function soundCommand(argument)
    local tested = argument:match("^test%s+(.+)$")
    if tested ~= nil then
        ns.UI.SoundTest(tested)
        return
    end
    if argument == "test" then
        -- The state is missing: recall the setting (its text names the three
        -- accepted test values) instead of guessing which sound to play.
        printSoundSetting()
        return
    end
    setSoundSetting(argument)
end

--- The saved intermission block, created if it is missing (never a shared table).
--- @return table|nil block, boolean created
local function intermissionBlock()
    local db = _G.GideonRaidDB
    if type(db) ~= "table" then
        return nil
    end
    if type(db.intermission) ~= "table" then
        db.intermission = ns.Config.defaultIntermission()
    end
    return db.intermission
end

--- "none" instead of an empty string: an empty allow-list is a MEANING (the safe
--- default: nothing opens by itself), not a missing value.
local function describeList(text)
    if text == "" then
        return ns.Locale.t("cmd.boss.value.absent")
    end
    return text
end

--- THE DELIVERED TARGET of the addon (`Core/Config.lua`), in one line: the encounter
--- id and the two names are MEASURED values shipped with the addon, so the raid lead
--- always sees what a fresh guild member gets WITHOUT typing anything.
--- @return string
local function deliveredLine()
    return ns.Locale.format("cmd.boss.delivered", ns.Config.deliveredIdsText(), ns.Config.deliveredNamesText())
end

--- `/gr boss` (no argument): WHAT WILL OPEN AT THE NEXT PULL - the EFFECTIVE
--- auto-open target (the delivered default of the addon plus whatever a player
--- added, or nothing after an explicit `/gr boss clear`), where it comes from, the
--- manual override and the encounter id log.
local function printBossTarget()
    local c = ns.Config.resolveIntermission(type(_G.GideonRaidDB) == "table" and _G.GideonRaidDB.intermission or nil)
    local word = ns.Locale.t(c.idlog and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.boss.status", ns.BossFilter.targetSummary(c), word))
    ns.UI.Print(ns.BossFilter.sourceLine(c))
    ns.UI.Print(deliveredLine())
    if not ns.BossFilter.hasTarget(c) then
        -- NOTHING will open: say it HERE too, with the exact procedure (this is the
        -- state `/gr boss clear` leaves the player in - a deliberate choice).
        ns.UI.Print(ns.Locale.t("cmd.boss.noTarget"))
    elseif c.overrideEncounter then
        ns.UI.Print(ns.Locale.t("cmd.boss.overrideArmed"))
    end
end

--- /gr boss <id>: ADDS one encounter id to the entries persisted for the player
--- (the PRIMARY criterion: `ENCOUNTER_START` arg1, an integer, identical in every
--- language). The EFFECTIVE target is `Config.resolveIntermission().bossIds`: the
--- delivered default of the addon PLUS these entries, so adding an id never removes
--- the target the addon ships with (and `/gr boss 3445` is idempotent). An explicit
--- `/gr boss clear` is NOT undone by an addition: the marker stays, so the delivered
--- default does not come back behind the back of the player.
--- A value that is not a positive integer is REFUSED without persisting anything
--- (same mechanics as /gr lang, /gr ping and /gr sound): nothing is invented, and
--- the id of the target boss is never guessed here - `/gr idlog on` measures it.
local function addBossTarget(raw)
    local id = ns.BossFilter.resolveId(raw)
    if id == nil then
        ns.UI.Print(ns.Locale.format("cmd.boss.unknown", tostring(raw)))
        return nil
    end
    local block = intermissionBlock()
    if block == nil then
        ns.UI.Print(ns.Locale.t("ui.noSavedVariables"))
        return nil
    end
    block.bossIds = ns.BossFilter.addId(block.bossIds, id)
    local c = ns.Config.resolveIntermission(block)
    ns.UI.Print(ns.Locale.format("cmd.boss.added", id, #c.bossIds, ns.BossFilter.targetSummary(c)))
    return id
end

--- /gr boss name <text>: adds the SECONDARY criterion - the exact encounter NAME
--- the client displays. It is language dependent (the raid lead plays on a French
--- client), so the list stays EMPTY by default and no translation is ever guessed.
local function addBossName(raw)
    local name = ns.BossFilter.resolveName(raw)
    if name == nil then
        ns.UI.Print(ns.Locale.format("cmd.boss.nameUnknown", tostring(raw)))
        return nil
    end
    local block = intermissionBlock()
    if block == nil then
        ns.UI.Print(ns.Locale.t("ui.noSavedVariables"))
        return nil
    end
    block.bossNames = ns.BossFilter.addName(block.bossNames, name)
    local c = ns.Config.resolveIntermission(block)
    ns.UI.Print(ns.Locale.format("cmd.boss.nameAdded", name, ns.BossFilter.targetSummary(c)))
    return name
end

--- /gr boss clear: empties BOTH lists AND stamps the explicit-clear marker, so the
--- DELIVERED default of the addon (encounter id + the two names) is dropped too.
--- From then on, nothing opens by itself until a target is added again - the marker
--- is what keeps "the player emptied the target on purpose" apart from "the addon
--- was never configured" (which gets the delivered default).
local function clearBossTarget()
    local block = intermissionBlock()
    if block == nil then
        ns.UI.Print(ns.Locale.t("ui.noSavedVariables"))
        return
    end
    block.bossIds = {}
    block.bossNames = {}
    block.bossTargetCleared = true
    ns.UI.Print(ns.Locale.t("cmd.boss.cleared"))
end

--- /gr boss list: the two EFFECTIVE allow-lists with the PROVENANCE of each entry
--- (delivered with the addon / added by a player), where the target comes from, the
--- delivered default, the state of the manual override and the encounters memorized
--- by the idlog (newest first).
local function listBossTarget()
    local db = _G.GideonRaidDB
    local c = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
    ns.UI.Print(ns.Locale.format("cmd.boss.list.ids", describeList(ns.BossFilter.annotateIds(c.bossIds, c.bossIdsOwn))))
    ns.UI.Print(ns.Locale.format("cmd.boss.list.names", describeList(ns.BossFilter.annotateNames(c.bossNames, c.bossNamesOwn))))
    ns.UI.Print(ns.BossFilter.sourceLine(c))
    ns.UI.Print(deliveredLine())
    ns.UI.Print(ns.Locale.format("cmd.boss.list.override", ns.Locale.t(c.overrideEncounter and "ui.wordEnabled" or "ui.wordDisabled")))
    local rawSeen = nil
    if type(db) == "table" and type(db.intermission) == "table" then
        rawSeen = db.intermission.seenEncounters
    end
    local seen = ns.BossFilter.toList(rawSeen)
    ns.UI.Print(ns.Locale.format("cmd.boss.list.seen", #seen))
    for index = 1, #seen do
        ns.UI.Print("  " .. ns.BossFilter.seenLine(seen[index]))
    end
end

--- /gr boss <list|clear|name <text>|<id>> : an unknown or non-numeric value is
--- REFUSED without persisting anything.
local function bossCommand(argument)
    if argument == "list" then
        listBossTarget()
        return
    end
    if argument == "clear" then
        clearBossTarget()
        return
    end
    local named = argument:match("^name%s+(.+)$")
    if named ~= nil then
        addBossName(named)
        return
    end
    if argument == "name" then
        ns.UI.Print(ns.Locale.format("cmd.boss.nameUnknown", ""))
        return
    end
    addBossTarget(argument)
end

--- /gr idlog (no argument): the state of the encounter id log - the measurement
--- mechanism that gives the REAL id of the target boss.
local function printIdlog()
    local c = ns.Config.resolveIntermission(type(_G.GideonRaidDB) == "table" and _G.GideonRaidDB.intermission or nil)
    local word = ns.Locale.t(c.idlog and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.idlog.status", word, ns.BossFilter.MAX_SEEN))
end

--- /gr idlog on|off: turns the log on/off and PERSISTS it. An unknown value is
--- REFUSED without persisting anything (same mechanics as /gr lang).
local function setIdlog(raw)
    local wanted = ns.BossFilter.resolveSwitch(raw)
    if wanted == nil then
        ns.UI.Print(ns.Locale.format("cmd.idlog.unknown", tostring(raw)))
        return nil
    end
    local block = intermissionBlock()
    if block == nil then
        ns.UI.Print(ns.Locale.t("ui.noSavedVariables"))
        return nil
    end
    block.idlog = wanted
    local word = ns.Locale.t(wanted and "ui.wordEnabled" or "ui.wordDisabled")
    ns.UI.Print(ns.Locale.format("cmd.idlog.updated", word))
    if wanted then
        -- Say the procedure straight away: one pull with the log on, then /gr boss.
        ns.UI.Print(ns.Locale.format("cmd.idlog.status", word, ns.BossFilter.MAX_SEEN))
    end
    return wanted
end

--- /gr style (no argument): WHICH CARD STYLE the intermission panel uses, and how
--- to change it. The list of candidates comes from Core/Layout (it owns the style
--- tables): the chat never writes a style name on its own.
local function printStyleSetting()
    local db = _G.GideonRaidDB
    local resolved = ns.Config.resolveIntermission(type(db) == "table" and db.intermission or nil)
    local names = {}
    for index = 1, #ns.Layout.STYLE_ORDER do
        local name = ns.Layout.STYLE_ORDER[index]
        names[#names + 1] = ns.Layout.styleNumber(name) or name
    end
    names[#names + 1] = tostring(ns.Layout.SHIPPED_STYLE)
    ns.UI.Print(ns.Locale.format("cmd.style.status", ns.Layout.styleLabel(resolved.style), table.concat(names, ", ")))
    ns.UI.Print(ns.Locale.t("cmd.style.help"))
end

--- /gr style <1..6|gideon|shipped>: chooses the CARD STYLE of the combat intermission
--- panel and PERSISTS it (the panel uses it from the next refresh on). An unknown
--- value is REFUSED - nothing is persisted, nothing is guessed - exactly like
--- /gr sound, /gr lang and /gr ping. `shipped` brings back the delivered style.
--- Core/Layout.resolveStyle() is the ONLY judge of what a style name means (each
--- style carries its own aliases), and Core/Config.resolveStyleName() is the only
--- writer of the field.
--- @param raw string|nil style written by the player
--- @return string|nil the accepted canonical style name
local function setStyleSetting(raw)
    local accepted = ns.Layout.resolveStyle(raw)
    if accepted == nil then
        ns.UI.Print(ns.Locale.format("cmd.style.unknown", tostring(raw)))
        return nil
    end
    local db = _G.GideonRaidDB
    if type(db) == "table" then
        if type(db.intermission) ~= "table" then
            db.intermission = ns.Config.defaultIntermission()
        end
        db.intermission.style = ns.Config.resolveStyleName(accepted)
    end
    -- The panels are refreshed AT ONCE: the raid lead sees his choice on the main
    -- panel and on the intermission panel without waiting for anything.
    ns.UI.IntermissionApplyConfig()
    ns.UI.IntermissionRefresh()
    if ns.UI.ShowcaseIsShown() then
        ns.UI.ShowcaseRefresh()
    end
    ns.UI.Print(ns.Locale.format("cmd.style.updated", ns.Layout.styleLabel(accepted)))
    return accepted
end

--- /gr diag: the HEALTH REPORT of the addon, in ONE read-only command (see
--- Core/Diag.lua and UI.PrintDiag). It reads the SavedVariables, two sound CVars and
--- - ONLY when the client is already silenced - checks each sound file with
--- PlaySoundFile; it writes nothing, sends nothing, pings nothing and never makes a
--- noise in a client whose sound is on.
local function slashHandler(cmd)
    cmd = (cmd or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Intermission declaration: any form accepted by Core ("3V1R", "2V2R",
    -- "1V3R", "3 verts", "2"). Subcommands (start/stop/on/off/status/macro/
    -- reset) are handled BEFORE, so everything else is a declaration.
    -- "1" or "3" ALONE is refused by Core (ambiguous): it asks for the color.
    local declaration = cmd:match("^inter%s+(.+)$")
    -- /gr lang <mode> : le mode est normalise en minuscules par l'appelant, donc
    -- le motif accepte n'importe quelle valeur et setLanguage() la juge.
    local langMode = cmd:match("^lang%s+(.+)$")
    -- /gr ping <mode> : same mechanics (the pattern accepts anything and
    -- setPingMode() judges it: an unknown value is refused).
    local pingMode = cmd:match("^ping%s+(.+)$")
    -- /gr sound <on|off|test ETA> : ASSIGNMENT SOUNDBOARD preference and its test
    -- entry. The pattern accepts anything and soundCommand() judges it: an unknown
    -- value is REFUSED (nothing is persisted, nothing is played).
    local soundArg = cmd:match("^sound%s+(.+)$")
    -- /gr boss <id|name ETA|list|clear> : which boss may open the panel by itself
    -- (allow-list of encounter ids). The pattern accepts anything and bossCommand()
    -- judges it: an unknown or non-numeric value is REFUSED without persisting
    -- anything.
    local bossArg = cmd:match("^boss%s+(.+)$")
    -- /gr idlog <on|off> : the encounter id log (how the REAL id of the target boss
    -- is captured in game). An unknown value is REFUSED without persisting.
    local idlogArg = cmd:match("^idlog%s+(.+)$")
    -- /gr sim <mode> : SIMULATION MODE (rehearsal alone, no boss, no raid).
    -- The pattern accepts anything and Core/Simulation.resolveCommand() judges it:
    -- an unknown value is REFUSED (nothing is guessed, nothing is launched).
    local simMode = cmd:match("^sim%s+(.+)$")
    -- /gr style <1..6|gideon|shipped> : the CARD STYLE of the combat intermission
    -- panel. The pattern accepts anything and setStyleSetting() judges it (through
    -- Core/Layout.resolveStyle): an unknown value is REFUSED, nothing is persisted.
    local styleArg = cmd:match("^style%s+(.+)$")
    if cmd == "" or cmd == "show" then
        ns.UI.Toggle()
    elseif cmd == "reset" then
        _G.GideonRaidDB = nil
        _G.GideonRaidDB = ns.Config.ensureDB(_G.GideonRaidDB)
        ns.UI.Refresh()
        ns.UI.Print(ns.Locale.t("cmd.reset"))
    elseif cmd == "status" then
        ns.UI.PrintStatus()
    elseif cmd == "plan" then
        ns.UI.PrintPlan()
    elseif cmd == "lang" then
        printLanguage()
    elseif langMode ~= nil then
        setLanguage(langMode)
    elseif cmd == "ping" then
        printPingMode()
    elseif pingMode ~= nil then
        setPingMode(pingMode)
    elseif cmd == "sound" then
        printSoundSetting()
    elseif soundArg ~= nil then
        soundCommand(soundArg)
    elseif cmd == "boss" then
        printBossTarget()
    elseif bossArg ~= nil then
        bossCommand(bossArg)
    elseif cmd == "idlog" then
        printIdlog()
    elseif idlogArg ~= nil then
        setIdlog(idlogArg)
    elseif cmd == "style" then
        printStyleSetting()
    elseif styleArg ~= nil then
        setStyleSetting(styleArg)
    elseif cmd == "diag" then
        -- HEALTH REPORT: sounds + effective target + idlog + ping, in one command.
        -- Read-only and silent (see UI.PrintDiag / Core/Diag.lua).
        ns.UI.PrintDiag()
    elseif cmd == "lock" then
        -- The main panel is movable by default; these three commands are the
        -- lock / unlock / reset-position entry points (same effect as the
        -- LOCK PANEL / UNLOCK PANEL button of the main panel).
        ns.UI.SetPanelLocked(true)
    elseif cmd == "unlock" then
        ns.UI.SetPanelLocked(false)
    elseif cmd == "resetposition" or cmd == "resetpos" then
        ns.UI.ResetPositions()
    elseif cmd == "inter" or cmd == "intermission" then
        ns.UI.IntermissionToggle()
    elseif cmd == "inter start" then
        ns.UI.IntermissionStart()
    elseif cmd == "inter stop" then
        ns.UI.IntermissionStop()
    elseif cmd == "inter reset" then
        ns.UI.IntermissionReset()
    elseif cmd == "inter status" then
        ns.UI.IntermissionStatus()
    elseif cmd == "inter ping" then
        ns.UI.IntermissionPrintPing()
    elseif cmd == "inter place" or cmd == "inter setup" then
        ns.UI.IntermissionSetup()
    elseif cmd == "inter ok" or cmd == "inter confirm" then
        -- VALIDATION OF THE PLACEMENT. The panel itself shows the illustration
        -- and NOTHING else (no button at all, raid-lead request), so the former
        -- OK button is replaced by this command: it saves the position exactly
        -- like the button did (UI.IntermissionConfirmSetup) and closes the panel.
        ns.UI.IntermissionConfirmSetup()
    elseif cmd == "inter on" then
        ns.UI.IntermissionSetEnabled(true)
    elseif cmd == "inter off" then
        ns.UI.IntermissionSetEnabled(false)
    elseif cmd == "sim" then
        ns.UI.Print(ns.Locale.t("cmd.sim.help"))
    elseif cmd == "pinghelp" then
        -- Alias of /gr sim ping: the SHORT help window (how to bind the keys and
        -- how to ping yourself). It simulates nothing and detects nothing.
        ns.UI.SimulationPingStart()
    elseif simMode ~= nil then
        ns.UI.SimulationCommand(simMode)
    elseif declaration ~= nil then
        ns.UI.IntermissionDeclare(declaration)
    else
        ns.UI.Print(ns.Locale.t("cmd.help"))
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        onAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        onPlayerLogin()
    elseif event == "ENCOUNTER_START" then
        onEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        onEncounterEnd()
    end
end)

_G.SLASH_GIDEONRAID1 = "/gr"
_G.SLASH_GIDEONRAID2 = "/gideonraid"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["GIDEONRAID"] = slashHandler

-- API ref 12.1.0: https://warcraft.wiki.gg/wiki/Creating_key_bindings
-- Bindings.xml is loaded AUTOMATICALLY by the client and must NOT be listed in
-- the .toc. The body of a binding is Lua executed insecurely: it only opens the
-- panel. This addon NEVER pings (the ping API is restricted to Blizzard's own
-- UI): the player pings themselves with the native ping keybind (Options >
-- Keybindings > ping system), and the addon only READS that key to display it.
-- The two globals below provide the labels shown in Options > Keybindings. They
-- are set in ENGLISH here (GideonRaid.lua is the FIRST file of the .toc, before
-- Core/Locale.lua) and refreshed in the effective language after ADDON_LOADED
-- and on every /gr lang through applyBindingLabel().
_G.BINDING_HEADER_GIDEONRAID = GR.DISPLAY
_G["BINDING_NAME_GIDEONRAID_INTERMISSION"] = "Intermission panel (Entombed Sentinels)"
