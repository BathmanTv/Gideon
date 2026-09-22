--[[--------------------------------------------------------------------------
    tools/intermission_cli.lua

    Out-of-game CLI front end of the "Intermission Coach" module. It is used to:
      - review the THREE color states (3V1R / 2V2R / 1V3R) without the client;
      - generate the ping macro to paste in game (the exact text);
      - check a meeting ("3V1R meets 2V2R" -> 5 green -> dead);
      - display the pre-pull view from a prepared assignment block.

    Usage (from the repository root):
      lua5.1 tools/intermission_cli.lua all
      lua5.1 tools/intermission_cli.lua 3V1R
      lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R
      lua5.1 tools/intermission_cli.lua plan [Name] [path/to/fixture.lua]

    No external dependency: only the lua5.1 of the VPS.
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
    out("usage: intermission_cli.lua all | 3V1R|2V2R|1V3R | pair A B | plan [Nom] [fixture.lua]")
    os.exit(2)
end

local function printDeclaration(declaration)
    local rec, err = I.getDeclaration(declaration)
    if rec == nil then
        out("REFUS : " .. tostring(err))
        return nil
    end
    out("TU VOIS : " .. rec.display .. "  (" .. rec.key .. ")")
    out("  NUMERO   : " .. rec.numberText .. (rec.numberAmbiguous and "  (AMBIGU : la couleur tranche)" or "  (non ambigu)"))
    out("  FAIS     : " .. rec.action)
    out("  POSITION : " .. rec.positionLabel)
    out("  REJOINS  : " .. rec.complement)
    out("  PING     : " .. rec.pingColor .. " (" .. rec.ping .. ")")
    local macro = assert(I.buildMacro(rec.key))
    out("  MACRO    : " .. macro.primary)
    out("  SECOURS  : " .. macro.fallback .. "  (" .. macro.note .. ")")
    return rec
end

local mode = arg[1]
if mode == nil then
    usage()
elseif mode == "all" then
    out("Etats de l'Intermission Coach (Entombed Sentinels mythique)")
    out("fenetre de visibilite : " .. I.VISIBILITY_SECONDS .. " s")
    out("sauvent : 3V1R + 1V3R = 4 verts + 4 rouges ; 2V2R + 2V2R = 4 verts + 4 rouges")
    out("tuent   : 3V1R + 2V2R = 5 verts (« 5g ») ; 1V3R + 1V3R ; 3V1R + 3V1R")
    out("le numero 1 ou 3 est AMBIGU : c'est la COULEUR qui decide (seul '2' est non ambigu)")
    out("")
    for _, declaration in ipairs(I.STATES) do
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
