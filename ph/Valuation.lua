--[[
    Valuation.lua - Item classification and expected value computation

    Buckets:
    - vendor_trash: Grays + low-liquidity whites valued at vendor price
    - market_items: Non-commodity tradable items valued by conservative AH floor
    - gathering: Trade goods, fish, and similar gathering outputs (AH floor)
    - enchanting: Enchanting mats (AH floor)
    - container_lockbox: Lockboxes with 0 expected value until opened
]]

local pH_Valuation = {}

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
local SUBCLASS_CONSUMABLE_FISH = 1 -- Fish (raw fish items)

-- Friction multiplier for AH values (to account for fees and risk)
local AH_FRICTION = 0.85

-- Keep lightweight reason metadata for debugging zero-value outcomes
local lastZeroReasons = {}

--------------------------------------------------
-- Item Classification
--------------------------------------------------

-- Classify an item into a bucket
-- @return bucket: "vendor_trash" | "market_items" | "gathering" | "enchanting" | "container_lockbox" | "other"
function pH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
    -- Check for lockbox by name pattern
    if itemName and self:IsLockbox(itemName) then
        return "container_lockbox"
    end

    -- Dedicated enchanting mats bucket (must happen before quality routing)
    if self:IsEnchantingMat(itemID, itemClass, itemSubClass, itemName) then
        return "enchanting"
    end

    -- Gathering first for commodity semantics
    if itemClass == CLASS_TRADE_GOODS or self:IsFish(itemID, itemName, itemClass, itemSubClass) then
        return "gathering"
    end

    -- Rep turn-in items should use market value when configured
    if pH_RepTurninCatalog and pH_RepTurninCatalog.IsRepTurninItem and pH_RepTurninCatalog:IsRepTurninItem(itemID, itemName) then
        local rules = pH_RepTurninCatalog.GetRepRules and pH_RepTurninCatalog:GetRepRules(itemID, itemName) or nil
        if rules then
            for _, rule in ipairs(rules) do
                if rule and rule.ahPreferred then
                    return "market_items"
                end
            end
        else
            local rule = pH_RepTurninCatalog:GetRepRule(itemID, itemName)
            if rule and rule.ahPreferred then
                return "market_items"
            end
        end
    end

    -- Quality-based fallback
    if quality == QUALITY_POOR then
        return "vendor_trash"
    elseif quality == QUALITY_COMMON then
        return "vendor_trash"
    elseif quality == QUALITY_UNCOMMON or quality == QUALITY_RARE or quality == QUALITY_EPIC then
        return "market_items"
    end

    return "other"
end

-- Known fish item IDs (valuable fish that should be treated as gathering materials)
local FISH_ITEM_IDS = {
    [6522] = true,
    [6359] = true,
    [6358] = true,
    [13422] = true,
    [13888] = true,
    [13889] = true,
    [13893] = true,
    [6317] = true,
    [6361] = true,
    [6362] = true,
    [8365] = true,
    [13754] = true,
    [13755] = true,
    [13756] = true,
    [13758] = true,
    [13759] = true,
    [13760] = true,
    [21153] = true,
    [6289] = true,
    [6291] = true,
    [6303] = true,
    [6308] = true,
}

function pH_Valuation:IsFish(itemID, itemName, itemClass, itemSubClass)
    if itemID and FISH_ITEM_IDS[itemID] then
        return true
    end

    if itemClass == CLASS_CONSUMABLE and itemSubClass == SUBCLASS_CONSUMABLE_FISH then
        return true
    end

    if itemName then
        local lowerName = itemName:lower()
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
        if lowerName == "deviate fish" or
            lowerName == "firefin snapper" or
            lowerName == "oily blackmouth" or
            lowerName == "stonescale eel" or
            lowerName == "winter squid" or
            lowerName == "darkclaw lobster"
        then
            return true
        end
    end

    return false
end

function pH_Valuation:IsEnchantingMat(itemID, itemClass, itemSubClass, itemName)
    if pH_EnchantingCatalog and pH_EnchantingCatalog.IsEnchantingMat then
        return pH_EnchantingCatalog:IsEnchantingMat(itemID, itemClass, itemSubClass, itemName)
    end
    return false
end

function pH_Valuation:IsLockbox(itemName)
    if not itemName then
        return false
    end

    local lowerName = itemName:lower()
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

function pH_Valuation:ComputeAHFloorValue(itemID, vendorPrice)
    local ahPrice = self:GetAHPrice(itemID)
    if ahPrice > 0 then
        local adjustedAH = math.floor(ahPrice * AH_FRICTION)
        return math.max(vendorPrice or 0, adjustedAH)
    end
    return vendorPrice or 0
end

function pH_Valuation:SetLastZeroReason(itemID, reason)
    if itemID and reason then
        lastZeroReasons[itemID] = reason
    end
end

function pH_Valuation:GetLastZeroReason(itemID)
    return itemID and lastZeroReasons[itemID] or nil
end

function pH_Valuation:ComputeExpectedValue(itemID, bucket)
    if bucket == "container_lockbox" then
        self:SetLastZeroReason(itemID, "LOCKBOX")
        return 0
    elseif bucket == "other" then
        self:SetLastZeroReason(itemID, "UNTRACKED_BUCKET")
        return 0
    end

    local vendorPrice = self:GetVendorPrice(itemID)
    local expectedEach = 0

    if bucket == "vendor_trash" then
        expectedEach = vendorPrice
    elseif bucket == "gathering" or bucket == "enchanting" or bucket == "market_items" then
        expectedEach = self:ComputeAHFloorValue(itemID, vendorPrice)
        if expectedEach == 0 then
            self:SetLastZeroReason(itemID, "NO_PRICE_SOURCE")
        end
    else
        expectedEach = 0
        self:SetLastZeroReason(itemID, "UNTRACKED_BUCKET")
    end

    return expectedEach
end

function pH_Valuation:GetVendorPrice(itemID)
    local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfo(itemID)
    return vendorPrice or 0
end

function pH_Valuation:GetAHPrice(itemID)
    local price = pH_PriceSources:GetAHPrice(itemID)
    return price or 0
end

-- Get item info with retry logic for cache misses
-- @return name, quality, itemClass, itemSubClass, vendorPrice (or nil if not cached yet)
function pH_Valuation:GetItemInfo(itemID)
    local name, _, quality, _, _, _, _, _, _, _, vendorPrice, itemClassID, itemSubClassID = GetItemInfo(itemID)

    if not name then
        return nil, nil, nil, nil, nil
    end

    return name, quality, itemClassID, itemSubClassID, vendorPrice
end

_G.pH_Valuation = pH_Valuation
