--[[
    Events.lua - Event handling and routing for GoldPH

    Handles WoW events and routes them to accounting actions.
]]

-- luacheck: globals GetMaxPlayerLevel UnitLevel UnitXP UnitXPMax GetNumFactions GetFactionInfo GoldPH_DB_Account
-- luacheck: ignore delta

local GoldPH_Events = {}

-- Gathering spell mapping (Classic / TBC)
-- These spellIDs are stable across Classic-era clients.
local GATHERING_SPELLS = {
    [2575] = "Mining",      -- Mining
    [2366] = "Herbalism",   -- Herb Gathering
    [8613] = "Skinning",    -- Skinning
    [7620] = "Fishing",     -- Fishing
}

--------------------------------------------------
-- API Compatibility (Classic Anniversary uses C_Container)
--------------------------------------------------

-- Container API wrapper for GetContainerNumSlots
local function GetBagNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    else
        return GetContainerNumSlots(bag)
    end
end

-- Container API wrapper for GetContainerItemInfo
-- Returns: itemCount, itemLink (nil if slot is empty)
local function GetBagItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.stackCount, info.hyperlink
        end
        return nil, nil
    else
        local _, itemCount, _, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
        return itemCount, itemLink
    end
end

-- Runtime state (not persisted)
local state = {
    moneyLast = nil,

    -- Phase 2: Merchant tracking
    merchantOpen = false,

    -- Phase 5: Taxi tracking
    taxiOpen = false,
    moneyAtTaxiOpen = nil,
    taxiCostProcessed = false,

    -- Phase 6: Pickpocket and lockbox attribution windows
    pickpocketActiveUntil = 0,
    openingLockboxUntil = 0,
    openingLockboxItemID = nil,
    -- Phase 6: BAG_UPDATE fallback for lockbox opening (when UseContainerItem isn't hookable)
    lockboxBagSnapshot = nil,  -- [ "bag_slot" ] = { itemID, count } for slots with lockboxes

    -- Phase 7: Gathering node tracking
    gatherSpellSentAt = 0,
    gatherTargetName = nil,
    gatherSpellID = nil,

    -- Phase 9: XP/Rep/Honor tracking
    xpLast = nil,
    xpMaxLast = nil,
    repCache = {},  -- [factionID] = barValue (for delta computation)
}

-- Initialize event system
function GoldPH_Events:Initialize(frame)
    -- Register events
    frame:RegisterEvent("CHAT_MSG_MONEY")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("CHAT_MSG_LOOT")  -- Phase 3
    frame:RegisterEvent("BAG_UPDATE")     -- Phase 4 (vendor sale detection)
    frame:RegisterEvent("PLAYER_MONEY")   -- Phase 5 (monitor money changes for taxi)
    frame:RegisterEvent("TAXIMAP_OPENED") -- Phase 5
    frame:RegisterEvent("TAXIMAP_CLOSED") -- Phase 5
    frame:RegisterEvent("QUEST_TURNED_IN") -- Phase 5
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") -- Phase 6 (pickpocket detection, Phase 7 gathering)
    frame:RegisterEvent("UNIT_SPELLCAST_SENT")      -- Phase 7 (gathering target capture)
    frame:RegisterEvent("PLAYER_XP_UPDATE") -- Phase 9 (XP tracking)
    frame:RegisterEvent("UPDATE_FACTION") -- Phase 9 (Reputation tracking)
    frame:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN") -- Phase 9 (Honor tracking)

    -- Note: We do NOT set OnEvent handler here - init.lua maintains control
    -- and will route events to us via GoldPH_Events:OnEvent()

    -- Initialize money tracking
    state.moneyLast = GetMoney()

    -- Phase 9: Initialize XP tracking (if not max level)
    -- GetMaxPlayerLevel() or fallback to 60 for Classic
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    if UnitLevel("player") < maxLevel then
        state.xpLast = UnitXP("player")
        state.xpMaxLast = UnitXPMax("player")
    end

    -- Phase 9: Initialize reputation cache
    self:InitializeRepCache()

    -- Hook repair function (Phase 2)
    self:HookRepairFunctions()

    -- Hook vendor sales (Phase 4)
    self:HookVendorSales()
    
    -- Hook taxi node selection (Phase 5)
    self:HookTaxiFunctions()

    -- Hook lockbox opening (Phase 6)
    self:HookLockboxOpening()
end

-- Main event dispatcher
function GoldPH_Events:OnEvent(event, ...)
    -- Early return if SessionManager isn't loaded yet (can happen during addon load)
    -- Use type() check to avoid indexing nil value errors
    if type(GoldPH_SessionManager) ~= "table" then
        return
    end
    
    -- Do not record any events while session is paused (keeps gold/hr accurate)
    local session = GoldPH_SessionManager:GetActiveSession()
    if session and session.pausedAt then
        return
    end

    if event == "CHAT_MSG_MONEY" then
        self:OnLootedCoin(...)
    elseif event == "CHAT_MSG_LOOT" then
        self:OnLootedItem(...)
    elseif event == "MERCHANT_SHOW" then
        self:OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        self:OnMerchantClosed()
    elseif event == "BAG_UPDATE" then
        self:OnBagUpdateAtMerchant()
    elseif event == "PLAYER_MONEY" then
        self:OnPlayerMoney()
    elseif event == "TAXIMAP_OPENED" then
        self:OnTaxiMapOpened()
    elseif event == "TAXIMAP_CLOSED" then
        self:OnTaxiMapClosed()
    elseif event == "QUEST_TURNED_IN" then
        self:OnQuestTurnedIn(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:OnUnitSpellcastSucceeded(...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        self:OnUnitSpellcastSent(...)
    elseif event == "PLAYER_XP_UPDATE" then
        self:OnPlayerXPUpdate()
    elseif event == "UPDATE_FACTION" then
        self:OnUpdateFaction()
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        self:OnHonorGain(...)
    end
end

-- Handle CHAT_MSG_MONEY event (looted coin)
function GoldPH_Events:OnLootedCoin(message)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Parse copper amount from message
    -- Example messages:
    -- "You loot 1 Gold, 23 Silver, 45 Copper."
    -- "You loot 5 Silver, 12 Copper."
    -- "You loot 42 Copper."
    local copper = self:ParseMoneyMessage(message)

    if copper and copper > 0 then
        -- Post double-entry: Dr Assets:Cash, Cr Income:LootedCoin
        GoldPH_Ledger:Post(session, "Assets:Cash", "Income:LootedCoin", copper)

        -- Phase 6: Pickpocket and lockbox attribution (reporting only, no double-post)
        -- INVARIANT: Only ONE Post to Assets:Cash per looted coin (above).
        -- Pickpocket/FromLockbox updates are reporting-only (balances and session.pickpocket counters).
        -- This prevents double-counting cash while still tracking attribution.
        local currentTime = GetTime()
        
        -- Ensure pickpocket structure exists
        if not session.pickpocket then
            session.pickpocket = {
                gold = 0,
                value = 0,
                lockboxesLooted = 0,
                lockboxesOpened = 0,
                fromLockbox = { gold = 0, value = 0 },
            }
        end

        -- Check if within pickpocket attribution window
        if currentTime <= state.pickpocketActiveUntil then
            session.pickpocket.gold = session.pickpocket.gold + copper
            -- Reporting only: update ledger balance directly (no second Post to Assets:Cash)
            if not session.ledger.balances["Income:Pickpocket:Coin"] then
                session.ledger.balances["Income:Pickpocket:Coin"] = 0
            end
            session.ledger.balances["Income:Pickpocket:Coin"] = session.ledger.balances["Income:Pickpocket:Coin"] + copper

            if GoldPH_DB_Account.debug.verbose then
                print(string.format("[GoldPH] Pickpocket coin: %s", GoldPH_Ledger:FormatMoney(copper)))
            end
        end

        -- Check if within lockbox opening attribution window
        if currentTime <= state.openingLockboxUntil then
            session.pickpocket.fromLockbox.gold = session.pickpocket.fromLockbox.gold + copper
            -- Reporting only: update ledger balance directly (no second Post to Assets:Cash)
            if not session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] then
                session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] = 0
            end
            session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] = session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] + copper

            if GoldPH_DB_Account.debug.verbose then
                print(string.format("[GoldPH] Lockbox coin: %s", GoldPH_Ledger:FormatMoney(copper)))
            end
        end

        -- Debug logging
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Looted: %s", GoldPH_Ledger:FormatMoney(copper)))
        end

        -- Run invariants if debug mode enabled
        if GoldPH_DB_Account.debug.enabled then
            GoldPH_Debug:ValidateInvariants(session)
        end

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Parse copper amount from CHAT_MSG_MONEY message
function GoldPH_Events:ParseMoneyMessage(message)
    local totalCopper = 0

    -- Match gold
    local gold = message:match("(%d+) Gold")
    if gold then
        totalCopper = totalCopper + tonumber(gold) * 10000
    end

    -- Match silver
    local silver = message:match("(%d+) Silver")
    if silver then
        totalCopper = totalCopper + tonumber(silver) * 100
    end

    -- Match copper
    local copper = message:match("(%d+) Copper")
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end

    return totalCopper
