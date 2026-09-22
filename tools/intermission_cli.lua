--[[--------------------------------------------------------------------------
    tools/intermission_cli.lua

    Interface CLI hors jeu du module « Intermission Coach ». Elle sert a :
      - relire la convention (positions, pings, consignes) sans ouvrir le client ;
      - generer la macro de ping a coller dans le jeu (le texte exact) ;
      - verifier une rencontre (« 2 rencontre 3 » -> mort) ;
      - afficher la vue pre-pull a partir d'un bloc d'assignation prepare.

    Usage (depuis la racine du depot) :
      lua5.1 tools/intermission_cli.lua all
      lua5.1 tools/intermission_cli.lua 2
      lua5.1 tools/intermission_cli.lua pair 2 3
      lua5.1 tools/intermission_cli.lua plan [Nom] [chemin/du/fixture.lua]

    Aucune dependance externe : uniquement le lua5.1 du VPS.
----------------------------------------------------------------------------]]
package.path = "./?.lua;./?/init.lua;" .. package.path

local wowenv = require("tests.support.wowenv")
local ns = wowenv.loadCore()
local I = ns.Intermission

local FIXTURE = "tests/fixtures/assignment_sample.lua"

local function out(line)
    io.write(line .. "\n")
end

local function usage()
    out("usage: intermission_cli.lua all | 1|2|3 | pair A B | plan [Nom] [fixture.lua]")
    os.exit(2)
end

local function printDeclaration(declaration)
    local rec, err = I.getDeclaration(declaration)
    if rec == nil then
        io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    out("TU ES " .. rec.n .. "  (" .. rec.orbs .. ")")
    out("  POSITION : " .. rec.positionLabel)
    out("  PING     : " .. rec.pingColor .. " (" .. rec.ping .. ")")
    out("  FAIS     : " .. rec.action)
    out("  REJOINS  : " .. rec.find)
    local macro = assert(I.buildMacro(rec.n))
    out("  MACRO    : " .. macro.primary)
    out("  SECOURS  : " .. macro.fallback .. "  (" .. macro.note .. ")")
    return rec
end

local mode = arg[1]
if mode == nil then
    usage()
elseif mode == "all" then
    out("Convention Intermission Coach (Entombed Sentinels mythique)")
    out("fenetre de visibilite : " .. I.VISIBILITY_SECONDS .. " s ; 2+2 et 1+3 sauvent ; 2+3 = 5 verts = mort")
    out("")
    for _, declaration in ipairs(I.DECLARATIONS) do
        printDeclaration(declaration)
        out("")
    end
elseif mode == "pair" then
    local result, err = I.checkMeeting(arg[2], arg[3])
    if result == nil then
        io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    out(result.label .. " : " .. (result.ok and "OK" or "MORT") .. " (" .. result.reason .. ")")
elseif mode == "plan" then
    local name = arg[2] or "Velna"
    local path = arg[3] or FIXTURE
    local chunk = assert(loadfile(path))
    local clean, err = ns.Pairing.validateAssignment(chunk())
    if clean == nil then
        io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
        os.exit(2)
    end
    local plan, planErr = I.buildPlan(clean, name)
    if plan == nil then
        io.stderr:write("ERREUR: " .. tostring(planErr) .. "\n")
        os.exit(2)
    end
    out("# vue pre-pull pour " .. name .. " (" .. path .. ")")
    for _, line in ipairs(plan.lines) do
        out(line)
    end
else
    printDeclaration(mode)
end
