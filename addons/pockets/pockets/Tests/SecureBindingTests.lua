--[[
    Tests/SecureBindingTests.lua - M2 secure-binding lifecycle: bind,
    rebind, stale detection, combat deferral, pool reuse, split safety.
    InventoryState/CombatAPI are stubbed; real state is restored.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Pool = Pockets.UI.ItemButtonPool
local InventoryState = Pockets.Services.InventoryState
local CombatAPI = Pockets.Adapters.CombatAPI

-- Runs fn(parent) with a fake InventoryState item table and combat flag,
-- restoring everything afterwards. items: { ["0:4"] = {itemID, quantity, isLocked, bagID, slotID} }
local function Scenario(items, inCombat, fn)
    local savedItems, savedCombat = InventoryState.items, CombatAPI.IsInCombat
    local savedProtected = Pool.templateProtected
    InventoryState.items = items
    CombatAPI.IsInCombat = function() return inCombat end
    Pool.templateProtected = true
    local parent = CreateFrame("Frame")
    local ok, a, b = pcall(fn, parent)
    Pool:ReleaseAll(parent)
    InventoryState.items = savedItems
    CombatAPI.IsInCombat = savedCombat
    Pool.templateProtected = savedProtected
    Pool.dirty = false
    if not ok then return false, tostring(a) end
    return a, b
end

local function Rec(bag, slot, itemID, qty, locked)
    return { bagID = bag, slotID = slot, itemID = itemID, quantity = qty, isLocked = locked or false }
end

local function Configured(parent, bag, slot, itemID)
    local button = Pool:Acquire(parent)
    Pool:Configure(button, { itemID = itemID, quantity = 5, bagID = bag, slotID = slot, interactive = true })
    return button
end

TestRunner:Register("SecureBinding: out of combat Configure binds IDs and marks valid", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    return Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        return b.secureBindingValid == true and b.secureBagID == 0 and b.secureSlotID == 4
            and b:GetID() == 4 and b.bagIndexFrame:GetID() == 0 and b.secureItemID == 123
    end)
end)

TestRunner:Register("SecureBinding: stale target is rebound out of combat to the item's smallest stack", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    return Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        items["0:4"] = Rec(0, 4, 999, 1) -- Hearthstone took the slot
        items["2:3"] = Rec(2, 3, 123, 3)
        Pool:ValidateAll()
        return b.secureBindingValid == true and b.secureBagID == 2 and b.secureSlotID == 3 and b:GetID() == 3
    end)
end)

TestRunner:Register("SecureBinding: item gone => button unbound and non-interactive", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    return Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        items["0:4"] = nil
        Pool:ValidateAll()
        return b.interactive == false and b.secureBagID == nil and b:GetID() == 0
    end)
end)

TestRunner:Register("SecureBinding: locked target is not trusted; another unlocked stack is chosen", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5), ["4:8"] = Rec(4, 8, 123, 7) }
    return Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        items["0:4"].isLocked = true
        Pool:ValidateAll()
        return b.secureBagID == 4 and b.secureSlotID == 8
    end)
end)

TestRunner:Register("SecureBinding: in combat a protected button's IDs are NOT rewritten; marked stale; repaired after", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    local combat = false
    local saved = CombatAPI.IsInCombat
    local ok, detail = Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        -- Pretend the frame is protected for this test.
        b.IsProtected = function() return true end
        CombatAPI.IsInCombat = function() return true end
        items["0:4"] = Rec(0, 4, 999, 1)
        items["2:3"] = Rec(2, 3, 123, 3)
        Pool:ValidateAll()
        local untouched = b:GetID() == 4 and b.secureSlotID == 4
        local stale = b.secureBindingValid == false and b.pendingSecure and b.pendingSecure.slotID == 3
        CombatAPI.IsInCombat = function() return false end
        Pool:Reconcile()
        local repaired = b.secureBindingValid == true and b:GetID() == 3 and b.secureBagID == 2
        b.IsProtected = nil
        return untouched and stale and repaired
    end)
    CombatAPI.IsInCombat = saved
    return ok, ok and "OK" or tostring(detail)
end)

TestRunner:Register("SecureBinding: combat + protected => ReleaseAll defers, Acquire blocked, flush after combat", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    local saved = CombatAPI.IsInCombat
    local ok = Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        b.IsProtected = function() return true end
        CombatAPI.IsInCombat = function() return true end
        Pool:ReleaseAll(parent)
        local p = Pool:GetPool(parent)
        local deferred = #(p.pendingRelease or {}) == 1 and #p.free == 0 and #p.active == 0
        local blocked = Pool:Acquire(parent) == nil
        CombatAPI.IsInCombat = function() return false end
        Pool:Reconcile()
        local flushed = #p.pendingRelease == 0 and #p.free == 1 and b:GetID() == 0 and b.secureItemID == nil
        b.IsProtected = nil
        return deferred and blocked and flushed
    end)
    CombatAPI.IsInCombat = saved
    return ok, ok and "OK" or "combat release lifecycle wrong"
