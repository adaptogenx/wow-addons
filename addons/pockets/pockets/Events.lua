--[[
    Events.lua - WoW event wiring and startup sequence (TDD §20)

    Owns the single ADDON_LOADED/PLAYER_ENTERING_WORLD/bag-event frame.
    Bag events are debounced into one coalesced Refresh() rather than
    rescanning on every individual event (TDD §8.1, §21).
]]

-- luacheck: globals PocketsDB PocketsCharDB BAG_UPDATE_DELAY PLAYERBANKSLOTS_FIRST_ID

local ADDON_NAME, Pockets = ...

local mainFrame = CreateFrame("Frame", "PocketsMainFrame")

local BAG_UPDATE_EVENTS = {
    BAG_UPDATE = true,
    BAG_UPDATE_DELAYED = true,
    ITEM_LOCK_CHANGED = true,
    PLAYERBANKSLOTS_CHANGED = false, -- bank is explicitly out of scope (PRD §4)
}

local DEBOUNCE_SECONDS = 0.2
local INCOMPLETE_RETRY_SECONDS = 0.5
local INCOMPLETE_RETRY_MAX = 10
local pendingRefreshTimer = nil
local incompleteRetries = 0

-- Always a fresh table copy, never a direct reference to the source -
-- Shell:SavePosition() mutates Pockets.CharDB.hud in place on every
-- drag, and aliasing it to a shared table (Constants.DEFAULT_SETTINGS.hud,
-- or another character's saved position during migration below) would
-- let a drag silently corrupt that shared table for the rest of the
-- session.
local function CopyHud(source)
    return {
        point = source.point,
        relativePoint = source.relativePoint,
        x = source.x,
        y = source.y,
        locked = source.locked,
    }
end

local function DefaultHud()
    return CopyHud(Pockets.Constants.DEFAULT_SETTINGS.hud)
end

local function EnsureSavedVariables()
    if not PocketsDB then
        PocketsDB = { version = 1, settings = {} }
    end
    if not PocketsDB.settings then
        PocketsDB.settings = {}
    end

    -- The category Grid view is gone (the list is the only view).
    PocketsDB.settings.categoryViewMode = nil

    -- The HUD mode setting is gone (Mini is the only HUD); drop stale values.
    PocketsDB.settings.hudMode = nil

    -- nil (never saved before) means "use the default"; an explicit
    -- true/false from a prior session must survive untouched.
    if PocketsDB.settings.recentItemPreviewEnabled == nil then
        PocketsDB.settings.recentItemPreviewEnabled = Pockets.Constants.DEFAULT_SETTINGS.recentItemPreviewEnabled
    end

    if not PocketsCharDB then
        PocketsCharDB = { debug = { enabled = false, verbose = false } }
    end
    if not PocketsCharDB.debug then
        PocketsCharDB.debug = { enabled = false, verbose = false }
    end
    -- Recent Items persistence pass: per-character (acquisitions are
    -- character-specific), not per-account.
    if not PocketsCharDB.recentItems then
        PocketsCharDB.recentItems = {}
    end

    -- Full Inventory category collapse state (Full Inventory redesign) -
    -- per-character (matches recentItems/hud above), keyed by categoryID
    -- -> true (collapsed). Absent/false means expanded. Presentation-only
    -- (never affects InventoryState/categorization).
    if not PocketsCharDB.collapsedCategories then
        PocketsCharDB.collapsedCategories = {}
    end

    -- HUD position pass: per-CHARACTER, not per-account - a position
    -- shared across every character on the account meant a layout tuned
    -- for one character's action bars/addons could overlap other UI
    -- entirely on a different character. One-time migration: seed this
    -- character's position from the OLD, no-longer-written account-wide
    -- PocketsDB.settings.hud if this character has never saved a
    -- position of its own yet, so at least the first character to log
    -- in after this change keeps its already-tuned spot instead of
    -- every character silently resetting to default. PocketsDB.settings.hud
    -- itself is left alone afterward (inert legacy data, not deleted).
    if not PocketsCharDB.hud then
        local legacyHud = PocketsDB.settings.hud
        PocketsCharDB.hud = legacyHud and CopyHud(legacyHud) or DefaultHud()
    end
    -- One-time migration: Pockets' V1 positioning uses a single fixed
    -- TOPLEFT anchor (UI layout pass §1). A position saved under the old
    -- CENTER-anchored scheme can't be meaningfully reprojected without a
    -- live frame, so it's reset to the TOPLEFT default rather than left
    -- to produce a mismatched anchor.
    -- A TOPLEFT-of-frame to TOPLEFT-of-UIParent offset can never be
    -- validly positive on Y (UIParent's TOPLEFT is already the top of
    -- the screen - nothing on-screen can sit above it) or negative on X.
    -- A previous drag could have saved exactly such an impossible value
    -- (UI/PositionStrategy.lua's CaptureSavedPosition used to trust
    -- frame:GetPoint()'s reported offset verbatim after a WoW drag
    -- commit, which turned out not to reliably match the TOPLEFT/TOPLEFT
    -- pairing actually applied). Treat that the same as a bad anchor
    -- type and reset to default rather than restoring an off-screen spot.
    local hud = PocketsCharDB.hud
    if hud.point ~= "TOPLEFT" or (hud.y or 0) > 1 or (hud.x or 0) < -1 then
        local locked = hud.locked
        PocketsCharDB.hud = DefaultHud()
        PocketsCharDB.hud.locked = locked or false
    end

    -- Loot Log: per-character recent activity feed, bounded by
    -- Constants.LOOT_LOG_MAX (see Core/LootLog.lua).
    if type(PocketsCharDB.lootLog) ~= "table" then
        PocketsCharDB.lootLog = { nextId = 1, entries = {} }
    end

    Pockets.SavedSettings = PocketsDB.settings
    Pockets.CharDB = PocketsCharDB
    Pockets.Services.RecentItems:LoadPersisted(PocketsCharDB.recentItems)
    Pockets.Services.LootLog:LoadPersisted(PocketsCharDB.lootLog)
end

local defaultBindingApplied = false

-- Binding APIs are not safe to call from ADDON_LOADED; the binding system
-- isn't fully initialized until around PLAYER_ENTERING_WORLD. Guarded by
-- defaultBindingApplied since PLAYER_ENTERING_WORLD can fire more than
-- once per session (zoning). Wrapped in pcall so a binding-API failure
-- degrades locally instead of breaking the rest of startup (TDD §22).
local function EnsureDefaultBinding()
    if defaultBindingApplied then
        return
    end
    defaultBindingApplied = true

    local ok, err = pcall(function()
        Pockets.Adapters.BindingsAPI:EnsureDefaultBinding("SHIFT-B", "POCKETS_TOGGLE_FULL_INVENTORY")
    end)
    if not ok and Pockets.Debug then
        Pockets.Debug:LogError("EnsureDefaultBinding failed: " .. tostring(err))
    end
end

local function ScheduleRefresh(reason)
    if pendingRefreshTimer then
        return
    end
    pendingRefreshTimer = C_Timer.NewTimer(DEBOUNCE_SECONDS, function()
        pendingRefreshTimer = nil
        local applied = Pockets.Services.InventoryState:Refresh(reason)
        if applied == false then
            if incompleteRetries < INCOMPLETE_RETRY_MAX then
                incompleteRetries = incompleteRetries + 1
                pendingRefreshTimer = C_Timer.NewTimer(INCOMPLETE_RETRY_SECONDS, function()
                    pendingRefreshTimer = nil
                    ScheduleRefresh("retry_incomplete_scan")
                end)
            end
        else
            incompleteRetries = 0
        end
    end)
end

local function InitializeAddon()
    EnsureSavedVariables()

    Pockets.UI.Shell:Initialize()
    Pockets.UI.TooltipCounts:Initialize()

    Pockets.Services.InventoryState:Refresh("initial_load")

    Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.READY, nil)

    local version = Pockets.Adapters.ClientAPI:GetAddonMetadata(ADDON_NAME, "Version") or "unknown"
    print(string.format("|cff00ff00[Pockets]|r Version %s loaded. Type /pockets help for commands.", version))