end

--------------------------------------------------
-- Phase 3: Item Looting
--------------------------------------------------

-- Handle CHAT_MSG_LOOT event (items)
function GoldPH_Events:OnLootedItem(message)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Parse item from loot message
    -- Example: "You receive loot: [Item Link]x3."
    -- Example: "You receive loot: [Item Link]."
    local itemLink, count = self:ParseLootMessage(message)

    if not itemLink then
        return -- Not a valid item loot message
    end

    count = count or 1

    -- Extract itemID from itemLink
    local itemID = self:ExtractItemID(itemLink)
    if not itemID then
        return
    end

    -- Get item info (may be nil if not cached yet)
    local itemName, quality, itemClass, itemSubClass, vendorPrice = GoldPH_Valuation:GetItemInfo(itemID)

    if not itemName then
        -- Item not in cache yet, defer processing
        -- TODO Phase 3+: Queue for retry
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Item cache miss: itemID=%d, will retry", itemID))
        end
        return
    end

    -- Classify item into bucket
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    if bucket == "other" then
        -- Not tracked
        return
    end

    -- Phase 6: Determine attribution context (pickpocket or lockbox)
    local currentTime = GetTime()
    local isPickpocket = (currentTime <= state.pickpocketActiveUntil)
    local isFromLockbox = (currentTime <= state.openingLockboxUntil)

    -- Ensure pickpocket structure exists
    if not session.pickpocket then
        session.pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        }
    end

    -- Compute expected value
    local expectedEach = GoldPH_Valuation:ComputeExpectedValue(itemID, bucket)
    local expectedTotal = count * expectedEach

    -- Special handling for lockboxes (Phase 6)
    if bucket == "container_lockbox" then
        -- Lockboxes have 0 expected value, don't post to ledger
        -- Just track in items aggregate
        GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)

        -- If looted via pickpocket, increment lockboxesLooted counter
        if isPickpocket then
            session.pickpocket.lockboxesLooted = session.pickpocket.lockboxesLooted + count

            if GoldPH_DB_Account.debug.verbose then
                print(string.format("[GoldPH] Pickpocket lockbox looted: %s x%d", itemName, count))
            end
        end

        return
    end

    -- Post to ledger: Dr Assets:Inventory:<bucket>, Cr Income:ItemsLooted:<bucket>
    local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucket)
    local incomeAccount = "Income:ItemsLooted:" .. self:BucketToAccountName(bucket)

    GoldPH_Ledger:Post(session, assetAccount, incomeAccount, expectedTotal)

    -- Add to holdings (FIFO lot)
    GoldPH_Holdings:AddLot(session, itemID, count, expectedEach, bucket)

    -- Add to items aggregate
    GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)

    -- Phase 6: Pickpocket and lockbox attribution (reporting only, no double-post)
    if isPickpocket then
        session.pickpocket.value = session.pickpocket.value + expectedTotal
        -- Reporting only: update ledger balance directly (no second Post to Assets)
        if not session.ledger.balances["Income:Pickpocket:Items"] then
            session.ledger.balances["Income:Pickpocket:Items"] = 0
        end
        session.ledger.balances["Income:Pickpocket:Items"] = session.ledger.balances["Income:Pickpocket:Items"] + expectedTotal

        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Pickpocket item: %s x%d (%s)", itemName, count, GoldPH_Ledger:FormatMoney(expectedTotal)))
        end
    end

    if isFromLockbox then
        session.pickpocket.fromLockbox.value = session.pickpocket.fromLockbox.value + expectedTotal
        -- Reporting only: update ledger balance directly (no second Post to Assets)
        if not session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] then
            session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] = 0
        end
        session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] = session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] + expectedTotal

        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Lockbox item: %s x%d (%s)", itemName, count, GoldPH_Ledger:FormatMoney(expectedTotal)))
        end
    end

    -- Debug logging
    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] Looted: %s x%d (%s, %s each)",
            itemName, count, bucket, GoldPH_Ledger:FormatMoney(expectedEach)))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

