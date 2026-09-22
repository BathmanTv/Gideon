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
        assert.are.equal(7, #files)
        assert.are.equal("GideonRaid.lua", files[1])
        -- Core/Locale.lua d'abord : la couche de langue est une dependance.
        assert.are.equal("Core/Locale.lua", files[2])
        assert.are.equal("Core/Config.lua", files[3])
        assert.are.equal("UI/Intermission.lua", files[7])
    end)

    it("expose toutes les couches attendues", function()
        assert.is_table(ns.Locale)
        assert.is_table(ns.Pairing)
        assert.is_table(ns.Config)
        assert.is_table(ns.Intermission)
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
        stub.fireTickers(50)
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
end)
