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

    it("charge tous les fichiers listes dans le .toc, dans l'ordre", function()
        local files = wowenv.tocFiles()
        assert.are.equal(10, #files)
        assert.are.equal("GideonRaid.lua", files[1])
        -- Core/Locale.lua d'abord : la couche de langue est une dependance.
        assert.are.equal("Core/Locale.lua", files[2])
        -- Core/Sound.lua juste apres Locale.lua et AVANT Config.lua : Config en
        -- resout la preference bornee (/gr sound), et il porte la table pure
        -- « etat -> fichier de son » du son d'assignation.
        assert.are.equal("Core/Sound.lua", files[3])
        assert.are.equal("Core/Config.lua", files[4])
        -- Core/Simulation.lua APRES Intermission.lua (il reutilise ses etats et
        -- ses libelles), Core/Layout.lua EN DERNIER des Core/ (il mesure les
        -- libelles), puis la couche de rendu (UI/) qui applique le tout.
        assert.are.equal("Core/Simulation.lua", files[7])
        assert.are.equal("Core/Layout.lua", files[8])
        assert.are.equal("UI/Panel.lua", files[9])
        assert.are.equal("UI/Intermission.lua", files[10])
    end)

    it("expose toutes les couches attendues", function()
        assert.is_table(ns.Locale)
        assert.is_table(ns.Sound)
        assert.is_table(ns.Pairing)
        assert.is_table(ns.Config)
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

    it("mode placement : bouton du panneau principal, OK ferme et sauvegarde", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.matches("BEFORE THE PULL", panel.headline:GetText())
        assert.is_true(contains(panel.body:GetText(), "Options > Keybindings"))
        assert.is_true(contains(panel.body:GetText(), "No out-of-game plan loaded (optional)."))
        assert.is_true(panel.ok:IsShown())
        assert.is_false(panel.buttons[1]:IsShown())
        panel.ok:Click()
        assert.is_false(panel:IsShown())
        assert.is_table(_G.GideonRaidDB.intermission.position)
        assert.matches("Placement saved", messages())
    end)

    it("/gr inter place ouvre aussi le mode placement et Close annule", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.matches("BEFORE THE PULL", panel.headline:GetText())
        panel.close:Click()
        assert.is_false(panel:IsShown())
    end)

    it("ENCOUNTER_START arme le planning sans ouvrir le panneau ni lire ses arguments", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START", 1234, "Entombed Sentinels", 16, 20)
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_false(panel:IsShown(), "le panneau ne s'ouvre qu'avant l'intermission")
        assert.matches("armed: 4 intermission", messages())
        assert.matches("opens 2 s before", messages())
    end)

    it("le panneau s'ouvre TOUT SEUL avant la 1re intermission (44,3 s) et ferme a la fin", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        local panel = _G.GideonRaidIntermissionPanel
        -- 40 s : toujours ferme (ouverture a 44,3 s).
        stub.fireTickers(400)
        assert.is_false(panel:IsShown())
        -- 45 s : ouvert, en attente du debut de l'intermission.
        stub.fireTickers(51)
        assert.is_true(panel:IsShown())
        assert.matches("GET READY", panel.headline:GetText())
        assert.are.equal("", panel.state:GetText())
        assert.is_true(panel.buttons[1]:IsShown())
        assert.is_false(panel.redo:IsShown())
        -- + 2 s : l'intermission commence (compte a rebours de visibilite).
        stub.fireTickers(20)
        assert.matches("LOOK AT THE ORB COLOR", panel.headline:GetText())
        -- + 3,5 s : salle obscurcie.
        stub.fireTickers(35)
        assert.matches("DARKENED", panel.headline:GetText())
        -- Fin de l'intermission (duree par defaut 20 s) : fermeture automatique.
        stub.fireTickers(200)
        assert.is_false(panel:IsShown(), "le panneau se ferme tout seul a la fin")
    end)

    it("clic sur une composition : etat en gros, role, PING et UNE action", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        assert.matches("2 green %+ 2 red", panel.buttons[2]:GetText())
        assert.matches("1 or 3", panel.buttons[1]:GetText())
        panel.buttons[2]:Click() -- 2V2R
        assert.are.equal("2V2R", panel.state:GetText())
        assert.are.equal("PING: NO", panel.pingBanner:GetText())
        assert.is_true(panel.pingBanner:IsShown())
        local text = panel.body:GetText()
        assert.is_true(contains(text, "ROLE: MIDDLE"))
        assert.is_true(contains(text, "DO NOT PING - go to the middle / under the boss"))
        -- Le pave technique a disparu : plus aucune de ces lignes.
        for _, banned in ipairs({ "ROLE ORDER", "PING POLICY", "STATE THAT JOINS YOU", "GUILD CONVENTION", "UNKNOWN" }) do
            assert.is_false(contains(text, banned), banned)
        end
    end)

    it("bouton CORRIGER : ramene aux trois choix, utilisable plusieurs fois", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click()
        assert.are.equal("1V3R", panel.state:GetText())
        assert.is_true(panel.redo:IsShown())
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        panel.redo:Click()
        assert.are.equal("", panel.state:GetText())
        assert.is_false(panel.redo:IsShown())
        assert.is_true(contains(panel.body:GetText(), "Click the composition you see"))
        -- Deuxieme corrige, puis troisieme : toujours possible.
        panel.buttons[3]:Click()
        assert.are.equal("3V1R", panel.state:GetText())
        panel.redo:Click()
        panel.buttons[2]:Click()
        assert.are.equal("2V2R", panel.state:GetText())
        panel.redo:Click()
        panel.buttons[1]:Click()
        assert.are.equal("1V3R", panel.state:GetText())
    end)

    it("affiche la touche de ping quand le joueur en a bindi une", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GetBindingKey = function(name)
            if name == "PING_WARNING" then
                return "Q"
            end
            return nil
        end
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click()
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        assert.is_true(contains(panel.body:GetText(), "PING: Warning - press Q"))
    end)

    it("sans raccourci bindi (ou GetBindingKey absent) : demande un raccourci", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        assert.is_nil(_G.GetBindingKey, "le harnais ne definit PAS GetBindingKey")
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click()
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        assert.is_true(contains(panel.body:GetText(), "PING: Warning - set a keybind in Options > Keybindings"))
    end)

    it("survit a un GetBindingKey qui leve une erreur", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GetBindingKey = function()
            error("GetBindingKey a leve")
        end
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click()
        assert.is_true(contains(panel.body:GetText(), "set a keybind in Options > Keybindings"))
    end)

    it("rouvre le panneau a l'intermission SUIVANTE (cycle complet)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
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
        assert.matches("GET READY", panel.headline:GetText())
        assert.are.equal("", panel.state:GetText())
    end)

    it("ENCOUNTER_END ferme le panneau et desarme le planning", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
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
        _G.GideonRaidIntermissionPanel.buttons[3]:Click() -- 3V1R
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
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(600)
        assert.is_false(_G.GideonRaidIntermissionPanel:IsShown(), "desactive = aucune ouverture automatique")
    end)

    it("le panneau reste lisible et n'affiche aucune valeur dynamique", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter start")
        local text = _G.GideonRaidIntermissionPanel.body:GetText()
        assert.is_nil(string.find(text, "UnitHealth", 1, true))
        assert.is_nil(string.find(text, "UnitAura", 1, true))
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
        stub.mainFrame():Fire("ENCOUNTER_START")
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
        assert.matches("GET READY", panel.headline:GetText())
    end)

    it("en placement, la croix ANNULE (meme effet que le bouton Close existant)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("inter place")
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.matches("BEFORE THE PULL", panel.headline:GetText())
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
        stub.mainFrame():Fire("ENCOUNTER_START")
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
        _G.GideonRaidIntermissionPanel.close:Click()
        stub.mainFrame():Fire("ENCOUNTER_START")
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
        local headline = panel.headline:GetText()
        assert.is_false(contains(headline, "LOOK AT THE ORB COLOR"))
        assert.is_true(contains(headline, "NO ORB TO READ"))
        assert.is_true(contains(panel.body:GetText(), "close this panel yourself"))
        assert.is_true(panel.buttons[1]:IsShown())

        -- Le geste complet du joueur : composition, CORRIGER, composition.
        panel.buttons[1]:Click()
        assert.are.equal("1V3R", panel.state:GetText())
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        assert.is_true(contains(panel.body:GetText(), "ROLE: ANCHOR"))
        assert.is_true(panel.redo:IsShown())
        assert.is_false(panel.buttons[1]:IsShown(), "les trois choix disparaissent apres le clic")
        assert.is_false(panel.buttons[2]:IsShown())
        assert.is_false(panel.buttons[3]:IsShown())
        panel.redo:Click()
        assert.are.equal("", panel.state:GetText())
        panel.buttons[3]:Click()
        assert.are.equal("3V1R", panel.state:GetText())
        -- Une repetition ne publie AUCUNE decision : le kit de diagnostic ne doit
        -- jamais lire une repetition comme un vrai choix.
        assert.is_nil(_G.GideonRaidDB.intermission.lastDecision)

        -- Elle ne se ferme PAS toute seule : aucun temps ne tourne.
        stub.fireTickers(5000)
        assert.is_true(panel:IsShown())
        -- ... c'est le JOUEUR qui la ferme (bouton Fermer), et le chat le dit.
        panel.close:Click()
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
        stub.mainFrame():Fire("ENCOUNTER_START")
        assert.matches("armed: 4 intermission", messages())
        stub.fireTickers(450)
        assert.is_true(panel:IsShown())
        assert.is_false(panel.simBanner:IsShown(), "plus de bandeau SIMULATION hors repetition")
    end)

    it("5e test : les trois boutons de composition sont affiches, poses et fonctionnels", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        local layout = ns.Layout
        assert.is_true(panel:IsShown())
        for index = 1, 3 do
            local button = panel.buttons[index]
            assert.is_true(button:IsShown(), "le bouton de composition " .. index .. " doit etre affiche")
            -- ANCRE : le bug du 5e test etait une ancre NULLE (SetPoint(nil) leve
            -- en jeu, l'applier s'arretait et ces trois boutons disparaissaient).
            assert.are.equal("TOPLEFT", button.__point[1])
            assert.is_number(button.__point[2])
            assert.is_number(button.__point[3])
            -- TAILLE mesuree depuis le libelle : plus jamais un cadre fixe.
            assert.is_true(button.__width >= layout.CHOICE_MIN_WIDTH, "bouton trop etroit")
            assert.is_true(button.__height >= layout.CHOICE_MIN_HEIGHT, "bouton trop court")
            assert.is_true(
                layout.textWidth(button:GetText(), "button") <= (button.__width - (2 * layout.BUTTON_PADDING_X)),
                "le libelle doit tenir dans le bouton avec sa marge"
            )
        end
        -- Le bouton Fermer est la lui aussi ; OK n'a rien a faire dans une
        -- repetition (il valide une POSITION, pas un choix).
        assert.is_true(panel.close:IsShown())
        assert.is_false(panel.ok:IsShown())
        -- CHAQUE bouton remplit sa fonction : etat + role + PING + ligne d'action.
        local expected = {
            { index = 1, state = "1V3R", role = "ROLE: ANCHOR", ping = "PING: YES", action = "PING: YES - hover YOUR OWN" },
            { index = 2, state = "2V2R", role = "ROLE: MIDDLE", ping = "PING: NO", action = "DO NOT PING - go to the middle" },
            { index = 3, state = "3V1R", role = "ROLE: CHASER", ping = "PING: NO", action = "DO NOT PING - run to a ping" },
        }
        for _, case in ipairs(expected) do
            panel.buttons[case.index]:Click()
            assert.are.equal(case.state, panel.state:GetText())
            local body = panel.body:GetText()
            assert.is_true(contains(body, case.role), case.state .. " : role manquant")
            assert.are.equal(case.ping, panel.pingBanner:GetText())
            assert.is_true(panel.pingBanner:IsShown())
            assert.is_true(contains(body, case.action), case.state .. " : ligne d'action manquante")
            for index = 1, 3 do
                assert.is_false(panel.buttons[index]:IsShown(), "les trois choix disparaissent apres le clic")
            end
            -- CORRIGER ramene les trois boutons et vide l'etat.
            assert.is_true(panel.redo:IsShown())
            panel.redo:Click()
            assert.are.equal("", panel.state:GetText())
            assert.is_false(panel.redo:IsShown())
            for index = 1, 3 do
                assert.is_true(panel.buttons[index]:IsShown(), "CORRIGER doit ramener les trois choix")
            end
        end
        _G.SlashCmdList["GIDEONRAID"]("sim stop")
    end)

    it("placement : le texte dit de placer le panneau puis d'appuyer sur OK", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        assert.is_true(panel:IsShown())
        assert.is_true(panel.ok:IsShown(), "le bouton OK doit etre affiche en mode placement")
        local body = panel.body:GetText()
        assert.is_true(contains(body, "Place the panel where you want it to appear, then press OK"), body)
        assert.is_true(contains(body, "during the fight it opens by itself"), body)
        -- ... et OK valide vraiment : il sauvegarde la position et ferme.
        panel.ok:Click()
        assert.is_false(panel:IsShown())
        assert.is_table(_G.GideonRaidDB.intermission.position)
        assert.matches("Placement saved", messages())
    end)

    it("placement : le texte francais dit la meme chose (client frFR)", function()
        _G.GetLocale = function()
            return "frFR"
        end
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.GideonRaidPanel.place:Click()
        local panel = _G.GideonRaidIntermissionPanel
        local body = panel.body:GetText()
        assert.is_true(contains(body, "Place le panneau la ou tu veux qu'il apparaisse, puis appuie sur OK"), body)
        assert.is_true(contains(body, "pendant le combat il s'ouvre tout seul"), body)
        assert.matches("OK", panel.ok:GetText())
        assert.matches("Fermer", panel.close:GetText())
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

    it("la disposition appliquee garde le grand etat SOUS le bandeau (EN + FR)", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        _G.SlashCmdList["GIDEONRAID"]("sim inter")
        local panel = _G.GideonRaidIntermissionPanel
        panel.buttons[1]:Click() -- le grand etat "1V3R" apparait
        assert.are.equal("1V3R", panel.state:GetText())
        for _, lang in ipairs({ "en", "fr" }) do
            _G.SlashCmdList["GIDEONRAID"]("lang " .. lang)
            local _, _, _, _, bannerY = panel.simBanner:GetPoint(1)
            local _, _, _, _, stateY = panel.state:GetPoint(1)
            -- Le grand etat est SOUS le bas du bandeau (bug du 4e test en jeu).
            assert.is_true(stateY < bannerY, lang .. " : le grand etat chevauche le bandeau")
            -- ... et il reste dans le cadre (le panneau grandit avec le contenu).
            assert.is_true(stateY > -panel.__height, "l'etat sort du cadre en " .. lang)
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
    it("apres le clic, les trois boutons disparaissent, CORRIGER seul reste", function()
        stub.mainFrame():Fire("ADDON_LOADED", "GideonRaid")
        stub.mainFrame():Fire("ENCOUNTER_START")
        stub.fireTickers(450)
        local panel = _G.GideonRaidIntermissionPanel
        -- Avant le clic : les trois choix, pas de CORRIGER.
        for index = 1, 3 do
            assert.is_true(panel.buttons[index]:IsShown(), "choix " .. index)
        end
        assert.is_false(panel.redo:IsShown())

        panel.buttons[1]:Click() -- 1V3R
        assert.are.equal("1V3R", panel.state:GetText())
        for index = 1, 3 do
            assert.is_false(panel.buttons[index]:IsShown(), "choix " .. index .. " masque apres le clic")
        end
        assert.is_true(panel.redo:IsShown(), "CORRIGER reste disponible")
        assert.are.equal("PING: YES", panel.pingBanner:GetText())
        local first = panel.body:GetText()
        assert.is_true(contains(first, "ROLE: ANCHOR"))
        assert.is_true(contains(first, "hover YOUR OWN character frame"))

        -- CORRIGER ramene les trois choix (etat vide)...
        panel.redo:Click()
        assert.are.equal("", panel.state:GetText())
        assert.is_false(panel.redo:IsShown())
        for index = 1, 3 do
            assert.is_true(panel.buttons[index]:IsShown(), "choix " .. index .. " de retour")
        end
        assert.is_true(contains(panel.body:GetText(), "Click the composition you see"))

        -- ... et le clic suivant masque a nouveau : le geste est rejouable.
        panel.buttons[3]:Click() -- 3V1R
        assert.are.equal("3V1R", panel.state:GetText())
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