-- Parse item link and count from CHAT_MSG_LOOT message
function GoldPH_Events:ParseLootMessage(message)
    -- Pattern: "You receive loot: [Item Link]x3."
    -- Pattern: "You receive loot: [Item Link]."
    local itemLink, countStr = message:match("You receive loot: (|c%x+|H.+|h.+|h|r)x(%d+)")

    if itemLink and countStr then
        return itemLink, tonumber(countStr)
    end

    -- Try without count (single item)
    itemLink = message:match("You receive loot: (|c%x+|H.+|h.+|h|r)")

    if itemLink then
        return itemLink, 1
    end

    return nil, nil
end

-- Extract itemID from itemLink
function GoldPH_Events:ExtractItemID(itemLink)
    -- ItemLink format: |cXXXXXXXX|Hitem:itemID:...|h[Name]|h|r
    local itemID = itemLink:match("|Hitem:(%d+):")
    if itemID then
        return tonumber(itemID)
    end
    return nil
end

-- Convert bucket name to account name component
function GoldPH_Events:BucketToAccountName(bucket)
    if bucket == "vendor_trash" then
        return "VendorTrash"
    elseif bucket == "rare_multi" then
        return "RareMulti"
    elseif bucket == "gathering" then
        return "Gathering"
    elseif bucket == "container_lockbox" then
        return "Containers:Lockbox"
    else
        return "Other"
    end
end

-- Inject a looted coin event (for testing)
function GoldPH_Events:InjectLootedCoin(copper)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not copper or copper <= 0 then
        return false, "Invalid copper amount"
    end

    -- Post directly (bypass CHAT_MSG_MONEY parsing)
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:LootedCoin", copper)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected loot: %s", GoldPH_Ledger:FormatMoney(copper)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 2: Merchant & Repair Tracking
--------------------------------------------------

-- Handle MERCHANT_SHOW event
function GoldPH_Events:OnMerchantShow()
    state.merchantOpen = true

    -- Initialize vendor sale tracking (Phase 4)
    state.bagSnapshot = self:SnapshotBags()
    state.lastMoneyCheck = GetMoney()

    if GoldPH_DB_Account.debug.verbose then
        print("[GoldPH] Merchant window opened")
    end
end

-- Handle MERCHANT_CLOSED event
function GoldPH_Events:OnMerchantClosed()
    state.merchantOpen = false

    -- Clear vendor sale tracking (Phase 4)
    state.bagSnapshot = nil
    state.lastMoneyCheck = 0

    if GoldPH_DB_Account.debug.verbose then
        print("[GoldPH] Merchant window closed")
    end
end

--------------------------------------------------
-- Phase 5: Travel (Flight Path) Expense Tracking
--------------------------------------------------

-- Handle PLAYER_MONEY event (monitor for taxi cost deduction)
function GoldPH_Events:OnPlayerMoney()
    -- Update money tracking
    local currentMoney = GetMoney()
    
    -- Debug: Always log money changes when taxi is open
    if state.taxiOpen and GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] PLAYER_MONEY: taxiOpen=%s, moneyAtTaxiOpen=%s, currentMoney=%s", 
            tostring(state.taxiOpen), 
            state.moneyAtTaxiOpen and GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen) or "nil",
            GoldPH_Ledger:FormatMoney(currentMoney)))
    end
    
    -- Check if taxi map is open and money decreased (flight cost deducted)
    -- Only process if we haven't already recorded it via TakeTaxiNode hook
    if state.taxiOpen and state.moneyAtTaxiOpen and not state.taxiCostProcessed and state.moneyAtTaxiOpen > currentMoney then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local cost = state.moneyAtTaxiOpen - currentMoney
            self:RecordTaxiCost(session, cost, "PLAYER_MONEY")
        end
    end
    
    -- Update money tracking for future events
    state.moneyLast = currentMoney
end

-- Handle TAXIMAP_OPENED event
function GoldPH_Events:OnTaxiMapOpened()
    state.taxiOpen = true
    state.moneyAtTaxiOpen = GetMoney()
    state.taxiCostProcessed = false  -- Track if we've already recorded the cost

    if GoldPH_DB_Account.debug.verbose then
        print("[GoldPH] TAXIMAP_OPENED: money=" .. GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen))
    end
