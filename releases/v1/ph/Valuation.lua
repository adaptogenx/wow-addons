--[[
    Valuation.lua - Item classification and expected value computation

    Implements conservative valuation model with buckets:
    - vendor_trash: Grays + most whites valued at vendor price
    - rare_multi: Greens/blues/purples using multi-path EV formula
    - gathering: Trade goods (herbs, ore, cloth, leather, etc.)
    - container_lockbox: Lockboxes with 0 expected value until opened
]]

local GoldPH_Valuation = {}

-- Item quality constants
local QUALITY_POOR = 0      -- Gray
local QUALITY_COMMON = 1    -- White
local QUALITY_UNCOMMON = 2  -- Green
local QUALITY_RARE = 3      -- Blue
local QUALITY_EPIC = 4      -- Purple

-- Item class constants (WoW Classic)
local CLASS_CONSUMABLE = 0
local CLASS_TRADE_GOODS = 7

-- Item subclass constants
local SUBCLASS_CONSUMABLE_FOOD_DRINK = 0  -- Food & Drink (includes fish when cooked)
local SUBCLASS_CONSUMABLE_FISH = 1        -- Fish (raw fish items)

-- Friction multiplier for AH values (to account for fees and risk)
local AH_FRICTION = 0.85

--------------------------------------------------
-- Item Classification
--------------------------------------------------

-- Classify an item into a bucket
-- @param itemID: Item ID
-- @param itemName: Item name (optional, used for lockbox detection)
-- @param quality: Item quality (0-4)
-- @param itemClass: Item class (from GetItemInfo)
-- @param itemSubClass: Item subclass (optional, from GetItemInfo)
-- @return bucket: "vendor_trash" | "rare_multi" | "gathering" | "container_lockbox" | "other"
function GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
    -- Check for lockbox by name pattern
    if itemName and self:IsLockbox(itemName) then
        return "container_lockbox"
    end

    -- Quality-based classification
    if quality == QUALITY_POOR then
        -- Gray items -> vendor_trash
        return "vendor_trash"
    elseif quality == QUALITY_UNCOMMON or quality == QUALITY_RARE or quality == QUALITY_EPIC then
        -- Green/Blue/Purple -> rare_multi
        return "rare_multi"
    elseif quality == QUALITY_COMMON then
        -- White items: check if trade goods, fish, or other valuable materials
        if itemClass == CLASS_TRADE_GOODS then
            return "gathering"
        elseif self:IsFish(itemID, itemName, itemClass, itemSubClass) then
            -- Fish are valuable gathering materials even though they're consumables
            return "gathering"
        else
            return "vendor_trash"
        end
    end

    -- Default: other (not tracked)
    return "other"
end

-- Known fish item IDs (valuable fish that should be treated as gathering materials)
local FISH_ITEM_IDS = {
    -- Classic fish
    [6522] = true,   -- Deviate Fish
    [6359] = true,   -- Firefin Snapper
    [6358] = true,   -- Oily Blackmouth
    [13422] = true,  -- Stonescale Eel
    [13888] = true,  -- Darkclaw Lobster
    [13889] = true,  -- Raw Whitescale Salmon
    [13893] = true,  -- Large Raw Mightfish
    [6317] = true,   -- Raw Loch Frenzy
    [6361] = true,   -- Raw Rainbow Fin Albacore
    [6362] = true,   -- Raw Rockscale Cod
    [8365] = true,   -- Raw Mithril Head Trout
    [13754] = true,  -- Raw Glossy Mightfish
    [13755] = true,  -- Winter Squid
    [13756] = true,  -- Raw Summer Bass
    [13758] = true,  -- Raw Redgill
    [13759] = true,  -- Raw Nightfin Snapper
    [13760] = true,  -- Raw Sunscale Salmon
    [21153] = true,  -- Raw Greater Sagefish
    [6289] = true,   -- Raw Longjaw Mud Snapper
    [6291] = true,   -- Raw Brilliant Smallfish
    [6303] = true,   -- Raw Slitherskin Mackerel
    [6308] = true,   -- Raw Bristle Whisker Catfish
}

-- Check if an item is a fish (valuable for AH, not just vendor)
function GoldPH_Valuation:IsFish(itemID, itemName, itemClass, itemSubClass)
    -- Check explicit fish whitelist first (most reliable)
    if itemID and FISH_ITEM_IDS[itemID] then
        return true
    end

    -- Check by item subclass (fish are Consumable class with Fish subclass in some versions)
    if itemClass == CLASS_CONSUMABLE and itemSubClass == SUBCLASS_CONSUMABLE_FISH then
        return true
    end

    -- Check by name pattern as fallback
    if itemName then
        local lowerName = itemName:lower()
        -- Common fish name patterns (raw fish typically have "Raw" prefix or fish-like names)
        if lowerName:find("^raw ") and (
            lowerName:find("fish") or
            lowerName:find("snapper") or
            lowerName:find("eel") or
            lowerName:find("salmon") or
            lowerName:find("trout") or
            lowerName:find("squid") or
            lowerName:find("lobster") or
            lowerName:find("bass") or
            lowerName:find("mightfish") or
            lowerName:find("sagefish") or
            lowerName:find("catfish") or
            lowerName:find("mackerel") or
            lowerName:find("albacore") or
            lowerName:find("cod") or
            lowerName:find("redgill") or
            lowerName:find("nightfin") or
            lowerName:find("sunscale")
        ) then
            return true
        end
        -- Special named fish without "Raw" prefix
        if lowerName == "deviate fish" or
           lowerName == "firefin snapper" or
           lowerName == "oily blackmouth" or
           lowerName == "stonescale eel" or
           lowerName == "winter squid" or
           lowerName == "darkclaw lobster" then
            return true
        end
    end

    return false
