-- Luacheck configuration for Pockets WoW Addon
-- WoW Classic Anniversary (TBC-compatible) uses Lua 5.1
-- Based on pH's configuration, generalized for the Pockets namespace

std = "lua51"
max_line_length = 140

-- Files to check
files = {
    "pockets/**/*.lua",
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

-- WoW API globals
globals = {
    -- Pockets-specific globals (must be included)
    "_G",
    "Pockets",
    "PocketsDB",
    "PocketsCharDB",
    "SLASH_POCKETS1",
    "SLASH_POCKETS2",
    "SlashCmdList",

    -- Core WoW API
    "GetTime",
    "time",
    "date",
    "CreateFrame",
    "UIParent",
    "hooksecurefunc",
    "print",
    "error",
    "pcall",
    "tostring",
    "tonumber",
    "string",
    "math",
    "table",
    "pairs",
    "ipairs",
    "select",
    "type",
    "next",
    "unpack",
    "wipe",
    "InCombatLockdown",
    "GameTooltip",
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontNormalLarge",
    "BackdropTemplateMixin",
    "ChatFontNormal",
    "UISpecialFrames",

    -- Item / bag API (Classic container API)
    "GetItemInfo",
    "C_Item",
    "C_AddOns",
    "GetBuildInfo",
    "GetAddOnMetadata",
    "issecretvalue",
    "GetItemIcon",
    "GetItemQualityColor",
    "ChatEdit_InsertLink",
    "GetCurrentKeyBoardFocus",
    "GetItemInfoInstant",
    "GetItemFamily",
    "bit",
    "GetItemCount",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetContainerItemLink",
    "GetContainerItemID",
    "PickupContainerItem",
    "SplitContainerItem",
    "UseContainerItem",
    "OpenStackSplitFrame",
    "StackSplitFrame",
    "ChatEdit_GetActiveWindow",
    "ChatFrameUtil",
    "HandleModifiedItemClick",
    "IsModifiedClick",
    "GetInventorySlotInfo",
    "GetInventoryItemLink",
    "IsInventoryItemLocked",
    "GetContainerNumFreeSlots",
    "C_Container",
    "GetMoney",

    -- Mailbox API (Mail Attach pass - Adapters/MailAPI.lua only)
    "SendMailFrame",
    "GetSendMailItem",
    "SetSendMailItem",
    "ATTACHMENTS_MAX_SEND",
    "C_MailInfo",
    "ClearCursor",
    "CursorHasItem",
    "C_Timer",
    "C_Timer.After",
    "C_Timer.NewTicker",
    "C_Timer.NewTimer",
    "GetMouseFocus",
    "GetMouseFoci",

    -- Combat / binding API
    "GetBindingKey",
    "SetBinding",
    "SaveBindings",
    "GetCurrentBindingSet",

    -- Tooltip API
    "GameTooltip_SetDefaultAnchor",

    -- Item button visuals
    "SetItemButtonDesaturated",
    "SetItemButtonCount",
    "ITEM_QUALITY_COLORS",
    "SecureActionButton_OnClick",

    -- Misc WoW API/constants referenced by adapters
    "ContainerIDToInventoryID",
    "ITEM_CLASS_QUEST",
}

-- Pockets intentionally exposes one global entry point for the binding
-- action handler (Adapters/BindingsAPI.lua); declare it here rather than
-- disabling the "setting non-standard global" check broadly.
globals[#globals + 1] = "Pockets_ToggleFullInventory"
