--[[
    Core/InventoryState.lua - Authoritative normalized inventory (TDD §5.1, §6, §8)

    Owns the current snapshot of carried items plus capacity aggregates.
    UI modules read from here; they must never rescan bags themselves
    (TDD §3.1). Refresh() is the single entry point that turns a raw
    BagAPI scan into normalized records, diffs it against the previous
    snapshot to find true acquisitions (TDD §8.2), updates the capacity
    estimator, and publishes domain events.
]]

local _, Pockets = ...

Pockets.Services.InventoryState = Pockets.Services.InventoryState or {}
local InventoryState = Pockets.Services.InventoryState

local Constants = Pockets.Constants
local EventBus = Pockets.Services.EventBus

InventoryState.items = InventoryState.items or {} -- key "bag:slot" -> normalized item record
InventoryState.previousQuantitiesByItemID = InventoryState.previousQuantitiesByItemID or nil
InventoryState.revision = InventoryState.revision or 0

-- Builds a normalized item record (TDD §6) from a raw BagAPI slot + cached metadata.
local function BuildRecord(slot)
    local meta = Pockets.Adapters.ItemAPI:GetItemMetadata(slot.itemID, slot.itemLink)
    local isQuestItem = meta and meta.status == "ready" and meta.classID == 12 or false

    local record = {
        key = slot.bagID .. ":" .. slot.slotIndex,
        bagID = slot.bagID,
        slotID = slot.slotIndex,
        itemID = slot.itemID,
        itemLink = slot.itemLink,
        quantity = slot.quantity,
        quality = slot.quality,
        isLocked = slot.isLocked,
        capacityClass = slot.capacityClass,
        texture = slot.texture,
        isQuestItem = isQuestItem,
    }

    if meta and meta.status == "ready" then
        record.name = meta.name
        record.texture = record.texture or meta.texture
        record.maxStack = meta.maxStack
        record.classID = meta.classID
        record.subclassID = meta.subclassID
        record.quality = record.quality or meta.quality
    end

    record.categoryID = Pockets.Services.ItemCategorizer:GetDisplayCategory(record)
    return record
end

-- Aggregates a list of normalized records into { [itemID] = totalQuantity }.
local function AggregateByItemID(records)
    local totals = {}
    for _, record in pairs(records) do
        if record.itemID then
            totals[record.itemID] = (totals[record.itemID] or 0) + record.quantity
        end
    end
    return totals
end

-- Diffs old vs. new aggregate totals and records positive deltas as
-- acquisitions in RecentItems (TDD §8.2). Negative deltas are ignored here;
-- they only matter for capacity/ETA which Refresh() handles separately.
local function RecordAcquisitions(oldTotals, newTotals, itemsByID)
    -- Collected and sorted by itemID before recording: pairs() order is
    -- unspecified, and simultaneous Loot Log entries must keep a
    -- deterministic insertion order.
    local gained = {}
    for itemID, newTotal in pairs(newTotals) do
        local delta = newTotal - (oldTotals and oldTotals[itemID] or 0)
        if delta > 0 then
            gained[#gained + 1] = { itemID = itemID, quantity = delta }
        end
    end
    table.sort(gained, function(a, b) return a.itemID < b.itemID end)

    for _, acquisition in ipairs(gained) do
        local sample = itemsByID[acquisition.itemID]
        local itemLink = sample and sample.itemLink
        Pockets.Services.RecentItems:Record({
            itemID = acquisition.itemID,
            quantity = acquisition.quantity,
            timestamp = GetTime(),
            itemLink = itemLink,
        })
        -- Loot Log's item feed (see Core/LootLog.lua for why this diff is
        -- its single item source).
        Pockets.Services.LootLog:ObserveAcquisition(acquisition.itemID, acquisition.quantity, itemLink)
    end
end

-- Re-scans bags, normalizes, diffs against the previous snapshot, updates
-- capacity/estimator state, and publishes domain events. `reason` is a
-- free-form string used for debug logging only.
function InventoryState:Refresh(reason)
    local rawSlots, incomplete = Pockets.Adapters.BagAPI:ScanAllBags()
    -- Mail/AH (and similar) can make GetContainerNumSlots return 0 for
    -- bags that are still equipped. Applying that snapshot would collapse
    -- Glance from the real 66/76 down to whichever bag still answered
    -- (e.g. 10/20). Never commit an incomplete scan - not even the very
    -- first one at login, before self.generalCapacity exists at all.
    -- Equipped-bag detection (GetInventoryItemLink) can still be settling
    -- right after ADDON_LOADED; committing that partial scan as "the"
    -- total left it permanently wrong since a self-matching scan reads as
    -- complete forever after. Let Events retry until a real scan lands.
    if incomplete then
        return false
    end

    local newItems = {}
    local itemsByID = {}
    for _, slot in ipairs(rawSlots) do
        local record = BuildRecord(slot)
        newItems[record.key] = record
        itemsByID[record.itemID] = record
    end

    local oldTotals = self.previousQuantitiesByItemID
    local newTotals = AggregateByItemID(newItems)

    if oldTotals then
        RecordAcquisitions(oldTotals, newTotals, itemsByID)
    end

    self.items = newItems
    self.previousQuantitiesByItemID = newTotals
    self.revision = self.revision + 1

    local capacity = Pockets.Adapters.BagAPI:GetCapacityCounts()
    self.generalCapacity = self:BuildCapacityResult(capacity.general)
    self.ammoCapacity = self:BuildCapacityResult(capacity.ammo)
    self.specializedCapacities = self:BuildSpecialized(capacity.specialized)

    Pockets.Services.CapacityEstimator:AddSample(GetTime(), capacity.general.used, capacity.general.total)

    EventBus:Publish(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, { reason = reason })
    EventBus:Publish(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, self.generalCapacity)
    return true
