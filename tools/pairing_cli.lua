--[[--------------------------------------------------------------------------
    tools/pairing_cli.lua
    CLI front end of the pairing engine, usable by GIDEON (the bot calls
    `lua5.1 tools/pairing_cli.lua` with the roster on stdin).

    Input  : stdin, one line per player -> "Name,debuff"
    Output : stdout, one line per pair -> "NameA|NameB" ; unpaired players on stderr
    Exit   : 0 if at least one pair, 1 otherwise (GIDEON can then alert).

    No external dependency: runs with the lua5.1 of the VPS.
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
