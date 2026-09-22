--[[--------------------------------------------------------------------------
    tools/intermission_cli.lua

    Out-of-game CLI front end of the "Intermission Coach" module. It is used to:
      - review the THREE color states (3V1R / 2V2R / 1V3R) without the client;
      - see which PING each state must use, under each ping policy, and what the
        panel displays in game (state, role, PING: YES/NO, ONE action line);
      - check a meeting ("3V1R meets 2V2R" -> 5 green -> dead);
      - replay the pre-computed intermission schedule (run machine);
      - display the pre-pull view from a prepared assignment block.

    The ping is placed by the PLAYER with the native Blizzard ping keybind: this
    CLI simulates the key it would display (argument `KEY`) because the real key
    is read in game with GetBindingKey.

    Usage (from the repository root):
      lua5.1 tools/intermission_cli.lua all
      lua5.1 tools/intermission_cli.lua roles
      lua5.1 tools/intermission_cli.lua 3V1R [anchors|color|none] [KEY]
      lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R
      lua5.1 tools/intermission_cli.lua run [lead]
      lua5.1 tools/intermission_cli.lua plan [Name] [fixture.lua] [anchors|color|none]

    No external dependency: only the lua5.1 of the VPS.
----------------------------------------------------------------------------]]
--
package.path = "./?.lua;./?/init.lua;" .. package.path

local wowenv = require("tests.support.wowenv")
local ns = wowenv.loadCore()
local I = ns.Intermission

local FIXTURE = "tests/fixtures/assignment_sample.lua"

local function out(line)
    io.write(line .. "\n")
end

local function usage()
    out("usage: intermission_cli.lua all | roles | run [lead]")
    out("       intermission_cli.lua 3V1R|2V2R|1V3R [politique] [TOUCHE]")
    out("       intermission_cli.lua pair A B | plan [Nom] [fixture.lua] [politique]")
    out("politiques : anchors (defaut) | color | none")
    os.exit(2)
end

local function printDeclaration(declaration, mode, key)
    local rec, err = I.getDeclaration(declaration, mode)
    if rec == nil then
        out("REFUS : " .. tostring(err))
        return nil
    end
    out("TU VOIS  : " .. rec.display .. "  (" .. rec.key .. ")")
    out("  NUMERO : " .. rec.numberText .. (rec.numberAmbiguous and "  (AMBIGU : la couleur tranche)" or "  (non ambigu)"))
    out("  ROLE   : " .. rec.roleName .. "  (" .. rec.role .. ")")
    out("  PING   : " .. rec.pingDecision)
    out("  CHAMP  : " .. rec.actionLine)
    local hint, hintErr = I.pingHint(rec.key, mode, key)
    if hint == nil then
        out("  TOUCHE : aucune (ce role ne ping pas dans cette politique : " .. tostring(hintErr) .. ")")
    else
        out("  TOUCHE : " .. hint.line)
        out("           noms de raccourci essayes en jeu : " .. table.concat(hint.bindNames, ", "))
    end
    return rec
end

local function printRoles(mode)
    local line, resolved = I.pingPolicyLine(mode)
    out("Politique de ping : " .. resolved)
    out("  " .. line)
    out("")
    for _, declaration in ipairs(I.STATES) do
        printDeclaration(declaration, resolved)
        out("")
    end
end

local function printSchedule(lead)
    local run = I.newRun(nil, lead)
    out("Planning pre-calcule (secondes depuis ENCOUNTER_START, lead " .. run.lead .. " s) :")
    for index = 1, #run.schedule do
        out(
            string.format(
                "  #%d : intermission a %.1f s -> panneau ouvert a %.1f s",
                index,
                run.schedule[index],
                run.schedule[index] - run.lead
            )
        )
    end
    -- Rejeu de la machine pure : on avance par pas de 0,1 s et on compte les
    -- ouvertures (la fermeture, elle, est pilotee par la machine d'etat).
    local clock = 0
    local opened = 0
    while not I.runFinished(run) do
        local _, index = I.advanceRun(run, 0.1)
        clock = clock + 0.1
        if index ~= nil then
            opened = opened + 1
        end
    end
    out(string.format("  rejeu : %d ouverture(s) detectee(s) par la machine, planning epuise a %.1f s", opened, clock))
    out("  fermeture du panneau : fin de la timeline de l'intermission (DONE -> fermeture automatique)")
end

local mode = arg[1]
if mode == nil then
    usage()
elseif mode == "all" then
    out("Etats de l'Intermission Coach (Entombed Sentinels mythique)")
    out("fenetre de visibilite : " .. I.VISIBILITY_SECONDS .. " s, lead du panneau : " .. I.LEAD_SECONDS .. " s")
    out("sauvent : 3V1R + 1V3R = 4 verts + 4 rouges ; 2V2R + 2V2R = 4 verts + 4 rouges")
    out("tuent   : 3V1R + 2V2R = 5 verts (« 5g ») ; 1V3R + 1V3R ; 3V1R + 3V1R")
    out("le numero 1 ou 3 est AMBIGU : c'est la COULEUR qui decide (seul '2' est non ambigu)")
    out("roles par ETAT : 1V3R = ANCRE, 2V2R = MILIEU, 3V1R = CHASSEUR")
    out("le joueur ping LUI-MEME avec son raccourci natif : l'addon affiche quel ping et quelle touche")
    out("")
    for _, declaration in ipairs(I.STATES) do
        printDeclaration(declaration)
        out("")
    end
elseif mode == "roles" then
    for _, policy in ipairs(I.PING_MODES) do
        printRoles(policy)
    end
elseif mode == "run" then
    printSchedule(tonumber(arg[2]))
elseif mode == "pair" then
    local result, err = I.checkMeeting(arg[2], arg[3])
    if result == nil then
        io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    out(result.label .. " : " .. (result.ok and "OK" or "MORT") .. " (" .. result.reason .. ")")
    out("  il faut rejoindre : " .. result.required)
elseif mode == "plan" then
    local name = arg[2] or "Velna"
    local path = arg[3] or FIXTURE
    local chunk = assert(loadfile(path))
    local clean, err = ns.Pairing.validateAssignment(chunk())
    if clean == nil then
        io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local plan, planErr = I.buildPlan(clean, name, arg[4])
    if plan == nil then
        io.stderr:write("ERREUR: " .. tostring(planErr) .. "\n")
        os.exit(2)
    end
    out("# vue pre-pull pour " .. name .. " (" .. path .. ")")
    for _, line in ipairs(plan.lines) do
        out(line)
    end
else
    printDeclaration(mode, arg[2], arg[3])
end
