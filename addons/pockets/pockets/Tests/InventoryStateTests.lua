--[[
    Tests/InventoryStateTests.lua - Aggregate capacity math (TDD §24.1)

    Full bag-scan/diff behavior requires live container APIs and is covered
    by the manual acceptance matrix (TESTING_GUIDE.md) and future in-game
    tests. These tests exercise the pure aggregate helpers that don't
    require a real bag scan.
]]

local _, Pockets = ...

local InventoryState = Pockets.Services.InventoryState

Pockets.Tests.TestRunner:Register("InventoryState: capacity result shape", function()
    local result = InventoryState:BuildCapacityResult({ used = 55, total = 70 })
    local ok = result.used == 55 and result.total == 70 and result.free == 15
        and math.abs(result.utilization - (55 / 70)) < 0.0001
    return ok, ok and "OK" or "capacity result fields did not match expected shape"
end)

Pockets.Tests.TestRunner:Register("InventoryState: zero-total capacity does not divide by zero", function()
    local result = InventoryState:BuildCapacityResult({ used = 0, total = 0 })
    local ok = result.utilization == 0
    return ok, ok and "OK" or string.format("expected utilization 0, got %s", tostring(result.utilization))
end)

Pockets.Tests.TestRunner:Register("InventoryState: general vs ammo are independent pools", function()
    InventoryState.generalCapacity = InventoryState:BuildCapacityResult({ used = 68, total = 68 })
    InventoryState.ammoCapacity = InventoryState:BuildCapacityResult({ used = 4, total = 16 })

    local general = InventoryState:GetGeneralCapacity()
    local ammo = InventoryState:GetAmmoCapacity()
    local ok = general.free == 0 and ammo.free == 12
    return ok, ok and "OK" or "general-full-while-ammo-has-space scenario failed"
end)

Pockets.Tests.TestRunner:Register("InventoryState: carried quantity defaults to zero for unseen item", function()
    local qty = InventoryState:GetCarriedQuantity(-1)
    return qty == 0, qty == 0 and "OK" or string.format("expected 0, got %s", tostring(qty))
end)

Pockets.Tests.TestRunner:Register("InventoryState: bag-full ETA sampling uses GENERAL capacity only, never ammo", function()
    local BagAPI = Pockets.Adapters.BagAPI
    local CapacityEstimator = Pockets.Services.CapacityEstimator
    local originalScan = BagAPI.ScanAllBags
    local originalCounts = BagAPI.GetCapacityCounts

    -- Stub the adapter boundary (no live bag scan needed): empty bags so
    -- BuildRecord never runs, and a GENERAL/AMMO split that would be
    -- wrong if ETA sampling ever blended the two pools.
    BagAPI.ScanAllBags = function() return {} end
    BagAPI.GetCapacityCounts = function()
        return { general = { used = 10, total = 20 }, ammo = { used = 5, total = 16 } }
    end

    -- Refresh() overwrites the previous-quantities snapshot with this
    -- stub's empty bags; left that way, the next REAL refresh would diff
    -- the whole inventory against nothing and log every carried item to
    -- Recent / the persisted Loot Log as freshly acquired.
    local originalPrevious = InventoryState.previousQuantitiesByItemID
    CapacityEstimator:Reset("test")
    InventoryState:Refresh("test")
    InventoryState.previousQuantitiesByItemID = originalPrevious

    BagAPI.ScanAllBags = originalScan
    BagAPI.GetCapacityCounts = originalCounts

    local last = CapacityEstimator.samples[#CapacityEstimator.samples]
    local ok = last and last.usedSlots == 10 and last.totalSlots == 20
    return ok, ok and "OK" or "estimator sample did not match GENERAL capacity (ammo may have leaked in)"
end)

-- Regression: at login, self.generalCapacity is still nil when the very
-- first Refresh() runs, so a guard keyed on "only skip if we already had
-- a good snapshot" does nothing here - an incomplete first scan (bags
-- still registering right after ADDON_LOADED) got committed as if it
-- were the real total, and nothing ever corrected it afterward since a
-- scan that matches itself reads as complete forever after.
Pockets.Tests.TestRunner:Register("InventoryState: incomplete first scan at login is never committed, even with no prior snapshot", function()
    local BagAPI = Pockets.Adapters.BagAPI
    local originalScan = BagAPI.ScanAllBags
    local originalCounts = BagAPI.GetCapacityCounts

    InventoryState.generalCapacity = nil
    InventoryState.ammoCapacity = nil

    -- Simulates bags 1-4 not yet reporting equipped right after
    -- ADDON_LOADED: backpack alone would look like the whole inventory.
    BagAPI.ScanAllBags = function() return {}, true end
    BagAPI.GetCapacityCounts = function()
        return { general = { used = 0, total = 16 }, ammo = { used = 0, total = 0 } }
    end

    local applied = InventoryState:Refresh("initial_load")

    BagAPI.ScanAllBags = originalScan
    BagAPI.GetCapacityCounts = originalCounts

    local ok = applied == false and InventoryState.generalCapacity == nil
    return ok, ok and "OK" or string.format(
        "expected incomplete first scan to be rejected (applied=%s, generalCapacity=%s)",
        tostring(applied), tostring(InventoryState.generalCapacity))
end)

