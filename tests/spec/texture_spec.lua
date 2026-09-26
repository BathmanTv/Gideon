--[[--------------------------------------------------------------------------
    tests/spec/texture_spec.lua   (busted)

    TEXTURES DES TROIS BOUTONS D'IMAGE (demande du raid lead) : le panneau
    d'intermission affiche une CAPTURE des orbes a la place de tout texte, donc
    les trois fichiers `Texture/*.tga` sont du CONTENU DE JEU, pas des documents.

    Quatre familles de verifications, toutes HORS JEU :

      1. Core/Textures.lua (PUR) : table etat -> fichier/chemin/taille, jamais de
         nom invente, un etat inconnu ne dessine rien plutot que d'echouer ;
      2. les FICHIERS sur disque : les trois TGA existent, ne sont pas vides et
         sont de VRAIS TGA 32 bits NON compresses (en-tete relu octet par octet :
         type d'image, dimensions, profondeur, bits d'alpha) ;
      3. la COHERENCE avec la source : `Core/Textures.lua` declare les dimensions
         que le fichier porte reellement, le cote long vaut la boite annoncee et
         le RATIO de la capture d'origine est conserve (aucun orbe ecrase), et
         l'outil `tools/make_textures.py` porte le MEME mapping etat -> capture
         que la table pure (une inversion enverrait les joueurs a la mort) ;
      4. le PACKAGING : les trois entrees sont listees dans GideonRaid.toc (le
         client ne charge pas une texture non listee) et rien dans .pkgmeta ne
         les exclut du zip - `assets/`, lui, est exclu, et les textures ne
         doivent pas y etre rangees.

    Les fichiers sont binaries : ce spec lit les OCTETS (io.open "rb") et ne
    depend d'aucune bibliotheque d'image.
----------------------------------------------------------------------------]]
--
--
--

local wowenv = require("tests.support.wowenv")

--- Reconstruit un entier 16 bits petit-boutiste (TGA = little-endian).
local function u16(byte1, byte2)
    return byte1 + byte2 * 256
end

local function fileExists(path)
    local handle = io.open(path, "rb")
    if handle == nil then
        return false, 0, nil
    end
    local content = handle:read("*a")
    handle:close()
    return true, #content, content
end

local function readFile(path)
    local exists, _, content = fileExists(path)
    assert.is_true(exists, path .. " introuvable")
    return content
end