end

-- Registering an event a client doesn't know errors; degrade per event
-- instead of failing the whole file (Forever M3 §23).
local function RegisterEventSafe(event)
    local ok, err = pcall(mainFrame.RegisterEvent, mainFrame, event)
    if not ok and Pockets.Debug then
        Pockets.Debug:LogError("RegisterEvent " .. event .. " failed: " .. tostring(err))
    end
end

RegisterEventSafe("ADDON_LOADED")
RegisterEventSafe("PLAYER_ENTERING_WORLD")
RegisterEventSafe("BAG_UPDATE")
RegisterEventSafe("BAG_UPDATE_DELAYED")
RegisterEventSafe("ITEM_LOCK_CHANGED")
RegisterEventSafe("PLAYER_MONEY")
RegisterEventSafe("LOOT_OPENED")
RegisterEventSafe("LOOT_CLOSED")
RegisterEventSafe("QUEST_COMPLETE")
RegisterEventSafe("QUEST_FINISHED")
RegisterEventSafe("GET_ITEM_INFO_RECEIVED")
RegisterEventSafe("MAIL_CLOSED")
RegisterEventSafe("AUCTION_HOUSE_CLOSED")
RegisterEventSafe("PLAYER_REGEN_DISABLED")
RegisterEventSafe("PLAYER_REGEN_ENABLED")
RegisterEventSafe("UPDATE_BINDINGS")
RegisterEventSafe("ADDON_ACTION_BLOCKED")
RegisterEventSafe("ADDON_ACTION_FORBIDDEN")