Pockets.Tests.TestRunner:Register("InventoryState: AggregateRecords collapses split stacks into one itemID entry", function()
    local records = {
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 1 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 2 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 20, bagID = 0, slotID = 3 },
        { itemID = 100, itemLink = "item:100", name = "Netherweave Cloth", texture = 1, quality = 1,
            categoryID = "trade_goods", quantity = 3, bagID = 0, slotID = 4 },
    }
    local aggregates = InventoryState:AggregateRecords(records)
    local ok = #aggregates == 1 and aggregates[1].totalQuantity == 63 and #aggregates[1].stacks == 4
    return ok, ok and "OK" or string.format(
        "expected 1 aggregate at 63 total across 4 stacks, got %d aggregates, total=%s",
        #aggregates, ok and "" or tostring(aggregates[1] and aggregates[1].totalQuantity))
end)

-- Physical stack resolver (.plans/Pockets_Glance_UI.md §7) picks the
-- SMALLEST unlocked stack, not just any/the first unlocked one - less
-- disruptive to manipulate. slotID 1 (qty 20) is locked and skipped;
-- between the two unlocked stacks (40, 3), the smaller (slotID 3) wins.
Pockets.Tests.TestRunner:Register("ItemButtonPool.ToButtonRecord: sums totalQuantity into quantity, prefers the smallest unlocked stack", function()
    local agg = {
        itemID = 100, itemLink = "item:100", texture = 1, quality = 1, totalQuantity = 63,
        stacks = {
            { bagID = 0, slotID = 1, quantity = 20, isLocked = true },
            { bagID = 0, slotID = 2, quantity = 40, isLocked = false },
            { bagID = 0, slotID = 3, quantity = 3, isLocked = false },
        },
    }
    local record = Pockets.UI.ItemButtonPool.ToButtonRecord(agg)
    local ok = record.quantity == 63 and record.bagID == 0 and record.slotID == 3 and record.interactive == true
    return ok, ok and "OK" or string.format(
        "expected quantity=63 slotID=3(smallest unlocked), got quantity=%s slotID=%s",
        tostring(record.quantity), tostring(record.slotID))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool.ToButtonRecord: no stacks means non-interactive", function()
    local agg = { itemID = 1, texture = 1, totalQuantity = 0, stacks = {} }
    local record = Pockets.UI.ItemButtonPool.ToButtonRecord(agg)
    local ok = record.interactive == false and record.bagID == nil
    return ok, ok and "OK" or "expected a stack-less aggregate to be non-interactive"
end)

Pockets.Tests.TestRunner:Register("InventoryState: AggregateRecords keeps distinct itemIDs separate, in first-seen order", function()
    local records = {
        { itemID = 200, name = "Linen Cloth", quantity = 10, bagID = 0, slotID = 1 },
        { itemID = 300, name = "Wool Cloth", quantity = 5, bagID = 0, slotID = 2 },
        { itemID = 200, name = "Linen Cloth", quantity = 8, bagID = 0, slotID = 3 },
    }
    local aggregates = InventoryState:AggregateRecords(records)
    local ok = #aggregates == 2 and aggregates[1].itemID == 200 and aggregates[1].totalQuantity == 18
        and aggregates[2].itemID == 300 and aggregates[2].totalQuantity == 5
    return ok, ok and "OK" or "expected two distinct aggregates in first-seen order"
end)