--- En-tete d'un TGA non compresse, relu octet par octet (specification TGA 2.0).
local function tgaHeader(content)
    assert.is_true(#content >= 18, "un TGA a au moins 18 octets d'en-tete")
    local bytes = {}
    for index = 1, 18 do
        bytes[index] = content:byte(index)
    end
    return {
        idLength = bytes[1],
        colorMapType = bytes[2],
        imageType = bytes[3],
        width = u16(bytes[13], bytes[14]),
        height = u16(bytes[15], bytes[16]),
        bitsPerPixel = bytes[17],
        descriptor = bytes[18],
    }
end

local function entriesContain(entries, expected)
    for index = 1, #entries do
        if entries[index] == expected then
            return true
        end
    end
    return false
end

--- Paires (etat, fichier source) du tableau SOURCES de tools/make_textures.py :
--- l'outil n'est pas executable dans la suite (il demande Pillow), mais son
--- mapping est une DONNEE qu'un test peut relire.
local function toolSources()
    local text = readFile("tools/make_textures.py")
    local out = {}
    for state, source in text:gmatch('%("([123]V[123]R)",%s*"([^"]+)"%)') do
        out[state] = source
    end
    return out, text
end

--- Entrees d' `ignore:` de .pkgmeta, normalisees (sans "- " ni slash final).
local function pkgmetaIgnores()
    local out = {}
    local inIgnore = false
    for line in readFile(".pkgmeta"):gmatch("[^\n]+") do
        if line:match("^ignore:%s*$") ~= nil then
            inIgnore = true
        elseif inIgnore then
            local entry = line:match("^%s+%-%s*(.-)%s*$")
            if entry == nil then
                break
            end
            out[#out + 1] = entry:gsub("^%./", ""):gsub("/+$", "")
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 1. Core/Textures.lua : table pure (chemins, tailles, etats)
-- ---------------------------------------------------------------------------

describe("Textures : table pure (chemins, tailles, etats)", function()
    local ns = wowenv.loadCore()
    local Textures, Intermission = ns.Textures, ns.Intermission

    it("couvre EXACTEMENT les trois etats canoniques du module d'intermission", function()
        local fromStates = {}
        for index = 1, #Intermission.STATES do
            fromStates[#fromStates + 1] = Intermission.STATES[index]
        end
        -- Deux listes ecrites separement (Textures.lua est charge AVANT
        -- Intermission.lua) : elles ne doivent jamais diverger.
        assert.are.same(fromStates, Textures.STATES)
        for index = 1, #Textures.STATES do
            local state = Textures.STATES[index]
            assert.is_string(Textures.fileName(state), state .. " n'a pas de fichier")
            assert.is_string(Textures.pathFor(state), state .. " n'a pas de chemin")
            assert.is_truthy(Textures.sizeFor(state) ~= nil, state .. " n'a pas de taille")
        end
    end)

    it("un etat inconnu ne dessine RIEN plutot que d'echouer", function()
        assert.is_nil(Textures.fileName("9V9R"))
        assert.is_nil(Textures.pathFor("9V9R"))
        assert.is_nil(Textures.fileName(nil))
        assert.is_nil(Textures.pathFor({}))
        local width, height = Textures.sizeFor("9V9R")
        assert.is_nil(width)
        assert.is_nil(height)
        local drawWidth, drawHeight = Textures.displaySize("9V9R", 160)
        assert.are.equal(0, drawWidth)
        assert.are.equal(0, drawHeight)
    end)

    it("les noms livres sont en minuscules, sans accent ni espace", function()
        for index = 1, #Textures.FILE_NAMES do
            local file = Textures.FILE_NAMES[index]
            assert.is_truthy(file:match("^[a-z0-9%.%-]+%.tga$") ~= nil, file .. " : nom non conforme")
            assert.are.equal(file:lower(), file, file)
        end
    end)

    it("le chemin client est le chemin COMPLET de l'addon, antislashs compris", function()
        -- Le client refuse un chemin relatif : la texture est cherchee dans le
        -- dossier de l'addon, tel que le .toc le declare.
        for index = 1, #Textures.STATES do
            local state = Textures.STATES[index]
            assert.are.equal("Interface\\AddOns\\GideonRaid\\Texture\\" .. Textures.fileName(state), Textures.pathFor(state))
        end
    end)

    it("dimensionne dans la boite annoncee en gardant le ratio", function()
        for index = 1, #Textures.STATES do
            local state = Textures.STATES[index]
            local width, height = Textures.sizeFor(state)
            local drawWidth, drawHeight = Textures.displaySize(state, 128)
            -- La boite 256 est celle des fichiers ; a l'ecran on reduit d'un facteur
            -- unique : le ratio est donc le MEME aux deux tailles.
            assert.is_true(width <= Textures.BOX and height <= Textures.BOX, state)
            assert.are.equal(Textures.BOX, math.max(width, height), state .. " : le cote long doit valoir la boite")
            assert.is_true(drawWidth <= 128 and drawHeight <= 128, state)
            assert.are.equal(128, math.max(drawWidth, drawHeight), state)
            assert.is_true(math.abs(width / height - drawWidth / drawHeight) < 0.02, state .. " : ratio non conserve")
        end
    end)

    it("mirroite les constantes de l'outil de conversion (mapping compris)", function()
        local sources, text = toolSources()
        -- Mapping etat -> capture du raid lead : c'est LUI qui protege du drame
        -- (une permutation enverrait les joueurs a la mort). Il vit a deux
        -- endroits qui doivent rester identiques.
        assert.are.equal("upload_20260924_222400_1.png", sources["3V1R"])
        assert.are.equal("upload_20260924_222400_2.png", sources["2V2R"])
        assert.are.equal("upload_20260924_222401_3.png", sources["1V3R"])
        -- La boite de l'outil et celle du module pur : meme valeur.
        assert.are.equal(Textures.BOX, tonumber(text:match("\nBOX%s*=%s*(%d+)")))
        -- ... et chaque etat declare bien le fichier que l'outil produit.
        assert.are.equal("3v1r.tga", Textures.fileName("3V1R"))
        assert.are.equal("2v2r.tga", Textures.fileName("2V2R"))
        assert.are.equal("1v3r.tga", Textures.fileName("1V3R"))
        -- Le rendu d'un etat suit le dossier annonce (pas d'assets/, pas de dossier
        -- en dur dans UI/).
        assert.are.equal(Textures.DIRECTORY, text:match('\nout_dir%s*=%s*"([^"]+)"') or Textures.DIRECTORY)
    end)
end)

-- ---------------------------------------------------------------------------
-- 2. Les fichiers sur disque : de VRAIS TGA 32 bits non compresses
-- ---------------------------------------------------------------------------

describe("Textures : les trois TGA livres sont valides", function()
    local ns = wowenv.loadCore()
    local Textures = ns.Textures

    it("existent sur disque, non vides, et sont listes dans le .toc", function()
        local entries = wowenv.tocEntries()
        for index = 1, #Textures.FILE_NAMES do
            local file = Textures.FILE_NAMES[index]
            local present, size = fileExists("Texture/" .. file)
            assert.is_true(present, "Texture/" .. file .. " est absent du depot")
            assert.is_true(size > 0, "Texture/" .. file .. " est vide")
            -- Sans entree au .toc, le client ne charge pas la texture et le bouton
            -- resterait VIDE en jeu.
            assert.is_true(entriesContain(entries, "Texture/" .. file), "Texture/" .. file .. " doit etre liste dans GideonRaid.toc")
        end
    end)

    it("portent un en-tete TGA non compresse 32 bits coherent avec sa taille", function()
        for index = 1, #Textures.FILE_NAMES do
            local file = Textures.FILE_NAMES[index]
            local content = readFile("Texture/" .. file)
            local header = tgaHeader(content)
            assert.are.equal(0, header.idLength, file .. " : pas de champ d'identification")
            assert.are.equal(0, header.colorMapType, file .. " : pas de palette")
            -- 2 = true-color NON compresse (10 = RLE, refuse : le client lit les
            -- deux, mais le raid lead a demande du non compresse).
            assert.are.equal(2, header.imageType, file .. " : doit etre un TGA non compresse")
            assert.are.equal(32, header.bitsPerPixel, file .. " : doit etre du 32 bits (alpha)")
            -- Bits d'alpha (0-3) = 8 : un chargeur strict lit ce champ.
            assert.are.equal(8, header.descriptor % 16, file .. " : 8 bits d'alpha attendus")
            -- Taille EXACTE d'un TGA non compresse : en-tete + donnees RGBA + le
            -- pied de page TGA 2.0 (26 octets, ecrit par Pillow).
            local expected = 18 + header.idLength + header.width * header.height * 4
            local tail = content:sub(-18, -1)
            assert.are.equal("TRUEVISION-XFILE", tail:sub(1, 16), file .. " : pied de page TGA 2.0 attendu")
            assert.are.equal(expected + 26, #content, file .. " : taille incoherente avec l'en-tete")
        end
    end)

    it("les dimensions de l'en-tete sont CELLES declarees par Core/Textures.lua", function()
        for index = 1, #Textures.STATES do
            local state = Textures.STATES[index]
            local file = Textures.fileName(state)
            local width, height = Textures.sizeFor(state)
            local header = tgaHeader(readFile("Texture/" .. file))
            assert.are.equal(width, header.width, file .. " : largeur")
            assert.are.equal(height, header.height, file .. " : hauteur")
            -- La capture d'origine n'est jamais etiree dans la boite : le cote long
            -- vaut EXACTEMENT la boite 256 px.
            assert.are.equal(Textures.BOX, math.max(header.width, header.height), file .. " : cote long")
        end
    end)

    it("le fond est TRANSPARENT : le premier pixel de la marge a un alpha nul", function()
        -- Garde-fou contre un export qui aurait perdu le canal alpha : un fond
        -- opaque dessinerait un carre plein dans le bouton.
        for index = 1, #Textures.FILE_NAMES do
            local file = Textures.FILE_NAMES[index]
            local content = readFile("Texture/" .. file)
            -- Premier pixel des donnees (TGA non compresse : B, G, R, A) : c'est un
            -- coin de l'image, donc du fond.
            local alpha = content:byte(18 + 4)
            assert.are.equal(0, alpha, file .. " : le fond doit etre transparent (alpha nul)")
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- 2b. L'illustration du PANNEAU DE PLACEMENT (hors etats canoniques)
-- ---------------------------------------------------------------------------

describe("Textures : l'illustration du panneau de placement", function()
    local ns = wowenv.loadCore()
    local Textures = ns.Textures

    it("est livree en TGA 32 bits non compresse, dans Texture/ et listee au .toc", function()
        -- Pendant `/gideon inter place`, le panneau n'affiche QUE cette illustration :
        -- elle sert de repere visuel (taille et emplacement de la fenetre). Le
        -- client retail ne charge pas de PNG, la livraison est donc convertie par
        -- tools/make_textures.py en TGA 32 bits NON compresse.
        local file = Textures.PLACEMENT_FILE
        local present, size = fileExists("Texture/" .. file)
        assert.is_true(present, "Texture/" .. file .. " est absent du depot")
        assert.is_true(size > 0, "Texture/" .. file .. " est vide")
        -- Sans entree au .toc, le client ne charge PAS la texture par chemin :
        -- l'illustration ne s'afficherait pas du tout en jeu.
        local entries = wowenv.tocEntries()
        assert.is_true(entriesContain(entries, "Texture/" .. file), "Texture/" .. file .. " doit etre liste dans GideonRaid.toc")
        local content = readFile("Texture/" .. file)
        local header = tgaHeader(content)
        assert.are.equal(0, header.idLength, file .. " : pas de champ d'identification")
        assert.are.equal(0, header.colorMapType, file .. " : pas de palette")
        assert.are.equal(2, header.imageType, file .. " : doit etre un TGA non compresse")
        assert.are.equal(32, header.bitsPerPixel, file .. " : doit etre du 32 bits (alpha)")
        assert.are.equal(8, header.descriptor % 16, file .. " : 8 bits d'alpha attendus")
        -- Taille EXACTE d'un TGA non compresse (en-tete + RGBA + pied de page 2.0).
        local expected = 18 + header.idLength + header.width * header.height * 4
        assert.are.equal(expected + 26, #content, file .. " : taille incoherente avec l'en-tete")
        -- Les dimensions de l'en-tete sont CELLES declarees par Core/Textures.lua,
        -- et la boite demandee par le raid lead est ~384 px, ratio conserve (le
        -- cote long vaut EXACTEMENT la boite : aucun etirement).
        local width, height = Textures.placementSize()
        assert.are.equal(width, header.width, file .. " : largeur declaree")
        assert.are.equal(height, header.height, file .. " : hauteur declaree")
        assert.are.equal(Textures.PLACEMENT_BOX, math.max(header.width, header.height), file .. " : cote long")
        assert.is_true(
            math.abs(Textures.PLACEMENT_BOX - 384) <= 8,
            file .. " : la boite demandee est ~384 px (recu " .. tostring(Textures.PLACEMENT_BOX) .. ")"
        )
        -- Le CANAL ALPHA est CONSERVE : le fichier est du 32 bits avec 8 bits
        -- d'alpha (un export en 24 bits l'aurait supprime, et le client lirait
        -- alors un TGA different), et la couche alpha est une VRAIE couche
        -- coherente : sur toute l'illustration livree elle est uniforme.
        -- NOTE : l'illustration livree pour cette version est OPAQUE (le PNG
        -- d'origine n'a pas de canal alpha : c'est un rectangle plein, ce qui
        -- donne exactement le repere « voici la taille et l'emplacement de la
        -- fenetre » demande). Une future livraison detouree garderait le meme
        -- chemin et la meme boite : ce test accepte les deux (uniformement
        -- opaque ou uniformement transparente), mais refuse un alpha perdu.
        assert.is_true(#content > 18, file .. " : fichier tronque")
        local samples = {}
        local pixels = header.width * header.height
        for index = 0, 8 do
            local offset = 18 + (math.floor((pixels - 1) * index / 8) * 4) + 3
            samples[#samples + 1] = content:byte(offset + 1)
        end
        local firstAlpha = samples[1]
        assert.is_true(firstAlpha ~= nil, file .. " : couche alpha illisible")
        for index = 1, #samples do
            assert.are.equal(firstAlpha, samples[index], file .. " : couche alpha incoherente")
        end
        -- Et rien ne vit dans assets/, exclu du paquet.
        assert.is_false(fileExists("assets/" .. file), "assets/ est exclu du paquet : " .. file)
    end)

    it("n'est PAS un etat de composition (le repere du placement reste a part)", function()
        -- Une confusion etat <-> illustration enverrait la mauvaise image sur un
        -- bouton de composition, donc la mauvaise decision de ping.
        assert.is_false(entriesContain(Textures.STATES, Textures.PLACEMENT_FILE))
        assert.is_false(entriesContain(Textures.FILE_NAMES, Textures.PLACEMENT_FILE))
        for index = 1, #Textures.STATES do
            local state = Textures.STATES[index]
            assert.are_not.equal(Textures.PLACEMENT_FILE, Textures.fileName(state))
            assert.are_not.equal(Textures.placementPath(), Textures.pathFor(state))
        end
        -- Le chemin client est complet (le client ne resout pas un chemin relatif)
        -- et il vise bien le dossier Texture/ de l'addon.
        local path = Textures.placementPath()
        assert.is_true(path:find("Interface\\AddOns\\GideonRaid\\Texture\\", 1, true) ~= nil, path)
        assert.is_true(path:find(Textures.PLACEMENT_FILE, 1, true) ~= nil, path)
    end)
end)

-- ---------------------------------------------------------------------------
-- 3. Packaging : rien n'exclut Texture/ du zip, et assets/ n'est PAS la place
-- ---------------------------------------------------------------------------

describe("Textures : packaging", function()
    local ns = wowenv.loadCore()
    local Textures = ns.Textures

    it("rien dans .pkgmeta n'exclut Texture/ du zip BigWigs", function()
        local ignores = pkgmetaIgnores()
        assert.is_true(#ignores >= 8, "bloc ignore: illisible dans .pkgmeta")
        local sawAssets = false
        for index = 1, #ignores do
            local entry = ignores[index]
            if entry == "assets" then
                sawAssets = true
            end
            assert.is_false(entry == "Texture" or entry:match("^Texture/") ~= nil, ".pkgmeta exclut le dossier des textures : " .. entry)
        end
        assert.is_true(sawAssets, "le bloc ignore: n'a pas ete lu correctement (assets/ doit y etre)")
    end)

    it("les textures ne vivent PAS dans assets/ (dossier exclu du paquet)", function()
        -- Le raid lead a livre des captures ; l'addon, lui, doit charger ses
        -- textures depuis Texture/ : un fichier range dans assets/ ne partirait
        -- jamais chez les joueurs.
        for index = 1, #Textures.FILE_NAMES do
            local present = fileExists("assets/" .. Textures.FILE_NAMES[index])
            assert.is_false(present, "assets/ est exclu du paquet : " .. Textures.FILE_NAMES[index])
        end
    end)

    it("le .toc declare les textures APRES les fichiers lua (le client les charge)", function()
        local entries = wowenv.tocEntries()
        local firstTexture, lastLua = nil, nil
        for index = 1, #entries do
            local entry = entries[index]
            if entry:match("^Texture/") ~= nil and firstTexture == nil then
                firstTexture = index
            end
            if entry:match("%.lua$") ~= nil then
                lastLua = index
            end
        end
        assert.is_truthy(firstTexture ~= nil, "aucune texture listee dans le .toc")
        assert.is_truthy(lastLua ~= nil, "aucun fichier lua listee dans le .toc")
        assert.is_true(firstTexture > lastLua, "les textures se listent apres le code")
    end)
end)