mainFrame:SetScript("OnEvent", function(_, event, addonName, blockedFunc)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- Names the protected call that was refused (only ours).
        if addonName == ADDON_NAME and Pockets.Debug then
            local stack = _G.debugstack and _G.debugstack(2, 6, 0) or ""
            Pockets.Debug:LogError(event .. ": " .. tostring(blockedFunc) .. "\n" .. stack)
        end
        return
    end
    if event == "UPDATE_BINDINGS" then
        Pockets.UI.Shell:UpdateCombatBindings()
        return
    end
    if event == "ADDON_LOADED" then
        if addonName == ADDON_NAME then
            InitializeAddon()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Money baseline for Loot Log, taken here (GetMoney can still read
        -- 0 at ADDON_LOADED, which would log the whole purse). A later PEW
        -- (zoning) keeps the existing baseline.
        if Pockets.Services.LootLog.lastMoney == nil then
            Pockets.Services.LootLog:ObserveMoney(Pockets.Adapters.MoneyAPI:GetMoney())
        end
        EnsureDefaultBinding()
        ScheduleRefresh("player_entering_world")
    elseif event == "PLAYER_MONEY" then
        Pockets.Services.LootLog:ObserveMoney(Pockets.Adapters.MoneyAPI:GetMoney())
    elseif event == "LOOT_OPENED" then
        Pockets.Services.LootLog:SetLootWindowOpen(true)
    elseif event == "LOOT_CLOSED" then
        Pockets.Services.LootLog:SetLootWindowOpen(false)
    elseif event == "QUEST_COMPLETE" then
        Pockets.Services.LootLog:SetQuestWindowOpen(true)
    elseif event == "QUEST_FINISHED" then
        Pockets.Services.LootLog:SetQuestWindowOpen(false)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Late item data: re-render visible Loot Log rows (no-op unless
        -- it's the open view). Must not trigger a bag rescan.
        Pockets.UI.Shell:RefreshLootLog()
    elseif event == "PLAYER_REGEN_DISABLED" then
        Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, { inCombat = true })
    elseif event == "PLAYER_REGEN_ENABLED" then
        Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, { inCombat = false })
        -- Bags may have changed during combat; rescan, then bindings reconcile.
        ScheduleRefresh("regen_enabled")
    elseif BAG_UPDATE_EVENTS[event] ~= nil then
        if BAG_UPDATE_EVENTS[event] then
            ScheduleRefresh(event)
        end
    else
        ScheduleRefresh(event)
    end
