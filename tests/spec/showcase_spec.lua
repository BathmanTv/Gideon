--[[--------------------------------------------------------------------------
    tests/spec/showcase_spec.lua   (busted)
    VITRINE DE STYLE (UI/Showcase.lua) : la surface ou le raid lead VOIT, en jeu,
    tout ce que le design sait faire - au lieu de juger sur une planche HTML hors
    du jeu.

    Familles de tests :
      1. le PLAN est complet (chaque section produit au moins un bloc), sans
         violation, sans identifiant en double ;
      2. les SEPT styles de cadre candidats existent, sont dessines (bordure, fond,
         ombre/cadre interne selon le style) et sont des DONNEES : ajouter un style
         ne demande aucune ligne de rendu en plus ;
      3. la PALETTE : les 8 constantes GIDEON et les 6 roles du panneau, chacun avec
         son code hexadecimal ecrit en clair ;
      4. l'allow-list de texte de la vitrine (regle structurelle de Layout) ;
      5. le style CHOISI est persiste, une valeur inconnue est REFUSEE, et Gideon
         reste un CANDIDAT (le style livre reste le defaut) ;
      6. les ANIMATIONS existent, sont BORNES et se coupent (et le panneau de combat
         n'en a AUCUNE) ;
      7. le bouton OK du PLACEMENT : present pendant le placement, absent en combat,
         clic = position sauvee + panneau ferme + AUCUN son.
----------------------------------------------------------------------------]]
--
local wowenv = require("tests.support.wowenv")
local stub = require("tests.support.wowapi_stub")

--- Recherche LITTERALE (les motifs Lua mangent « - » et « # »).
local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

--- Tous les blocs d'un plan, LIGNES INCLUSES (un « row » porte des items).
local function everyBlock(layout)
    local out = {}
    for index = 1, #layout.blocks do
        local block = layout.blocks[index]
        out[#out + 1] = block
        if block.kind == "row" and block.items ~= nil then
            for item = 1, #block.items do
                out[#out + 1] = block.items[item]
            end
        end
    end
    return out
end

local function textBlock(layout, id)
    for _, block in ipairs(everyBlock(layout)) do
        if block.id == id then
            return block
        end
    end
    return nil
end

-- ===========================================================================
describe("Vitrine : le plan (Core/Layout, pur)", function()
    local ns
    local L
    local T

    before_each(function()
        ns = wowenv.loadCore()
        L = ns.Layout
        T = ns.Textures
    end)

    it("expose les SEPT styles candidats, dans un ordre STABLE", function()
        assert.are.same({ "1", "2", "3", "4", "5", "6", "gideon" }, L.STYLE_ORDER)
        for index = 1, #L.STYLE_ORDER do
            local name = L.STYLE_ORDER[index]
            assert.is_not_nil(L.BUTTON_STYLES[name], name .. " doit exister")
            assert.is_true(L.isCandidateStyle(name))
        end
        -- Le style LIVRE n'est PAS dans les sept : on ne propose pas au raid lead
        -- de « choisir » ce qui est deja en place. Il reste PREVISUALISABLE a la
        -- demande (`/gr sim style card`), ce qui sert a comparer Gideon a l'existant.
        assert.are.equal("card", L.SHIPPED_STYLE)
        assert.is_true(L.isCandidateStyle(L.SHIPPED_STYLE))
        for index = 1, #L.STYLE_ORDER do
            assert.are_not.equal(L.SHIPPED_STYLE, L.STYLE_ORDER[index])
        end
        assert.is_false(L.isCandidateStyle("nope"))
        assert.is_false(L.isCandidateStyle("8"))
    end)

    it("chaque style est une DONNEE complete (bordure, fond, padding, etats)", function()
        for index = 1, #L.STYLE_ORDER do
            local name = L.STYLE_ORDER[index]
            local style = L.style(name)
            assert.is_string(style.edgeFile, name .. " : bordure (edgeFile) manquante")
            assert.is_true(tonumber(style.edgeSize) > 0, name .. " : edgeSize invalide")
            assert.is_table(style.background, name .. " : fond (background) manquant")
            assert.is_table(style.border, name .. " : bordure au repos manquante")
            -- LE RETOUR VISUEL : survol et appui sont des couleurs, pas du code.
            assert.is_table(style.borderHover, name .. " : bordure au survol manquante")
            assert.is_table(style.borderPressed, name .. " : bordure a l'appui manquante")
            assert.is_true(L.cardPadding(name) >= 0, name .. " : padding invalide")
        end
    end)

    it("le style GIDEON : palette exacte, bordure or, survol cyan, appui dore clair", function()
        local style = L.style("gideon")
        -- BORDURE 2 px (au repos) : GIDEON_GOLD.
        assert.are.same(L.colorOf(L.GIDEON_GOLD), style.border)
        -- SURVOL : cyan + halo (le halo est CUIT dans la texture d'encadrement,
        -- donc la bordure entiere prend la teinte cyan).
        assert.are.same(L.colorOf(L.GIDEON_CYAN), style.borderHover)
        -- APPUI : l'eclat dore.
        assert.are.same(L.colorOf(L.GIDEON_GOLD_HI), style.borderPressed)
        -- FOND : le verre bleu nuit.
        assert.are.equal(L.hexOf(L.GIDEON_PANEL), L.hexOfColor(style.background))
        -- LA TEXTURE D'ENCOURAGEMENT EST GENREE PAR tools/make_gideon_frame.py et
        -- declaree dans Core/Textures.lua (jamais ecrite a la main dans Core/Layout).
        assert.are.equal(T.gideonFramePath(), style.edgeFile)
    end)

    it("les SIX autres styles se distinguent les uns des autres", function()
        -- Deux styles identiques n'auraient aucun interet : le raid lead doit
        -- pouvoir les DEPARTER a l'oeil (bordure ou fond differents).
        local seen = {}
        for index = 1, #L.STYLE_ORDER do
            local name = L.STYLE_ORDER[index]
            local style = L.style(name)
            local key = L.hexOfColor(style.border) .. "/" .. L.hexOfColor(style.background) .. "/" .. style.edgeFile
            assert.is_nil(seen[key], name .. " est indiscernable de " .. tostring(seen[key]))
            seen[key] = name
        end
    end)

    it("un style peut porter un SECOND cadre (le « double cadre ») sans code en plus", function()
        local double = L.style("6")
        assert.is_true(tonumber(double.innerEdgeSize) > 0, "le style 6 doit declarer son cadre interne")
        assert.is_table(double.innerBorder, "le style 6 doit declarer la couleur de son cadre interne")
        assert.is_true(tonumber(double.innerInset) >= 0)
        -- Les autres styles n'en ont pas : la donnee est ABSENTE, pas a zero.
        for index = 1, #L.STYLE_ORDER do
            local name = L.STYLE_ORDER[index]
            if name ~= "6" then
                assert.is_nil(L.style(name).innerEdgeSize, name .. " ne doit pas avoir de cadre interne")
            end
        end
    end)

    it("resout les alias et REFUSE une valeur inconnue", function()
        assert.are.equal("1", L.resolveStyle("1"))
        assert.are.equal("6", L.resolveStyle("6"))
        assert.are.equal("gideon", L.resolveStyle("gideon"))
        assert.are.equal("gideon", L.resolveStyle("GIDEON"))
        assert.are.equal("gideon", L.resolveStyle("  gideon  "))
        -- « shipped » ramene le style LIVRE (la valeur persistee est toujours un nom
        -- canonique : jamais le mot « shipped »).
        assert.are.equal(L.SHIPPED_STYLE, L.resolveStyle("shipped"))
        assert.are.equal(L.SHIPPED_STYLE, L.resolveStyle("card"))
        -- TOUT LE RESTE EST REFUSE (aucun repli silencieux).
        for _, bad in ipairs({ "0", "7", "99", "nope", "gideonn", "-1", "" }) do
            assert.is_nil(L.resolveStyle(bad), tostring(bad) .. " doit etre refuse")
        end
        assert.is_nil(L.resolveStyle(nil))
        assert.is_nil(L.resolveStyle(7))
    end)

    it("la vitrine a SEPT sections, chacune avec du contenu", function()
        local layout = L.showcasePanel()
        assert.are.equal(L.PANEL.SHOWCASE, layout.panel)
        assert.are.equal("", table.concat(L.violations(layout), " | "))
        -- 1. les compositions en direct.
        assert.is_not_nil(textBlock(layout, "liveHeader"))
        assert.are.equal(3, #layout.blocks[3].items, "les 3 compositions doivent etre dans une ligne")
        -- 2. la typographie.
        assert.is_not_nil(textBlock(layout, "typoHeader"))
        assert.is_not_nil(textBlock(layout, "typoBoss"))
        -- 3. les trois etats d'un encart.
        assert.is_not_nil(textBlock(layout, "statesHeader"))
        assert.is_not_nil(textBlock(layout, "stateCap3"))
        -- 4. la palette (deux fois : celle du panneau, puis celle de GIDEON).
        assert.is_not_nil(textBlock(layout, "paletteHeader"))
        assert.is_not_nil(textBlock(layout, "gideonPaletteHeader"))
        -- 5. les styles de cadre.
        assert.is_not_nil(textBlock(layout, "stylesHeader"))
        assert.is_not_nil(textBlock(layout, "styleCap1"))
        assert.is_not_nil(textBlock(layout, "styleCap7"))
        -- 6. les animations.
        assert.is_not_nil(textBlock(layout, "animHeader"))
        assert.is_not_nil(textBlock(layout, "animLine"))
        -- Le contenu est PLUS GRAND que la fenetre : il y a de quoi faire defiler.
        assert.is_true(layout.height > L.SHOWCASE_WINDOW_HEIGHT, "la vitrine doit etre scrollable")
    end)

    it("le bandeau SIMULATION est une surface FIXE (il ne defile jamais)", function()
        -- Le raid lead ne doit JAMAIS confondre la vitrine avec un combat : le
        -- bandeau « SIMULATION - NO BOSS, NO RAID » vit dans un plan A PART, dessine
        -- au-dessus de la zone defilante (UI/Showcase.lua l'applique hors du
        -- ScrollFrame).
        local strip = L.showcaseBannerPanel()
        assert.are.equal(L.PANEL.SHOWCASE, strip.panel)
        assert.are.equal("", table.concat(L.violations(strip), " | "))
        assert.are.equal(3, #strip.blocks)
        for index = 1, #strip.blocks do
            assert.are.equal("text", strip.blocks[index].kind)
        end
        assert.are.equal(ns.Locale.t("sim.banner"), strip.blocks[1].text)
        assert.are.equal(ns.Locale.t("ui.showcaseTitle"), strip.blocks[2].text)
        -- ... et le contenu defilant ne le repete pas (un seul endroit par texte).
        local content = L.showcasePanel()
        assert.is_nil(textBlock(content, "showcaseBanner"))
    end)

    it("AUCUN identifiant en double dans tout l'ecran", function()
        -- Le calque de rendu range ses cadres PAR IDENTIFIANT : deux blocs qui
        -- partagent un id se recouvriraient sans qu'aucun test ne le voie.
        local seen = {}
        for _, layout in ipairs({ L.showcaseBannerPanel(), L.showcasePanel() }) do
            for _, block in ipairs(everyBlock(layout)) do
                assert.is_nil(seen[block.id], "identifiant en double : " .. tostring(block.id))
                seen[block.id] = true
            end
        end
    end)

    it("les 7 styles sont DESSINES dans la vitrine, chacun dans son style", function()
        local layout = L.showcasePanel()
        local styleCards = {}
        for _, block in ipairs(everyBlock(layout)) do
            if block.kind == "image" and type(block.id) == "string" and block.id:match("^styleCard%d+$") ~= nil then
                styleCards[block.id] = block
            end
        end
        for index = 1, #L.STYLE_ORDER do
            local block = styleCards["styleCard" .. index]
            assert.is_not_nil(block, "styleCard" .. index .. " doit etre dessine")
            -- Chaque encart porte SON style : c'est la donnee qui decide du rendu.
            assert.are.equal(L.STYLE_ORDER[index], block.style)
            -- ... et le meme echantillon pour tous (2 verts + 2 rouges), pour que
            -- seule la CADRE change d'un encart a l'autre.
            assert.are.equal(L.SHOWCASE_SAMPLE_STATE, block.state)
            -- La legende donne le NUMERO et les deux codes hexa : le raid lead dicte
            -- « style 3 » sans ambiguite.
            local caption = textBlock(layout, "styleCap" .. index)
            assert.is_not_nil(caption)
            assert.is_true(contains(caption.text, L.hexOfColor(L.style(L.STYLE_ORDER[index]).border)))
            if index == 7 then
                assert.is_true(contains(caption.text, "GIDEON"))
            end
        end
        -- Le style PREVIEW est celui des compositions (selectionne en direct).
        local preview = L.showcasePanel({ style = "gideon" })
        for _, block in ipairs(everyBlock(preview)) do
            if type(block.id) == "string" and block.id:match("^liveChoice%d+$") ~= nil then
                assert.are.equal("gideon", block.style)
            end
        end
    end)

    it("la palette ecrit le CODE HEXADECIMAL en clair, pour les 8 constantes GIDEON", function()
        local layout = L.showcasePanel()
        local expected = {
            { "NIGHT", L.GIDEON_NIGHT, "#04050F" },
            { "PANEL", L.GIDEON_PANEL, "#0A0C22" },
            { "ROYAL", L.GIDEON_ROYAL, "#08218E" },
            { "CYAN", L.GIDEON_CYAN, "#7ADBFA" },
            { "GOLD", L.GIDEON_GOLD, "#D19A45" },
            { "GOLD_HI", L.GIDEON_GOLD_HI, "#FFE982" },
            { "CHROME", L.GIDEON_CHROME, "#FFFFFF" },
            { "MUTED", L.GIDEON_MUTED, "#A9B4C7" },
        }
        assert.are.equal(#expected, #L.GIDEON_PALETTE)
        for index = 1, #expected do
            local key, value, hex = expected[index][1], expected[index][2], expected[index][3]
            assert.are.equal(key, L.GIDEON_PALETTE[index].key)
            assert.are.equal(value, L.GIDEON_PALETTE[index].value)
            assert.are.equal(hex, L.hexOf(value))
            -- La pastille est DESSINEE avec la couleur exacte...
            local chip = textBlock(layout, "gideon" .. index)
            assert.is_not_nil(chip)
            assert.are.equal(hex, L.hexOfColor(chip.color))
            -- ... et le libelle ECRIT le code : « dicte-moi une valeur » doit etre
            -- possible sans ouvrir le code.
            local label = textBlock(layout, "gideonLabel" .. index)
            assert.is_not_nil(label)
            assert.is_true(contains(label.text, hex), "le libelle doit contenir " .. hex)
            assert.is_true(contains(label.text, key), "le libelle doit nommer la constante " .. key)
        end
    end)

    it("la palette du panneau couvre les 6 roles demandes (dont l'alerte)", function()
        local layout = L.showcasePanel()
        assert.are.equal(6, #L.PALETTE)
        local roles = {}
        for index = 1, #L.PALETTE do
            roles[L.PALETTE[index].key] = true
            assert.is_not_nil(textBlock(layout, "swatch" .. index))
            assert.is_not_nil(textBlock(layout, "swatchLabel" .. index))
        end
        for _, key in ipairs({ "background", "border", "accent", "textMain", "textSecondary", "alert" }) do
            assert.is_true(roles[key] == true, "role manquant : " .. key)
        end
    end)

    it("une pastille de couleur n'existe QUE dans la vitrine", function()
        -- Regle structurelle : le panneau de combat ne peut pas peindre une pastille,
        -- meme si un appelant en ajoutait une par erreur.
        local foreign = L.build({
            panel = L.PANEL.INTERMISSION,
            blocks = { { id = "chip", kind = "swatch", align = "center", color = L.colorOf(L.GIDEON_GOLD) } },
        })
        local problems = table.concat(L.violations(foreign), " | ")
        assert.is_true(contains(problems, "colour chip"), problems)
    end)

    it("la TYPOGRAPHIE montre les tailles REELLES, et les deux variantes du mot", function()
        local layout = L.showcasePanel()
        -- Le mot de 64 px.
        local boss = textBlock(layout, "typoBoss")
        assert.are.equal(L.WORD_FONT_FILE, boss.fontFile)
        assert.are.equal(L.WORD_SIZE_BIG, boss.fontSize)
        assert.are.equal(L.WORD_SIZE_BIG, 64)
        -- Les mots de 44 px, dans les DEUX variantes : le vert livre et le cyan
        -- Gideon (le raid lead tranche).
        local green = textBlock(layout, "typoPingGreen")
        local cyan = textBlock(layout, "typoPingCyan")
        assert.are.equal(44, green.fontSize)
        assert.are.equal(44, cyan.fontSize)
        assert.are.equal(L.WORD_FONT_FILE, cyan.fontFile)
        assert.are.same(L.THEME.GREEN, green.color)
        assert.are.equal(L.hexOf(L.GIDEON_CYAN), L.hexOfColor(cyan.color))
        -- Les tailles SECONDAIRES : un echantillon de chaque style de texte du panneau.
        assert.is_not_nil(textBlock(layout, "typoBanner"))
        assert.is_not_nil(textBlock(layout, "typoLabel"))
        assert.is_not_nil(textBlock(layout, "typoSingle"))
        -- Chaque echantillon est suivi de SA taille, ecrite en toutes lettres.
        for _, id in ipairs({ "typoBoss", "typoPingGreen", "typoBanner", "typoLabel", "typoSingle" }) do
            local caption = textBlock(layout, id .. "Size")
            assert.is_not_nil(caption, id .. " doit afficher sa taille")
            assert.is_true(contains(caption.text, "px"), caption.text)
        end
    end)

    it("les trois ETATS sont montres cote a cote, cadres et legendes", function()
        local layout = L.showcasePanel()
        local wanted = { L.CARD_STATE.REST, L.CARD_STATE.HOVER, L.CARD_STATE.PRESSED }
        for index = 1, 3 do
            local card = textBlock(layout, "stateCard" .. index)
            assert.is_not_nil(card)
            -- L'etat est FORCE par le plan : les trois se voient en meme temps.
            assert.are.equal(wanted[index], card.cardState)
            assert.are.equal(L.INTERMISSION_CHOICE_ORDER[index], card.state)
            -- La legende dit exactement quoi faire pour verifier le retour visuel.
            assert.is_not_nil(textBlock(layout, "stateCap" .. index))
        end
    end)

    it("l'allow-list de texte de la vitrine est RESPECTEE et FERMEE", function()
        -- Chaque plan de la vitrine ne contient que des libelles declares...
        for _, layout in ipairs({ L.showcaseBannerPanel(), L.showcasePanel() }) do
            for _, block in ipairs(everyBlock(layout)) do
                if block.kind == "text" then
                    assert.is_true(L.panelTextIds(L.PANEL.SHOWCASE)[block.id] == true, "libelle hors allow-list : " .. tostring(block.id))
                end
            end
        end
        -- ... et l'allow-list ne laisse rien passer d'autre : un titre etranger est
        -- REFUSE (c'est ce qui protege le panneau de combat).
        local foreign = L.build({
            panel = L.PANEL.SHOWCASE,
            blocks = { { id = "title", kind = "text", align = "center", text = "HELLO" } },
        })
        local problems = table.concat(L.violations(foreign), " | ")
        assert.is_true(contains(problems, "not allowed"), problems)
    end)

    it("les ANIMATIONS sont bornees, et coupees par defaut seulement sur demande", function()
        -- Fondu d'apparition.
        assert.are.equal(0, L.fadeAlpha(0))
        assert.are.equal(1, L.fadeAlpha(L.ANIMATION.FADE_SECONDS))
        assert.are.equal(1, L.fadeAlpha(999))
        assert.is_true(L.fadeAlpha(L.ANIMATION.FADE_SECONDS / 2) > 0)
        assert.is_true(L.fadeAlpha(-5) >= 0)
        -- Pulsation : BORNEE entre PULSE_MIN et PULSE_MAX, jamais hors des clous
        -- (une bordure qui disparait ou qui deborde serait un bug a l'ecran).
        for step = 0, 200 do
            local alpha = L.pulseAlpha(step * 0.05)
            assert.is_true(alpha >= L.ANIMATION.PULSE_MIN, "pulsation trop faible : " .. alpha)
            assert.is_true(alpha <= L.ANIMATION.PULSE_MAX, "pulsation trop forte : " .. alpha)
        end
        assert.is_true(L.ANIMATION.PULSE_MIN > 0 and L.ANIMATION.PULSE_MAX <= 1)
        -- Le drapeau : seul un faux EXPLICITE les coupe (defaut = on, pour que le
        -- raid lead les voie sans rien regler).
        assert.is_true(L.animationsEnabled(nil))
        assert.is_true(L.animationsEnabled(true))
        assert.is_true(L.animationsEnabled("false"))
        assert.is_false(L.animationsEnabled(false))
        -- ... et le mot ecrit en jeu suit la meme regle.
        assert.are.equal(ns.Locale.t("ui.wordEnabled"), L.settingWord(true))
        assert.are.equal(ns.Locale.t("ui.wordDisabled"), L.settingWord(false))
    end)

    it("la ligne des animations dit TOUJOURS dans quel etat elles sont", function()
        local on = L.showcasePanel({ animations = true })
        local off = L.showcasePanel({ animations = false })
        local onLine = textBlock(on, "animLine")
        local offLine = textBlock(off, "animLine")
        assert.is_true(contains(onLine.text, ns.Locale.t("ui.wordEnabled")), onLine.text)
        assert.is_true(contains(offLine.text, ns.Locale.t("ui.wordDisabled")), offLine.text)
        assert.is_true(contains(onLine.text, "/gr sim anim"), "la commande doit etre rappelee")
    end)
end)

-- ===========================================================================
describe("Vitrine : la configuration du raid lead", function()
    local ns
    local C
    local L

    before_each(function()
        ns = wowenv.loadCore()
        C = ns.Config
        L = ns.Layout
    end)

    it("la liste des styles est le MIROIR EXACT de Core/Layout", function()
        -- Core/Config.lua est charge AVANT Core/Layout.lua (il le faut : Layout
        -- mesure les libelles de Config), donc la liste est un miroir. Ce test est
        -- ce qui empeche le miroir de mentir : un style ajoute dans Layout sans etre
        -- ajoute ici est un style INUTILISABLE - il echoue ici au lieu de disparaitre
        -- en silence.
        local names = {}
        for name in pairs(L.BUTTON_STYLES) do
            names[#names + 1] = name
        end
        table.sort(names)
        local mirror = {}
        for index = 1, #C.STYLE_NAMES do
            mirror[#mirror + 1] = C.STYLE_NAMES[index]
        end
        table.sort(mirror)
        assert.are.same(names, mirror)
        assert.are.equal(L.SHIPPED_STYLE, C.DEFAULT_STYLE)
    end)

    it("le style par defaut est le style LIVRE, et une valeur inconnue y retombe", function()
        assert.are.equal("card", C.resolveStyleName(nil))
        assert.are.equal("card", C.resolveStyleName(""))
        assert.are.equal("card", C.resolveStyleName("nope"))
        assert.are.equal("card", C.resolveStyleName(7))
        assert.are.equal("card", C.resolveStyleName({}))
        -- « shipped » n'est PAS un nom canonique : c'est un alias de commande,
        -- resolu par Core/Layout.resolveStyle AVANT d'arriver ici.
        assert.are.equal("card", C.resolveStyleName("shipped"))
        assert.are.equal("1", C.resolveStyleName("1"))
        assert.are.equal("gideon", C.resolveStyleName("gideon"))
    end)

    it("la sauvegarde porte le style, l'apercu et les animations", function()
        local db = C.ensureDB({})
        assert.are.equal("card", db.intermission.style)
        assert.are.equal("card", db.intermission.showcaseStyle)
        assert.is_true(db.intermission.showcaseAnimations)
        assert.is_table(db.showcasePosition)
        -- Un style ABSURDE dans la sauvegarde ne casse rien : on retombe sur le livre.
        local broken = C.ensureDB({ intermission = { style = "hacker" } })
        assert.are.equal("card", C.resolveIntermission(broken.intermission).style)
        -- Un style choisi EST respecte.
        local chosen = C.ensureDB({ intermission = { style = "gideon", showcaseAnimations = false } })
        assert.are.equal("gideon", C.resolveIntermission(chosen.intermission).style)
        assert.is_false(C.resolveIntermission(chosen.intermission).showcaseAnimations)
        -- Les animations : seul un faux EXPLICITE les coupe (meme regle que Layout).
        for _, raw in ipairs({ nil, true, "false", 0, "" }) do
            assert.is_true(C.resolveIntermission({ showcaseAnimations = raw }).showcaseAnimations)
        end
        assert.is_false(C.resolveIntermission({ showcaseAnimations = false }).showcaseAnimations)
    end)

    it("la texture GIDEON est declaree ET presente sur le disque, en puissance de 2", function()
        local width, height = ns.Textures.gideonFrameSize()
        assert.are.equal(width, height)
        -- Puissance de 2 (exigence explicite) : la 9 tranches du client n'accepte pas
        -- n'importe quelle dimension.
        local isPowerOfTwo = false
        for exponent = 1, 12 do
            if 2 ^ exponent == width then
                isPowerOfTwo = true
            end
        end
        assert.is_true(isPowerOfTwo, "la texture d'encadrement doit etre en puissance de 2 : " .. width)
        assert.is_true(width >= 32 and width <= 64, "taille attendue : 32 ou 64 px")
        -- Le chemin EN JEU nomme le fichier, et le FICHIER est bien la (committe).
        assert.is_true(contains(ns.Textures.gideonFramePath(), "Texture\\gideon-frame.tga"))
        local file = assert(io.open("Texture/gideon-frame.tga", "rb"), "Texture/gideon-frame.tga manquante")
        local header = file:read(18)
        file:close()
        assert.are.equal(18, #header)
        local bytes = { header:byte(1, 18) }
        assert.are.equal(2, bytes[3], "TGA non compresse type 2 attendu")
        assert.are.equal(32, bytes[17], "32 bits attendus (et non 24)")
        assert.are.equal(width, bytes[13] + bytes[14] * 256)
        assert.are.equal(height, bytes[15] + bytes[16] * 256)
        -- La taille du fichier est celle d'une image NON COMPRESSEE :
        -- 18 octets d'en-tete + largeur x hauteur x 4 octets.
        local size = assert(io.open("Texture/gideon-frame.tga", "rb")):seek("end")
        assert.are.equal(18 + width * height * 4, size)
    end)

    it("la texture GIDEON est REPRODUCTIBLE : le generateur la regenere a l'identique", function()
        -- L'exigence est explicite : aucun binaire « sorti de nulle part ». Le
        -- generateur deterministe de tools/ doit produire EXACTEMENT le fichier
        -- committe (sinon la CI le dit ici).
        local handle = assert(io.popen("python3 tools/make_gideon_frame.py --check 2>&1"))
        local output = handle:read("*a")
        local ok = handle:close()
        assert.is_true(ok, "tools/make_gideon_frame.py --check a echoue : " .. output)
        assert.is_true(contains(output, "OK"), output)
    end)
end)

-- ===========================================================================
describe("Vitrine : les commandes (UI/Showcase.lua, avec le client stubbe)", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.GideonRaidPingHelpPanel = nil
        _G.GideonRaidStyleShowcase = nil
        _G.GideonRaidStyleShowcaseScroll = nil
        _G.GideonRaidStyleShowcaseContent = nil
        _G.SlashCmdList = nil
        _G.GetBindingKey = nil
        stub.install()
        ns = wowenv.loadAddon()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    local function slash(argument)
        _G.SlashCmdList["GIDEONRAID"](argument)
    end

    local function showcase()
        return _G.GideonRaidStyleShowcase
    end

    local function cards()
        return ns.UI.ShowcaseElements()
    end

    -- La vitrine telle que le calque de rendu l'a construite : l'element du bloc.
    local function element(id)
        local found = cards()[id]
        assert.is_not_nil(found, "element introuvable dans la vitrine : " .. tostring(id))
        return found
    end

    -- ------------------------------------------------------------- OUVERTURE ---
    it("`/gr sim style` ouvre la vitrine, avec le bandeau SIMULATION visible", function()
        slash("sim style")
        local panel = showcase()
        assert.is_not_nil(panel, "la vitrine doit exister apres /gr sim style")
        assert.is_true(panel:IsShown())
        -- Le bandeau est DESSINE et il dit qu'on n'est pas en combat.
        local banner = element("showcaseBanner")
        assert.is_true(banner:IsShown())
        assert.are.equal(ns.Locale.t("sim.banner"), banner:GetText())
        -- Le contenu est plus grand que la fenetre : la zone defile.
        local content = element("liveHeader")
        assert.is_not_nil(content)
        assert.is_true(panel.content:GetHeight() > panel:GetHeight())
        assert.is_true(contains(messages(), "STYLE SHOWCASE"))
    end)

    it("la vitrine refuse une valeur de style inconnue, et n'ouvre rien", function()
        slash("sim style 99")
        assert.is_nil(showcase())
        assert.is_true(contains(messages(), "unknown style"))
        -- Rien n'a ete persiste au passage.
        assert.are.equal("card", _G.GideonRaidDB.intermission.style)
    end)

    it("un vrai combat en cours FERME la porte a la vitrine", function()
        -- « elle n'est accessible qu'en mode simulation, JAMAIS en combat ».
        _G.GideonRaidDB.intermission.position = nil
        ns.UI.IntermissionStart()
        assert.is_true(ns.UI.IntermissionRealFlowBusy())
        slash("sim style")
        assert.is_true(contains(messages(), ns.Locale.t("sim.refused.live")), messages())
        assert.is_nil(showcase(), "la vitrine ne doit pas s'ouvrir pendant un combat")
    end)

    -- -------------------------------------------------------------- EN DIRECT ---
    it("cliquer une composition : le mot geant + LE son, exactement comme en combat", function()
        slash("sim style")
        local before = #stub.sounds
        -- Le premier encart de la ligne est le premier etat de l'ordre FIGE
        -- (Layout.INTERMISSION_CHOICE_ORDER).
        local firstState = ns.Layout.INTERMISSION_CHOICE_ORDER[1]
        local card = element("liveChoice1")
        card:Click()
        -- Le son d'assignation est parti, sur le chemin du combat (PlayAssignSound).
        assert.are.equal(1, #stub.sounds - before)
        assert.is_true(contains(stub.sounds[#stub.sounds].path, "assign-3v1r"))
        -- Le clic REMPLACE les trois encarts par UN mot, comme en combat.
        assert.is_false(element("liveChoice1"):IsShown())
        local word = element("word")
        assert.is_true(word:IsShown())
        assert.are.equal(ns.Locale.t("state.word." .. firstState), word:GetText())
        -- ... et le CORRECTEUR ramene les trois encarts.
        element("liveRedo"):Click()
        assert.is_true(element("liveChoice1"):IsShown())
        assert.is_false(element("word"):IsShown())
    end)

    it("RE-cliquer la MEME composition rejoue le son : c'est une demonstration", function()
        slash("sim style")
        local before = #stub.sounds
        element("liveChoice2"):Click()
        element("liveChoice2"):Click()
        element("liveChoice2"):Click()
        assert.are.equal(3, #stub.sounds - before, "chaque clic doit etre audible dans la vitrine")
    end)

    it("`/gr sim style gideon` change l'APERCU en direct, sans toucher au combat", function()
        slash("sim style")
        slash("sim style gideon")
        -- Les encarts de la vitrine sont DESSINES avec la bordure dorée de Gideon...
        local card = element("liveChoice1")
        local border = card.__backdropBorderColor
        assert.is_not_nil(border)
        assert.are.equal(ns.Layout.hexOf(ns.Layout.GIDEON_GOLD), ns.Layout.hexOfColor({ r = border[1], g = border[2], b = border[3] }))
        -- ... et la texture d'encadrement est celle generee par tools/.
        assert.are.equal(ns.Textures.gideonFramePath(), card.__backdrop.edgeFile)
        -- LE PANNEAU DE COMBAT N'A PAS BOUGE : le style livre reste le defaut.
        assert.are.equal("card", _G.GideonRaidDB.intermission.style)
    end)

    -- ------------------------------------------------------------ LE CHOIX REEL --
    it("`/gr style gideon` persiste le style et l'applique au panneau de COMBAT", function()
        slash("style gideon")
        assert.are.equal("gideon", _G.GideonRaidDB.intermission.style)
        slash("inter start")
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        local card = _G.GideonRaidIntermissionPanel.buttons[1]
        assert.are.equal(ns.Textures.gideonFramePath(), card.__backdrop.edgeFile)
        -- `/gr style shipped` ramene le style LIVRE (l'encart a bords actuel).
        slash("style shipped")
        assert.are.equal("card", _G.GideonRaidDB.intermission.style)
        local plain = _G.GideonRaidIntermissionPanel.buttons[1]
        assert.are.equal(ns.Layout.style("card").edgeFile, plain.__backdrop.edgeFile)
    end)

    it("un style inconnu est REFUSE : rien n'est persiste, rien ne change", function()
        slash("style gideon")
        slash("style 42")
        assert.is_true(contains(messages(), "unknown style"))
        assert.are.equal("gideon", _G.GideonRaidDB.intermission.style, "la valeur refusee ne doit rien ecraser")
        -- `/gr style` sans argument DIT ou on en est (et rappelle les candidats).
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("style")
        local text = messages()
        assert.is_true(contains(text, "gideon"), text)
        assert.is_true(contains(text, "shipped"), text)
    end)

    -- ------------------------------------------------------------- ANIMATIONS ---
    it("les animations tournent : fondu d'apparition puis pulsation de bordure", function()
        slash("sim style")
        local panel = showcase()
        assert.is_true(ns.Layout.animationsEnabled(_G.GideonRaidDB.intermission.showcaseAnimations))
        -- Le script OnUpdate n'existe QUE dans la vitrine.
        local update = panel:GetScript("OnUpdate")
        assert.is_not_nil(update)
        -- Au premier tick le panneau apparait en fondu (il n'est pas encore opaque).
        update(panel, 0.05)
        assert.is_true(panel:GetAlpha() < 1)
        assert.is_true(panel:GetAlpha() > 0)
        -- Le fondu se termine, la pulsation prend le relais sur la bordure du
        -- premier encart.
        local pulseCard = element("liveChoice1")
        update(panel, ns.Layout.ANIMATION.FADE_SECONDS + 0.2)
        assert.are.equal(1, panel:GetAlpha())
        local pulsed = pulseCard.__backdropBorderColor
        assert.is_not_nil(pulsed)
        assert.is_true(pulsed[4] < 1, "la bordure doit pulser (alpha < 1) : " .. tostring(pulsed[4]))
    end)

    it("`/gr sim anim off` coupe les animations ET les persiste", function()
        slash("sim anim off")
        assert.is_false(_G.GideonRaidDB.intermission.showcaseAnimations)
        slash("sim style")
        local panel = showcase()
        -- Plus de machine a animer du tout : le panneau est opaque et fixe.
        assert.is_nil(panel:GetScript("OnUpdate"), "aucun OnUpdate quand les animations sont coupees")
        assert.are.equal(1, panel:GetAlpha())
        -- ... et l'encart pulsé a retrouve sa bordure au repos.
        local card = element("liveChoice1")
        local border = card.__backdropBorderColor
        assert.is_not_nil(border)
        assert.are.equal(1, border[4])
        -- La vitrine DIT qu'elles sont coupees.
        assert.is_true(contains(element("animLine"):GetText(), ns.Locale.t("ui.wordDisabled")))
        -- Une valeur inconnue est refusee (rien n'est persiste).
        _G.GideonRaidDB.intermission.showcaseAnimations = true
        slash("sim anim banana")
        assert.is_true(_G.GideonRaidDB.intermission.showcaseAnimations)
        assert.is_true(contains(messages(), "on|off"))
        -- `/gr sim anim` sans argument dit ou on en est, sans rien changer.
        slash("sim anim")
        assert.is_true(contains(messages(), "showcase animations"))
    end)

    it("le panneau de COMBAT n'anime RIEN, jamais", function()
        slash("sim anim off")
        slash("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Aucun fondu : le panneau est opaque des sa premiere image...
        assert.is_nil(panel.__alpha)
        -- ... et il ne porte aucun script d'animation (la vitrine est le SEUL
        -- endroit ou elles tournent).
        assert.is_nil(panel:GetScript("OnUpdate"))
        stub.fireTickers(30)
        assert.is_nil(panel.__alpha)
    end)

    -- ----------------------------------------------------------- BOUTON OK ---
    it("le bouton OK du PLACEMENT enregistre la position, ferme, et ne fait AUCUN bruit", function()
        local db = _G.GideonRaidDB
        db.intermission.position = nil
        slash("inter place")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        local ok = panel.placementOk
        assert.is_not_nil(ok, "le bouton OK doit exister")
        assert.is_true(ok:IsShown(), "le bouton OK doit etre visible pendant le placement")
        -- Le placement ne propose AUCUNE composition : l'illustration, le bouton OK.
        assert.is_false(panel.buttons[1]:IsShown())
        assert.is_false(panel.word:IsShown())
        local before = #stub.sounds
        ok:Click()
        -- Position sauvee...
        assert.is_table(db.intermission.position)
        -- ... panneau ferme...
        assert.is_false(panel:IsShown())
        -- ... et AUCUN son : le placement n'est pas une assignation.
        assert.are.equal(before, #stub.sounds)
    end)

    it("le bouton OK n'apparait JAMAIS dans le panneau de combat", function()
        slash("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.is_false(panel.placementOk:IsShown(), "pas de bouton OK dans le combat")
        -- Pas plus pendant une repetition (le mode simulation n'est pas le placement).
        slash("inter stop")
        ns.UI.SimulationStop()
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("sim inter")
        assert.is_true(panel:IsShown(), messages())
        assert.is_true(panel.buttons[1]:IsShown(), "les trois compositions doivent etre la")
        assert.is_false(panel.placementOk:IsShown(), "pas de bouton OK pendant une repetition")
    end)

    it("la vitrine est positionnable, deplacable, et se remet au centre", function()
        slash("sim style")
        local panel = showcase()
        assert.is_true(panel:IsMovable())
        ns.UI.ShowcaseSavePosition()
        assert.is_table(_G.GideonRaidDB.showcasePosition)
        _G.GideonRaidDB.showcasePosition = { point = "TOPLEFT", x = 40, y = -40 }
        ns.UI.ShowcaseApplyPosition()
        assert.are.equal("TOPLEFT", panel.__point[1])
        slash("resetposition")
        assert.are.equal(ns.Config.defaultPanelPosition().point, _G.GideonRaidDB.showcasePosition.point)
    end)
end)
