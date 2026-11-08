--[[
    Core/DiscardFirst.lua - "Discard first": when the general bags are nearly
    full, the carried stacks that are worth the least to a vendor.

    Pure selection (Select) over normalized InventoryState records plus a thin
    service wrapper. Never offers quest items, ammo or the Hearthstone, never
    guesses at items whose vendor price has not resolved yet, and treats
    zero-price items that are not poor quality as "can't judge" (usually
    unique or important items), not as free to throw away.
]]

local _, Pockets = ...

Pockets.Services.DiscardFirst = Pockets.Services.DiscardFirst or {}
local DiscardFirst = Pockets.Services.DiscardFirst
local Constants = Pockets.Constants

local HEARTHSTONE = 6948

-- Profession gear and materials are skipped by default: trade goods and
-- recipes by item class, fishing poles / misc "weapons" (skinning knife,
-- mining pick...) by subclass, plus known tool IDs (rods, hammer, spanner).
local CLASS_TRADE_GOODS, CLASS_RECIPE, CLASS_WEAPON = 7, 9, 2
local SUBCLASS_FISHING_POLE, SUBCLASS_WEAPON_MISC = 20, 14
local PROFESSION_TOOLS = {
    [7005] = true, [2901] = true, [5956] = true, [6219] = true,
    [6218] = true, [6339] = true, [11130] = true, [11145] = true, [16207] = true,
}

function DiscardFirst.IsProfessionItem(record)
    if PROFESSION_TOOLS[record.itemID] then
        return true
    end
    local class = record.classID
    if class == CLASS_TRADE_GOODS or class == CLASS_RECIPE then
        return true
    end
    return class == CLASS_WEAPON
        and (record.subclassID == SUBCLASS_FISHING_POLE or record.subclassID == SUBCLASS_WEAPON_MISC)
end

-- Total vendor value of one aggregated item, or nil when it must not be offered.
local function Eligible(record, price)
    if not record.itemID or record.itemID == HEARTHSTONE then
        return false
    end
    if record.capacityClass and record.capacityClass ~= Constants.CAPACITY_CLASS.GENERAL then
        return false
    end
    local category = record.categoryID
    if category == Constants.CATEGORY.QUEST or category == Constants.CATEGORY.AMMO then
        return false
    end
    if DiscardFirst.IsProfessionItem(record)
        and not (Pockets.SavedSettings and Pockets.SavedSettings.discardIncludeProfession) then
        return false
    end
    if record.isQuestItem or type(price) ~= "number" then
        return false
    end
    if price <= 0 and record.quality ~= 0 then
        return false
    end
    return true
end

-- records: array of per-slot records (with sellPrice = per-unit copper).
-- Returns up to `limit` aggregated entries { itemID, record, value }, lowest
-- total stack value first (ties: poor quality first, then name, then itemID).
function DiscardFirst.Select(records, limit)
    local byItem, order = {}, {}
    for _, record in ipairs(records) do
        local entry = byItem[record.itemID]
        if not entry then
            if Eligible(record, record.sellPrice) then
                entry = { itemID = record.itemID, record = record, quantity = 0, price = record.sellPrice }
                byItem[record.itemID] = entry
                order[#order + 1] = entry
            else
                byItem[record.itemID] = false
            end
        end
        if entry then
            entry.quantity = entry.quantity + (record.quantity or 0)
        end
    end
    for _, entry in ipairs(order) do
        entry.value = entry.price * entry.quantity
    end
    table.sort(order, function(a, b)
        if a.value ~= b.value then
            return a.value < b.value
        end
        local aq, bq = a.record.quality or 1, b.record.quality or 1
        if aq ~= bq then
            return aq < bq
        end
        local an, bn = (a.record.name or ""):lower(), (b.record.name or ""):lower()
        if an ~= bn then
            return an < bn
        end
        return a.itemID < b.itemID
    end)
    local out = {}
    for i = 1, math.min(#order, limit or Constants.DISCARD_FIRST_LIMIT) do
        out[i] = order[i]
    end
    return out
end

function DiscardFirst.IsActive(capacity)
    return capacity ~= nil and (capacity.total or 0) > 0
        and (capacity.utilization or 0) >= Constants.DISCARD_FIRST_AT
end

-- Button-shaped records (same shape as Recent / aggregated items), or {} when
-- the bags are not nearly full.
function DiscardFirst:GetItems()
    local InventoryState = Pockets.Services.InventoryState
    if not DiscardFirst.IsActive(InventoryState:GetGeneralCapacity()) then
        return {}
    end
    local records = {}
    for _, record in pairs(InventoryState:GetItems()) do
        records[#records + 1] = record
    end
    local aggByItem = {}
    for _, agg in ipairs(InventoryState:AggregateRecords(records)) do
        aggByItem[agg.itemID] = agg
    end
    local out = {}
    for _, entry in ipairs(DiscardFirst.Select(records)) do
        local agg = aggByItem[entry.itemID]
        if agg then
            local button = Pockets.UI.ItemButtonPool.ToButtonRecord(agg)
            button.vendorValue = entry.value
            out[#out + 1] = button
        end
    end
    return out
end