end

-- Handle TAXIMAP_CLOSED event
function GoldPH_Events:OnTaxiMapClosed()
    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] TAXIMAP_CLOSED: taxiOpen=%s, moneyAtTaxiOpen=%s, costProcessed=%s",
            tostring(state.taxiOpen),
            state.moneyAtTaxiOpen and GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen) or "nil",
            tostring(state.taxiCostProcessed)))
    end
    
    -- Flight cost should already be captured via PLAYER_MONEY or TakeTaxiNode hook
    -- But check one more time in case those didn't fire (edge case)
    if state.taxiOpen and state.moneyAtTaxiOpen and not state.taxiCostProcessed then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local currentMoney = GetMoney()
            local cost = state.moneyAtTaxiOpen - currentMoney

            -- Only post expense if cost > 0
            if cost > 0 then
                -- Post double-entry: Dr Expense:Travel, Cr Assets:Cash
                GoldPH_Ledger:Post(session, "Expense:Travel", "Assets:Cash", cost)

                if GoldPH_DB_Account.debug.verbose then
                    print(string.format("[GoldPH] Flight cost (fallback on TAXIMAP_CLOSED): %s", GoldPH_Ledger:FormatMoney(cost)))
                end

                -- Run invariants if debug mode enabled
                if GoldPH_DB_Account.debug.enabled then
                    GoldPH_Debug:ValidateInvariants(session)
                end

                -- Update HUD
                GoldPH_HUD:Update()
                
                state.taxiCostProcessed = true
            end
        end
    end

    -- Clear taxi state
    state.taxiOpen = false
    state.moneyAtTaxiOpen = nil
    state.taxiCostProcessed = nil
end

--------------------------------------------------
-- Phase 5: Quest Gold Income Tracking
--------------------------------------------------

-- Handle QUEST_TURNED_IN event
-- @param questID: Quest ID
-- @param xpReward: Experience reward (unused)
-- @param moneyReward: Money reward in copper
function GoldPH_Events:OnQuestTurnedIn(questID, xpReward, moneyReward)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Only process if quest gave money reward
    if not moneyReward or moneyReward <= 0 then
        return
    end

    -- Post double-entry: Dr Assets:Cash, Cr Income:Quest
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:Quest", moneyReward)

    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] Quest reward: %s (Quest ID: %d)", 
            GoldPH_Ledger:FormatMoney(moneyReward), questID))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

--------------------------------------------------
-- Phase 6: Pickpocket Context Detection
--------------------------------------------------

-- Phase 7: Gathering Node Tracking
--------------------------------------------------

-- Handle UNIT_SPELLCAST_SENT event (capture target for gathering spells)
-- @param unitTarget: Unit that cast the spell (e.g., "player", "target")
-- @param spellName: Localized spell name
-- @param rank: Spell rank (unused)
-- @param targetName: Name of the target (e.g., "Copper Vein", "Peacebloom", "Skinning")
-- @param lineID: Cast line ID (unused)
-- @param spellID: Spell ID
function GoldPH_Events:OnUnitSpellcastSent(unitTarget, spellName, rank, targetName, lineID, spellID)
    -- Only track player casts
    if unitTarget ~= "player" then
        return
    end

    if not spellID or not GATHERING_SPELLS[spellID] then
        return
    end

    -- Record most recent gathering cast context
    state.gatherSpellSentAt = GetTime()
    state.gatherSpellID = spellID
    state.gatherTargetName = targetName

    if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
        print(string.format(
            "[GoldPH] Gathering cast sent: %s on %s",
            GATHERING_SPELLS[spellID] or (spellName or "?"),
            targetName or "unknown"
        ))
    end
end

-- Handle UNIT_SPELLCAST_SUCCEEDED event (for pickpocket detection)
-- @param unitTarget: Unit that cast the spell (e.g., "player", "target")
-- @param castGUID: Cast GUID
-- @param spellID: Spell ID
function GoldPH_Events:OnUnitSpellcastSucceeded(unitTarget, castGUID, spellID)
    -- Only process player spells
    if unitTarget ~= "player" then
        return
    end

    -- Get spell name from spell ID (used for logging and fallback labels)
    local spellName = GetSpellInfo(spellID)
    if not spellName then
        return
    end

    --------------------------------------------------
    -- Pickpocket attribution window
    --------------------------------------------------
    -- Check if this is Pick Pocket spell
    -- In Classic, the spell name is "Pick Pocket" (with space)
    if spellName == "Pick Pocket" or spellName == "Pickpocket" then
        -- Set attribution window: 2 seconds after cast
        state.pickpocketActiveUntil = GetTime() + 2.0

        if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Pick Pocket detected, attribution window: %.1f seconds", 2.0))
        end
    end

    --------------------------------------------------
    -- Gathering node tracking (Mining / Herbalism / Skinning / Fishing)
    --------------------------------------------------
    local gatherLabel = GATHERING_SPELLS[spellID]
    if gatherLabel then
        local session = GoldPH_SessionManager:GetActiveSession()
        if not session then
            return
        end

        -- Only attribute if this SUCCEEDED corresponds to a recent SENT for the same spell.
        local shouldAttribute = false
        if state.gatherSpellID == spellID and state.gatherSpellSentAt and state.gatherSpellSentAt > 0 then
            local elapsed = GetTime() - state.gatherSpellSentAt
            if elapsed >= 0 and elapsed <= 5.0 then
                shouldAttribute = true
            end
        else
            -- Fallback: if SENT wasn't captured (edge case), still count by spell label
            shouldAttribute = true
        end

        if shouldAttribute and GoldPH_SessionManager.AddGatherNode then
            local nodeName = state.gatherTargetName or gatherLabel or spellName
            GoldPH_SessionManager:AddGatherNode(session, nodeName)

            if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format("[GoldPH] Gathering node recorded: %s via %s", nodeName, gatherLabel or spellName))
            end
        end

        -- Clear gathering state after processing
        state.gatherSpellSentAt = 0
        state.gatherTargetName = nil
        state.gatherSpellID = nil
    end
