--[[
    Core/Supplies.lua - Consumable "supply" counters shown beside the ammo pill:
    soul shards (warlock), water (mana classes) and food (optional).

    Pure domain logic (no frames): takes normalized InventoryState records and
    the player's class token, returns an ordered list of supply entries.
    Water and food share Classic's "Food & Drink" subclass, so water is
    identified by a curated itemID list (listed worst -> best; list position
    is the rank used for "best item") and food is every other Food & Drink
    item. Unknown new water therefore counts as food - acceptable for
    Classic's closed item set.
]]

local _, Pockets = ...

Pockets.Services.Supplies = Pockets.Services.Supplies or {}
local Supplies = Pockets.Services.Supplies

local CLASS_CONSUMABLE = 0
local SUBCLASS_FOOD_DRINK = 5

Supplies.SOUL_SHARD_ID = 6265

-- Classes that use mana (and so want water).
Supplies.MANA_CLASSES = {
    MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true,
    PALADIN = true, SHAMAN = true, HUNTER = true,
}

-- Water itemIDs, roughly worst -> best. Position = rank for "best item".
Supplies.WATER_ITEM_IDS = {
    159, -- Refreshing Spring Water
    5350, -- Conjured Water
    1179, -- Ice Cold Milk
    1205, -- Melon Juice
    2288, -- Conjured Fresh Water
    1645, -- Moonberry Juice
    3772, -- Conjured Spring Water
    1708, -- Sweet Nectar
    2136, -- Conjured Purified Water
    4791, -- Enchanted Water
    8077, -- Conjured Mineral Water
    8766, -- Morning Glory Dew
    8078, -- Conjured Sparkling Water
    8079, -- Conjured Crystal Water
    22018, -- Conjured Glacier Water
    28399, -- Filtered Draenic Water
    27860, -- Purified Draenic Water
}

local WATER_RANK = {}
for rank, itemID in ipairs(Supplies.WATER_ITEM_IDS) do
    WATER_RANK[itemID] = rank
end

-- Icon source when nothing is carried.
local FALLBACK_ITEM = { shards = 6265, water = 159, food = 4540 }
local LABEL = { shards = "Soul Shards", water = "Water", food = "Food" }

-- Which supply kinds a class sees, in display order.
function Supplies.EligibleKinds(classToken, settings)
    local out = {}
    if classToken == "WARLOCK" then
        out[#out + 1] = "shards"
    end
    if Supplies.MANA_CLASSES[classToken] then
        out[#out + 1] = "water"
    end
    if settings and settings.showFood then
        out[#out + 1] = "food"
    end
    return out
end

-- Which supply kind a record belongs to, or nil.
function Supplies.KindOf(record)
    if record.itemID == Supplies.SOUL_SHARD_ID then
        return "shards"
    end
    if record.classID == CLASS_CONSUMABLE and record.subclassID == SUBCLASS_FOOD_DRINK then
        return WATER_RANK[record.itemID] and "water" or "food"
    end
    return nil
end

-- Is record a better "best item" than current? Water by list rank; food by
-- required level, then itemID.
local function IsBetter(kind, record, best)
    if not best then
        return true
    end
    if kind == "water" then
        return (WATER_RANK[record.itemID] or 0) > (WATER_RANK[best.itemID] or 0)
    end
    local a, b = record.minLevel or 0, best.minLevel or 0
    if a ~= b then
        return a > b
    end
    return (record.itemID or 0) > (best.itemID or 0)
end

-- records: iterable table of normalized item records (InventoryState items).
-- Returns an ordered array of { kind, label, count, bestItemID, bestName,
-- bestLink, texture, fallbackItemID } for each kind the class is eligible for.
function Supplies.Compute(records, classToken, settings)
    local kinds = Supplies.EligibleKinds(classToken, settings)
    if #kinds == 0 then
        return {}
    end

    local state = {}
    for _, kind in ipairs(kinds) do
        state[kind] = { kind = kind, label = LABEL[kind], count = 0, fallbackItemID = FALLBACK_ITEM[kind] }
    end

    for _, record in pairs(records or {}) do
        local kind = Supplies.KindOf(record)
        local entry = kind and state[kind]
        if entry then
            entry.count = entry.count + (record.quantity or 0)
            if IsBetter(kind, record, entry.best) then
                entry.best = record
            end
        end
    end

    local out = {}
    for _, kind in ipairs(kinds) do
        local entry = state[kind]
        local best = entry.best
        entry.best = nil
        if best then
            entry.bestItemID = best.itemID
            entry.bestName = best.name
            entry.bestLink = best.itemLink
            entry.texture = best.texture
        end
        out[#out + 1] = entry
    end
    return out
end
