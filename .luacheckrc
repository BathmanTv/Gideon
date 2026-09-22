-- luacheck configuration for a WoW addon (Lua 5.1).
-- luacheck runs here on PUC-Rio Lua 5.1: exactly the client runtime.
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
    -- allowed unit API (player name only, never a combat value)
    "UnitName", "GetLocale",
    -- Ping keybind READ-ONLY: UI/ only, under pcall, to display the key the
    -- player bound to a native ping (the addon never pings).
    "GetBindingKey",
    -- Misc
    "C_Timer",
    -- CLIENT clock: used ONLY by UI/ to timestamp the decision published in the
    -- SavedVariables (the diagnostic kit reads it back). Core/ never touches it
    -- (pure logic).
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