end

-- Hook repair functions to track costs
function GoldPH_Events:HookRepairFunctions()
    -- Hook RepairAllItems (repair all button)
    hooksecurefunc("RepairAllItems", function(guildBankRepair)
        self:OnRepairAll(guildBankRepair)
    end)

    -- Note: We could also hook individual item repairs via UseContainerItem
    -- but RepairAllItems is the most common use case for Phase 2
end

-- Hook taxi functions to track flight costs (Phase 5)
function GoldPH_Events:HookTaxiFunctions()
    -- Hook TakeTaxiNode - called when player selects a destination
    -- This fires BEFORE the money is deducted, so we capture money state here
    if TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", function(nodeIndex)
            self:OnTakeTaxiNode(nodeIndex)
        end)
    end
end

-- Hook lockbox opening (Phase 6)
function GoldPH_Events:HookLockboxOpening()
    -- Try to hook UseContainerItem for lockbox detection
    -- Note: In Classic, this may not be hookable, so we also use BAG_UPDATE fallback
    if UseContainerItem and hooksecurefunc then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            self:OnUseContainerItemForLockbox(bag, slot)
        end)
    end
end

-- Handle TakeTaxiNode hook (when player clicks a destination)
function GoldPH_Events:OnTakeTaxiNode(nodeIndex)
    -- Only process if taxi map was open (we tracked the initial money)
    if not state.taxiOpen or not state.moneyAtTaxiOpen or state.taxiCostProcessed then
        return
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Get current money (should be before deduction, but check anyway)
    local currentMoney = GetMoney()
    
    -- Try to get cost from API if available
    local cost = nil
    if TaxiNodeCost then
        cost = TaxiNodeCost(nodeIndex)
    end
    
    -- If we can't get cost from API, use money delta
    if not cost or cost == 0 then
        -- Wait a tiny bit for money to be deducted, then check
        -- Use a frame update to check after the deduction happens
        C_Timer.After(0.1, function()
            local newMoney = GetMoney()
            local deltaCost = state.moneyAtTaxiOpen - newMoney
            if deltaCost > 0 then
                self:RecordTaxiCost(session, deltaCost, "TakeTaxiNode (delta)")
            end
        end)
    else
        -- Use the API cost directly
        self:RecordTaxiCost(session, cost, "TakeTaxiNode (API)")
    end
end

-- Helper function to record taxi cost (prevents double-counting)
function GoldPH_Events:RecordTaxiCost(session, cost, source)
    if not session or not cost or cost <= 0 or state.taxiCostProcessed then
        return
    end

    -- Post double-entry: Dr Expense:Travel, Cr Assets:Cash
    GoldPH_Ledger:Post(session, "Expense:Travel", "Assets:Cash", cost)

    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] Flight cost recorded (%s): %s", source, GoldPH_Ledger:FormatMoney(cost)))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
    
    -- Mark as processed to prevent double-counting
    state.taxiCostProcessed = true
    state.moneyAtTaxiOpen = nil  -- Clear so PLAYER_MONEY doesn't double-count
end

-- Handle repair all action
function GoldPH_Events:OnRepairAll(guildBankRepair)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Don't track guild bank repairs (player doesn't pay)
    if guildBankRepair then
        return
    end

    -- Get repair cost
    local repairCost = GetRepairAllCost()

    if repairCost and repairCost > 0 then
        -- Check if player can afford it
        local playerMoney = GetMoney()
        if playerMoney < repairCost then
            return -- Repair will fail, don't record
        end

        -- Post expense: Cr Assets:Cash (decrease), Dr Expense:Repairs
        GoldPH_Ledger:Post(session, "Expense:Repairs", "Assets:Cash", repairCost)

        -- Debug logging
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Repair cost: %s", GoldPH_Ledger:FormatMoney(repairCost)))
        end

        -- Run invariants if debug mode enabled
        if GoldPH_DB_Account.debug.enabled then
            GoldPH_Debug:ValidateInvariants(session)
        end

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Inject a repair event (for testing)
function GoldPH_Events:InjectRepair(copper)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not copper or copper <= 0 then
        return false, "Invalid copper amount"
    end

    -- Post directly: Dr Expense:Repairs, Cr Assets:Cash
    GoldPH_Ledger:Post(session, "Expense:Repairs", "Assets:Cash", copper)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected repair: %s", GoldPH_Ledger:FormatMoney(copper)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 4: Vendor Sales & FIFO Reversals
--------------------------------------------------

-- Track bag contents for vendor sale detection
state.bagSnapshot = nil
state.lastMoneyCheck = 0

-- Hook vendor sales to track items sold
function GoldPH_Events:HookVendorSales()
    -- In Classic, UseContainerItem isn't hookable, so we use BAG_UPDATE events instead
    -- The merchant events (MERCHANT_SHOW/CLOSED) are already registered
    -- We'll detect sales via BAG_UPDATE + money changes
end

-- Take snapshot of bag contents
function GoldPH_Events:SnapshotBags()
    local snapshot = {}

    for bag = 0, 4 do
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local itemCount, itemLink = GetBagItemInfo(bag, slot)
            if itemLink and itemCount then
                local itemID = self:ExtractItemID(itemLink)
                if itemID then
                    snapshot[itemID] = (snapshot[itemID] or 0) + itemCount
                end
            end
        end
    end

    return snapshot
end

