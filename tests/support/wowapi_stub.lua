--[[--------------------------------------------------------------------------
    tests/support/wowapi_stub.lua
    Stub minimal de l'API WoW, suffisant pour executer la couche rendu hors jeu
    (aucun acces aux APIs de combat, aucun besoin de harnais lourd type wowless).
    Volontairement minuscule : si un fichier a besoin d'autre chose, c'est le
    signe qu'il touche a l'API de combat -> il doit etre refactore.

    Aucun stub d'API de combat n'existe ici (ni UniteAura, ni journal de combat) :
    l'addon n'en appelle aucune, et le jour ou il en appellerait une, les tests
    echoueraient faute de stub - c'est la garde.

    GetBindingKey n'est PAS defini ici, volontairement : hors client ce raccourci
    n'existe pas, donc le cas par defaut teste est « aucun raccourci connu » (le
    panneau demande alors au joueur de binder une touche). Une spec qui veut
    tester l'affichage d'une touche l'installe elle-meme explicitement
    (_G.GetBindingKey = function(name) ... end).

    PlaySoundFile EST defini ici (et enregistre ses appels) : c'est le SEUL appel
    audio de l'addon, la couche de rendu l'encadre d'un pcall, et une spec doit
    pouvoir verifier qu'un son est joue une seule fois avec le bon fichier - puis
    le casser (error / nil) pour prouver que le rendu continue.
----------------------------------------------------------------------------]]
--
local stub = {}