end

-- Check if an item is a lockbox based on name
function GoldPH_Valuation:IsLockbox(itemName)
    if not itemName then
        return false
    end

    local lowerName = itemName:lower()

    -- Common lockbox name patterns
    local lockboxPatterns = {
        "junkbox",
        "strongbox",
        "lockbox",
        "battered junkbox",
        "worn junkbox",
        "sturdy junkbox",
        "heavy junkbox",
    }

    for _, pattern in ipairs(lockboxPatterns) do
        if lowerName:find(pattern) then
            return true
        end
    end

    return false
end

--------------------------------------------------
-- Expected Value Computation
--------------------------------------------------

-- Compute expected value for an item
-- @param itemID: Item ID
-- @param bucket: Item bucket (from ClassifyItem)
-- @return expectedEach: Expected value per item in copper (conservative estimate)
function GoldPH_Valuation:ComputeExpectedValue(itemID, bucket)
    if bucket == "container_lockbox" then
        -- Lockboxes have 0 expected value until opened
        return 0
    elseif bucket == "other" then
        -- Other items: no expected value (not tracked)
        return 0
    end

    -- Get vendor price
    local vendorPrice = self:GetVendorPrice(itemID)

    if bucket == "vendor_trash" then
        -- Trash items: use vendor price directly
        return vendorPrice
    elseif bucket == "gathering" then
        -- Gathering: use AH price if available, else vendor price
        -- Always ensure expected value is at least vendor price (guaranteed liquidation path)
        local ahPrice = self:GetAHPrice(itemID)
        if ahPrice > 0 then
            local adjustedAH = math.floor(ahPrice * AH_FRICTION)
            return math.max(vendorPrice, adjustedAH)
        else
            return vendorPrice
        end
    elseif bucket == "rare_multi" then
        -- Rare items: use multi-path expected value formula
        return self:ComputeRareMultiEV(itemID, vendorPrice)
    end

    return 0
end

-- Get vendor sell price for an item
function GoldPH_Valuation:GetVendorPrice(itemID)
    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemID)
    return vendorPrice or 0
end

-- Get conservative AH price for an item
-- Delegates to PriceSources module for pluggable price data
function GoldPH_Valuation:GetAHPrice(itemID)
    local price = GoldPH_PriceSources:GetAHPrice(itemID)
    return price or 0
end

-- Get disenchant expected value (not implemented in MVP)
function GoldPH_Valuation:GetDEValue(itemID)
    -- TODO Phase 3+: Implement DE value estimation
    return 0
end

-- Compute rare/multi-path expected value
-- Formula: EV = 0.50 * V_vendor + 0.35 * V_DE + 0.15 * V_AH
--          Final = min(EV, 1.25 * max(V_vendor, V_DE))
--          Final = max(Final, V_vendor) -- Vendor floor (guaranteed liquidation path)
function GoldPH_Valuation:ComputeRareMultiEV(itemID, vendorPrice)
    local deValue = self:GetDEValue(itemID)
    local ahPrice = self:GetAHPrice(itemID)

    -- Apply weights
    local ev = 0.50 * vendorPrice + 0.35 * deValue + 0.15 * ahPrice

    -- Apply cap
    local maxValue = math.max(vendorPrice, deValue)
    local cap = 1.25 * maxValue
    local cappedEV = math.min(ev, cap)

    -- Ensure expected value is never below vendor price (guaranteed liquidation path)
    return math.max(vendorPrice, math.floor(cappedEV))
end

--------------------------------------------------
-- Item Info Resolution (with caching)
--------------------------------------------------

-- Get item info with retry logic for cache misses
-- @param itemID: Item ID
-- @return name, quality, itemClass, itemSubClass, vendorPrice (or nil if not cached yet)
function GoldPH_Valuation:GetItemInfo(itemID)
    local name, _, quality, _, _, _, _, _, _, _, vendorPrice, itemClassID, itemSubClassID = GetItemInfo(itemID)

    if not name then
        -- Item not in cache yet, will need to retry
        return nil, nil, nil, nil, nil
    end

    return name, quality, itemClassID, itemSubClassID, vendorPrice
end

-- Export module
_G.GoldPH_Valuation = GoldPH_Valuation