-- Build per-slot snapshot of lockbox items only (for BAG_UPDATE lockbox-open detection)
-- Returns: [ "bag_slot" ] = { itemID = n, count = n }
function GoldPH_Events:SnapshotLockboxesBySlot()
    local snapshot = {}
    for bag = 0, 4 do
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local itemCount, itemLink = GetBagItemInfo(bag, slot)
            if itemLink and itemCount and itemCount > 0 then
                local itemID = self:ExtractItemID(itemLink)
                if itemID then
                    local itemName, _, quality, _, _, _, _, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemID)
                    if itemName then
                        local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
                        if bucket == "container_lockbox" then
                            local key = string.format("%d_%d", bag, slot)
                            snapshot[key] = { itemID = itemID, count = itemCount }
                        end
                    end
                end
            end
        end
    end
    return snapshot
end

-- Detect lockbox opening via BAG_UPDATE: compare previous vs current lockbox slots (Classic fallback)
function GoldPH_Events:OnBagUpdateLockboxCheck(session)
    if not session then
        return
    end
    if not session.pickpocket then
        session.pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        }
    end

    local current = self:SnapshotLockboxesBySlot()
    local previous = state.lockboxBagSnapshot

    -- First run: just store snapshot, no opened count
    if not previous then
        state.lockboxBagSnapshot = current
        return
    end

    local opened = 0
    local openedItemID = nil
    for key, prevSlot in pairs(previous) do
        local curSlot = current[key]
        local prevCount = prevSlot.count or 0
        local curCount = (curSlot and curSlot.count) or 0
        if prevCount > curCount then
            opened = opened + (prevCount - curCount)
            if not openedItemID then
                openedItemID = prevSlot.itemID
            end
        end
    end

    -- Also check: slot had lockbox, now empty or different item (current[key] nil)
    -- Already covered: curCount = 0 when curSlot is nil, so prevCount - 0 = prevCount

    if opened > 0 then
        session.pickpocket.lockboxesOpened = session.pickpocket.lockboxesOpened + opened
        state.openingLockboxUntil = GetTime() + 3.0
        state.openingLockboxItemID = openedItemID

        if GoldPH_DB_Account.debug.verbose then
            local name = openedItemID and (GetItemInfo(openedItemID) or "?") or "?"
            print(string.format("[GoldPH] Lockbox opened (BAG_UPDATE): %s x%d, attribution window: %.1f seconds",
                name, opened, 3.0))
        end
    end

    state.lockboxBagSnapshot = current
end

-- Handle BAG_UPDATE when merchant is open (detects vendor sales) or when not (lockbox opening fallback)
function GoldPH_Events:OnBagUpdateAtMerchant()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Phase 6: When NOT at merchant, detect lockbox opening via bag diff (UseContainerItem often not hookable in Classic)
    if not state.merchantOpen then
        self:OnBagUpdateLockboxCheck(session)
        return
    end

    -- Take new snapshot
    local newSnapshot = self:SnapshotBags()

    -- If we don't have an old snapshot, save this one and return
    if not state.bagSnapshot then
        state.bagSnapshot = newSnapshot
        state.lastMoneyCheck = GetMoney()
        return
    end

    -- Check for money increase (vendor proceeds)
    local currentMoney = GetMoney()
    local moneyGained = currentMoney - state.lastMoneyCheck

    if moneyGained <= 0 then
        -- No money gained, not a sale (or it's a purchase)
        state.bagSnapshot = newSnapshot
        state.lastMoneyCheck = currentMoney
        return
    end

    -- Find items that decreased in quantity
    for itemID, oldCount in pairs(state.bagSnapshot) do
        local newCount = newSnapshot[itemID] or 0
        local countSold = oldCount - newCount

        if countSold > 0 then
            -- Item was sold, process it
            local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)

            if itemName and vendorSellEach and vendorSellEach > 0 then
                -- Calculate expected proceeds for this item
                local expectedProceeds = countSold * vendorSellEach

                -- Only process if this accounts for the money gained
                -- (handles case where multiple items sold at once)
                if expectedProceeds <= moneyGained then
                    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
                    self:ProcessVendorSale(session, itemID, itemName, countSold, expectedProceeds, bucket)

                    -- Update money tracking
                    moneyGained = moneyGained - expectedProceeds
                end
            end
        end
    end

    -- Update snapshot for next check
    state.bagSnapshot = newSnapshot
    state.lastMoneyCheck = currentMoney
end

-- Handle UseContainerItem for lockbox opening detection (Phase 6)
-- Called when player uses an item from their bags (including lockboxes)
function GoldPH_Events:OnUseContainerItemForLockbox(bag, slot)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Only process if NOT at merchant (lockboxes are opened, not sold)
    if state.merchantOpen then
        return
    end

    -- Ensure pickpocket structure exists
    if not session.pickpocket then
        session.pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        }
    end

    -- Get item info
    local itemCount, itemLink = GetBagItemInfo(bag, slot)
    if not itemLink or not itemCount then
        return
    end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then
        return
    end

    -- Get item name and classify
    local itemName, _, quality, _, _, _, _, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemID)
    if not itemName then
        return
    end

    -- Check if this is a lockbox
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
    if bucket == "container_lockbox" then
        -- Set attribution window: 3 seconds after opening
        state.openingLockboxUntil = GetTime() + 3.0
        state.openingLockboxItemID = itemID
        session.pickpocket.lockboxesOpened = session.pickpocket.lockboxesOpened + 1

        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Lockbox opened: %s (ID: %d), attribution window: %.1f seconds",
                itemName, itemID, 3.0))
        end
    end
end

-- Legacy function for compatibility (now unused but kept for test injection)
function GoldPH_Events:OnUseContainerItem(bag, slot)
    -- This function is no longer called by hooks, but kept for test injection
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    if not state.merchantOpen then
        return
    end

    local itemCount, itemLink = GetBagItemInfo(bag, slot)
    if not itemLink or not itemCount then
        return
    end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then
        return
    end

    local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)
    if not itemName then
        return
    end

    if not vendorSellEach or vendorSellEach == 0 then
        return
    end

    -- Calculate total vendor proceeds
    local vendorProceeds = itemCount * vendorSellEach

    -- Classify item to get bucket
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    -- Process vendor sale
    self:ProcessVendorSale(session, itemID, itemName, itemCount, vendorProceeds, bucket)
