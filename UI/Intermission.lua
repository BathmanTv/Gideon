--[[--------------------------------------------------------------------------
    GideonRaid / UI / Intermission.lua

    COUCHE RENDU UNIQUEMENT (« Intermission Coach »). Ce fichier peut appeler
    l'API WoW (frames, fonts, C_Timer). Il ne contient AUCUN calcul metier :
    tout vient de ns.Intermission.snapshot() / ns.Intermission.buildPlan().

    Interdictions 12.x (voir docs/CONVENTIONS.md) :
      - aucune lecture d'aura / sante / ressource (valeur SECRETE possible) ;
      - aucun evenement de journal de combat ;
      - aucun message addon -> addon en instance ;
      - aucun ping envoye par l'addon : C_Ping.SendMacroPing est #protected
        (https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing). L'addon se
        contente d'AFFICHER le texte d'une macro que le joueur declenche.

    Ce que le joueur voit ici est LOCAL a son client : l'addon ne peut pas
    savoir ce que les autres joueurs voient ni ce qu'ils declarent.
----------------------------------------------------------------------------]]
local _, ns = ...

local UI = ns.UI or {}
ns.UI = UI

local TICK_SECONDS = 0.1

--- Ref API 12.x : https://warcraft.wiki.gg/wiki/Secret_Values
--- Contrainte : ce panneau n'affiche QUE des chaines ecrites par le joueur
--- (clic 1/2/3) ou preparees hors jeu (SavedVariables GIDEON). Aucune valeur
--- d'unite n'est lue, donc aucune comparaison sur une valeur secrete.
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
    -- Le pas de temps est une CONSTANTE LOCALE : aucune valeur lue sur le client,
    --- donc le module Core reste pur et deterministe (testable avec dt injecte).
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
    p.title:SetText("GideonRaid - Intermission Coach")

    -- Le rappel de la convention, en tres gros (exigence du module).
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
    -- Trois boutons : le joueur clique la COMPOSITION d'orbes qu'il voit au-dessus
    -- de sa tete. Le libelle vient de Core (« 3 verts + 1 rouge / 3V1R /
    -- numero : 1 ou 3 ») : la couche UI ne calcule rien.
    -- Le numero n'est qu'un INDICE : 1 et 3 sont AMBIGUS sur la couleur, seul 2
    -- est non ambigu (2 verts + 2 rouges).
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
    p.macroLabel:SetText("Macro de ping (clic = tout selectionner, puis Ctrl+C) :")

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
    p.close:SetText("Fermer")
    p.close:SetScript("OnClick", function()
        UI.IntermissionHide()
    end)

    p:Hide()
    panel = p
    return panel
end

--- Applique echelle + position configurees (aucun calcul metier).
function UI.IntermissionApplyConfig()
    local p = ensurePanel()
    local c = config()
    local pos = c.position
    p:SetScale(c.scale)
    p:ClearAllPoints()
    p:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
end

--- Sauvegarde la position courante du panneau dans les SavedVariables.
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

--- Reconstruit l'affichage a partir de l'etat calcule par Core/.
function UI.IntermissionRefresh()
    local p = ensurePanel()
    local snap = ns.Intermission.snapshot(state)
    p.headline:SetText(snap.headline)
    p.body:SetText(table.concat(snap.lines, "\n"))
    for _, button in ipairs(p.buttons) do
        -- Libelle deja pose a la creation (il vient de Core et ne change pas) :
        -- ici on ne fait que montrer/masquer.
        button:SetShown(snap.showButtons)
    end
    p.macroBox:SetText(snap.macroPrimary or "")
    if snap.macroPrimary then
        p.note:SetText("Secours : " .. tostring(snap.macroFallback) .. " - " .. tostring(snap.macroNote))
    else
        p.note:SetText("Clique la COMPOSITION que tu vois (3 verts + 1 rouge, 2-2, 1 vert + 3 rouges) : la macro apparait ici.")
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

