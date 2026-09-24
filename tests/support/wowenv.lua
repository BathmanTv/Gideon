--[[--------------------------------------------------------------------------
    tests/support/wowenv.lua
    Charge un fichier d'addon comme le ferait le client WoW, hors jeu.
    Le client appelle chaque chunk avec (addonName, addonTable) :
    on reproduit exactement cette signature pour pouvoir tester la vraie
    logique, sans mock de l'API de combat.
----------------------------------------------------------------------------]]
local wowenv = {}

local ROOT = ""
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
    wowenv.load("Core/Locale.lua", ns)
    -- Core/Sound.lua vient JUSTE APRES Locale.lua : il porte la table pure
    -- « etat canonique -> fichier de son », la garde « un seul son par
    -- assignation » et les resolveurs BORNES de la preference /gr sound.
    -- Core/Config.lua le lit, il doit donc etre charge avant lui.
    wowenv.load("Core/Sound.lua", ns)
    -- Core/BossFilter.lua vient egalement AVANT Config.lua : il porte la
    -- allow-list d'ids d'encounter (critere PRINCIPAL, /gr boss <id>), celle des
    -- noms (SECONDARY, dependante de la langue) et la DECISION pure « ce combat
    -- est-il le boss cible ? » (liste vide = aucune ouverture automatique).
    wowenv.load("Core/BossFilter.lua", ns)
    -- Core/Diag.lua vient juste APRES BossFilter.lua (meme ordre que le .toc) : il ne
    -- depend que de Locale et Sound, deja charges, et il porte le RAPPORT de
    -- `/gr diag` (les 4 fichiers de son + la cible effective + l'idlog + le ping).
    -- Il est PUR : aucun appel client, c'est UI/Panel.lua qui lui injecte les CVars
    -- et les reponses de PlaySoundFile.
    wowenv.load("Core/Diag.lua", ns)
    wowenv.load("Core/Config.lua", ns)
    wowenv.load("Core/Pairing.lua", ns)
    wowenv.load("Core/Intermission.lua", ns)
    -- Core/Simulation.lua vient APRES Intermission.lua (il reutilise ses etats,
    -- ses libelles de ping et ses candidats de raccourci) et AVANT les UI/.
    wowenv.load("Core/Simulation.lua", ns)
    -- Core/Textures.lua vient APRES Simulation.lua et AVANT Layout.lua : il porte
    -- la table pure « etat canonique -> texture TGA » des trois boutons d'image du
    -- panneau d'intermission, et la taille REELLE de chaque fichier (Core/ ne peut
    -- pas ouvrir un fichier : la taille est une DONNEE, verifiee sur disque par
    -- tests/spec/texture_spec.lua).
    wowenv.load("Core/Textures.lua", ns)
    -- Core/Layout.lua vient APRES Simulation.lua et Textures.lua : il mesure les
    -- libelles de Locale, la convention d'Intermission et les images de Textures
    -- pour construire la DISPOSITION des panneaux (listes ordonnees de blocs
    -- ancres les uns sous les autres).
    wowenv.load("Core/Layout.lua", ns)
    return ns
end

--- Liste TOUTES les entrees du .toc (fichiers .lua ET fichiers de son), dans
--- l'ordre de chargement du client. Un son NON liste dans le .toc n'est pas
--- charge par le client : c'est justement ce que verifie sound_spec.lua.
function wowenv.tocEntries(tocPath)
    local path = tocPath or "GideonRaid.toc"
    local out = {}
    for line in io.lines(ROOT .. path) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not trimmed:match("^#") then
            out[#out + 1] = trimmed:gsub("\\", "/")
        end
    end
    return out
end

--- Liste les fichiers .lua du .toc, dans l'ordre de chargement du client.
--- Garantit que lire le .toc et charger l'addon donnent le meme resultat.
--- Les sons (Sound/*.ogg) sont listes dans le .toc pour que le CLIENT les charge,
--- mais lua ne les execute pas : ils sont donc filtres ici (voir tocEntries pour
--- la liste complete).
function wowenv.tocFiles(tocPath)
    local out = {}
    local entries = wowenv.tocEntries(tocPath)
    for index = 1, #entries do
        local rel = entries[index]
        if rel:match("%.lua$") ~= nil then
            out[#out + 1] = rel
        end
    end
    return out
end

--- Charge TOUS les fichiers lua listes dans le .toc, dans l'ordre du .toc.
--- C'est ce chargement qui prouve qu'un fichier oublie/renomme fait echouer la CI.
function wowenv.loadAddon(tocPath)
    local ns = wowenv.newNamespace()
    for _, rel in ipairs(wowenv.tocFiles(tocPath)) do
        wowenv.load(rel, ns)
    end
    return ns
end

return wowenv