end

-- Process a vendor sale (called by hook or test injection)
function GoldPH_Events:ProcessVendorSale(session, itemID, itemName, count, vendorProceeds, bucket)
    -- Post cash proceeds: Dr Assets:Cash, Cr Income:VendorSales
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:VendorSales", vendorProceeds)

    -- Consume FIFO lots to get held expected value by bucket
    local bucketValues = GoldPH_Holdings:ConsumeFIFO(session, itemID, count)

    -- Reverse inventory expected value for each bucket
    for bucketName, heldValue in pairs(bucketValues) do
        if heldValue > 0 then
            local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucketName)
            local equityAccount = "Equity:InventoryRealization"

            -- Cr Assets:Inventory (decrease), Dr Equity:InventoryRealization
            GoldPH_Ledger:Post(session, equityAccount, assetAccount, heldValue)
        end
    end

    -- Update item aggregate (decrement count, but keep entry for history)
    if session.items[itemID] then
        session.items[itemID].count = session.items[itemID].count - count
        if session.items[itemID].count < 0 then
            session.items[itemID].count = 0
        end
    end

    -- Debug logging
    if GoldPH_DB_Account.debug.verbose then
        local totalHeldValue = 0
        for _, val in pairs(bucketValues) do
            totalHeldValue = totalHeldValue + val
        end

        print(string.format("[GoldPH] Vendor sale: %s x%d, proceeds=%s, held expected=%s",
            itemName, count,
            GoldPH_Ledger:FormatMoney(vendorProceeds),
            GoldPH_Ledger:FormatMoney(totalHeldValue)))

        if totalHeldValue == 0 then
            print("[GoldPH]   (Pre-session item - no inventory reversal)")
        end
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

--------------------------------------------------
-- Phase 7: Test Injection - Gathering Nodes
--------------------------------------------------

-- Inject a gathering node event (for testing)
-- In real gameplay, value comes from the looted items (ore, herbs, etc.).
-- For testing, copperValueEach lets you simulate the average loot value per node.
-- @param nodeName: Human-readable node name (e.g., "Copper Vein", "Peacebloom")
-- @param count: Number of nodes to inject (default 1)
-- @param copperValueEach: Optional copper value per node to post as gathering inventory
function GoldPH_Events:InjectGatherNode(nodeName, count, copperValueEach)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not nodeName or nodeName == "" then
        return false, "Invalid node name"
    end

    count = count or 1
    if count <= 0 then
        return false, "Count must be > 0"
    end

    for i = 1, count do
        GoldPH_SessionManager:AddGatherNode(session, nodeName)
    end

    -- Post gathering inventory value if provided
    if copperValueEach and copperValueEach > 0 then
        local totalValue = count * copperValueEach
        GoldPH_Ledger:Post(session, "Assets:Inventory:Gathering", "Income:ItemsLooted:Gathering", totalValue)
    end

    -- Debug logging
    local valueStr = ""
    if copperValueEach and copperValueEach > 0 then
        valueStr = string.format(", value=%s each, total=%s",
            GoldPH_Ledger:FormatMoney(copperValueEach),
            GoldPH_Ledger:FormatMoney(count * copperValueEach))
    end
    print(string.format("[GoldPH Test] Injected gathering node: %s x%d (totalNodes=%d%s)",
        nodeName, count, session.gathering and session.gathering.totalNodes or 0, valueStr))

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 3: Test Injection - Items
--------------------------------------------------

-- Inject a looted item event (for testing)
-- @param itemID: Item ID (must be valid)
-- @param count: Number of items
function GoldPH_Events:InjectLootItem(itemID, count)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not itemID or not count or count <= 0 then
        return false, "Invalid itemID or count"
    end

    -- Get item info (may fail if not cached)
    local itemName, quality, itemClass, itemSubClass, vendorPrice = GoldPH_Valuation:GetItemInfo(itemID)

    if not itemName then
        return false, string.format("Item not in cache: itemID=%d (try mousing over it first)", itemID)
    end

    -- Classify and value item
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    if bucket == "other" then
        return false, string.format("Item not tracked: %s (bucket=other)", itemName)
    end

    local expectedEach = GoldPH_Valuation:ComputeExpectedValue(itemID, bucket)

    -- Post to ledger (unless lockbox)
    if bucket ~= "container_lockbox" then
        local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucket)
        local incomeAccount = "Income:ItemsLooted:" .. self:BucketToAccountName(bucket)

        local expectedTotal = count * expectedEach
        GoldPH_Ledger:Post(session, assetAccount, incomeAccount, expectedTotal)

        -- Add to holdings
        GoldPH_Holdings:AddLot(session, itemID, count, expectedEach, bucket)
    end

    -- Add to items aggregate
    GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected loot: %s x%d (bucket=%s, %s each)",
        itemName, count, bucket, GoldPH_Ledger:FormatMoney(expectedEach)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB_Account.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 4: Test Injection - Vendor Sales
--------------------------------------------------