--- Touche/bouton manuel : affiche (ou masque) le panneau de l'intermission.
function UI.IntermissionToggle()
    local p = ensurePanel()
    if p:IsShown() then
        p:Hide()
        return
    end
    local c = config()
    if not c.enabled then
        UI.Print("Intermission Coach desactive (/gr inter on pour l'activer).")
        return
    end
    if state == nil or state.phase == ns.Intermission.PHASE.IDLE then
        UI.IntermissionStart()
        return
    end
    UI.IntermissionShow()
end

--- Demarre l'intermission (declencheur : touche, bouton, ou ENCOUNTER_START).
function UI.IntermissionStart()
    local c = config()
    if not c.enabled then
        UI.Print("Intermission Coach desactive (/gr inter on pour l'activer).")
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
        UI.Print("Intermission : " .. tostring(err))
        return
    end
    ensureTicker()
    UI.Print("Intermission lancee : " .. c.visibilitySeconds .. " s de visibilite, puis salle obscurcie.")
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

--- Avance d'un tick. dt est injecte par le ticker (constante locale) : Core ne
--- lit jamais l'heure du client.
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

--- Declaration du joueur : clic sur un bouton de COMPOSITION (3V1R / 2V2R /
--- 1V3R). Un numero ambigu (« 1 » ou « 3 » seul) est refuse par Core avec un
--- message demandant la couleur dominante.
function UI.IntermissionDeclare(declaration)
    local c = config()
    if not c.enabled then
        UI.Print("Intermission Coach desactive (/gr inter on pour l'activer).")
        return
    end
    if state == nil or state.phase == ns.Intermission.PHASE.IDLE then
        UI.IntermissionStart()
    end
    local _, err = ns.Intermission.declare(state, declaration)
    if err ~= nil then
        UI.Print("Declaration refusee : " .. tostring(err))
        return
    end
    -- On PUBLIE la decision horodatee dans les SavedVariables : le kit de
    -- diagnostic (GideonDiagAddon) la lit ensuite, sans aucune saisie de chat
    -- pendant le combat et sans communication inter-addons.
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

--- ENCOUNTER_START est un evenement d'instance, pas de combat log. Ses arguments
--- ne sont PAS lus (aucun risque de valeur secrete) : seul le declencheur sert.
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
        UI.Print("SavedVariables non initialisees.")
        return
    end
    db.intermission.enabled = enabled and true or false
    UI.Print("Intermission Coach " .. (enabled and "active" or "desactive") .. ".")
end

function UI.IntermissionStatus()
    local c = config()
    local snap = ns.Intermission.snapshot(state)
    UI.Print(
        string.format(
            "intermission : %s, phase %s, declaration %s",
            c.enabled and "active" or "desactive",
            snap.phase,
            tostring(snap.declaration)
        )
    )
    UI.Print(string.format("timeline : %d s visibles, %d s au total, echelle %.2f", c.visibilitySeconds, c.durationSeconds, c.scale))
end

function UI.IntermissionPrintMacro()
    local snap = ns.Intermission.snapshot(state)
    if not snap.macroPrimary then
        UI.Print("Aucune macro : declare d'abord ta composition (/gr inter 3V1R).")
        return
    end
    UI.Print("macro a coller : " .. snap.macroPrimary)
    UI.Print("secours : " .. tostring(snap.macroFallback) .. " (" .. tostring(snap.macroNote) .. ")")
end

--- Affiche le plan prepare hors jeu dans le chat (meme source que le panneau).
function UI.PrintPlan()
    local me = UnitName("player")
    local assignment, err = ns.Config.getAssignment()
    if not assignment then
        UI.Print("pas d'assignation (" .. tostring(err) .. ")")
        return
    end
    local plan, planErr = ns.Intermission.buildPlan(assignment, me)
    if not plan then
        UI.Print("plan illisible (" .. tostring(planErr) .. ")")
        return
    end
    for _, line in ipairs(plan.lines) do
        UI.Print(line)
    end
end

function UI.IntermissionInitialize()
    ensurePanel()
    UI.IntermissionApplyConfig()
end
