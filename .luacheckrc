-- Configuration luacheck pour addon WoW (Lua 5.1).
-- Luacheck tourne ici sous PUC-Rio Lua 5.1 : exactement le runtime du client.
std = "lua51"
max_line_length = 140

globals = {
    "GideonRaid",
    "GideonRaidDB",
    "GideonRaidCharDB",
}

read_globals = {
    -- Frames / UI
    "CreateFrame", "UIParent", "GameFontNormal", "GameFontHighlightSmall",
    "DEFAULT_CHAT_FRAME", "BackdropTemplate", "SlashCmdList",
    -- API unitaire autorisee (nom du joueur uniquement, jamais une valeur de combat)
    "UnitName", "GetLocale",
    -- Divers
    "C_Timer",
    -- Horloge CLIENTE : utilisee UNIQUEMENT par UI/ pour horodater la decision
    -- publiee dans les SavedVariables (le kit de diagnostic la relit). Core/ n'y
    -- touche jamais (logique pure).
    "time", "date",
}

files["tools/pairing_cli.lua"] = {
    std = "+busted",
}

files["tools/intermission_cli.lua"] = {
    std = "+busted",
}

files["tests/support/**"] = {
    std = "+busted",
    ignore = { "212", "431", "432" },
}

files["tests/**"] = {
    std = "+busted",
    read_globals = { "describe", "it", "setup", "before_each", "assert" },
}

exclude_files = {
    "libs",
    ".release",
}