end

function InventoryState:BuildCapacityResult(counts)
    local used, total = counts.used or 0, counts.total or 0
    return {
        used = used,
        total = total,
        free = total - used,
        utilization = total > 0 and (used / total) or 0,
    }
end

-- Ordered (stable: Ammo -> Reagents -> profession bags) array of
-- { class, label, used, total, free, utilization, bagIDs, texture } for
-- every equipped specialized bag class.
function InventoryState:BuildSpecialized(specialized)
    local BagAPI = Pockets.Adapters.BagAPI
    local out = {}
    for _, key in ipairs(BagAPI.BAG_CLASS_ORDER) do
        local pool = specialized and specialized[key]
        if pool and pool.total > 0 then
            local result = self:BuildCapacityResult(pool)
            result.class = key
            result.label = BagAPI.BAG_CLASS_LABEL[key]
            result.bagIDs = pool.bagIDs
            result.texture = pool.texture
            table.insert(out, result)
        end
    end
    return out
end

function InventoryState:GetSpecializedCapacities()
    return self.specializedCapacities or {}
end

function InventoryState:GetGeneralCapacity()
    return self.generalCapacity or self:BuildCapacityResult({ used = 0, total = 0 })
end

function InventoryState:GetAmmoCapacity()
    return self.ammoCapacity or self:BuildCapacityResult({ used = 0, total = 0 })
end

function InventoryState:GetItems()
    return self.items
end

function InventoryState:GetItem(itemKey)
    return self.items[itemKey]
end

function InventoryState:GetItemsByCategory(categoryID)
    local out = {}
    for _, record in pairs(self.items) do
        if record.categoryID == categoryID then
            table.insert(out, record)
        end
    end
    return out
end

-- Collapses a list of per-slot records into one entry per itemID (TDD §6):
-- the full inventory grid must render one icon per itemID even when it's
-- spread across many physical stacks. Pure function - no bag scan, so
-- it's directly unit-testable with hand-built record lists. Returns an
-- array (insertion order = first-seen order in `records`) of:
--   { itemID, itemLink, name, texture, quality, categoryID,
--     totalQuantity, stacks = { { bagID, slotID, quantity, isLocked }, ... } }
function InventoryState:AggregateRecords(records)
    local order = {}
    local byItemID = {}

    for _, record in ipairs(records) do
        local agg = byItemID[record.itemID]
        if not agg then
            agg = {
                itemID = record.itemID,
                itemLink = record.itemLink,
                name = record.name,
                texture = record.texture,
                quality = record.quality,
                categoryID = record.categoryID,
                totalQuantity = 0,
                stacks = {},
            }
            byItemID[record.itemID] = agg
            table.insert(order, agg)
        end

        agg.totalQuantity = agg.totalQuantity + (record.quantity or 0)
        if record.bagID and record.slotID then
            table.insert(agg.stacks, {
                bagID = record.bagID,
                slotID = record.slotID,
                quantity = record.quantity,
                isLocked = record.isLocked,
            })
        end
    end

    return order
end

function InventoryState:GetCarriedQuantity(itemID)
    local totals = self.previousQuantitiesByItemID
    return (totals and totals[itemID]) or 0
end

-- Finds the first current bag+slot record for an itemID, or nil if not
-- carried. Used to resolve a Recent Items entry to a real, interactive
-- location (UI_SPEC §9) - Recent itself only remembers itemID/quantity,
-- never a bag/slot, since acquisition history and physical location are
-- different concerns.
function InventoryState:FindLiveRecordByItemID(itemID)
    for _, record in pairs(self.items) do
        if record.itemID == itemID then
            return record
        end
    end
    return nil
end

function InventoryState:GetRevision()
    return self.revision
end

-- True if bagID/slotID still holds an unlocked, current stack of itemID
-- (TDD/Glance UI §7 "reject stale location"). A rendered aggregate binds
-- to one representative stack at render time; this is the check callers
-- must run again at the moment of interaction before trusting it.
function InventoryState:IsValidStack(bagID, slotID, itemID)
    if bagID == nil or slotID == nil then
        return false
    end
    local record = self.items[bagID .. ":" .. slotID]
    return record ~= nil and record.itemID == itemID and not record.isLocked
end

-- Finds the smallest current unlocked physical stack of itemID (Glance UI
-- §7 "use the SMALLEST valid physical stack first" - less disruptive to a
-- player's deliberately-maintained stack sizes). Returns nil if the item
-- isn't currently carried in any unlocked stack.
function InventoryState:ResolveSmallestStack(itemID)
    local best = nil
    for _, record in pairs(self.items) do
        if record.itemID == itemID and not record.isLocked then
            if not best or (record.quantity or 0) < (best.quantity or 0) then
                best = record
            end
        end
    end
    return best
end
