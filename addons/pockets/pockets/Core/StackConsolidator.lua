--[[
    Core/StackConsolidator.lua - Automatic partial-stack consolidation (TDD §5, §12)

    The one intentional inventory-management behavior in v1. v1 ships the
    loop-protection/transaction scaffolding; the actual slot-move
    implementation is deferred to Phase 5 (TDD §29) and must be built
    against the target client's exact container-move APIs.
]]

local _, Pockets = ...

Pockets.Services.StackConsolidator = Pockets.Services.StackConsolidator or {}
local StackConsolidator = Pockets.Services.StackConsolidator

-- Incremented for every consolidation pass; lets InventoryState/RecentItems
-- recognize bag-change events caused by Pockets itself (TDD §12.3).
StackConsolidator.generation = StackConsolidator.generation or 0
StackConsolidator.transactionActive = StackConsolidator.transactionActive or false

function StackConsolidator:IsTransactionActive()
    return self.transactionActive
end

-- Finds compatible partial-stack pairs (same itemID, same capacityClass,
-- neither locked) eligible for consolidation. Returns a plan array of
-- { itemID, fromKey, toKey } without moving anything - callers execute it.
function StackConsolidator:BuildPlan()
    local plan = {}
    local byItemID = {}

    for key, record in pairs(Pockets.Services.InventoryState:GetItems()) do
        if not record.isLocked and record.maxStack and record.maxStack > 1
            and record.quantity < record.maxStack then
            byItemID[record.itemID] = byItemID[record.itemID] or {}
            table.insert(byItemID[record.itemID], { key = key, record = record })
        end
    end

    for itemID, partials in pairs(byItemID) do
        if #partials > 1 then
            table.sort(partials, function(a, b) return a.record.quantity < b.record.quantity end)
            for i = 1, #partials - 1 do
                table.insert(plan, {
                    itemID = itemID,
                    fromKey = partials[i].key,
                    toKey = partials[i + 1].key,
                })
            end
        end
    end

    return plan
end

-- Schedules one consolidation pass if eligible (no item currently on the
-- cursor, no transaction already active). Actual slot moves are performed
-- by an adapter-level executor once implemented (Phase 5).
function StackConsolidator:ScheduleConsolidationPass()
    if self.transactionActive then
        return false, "consolidation already in progress"
    end

    local plan = self:BuildPlan()
    if #plan == 0 then
        return false, "nothing to consolidate"
    end

    self.transactionActive = true
    self.generation = self.generation + 1

    -- Phase 5 TODO: execute `plan` via a dedicated slot-move adapter method
    -- (added to Adapters/BagAPI.lua), then clear transactionActive.
    self.transactionActive = false

    return true, plan
end
