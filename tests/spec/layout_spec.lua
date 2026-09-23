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
            if block.kind == "button" then
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
    --- sort du bouton »).
    local function assertLabelFits(block, label)
        assert.is_number(block.width, label .. " : largeur manquante")
        assert.is_number(block.height, label .. " : hauteur manquante")
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
            { id = "placement", layout = L.intermissionPanel({ headline = "h", bodyLines = { "b" }, showOk = true }) },
            {
                id = "repetition",
                layout = L.intermissionPanel({
                    bannerLines = rehearsal.simBannerLines,
                    headline = rehearsal.headline,
                    bodyLines = rehearsal.lines,
                    showChoices = true,
                }),
            },
            {
                id = "apres-clic",
                layout = L.intermissionPanel({
                    stateText = "1V3R",
                    headline = "h",
                    pingBanner = "PING: YES",
                    bodyLines = { "b" },
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

    it("le bouton OK du mode placement est mesure, ancre et present", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = L.intermissionPanel({ headline = "h", bodyLines = { "b" }, showOk = true })
            local ok = rowItemOf(layout, "actions", "ok")
            assert.is_truthy(ok, "le bouton OK manque en " .. lang)
            assert.are.equal(ns.Locale.t("ui.ok"), ok.text)
            assert.are.equal("TOPLEFT", ok.point)
            assert.is_true(ok.width >= L.BUTTON_MIN_WIDTH)
            assert.is_true(ok.height >= L.BUTTON_MIN_HEIGHT)
            assertLabelFits(ok, "ok/" .. lang)
            -- Close est toujours la, et les deux ne se recouvrent pas.
            local close = rowItemOf(layout, "actions", "close")
            assert.is_truthy(close)
            assert.is_true(ok.x + ok.width <= close.x)
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

describe("Layout : panneau principal /gr (ordre, bords, deux langues)", function()
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

describe("Layout : panneau d'intermission (chevauchements, deux langues)", function()
    local ns = wowenv.loadCore()
    local L, I, S = ns.Layout, ns.Intermission, ns.Simulation

    before_each(function()
        ns.Locale.setActive("en")
    end)

    --- Le plan du panneau pour l'etat courant, exactement comme UI/ le construit.
    local function planFor(opts)
        return L.intermissionPanel(opts)
    end

    it("le grand etat n'est JAMAIS dessine sur le bandeau SIMULATION", function()
        local run = S.newRun()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local view = S.forRehearsal(I.snapshot(I.start(I.newState(), { leadSeconds = 0 }), "anchors"), run)
            local layout = planFor({
                bannerLines = view.simBannerLines,
                stateText = "2V2R",
                headline = view.headline,
                bodyLines = view.lines,
                showRedo = true,
            })
            assert.are.equal("", problemsOf(L, layout), lang)
            -- Le grand etat est SOUS les deux lignes du bandeau (bug du 4e test).
            assertStacked(layout, "simBanner", "state", lang)
            local state = blockOf(layout, "state")
            assert.is_true(state.bottom > -layout.height, lang)
        end
    end)

    it("phase SOMBRE : bandeau, ping, role et action ne se recouvrent pas", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local state = I.newState()
            I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
            I.tick(state, 10) -- salle obscurcie
            I.declare(state, "3V1R")
            local snap = I.snapshot(state, "color")
            local layout = planFor({
                stateText = snap.stateText,
                headline = snap.headline,
                pingBanner = snap.pingBanner,
                bodyLines = snap.lines,
                showRedo = snap.showRedo,
            })
            assert.are.equal("", problemsOf(L, layout), lang)
            assertStacked(layout, "headline", "pingBanner", lang)
            assertStacked(layout, "pingBanner", "body", lang)
            assertStacked(layout, "body", "actions", lang)
            -- Une ligne par bande : aucune adresse Y partagee.
            local seen = {}
            for index = 1, #layout.blocks do
                local block = layout.blocks[index]
                assert.is_nil(seen[block.top], "deux blocs au meme Y dans " .. lang)
                seen[block.top] = block.id
            end
        end
    end)

    it("les trois boutons de composition disparaissent apres le clic", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local withChoices = planFor({ headline = "GET READY: 2 s", bodyLines = { "un indice" }, showChoices = true })
            assert.are.equal("", problemsOf(L, withChoices), lang)
            assert.is_truthy(blockOf(withChoices, "choices"))
            -- Les trois libelles tiennent dans leur bouton et ne se touchent pas.
            local row = blockOf(withChoices, "choices")
            for index = 1, #row.items do
                local item = row.items[index]
                assert.is_true(L.wordWidth(item.text, item.style) <= item.width)
                if index > 1 then
                    assert.is_true(row.items[index - 1].x + row.items[index - 1].width <= item.x)
                end
            end
            -- Apres le clic : Core ne fournit plus la ligne de choix, donc aucun
            -- bloc : UI.ApplyLayout masque alors les trois boutons.
            local afterClick = planFor({ stateText = "1V3R", headline = "ROOM DARKENED", bodyLines = { "ROLE : ANCRE" }, showRedo = true })
            assert.is_nil(blockOf(afterClick, "choices"))
            assert.are.equal("", problemsOf(L, afterClick), lang)
            assert.is_truthy(rowItemOf(afterClick, "actions", "redo"))
        end
    end)

    it("la REPETITION affiche les trois boutons de composition (5e test en jeu)", function()
        -- Retour en jeu : « le panneau de repetition n'affiche plus les 3 boutons,
        -- c'est tout son interet ». Le plan de la repetition est construit ici
        -- EXACTEMENT comme UI.IntermissionRefresh le fait (meme snapshot, meme
        -- spec) : tant qu'aucune composition n'est declaree, la ligne de choix
        -- est la, avec les libelles de Core et une taille mesuree.
        local run = S.newRun()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local state = I.newState()
            I.start(state, { leadSeconds = 0, visibilitySeconds = 3, durationSeconds = 20 })
            local snap = S.forRehearsal(I.snapshot(state, "anchors"), run)
            assert.is_true(snap.showButtons, lang .. " : les choix doivent etre affiches")
            local layout = planFor({
                bannerLines = snap.simBannerLines,
                stateText = snap.stateText,
                headline = snap.headline,
                pingBanner = snap.pingBanner,
                bodyLines = snap.lines,
                showChoices = snap.showButtons,
                showRedo = snap.showRedo,
            })
            local row = blockOf(layout, "choices")
            assert.is_truthy(row, lang .. " : la ligne des trois compositions manque")
            assert.are.equal(#I.STATES, #row.items)
            assertStacked(layout, "body", "choices", lang)
            for index = 1, #row.items do
                local item = row.items[index]
                local key = I.STATES[index]
                local rec = I.getDeclaration(key)
                assert.are.equal("choice" .. index, item.id)
                assert.are.equal(rec.buttonLabel, item.text)
                assert.is_true(contains(item.text, key), item.text)
                assert.is_true(item.width >= L.CHOICE_MIN_WIDTH, "bouton trop etroit en " .. lang)
                assert.is_true(item.height >= L.CHOICE_MIN_HEIGHT, "bouton trop court en " .. lang)
                assert.are.equal("TOPLEFT", item.point)
            end
            -- Une fois la composition cliquee, Core ne fournit plus les choix :
            -- le panneau ne garde que le resultat et CORRIGER.
            I.declare(state, "1V3R")
            local afterSnap = S.forRehearsal(I.snapshot(state, "anchors"), run)
            assert.is_false(afterSnap.showButtons)
            local after = planFor({
                bannerLines = afterSnap.simBannerLines,
                stateText = afterSnap.stateText,
                headline = afterSnap.headline,
                pingBanner = afterSnap.pingBanner,
                bodyLines = afterSnap.lines,
                showChoices = afterSnap.showButtons,
                showRedo = afterSnap.showRedo,
            })
            assert.is_nil(blockOf(after, "choices"))
            assert.is_truthy(rowItemOf(after, "actions", "redo"))
            assert.is_truthy(rowItemOf(after, "actions", "close"))
            assert.are.equal("", problemsOf(L, after), lang)
            assert.are.equal("", problemsOf(L, layout), lang)
        end
    end)

    it("mode placement : OK et Fermer ne se recouvrent pas, dans les deux langues", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local view = I.setupView({ leadSeconds = 2, pairs = 8 })
            local layout = planFor({ headline = view.headline, bodyLines = view.lines, showOk = true })
            assert.are.equal("", problemsOf(L, layout), lang)
            local ok, close = rowItemOf(layout, "actions", "ok"), rowItemOf(layout, "actions", "close")
            assert.is_truthy(ok)
            assert.is_truthy(close)
            assert.is_true(close.x + close.width <= layout.width)
            assert.is_true(ok.x + ok.width <= close.x)
            assert.is_nil(rowItemOf(layout, "actions", "redo"))
        end
    end)

    it("le titre ne passe jamais sous la croix de fermeture", function()
        for _, lang in ipairs({ "en", "fr" }) do
            ns.Locale.setActive(lang)
            local layout = planFor({ headline = "GET READY", bodyLines = { "x" } })
            assert.are.equal("", problemsOf(L, layout), lang)
            local title = blockOf(layout, "title")
            local _, right = L.bounds(title, layout)
            assert.is_true(right <= layout.width - L.CROSS_OFFSET - L.CROSS_SIZE, lang)
        end
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
