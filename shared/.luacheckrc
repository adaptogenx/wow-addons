-- Luacheck configuration for shared/ui (canonical shared library).
-- Strict on purpose: setting a global (code 111/112/121) is an error, so a
-- shared file can never leak a global like _G.PHUI. WoW API names are
-- read-only.
std = "lua51"
max_line_length = 140

files = { "ui/*.lua" }

ignore = {
    "211", -- Unused local variable (e.g. `addonName`)
    "212", -- Unused argument (e.g. "self")
    "213", -- Unused loop variable
    "431", "432", -- Shadowing
    "611", "612", "614", "631",
}

read_globals = {
    "CreateFrame", "UIParent", "GameTooltip", "GetBuildInfo",
}
