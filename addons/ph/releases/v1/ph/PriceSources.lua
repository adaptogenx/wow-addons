--[[
    PriceSources.lua - Pluggable AH price data sources

    Provides a common interface for querying AH prices from multiple sources:
    - Manual overrides (GoldPH_DB_Account.priceOverrides)
    - TSM (TradeSkillMaster addon)
    - Custom AH addon (user-developed)

    Priority order: Manual overrides > Custom addon > TSM > 0
]]

-- luacheck: globals GoldPH_DB_Account

local GoldPH_PriceSources = {}

--------------------------------------------------
-- Price Source Interface
--------------------------------------------------

-- Each price source must implement:
-- function GetPrice(itemID) -> price in copper (or nil if not available)

--------------------------------------------------
-- Manual Overrides
--------------------------------------------------

local function GetManualOverride(itemID)
    if GoldPH_DB_Account.priceOverrides and GoldPH_DB_Account.priceOverrides[itemID] then
        return GoldPH_DB_Account.priceOverrides[itemID]
    end
    return nil
end

--------------------------------------------------
-- TSM Integration
--------------------------------------------------

local function GetTSMPrice(itemID)
    -- Check if TSM is loaded
    if not TSM_API then
        return nil
    end

    -- Build item string (TSM requires "i:itemID" format)
    local itemString = "i:" .. itemID

    -- Try TSM price sources in order of conservatism
    -- DBMinBuyout: Lowest current buyout (most conservative)
    -- DBMarket: Market average (medium)
    -- DBHistorical: Long-term average (least volatile)

    local price = TSM_API.GetCustomPriceValue("DBMinBuyout", itemString)

    if not price or price == 0 then
        -- Fallback to market value if min buyout unavailable
        price = TSM_API.GetCustomPriceValue("DBMarket", itemString)
    end

    if price and price > 0 then
        return price
    end

    return nil
end

--------------------------------------------------
-- Custom AH Addon Integration
--------------------------------------------------

-- Hook for user's custom AH addon
-- User should implement: _G.CustomAH_GetPrice = function(itemID) ... end
local function GetCustomAHPrice(itemID)
    if _G.CustomAH_GetPrice then
        local price = _G.CustomAH_GetPrice(itemID)
        if price and price > 0 then
            return price
        end
    end
    return nil
end

--------------------------------------------------
-- Public API
--------------------------------------------------

-- Get AH price for an item from available sources
-- @param itemID: Item ID
-- @return price in copper (or nil if no source has data)
function GoldPH_PriceSources:GetAHPrice(itemID)
    -- Priority 1: Manual overrides (highest priority)
    local price = GetManualOverride(itemID)
    if price then
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH Price] Manual override: itemID=%d, price=%d", itemID, price))
        end
        return price
    end

    -- Priority 2: Custom AH addon
    price = GetCustomAHPrice(itemID)
    if price then
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH Price] Custom AH: itemID=%d, price=%d", itemID, price))
        end
        return price
    end

    -- Priority 3: TSM
    price = GetTSMPrice(itemID)
    if price then
        if GoldPH_DB_Account.debug.verbose then
            print(string.format("[GoldPH Price] TSM: itemID=%d, price=%d", itemID, price))
        end
        return price
    end

    -- No price data available
    return nil
end

-- Check which price sources are available
function GoldPH_PriceSources:GetAvailableSources()
    local sources = {}

    if GoldPH_DB_Account.priceOverrides and next(GoldPH_DB_Account.priceOverrides) ~= nil then
        table.insert(sources, "Manual Overrides")
    end

    if _G.CustomAH_GetPrice then
        table.insert(sources, "Custom AH")
    end

    if TSM_API then
        table.insert(sources, "TSM")
    end

    return sources
end

-- Export module
_G.GoldPH_PriceSources = GoldPH_PriceSources
