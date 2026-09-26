--[[--------------------------------------------------------------------------
    tests/spec/layout_spec.lua   (busted)

    Tests HORS JEU de la DISPOSITION DES PANNEAUX (Core/Layout.lua, logique PURE) :
    apres le 4e test en jeu, le raid lead a signale (a) des libelles qui
    debordaient du cadre du panneau principal et (b) le grand etat (« 2V2R »)
    dessine PAR-DESSUS le bandeau SIMULATION. La cause etait la meme : chaque
    element etait pose a un decalage Y FIXE.

    Ce que ces tests verrouillent, pour l'ANGLAIS ET LE FRANCAIS :
      1. le moteur empile les blocs les uns SOUS les autres (jamais deux blocs
         sur la meme bande Y, jamais un bloc hors du cadre) ;
      2. les plans des trois surfaces (panneau principal, panneau d'intermission,
         fenetre d'aide au ping) ne produisent AUCUNE violation, dans toutes les
         phases (placement, combat, declaration, repetition, sans boss) ;
      3. l'ORDRE des boutons du panneau principal est fige
         (PLACE, PING, SIM-INTER, LOCK) : un futur changement ne peut pas casser
         silencieusement l'ordre demande ;
      4. les quatre boutons du panneau principal ont la MEME largeur et le flux
         est espace regulierement, le bouton de verrouillage etant mis a part.
----------------------------------------------------------------------------]]
--
--
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

--- La liste des violations, en une chaine lisible (vide = plan sain).
local function problemsOf(Layout, layout)
    return table.concat(Layout.violations(layout), " | ")
end

--- Les identifiants des blocs, dans l'ordre du plan.
local function ids(layout)
    local out = {}
    for index = 1, #layout.blocks do
        out[#out + 1] = layout.blocks[index].id
    end
    return out
end

--- Un bloc par identifiant (nil s'il n'est pas dans le plan).
local function blockOf(layout, id)
    for index = 1, #layout.blocks do
        if layout.blocks[index].id == id then
            return layout.blocks[index]
        end
    end
    return nil
end

--- L'element de ligne d'un bloc (bouton de ligne ou bloc entier).
local function rowItemOf(layout, rowId, itemId)
    local row = blockOf(layout, rowId)
    if row == nil or row.kind ~= "row" then
        return nil
    end
    for index = 1, #row.items do
        if row.items[index].id == itemId then
            return row.items[index]
        end
    end
    return nil
end

--- Verifie que le bloc `second` est entierement SOUS le bloc `first` (c'est
--- exactement le bug du 4e test en jeu : le grand etat par-dessus le bandeau).
local function assertStacked(layout, firstId, secondId, label)
    local first = blockOf(layout, firstId)
    local second = blockOf(layout, secondId)
    assert.is_truthy(first, firstId)
    assert.is_truthy(second, secondId)
    assert.is_true(second.top < first.bottom, (label or "") .. " : " .. firstId .. " chevauche " .. secondId)
end

local function bodyLines(count, text)
    local out = {}
    for index = 1, count do
        out[index] = text or ("line " .. index .. ": a long enough body line to be wrapped by the layout engine")
    end
    return out
end

describe("Layout : moteur pur (blocs ancres les uns sous les autres)", function()
    local ns = wowenv.loadCore()
    local L = ns.Layout

    before_each(function()
        ns.Locale.setActive("en")
    end)

    it("empile les blocs SANS jamais les faire se chevaucher", function()
        local layout = L.build({
            minWidth = 300,
            blocks = {
                { id = "title", kind = "text", align = "center", style = "normal", text = "GideonRaid" },
                { id = "body", kind = "text", align = "left", style = "small", text = "un corps de texte" },
                { id = "ok", kind = "button", align = "center", text = "OK" },
            },
        })
        assert.are.equal("title body ok", table.concat(ids(layout), " "))
        -- Chaque bloc commence SOUS le bas du precedent (gap > 0).
        for index = 2, #layout.blocks do
            local previous = layout.blocks[index - 1]
            local current = layout.blocks[index]
            assert.is_true(current.top <= previous.bottom, index .. " remonte au-dessus du precedent")
            assert.are.equal((current.gapBefore or 0) + L.GAP, previous.bottom - current.top)
        end
        -- Le cadre contient le dernier bloc, avec la marge basse.
        local last = layout.blocks[#layout.blocks]
        assert.are.equal(-last.bottom + L.MARGIN_BOTTOM, layout.height)
        assert.are.equal("", problemsOf(L, layout))
    end)

    it("detecte VRAIMENT un chevauchement, un debordement et un mot trop large", function()
        -- Plan fabrique a la main : c'est le DETECTEUR qu'on teste ici, donc on
        -- n'utilise pas build() (qui, lui, ne peut pas produire ces defauts).
        local layout = {
            width = 200,
            height = 100,
            marginX = 16,
            blocks = {
                {
                    id = "a",
                    kind = "text",
                    align = "left",
                    style = "normal",
                    text = "bloc A",
                    top = -10,
                    bottom = -25,
                    x = 16,
                    width = 168,
                },
                {
                    id = "b",
                    kind = "text",
                    align = "left",
                    style = "normal",
                    text = "bloc B",
                    top = -20,
                    bottom = -35,
                    x = 16,
                    width = 168,
                },
                { id = "wide", kind = "button", align = "center", text = "X", top = -40, bottom = -60, width = 400 },
                {
                    id = "word",
                    kind = "text",
                    align = "left",
                    style = "huge",
                    text = "SUPERCALIFRAGILISTIC",
                    top = -70,
                    bottom = -90,
                    x = 16,
                    width = 100,
                },
            },
        }
        local problems = table.concat(L.violations(layout), " | ")
        assert.is_true(contains(problems, "overlap"), problems)
        assert.is_true(contains(problems, "border"), problems)
        assert.is_true(contains(problems, "wider than its block"), problems)
    end)

    it("mesure, replie et fait grandir le texte", function()
        -- Une ligne courte tient sur une ligne, une ligne longue se replie.
        assert.are.equal(1, L.wrapCount("court", "normal", 300))
        assert.is_true(L.wrapCount(string.rep("x", 100), "normal", 200) >= 3)
        assert.are.equal(1, L.wrapCount("", "normal", 0))
        -- La hauteur suit le repli, la largeur suit la plus longue ligne explicite.
        local short = L.textHeight("court", "normal", 200)
        local long = L.textHeight(string.rep("mot ", 40), "normal", 200)
        assert.is_true(long > short)
        assert.are.equal(L.FONTS.normal.height, short)
        assert.is_true(L.textWidth("a\n" .. string.rep("b", 20), "normal") >= (20 * L.FONTS.normal.charWidth))
        assert.are.equal(0, L.textWidth("", "normal"))
        -- Un style inconnu retombe sur la police par defaut (jamais d'erreur).
        assert.are.equal(L.FONTS[L.FONT_FALLBACK].height, L.textHeight("x", "bidon", 100))
        -- Le decoupage explicite (les libelles de boutons portent des \n).
        assert.are.same({ "1v3r", "suite" }, L.splitLines("1v3r\nsuite"))
        assert.are.same({ "" }, L.splitLines(""))
        assert.are.same({ "" }, L.splitLines(nil))
    end)

    it("ne descend JAMAIS sous la largeur exigee par un libelle de bouton", function()
        local layout = L.build({
            minWidth = 120,
            blocks = {
                { id = "title", kind = "text", align = "center", style = "normal", text = "GideonRaid" },
                { id = "b", kind = "button", align = "center", text = "UN LIBELLE FRANCAIS ASSEZ LONG" },
            },
        })
        assert.is_true(layout.width > 120, "le cadre doit s'elargir pour le libelle")
        local block = layout.blocks[2]
        assert.is_true(L.textWidth(block.text, "button") + (2 * L.BUTTON_PADDING_X) <= block.width)
        assert.are.equal("", problemsOf(L, layout))
    end)
    it("ancre CHAQUE bloc et CHAQUE bouton de ligne (regression du 5e test en jeu)", function()
        -- Bug du 5e test : les boutons de ligne n'avaient AUCUNE ancre, donc
        -- Frame:SetPoint recevait nil, levait, et l'applier s'arretait : les trois
        -- boutons de composition et le bouton OK disparaissaient de l'ecran.
        local layout = L.build({
            minWidth = 300,
            blocks = {
                { id = "t", kind = "text", align = "left", style = "small", text = "x" },
                { id = "b", kind = "button", align = "center", text = "OK" },
                {
                    id = "row",
                    kind = "row",
                    items = {
                        { id = "gauche", text = "REDO", align = "left" },
                        { id = "droite", text = "Close", align = "right" },
                    },
                },
            },
        })
        for index = 1, #layout.blocks do
            local block = layout.blocks[index]
            assert.is_true(type(block.point) == "string" and block.point ~= "", "bloc sans ancre : " .. block.id)
            if block.kind == "row" then
                for item = 1, #block.items do
                    local current = block.items[item]
                    assert.is_true(type(current.point) == "string" and current.point ~= "", "bouton de ligne sans ancre : " .. current.id)
                    -- L'ancre est celle de l'applier : TOPLEFT, x mesure depuis le
                    -- bord gauche du cadre, top depuis le bord haut.
                    assert.are.equal("TOPLEFT", current.point)
                    assert.is_number(current.x)
                    assert.is_number(current.top)
                end
            end
        end
        assert.are.equal("", problemsOf(L, layout))
    end)

    it("detecte un bloc sans ancre et un libelle plus grand que son bouton", function()
        local layout = {
            width = 200,
            height = 100,
            marginX = 16,
            blocks = {
                {
                    id = "sans",
                    kind = "button",
                    align = "left",
                    style = "button",
                    text = "OK",
                    x = 16,
                    top = -10,
                    bottom = -38,
                    width = 80,
                    height = 28,
                },
                {
                    id = "etroit",
                    kind = "button",
                    align = "left",
                    point = "TOPLEFT",
                    style = "button",
                    text = "UN LIBELLE BEAUCOUP TROP LONG",
                    x = 16,
                    top = -45,
                    bottom = -75,
                    width = 60,
                    height = 30,
                },
            },
        }
        local problems = problemsOf(L, layout)
        assert.is_true(contains(problems, "has no anchor point"), problems)
        assert.is_true(contains(problems, "is wider than its button"), problems)
    end)
end)

describe("Layout : boutons dimensionnes sur leur libelle (EN et FR)", function()
    local ns = wowenv.loadCore()
    local L, I, S = ns.Layout, ns.Intermission, ns.Simulation

    before_each(function()
        ns.Locale.setActive("en")
    end)

    --- Tous les boutons d'un plan : blocs boutons + boutons de ligne.
    local function buttonsOf(layout)
        local out = {}
        for index = 1, #layout.blocks do
            local block = layout.blocks[index]
            if block.kind == "button" or block.kind == "image" then
                out[#out + 1] = block
            elseif block.kind == "row" then
                for item = 1, #block.items do
                    out[#out + 1] = block.items[item]
                end
            end
        end
        return out
    end

    --- Le libelle d'un bouton tient dans le bouton, AVEC la marge interieure du
    --- module : ni trop large, ni trop haut (c'est le retour en jeu « le texte
    --- sort du bouton »). Un bouton d'IMAGE n'a aucun libelle : c'est l'image qui
    --- est mesuree (voir le test de l'ordre fige du panneau d'intermission).
    local function assertLabelFits(block, label)
        assert.is_number(block.width, label .. " : largeur manquante")
        assert.is_number(block.height, label .. " : hauteur manquante")
        if block.kind == "image" then
            assert.is_true(block.width > 0 and block.height > 0, label .. " : image de taille nulle")
            return
        end
        local paddingX = block.paddingX or L.BUTTON_PADDING_X
        local paddingY = block.paddingY or L.BUTTON_PADDING_Y
        local drawn = L.textWidth(block.text, block.style)
        assert.is_true(drawn <= (block.width - (2 * paddingX)), label .. " : libelle plus large que le bouton")
        local lines = #L.splitLines(block.text)
        local needed = lines * L.FONTS[block.style or "button"].height
        assert.is_true(needed <= (block.height - (2 * paddingY)), label .. " : libelle plus haut que le bouton")
    end

    --- Les cinq surfaces de l'addon, telles que la couche UI/ les demande.
    local function surfaces()
        local run = S.newRun()
        local rehearsal = S.forRehearsal(I.snapshot(I.start(I.newState(), { leadSeconds = 0 }), "anchors"), run)
        return {
            { id = "panneau-principal", layout = L.mainPanel({ bodyLines = { "plan" } }) },
            { id = "placement", layout = L.placementPanel() },
            {
                id = "repetition",
                layout = L.intermissionPanel({
                    bannerLines = rehearsal.simBannerLines,
                    showChoices = true,
                }),
            },
            {
                id = "apres-clic",
                layout = L.intermissionPanel({
                    wordText = ns.Locale.t("state.word.1V3R"),
                    wordState = "1V3R",
                    showRedo = true,
                }),
            },
            { id = "aide-au-ping", layout = L.pingHelpPanel({ lines = { "l" }, keyLines = { "k" } }) },
        }
    end

    it("aucun libelle ne touche ni ne depasse le bord de son bouton (deux langues)", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            for _, surface in ipairs(surfaces()) do
                local buttons = buttonsOf(surface.layout)
                assert.is_true(#buttons > 0, surface.id .. " : aucun bouton dans le plan")
                for index = 1, #buttons do
                    assertLabelFits(buttons[index], lang .. " / " .. surface.id .. " / " .. buttons[index].id)
                end
                -- Le plan complet reste sain : c'est AUSSI ce que verifie
                -- Layout.violations (largeur ET hauteur du libelle).
                assert.are.equal("", problemsOf(L, surface.layout), lang .. " / " .. surface.id)
            end
        end
    end)

    it("le mot du clic est EXPLICITE, plus GROS que le minimum demande, et jamais tronque", function()
        -- Le raid lead a demande le mot « 5 crans plus gros » : au moins 44 px
        -- pour PING et CHASSEUR, au moins 64 px pour BOSS (le plus gros element
        -- de la fenetre). Les deux tailles ET le fichier de police sont une
        -- DONNEE DE CORE (L.WORD_SIZE / L.WORD_SIZE_BIG / L.WORD_FONT_FILE) et le
        -- bloc du plan les PORTE : la couche UI/ appelle SetFont(file, taille, "")
        -- avec ces valeurs, jamais un objet de police Blizzard dont la taille ne
        -- peut pas etre lue hors du jeu.
        assert.is_true(L.WORD_SIZE >= 44, "PING/CHASSEUR : taille demandee >= 44 px (recu " .. tostring(L.WORD_SIZE) .. ")")
        assert.is_true(L.WORD_SIZE_BIG >= 64, "BOSS : taille demandee >= 64 px (recu " .. tostring(L.WORD_SIZE_BIG) .. ")")
        assert.is_true(L.WORD_SIZE_BIG > L.WORD_SIZE, "BOSS doit rester le plus gros mot de la fenetre")
        assert.are.equal("string", type(L.WORD_FONT_FILE))
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            for _, state in ipairs({ "1V3R", "3V1R", "2V2R" }) do
                local layout = L.intermissionPanel({
                    wordText = ns.Locale.t("state.word." .. state),
                    wordState = state,
                    showRedo = true,
                })
                local id = L.wordBlockId(state)
                local word = blockOf(layout, id)
                assert.is_truthy(word, ("%s / %s : le mot manque"):format(lang, state))
                assert.are.equal(L.WORD_FONT_FILE, word.fontFile, ("%s / %s : fichier de police"):format(lang, state))
                assert.are.equal(L.wordFontSize(state), word.fontSize, ("%s / %s : taille"):format(lang, state))
                assert.is_true(word.fontSize >= 44, ("%s / %s : mot trop petit"):format(lang, state))
                if state == "2V2R" then
                    assert.is_true(word.fontSize >= 64, lang .. " : BOSS doit valoir au moins 64 px")
                    -- Le plus GROS texte du module : aucun style de texte n'a une
                    -- police plus haute que BOSS.
                    for style, font in pairs(L.FONTS) do
                        assert.is_true(word.fontSize >= font.height, "BOSS (" .. word.fontSize .. " px) plus petit que le style " .. style)
                    end
                end
                -- JAMAIS TRONQUE, en FR comme en EN : le mot tient dans la largeur
                -- UTILE du panneau (les marges laterales sont exclues) et le
                -- panneau s'est elargi pour lui. Le bloc `nowrap` interdit de le
                -- couper en deux lignes.
                local drawn = L.wordWidth(word.text, word.style)
                assert.is_true(
                    drawn <= (layout.width - (2 * L.MARGIN_X)),
                    ("%s / %s : « %s » (%d px dessines) deborde du panneau (%d px)"):format(lang, state, word.text, drawn, layout.width)
                )
                assert.is_true(word.width <= (layout.width - (2 * L.MARGIN_X)), lang .. " / " .. state)
                assert.is_true(word.nowrap == true, lang .. " / " .. state .. " : le mot doit rester sur une ligne")
                assert.are.equal("", problemsOf(L, layout), lang .. " / " .. state)
            end
        end
    end)

    it("le panneau d'intermission n'a AUCUN bouton d'action : ni OK, ni Fermer", function()
        -- Le panneau de placement n'affiche plus QUE l'illustration (raid lead :
        -- « aucun bouton ») et la validation passe par `/gideon inter ok` : il ne
        -- reste donc aucun bouton OK. Le bouton « Fermer » avait deja disparu au
        -- profit de la croix. CORRIGER reste, seul, dans sa ligne d'actions.
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local afterClick = L.intermissionPanel({
                wordText = ns.Locale.t("state.word.1V3R"),
                wordState = "1V3R",
                showRedo = true,
            })
            local row = blockOf(afterClick, "actions")
            assert.is_truthy(row, lang .. " : la ligne de CORRIGER a disparu")
            assert.are.equal(1, #row.items, lang .. " : un bouton de trop dans la ligne d'actions")
            assert.are.equal("redo", row.items[1].id, lang)
            assert.is_nil(rowItemOf(afterClick, "actions", "ok"), lang)
            assert.is_nil(rowItemOf(afterClick, "actions", "close"), lang)
            assert.are.equal("", problemsOf(L, afterClick), lang)
            -- Sans CORRIGER, il n'y a plus AUCUNE ligne d'actions.
            local plain = L.intermissionPanel({ wordText = ns.Locale.t("state.word.1V3R"), wordState = "1V3R" })
            assert.is_nil(blockOf(plain, "actions"), lang .. " : une ligne d'actions traine")
            -- Et le panneau de placement : l'illustration et son bouton OK, RIEN
            -- d'autre - aucune composition, aucun Fermer.
            local placement = L.placementPanel()
            assert.are.equal(2, #placement.blocks, lang .. " : le panneau de placement doit avoir 2 blocs")
            for index = 1, #placement.blocks do
                local block = placement.blocks[index]
                local known = block.id == L.PLACEMENT_BLOCK_ID or block.id == L.PLACEMENT_OK_BLOCK_ID
                assert.is_true(known, lang .. " : un bouton etranger traine sur le panneau de placement")
                if block.kind == "button" then
                    assert.are.equal(L.PLACEMENT_OK_BLOCK_ID, block.id, lang .. " : seul le bouton OK est autorise")
                    assert.are.equal(ns.Locale.t("ui.placementOk"), block.text, lang)
                end
            end
        end
    end)

    it("buttonSize suit le libelle le plus long et le nombre de lignes", function()
        local shortWidth = L.buttonSize("OK")
        local longWidth = L.buttonSize(string.rep("A", 30))
        assert.is_true(longWidth > shortWidth, "un libelle plus long doit donner un bouton plus large")
        -- Un libelle court garde la taille minimale cliquable.
        assert.are.equal(L.BUTTON_MIN_WIDTH, shortWidth)
        local _, shortHeight = L.buttonSize("OK")
        assert.is_true(shortHeight >= L.BUTTON_MIN_HEIGHT, "hauteur minimale cliquable")
        -- Trois lignes explicites : le bouton grandit en hauteur.
        local oneLine = L.buttonSize("1V3R")
        local threeLines = L.buttonSize("1 vert + 3 rouges\n1V3R\nnumero : 1 ou 3")
        assert.is_true(threeLines > oneLine)
        -- La ligne la PLUS LONGUE decide (pas la concatenation des lignes).
        assert.are.equal(L.buttonSize("aaaa"), L.buttonSize("aaaa\nbb"))
        -- Les planchers demandes sont respectes.
        local flooredWidth, flooredHeight = L.buttonSize("OK", "button", 300, 90)
        assert.are.equal(300, flooredWidth)
        assert.are.equal(90, flooredHeight)
    end)
end)

describe("Layout : panneau principal /gideon (ordre, bords, deux langues)", function()
    local ns = wowenv.loadCore()
    local L = ns.Layout

    before_each(function()
        ns.Locale.setActive("en")
    end)

    it("fige l'ORDRE des boutons : PLACE, PING, SIM-INTER, LOCK", function()
        -- L'ordre est une donnee PURE de Core/, appliquee telle quelle par UI/.
        assert.are.same({ "place", "simPing", "simInter", "lock" }, L.MAIN_PANEL_ORDER)
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = L.mainPanel({ bodyLines = { "Aucun plan hors jeu charge (optionnel)." } })
            local order = {}
            for index = 1, #layout.blocks do
                local block = layout.blocks[index]
                if block.kind == "button" then
                    order[#order + 1] = block.id
                end
            end
            assert.are.same({ "place", "simPing", "simInter", "lock" }, order, "ordre des boutons en " .. lang)
            -- Le flux d'abord, l'utilitaire EN DERNIER et mis a part.
            local lock = blockOf(layout, "lock")
            assert.is_true(lock.gapBefore > 0, "le verrouillage doit etre separe")
            assert.is_true(lock.top < blockOf(layout, "simInter").bottom)
            assert.are.equal("", problemsOf(L, layout))
        end
    end)

    it("aligne les quatre boutons (meme largeur, flux espace regulierement)", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = L.mainPanel({})
            local place, ping, inter, lock =
                blockOf(layout, "place"), blockOf(layout, "simPing"), blockOf(layout, "simInter"), blockOf(layout, "lock")
            assert.are.equal(place.width, ping.width, lang)
            assert.are.equal(ping.width, inter.width, lang)
            assert.are.equal(inter.width, lock.width, lang)
            -- Espacement REGULIER entre les trois boutons du flux...
            assert.are.equal(L.GAP, place.bottom - ping.top)
            assert.are.equal(L.GAP, ping.bottom - inter.top)
            -- ... et un espace PLUS GRAND avant l'utilitaire.
            assert.are.equal(L.GAP + L.MAIN_PANEL_UTILITY_GAP, inter.bottom - lock.top)
        end
    end)

    it("garde les libelles COURTS et dans le cadre, dans les deux langues", function()
        assert.are.equal("PLACE INTERMISSION PANEL", ns.Locale.t("panel.placeButton", "en"))
        assert.are.equal("PLACER LE PANNEAU", ns.Locale.t("panel.placeButton", "fr"))
        assert.are.equal("SIM: PING YOURSELF", ns.Locale.t("panel.simPingButton", "en"))
        assert.are.equal("SIMULATION : TE PINGER", ns.Locale.t("panel.simPingButton", "fr"))
        assert.are.equal("SIM: INTERMISSION GROUP", ns.Locale.t("panel.simInterButton", "en"))
        assert.are.equal("SIMULATION : GROUPE INTER", ns.Locale.t("panel.simInterButton", "fr"))
        assert.are.equal("LOCK PANEL", ns.Locale.t("panel.lockButton", "en"))
        assert.are.equal("VERROUILLER", ns.Locale.t("panel.lockButton", "fr"))

        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            for _, locked in ipairs({ false, true }) do
                local layout = L.mainPanel({ bodyLines = { "plan" }, locked = locked })
                assert.are.equal("", problemsOf(L, layout), lang .. " / locked=" .. tostring(locked))
                assert.is_true(layout.width >= L.MAIN_PANEL_WIDTH)
                for index = 1, #layout.blocks do
                    local block = layout.blocks[index]
                    local left, right = L.bounds(block, layout)
                    assert.is_true(left >= 0, block.id .. " deborde a gauche")
                    assert.is_true(right <= layout.width, block.id .. " deborde a droite")
                end
            end
        end
    end)

    it("grandit avec un plan long sans rien faire sortir du cadre", function()
        ns.Locale.setActive("fr")
        local short = L.mainPanel({ bodyLines = { "Aucun plan hors jeu charge (optionnel)." } })
        local long = L.mainPanel({ bodyLines = bodyLines(14) })
        assert.is_true(long.height > short.height)
        assert.are.equal("", problemsOf(L, long))
        local body = blockOf(long, "body")
        assert.is_true(body.bottom >= -long.height)
        -- Le corps est sous le titre et au-dessus du premier bouton.
        assert.is_true(body.top < blockOf(long, "title").bottom)
        assert.is_true(body.bottom > blockOf(long, "place").top)
    end)
end)

describe("Layout : panneau d'intermission (images, ordre fige, deux langues)", function()
    local ns = wowenv.loadCore()
    local L, I, S, T = ns.Layout, ns.Intermission, ns.Simulation, ns.Textures

    before_each(function()
        ns.Locale.setActive("en")
    end)

    --- Le plan du panneau pour l'etat courant, exactement comme UI/ le construit.
    local function planFor(opts)
        return L.intermissionPanel(opts)
    end

    --- Les blocs de TEXTE d'un plan (le panneau n'en doit contenir qu'un seul,
    --- apres le clic, et aucun avant).
    local function textBlocks(layout)
        local found = {}
        for index = 1, #layout.blocks do
            if layout.blocks[index].kind == "text" then
                found[#found + 1] = layout.blocks[index]
            end
        end
        return found
    end

    it("empile les trois IMAGES, VERTICALEMENT, dans l'ordre fige", function()
        -- L'ordre est une DONNEE DE CORE (raid lead : « 3 verts + 1 rouge, puis
        -- 2 verts + 2 rouges, puis 1 vert + 3 rouges ») : la couche de rendu
        -- l'applique telle quelle, ce test le fige.
        assert.are.same({ "3V1R", "2V2R", "1V3R" }, L.INTERMISSION_CHOICE_ORDER)
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = planFor({ showChoices = true })
            assert.are.equal("", problemsOf(L, layout), lang)
            local previous = nil
            for index = 1, #L.INTERMISSION_CHOICE_ORDER do
                local key = L.INTERMISSION_CHOICE_ORDER[index]
                local block = blockOf(layout, "choice" .. index)
                assert.is_truthy(block, ("choice%d manquant en %s"):format(index, lang))
                assert.are.equal("image", block.kind, lang)
                assert.are.equal(key, block.state, lang)
                -- Le bouton PORTE l'image de sa composition : le chemin vient de
                -- Core/Textures.lua, personne ne le recopie.
                assert.are.equal(T.pathFor(key), block.texture, lang)
                -- L'image garde le ratio de son fichier : aucun orbe ecrase.
                local width, height = T.sizeFor(key)
                assert.is_true(math.abs(block.width / block.height - width / height) < 0.03, lang .. " / " .. key)
                -- EMPILES : chaque bouton est SOUS le precedent, sans trou beant.
                if previous ~= nil then
                    assert.is_true(block.top < previous.bottom, lang .. " / " .. key .. " recouvre le bouton du dessus")
                    assert.are.equal(L.GAP, previous.bottom - block.top, lang)
                end
                previous = block
            end
            -- Le dernier bouton reste DANS le cadre, avec la marge basse.
            assert.is_true(previous.bottom >= -layout.height, lang)
        end
    end)

    it("n'affiche AUCUN texte avant le clic (deux langues)", function()
        -- Consigne du raid lead : « enleve tout le blabla ». Le panneau ne montre
        -- plus ni titre, ni etat, ni role, ni action, ni rappel de touche.
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = planFor({ showChoices = true })
            assert.are.equal("", problemsOf(L, layout), lang)
            assert.are.equal(0, #textBlocks(layout), lang .. " : un texte est affiche avant le clic")
            for _, id in ipairs({ "title", "state", "headline", "pingBanner", "body" }) do
                assert.is_nil(blockOf(layout, id), lang .. " : le bloc " .. id .. " existe encore")
            end
            -- Le bouton texte "Fermer" a disparu lui aussi : la croix ferme.
            assert.is_nil(rowItemOf(layout, "actions", "close"), lang)
            -- Le panneau ne contient QUE les trois images : aucun bloc d'action (le
            -- bouton "Fermer" a disparu) et aucun texte. La croix et le
            -- deplacement du panneau ne sont pas des blocs du plan.
            assert.are.equal(3, #layout.blocks, lang)
        end
    end)

    it("apres le clic : UN SEUL mot, taille et couleur du theme", function()
        -- Consigne du raid lead : « apres le clic, un seul mot ». Le mot exact
        -- vient de Core/Locale (EN officiel + FR du raid lead), sa TAILLE et sa
        -- COULEUR du theme de Core/Layout ; le bouton CORRIGER reste.
        local cases = {
            { state = "1V3R", en = "Ping", fr = "Ping", color = "GREEN" },
            { state = "2V2R", en = "Boss", fr = "BOSS", color = "BOSS" },
            { state = "3V1R", en = "Chaser", fr = "Chasseur", color = "GREEN" },
        }
        for _, case in ipairs(cases) do
            for _, lang in ipairs({ "en", "fr" }) do
                ns.Locale.setActive(lang)
                local state = I.newState()
                I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
                I.declare(state, case.state)
                local snap = I.snapshot(state, "color")
                -- Le clic a bien masque les trois images cote Core...
                assert.is_false(snap.showButtons, lang .. " / " .. case.state)
                -- ... et Core fournit le mot ET l'etat qui le colore.
                assert.are.equal(case[lang], snap.word, lang .. " / " .. case.state)
                assert.are.equal(case.state, snap.wordKey, lang .. " / " .. case.state)
                local layout = planFor({ wordText = snap.word, wordState = snap.wordKey, showRedo = snap.showRedo })
                assert.are.equal("", problemsOf(L, layout), lang .. " / " .. case.state)
                -- UN SEUL bloc texte dans tout le panneau : le mot.
                local texts = textBlocks(layout)
                assert.are.equal(1, #texts, lang .. " / " .. case.state .. " : le panneau affiche un texte de trop")
                local word = texts[1]
                assert.are.equal(case[lang], word.text, lang)
                assert.are.equal(L.wordBlockId(case.state), word.id, lang)
                -- CORRIGER est la, seul, et ne porte pas de texte parasite.
                local redo = rowItemOf(layout, "actions", "redo")
                assert.is_truthy(redo, lang)
                assert.are.equal(ns.Locale.t("ui.redo"), redo.text, lang)
                assert.is_nil(rowItemOf(layout, "actions", "ok"), lang)
                assert.is_nil(rowItemOf(layout, "actions", "close"), lang)
                assertStacked(layout, word.id, "actions", lang)
                -- La COULEUR vient du theme : le VERT pour les deux mots de survie
                -- (« Ping » et « Chasseur »), la couleur du mot BOSS pour la
                -- composition du milieu. Aucune valeur en dur dans UI/.
                assert.are.same(L.THEME[case.color], L.wordColor(case.state), lang .. " / " .. case.state)
                if case.color ~= "GREEN" then
                    assert.is_not.same(L.THEME.GREEN, L.wordColor(case.state), lang .. " / " .. case.state)
                end
            end
        end
    end)

    it("le vert du theme est VERT, et le mot BOSS est le plus gros element", function()
        -- Une couleur en dur dispersee dans UI/ est ce qui a casse la lisibilite
        -- en jeu : elle vit ici, une seule fois, et ce test la verrouille.
        local green = L.THEME.GREEN
        assert.is_true(green.g > green.r, "le vert doit dominer le rouge")
        assert.is_true(green.g > green.b, "le vert doit dominer le bleu")
        assert.is_true(green.g >= 0.75, "le vert doit etre franc, pas pastel")
        assert.are.equal(green.r, green.b, "vert pur : autant de rouge que de bleu")
        -- "huge" est la PLUS GRANDE police du catalogue de Core/ : le mot BOSS est
        -- donc le plus gros element TEXTUEL que la fenetre puisse afficher.
        for name, font in pairs(L.FONTS) do
            assert.is_true(font.height <= L.FONTS[L.WORD_STYLE_BIG].height, name .. " depasse la police du mot BOSS")
        end
        local big = L.intermissionPanel({ wordText = "BOSS", wordState = "2V2R", showRedo = true })
        local small = L.intermissionPanel({ wordText = "Ping", wordState = "1V3R", showRedo = true })
        local bigWord = blockOf(big, L.wordBlockId("2V2R"))
        local smallWord = blockOf(small, L.wordBlockId("1V3R"))
        assert.are.equal(L.WORD_STYLE_BIG, bigWord.style)
        assert.are.equal(L.WORD_STYLE, smallWord.style)
        assert.is_true(bigWord.height > smallWord.height, "le mot BOSS doit etre plus grand")
        -- Plus grand que TOUT autre element TEXTUEL du panneau reel (CORRIGER).
        local redo = rowItemOf(big, "actions", "redo")
        assert.is_true(bigWord.height > redo.height, "le mot BOSS doit dominer CORRIGER")
        -- Le bandeau SIMULATION (deux lignes) n'existe QUE pendant une repetition :
        -- le mot BOSS reste le plus gros element textuel du panneau de combat, et
        -- le bandeau ne le recouvre jamais (verifie par problemsOf ci-dessus).
        local run = S.newRun()
        local view = S.forRehearsal(I.snapshot(I.newState(), "anchors"), run)
        local rehearsal = L.intermissionPanel({
            bannerLines = view.simBannerLines,
            wordText = "BOSS",
            wordState = "2V2R",
            showRedo = true,
        })
        assert.is_truthy(blockOf(rehearsal, "simBanner"), "le bandeau de repetition manque")
        assert.are.equal("", problemsOf(L, rehearsal))
        assertStacked(rehearsal, "simBanner", L.wordBlockId("2V2R"), "repetition")
    end)

    it("la REPETITION garde son bandeau SIMULATION et ses trois images", function()
        -- Retour en jeu : « le panneau de repetition n'affiche plus les 3 boutons,
        -- c'est tout son interet ». Le plan est construit ici EXACTEMENT comme
        -- UI.IntermissionRefresh le fait (meme snapshot, meme spec) : tant qu'aucune
        -- composition n'est declaree, les trois IMAGES sont la, sous le bandeau.
        local run = S.newRun()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local state = I.newState()
            I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
            local snap = S.forRehearsal(I.snapshot(state, "anchors"), run)
            assert.is_true(snap.showButtons, lang .. " : les choix doivent etre affiches")
            local layout = planFor({
                bannerLines = snap.simBannerLines,
                showChoices = snap.showButtons,
                showRedo = snap.showRedo,
            })
            assert.are.equal("", problemsOf(L, layout), lang)
            -- Le bandeau est le SEUL texte d'une repetition, et il est AU-DESSUS
            -- des trois images (bug du 4e test en jeu : le texte recouvrait le plan).
            local banner = blockOf(layout, "simBanner")
            assert.is_truthy(banner, lang)
            assert.are.equal("text", banner.kind, lang)
            assertStacked(layout, "simBanner", "choice1", lang)
            assert.are.equal(1, #textBlocks(layout), lang .. " : un texte de trop en repetition")
            -- Le bandeau ne passe pas sous la croix de fermeture.
            local _, right = L.bounds(banner, layout)
            assert.is_true(right <= layout.width - L.CROSS_OFFSET - L.CROSS_SIZE, lang)
            for index = 1, #L.INTERMISSION_CHOICE_ORDER do
                local block = blockOf(layout, "choice" .. index)
                assert.is_truthy(block, lang .. " : image " .. index .. " manquante")
                assert.are.equal(L.INTERMISSION_CHOICE_ORDER[index], block.state, lang)
            end
            -- Une fois la composition cliquee, les images disparaissent : il ne
            -- reste que le mot et CORRIGER.
            I.declare(state, "2V2R")
            local after = S.forRehearsal(I.snapshot(state, "anchors"), run)
            assert.is_false(after.showButtons, lang)
            local afterLayout = planFor({
                bannerLines = after.simBannerLines,
                wordText = after.word,
                wordState = after.wordKey,
                showRedo = after.showRedo,
            })
            assert.are.equal("", problemsOf(L, afterLayout), lang)
            assert.is_nil(blockOf(afterLayout, "choice1"), lang)
            assert.are.equal(ns.Locale.t("state.word.2V2R"), blockOf(afterLayout, "wordBig").text, lang)
            assert.is_truthy(rowItemOf(afterLayout, "actions", "redo"), lang)
            assert.is_nil(rowItemOf(afterLayout, "actions", "close"), lang)
        end
    end)

    it("mode placement : l'illustration + son bouton OK, aucun texte, rien sous la croix", function()
        -- Retour du raid lead : pendant le placement, le panneau affiche la
        -- nouvelle illustration (un repere visuel pour voir la taille et
        -- l'emplacement qu'aura la fenetre) PUIS le petit bouton OK qui enregistre
        -- la position et ferme (« Remet oui ok »). Aucun texte, aucune composition :
        -- `/gideon inter ok` fait la meme chose que le bouton, l'annulation par la
        -- croix, le deplacement par le drag.
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = L.placementPanel()
            assert.are.equal(2, #layout.blocks, lang .. " : le panneau de placement doit avoir 2 blocs")
            assert.are.equal("", problemsOf(L, layout), lang)
            -- Aucun texte : le mode placement explique en chat/README, pas a l'ecran.
            assert.are.equal(0, #textBlocks(layout), lang)
            local picture = layout.blocks[1]
            assert.are.equal("placement", picture.id, lang)
            assert.are.equal("image", picture.kind, lang)
            assert.are.equal(T.placementPath(), picture.texture, lang)
            -- L'image est dessinee en entier, a l'echelle de son fichier : le
            -- repere a donc EXACTEMENT la taille de l'illustration livree.
            assert.are.equal(T.placementSize(), picture.sourceWidth, lang)
            assert.are.equal(select(2, T.placementSize()), picture.sourceHeight, lang)
            -- Rien ne deborde (le passage sous la croix est deja couvert par
            -- problemsOf -> Layout.violations, appele plus haut).
            for index = 1, #layout.blocks do
                local block = layout.blocks[index]
                local left, blockRight = L.bounds(block, layout)
                assert.is_true(left >= 0 and blockRight <= layout.width, lang .. " / " .. block.id)
            end
        end
    end)

    it("refuse un TITRE qui reviendrait sur le panneau d'intermission", function()
        -- La regle « aucun titre residuel » est STRUCTURELLE (Layout.violations
        -- applique l'allow-list du panneau) : ce test la met a l'epreuve avec un
        -- faux titre, exactement celui que le raid lead voyait encore.
        local withTitle = L.build({
            panel = L.PANEL.INTERMISSION,
            minWidth = 300,
            blocks = {
                { id = "title", kind = "text", align = "center", style = "normal", text = "GideonRaid - Intermission Coach" },
                { id = "choice1", kind = "image", align = "center", state = "3V1R" },
            },
        })
        local titleProblems = problemsOf(L, withTitle)
        assert.is_true(contains(titleProblems, "not allowed"), titleProblems)
        assert.is_true(contains(titleProblems, "title"), titleProblems)
        -- Et les blocs LEGITIMES ne declenchent rien : le bandeau SIMULATION et le
        -- mot du clic sont les deux seuls textes autorises pendant le combat.
        for _, id in ipairs({ "simBanner", "word", "wordBig" }) do
            local legit = L.build({
                panel = L.PANEL.INTERMISSION,
                minWidth = 300,
                blocks = { { id = id, kind = "text", align = "center", style = "normal", text = "x" } },
            })
            assert.are.equal("", problemsOf(L, legit), id)
        end
        -- Le panneau de placement, lui, refuse TOUT ce qui n'est pas l'illustration.
        local withButton = L.build({
            panel = L.PANEL.PLACEMENT,
            blocks = {
                {
                    id = "placement",
                    kind = "image",
                    imageWidth = 64,
                    imageHeight = 64,
                    sourceWidth = 64,
                    sourceHeight = 64,
                    texture = "Interface\\AddOns\\GideonRaid\\Texture\\placement.tga",
                },
                { id = "ok", kind = "button", text = "OK" },
            },
        })
        local placementProblems = problemsOf(L, withButton)
        assert.is_true(contains(placementProblems, "placement panel"), placementProblems)
    end)
end)

describe("Layout : fenetre d'aide au ping (deux langues)", function()
    local ns = wowenv.loadCore()
    local L, S, I = ns.Layout, ns.Simulation, ns.Intermission

    before_each(function()
        ns.Locale.setActive("en")
    end)

    --- Le contenu REEEL de la fenetre, calcule par Core/Simulation.
    local function layoutFor(resolver)
        local view = S.pingHelpView(resolver)
        return view, L.pingHelpPanel({ lines = view.lines, keyLines = view.keyLines })
    end

    it("decrit le binding, le geste, le groupe et l'honnetete, sans debordement", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local view, layout = layoutFor()
            assert.are.equal("", problemsOf(L, layout), lang)
            local body = blockOf(layout, "body").text
            assert.is_true(contains(body, "Options > Keybindings") or contains(body, "Options > Raccourcis"), body)
            assert.is_true(contains(body, "hover YOUR OWN character frame") or contains(body, "survole TON propre cadre"), body)
            assert.is_true(contains(body, "GROUP or a RAID") or contains(body, "GROUPE ou en RAID"), body)
            assert.is_true(contains(body, "CANNOT detect a ping") or contains(body, "NE PEUT PAS detecter"), body)
            assert.is_true(contains(body, "1V3R"))
            -- Les trois pings sont listes avec leur touche (ou l'absence de touche).
            assert.are.equal(3, #view.keyLines)
            for index = 1, #view.keyLines do
                assert.is_true(contains(view.keyLines[index], I.pingLabel(S.PING_SEQUENCE[index])))
                assert.is_true(contains(view.keyLines[index], "no key bound") or contains(view.keyLines[index], "aucune touche"))
            end
        end
    end)

    it("affiche la touche reellement bindee, injectee depuis la couche rendu", function()
        ns.Locale.setActive("fr")
        local view, layout = layoutFor(function()
            return "Q"
        end)
        assert.are.equal("", problemsOf(L, layout))
        for index = 1, #view.keyLines do
            assert.is_true(contains(view.keyLines[index], "= Q"), view.keyLines[index])
        end
        -- Aucune ligne ne se chevauche, et la fenetre reste dans son cadre.
        assertStacked(layout, "keys", "close", "fr")
    end)

    it("retombe sur « aucune touche » quand le raccourci est inconnu", function()
        local view = S.pingHelpView(function()
            return nil
        end)
        for index = 1, #view.keyLines do
            assert.is_true(contains(view.keyLines[index], "no key bound"))
        end
        -- Un resolveur qui leve ne casse rien (Core/ l'appelle sous pcall).
        local broken = S.pingHelpView(function()
            error("boom")
        end)
        assert.are.equal(3, #broken.keyLines)
    end)
end)