end)

TestRunner:Register("SecureBinding: recycled button never keeps the previous item's secure target", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5), ["1:1"] = Rec(1, 1, 555, 1) }
    return Scenario(items, false, function(parent)
        local a = Configured(parent, 0, 4, 123)
        Pool:ReleaseAll(parent)
        local cleared = a:GetID() == 0 and a.secureItemID == nil
        local b = Configured(parent, 1, 1, 555)
        return cleared and b == a and b.secureItemID == 555 and b:GetID() == 1
    end)
end)

TestRunner:Register("SecureBinding: CanMutateProtected follows combat + IsProtected", function()
    local saved = CombatAPI.IsInCombat
    local protectedFrame = { IsProtected = function() return true end }
    local plainFrame = { IsProtected = function() return false end }
    CombatAPI.IsInCombat = function() return true end
    local inCombat = CombatAPI:CanMutateProtected(protectedFrame) == false and CombatAPI:CanMutateProtected(plainFrame) == true
    CombatAPI.IsInCombat = function() return false end
    local out = CombatAPI:CanMutateProtected(protectedFrame) == true
    CombatAPI.IsInCombat = saved
    local ok = inCombat and out
    return ok, ok and "OK" or "CanMutateProtected wrong"
end)

TestRunner:Register("SecureBinding: split uses the opened physical stack; re-validates; no-ops if gone", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 12), ["2:3"] = Rec(2, 3, 123, 3) }
    local BagAPI = Pockets.Adapters.BagAPI
    local savedSplit = BagAPI.SplitStack
    local calls = {}
    BagAPI.SplitStack = function(_, bag, slot, amount) calls[#calls + 1] = { bag, slot, amount } end
    local ok = Scenario(items, false, function(parent)
        local b = Configured(parent, 2, 3, 123)
        b.splitTarget = { bagID = 2, slotID = 3, itemID = 123 }
        b:SplitStack(2)                       -- fits stack of 3 -> splits 2:3
        b.splitTarget = { bagID = 2, slotID = 3, itemID = 123 }
        b:SplitStack(5)                       -- 5 > 3 -> no-op, never the 23 total
        b.splitTarget = { bagID = 2, slotID = 3, itemID = 123 }
        items["2:3"] = nil
        items["0:4"] = Rec(0, 4, 123, 12)
        b:SplitStack(2)                       -- target gone -> re-resolve to 0:4
        return #calls == 2 and calls[1][1] == 2 and calls[1][2] == 3 and calls[1][3] == 2
            and calls[2][1] == 0 and calls[2][2] == 4
    end)
    BagAPI.SplitStack = savedSplit
    return ok, ok and "OK" or "split target handling wrong"
end)

TestRunner:Register("SecureBinding: smallest-stack resolution (3 stacks, lock, removal)", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 12), ["2:3"] = Rec(2, 3, 123, 3), ["4:8"] = Rec(4, 8, 123, 7) }
    local saved = InventoryState.items
    InventoryState.items = items
    local a = InventoryState:ResolveSmallestStack(123)
    items["2:3"].isLocked = true
    local b = InventoryState:ResolveSmallestStack(123)
    items["2:3"] = nil
    items["4:8"] = nil
    local c = InventoryState:ResolveSmallestStack(123)
    items["0:4"] = nil
    local d = InventoryState:ResolveSmallestStack(123)
    InventoryState.items = saved
    local ok = a.slotID == 3 and b.slotID == 8 and c.slotID == 4 and d == nil
    return ok, ok and "OK" or "resolver order wrong"
end)

TestRunner:Register("SecureBinding: Forever secure attributes follow bind/unbind (type2=item, item2='bag slot')", function()
    local items = { ["0:4"] = Rec(0, 4, 123, 5) }
    return Scenario(items, false, function(parent)
        local b = Configured(parent, 0, 4, 123)
        if not b.usesSecureAttributes then
            return true -- Classic/TBC keep the template's own OnClick path
        end
        local bound = b:GetAttribute("type2") == "item" and b:GetAttribute("item2") == "0 4"
            and b:GetAttribute("shift-type2") == "none"
        items["0:4"] = nil
        Pool:ValidateAll()
        local cleared = b:GetAttribute("type2") == nil and b:GetAttribute("item2") == nil
        return bound and cleared
    end)
end)
