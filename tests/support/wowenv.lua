--[[--------------------------------------------------------------------------
    tests/support/wowenv.lua
    Charge un fichier d'addon comme le ferait le client WoW, hors jeu.
    Le client appelle chaque chunk avec (addonName, addonTable) :
    on reproduit exactement cette signature pour pouvoir tester la vraie
    logique, sans mock de l'API de combat.
----------------------------------------------------------------------------]]
local wowenv = {}

local ROOT = "GideonRaid/"
local ADDON = "GideonRaid"

--- Cree un namespace vide (equivalent de la table passee en 2e argument).
function wowenv.newNamespace()
    return {}
end

--- Charge un fichier de l'addon et l'execute avec (addonName, ns).
--- @param relPath string chemin relatif a GideonRaid/, sans prefixe
--- @param ns table le namespace
function wowenv.load(relPath, ns)
    local chunk, err = loadfile(ROOT .. relPath)
    assert(chunk, "chargement impossible de " .. relPath .. " : " .. tostring(err))
    local ok, runErr = pcall(chunk, ADDON, ns)
    assert(ok, "erreur d'execution dans " .. relPath .. " : " .. tostring(runErr))
    return ns
end

--- Charge la chaine standard de l'addon (meme ordre que le .toc).
function wowenv.loadCore()
    local ns = wowenv.newNamespace()
    wowenv.load("Core/Config.lua", ns)
    wowenv.load("Core/Pairing.lua", ns)
    return ns
end

return wowenv
