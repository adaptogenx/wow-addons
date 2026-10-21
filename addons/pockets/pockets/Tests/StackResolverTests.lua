--[[
    Tests/StackResolverTests.lua - Physical stack aggregation/resolution
    (.plans/Pockets_Glance_UI.md §5, §7, §15 "aggregated item interaction")

    InventoryState:ResolveSmallestStack/IsValidStack and
    ItemButtonPool.ToButtonRecord are pure-data functions - directly
    testable with hand-built item tables, no live bag scan needed.
]]

local _, Pockets = ...

local InventoryState = Pockets.Services.InventoryState
local ItemButtonPool = Pockets.UI.ItemButtonPool

--------------------------------------------------
-- InventoryState:ResolveSmallestStack / IsValidStack
--------------------------------------------------

Pockets.Tests.TestRunner:Register("StackResolver: picks the smallest unlocked stack (20+20+3 -> 3)", function()
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 200, quantity = 20 },
        ["0:2"] = { key = "0:2", bagID = 0, slotID = 2, itemID = 200, quantity = 20 },
        ["0:3"] = { key = "0:3", bagID = 0, slotID = 3, itemID = 200, quantity = 3 },
    }
    local resolved = InventoryState:ResolveSmallestStack(200)
    local ok = resolved and resolved.bagID == 0 and resolved.slotID == 3 and resolved.quantity == 3
    return ok and true or false, ok and "OK" or "expected the smallest physical stack (qty 3) to be resolved"
end)

Pockets.Tests.TestRunner:Register("StackResolver: skips locked stacks even if smaller", function()
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 201, quantity = 2, isLocked = true },
        ["0:2"] = { key = "0:2", bagID = 0, slotID = 2, itemID = 201, quantity = 9, isLocked = false },
    }
    local resolved = InventoryState:ResolveSmallestStack(201)
    local ok = resolved and resolved.bagID == 0 and resolved.slotID == 2
    return ok and true or false, ok and "OK" or "expected the locked (smaller) stack to be skipped"
end)

Pockets.Tests.TestRunner:Register("StackResolver: returns nil when the item is no longer carried", function()
    InventoryState.items = {}
    local resolved = InventoryState:ResolveSmallestStack(999)
    return resolved == nil, resolved == nil and "OK" or "expected nil for an uncarried itemID"
end)

Pockets.Tests.TestRunner:Register("StackResolver: IsValidStack rejects a stale bag/slot (item moved away)", function()
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 300, quantity = 5 },
    }
    local staleOk = InventoryState:IsValidStack(0, 2, 300) -- slot 2 doesn't hold itemID 300
    local staleOk2 = InventoryState:IsValidStack(1, 1, 300) -- wrong bag entirely
    local currentOk = InventoryState:IsValidStack(0, 1, 300)
    local ok = staleOk == false and staleOk2 == false and currentOk == true
    return ok, ok and "OK" or "IsValidStack did not correctly distinguish stale vs. current location"
end)

Pockets.Tests.TestRunner:Register("StackResolver: IsValidStack rejects a locked stack", function()
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 301, quantity = 5, isLocked = true },
    }
    local ok = InventoryState:IsValidStack(0, 1, 301) == false
    return ok, ok and "OK" or "expected a locked stack to be rejected as invalid"
end)

Pockets.Tests.TestRunner:Register("StackResolver: another valid stack is used when the bound one goes stale", function()
    InventoryState.items = {
        ["0:2"] = { key = "0:2", bagID = 0, slotID = 2, itemID = 302, quantity = 6 },
    }
    -- Button was configured against 0:1, which no longer holds itemID 302
    -- (moved/consumed) - the resolver must fall back to the current stack.
    local valid = InventoryState:IsValidStack(0, 1, 302)
    local fallback = InventoryState:ResolveSmallestStack(302)
    local ok = valid == false and fallback and fallback.bagID == 0 and fallback.slotID == 2
    return ok and true or false, ok and "OK" or "expected fallback to the current valid stack after the bound one went stale"
end)

--------------------------------------------------
-- ItemButtonPool.ToButtonRecord (aggregate -> representative stack)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("ToButtonRecord: aggregate quantity sums across all physical stacks", function()
    local agg = {
        itemID = 400, itemLink = "item:400", texture = 1, quality = 1,
        totalQuantity = 17,
        stacks = {
            { bagID = 0, slotID = 1, quantity = 5, isLocked = false },
            { bagID = 0, slotID = 2, quantity = 5, isLocked = false },
            { bagID = 0, slotID = 3, quantity = 5, isLocked = false },
            { bagID = 0, slotID = 4, quantity = 2, isLocked = false },
        },
    }
    local record = ItemButtonPool.ToButtonRecord(agg)
    local ok = record.quantity == 17 and record.bagID == 0 and record.slotID == 4
    return ok, ok and "OK" or "expected quantity 17 bound to the smallest stack (qty 2, slot 4)"
end)

Pockets.Tests.TestRunner:Register("ToButtonRecord: single stack resolves to that stack", function()
    local agg = {
        itemID = 401, itemLink = "item:401", texture = 1, quality = 1,
        totalQuantity = 8,
        stacks = { { bagID = 1, slotID = 3, quantity = 8, isLocked = false } },
    }
    local record = ItemButtonPool.ToButtonRecord(agg)
    local ok = record.bagID == 1 and record.slotID == 3 and record.quantity == 8
    return ok, ok and "OK" or "expected the single stack to be used"
end)

Pockets.Tests.TestRunner:Register("ToButtonRecord: falls back to a locked stack only if nothing is unlocked", function()
    local agg = {
        itemID = 402, itemLink = "item:402", texture = 1, quality = 1,
        totalQuantity = 4,
        stacks = { { bagID = 0, slotID = 1, quantity = 4, isLocked = true } },
    }
    local record = ItemButtonPool.ToButtonRecord(agg)
    local ok = record.isLocked == true and record.bagID == 0 and record.slotID == 1
    return ok, ok and "OK" or "expected the only (locked) stack to still be used as a last resort"
end)