function stub.install()
    local frames = {}
    local tickers = {}

    local Frame = {}
    Frame.__index = Frame
    function Frame:RegisterEvent(e)
        self.__events = self.__events or {}
        self.__events[e] = true
    end
    function Frame:SetScript(name, fn)
        self.__scripts = self.__scripts or {}
        self.__scripts[name] = fn
    end
    --- Retourne le script (OnClick, OnEnter, OnLeave, OnEvent...) pour pouvoir le
    --- declencher depuis un test, par exemple pour verifier le tooltip de la croix
    --- de fermeture (survol lisible).
    function Frame:GetScript(name)
        if not self.__scripts then
            return nil
        end
        return self.__scripts[name]
    end
    function Frame:Fire(event, ...)
        local fn = self.__scripts and self.__scripts.OnEvent
        if fn then
            fn(self, event, ...)
        end
    end
    function Frame:SetSize(width, height)
        self.__width = width
        self.__height = height
    end
    function Frame:GetWidth()
        return self.__width or 0
    end
    function Frame:GetHeight()
        return self.__height or 0
    end
    --- Tous les arguments sont conserves (point, relativeTo, relativePoint, x, y) :
    --- les positions PERSISTEES (panneau principal, panneau intermission, fenetre
    --- de simulation) sont ainsi verifiables hors jeu.
    --- Le CLIENT exige une CHAINE d'ancre en 1er argument : le stub fait pareil,
    --- sinon un bloc sans ancre (bug du 5e test en jeu : les trois boutons de
    --- composition et le bouton OK disparaissaient) passerait la suite de tests.
    function Frame:SetPoint(point, ...)
        assert(
            type(point) == "string" and point ~= "",
            "SetPoint attend une chaine d'ancre (recu : " .. tostring(point) .. ") - le client refuse une ancre nulle"
        )
        self.__point = { point, ... }
    end
    function Frame:ClearAllPoints()
        self.__point = nil
    end
    function Frame:GetPoint()
        local p = self.__point
        if not p or not p[1] then
            return "CENTER", _G.UIParent, "CENTER", 0, 0
        end
        return p[1], p[2], p[3], p[4] or 0, p[5] or 0
    end
    function Frame:SetMovable(movable)
        self.__movable = movable and true or false
    end
    function Frame:IsMovable()
        return self.__movable == true
    end
    function Frame:EnableMouse() end
    function Frame:RegisterForDrag() end
    function Frame:RegisterForClicks() end
    function Frame:SetBackdrop(backdrop)
        -- Le client dessine un fond et une bordure a partir de cette table : le
        -- stub la CONSERVE pour qu'un test puisse verifier qu'un encart a bien un
        -- fond sombre et une bordure (le style vient de Core/Layout).
        self.__backdrop = backdrop
    end
    function Frame:SetBackdropColor(r, g, b, a)
        self.__backdropColor = { r, g, b, a }
    end
    function Frame:GetBackdropColor()
        local c = self.__backdropColor
        if not c then
            return 1, 1, 1, 1
        end
        return c[1], c[2], c[3], c[4]
    end
    function Frame:SetBackdropBorderColor(r, g, b, a)
        self.__backdropBorderColor = { r, g, b, a }
    end
    function Frame:GetBackdropBorderColor()
        local c = self.__backdropBorderColor
        if not c then
            return 1, 1, 1, 1
        end
        return c[1], c[2], c[3], c[4]
    end
    function Frame:CreateTexture(_, _)
        -- Une texture ENFANT (le stub enregistre les points et la texture posee,
        -- comme le client). Les cartes de composition portent une image enfant :
        -- le cadre garde donc sa bordure visible autour de l'image.
        local tex = {}
        function tex:SetPoint(point, ...)
            assert(type(point) == "string" and point ~= "", "Texture:SetPoint attend une chaine d'ancre (recu : " .. tostring(point) .. ")")
            tex.__point = { point, ... }
            -- Une texture peut etre posee aux QUATRE coins (SetPoint TOPLEFT puis
            -- BOTTOMRIGHT) : le stub garde la LISTE, sinon un test ne verrait que
            -- la derniere ancre.
            tex.__points = tex.__points or {}
            tex.__points[#tex.__points + 1] = { point, ... }
        end
        function tex:GetPoint()
            local p = tex.__point
            if not p or not p[1] then
                return "CENTER", _G.UIParent, "CENTER", 0, 0
            end
            return p[1], p[2], p[3], p[4] or 0, p[5] or 0
        end
        function tex:ClearAllPoints()
            tex.__point = nil
        end
        function tex:SetTexture(file)
            tex.__texture = file
        end
        function tex:GetTexture()
            return tex.__texture
        end
        function tex:Show() end
        function tex:Hide() end
        return tex
    end
    function Frame:SetClampedToScreen() end
    function Frame:SetScale(scale)
        self.__scale = scale
    end
    --- Opacite d'un cadre. La VITRINE DE STYLE fait un FONDU D'APPARITION et une
    --- PULSATION DE BORDURE : les deux passent par SetAlpha / SetBackdropBorderColor.
    --- Le stub CONSERVE la valeur, sinon un test ne pourrait pas prouver que les
    --- animations ne tournent que dans la vitrine (et jamais pendant un combat).
    function Frame:SetAlpha(alpha)
        self.__alpha = alpha
    end
    function Frame:GetAlpha()
        if self.__alpha == nil then
            return 1
        end
        return self.__alpha
    end
    --- ZONE DEFILANTE de la vitrine (un ScrollFrame) : le client garde un ENFANT
    --- defilant et une position verticale. Le stub les RETIENT pour qu'un test
    --- puisse verifier que le contenu de la vitrine depasse bien la fenetre.
    function Frame:SetScrollChild(child)
        self.__scrollChild = child
    end
    function Frame:GetScrollChild()
        return self.__scrollChild
    end
    function Frame:SetVerticalScroll(offset)
        self.__verticalScroll = offset
    end
    function Frame:GetVerticalScroll()
        return tonumber(self.__verticalScroll) or 0
    end
    function Frame:SetVerticalScrollRange(range)
        self.__verticalScrollRange = range
    end
    function Frame:EnableMouseWheel() end
    function Frame:DisableMouseWheel() end
    function Frame:GetScale()
        return self.__scale or 1
    end
    function Frame:SetShown(shown)
        self.__shown = shown and true or false
    end
    function Frame:CreateFontString(_, _, font)
        local fs = {}
        -- La police demandee a la creation est ENREGISTREE (comme le client) : un
        -- test peut verifier que le mot BOSS utilise la plus grande police et les
        -- mots de survie la police courante.
        fs.__font = font
        -- Les points sont ENREGISTRES (comme pour les cadres) : un test peut
        -- verifier que UI/ applique bien la disposition calculee par Core/Layout.
        -- Comme le client, le stub REFUSE une ancre nulle (1er argument).
        function fs:SetPoint(point, ...)
            assert(
                type(point) == "string" and point ~= "",
                "FontString:SetPoint attend une chaine d'ancre (recu : " .. tostring(point) .. ")"
            )
            fs.__point = { point, ... }
        end
        --- SetPoint(point, x, y) : le cadre est ancre au PARENT au meme point,
        --- avec les decalages demandes (c'est exactement ce que fait l'applier).
        function fs:GetPoint()
            local p = fs.__point
            if not p or not p[1] then
                return "CENTER", _G.UIParent, "CENTER", 0, 0
            end
            return p[1], _G.UIParent, p[1], p[2] or 0, p[3] or 0
        end
        function fs:ClearAllPoints()
            fs.__point = nil
        end
        function fs:SetSize() end
        function fs:SetHeight() end
        function fs:SetText(t)
            fs.__text = t
        end
        function fs:GetText()
            return fs.__text
        end
        function fs:SetJustifyH() end
        function fs:SetJustifyV() end
        function fs:SetFontObject(fontObject)
            fs.__font = fontObject
            fs.__fontFile = nil
            fs.__fontSize = nil
            return fs.__font
        end
        function fs:GetFontObject()
            return fs.__font
        end
        --- SetFont(file, size, flags) : LE CLIENT REMPLACE L'OBJET DE POLICE. Le
        --- stub enregistre donc le FICHIER et la TAILLE telle quelle (troisieme
        --- argument : le drapeau, une chaine vide chez nous). Un test peut ainsi
        --- verifier la taille REELLE du mot (44 px / 64 px, Core/Layout) au lieu
        --- de croire un objet de police dont l'addon ne peut pas lire la taille
        --- hors du jeu.
        function fs:SetFont(file, size, flags)
            fs.__fontFile = file
            fs.__fontSize = size
            fs.__fontFlags = flags
            fs.__font = nil
            return true
        end
        function fs:GetFont()
            return fs.__fontFile, fs.__fontSize, fs.__fontFlags
        end
        function fs:SetWidth(width)
            fs.__width = width
        end
        function fs:SetShown(shown)
            fs.__shown = shown and true or false
        end
        -- Visibility of a FontString (real API: Show/Hide/IsShown). The ping
        -- banner and the macro zone of the intermission panel use them to show
        -- ONLY what the current role has to read.
        function fs:Show()
            fs.__shown = true
        end
        function fs:Hide()
            fs.__shown = false
        end
        function fs:IsShown()
            return fs.__shown ~= false
        end
        function fs:SetTextColor(r, g, b)
            fs.__color = { r, g, b }
        end
        return fs
    end
    function Frame:Show()
        self.__shown = true
    end
    function Frame:Hide()
        self.__shown = false
    end
    function Frame:IsShown()
        return self.__shown == true
    end
    function Frame:StartMoving() end
    function Frame:StopMovingOrSizing() end
    function Frame:SetNormalTexture(texture)
        self.__normalTexture = texture
        return self:GetNormalTexture()
    end
    --- Le CLIENT renvoie un objet Texture : le stub en renvoie un miniature, dont
    --- GetTexture() rend le chemin DEMANDE - c'est ce qu'une spec verifie pour
    --- prouver que le bouton affiche bien l'image de sa composition.
    function Frame:GetNormalTexture()
        local path = self.__normalTexture
        return {
            __path = path,
            GetTexture = function()
                return path
            end,
            SetTexture = function() end,
            SetTexCoord = function() end,
            SetAllPoints = function() end,
        }
    end
    function Frame:SetPushedTexture(texture)
        self.__pushedTexture = texture
        return self.__normalTexture or texture
    end
    function Frame:GetPushedTexture()
        return { GetTexture = function() end }
    end
    function Frame:SetHighlightTexture(texture)
        self.__highlightTexture = texture
        return { GetTexture = function() end }
    end
    function Frame:SetDisabledTexture(texture)
        self.__disabledTexture = texture
        return { GetTexture = function() end }
    end
    function Frame:SetTexCoord() end
    function Frame:SetAllPoints() end
    -- LIBELLE D'UN BOUTON. Ce n'est PAS une methode de Frame dans le client :
    -- un Frame NU (une carte d'image dessinee par UI.CreateCard("Frame", ...))
    -- n'a ni SetText ni GetText, et l'appeler leve « attempt to call method
    -- 'SetText' (a nil value) ». Le stub reproduit cette difference (voir
    -- CreateFrame plus bas) : c'est ce qui rend le bug visible hors jeu.
    --   * un Button (et un EditBox) : a SetText/GetText ;
    --   * un Frame nu : ne les a PAS (FRAME_WITHOUT_TEXT ci-dessous).
    function Frame:SetText(t)
        self.__text = t
    end
    function Frame:GetText()
        return self.__text
    end
    function Frame:SetEnabled(enabled)
        self.__enabled = enabled and true or false
    end
    function Frame:Click()
        local fn = self.__scripts and self.__scripts.OnClick
        if fn then
            fn(self, "LeftButton", false)
        end
    end
    -- Zone de texte (macro a copier).
    function Frame:SetAutoFocus() end
    function Frame:SetFocus()
        local fn = self.__scripts and self.__scripts.OnEditFocusGained
        if fn then
            fn(self)
        end
    end
    function Frame:ClearFocus() end
    function Frame:HighlightText()
        self.__highlighted = true
    end
    function Frame:SetTextInsets() end

    --[[ UN FRAME NU N'A PAS DE LIBELLE.

         Reproduit le client : Frame:SetText / Frame:GetText n'existent PAS sur
         un Frame (seuls Button et EditBox les portent, et les FontString les
         definissent pour eux-memes). C'est exactement le meme raisonnement que
         pour l'ancre nulle de SetPoint plus haut : le stub doit REFUSER ce que le
         client refuse, sinon la suite de tests valide du code qui leverait en jeu
         (« attempt to call method 'SetText' (a nil value) »), et l'applier
         s'arreterait au milieu du panneau.
    ]]
    local FRAME_WITHOUT_TEXT = {
        __index = function(_, key)
            if key == "SetText" or key == "GetText" then
                return nil
            end
            return Frame[key]
        end,
    }

    --- Le type d'un frame cree : un Button (ou un template de bouton, comme
    --- "UIPanelButtonTemplate") porte un LIBELLE, les autres non.
    --- @return table la metatable a appliquer
    local function metatableFor(frameType, template)
        local kind = type(frameType) == "string" and frameType or "Frame"
        local name = type(template) == "string" and template or ""
        if kind == "Button" or kind == "EditBox" or name:find("Button", 1, true) ~= nil then
            return Frame
        end
        return FRAME_WITHOUT_TEXT
    end
    stub.metatableFor = metatableFor

    _G.CreateFrame = function(frameType, name, parent, template)
        local f = setmetatable({ __name = name, __frameType = frameType }, metatableFor(frameType, template))
        if name then
            _G[name] = f
        end
        frames[#frames + 1] = f
        return f
    end
    _G.UIParent = setmetatable({}, Frame)
    _G.DEFAULT_CHAT_FRAME = { messages = {} }
    function _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        self.messages[#self.messages + 1] = msg
    end
    _G.UnitName = function()
        return "Testeur"
    end
    -- Langue du client : le vrai client renvoie "enUS", "frFR", "deDE"... Le
    -- stub repond enUS (anglais = langue officielle de l'addon) ; une spec peut
    -- remplacer _G.GetLocale pour simuler un client frFR.
    _G.GetLocale = function()
        return "enUS"
    end
    -- Horloge cliente : c'est CE couple (time, date) que la couche UI utilise
    -- pour publier la decision du joueur dans les SavedVariables (le kit de
    -- diagnostic la relit ensuite). Core/ n'y touche jamais.
    _G.time = function()
        return 1758500000
    end
    _G.date = function()
        return "2026-09-22 21:00:00"
    end
    _G.C_Timer = {
        -- Appeles avec un point (C_Timer.NewTicker(duree, callback)) : pas de self.
        NewTicker = function(interval, fn)
            local t = { interval = interval, callback = fn, cancelled = false }
            function t:Cancel()
                self.cancelled = true
            end
            tickers[#tickers + 1] = t
            return t
        end,
        After = function(delay, fn)
            local t = { delay = delay, callback = fn, cancelled = false }
            function t:Cancel()
                self.cancelled = true
            end
            tickers[#tickers + 1] = t
            return t
        end,
    }

    -- SON D'ASSIGNATION : PlaySoundFile est le SEUL appel audio de l'addon, et il
    -- vient de la couche de rendu (UI/), sous pcall. Le stub l'ENREGISTRE (chemin
    -- + canal) pour qu'une spec puisse verifier « un seul son, le bon fichier, une
    -- seule fois ». Une spec qui veut un client en echec le remplace elle-meme
    -- (_G.PlaySoundFile = function() error("...") end) ou le supprime
    -- (_G.PlaySoundFile = nil) : l'addon doit alors rester SILENCIEUX sans lever.
    -- Le stub de la lecture de raccourci (GetBindingKey ci-dessus) n'existe toujours
    -- pas ici : hors client, aucun raccourci n'est connu (cas par defaut teste).
    local sounds = {}
    _G.PlaySoundFile = function(path, channel)
        sounds[#sounds + 1] = { path = path, channel = channel }
        return true
    end

    stub.frames = frames
    stub.tickers = tickers
    stub.sounds = sounds
    -- Le Frame racine cree par GideonRaid.lua est le 1er de la liste.
    stub.mainFrame = function()
        return frames[1]
    end
    -- Simule N passages du ticker (une passe = un tick du module UI).
    stub.fireTickers = function(times)
        for _ = 1, times do
            for _, t in ipairs(tickers) do
                if not t.cancelled then
                    t.callback()
                end
            end
        end
    end
end

return stub
