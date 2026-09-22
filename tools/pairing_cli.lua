--[[--------------------------------------------------------------------------
    tools/pairing_cli.lua
    Interface CLI du moteur d'appariement, utilisable par GIDEON (le bot appelle
    `lua5.1 tools/pairing_cli.lua` avec le roster au format JSON-like ou CSV).

    Entree  : stdin, une ligne par joueur -> "Nom,debuff"
    Sortie  : stdout, une ligne par paire -> "NomA|NomB" ; non-apparies sur stderr
    Exit    : 0 si au moins une paire, 1 sinon (GIDEON peut alerter).

    Aucune dependance externe : fonctionne avec le lua5.1 du VPS.
----------------------------------------------------------------------------]]
package.path = "./?.lua;./?/init.lua;" .. package.path

local wowenv = require("tests.support.wowenv")
local ns = wowenv.loadCore()
local Pairing = ns.Pairing

local players = {}
for line in io.lines() do
    local name, debuff = line:match("^%s*([^,]+)%s*,%s*(.-)%s*$")
    if name then
        players[#players + 1] = { name = name, debuff = debuff }
    end
end

local res, err = Pairing.buildPairs(players)
if not res then
    io.stderr:write("ERREUR: " .. tostring(err) .. "\n")
    os.exit(2)
end

for _, pair in ipairs(res.pairs) do
    io.write(pair.a .. "|" .. pair.b .. "\n")
end
for _, u in ipairs(res.unpaired) do
    io.stderr:write("NON-APPARIE: " .. u.name .. " (" .. u.reason .. ")\n")
end

os.exit(#res.pairs > 0 and 0 or 1)