end)

--------------------------------------------------
-- Slash commands
--------------------------------------------------

local function ShowHelp()
    print("|cff00ff00=== Pockets Commands ===|r")
    print("|cffffff00/pockets show|r - Show/hide the HUD")
    print("|cffffff00/pockets recentpreview [on||off]|r - Show or set the large icon + tooltip preview when hovering Recent items (default off)")
    print("|cffffff00/pockets help|r - Show this help")
    print("|cffffff00/pockets help dev|r - Show debug/testing commands")
    print("=========================")
end

local function ShowDevHelp()
    print("|cff00ff00=== Pockets Developer Commands ===|r")
    print("|cffffff00/pockets debug on||off|r - Enable/disable debug mode")
    print("|cffffff00/pockets debug verbose on||off|r - Enable/disable verbose logging")
    print("|cffffff00/pockets debug inventory|r - Dump current inventory state")
    print("|cffffff00/pockets debug categories|r - Dump category summary")
    print("|cffffff00/pockets debug estimator|r - Dump capacity estimator state")
    print("|cffffff00/pockets debug events|r - Dump EventBus subscriber counts")
    print("|cffffff00/pockets debug bags|r - Dump equipped bags (family/slots/Ammo classification)")
    print("|cffffff00/pockets debug secure|r - Dump active item buttons' bagID/slotID + resolved bag-index/slot IDs + cursor state")
    print("|cffffff00/pockets debug client|r - Dump client type, interface, tooltip mode, binding key")
    print("|cffffff00/pockets debug regions|r - Dump a pooled item button's visual regions (name/type/shown/size)")
    print("|cffffff00/pockets debug portrait|r - Dump the native portrait template's frames/regions (atlas, size, anchor)")
    print("|cffffff00/pockets debug ring|r - Toggle a large gridded view of the native portrait ring atlas")
    print("|cffffff00/pockets test run|r - Run automated test suite")
    print("|cffffff00/pockets test sample <used> <total> <secondsAgo>|r - Inject a capacity sample")
    print("|cffffff00/pockets test category <itemID>|r - Print the category for an item")
    print("|cffffff00/pockets test recent <itemID> <quantity>|r - Inject a Recent Items entry")
    print("|cffffff00/pockets test loot item <itemID> <quantity>|r - Inject a Loot Log item entry")
    print("|cffffff00/pockets test loot money <copper>|r - Inject a Loot Log looted-coin entry")
    print("===============================")
end

local function HandleCommand(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end
    local cmd = (args[1] or "help"):lower()

    if cmd == "show" then
        Pockets.UI.Shell:Toggle()
    elseif cmd == "recentpreview" then
        local requested = (args[2] or ""):lower()
        if requested == "on" or requested == "off" then
            Pockets.SavedSettings.recentItemPreviewEnabled = (requested == "on")
            print("[Pockets] Recent-item hover preview " .. (requested == "on" and "enabled" or "disabled"))
        elseif requested == "" then
            print("[Pockets] Recent-item hover preview is currently "
                .. (Pockets.SavedSettings.recentItemPreviewEnabled and "on" or "off"))
        else
            print("[Pockets] Usage: /pockets recentpreview on||off")
        end
    elseif cmd == "debug" then
        Pockets.Debug:HandleCommand(args)
    elseif cmd == "test" then
        Pockets.Debug:HandleTestCommand(args)
    elseif cmd == "help" then
        if (args[2] or ""):lower() == "dev" then
            ShowDevHelp()
        else
            ShowHelp()
        end
    else
        print("[Pockets] Unknown command. Type /pockets help for usage.")
    end
end

SLASH_POCKETS1 = "/pockets"
SLASH_POCKETS2 = "/pk"
SlashCmdList["POCKETS"] = HandleCommand
