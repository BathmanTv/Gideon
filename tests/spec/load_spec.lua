--[[--------------------------------------------------------------------------
    tests/spec/load_spec.lua   (busted)
    ETAPE 2 du plan de test : l'addon se charge sans erreur, DANS L'ORDRE DU .TOC,
    et les evenements ADDON_LOADED / PLAYER_LOGIN / ENCOUNTER_START ne levent pas.

    Le chargement passe par wowenv.loadAddon() : la liste des fichiers vient du
    .toc lui-meme, donc un fichier oublie, renomme ou mal ordonne fait echouer ce
    fichier de test (c'est le bug n°1 des addons).

    Le FLUX DE SOIREE du raid lead est verifie ici de bout en bout, avec l'horloge
    du moteur (ticker) avancee a la main :
      placement du panneau + OK -> validation ; ENCOUNTER_START = coup de depart
      du planning -> ouverture automatique avant l'intermission -> clic de la
      composition -> CORRIGER -> fermeture automatique a la fin -> reouverture a
      l'intermission suivante.
----------------------------------------------------------------------------]]
--
local stub = require("tests.support.wowapi_stub")
local wowenv = require("tests.support.wowenv")

local function contains(text, needle)
    return string.find(text, needle, 1, true) ~= nil
end

describe("chargement de l'addon", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.GideonRaidPingHelpPanel = nil
        _G.GameTooltip = nil
        _G.SlashCmdList = nil
        _G.GetBindingKey = nil
        stub.install()

        -- Meme ordre que le client : celui du .toc.
        ns = wowenv.loadAddon()
    end)

    local function messages()
        return table.concat(_G.DEFAULT_CHAT_FRAME.messages, "\n")
    end

    --- Le boss CIBLE du test. Depuis la correction du bug critique (« le panneau
    --- s'ouvre sur n'importe quel boss ») l'ouverture automatique est filtree par
    --- une allow-list d'ids d'ENCOUNTER_START, persistee et VIDE par defaut (defaut
    --- sur : aucune ouverture). Les tests du flux reel nomment donc la cible puis
    --- tirent CE boss, avec les arguments reels de l'evenement (id, nom, difficulte,
    --- taille de groupe).
    local BOSS_ID = 1234
    local BOSS_NAME = "Entombed Sentinels"

    local function setBossTarget(ids)
        _G.GideonRaidDB.intermission.bossIds = ids or { BOSS_ID }
    end

    --- Pull du boss CIBLE : la seule maniere normale d'armer le planning.
    local function pullTargetBoss()
        setBossTarget()
        stub.mainFrame():Fire("ENCOUNTER_START", BOSS_ID, BOSS_NAME, 16, 20)
    end

    --- LE bouton d'image d'une composition. L'ordre VERTICAL des trois boutons est
    --- fige par Core/Layout.INTERMISSION_CHOICE_ORDER (3V1R en haut, puis 2V2R,
    --- puis 1V3R) : les tests passent donc par la composition, jamais par un index
    --- en dur (c'est ce qui garantit qu'un clic declara bien ce que le joueur voit).
    local function buttonFor(panel, stateKey)
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            if ns.Layout.INTERMISSION_CHOICE_ORDER[index] == stateKey then
                return panel.buttons[index]
            end
        end
        return nil
    end

    it("charge tous les fichiers listes dans le .toc, dans l'ordre", function()
        local files = wowenv.tocFiles()
        assert.are.equal(13, #files)
        assert.are.equal("GideonRaid.lua", files[1])
        -- Core/Locale.lua d'abord : la couche de langue est une dependance.
        assert.are.equal("Core/Locale.lua", files[2])
        -- Core/Sound.lua juste apres Locale.lua et AVANT Config.lua : Config en
        -- resout la preference bornee (/gr sound), et il porte la table pure
        -- « etat -> fichier de son » du son d'assignation.
        assert.are.equal("Core/Sound.lua", files[3])
        -- Core/BossFilter.lua AVANT Config.lua : Config en resout l'allow-list
        -- d'ids d'encounter du filtre d'ouverture auto (dont le DEFAUT LIVRE :
        -- id 3445 + les deux noms, /gr boss <id>).
        assert.are.equal("Core/BossFilter.lua", files[4])
        -- Core/Diag.lua juste apres BossFilter.lua : il ne depend que de Locale et
        -- Sound (deja charges) et il porte le rapport de /gr diag. Il ne contient
        -- AUCUN appel client : c'est UI/Panel.lua qui lui injecte les CVars et les
        -- reponses de PlaySoundFile.
        assert.are.equal("Core/Diag.lua", files[5])
        assert.are.equal("Core/Config.lua", files[6])
        -- Core/Textures.lua APRES Intermission.lua (elle miroite ses etats) et AVANT
        -- Layout.lua, qui s'en sert pour dimensionner les trois boutons d'image.
        assert.are.equal("Core/Simulation.lua", files[9])
        assert.are.equal("Core/Textures.lua", files[10])
        -- Core/Layout.lua EN DERNIER des Core/ (il mesure les libelles), puis la
        -- couche de rendu (UI/) qui applique le tout.
        assert.are.equal("Core/Layout.lua", files[11])
        assert.are.equal("UI/Panel.lua", files[12])
        assert.are.equal("UI/Intermission.lua", files[13])
    end)

    it("expose toutes les couches attendues", function()
        assert.is_table(ns.Locale)
        assert.is_table(ns.Sound)
        assert.is_table(ns.Pairing)
        assert.is_table(ns.Config)
        assert.is_table(ns.Diag)
        assert.is_table(ns.Intermission)
        assert.is_table(ns.Simulation)
        assert.is_table(ns.Layout)
        assert.is_table(ns.UI)
        assert.is_table(ns.GR)
    end)

    it("ADDON_LOADED initialise les SavedVariables (planning inclus)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_table(_G.GideonRaidDB)
        assert.is_true(_G.GideonRaidDB.enabled)
        assert.is_table(_G.GideonRaidCharDB)
        assert.is_table(_G.GideonRaidDB.intermission)
        assert.are.same({ 46.3, 148.9, 251.5, 353.2 }, _G.GideonRaidDB.intermission.scheduleSeconds)
        assert.are.equal(2, _G.GideonRaidDB.intermission.leadSeconds)
        -- Plus aucun champ de macro dans les defaults.
        assert.is_nil(_G.GideonRaidDB.intermission.macroTargetToken)
    end)

    it("ADDON_LOADED ignore les autres addons", function()
        stub.mainFrame():Fire("ADDON_LOADED", "UnAutreAddon")
        assert.is_nil(_G.GideonRaidDB)
    end)

    it("PLAYER_LOGIN sans assignation n'echoue pas", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("PLAYER_LOGIN")
        assert.is_true(true)
    end)

    it("PLAYER_LOGIN affiche le plan si l'assignation existe", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidDB.assignment = {
            schema = 1,
            pairs = { { a = "Testeur", b = "Partenaire" } },
            plan = {
                { name = "Testeur", role = "2V2R", position = "MIDDLE" },
                { name = "Partenaire", role = "2V2R", position = "MIDDLE" },
            },
        }
        stub.mainFrame():Fire("PLAYER_LOGIN")
        local text = _G.GideonRaidPanel.body:GetText()
        assert.matches("Partenaire", text)
        assert.matches("Your partner", text)
        assert.matches("MIDDLE", text)
        assert.matches("2V2R%+2V2R", text)
        -- Plus aucune macro de ping, nulle part.
        assert.is_false(contains(text, "SendMacroPing"))
        assert.is_false(contains(text, "C_Ping"))
    end)

    it("sans plan hors jeu : phrase discrete, JAMAIS une commande inexistante", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("show")
        local text = _G.GideonRaidPanel.body:GetText()
        assert.are.equal("No out-of-game plan loaded (optional).", text)
        assert.is_false(contains(text, "roster assign"))
        assert.is_false(contains(text, "Ask GIDEON"))
        assert.is_false(contains(text, "No GIDEON assignment"))
        -- La politique de ping n'est plus affichee en permanence non plus.
        assert.is_false(contains(text, "ANCHORS"))
    end)

    it("le slash handler repond et ne leve pas", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("show")
        _G.SlashCmdList["GIDEONRAID"]("status")
        _G.SlashCmdList["GIDEONRAID"]("plan")
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        _G.SlashCmdList["GIDEONRAID"]("inter ping")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        assert.is_truthy(#_G.DEFAULT_CHAT_FRAME.messages >= 1)
    end)

    it("le menu d'aide ne renvoie plus vers une commande inexistante", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        local text = messages()
        assert.matches("/gr inter", text)
        assert.matches("place", text)
        assert.is_false(contains(text, "macro"))
        assert.is_false(contains(text, "roster assign"))
    end)

    it("mode placement : bouton du panneau principal, /gr inter ok sauvegarde et ferme", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Le mode placement n'affiche QUE l'illustration de Gideon (raid lead :
        -- « uniquement son illustration, pas de boutons ») : PAS une composition,
        -- PAS un mot, PAS un texte, PAS un bouton.
        assert.is_false(panel.buttons[1]:IsShown())
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.is_false(panel.redo:IsShown())
        assert.is_true(panel.placement:IsShown())
        assert.are.equal(ns.Textures.placementPath(), panel.placement.picture:GetTexture())
        -- Aucun bouton du tout : la validation passe par `/gr inter ok` (le bouton
        -- OK a disparu avec le reste du texte du panneau).
        assert.is_nil(panel.ok)
        _G.SlashCmdList["GIDEONRAID"]("inter ok")
        assert.is_false(panel:IsShown())
        assert.is_table(_G.GideonRaidDB.intermission.position)
        assert.matches("Placement saved", messages())
    end)

    it("/gr inter place ouvre aussi le mode placement et la CROIX annule", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Le bouton texte "Fermer" n'existe plus : la croix fait le travail.
        assert.is_nil(panel.close)
        assert.is_truthy(panel.closeCross)
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
    end)

    it("ENCOUNTER_START du boss CIBLE arme le planning sans ouvrir le panneau", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        -- Le filtre d'ouverture auto est une allow-list d'ids persistee, vide par
        -- defaut : le test NOMME donc la cible avant de tirer, comme le raid lead
        -- le fera en jeu (/gr boss <id>), et les arguments lus sont ceux reels de
        -- l'evenement.
        pullTargetBoss()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_false(panel:IsShown(), "le panneau ne s'ouvre qu'avant l'intermission")
        assert.matches("armed: 4 intermission", messages())
        assert.matches("opens 2 s before", messages())
    end)

    it("le panneau s'ouvre TOUT SEUL avant la 1re intermission (44,3 s) et ferme a la fin", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        local panel = _G.GideonRaidIntermissionPanel
        -- 40 s : toujours ferme (ouverture a 44,3 s).
        stub.fireTickers(400)
        assert.is_false(panel:IsShown())
        -- 45 s : ouvert, en attente du debut de l'intermission.
        stub.fireTickers(51)
        assert.is_true(panel:IsShown())
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_true(panel.buttons[2]:IsShown())
        assert.is_true(panel.buttons[3]:IsShown())
        assert.is_false(panel.redo:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        -- + 2 s : l'intermission commence (compte a rebours de visibilite) et
        -- + 3,5 s : salle obscurcie. L'ecran NE CHANGE PAS d'un mot : il n'y a plus
        -- AUCUN texte avant le clic (consigne du raid lead), seulement les images.
        stub.fireTickers(20)
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_false(panel.word:IsShown())
        stub.fireTickers(35)
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        -- Fin de l'intermission (duree par defaut 20 s) : fermeture automatique.
        stub.fireTickers(200)
        assert.is_false(panel:IsShown(), "le panneau se ferme tout seul a la fin")
    end)

    it("clic sur une composition : l'image du bouton, puis UN SEUL mot", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        -- Chaque bouton PORTE l'image de sa composition (le chemin vient de
        -- Core/Textures.lua) et AUCUN libelle de composition n'est dessine dessus.
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            local key = ns.Layout.INTERMISSION_CHOICE_ORDER[index]
            -- L'image est une texture ENFANT de la carte (le cadre garde donc sa
            -- bordure visible autour de l'image, raid lead : « un simple encart
            -- avec des bords »).
            assert.are.equal(ns.Textures.pathFor(key), panel.buttons[index].picture:GetTexture())
            assert.are.equal("", panel.buttons[index]:GetText(), "le bouton " .. key .. " porte un texte")
        end
        panel.buttons[2]:Click() -- 2V2R (2e bouton de l'ordre fige)
        -- UN SEUL mot, et rien d'autre : plus d'etat, plus de role, plus de ligne
        -- d'action, plus de bandeau de ping (tout le blabla a disparu).
        assert.is_true(panel.wordBig:IsShown())
        assert.are.equal(ns.Locale.t("state.word.2V2R"), panel.wordBig:GetText())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.buttons[1]:IsShown())
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        for _, gone in ipairs({ "state", "headline", "pingBanner", "body", "title", "close", "ok" }) do
            assert.is_nil(panel[gone], "l'element " .. gone .. " existe encore dans le panneau")
        end
        -- Le mot BOSS est le plus GROS texte de la fenetre : une police et une
        -- TAILLE EXPLICITES (les constantes de Core/Layout), jamais un objet de
        -- police Blizzard dont l'addon ne peut pas lire la taille hors du jeu.
        -- C'est la reponse a « le mot doit etre beaucoup plus gros » : la taille
        -- est verifiee ici, pas supposee.
        local bigFile, bigSize = panel.wordBig:GetFont()
        assert.are.equal(ns.Layout.WORD_FONT_FILE, bigFile)
        assert.are.equal(ns.Layout.WORD_SIZE_BIG, bigSize)
        assert.is_true(bigSize >= 64, "BOSS doit valoir au moins 64 px (recu " .. tostring(bigSize) .. ")")
        local smallFile, smallSize = panel.word:GetFont()
        assert.are.equal(ns.Layout.WORD_FONT_FILE, smallFile)
        assert.are.equal(ns.Layout.WORD_SIZE, smallSize)
        assert.is_true(smallSize >= 44, "PING/CHASSEUR doivent valoir au moins 44 px")
        assert.is_true(bigSize > smallSize, "BOSS doit rester le plus gros mot")
        -- AUCUN objet de police : sinon la taille reelle echapperait au test.
        assert.is_nil(panel.word:GetFontObject())
        assert.is_nil(panel.wordBig:GetFontObject())
    end)

    it("bouton CORRIGER : ramene aux trois choix, utilisable plusieurs fois", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        local function wordText()
            if panel.wordBig:IsShown() then
                return panel.wordBig:GetText()
            end
            return panel.word:GetText()
        end
        panel.buttons[1]:Click() -- 3V1R (1er bouton de l'ordre fige)
        assert.are.equal(ns.Locale.t("state.word.3V1R"), wordText())
        assert.is_true(panel.redo:IsShown())
        assert.is_false(panel.buttons[1]:IsShown())
        panel.redo:Click()
        -- Retour aux trois images, plus aucun mot.
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_true(panel.buttons[2]:IsShown())
        assert.is_true(panel.buttons[3]:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.is_false(panel.redo:IsShown())
        -- Deuxieme corrige, puis troisieme : toujours possible.
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(ns.Locale.t("state.word.1V3R"), wordText())
        panel.redo:Click()
        buttonFor(panel, "2V2R"):Click()
        assert.are.equal(ns.Locale.t("state.word.2V2R"), wordText())
        panel.redo:Click()
        buttonFor(panel, "3V1R"):Click()
        assert.are.equal(ns.Locale.t("state.word.3V1R"), wordText())
    end)

    it("le panneau ne montre PLUS la touche de ping (tout le texte est parti)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GetBindingKey = function(name)
            if name == "PING_WARNING" then
                return "Q"
            end
            return nil
        end
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click()
        -- Le clic affiche UN SEUL mot : ni le mot "PING", ni la touche bindi, ni la
        -- moindre consigne. La touche reste accessible dans /gr sim ping.
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        assert.is_false(panel.word:GetText():find("Q", 1, true) ~= nil)
        assert.is_nil(panel.body)
    end)

    it("sans raccourci bindi, le rendu ne depend PAS de GetBindingKey", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_nil(_G.GetBindingKey, "le harnais ne definit PAS GetBindingKey")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        assert.is_false(panel.buttons[1]:IsShown())
    end)

    it("survit a un GetBindingKey qui leve une erreur", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GetBindingKey = function()
            error("GetBindingKey a leve")
        end
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
    end)

    it("rouvre le panneau a l'intermission SUIVANTE (cycle complet)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        local panel = _G.GideonRaidIntermissionPanel
        stub.fireTickers(450) -- 1re intermission, panneau ouvert
        assert.is_true(panel:IsShown())
        stub.fireTickers(255) -- fin de l'intermission (20 s) : ferme
        assert.is_false(panel:IsShown())
        -- La 2e intermission du planning est a 148,9 s : ouverture a 146,9 s.
        stub.fireTickers(740) -- 144,5 s : encore ferme
        assert.is_false(panel:IsShown())
        stub.fireTickers(25) -- 147,0 s : reouverture automatique
        assert.is_true(panel:IsShown(), "reouverture automatique a l'intermission suivante")
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.is_false(panel.redo:IsShown())
    end)

    it("ENCOUNTER_END ferme le panneau et desarme le planning", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        stub.mainFrame():Fire("ENCOUNTER_END")
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        -- Plus aucune ouverture apres la fin du combat.
        stub.fireTickers(1000)
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
    end)

    it("publie la decision du joueur dans les SavedVariables (lue par le kit diag)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        buttonFor(_G.GideonRaidIntermissionPanel, "3V1R"):Click()
        local decision = _G.GideonRaidDB.intermission.lastDecision
        assert.is_not_nil(decision)
        assert.equals("3V1R", decision.composition)
        assert.equals(1758500000, decision.at)
        assert.equals("2026-09-22 21:00:00", decision.clock)
        assert.equals("coach-panel", decision.source)
    end)

    it("une declaration ambigue n'est ni acceptee ni publiee (aucune saisie de chat)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        _G.SlashCmdList["GIDEONRAID"]("inter 1")
        assert.matches("ambiguous", messages())
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision)
    end)

    it("respecte la desactivation du module (y compris le planning)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter off")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        assert.matches("disabled", _G.DEFAULT_CHAT_FRAME.messages[#_G.DEFAULT_CHAT_FRAME.messages])
        pullTargetBoss()
        stub.fireTickers(600)
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown(), "desactive = aucune ouverture automatique")
    end)

    it("le panneau n'affiche AUCUN texte a l'ouverture, et aucune valeur dynamique", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        -- Plus de pavé : avant le clic, TOUT le texte du panneau est vide (les deux
        -- FontStrings du mot sont cachees et vides).
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.are.equal("", panel.word:GetText())
        assert.are.equal("", panel.wordBig:GetText())
        for _, gone in ipairs({ "body", "state", "headline", "pingBanner", "title" }) do
            assert.is_nil(panel[gone], "l'element " .. gone .. " existe encore")
        end
    end)

    -- ------------------------------------------------------------------------
    -- CROIX DE FERMETURE ("X") : panneau principal ET panneau d'intermission
    -- ------------------------------------------------------------------------
    it("les deux panneaux portent une croix X avec un tooltip court et traduit", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_table(main.closeCross)
        assert.is_table(panel.closeCross)
        assert.are.equal("X", main.closeCross:GetText())
        assert.are.equal("X", panel.closeCross:GetText())

        -- Survol LISIBLE : court, et dans la langue servie (Core/Locale.lua).
        _G.GameTooltip = {
            SetOwner = function() end,
            SetText = function(self, text)
                self.text = text
            end,
            Show = function() end,
            Hide = function() end,
        }
        main.closeCross:GetScript("OnEnter")(main.closeCross)
        assert.are.equal("Close", _G.GameTooltip.text)
        _G.SlashCmdList["GIDEONRAID"]("lang fr")
        main.closeCross:GetScript("OnEnter")(main.closeCross)
        assert.are.equal("Fermer", _G.GameTooltip.text)
        main.closeCross:GetScript("OnLeave")(main.closeCross)
        -- Hors client (aucun GameTooltip) : le survol ne leve jamais.
        _G.GameTooltip = nil
        main.closeCross:GetScript("OnEnter")(main.closeCross)

        -- La croix ferme le panneau principal.
        _G.SlashCmdList["GIDEONRAID"]("show")
        assert.is_true(main:IsShown())
        main.closeCross:Click()
        assert.is_false(main:IsShown())
    end)

    it("la croix de l'intermission ferme, et le tour reste intact (fermeture + reouverture auto)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        local panel = _G.GideonRaidIntermissionPanel
        stub.fireTickers(450)
        assert.is_true(panel:IsShown())
        panel.closeCross:Click()
        assert.is_false(panel:IsShown(), "une fermeture a la main doit etre possible")
        -- L'horloge n'est PAS desarmee : le panneau se ferme tout seul a la fin
        -- et se ROUVRE a l'intermission suivante.
        stub.fireTickers(260)
        assert.is_false(panel:IsShown())
        stub.fireTickers(760)
        assert.is_true(panel:IsShown(), "reouverture automatique a l'intermission suivante")
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
    end)

    it("en placement, la croix ANNULE", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Le panneau porte l'illustration et RIEN d'autre : aucun bouton (le
        -- bouton OK a disparu, `/gr inter ok` valide desormais).
        assert.is_true(panel.placement:IsShown())
        assert.is_nil(panel.ok)
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
        -- Annulation : le placement n'est PAS valide.
        assert.is_false(contains(messages(), "Placement saved"))
    end)

    -- ------------------------------------------------------------------------
    -- SIMULATION : entrees, refus et isolation du flux reel
    -- ------------------------------------------------------------------------
    it("/gr sim affiche l'aide et REFUSE une sous-commande inconnue", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim")
        assert.matches("/gr sim", messages())
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim bidon")
        assert.matches("Unknown simulation", messages())
        -- L'aide generale annonce la simulation, et rien n'a ete lance.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        assert.matches("/gr sim", messages())
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        -- La fenetre d'aide au ping n'est meme pas construite : rien n'a ete lance.
        assert.is_nil(_G.GideonRaidPingHelpPanel)
    end)

    it("les deux entrees SIMULATION sont sur le panneau principal", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        assert.matches("SIM:", main.simInter:GetText())
        assert.matches("SIM:", main.simPing:GetText())
        assert.matches("PING YOURSELF", main.simPing:GetText())
        main:Show()
        main.simInter:Click()
        -- 4e retour en jeu : la repetition s'ouvre TOUT DE SUITE.
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        assert.matches("opens RIGHT AWAY", messages())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        main.simPing:Click()
        assert.is_true(_G.GideonRaidPingHelpPanel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.is_false(_G.GideonRaidPingHelpPanel:IsShown())
    end)

    it("refuse de melanger une repetition et le flux reel, et n'arme jamais la timeline", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        -- Flux reel en cours (intermission lancee a la main) : repetition refusee.
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        assert.matches("Simulation refused", messages())
        assert.is_false(_G.GideonRaidIntermissionPanel.simBanner:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("inter stop")
        -- Repetition en cours : le placement et l'intermission manuelle sont refuses.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        assert.matches("Refused: a simulation is already running", messages())
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        assert.matches("Refused: a simulation is already running", messages())
        -- ENCOUNTER_START ferme la repetition et arme le planning normalement.
        pullTargetBoss()
        assert.matches("Encounter started", messages())
        assert.matches("armed: 4 intermission", messages())
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.matches("No simulation running", messages())

        -- La fenetre d'aide au ping n'est PAS une simulation : elle ne bloque
        -- aucun flux (mais elle est refusee pendant un combat en cours), et le
        -- combat la referme.
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        assert.matches("Simulation refused", messages())
        -- Fin du combat : le planning pre-calcule est desarme, et l'aide repart.
        stub.mainFrame():Fire("ENCOUNTER_END")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        local help = _G.GideonRaidPingHelpPanel
        assert.is_true(help:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown(), "l'aide au ping ne bloque pas le placement")
        _G.GideonRaidIntermissionPanel.closeCross:Click()
        pullTargetBoss()
        assert.is_false(help:IsShown())
        assert.matches("Encounter started", messages())
    end)

    -- ------------------------------------------------------------------------
    -- SIMULATION "Groupe inter" : ouverture IMMEDIATE, fermeture PAR LE JOUEUR
    -- ------------------------------------------------------------------------
    it("SIMULATION groupe inter : ouverture immediate, sans horloge ni fermeture auto", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        -- 4e retour en jeu : plus de delai, le panneau est OUVERT tout de suite.
        assert.is_true(panel:IsShown())
        assert.matches("opens RIGHT AWAY", messages())
        assert.is_true(contains(messages(), "NOT armed"))
        -- AUCUNE horloge : la repetition ne fait avancer aucun temps.
        assert.are.equal(0, #stub.tickers)
        -- Bandeau SIMULATION (deux lignes) et titre de repetition : aucun compte
        -- a rebours contradictoire ("sans boss, pas d'orbe a lire").
        local banner = panel.simBanner:GetText()
        assert.is_true(contains(banner, "SIMULATION - NO BOSS, NO RAID"))
        assert.is_true(contains(banner, "YOU CLOSE THE PANEL YOURSELF"))
        -- Le blabla a disparu : le bandeau SIMULATION est le SEUL texte de la
        -- repetition, et aucune composition n'est encore declaree.
        assert.is_nil(panel.headline)
        assert.is_nil(panel.body)
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_true(panel.buttons[2]:IsShown())
        assert.is_true(panel.buttons[3]:IsShown())

        -- Le geste complet du joueur : composition, CORRIGER, composition.
        buttonFor(panel, "1V3R"):Click()
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        assert.is_true(panel.word:IsShown())
        assert.is_true(panel.redo:IsShown())
        assert.is_false(panel.buttons[1]:IsShown(), "les trois choix disparaissent apres le clic")
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        panel.redo:Click()
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        buttonFor(panel, "3V1R"):Click()
        assert.are.equal(ns.Locale.t("state.word.3V1R"), panel.word:GetText())
        -- Une repetition ne publie AUCUNE decision : le kit de diagnostic ne doit
        -- jamais lire une repetition comme un vrai choix.
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision)

        -- Elle ne se ferme PAS toute seule : aucun temps ne tourne.
        stub.fireTickers(5000)
        assert.is_true(panel:IsShown())
        -- ... c'est le JOUEUR qui la ferme (la croix), et le chat le dit.
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
        assert.matches("Simulation closed", messages())
        assert.matches("no boss, no raid", messages())
        -- ISOLATION : la timeline ENCOUNTER_START n'a jamais ete armee ("coach
        -- armed" absent) et l'etat REEL de l'intermission est reste IDLE.
        assert.is_false(contains(messages(), "coach armed"))
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("inter status")
        assert.matches("phase IDLE", messages())
        -- ... et le flux reel fonctionne encore normalement apres la repetition.
        pullTargetBoss()
        assert.matches("armed: 4 intermission", messages())
        stub.fireTickers(450)
        assert.is_true(panel:IsShown())
        assert.is_false(panel.simBanner:IsShown(), "plus de bandeau SIMULATION hors repetition")
    end)

    it("5e test : les trois boutons d'image sont affiches, poses et fonctionnels", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        local layout = ns.Layout
        assert.is_true(panel:IsShown())
        for index = 1, #layout.INTERMISSION_CHOICE_ORDER do
            local key = layout.INTERMISSION_CHOICE_ORDER[index]
            local button = panel.buttons[index]
            assert.is_true(button:IsShown(), "le bouton de composition " .. key .. " doit etre affiche")
            -- ANCRE : le bug du 5e test etait une ancre NULLE (SetPoint(nil) leve
            -- en jeu, l'applier s'arretait et ces trois boutons disparaissaient).
            assert.are.equal("TOP", button.__point[1])
            assert.is_number(button.__point[2])
            assert.is_number(button.__point[3])
            -- LE BOUTON EST UN ENCART A BORDS : un fond sombre discret et une
            -- bordure fine (le style vient de Core/Layout.BUTTON_STYLES, il n'est
            -- pas ecrit ici), AUCUN texte, et la taille = l'image ajustee PLUS le
            -- padding du style de chaque cote.
            local pictureWidth, pictureHeight = ns.Textures.displaySize(key, layout.CHOICE_IMAGE_MAX)
            local padding = layout.cardPadding(layout.CHOICE_STYLE)
            assert.is_true(padding > 0, "le style d'encart doit reserver une marge interieure")
            assert.are.equal(pictureWidth + (2 * padding), button.__width, key .. " : largeur de l'encart")
            assert.are.equal(pictureHeight + (2 * padding), button.__height, key .. " : hauteur de l'encart")
            local style = layout.style(layout.CHOICE_STYLE)
            assert.is_truthy(button.__backdrop, key .. " : l'encart n'a pas de fond")
            assert.are.equal(style.edgeFile, button.__backdrop.edgeFile, key .. " : pas de bordure")
            assert.are.equal(style.bgFile, button.__backdrop.bgFile, key .. " : pas de fond")
            local br, bg, bb, ba = button:GetBackdropBorderColor()
            assert.are.equal(style.border.r, br, key .. " : couleur de bordure au repos")
            assert.are.equal(style.border.g, bg, key .. " : couleur de bordure au repos")
            assert.are.equal(style.border.b, bb, key .. " : couleur de bordure au repos")
            assert.are.equal(style.border.a, ba, key .. " : couleur de bordure au repos")
            local bgR, bgG, bgB, bgA = button:GetBackdropColor()
            assert.are.equal(style.background.r, bgR, key .. " : fond discret")
            assert.are.equal(style.background.g, bgG, key .. " : fond discret")
            assert.are.equal(style.background.b, bgB, key .. " : fond discret")
            assert.are.equal(style.background.a, bgA, key .. " : fond discret")
            -- L'IMAGE EST DESSINEE EN ENTIER, DANS la bordure : une texture ENFANT
            -- du cadre, posee aux QUATRE coins a `padding` de la bordure.
            assert.are.equal(ns.Textures.pathFor(key), button.picture:GetTexture(), key)
            local points = button.picture.__points
            assert.is_true(type(points) == "table" and #points == 2, key .. " : image non ancree aux 4 coins")
            assert.are.equal("TOPLEFT", points[1][1], key .. " : coin haut-gauche")
            assert.are.equal(padding, points[1][4], key .. " : image collee a la bordure")
            assert.are.equal(-padding, points[1][5], key .. " : image collee a la bordure")
            assert.are.equal("BOTTOMRIGHT", points[2][1], key .. " : coin bas-droite")
            assert.are.equal(-padding, points[2][4], key .. " : image collee a la bordure")
            assert.are.equal(padding, points[2][5], key .. " : image collee a la bordure")
            assert.are.equal("", button:GetText(), key .. " : un texte est dessine sur l'image")
        end
        -- La croix est la (elle ferme le panneau) ; OK a disparu (il valait une
        -- POSITION et `/gr inter ok` le remplace : le panneau de placement
        -- n'affiche plus aucun bouton). La croix est du "chrome" attache au coin
        -- du cadre, hors plan (Core ne la place pas).
        assert.is_truthy(panel.closeCross)
        assert.is_nil(panel.ok)
        -- CHAQUE bouton remplit sa fonction : UN SEUL mot, celui du raid lead.
        local expected = {
            { state = "3V1R", word = "state.word.3V1R", big = false },
            { state = "2V2R", word = "state.word.2V2R", big = true },
            { state = "1V3R", word = "state.word.1V3R", big = false },
        }
        for _, case in ipairs(expected) do
            buttonFor(panel, case.state):Click()
            local drawn = case.big and panel.wordBig or panel.word
            assert.is_true(drawn:IsShown(), case.state .. " : le mot doit etre affiche")
            assert.are.equal(ns.Locale.t(case.word), drawn:GetText(), case.state)
            -- ... et RIEN d'autre : l'autre FontString du mot reste cachee.
            assert.is_false((case.big and panel.word or panel.wordBig):IsShown(), case.state)
            for index = 1, #layout.INTERMISSION_CHOICE_ORDER do
                assert.is_false(panel.buttons[index]:IsShown(), "les trois choix disparaissent apres le clic")
            end
            -- CORRIGER ramene les trois boutons et efface le mot.
            assert.is_true(panel.redo:IsShown())
            panel.redo:Click()
            assert.is_false(panel.word:IsShown())
            assert.is_false(panel.wordBig:IsShown())
            assert.is_false(panel.redo:IsShown())
            for index = 1, #layout.INTERMISSION_CHOICE_ORDER do
                assert.is_true(panel.buttons[index]:IsShown(), "CORRIGER doit ramener les trois choix")
            end
        end
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    it("encart a bords : au survol et au clic, SEULE la bordure s'eclaire - aucun son", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        local style = ns.Layout.style(ns.Layout.CHOICE_STYLE)
        local button = panel.buttons[1]
        local soundsBefore = #stub.sounds
        local width, height = button.__width, button.__height
        -- AU REPOS : la bordure du style (un simple encart, rien de plus).
        local rest = button:GetBackdropBorderColor()
        assert.are.equal(style.border.r, rest, "bordure au repos")
        assert.are.equal("", button:GetText(), "aucun texte dans le cadre")
        -- SURVOL : la bordure S'ECLAIRE (c'est le SEUL retour visuel demande).
        button:GetScript("OnEnter")(button)
        assert.are.equal(style.borderHover.r, button:GetBackdropBorderColor(), "bordure au survol")
        assert.is_true(style.borderHover.r > rest, "la bordure doit s'eclairer au survol")
        -- APPUI : la bordure reste allumee.
        button:GetScript("OnMouseDown")(button)
        assert.are.equal(style.borderPressed.r, button:GetBackdropBorderColor(), "bordure a l'appui")
        -- SORTIE : retour au repos.
        button:GetScript("OnLeave")(button)
        assert.are.equal(style.border.r, button:GetBackdropBorderColor(), "bordure apres la sortie")
        -- AUCUN SON pour un survol, un appui ou une sortie : le son du raid lead
        -- n'est joue qu'au CLIC d'un bouton de composition (jamais en automatique).
        assert.are.equal(soundsBefore, #stub.sounds, "un survol ne doit JAMAIS jouer de son")
        -- ... et RIEN d'autre n'a bouge : ni taille, ni texte, ni image.
        assert.are.equal(width, button.__width, "la taille de l'encart ne bouge pas")
        assert.are.equal(height, button.__height, "la taille de l'encart ne bouge pas")
        assert.are.equal("", button:GetText(), "le survol n'ecrit aucun texte")
        assert.are.equal(
            ns.Textures.pathFor(ns.Layout.INTERMISSION_CHOICE_ORDER[1]),
            button.picture:GetTexture(),
            "le survol ne change pas l'image"
        )
        -- LE CLIC, lui, joue UN SEUL son (le bon fichier, une seule fois).
        button:Click()
        assert.are.equal(soundsBefore + 1, #stub.sounds, "le clic joue exactement un son")
        assert.are.equal(
            ns.Sound.pathFor(ns.Layout.INTERMISSION_CHOICE_ORDER[1]),
            stub.sounds[#stub.sounds].path,
            "le clic joue le son de SA composition"
        )
        assert.are.equal(ns.Sound.CHANNEL, stub.sounds[#stub.sounds].channel)
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    it("placement : l'illustration SEULE, AUCUN texte et AUCUN bouton a l'ecran", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Retour du raid lead : pendant le placement, le panneau n'affiche QUE
        -- l'illustration de Gideon (repere visuel de la taille et de l'emplacement
        -- de la fenetre). Aucun bouton, aucun texte, aucune composition.
        assert.is_true(panel.placement:IsShown(), "l'illustration doit etre affichee en mode placement")
        assert.are.equal(ns.Textures.placementPath(), panel.placement.picture:GetTexture())
        assert.is_nil(panel.ok)
        for _, gone in ipairs({ "body", "headline", "state", "title", "ok" }) do
            assert.is_nil(panel[gone], "l'element " .. gone .. " existe encore")
        end
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.is_false(panel.redo:IsShown())
        for index = 1, #ns.Layout.INTERMISSION_CHOICE_ORDER do
            assert.is_false(panel.buttons[index]:IsShown(), "aucune composition pendant le placement")
        end
        -- ... et `/gr inter ok` valide vraiment : il sauvegarde la position et ferme.
        _G.SlashCmdList["GIDEONRAID"]("inter ok")
        assert.is_false(panel:IsShown())
        assert.is_table(_G.GideonRaidDB.intermission.position)
        assert.matches("Placement saved", messages())
    end)

    it("placement en FR : le panneau n'ecrit RIEN a l'ecran", function()
        _G.GetLocale = function()
            return "frFR"
        end
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Plus AUCUN texte : ni titre, ni libelle, ni bouton. Seule la croix
        -- (chrome du cadre) porte un glyphe, et c'est le « X ».
        assert.is_nil(panel.ok)
        assert.are.equal("X", panel.closeCross:GetText())
        assert.is_nil(panel.close)
        assert.is_nil(panel.body)
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())
        assert.are.equal(ns.Textures.placementPath(), panel.placement.picture:GetTexture())
        -- Les trois mots du raid lead en francais.
        assert.are.equal("Ping", ns.Locale.t("state.word.1V3R", "fr"))
        assert.are.equal("BOSS", ns.Locale.t("state.word.2V2R", "fr"))
        assert.are.equal("Chasseur", ns.Locale.t("state.word.3V1R", "fr"))
    end)

    it("la croix de la repetition la ferme aussi (un seul cycle, pas de relance)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
        assert.matches("Simulation closed", messages())
        -- Aucune relance automatique, meme tres longtemps apres.
        stub.fireTickers(5000)
        assert.is_false(panel:IsShown())
        assert.matches("Simulation closed", messages())
    end)

    it("cacher le panneau pendant une repetition la termine (aucun etat coince)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- /gr inter (ou /gr inter stop) pendant la repetition : elle est terminee,
        -- sinon la repetition suivante serait refusee sans raison visible.
        _G.SlashCmdList["GIDEONRAID"]("inter")
        assert.is_false(panel:IsShown())
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        assert.is_true(panel:IsShown(), "la repetition doit pouvoir redemarrer")
        assert.is_false(contains(messages(), "already running"))
        _G.SlashCmdList["GIDEONRAID"]("inter stop")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        assert.is_true(panel:IsShown(), "inter stop ne doit pas coincer la repetition")
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    it("/gr sim inter refuse TOUTE option (l'ancien cycles=N a disparu)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter cycles=3")
        assert.matches("no option here", messages())
        assert.matches("Unknown simulation", messages())
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown())
        stub.fireTickers(500)
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown(), "aucune repetition lancee")
        -- Une option collee a une sous-commande qui n'en prend pas est refusee.
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim ping cycles=3")
        assert.matches("no option here", messages())
        assert.is_nil(_G.GideonRaidPingHelpPanel)
    end)

    it("accepte les alias /gr sim group et /gr sim groupe", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim groupe")
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.matches("Simulation closed", messages())
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim group")
        assert.is_true(_G.GideonRaidIntermissionPanel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.matches("Simulation closed", messages())
    end)

    -- ------------------------------------------------------------------------
    -- SIMULATION "Aide au ping" : une fenetre d'information, aucune sequence
    -- ------------------------------------------------------------------------
    it("SIMULATION ping : fenetre d'aide courte, sans sequence ni detection", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GetBindingKey = function(name)
            if name == "PING_WARNING" then
                return "Q"
            end
            return nil
        end
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        local help = _G.GideonRaidPingHelpPanel
        assert.is_true(help:IsShown())
        assert.matches("PING HELP", messages())
        -- Le titre de la fenetre dit ce qu'elle est : une aide, pas un test guide.
        assert.matches("PING: YES = PING YOURSELF", help.headline:GetText())
        local body = help.body:GetText()
        assert.is_true(contains(body, "Options > Keybindings"))
        assert.is_true(contains(body, "hover YOUR OWN character frame"))
        assert.is_true(contains(body, "press your key"))
        assert.is_true(contains(body, "GROUP or a RAID"))
        assert.is_true(contains(body, "CANNOT detect a ping"))
        assert.is_true(contains(body, "1V3R"))
        -- La touche REELLEMENT bindee est listee, les autres sont signalees absentes.
        local keys = help.keys:GetText()
        assert.is_true(contains(keys, "Warning = Q"))
        assert.is_true(contains(keys, "On My Way = no key bound"))
        -- AUCUN compte a rebours, aucun chronometre : rien n'est sequence.
        assert.are.equal(0, #stub.tickers)
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision)

        -- Elle se ferme par le bouton Fermer ET par la croix.
        help.close:Click()
        assert.is_false(help:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        assert.is_true(help:IsShown())
        help.closeCross:Click()
        assert.is_false(help:IsShown())
        -- /gr sim stop la ferme aussi (rapport honnete, rien d'autre ne tourne).
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.is_false(help:IsShown())
        assert.matches("Simulation closed", messages())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.matches("No simulation running", messages())

        -- En francais : la meme fenetre, les memes consignes.
        _G.SlashCmdList["GIDEONRAID"]("lang fr")
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        assert.matches("PING : OUI", help.headline:GetText())
        assert.is_true(contains(help.body:GetText(), "Raccourcis"))
        assert.is_true(contains(help.body:GetText(), "survole TON propre cadre"))
        _G.SlashCmdList["GIDEONRAID"]("lang en")
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    it("/gr pinghelp ouvre la meme fenetre d'aide (alias documente)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        assert.matches("/gr pinghelp", messages())
        _G.DEFAULT_CHAT_FRAME.messages = {}
        _G.SlashCmdList["GIDEONRAID"]("pinghelp")
        local help = _G.GideonRaidPingHelpPanel
        assert.is_true(help:IsShown())
        assert.matches("PING HELP", messages())
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.is_false(help:IsShown())
    end)

    it("la disposition appliquee garde le MOT sous le bandeau (EN + FR)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        buttonFor(panel, "1V3R"):Click() -- le mot du 1V3R apparait
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        for _, lang in ipairs({ "en", "fr" }) do
            _G.SlashCmdList["GIDEONRAID"]("lang " .. lang)
            local _, _, _, _, bannerY = panel.simBanner:GetPoint(1)
            local _, _, _, _, wordY = panel.word:GetPoint(1)
            -- Le mot est SOUS le bas du bandeau (bug du 4e test en jeu : un bloc
            -- dessine sur le bandeau rendait les deux illisibles).
            assert.is_true(wordY < bannerY, lang .. " : le mot chevauche le bandeau")
            -- ... et il reste dans le cadre (le panneau grandit avec le contenu).
            assert.is_true(wordY > -panel.__height, "le mot sort du cadre en " .. lang)
            -- Le mot suit la langue servie, sans re-clic.
            assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText(), lang)
            assert.is_true(panel.word:IsShown(), lang)
        end
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    -- ------------------------------------------------------------------------
    -- PANNEAU PRINCIPAL DEPLACABLE + POSITIONS PERSISTEES (3e retour en jeu)
    -- ------------------------------------------------------------------------
    --- Simule un drag du joueur : la position est ecrite hors jeu par SetPoint,
    --- puis le script OnDragStop du cadre enregistre cette position.
    local function dragTo(frame, point, relativePoint, x, y)
        frame:ClearAllPoints()
        frame:SetPoint(point, _G.UIParent, relativePoint, x, y)
        frame:GetScript("OnDragStop")(frame)
    end

    it("le panneau principal est DEPLACABLE par defaut et sa position est memorisee", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        -- Le verrou n'est plus pose par defaut : c'est la cause du bug signale.
        assert.is_false(_G.GideonRaidDB.lockPanel)
        local moved = false
        main.StartMoving = function()
            moved = true
        end

        -- Le joueur deplace le panneau : la position part dans les SauvedVariables.
        dragTo(main, "TOPLEFT", "TOPLEFT", -120, -40)
        assert.are.equal("TOPLEFT", _G.GideonRaidDB.panelPosition.point)
        assert.are.equal(-120, _G.GideonRaidDB.panelPosition.x)
        assert.are.equal(-40, _G.GideonRaidDB.panelPosition.y)

        -- /reload : la position est REAPPLIQUEE a partir des SauvedVariables.
        main:ClearAllPoints()
        main:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        _G.SlashCmdList["GIDEONRAID"]("show")
        local _, _, _, x, y = main:GetPoint(1)
        assert.are.equal(-120, x, "position restauree au login")
        assert.are.equal(-40, y)

        -- Deverrouille par defaut : le glisser est reellement autorise.
        main:GetScript("OnDragStart")(main)
        assert.is_true(moved, "le glisser doit etre autorise par defaut")
    end)

    it("/gr lock fige le panneau, /gr unlock le libere, la position est conservee", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        local moved
        main.StartMoving = function()
            moved = true
        end
        dragTo(main, "BOTTOMLEFT", "BOTTOMLEFT", 30, 50)

        _G.SlashCmdList["GIDEONRAID"]("lock")
        assert.is_true(_G.GideonRaidDB.lockPanel)
        assert.matches("Panel locked", messages())
        moved = false
        main:GetScript("OnDragStart")(main)
        assert.is_false(moved, "verrouille : le panneau ne bouge pas")
        assert.matches("Panel locked: /gr unlock", messages())
        assert.matches("UNLOCK PANEL", main.lock:GetText())

        -- Le verrou survit a un rechargement (marqueur de schema pose).
        _G.GideonRaidDB.panelSchema = ns.Config.PANEL_SCHEMA
        assert.is_true(ns.Config.ensureDB(_G.GideonRaidDB).lockPanel)

        _G.SlashCmdList["GIDEONRAID"]("unlock")
        assert.is_false(_G.GideonRaidDB.lockPanel)
        assert.matches("Panel unlocked", messages())
        assert.matches("LOCK PANEL", main.lock:GetText())
        moved = false
        main:GetScript("OnDragStart")(main)
        assert.is_true(moved, "deverrouille : le panneau se deplace a nouveau")
        -- La position deplacee n'a pas ete perdue par le verrouillage.
        assert.are.equal(30, _G.GideonRaidDB.panelPosition.x)
    end)

    it("le bouton LOCK/UNLOCK du panneau principal fait la meme chose que la commande", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        assert.matches("LOCK PANEL", main.lock:GetText())
        main.lock:Click()
        assert.is_true(_G.GideonRaidDB.lockPanel)
        assert.matches("UNLOCK PANEL", main.lock:GetText())
        main.lock:Click()
        assert.is_false(_G.GideonRaidDB.lockPanel)
    end)

    it("la fenetre d'aide au ping est deplacable et sa position memorisee", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        local test = _G.GideonRaidPingHelpPanel
        dragTo(test, "BOTTOMLEFT", "BOTTOMLEFT", 30, 50)
        assert.are.equal("BOTTOMLEFT", _G.GideonRaidDB.pingPanelPosition.point)
        assert.are.equal(30, _G.GideonRaidDB.pingPanelPosition.x)
        assert.are.equal(50, _G.GideonRaidDB.pingPanelPosition.y)
        -- Elle se rouvre la ou le joueur l'a laissee.
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        test:ClearAllPoints()
        test:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        local _, _, _, x, y = test:GetPoint(1)
        assert.are.equal(30, x, "position restauree a l'ouverture suivante")
        assert.are.equal(50, y)
    end)

    it("/gr resetposition remet les trois panneaux au centre", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        local main = _G.GideonRaidPanel
        dragTo(main, "TOPLEFT", "TOPLEFT", -120, -40)
        _G.SlashCmdList["GIDEONRAID"]("sim ping")
        dragTo(_G.GideonRaidPingHelpPanel, "TOPLEFT", "TOPLEFT", -50, -10)
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
        assert.are_not.equal("CENTER", _G.GideonRaidDB.panelPosition.point)

        _G.SlashCmdList["GIDEONRAID"]("resetposition")
        assert.are.equal("CENTER", _G.GideonRaidDB.panelPosition.point)
        assert.are.equal(0, _G.GideonRaidDB.panelPosition.x)
        assert.are.equal("CENTER", _G.GideonRaidDB.pingPanelPosition.point)
        assert.are.equal("CENTER", _G.GideonRaidDB.intermission.position.point)
        assert.matches("positions reset", messages())
        local point, _, _, x, y = main:GetPoint(1)
        assert.are.equal("CENTER", point)
        assert.are.equal(0, x)
        assert.are.equal(0, y)
    end)

    it("les commandes de panneau sont documentees dans l'aide, et inconnues refusees", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inconnu")
        local text = messages()
        assert.matches("/gr lock", text)
        assert.matches("/gr unlock", text)
        assert.matches("/gr resetposition", text)
        -- Un verrou sans SauvedVariables ne leve pas.
        local saved = _G.GideonRaidDB
        _G.GideonRaidDB = nil
        _G.SlashCmdList["GIDEONRAID"]("lock")
        assert.matches("SavedVariables not initialized", messages())
        _G.GideonRaidDB = saved
    end)

    -- ------------------------------------------------------------------------
    -- PANNEAU DE COMBAT : les trois choix DISPARAISSENT apres le clic
    -- ------------------------------------------------------------------------
    it("apres le clic, les trois images disparaissent, le mot et CORRIGER restent", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        -- Avant le clic : les trois images, aucun mot, pas de CORRIGER.
        for index = 1, 3 do
            assert.is_true(panel.buttons[index]:IsShown(), "choix " .. index)
        end
        assert.is_false(panel.redo:IsShown())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.wordBig:IsShown())

        buttonFor(panel, "1V3R"):Click()
        for index = 1, 3 do
            assert.is_false(panel.buttons[index]:IsShown(), "choix " .. index .. " masque apres le clic")
        end
        assert.is_true(panel.redo:IsShown(), "CORRIGER reste disponible")
        -- UN SEUL mot : "Ping", en vert (couleur du theme), et rien d'autre.
        assert.is_true(panel.word:IsShown())
        assert.are.equal(ns.Locale.t("state.word.1V3R"), panel.word:GetText())
        assert.are.same({ 0.25, 1.0, 0.25 }, panel.word.__color)

        -- CORRIGER ramene les trois images (et efface le mot)...
        panel.redo:Click()
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.redo:IsShown())
        for index = 1, 3 do
            assert.is_true(panel.buttons[index]:IsShown(), "choix " .. index .. " de retour")
        end

        -- ... et le clic suivant masque a nouveau : le geste est rejouable.
        buttonFor(panel, "2V2R"):Click()
        assert.is_true(panel.wordBig:IsShown())
        assert.are.equal(ns.Locale.t("state.word.2V2R"), panel.wordBig:GetText())
        assert.is_false(panel.word:IsShown())
        assert.is_false(panel.buttons[1]:IsShown())
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        assert.is_true(panel.redo:IsShown())
    end)

    it("pendant une repetition aussi, le clic masque les trois choix", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        -- Le panneau est DEJA la : aucun ticker a faire tourner (4e retour en jeu).
        assert.are.equal(0, #stub.tickers)
        assert.is_true(panel:IsShown())
        assert.is_true(panel.buttons[2]:IsShown())
        panel.buttons[2]:Click()
        assert.is_false(panel.buttons[1]:IsShown())
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        assert.is_true(panel.redo:IsShown())
        panel.redo:Click()
        assert.is_true(panel.buttons[2]:IsShown())
    end)
end)

-- ---------------------------------------------------------------------------
-- 6. Fermeture BORNEE : le panneau ne reste JAMAIS a l'ecran (raid lead)
-- ---------------------------------------------------------------------------

describe("fermeture bornee du panneau d'intermission", function()
    local ns

    before_each(function()
        _G.GideonRaid = nil
        _G.GideonRaidDB = nil
        _G.GideonRaidCharDB = nil
        _G.GideonRaidPanel = nil
        _G.GideonRaidIntermissionPanel = nil
        _G.GideonRaidPingHelpPanel = nil
        _G.GameTooltip = nil
        _G.SlashCmdList = nil
        _G.GetBindingKey = nil
        stub.install()
        ns = wowenv.loadAddon()
    end)

    --- Le boss CIBLE du harness (allow-list vide par defaut).
    local BOSS_ID = 1234
    local function pullTargetBoss()
        _G.GideonRaidDB.intermission.bossIds = { BOSS_ID }
        stub.mainFrame():Fire("ENCOUNTER_START", BOSS_ID, "Entombed Sentinels", 16, 20)
    end

    --- Bloque la machine a etats : le cas ou l'intermission ne se termine JAMAIS
    --- toute seule (etat perdu, tick gele). C'est exactement le cadre qui restait a
    --- l'ecran pour toujours avant le filet : la phase n'avance plus, donc le seul
    --- chemin de fermeture qui reste est le filet borne.
    local function freezeIntermission()
        local realTick = ns.Intermission.tick
        ns.Intermission.tick = function()
            return nil
        end
        return function()
            ns.Intermission.tick = realTick
        end
    end

    it("ferme le panneau a la fin de l'intermission, meme si la machine se bloque", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450) -- ouverture automatique avant la 1re intermission
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())

        local unfreeze = freezeIntermission()
        -- Filet par defaut : 30 s (fenetre reelle de 25 s + marge de 5 s). A 25 s,
        -- le panneau est encore la : le filet ne coupe JAMAIS une intermission en
        -- cours.
        stub.fireTickers(250)
        assert.is_true(panel:IsShown(), "le filet ne doit pas couper une intermission en cours")
        -- ... et au-dela du delai borne, il disparait TOUT SEUL.
        stub.fireTickers(100)
        assert.is_false(panel:IsShown(), "le panneau doit disparaitre malgre la machine bloquee")
        unfreeze()
    end)

    it("le delai est CONFIGURABLE (SavedVariables) et toujours borne", function()
        _G.GideonRaidDB = { intermission = { autoCloseSeconds = 60 } }
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        local unfreeze = freezeIntermission()
        stub.fireTickers(400) -- 40 s : sous le delai configure de 60 s
        assert.is_true(panel:IsShown(), "le delai configure doit etre respecte")
        stub.fireTickers(300) -- 70 s : au-dela
        assert.is_false(panel:IsShown(), "le delai configure finit par fermer")
        unfreeze()
    end)

    it("une valeur absurde dans les SavedVariables reste bornee", function()
        -- Planning reduit a UNE intermission : on isole le filet du planning.
        _G.GideonRaidDB = { intermission = { autoCloseSeconds = 99999, scheduleSeconds = { 46.3 } } }
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        local unfreeze = freezeIntermission()
        -- Le maximum borne est de 300 s : passe ce delai, le panneau a disparu.
        stub.fireTickers(3100)
        assert.is_false(panel:IsShown(), "un delai hors bornes doit etre ramene au maximum")
        unfreeze()
    end)

    it("le filet est REARME a chaque nouvelle intermission", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        pullTargetBoss()
        local panel = _G.GideonRaidIntermissionPanel
        stub.fireTickers(450) -- 1re intermission
        assert.is_true(panel:IsShown())
        -- 1re intermission : fermeture automatique par la machine a etats (le filet
        -- est desarme avec elle).
        stub.fireTickers(255)
        assert.is_false(panel:IsShown())
        local unfreeze = freezeIntermission()
        -- 2e intermission : le panneau se rouvre et disparait ENCORE tout seul.
        stub.fireTickers(765)
        assert.is_true(panel:IsShown())
        stub.fireTickers(100)
        assert.is_true(panel:IsShown(), "le delai repart de zero a chaque intermission")
        stub.fireTickers(250)
        assert.is_false(panel:IsShown(), "le filet doit etre rearme a chaque intermission")
        unfreeze()
    end)

    it("croix et fermeture a la main restent possibles, sans laisser de filet arme", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
        -- Rouverte a la main (/gr inter = bascule), puis refermee par la bascule.
        _G.SlashCmdList["GIDEONRAID"]("inter")
        assert.is_true(panel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("inter")
        assert.is_false(panel:IsShown())
        stub.fireTickers(500)
        assert.is_false(panel:IsShown())
        -- Rouverte seule : le filet la referme (aucune intermission ne tourne, le
        -- delai configure est la seule borne).
        _G.SlashCmdList["GIDEONRAID"]("inter")
        assert.is_true(panel:IsShown())
        stub.fireTickers(350)
        assert.is_false(panel:IsShown(), "un panneau ouvert a la main ne reste pas non plus")
    end)

    it("le mode placement n'est PAS soumis au filet (le joueur prend son temps)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        -- Un placement peut durer : aucune fermeture surprise.
        stub.fireTickers(3000)
        assert.is_true(panel:IsShown(), "le mode placement ne doit pas se fermer tout seul")
        _G.SlashCmdList["GIDEONRAID"]("inter ok")
        assert.is_false(panel:IsShown())
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        assert.is_true(panel:IsShown())
        stub.fireTickers(3000)
        assert.is_true(panel:IsShown())
        panel.closeCross:Click()
        assert.is_false(panel:IsShown())
    end)
end)
