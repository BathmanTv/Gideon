--[[--------------------------------------------------------------------------
    tests/support/wowapi_stub.lua
    Stub minimal de l'API WoW, suffisant pour executer la couche rendu hors jeu
    (aucun acces aux APIs de combat, aucun besoin de harnais lourd type wowless).
    Volontairement minuscule : si un fichier a besoin d'autre chose, c'est le
    signe qu'il touche a l'API de combat -> il doit etre refactore.
----------------------------------------------------------------------------]]
local stub = {}

function stub.install()
    local frames = {}

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
    function Frame:Fire(event, ...)
        local fn = self.__scripts and self.__scripts.OnEvent
        if fn then
            fn(self, event, ...)
        end
    end
    function Frame:SetSize() end
    function Frame:SetPoint() end
    function Frame:SetMovable() end
    function Frame:EnableMouse() end
    function Frame:RegisterForDrag() end
    function Frame:SetBackdrop() end
    function Frame:CreateFontString()
        local fs = {}
        function fs:SetPoint() end
        function fs:SetText(t)
            fs.__text = t
        end
        function fs:GetText()
            return fs.__text
        end
        function fs:SetJustifyH() end
        function fs:SetJustifyV() end
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

    _G.createFrame = function(_, name)
        local f = setmetatable({ __name = name }, Frame)
        if name then
            _G[name] = f
        end
        frames[#frames + 1] = f
        return f
    end
    _G.UIParent = setmetatable({}, Frame)
    _G.CreateFrame = function(_, name)
        local f = setmetatable({ __name = name }, Frame)
        if name then
            _G[name] = f
        end
        frames[#frames + 1] = f
        return f
    end
    _G.DEFAULT_CHAT_FRAME = { messages = {} }
    function _G.DEFAULT_CHAT_FRAME:AddMessage(msg)
        self.messages[#self.messages + 1] = msg
    end
    _G.UnitName = function()
        return "Testeur"
    end

    stub.frames = frames
    -- Le Frame racine cree par GideonRaid.lua est le 1er de la liste.
    stub.mainFrame = function()
        return frames[1]
    end
end

return stub
