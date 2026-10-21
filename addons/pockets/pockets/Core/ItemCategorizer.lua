--[[
    Core/ItemCategorizer.lua - Automatic item categorization (TDD §5.2, §10)

    Classification precedence (TDD §10):
      1. Quest override
      2. Ammo
      3. Junk / poor quality
      4. Consumable
      5. Equipment
      6. Trade Goods
      7. Other

    "Recent" is not assigned here - it is a first-class view composed from
    RecentItems, not a mutually-exclusive category (PRD §3.3, §3.4).
]]

local _, Pockets = ...

Pockets.Services.ItemCategorizer = Pockets.Services.ItemCategorizer or {}
local ItemCategorizer = Pockets.Services.ItemCategorizer

local CATEGORY = Pockets.Constants.CATEGORY

-- Classic item class IDs relevant to categorization.
local CLASS_CONSUMABLE = 0
local CLASS_TRADE_GOODS = 7
local CLASS_QUEST = 12
local CLASS_AMMO = 6
local CLASS_ARMOR = 4
local CLASS_WEAPON = 2

local QUALITY_POOR = 0

-- item: a normalized item record (TDD §6), at minimum:
--   { itemID, classID, subclassID, quality, isQuestItem, capacityClass }
-- Returns a stable category ID (Constants.CATEGORY.*).
function ItemCategorizer:Categorize(item)
    if not item then
        return CATEGORY.OTHER
    end

    -- 1. Quest override
    if item.isQuestItem or item.classID == CLASS_QUEST then
        return CATEGORY.QUEST
    end

    -- 2. Ammo - independent of physical bag location (PRD §3.9, TDD §7)
    if item.classID == CLASS_AMMO or item.capacityClass == Pockets.Constants.CAPACITY_CLASS.AMMO then
        return CATEGORY.AMMO
    end

    -- 3. Junk / poor quality
    if item.quality == QUALITY_POOR then
        return CATEGORY.JUNK
    end

    -- 4. Consumable
    if item.classID == CLASS_CONSUMABLE then
        return CATEGORY.CONSUMABLE
    end

    -- 5. Equipment
    if item.classID == CLASS_ARMOR or item.classID == CLASS_WEAPON then
        return CATEGORY.EQUIPMENT
    end

    -- 6. Trade Goods
    if item.classID == CLASS_TRADE_GOODS then
        return CATEGORY.TRADE_GOODS
    end

    -- 7. Other
    return CATEGORY.OTHER
end

-- The simplified display category shown in the UI. In v1 this is identical
-- to Categorize(), but kept as a separate seam per TDD §5.2 so the domain
-- categorizer can later record a richer internalCategory while still
-- mapping to one simplified display bucket.
function ItemCategorizer:GetDisplayCategory(item)
    return self:Categorize(item) or CATEGORY.OTHER
end

