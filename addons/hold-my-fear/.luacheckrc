-- Luacheck configuration for Hold My Fear WoW Addon
-- WoW Classic Anniversary (TBC-compatible) uses Lua 5.1
-- Based on pH's configuration, generalized for the Hold My Fear namespace

std = "lua51"
max_line_length = 140

-- Files to check
files = {
    "holdmyfear/**/*.lua",
}

-- Exclude patterns
exclude_files = {
    -- Exclude any generated files if we add them later
}

-- Ignore patterns (shared with pH)
ignore = {
    "211", -- Unused local variable
    "212", -- Unused argument (e.g. "self")
    "213", -- Unused loop variable
    "431", -- Shadowing an upvalue
    "432", -- Shadowing an upvalue argument (e.g. "self")
    "611", -- A line consists of nothing but whitespace
    "612", -- A line contains trailing whitespace
    "614", -- Trailing whitespace in a comment
    "631", -- Line is too long
}

-- WoW API globals. Add only APIs actually used; never add an addon-leaked
-- name here to silence a warning.
globals = {
    "_G",
    "HoldMyFear",
    "HoldMyFearDB",
    "SLASH_HOLDMYFEAR1",
    "SlashCmdList",
    "CreateFrame",
    "UIParent",
    "GetTime",
    "InCombatLockdown",
    "GetPlayerFacing",
    "UnitClass",
    "debugstack",
    "SetBindingClick",
    "GetMacroBody",
    "CreateMacro",
    "EditMacro",
    "GetMacroIndexByName",
    "GetBindingKey",
    "GetBindingText",
    "SaveBindings",
    "GetCurrentBindingSet",
    "GetBindingAction",
    "GetNumTrackingTypes",
    "GetTrackingInfo",
    "UnitPosition",
    "UnitGUID",
    "UnitName",
    "C_NamePlate",
    "C_Timer",
    "C_AddOns",
    "GetBuildInfo",
    "GetRaidTargetIndex",
    "SetRaidTarget",
    "hooksecurefunc",
    "wipe",
    "SLASH_HMFLAB1", "UnitExists", "UnitCanAttack", "UnitCanAttack", "SetRaidTarget", "GetRaidTargetIndex",
    "CombatLogGetCurrentEventInfo", "GetSpellInfo", "SpellStopCasting", "C_Spell", "SpellCanTargetUnit", "SpellIsTargeting", "SpellStopTargeting", "IsSpellInRange", "CastSpellByName", "TargetUnit", "FocusUnit", "STANDARD_TEXT_FONT", "GetUnitSpeed", "UnitLevel", "UnitAffectingCombat", "UnitIsDead", "UnitThreatSituation", "UnitIsUnit", "SetPortraitTexture", "UnitDebuff", "C_UnitAuras", "GetSpellTexture", "SetOverrideBindingClick", "RegisterStateDriver", "GetCVar",
    "BackdropTemplateMixin", "ChatFontNormal", "unpack", "select", "pcall", "tostring", "print", "table",
    "issecretvalue", "UnregisterStateDriver", "GameTooltip", "GetSpellDescription", "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "CurveConstants", "IsPlayerSpell", "C_SpellBook", "C_XMLUtil", "Enum", "ipairs", "pairs", "string", "math",
}