-- Inject a vendor sale event (for testing)
-- @param itemID: Item ID (must be valid and in holdings)
-- @param count: Number of items to sell
function GoldPH_Events:InjectVendorSale(itemID, count)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not itemID or not count or count <= 0 then
        return false, "Invalid itemID or count"
    end

    -- Get item info
    local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)

    if not itemName then
        return false, string.format("Item not in cache: itemID=%d (try mousing over it first)", itemID)
    end

    if not vendorSellEach or vendorSellEach == 0 then
        return false, string.format("Item has no vendor value: %s", itemName)
    end

    -- Check if item is in holdings
    local holdingsCount = GoldPH_Holdings:GetCount(session, itemID)
    if holdingsCount < count then
        return false, string.format("Not enough in holdings: have %d, trying to sell %d", holdingsCount, count)
    end

    -- Calculate vendor proceeds
    local vendorProceeds = count * vendorSellEach

    -- Classify item
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    -- Process vendor sale
    self:ProcessVendorSale(session, itemID, itemName, count, vendorProceeds, bucket)

    print(string.format("[GoldPH Test] Injected vendor sale: %s x%d for %s",
        itemName, count, GoldPH_Ledger:FormatMoney(vendorProceeds)))

    return true
end

--------------------------------------------------
-- Phase 9: XP/Rep/Honor Tracking
--------------------------------------------------

-- Initialize reputation cache (scan all factions, use factionID as stable key)
function GoldPH_Events:InitializeRepCache()
    state.repCache = {}

    local numFactions = GetNumFactions()
    for i = 1, numFactions do
        local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = GetFactionInfo(i)

        -- Skip headers, use factionID as stable key
        if not isHeader and factionID then
            state.repCache[factionID] = barValue
        end
    end

    if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
        local count = 0
        for _ in pairs(state.repCache) do count = count + 1 end
        print(string.format("[GoldPH] Initialized reputation cache with %d factions", count))
    end
end

-- Handle PLAYER_XP_UPDATE event (XP gains with rollover detection for level-ups)
function GoldPH_Events:OnPlayerXPUpdate()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Skip if max level
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    if UnitLevel("player") >= maxLevel then
        return
    end

    -- Ensure metrics structure exists
    if not session.metrics then
        session.metrics = {
            xp = { gained = 0, enabled = false },
            rep = { gained = 0, enabled = false, byFaction = {} },
            honor = { gained = 0, enabled = false, kills = 0 },
        }
    end
    if not session.metrics.xp then
        session.metrics.xp = { gained = 0, enabled = false }
    end

    local newXP = UnitXP("player")
    local newXPMax = UnitXPMax("player")

    -- First update: just store values
    if not state.xpLast then
        state.xpLast = newXP
        state.xpMaxLast = newXPMax
        session.metrics.xp.enabled = true
        return
    end

    -- Compute delta with rollover detection
    local delta = 0  -- luacheck: ignore 311 (false positive, variable is used below)
    if newXP >= state.xpLast then
        -- Normal gain (no level-up)
        delta = newXP - state.xpLast
    else
        -- Level-up detected (XP wrapped from high to low)
        delta = (state.xpMaxLast - state.xpLast) + newXP
    end

    -- Update session metrics
    session.metrics.xp.gained = session.metrics.xp.gained + delta
    session.metrics.xp.enabled = true

    -- Update runtime state
    state.xpLast = newXP
    state.xpMaxLast = newXPMax

    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH] XP gained: %d (total: %d)", delta, session.metrics.xp.gained))
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

-- Handle UPDATE_FACTION event (Reputation gains)
function GoldPH_Events:OnUpdateFaction()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Ensure metrics structure exists
    if not session.metrics then
        session.metrics = {
            xp = { gained = 0, enabled = false },
            rep = { gained = 0, enabled = false, byFaction = {} },
            honor = { gained = 0, enabled = false, kills = 0 },
        }
    end
    if not session.metrics.rep then
        session.metrics.rep = { gained = 0, enabled = false, byFaction = {} }
    end

    -- Scan all factions and compute deltas
    local numFactions = GetNumFactions()
    local totalDelta = 0

    for i = 1, numFactions do
        local name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID = GetFactionInfo(i)

        -- Skip headers, use factionID as stable key
        if not isHeader and factionID and name then
            local oldValue = state.repCache[factionID] or barValue
            local delta = barValue - oldValue

            if delta > 0 then
                -- Reputation gained
                totalDelta = totalDelta + delta

                -- Update per-faction totals
                if not session.metrics.rep.byFaction[name] then
                    session.metrics.rep.byFaction[name] = 0
                end
                session.metrics.rep.byFaction[name] = session.metrics.rep.byFaction[name] + delta

                if GoldPH_DB_Account.debug.verbose then
                    print(string.format("[GoldPH] Rep gained: %s +%d", name, delta))
                end
            end

            -- Update cache
            state.repCache[factionID] = barValue
        end
    end

    if totalDelta > 0 then
        session.metrics.rep.gained = session.metrics.rep.gained + totalDelta
        session.metrics.rep.enabled = true

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Handle CHAT_MSG_COMBAT_HONOR_GAIN event (Honor gains)
function GoldPH_Events:OnHonorGain(message)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Ensure metrics structure exists
    if not session.metrics then
        session.metrics = {
            xp = { gained = 0, enabled = false },
            rep = { gained = 0, enabled = false, byFaction = {} },
            honor = { gained = 0, enabled = false, kills = 0 },
        }
    end
    if not session.metrics.honor then
        session.metrics.honor = { gained = 0, enabled = false, kills = 0 }
    end

    -- Parse honor amount from message
    -- Patterns: "You have been awarded 42 honor points." or "You have gained 10 honor."
    local amount = message:match("(%d+) honor")
    if not amount then
        amount = message:match("awarded (%d+) honor")
    end

    if amount then
        amount = tonumber(amount)
        session.metrics.honor.gained = session.metrics.honor.gained + amount
        session.metrics.honor.enabled = true

        -- Optional: detect HK with "killing blow"
        if message:find("killing blow") then
            session.metrics.honor.kills = session.metrics.honor.kills + 1
        end

        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH] Honor gained: %d (total: %d, HKs: %d)",
                amount, session.metrics.honor.gained, session.metrics.honor.kills))
        end

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Export module
_G.GoldPH_Events = GoldPH_Events
