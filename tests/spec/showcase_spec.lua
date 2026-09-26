--[[--------------------------------------------------------------------------
    tests/spec/showcase_spec.lua   (busted)
    VITRINE DE STYLE (UI/Showcase.lua) : la surface ou le raid lead VOIT, en jeu,
    tout ce que le design sait faire - au lieu de juger sur une planche HTML hors
    du jeu. DEPUIS LA 0.13.4 IL N'Y A PLUS DE GALERIE : l'encart de la guilde est
    le SEUL style (decision du raid lead, « garde l'option 1 »).

    Familles de tests :
      1. le PLAN est complet (chaque section produit au moins un bloc), sans
         violation, sans identifiant en double, SANS BLOC VIDE NI CADRE FANTOME
         laisse par les sections supprimees ;
      2. IL N'EXISTE QU'UN STYLE : STYLE_ORDER vide, une seule entree dans
         BUTTON_STYLES, une seule dans Config.STYLE_NAMES, et l'encart de la
         guilde porte la palette GIDEON avec la bordure FINE de l'option 1 ;
      3. la PALETTE : les 8 constantes GIDEON et les 6 roles du panneau, chacun avec
         son code hexadecimal ecrit en clair ;
      4. l'allow-list de texte de la vitrine (regle structurelle de Layout) ;
      5. le style CHOISI est persiste, une valeur inconnue - ou un ANCIEN style
         (`gideon`, `card`, `2`..) - est REFUSEE en commande et retombe proprement
         sur l'encart de la guilde dans une sauvegarde ;
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

    before_each(function()
        ns = wowenv.loadCore()
        L = ns.Layout
    end)

    it("n'a QU'UN SEUL style : la galerie de candidats a disparu", function()
        -- STYLE_ORDER est VIDE : rien ne peut plus proposer un choix qui n'existe
        -- pas, et aucune entree morte ne survit dans BUTTON_STYLES.
        assert.are.same({}, L.STYLE_ORDER)
        local names = {}
        for name in pairs(L.BUTTON_STYLES) do
            names[#names + 1] = name
        end
        table.sort(names)
        assert.are.same({ "1" }, names)
        assert.are.equal("1", L.SHIPPED_STYLE)
        assert.are.equal(L.SHIPPED_STYLE, L.CHOICE_STYLE)
        assert.is_true(L.isCandidateStyle("1"))
        assert.is_true(L.isCandidateStyle(L.SHIPPED_STYLE))
        assert.is_true(L.isCandidateStyle("shipped"))
        -- LES SIX CANDIDATS DE LA PLANCHE, `card` ET `gideon` SONT SUPPRIMES :
        -- plus de donnee, plus de resolution, plus de candidat.
        for _, gone in ipairs({ "2", "3", "4", "5", "6", "card", "gideon" }) do
            assert.is_nil(L.BUTTON_STYLES[gone], gone .. " ne doit plus avoir de donnee")
            assert.is_nil(L.resolveStyle(gone), gone .. " ne doit plus se resoudre")
            assert.is_false(L.isCandidateStyle(gone), gone .. " ne doit plus etre un candidat")
        end
        assert.is_false(L.isCandidateStyle("8"))
        assert.is_false(L.isCandidateStyle("nope"))
    end)

    it("l'encart de la guilde : bordure FINE (option 1) et palette GIDEON exacte", function()
        local style = L.style("1")
        -- LA SIGNATURE de l'option 1 : une bordure de 1 px, JAMAIS epaissie, un
        -- fond discret et un padding de 6 px. L'identite GIDEON passe par la
        -- COULEUR, jamais par l'epaisseur du cadre.
        assert.are.equal(1, style.edgeSize, "la bordure doit rester FINE (1 px)")
        assert.are.equal("Interface\\Buttons\\WHITE8X8", style.edgeFile)
        assert.are.equal("Interface\\Buttons\\WHITE8X8", style.bgFile)
        assert.are.equal(6, style.padding)
        assert.are.same({ left = 1, right = 1, top = 1, bottom = 1 }, style.insets)
        -- LES COULEURS SONT LES CONSTANTES ELLES-MEMES.
        assert.are.same(L.colorOf(L.GIDEON_GOLD), style.border, "bordure au repos = or Gideon")
        assert.are.same(L.colorOf(L.GIDEON_CYAN), style.borderHover, "survol = cyan Gideon")
        assert.are.same(L.colorOf(L.GIDEON_GOLD_HI), style.borderPressed, "appui = or vif Gideon")
        assert.are.equal(L.hexOf(L.GIDEON_PANEL), L.hexOfColor(style.background))
        assert.is_true(style.background.a > 0.9 and style.background.a < 0.95, "fond sombre ~0,92")
        -- AUCUN second cadre : le style 6 (« double cadre ») est supprime.
        assert.is_nil(style.innerEdgeSize)
        assert.is_nil(style.innerBorder)
        assert.is_true(L.cardPadding("1") > 0, "l'encart reserve une marge interieure")
    end)

    it("chaque style declare est une DONNEE complete, et FINE (aucun second cadre)", function()
        -- Il n'y a qu'UNE entree, mais elle est verifiee comme la galerie l'etait :
        -- une bordure, un fond, un padding et les trois etats sont OBLIGATOIRES, et
        -- l'epaisseur reste celle de l'option 1 (1 px) - le style 6, qui declarait
        -- un second cadre interieur, a disparu avec la galerie.
        local count = 0
        for name, style in pairs(L.BUTTON_STYLES) do
            count = count + 1
            assert.is_string(style.edgeFile, name .. " : bordure (edgeFile) manquante")
            assert.is_true(tonumber(style.edgeSize) > 0, name .. " : edgeSize invalide")
            assert.are.equal(1, tonumber(style.edgeSize), name .. " : la bordure de l'option 1 doit rester FINE")
            assert.is_table(style.background, name .. " : fond (background) manquant")
            assert.is_table(style.border, name .. " : bordure au repos manquante")
            assert.is_table(style.borderHover, name .. " : bordure au survol manquante")
            assert.is_table(style.borderPressed, name .. " : bordure a l'appui manquante")
            assert.is_true(L.cardPadding(name) >= 0, name .. " : padding invalide")
            assert.is_nil(style.innerEdgeSize, name .. " : plus aucun style ne porte de second cadre")
            assert.is_nil(style.innerBorder, name .. " : plus aucun style ne porte de second cadre")
        end
        assert.are.equal(1, count, "une seule entree de style")
    end)

    it("le style de la guilde est le SEUL : chaque alias mene a la meme table", function()
        -- « une seule source de verite » : `1`, `shipped`, `bare`, `nu` et `encartnu`
        -- doivent tous rendre LA MEME table (aucune copie qui pourrait diverger).
        local reference = L.BUTTON_STYLES["1"]
        for _, alias in ipairs({ "1", "shipped", "bare", "nu", "encartnu", "livre", "default" }) do
            local resolved = L.resolveStyle(alias)
            assert.is_not_nil(resolved, alias)
            assert.are.equal(reference, L.style(resolved), alias .. " : deux tables differentes")
            assert.are.equal(reference, L.style(alias), alias)
        end
        -- Un nom absent ne rend jamais nil : le repli est le style livre.
        assert.are.equal(reference, L.style(nil))
        assert.are.equal(reference, L.style("gideon"))
        assert.are.equal(reference, L.style("card"))
    end)

    it("le panneau de COMBAT dessine l'encart de la guilde, sans qu'on le lui dise", function()
        -- Le defaut du panneau EST le style livre : les trois encarts de combat
        -- portent tous le meme style, celui de la guilde, sans option passee.
        local layout = L.intermissionPanel({ showChoices = true })
        assert.are.equal("", table.concat(L.violations(layout), " | "))
        local seen = 0
        for index = 1, #layout.blocks do
            local block = layout.blocks[index]
            if block.kind == "image" then
                seen = seen + 1
                assert.are.equal(L.CHOICE_STYLE, block.style, "encart " .. index)
                assert.are.equal(L.SHIPPED_STYLE, block.style, "encart " .. index)
                assert.are.equal(L.cardPadding(L.CHOICE_STYLE), block.padding, "encart " .. index)
                -- Un encart de COMBAT ne porte jamais d'action de vitrine.
                assert.is_nil(block.action, "encart " .. index)
            end
        end
        assert.are.equal(#L.INTERMISSION_CHOICE_ORDER, seen, "les trois compositions sont des encarts")
        -- L'illustration du PLACEMENT suit exactement le meme style.
        local placement = L.placementPanel()
        assert.are.equal("", table.concat(L.violations(placement), " | "))
        assert.are.equal(L.CHOICE_STYLE, placement.blocks[1].style)
    end)

    it("le retour visuel est une COULEUR : la bordure s'eclaire au survol et a l'appui", function()
        -- On mesure la LUMINANCE PERCUE et pas le canal rouge : le survol passe de
        -- l'or (#D19A45) au CYAN (#7ADBFA) - rouge en baisse, vert et bleu en
        -- hausse, luminance globale en hausse.
        local style = L.style(L.CHOICE_STYLE)
        local function lum(color)
            return (0.2126 * color.r) + (0.7152 * color.g) + (0.0722 * color.b)
        end
        assert.is_true(lum(style.borderHover) > lum(style.border), "la bordure doit s'eclairer au survol")
        assert.is_true(lum(style.borderPressed) > lum(style.border), "la bordure doit s'eclairer a l'appui")
        -- ... et les trois etats sont DISTINCTS : comparer n'a de sens que s'ils
        -- ne partagent pas la meme couleur.
        local seen = {}
        for _, color in ipairs({ style.border, style.borderHover, style.borderPressed }) do
            local hex = L.hexOfColor(color)
            assert.is_nil(seen[hex], "deux etats partagent la meme couleur : " .. hex)
            seen[hex] = true
        end
    end)

    it("resout les alias de l'encart de la guilde et REFUSE tout le reste", function()
        assert.are.equal("1", L.resolveStyle("1"))
        for _, alias in ipairs({ "bare", "nu", "encartnu", "  BaRe  " }) do
            assert.are.equal("1", L.resolveStyle(alias), alias)
        end
        -- « shipped » (et ses synonymes) ramene le style LIVRE : la valeur persistee
        -- est toujours un nom canonique, jamais le mot « shipped ».
        for _, alias in ipairs({ "shipped", "livre", "default" }) do
            assert.are.equal(L.SHIPPED_STYLE, L.resolveStyle(alias), alias)
        end
        -- TOUT LE RESTE EST REFUSE (aucun repli silencieux) : les anciens candidats,
        -- l'ancien encart et n'importe quelle valeur inconnue.
        for _, bad in ipairs({ "0", "2", "3", "4", "5", "6", "7", "99", "card", "gideon", "nue", "nope", "-1", "" }) do
            assert.is_nil(L.resolveStyle(bad), tostring(bad) .. " doit etre refuse")
        end
        assert.is_nil(L.resolveStyle(nil))
        assert.is_nil(L.resolveStyle(7))
    end)

    it("la vitrine a SIX sections, chacune avec du contenu", function()
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
        -- 5. l'encart de la guilde, UN SEUL exemple.
        assert.is_not_nil(textBlock(layout, "stylesHeader"))
        assert.is_not_nil(textBlock(layout, "styleCap1"))
        -- 6. les animations.
        assert.is_not_nil(textBlock(layout, "animHeader"))
        assert.is_not_nil(textBlock(layout, "animLine"))
        -- AUCUN BLOC VIDE, AUCUN CADRE FANTOME : les sections supprimees (la galerie
        -- des 7 candidats) ne laissent ni deuxieme exemple, ni legende, ni rangee
        -- derriere elles.
        assert.is_nil(textBlock(layout, "styleCap2"))
        assert.is_nil(textBlock(layout, "styleCap7"))
        assert.is_nil(textBlock(layout, "stylesPreview"))
        assert.is_nil(textBlock(layout, "styleRow1"))
        assert.is_nil(textBlock(layout, "styleCard2"))
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

    it("l'encart de la guilde est DESSINE UNE SEULE FOIS, dans son style", function()
        local layout = L.showcasePanel()
        local cards = {}
        for _, block in ipairs(everyBlock(layout)) do
            if block.kind == "image" and type(block.id) == "string" and block.id:match("^styleCard%d+$") ~= nil then
                cards[#cards + 1] = block
            end
        end
        assert.are.equal(1, #cards, "UN SEUL encart d'exemple (plus de galerie)")
        local card = cards[1]
        assert.are.equal("styleCard1", card.id)
        -- L'exemple porte LE style livre : la donnee decide du rendu.
        assert.are.equal(L.CHOICE_STYLE, card.style)
        -- ... et le meme echantillon que la planche validee (2 verts + 2 rouges).
        assert.are.equal(L.SHOWCASE_SAMPLE_STATE, card.state)
        -- PLUS RIEN A CLIQUER : l'apercu d'un candidat n'existe plus.
        assert.is_nil(card.action)
        -- La legende donne les DEUX codes hexa et le NOM du style, dans la langue
        -- active : le raid lead dicte une valeur sans ambiguite.
        local caption = textBlock(layout, "styleCap1")
        assert.is_not_nil(caption)
        local style = L.style(L.CHOICE_STYLE)
        assert.is_true(contains(caption.text, L.hexOfColor(style.border)), caption.text)
        assert.is_true(contains(caption.text, L.hexOfColor(style.background)), caption.text)
        assert.is_true(contains(caption.text, ns.Locale.t(style.labelKey)), caption.text)
        -- L'entete et la note disent que c'est L'ENCART DE LA GUILDE, le seul style.
        assert.is_true(contains(textBlock(layout, "stylesHeader").text, "GUILD CARD"))
        assert.is_true(contains(textBlock(layout, "stylesNote").text, "gallery is gone"))
        -- ... et la note de contexte nomme ce que le COMBAT dessine.
        assert.is_true(contains(textBlock(layout, "stylesCurrent").text, ns.Locale.t(style.labelKey)))
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
        assert.is_true(contains(onLine.text, "/gideon sim anim"), "la commande doit etre rappelee")
    end)
end)

-- ===========================================================================
describe("Vitrine : la configuration du raid lead", function()
    local ns
    local C
    local L
    local T

    before_each(function()
        ns = wowenv.loadCore()
        C = ns.Config
        L = ns.Layout
        T = ns.Textures
    end)

    it("la liste des styles est le MIROIR EXACT de Core/Layout - et il n'y en a QU'UN", function()
        -- Core/Config.lua est charge AVANT Core/Layout.lua (il le faut : Layout
        -- mesure les libelles de Config), donc la liste est un miroir. Ce test est
        -- ce qui empeche le miroir de mentir : un style ajoute dans Layout sans etre
        -- ajoute ici est un style INUTILISABLE - il echoue ici au lieu de disparaitre
        -- en silence. Depuis la 0.13.4 il verrouille AUSSI l'unicite : UNE entree de
        -- chaque cote, jamais une de plus.
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
        assert.are.equal(1, #names, "une seule source de verite : UN style")
        assert.are.equal(1, #mirror)
        assert.are.equal(L.SHIPPED_STYLE, C.DEFAULT_STYLE)
        assert.are.equal(L.SHIPPED_STYLE, C.STYLE_NAMES[1])
        assert.are.same({}, L.STYLE_ORDER)
    end)

    it("une valeur inconnue - ou un ANCIEN style - retombe sur l'encart de la guilde", function()
        -- Le resolver est TOTAL : jamais nil, jamais d'erreur, toujours le style
        -- livre. Les anciens noms (`gideon`, `card`, les candidats `2`..`6`) sont
        -- d'anciennes sauvegardes, pas des commandes.
        for _, raw in ipairs({ nil, "", "nope", 7, "shipped", "gideon", "card", "2", "3", "6" }) do
            assert.are.equal("1", C.resolveStyleName(raw), tostring(raw) .. " doit retomber sur le style livre")
        end
        assert.are.equal("1", C.resolveStyleName({}))
        assert.are.equal("1", C.resolveStyleName("1"))
        assert.are.equal("1", C.resolveStyleName(" 1 "))
    end)

    it("la sauvegarde porte le style, l'apercu et les animations", function()
        local db = C.ensureDB({})
        assert.are.equal("1", db.intermission.style)
        assert.are.equal("1", db.intermission.showcaseStyle)
        assert.is_true(db.intermission.showcaseAnimations)
        assert.is_table(db.showcasePosition)
        -- Un style ABSURDE dans la sauvegarde ne casse rien : on retombe sur le livre.
        local broken = C.ensureDB({ intermission = { style = "hacker" } })
        assert.are.equal("1", C.resolveIntermission(broken.intermission).style)
        -- UNE SAUVEGARDE ANCIENNE retombe PROPREMENT sur l'encart de la guilde, sans
        -- erreur et sans qu'un style supprime remonte jamais au panneau.
        for _, old in ipairs({ "gideon", "card", "2", "6" }) do
            local legacy = C.ensureDB({ intermission = { style = old } })
            assert.are.equal("1", C.resolveIntermission(legacy.intermission).style, tostring(old))
        end
        -- Un style choisi EST respecte.
        local chosen = C.ensureDB({ intermission = { style = "1", showcaseAnimations = false } })
        assert.are.equal("1", C.resolveIntermission(chosen.intermission).style)
        assert.is_false(C.resolveIntermission(chosen.intermission).showcaseAnimations)
        -- Les animations : seul un faux EXPLICITE les coupe (meme regle que Layout).
        for _, raw in ipairs({ nil, true, "false", 0, "" }) do
            assert.is_true(C.resolveIntermission({ showcaseAnimations = raw }).showcaseAnimations)
        end
        assert.is_false(C.resolveIntermission({ showcaseAnimations = false }).showcaseAnimations)
    end)

    it("le cadre GIDEON a disparu : ni donnee, ni entree au .toc, ni fichier", function()
        -- La galerie est retiree : le cadre 9 tranches de l'ancien style `gideon` ne
        -- doit plus exister nulle part - ni dans Core/Textures.lua, ni dans le .toc,
        -- ni sur le disque (le generateur non plus : il sait se refaire si le raid
        -- lead redemande un jour un cadre).
        assert.is_nil(T.GIDEON_FRAME_FILE)
        assert.is_nil(T.GIDEON_FRAME_SIZE)
        assert.is_nil(T.gideonFramePath)
        assert.is_nil(T.gideonFrameSize)
        -- Le .toc ne doit plus le LISTER...
        for _, entry in ipairs(wowenv.tocEntries()) do
            assert.is_nil(entry:find("gideon%-frame"), "le .toc ne doit plus lister " .. entry)
        end
        -- ... ni meme le NOMMER, commentaire compris : une entree fantome dans un
        -- manifeste est exactement ce qui remet un fichier dans le zip un jour.
        local manifest = io.open("GideonRaid.toc", "r")
        assert.is_not_nil(manifest, "GideonRaid.toc doit exister")
        for line in manifest:lines() do
            assert.is_nil(line:find("gideon%-frame"), "reference fantome dans le .toc : " .. line)
            assert.is_nil(line:find("make_gideon"), "reference fantome dans le .toc : " .. line)
        end
        manifest:close()
        for _, relative in ipairs({ "Texture/gideon-frame.tga", "tools/make_gideon_frame.py" }) do
            -- `busted` tourne depuis la racine du depot (voir .busted).
            local handle = io.open(relative, "rb")
            assert.is_nil(handle, relative .. " doit avoir ete supprime")
            if handle ~= nil then
                handle:close()
            end
        end
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
    it("`/gideon sim style` ouvre la vitrine, avec le bandeau SIMULATION visible", function()
        slash("sim style")
        local panel = showcase()
        assert.is_not_nil(panel, "la vitrine doit exister apres /gideon sim style")
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
        -- Les anciens candidats, l'ancien encart et n'importe quelle valeur
        -- inconnue sont REFUSES : rien n'est cree, rien n'est affiche, rien n'est
        -- persiste.
        for _, bad in ipairs({ "99", "gideon", "card", "2", "6" }) do
            _G.DEFAULT_CHAT_FRAME.messages = {}
            slash("sim style " .. bad)
            assert.is_nil(showcase(), bad .. " ne doit pas ouvrir la vitrine")
            assert.is_true(contains(messages(), "unknown style"), messages())
        end
        assert.are.equal("1", _G.GideonRaidDB.intermission.style, "rien n'a ete persiste")
        -- ... alors que LE style de la guilde ouvre la vitrine.
        slash("sim style 1")
        assert.is_not_nil(showcase())
        assert.is_true(showcase():IsShown())
        slash("sim style shipped")
        assert.is_true(showcase():IsShown())
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

    it("la vitrine dessine l'encart de la guilde : bordure fine + OR de GIDEON", function()
        slash("sim style")
        -- Les encarts de la vitrine sont DESSINES avec la bordure dorée de Gideon...
        local card = element("liveChoice1")
        local border = card.__backdropBorderColor
        assert.is_not_nil(border)
        assert.are.equal(ns.Layout.hexOf(ns.Layout.GIDEON_GOLD), ns.Layout.hexOfColor({ r = border[1], g = border[2], b = border[3] }))
        -- ... et la bordure est FINE : c'est la texture blanche 1x1 du client, plus
        -- aucun cadre 9 tranches.
        assert.are.equal("Interface\\Buttons\\WHITE8X8", card.__backdrop.edgeFile)
        assert.are.equal(ns.Layout.style(ns.Layout.CHOICE_STYLE).edgeFile, card.__backdrop.edgeFile)
        -- L'ENCART D'EXEMPLE est dessine dans le meme style, et il n'a plus d'action.
        assert.are.equal("Interface\\Buttons\\WHITE8X8", element("styleCard1").__backdrop.edgeFile)
        assert.is_nil(element("styleCard1").showcaseAction)
        -- IL N'Y A PLUS D'APERCU A CHANGER : `/gideon sim style 1` est accepte sans
        -- toucher au style du combat, et un ancien style est REFUSE.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("sim style 1")
        assert.are.equal(ns.Layout.SHIPPED_STYLE, _G.GideonRaidDB.intermission.style)
        slash("sim style gideon")
        assert.is_true(contains(messages(), "unknown style"))
        assert.are.equal(ns.Layout.SHIPPED_STYLE, _G.GideonRaidDB.intermission.style)
    end)

    -- ------------------------------------------------------------ LE CHOIX REEL --
    it("`/gideon style 1` (et `shipped`) persiste le style et l'applique au panneau de COMBAT", function()
        slash("style shipped")
        assert.are.equal("1", _G.GideonRaidDB.intermission.style)
        slash("inter start")
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        local card = _G.GideonRaidIntermissionPanel.buttons[1]
        assert.are.equal("Interface\\Buttons\\WHITE8X8", card.__backdrop.edgeFile)
        local red, green, blue = card:GetBackdropBorderColor()
        assert.are.equal(
            ns.Layout.hexOf(ns.Layout.GIDEON_GOLD),
            ns.Layout.hexOfColor({ r = red, g = green, b = blue }),
            "le panneau de combat dessine la bordure OR de Gideon"
        )
        -- TOUS les alias de l'encart de la guilde sont acceptes et persistent la
        -- meme valeur canonique.
        for _, alias in ipairs({ "1", "bare", "nu", "encartnu", "shipped" }) do
            _G.SlashCmdList["GIDEONRAID"]("style " .. alias)
            assert.are.equal("1", _G.GideonRaidDB.intermission.style, alias)
        end
        -- ... et un ANCIEN style est REFUSE : rien n'est persiste.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("style card")
        assert.is_true(contains(messages(), "unknown style"), messages())
        assert.are.equal("1", _G.GideonRaidDB.intermission.style)
    end)

    it("une sauvegarde ANCIENNE retombe sur l'encart de la guilde, en combat", function()
        -- Un joueur qui avait `gideon` (ou `card`, ou un candidat) dans son
        -- SavedVariables ne casse rien : le panneau de combat dessine le style livre.
        _G.GideonRaidDB.intermission.style = "gideon"
        slash("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        local style = ns.Layout.style(ns.Layout.CHOICE_STYLE)
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            assert.are.equal(style.edgeFile, panel.buttons[index].__backdrop.edgeFile, "bouton " .. index)
        end
        -- Le resolver reste TOTAL : l'ancienne valeur ne remonte jamais telle quelle.
        assert.are.equal("1", ns.Config.resolveIntermission(_G.GideonRaidDB.intermission).style)
    end)

    it("un style inconnu est REFUSE : rien n'est persiste, rien ne change", function()
        slash("style 1")
        slash("style 42")
        assert.is_true(contains(messages(), "unknown style"))
        assert.are.equal("1", _G.GideonRaidDB.intermission.style, "la valeur refusee ne doit rien ecraser")
        -- `/gideon style` sans argument DIT ou on en est ET qu'il n'y a plus de choix.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        slash("style")
        local text = messages()
        assert.is_true(contains(text, ns.Locale.t("style.1")), text)
        assert.is_true(contains(text, "nothing left to choose"), text)
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

    it("`/gideon sim anim off` coupe les animations ET les persiste", function()
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
        -- `/gideon sim anim` sans argument dit ou on en est, sans rien changer.
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
