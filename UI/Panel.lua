--[[--------------------------------------------------------------------------
    GideonRaid / UI / Panel.lua

    COUCHE RENDU UNIQUEMENT. Ce fichier peut appeler l'API WoW (frames, fonts).
    Il ne doit contenir AUCUN calcul metier : tout passe par ns.Pairing.

    Interdictions 12.x (voir docs/CONVENTIONS.md) :
      - ne jamais lire UnitAura / UnitHealth / UnitPower d'une autre unite et
        faire un test dessus en combat : la valeur peut etre SECRETE.
      - ne jamais enregistrer un evenement de JOURNAL DE COMBAT (erreur immediate
        en 12.x, voir docs/CONVENTIONS.md section 1.2).
      - ne jamais envoyer de message addon -> addon en instance.
    Les donnees affichees ici viennent EXCLUSIVEMENT de GideonRaidDB (ecrites
    hors jeu par GIDEON) ou de la saisie manuelle du joueur.
----------------------------------------------------------------------------]]
local _, ns = ...

---@class UI
local UI = {}
ns.UI = UI

local panel

local function ensurePanel()
    if panel then
        return panel
    end
    panel = CreateFrame("Frame", "GideonRaidPanel", UIParent, "BackdropTemplate")
    panel:SetSize(300, 260)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not _G.GideonRaidDB or not _G.GideonRaidDB.lockPanel then
            self:StartMoving()
        end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -16)
    panel.title:SetText("GideonRaid")

    panel.body = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.body:SetPoint("TOPLEFT", 16, -44)
    panel.body:SetPoint("BOTTOMRIGHT", -16, 16)
    panel.body:SetJustifyH("LEFT")
    panel.body:SetJustifyV("TOP")
    panel.body:SetText("")

    panel:Hide()
    return panel
end

function UI.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GideonRaid|r: " .. tostring(msg))
end

function UI.Toggle()
    local p = ensurePanel()
    if p:IsShown() then
        p:Hide()
    else
        UI.Refresh()
        p:Show()
    end
end

--- Reconstruit l'affichage a partir des seules donnees non secretes.
--- Le contenu (partenaire, roles, positions, paires) est calcule par
--- Core/Intermission.buildPlan : cette couche ne fait que rendre des lignes.
function UI.Refresh()
    local p = ensurePanel()
    --- Ref API 12.x : https://warcraft.wiki.gg/wiki/Secret_Values
    --- Contrainte : on ne lit que le NOM de sa propre unite ("player"), jamais
    --- une valeur d'unite (sante, aura, ressource) qui pourrait etre secrete.
    local me = UnitName("player")
    local lines = {}
    local assignment, err = ns.Config.getAssignment()

    if _G.GideonRaidDB and type(_G.GideonRaidDB.scale) == "number" then
        p:SetScale(_G.GideonRaidDB.scale)
    end

    if not assignment then
        lines[#lines + 1] = "Aucune assignation GIDEON."
        lines[#lines + 1] = "|cff808080(" .. tostring(err) .. ")|r"
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Demande a GIDEON :"
        lines[#lines + 1] = "!g roster assign"
    else
        local plan, planErr = ns.Intermission.buildPlan(assignment, me)
        if not plan then
            lines[#lines + 1] = "|cffff5555Plan illisible|r (" .. tostring(planErr) .. ")"
        else
            for _, line in ipairs(plan.lines) do
                lines[#lines + 1] = line
            end
        end
    end

    p.body:SetText(table.concat(lines, "\n"))
end

function UI.PrintStatus()
    local assignment, err = ns.Config.getAssignment()
    if not assignment then
        UI.Print("pas d'assignation (" .. tostring(err) .. ")")
        return
    end
    UI.Print(string.format("assignation OK, %d paires", #assignment.pairs))
end

function UI.Initialize()
    ensurePanel()
end
