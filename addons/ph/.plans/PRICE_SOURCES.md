# Price Sources Integration

GoldPH supports multiple AH price data sources through a pluggable interface.

## Priority Order

1. **Manual Overrides** (highest priority)
2. **Custom AH Addon** (your custom addon)
3. **TSM (TradeSkillMaster)** (if installed)
4. **Vendor Price** (fallback)

## Using TSM

If TSM is installed, GoldPH will automatically use it for AH prices.

**TSM Price Sources Used:**
- `DBMinBuyout`: Lowest current buyout (most conservative)
- `DBMarket`: Market average (fallback if min buyout unavailable)

**Friction:** AH prices are multiplied by 0.85 to account for:
- AH cut (5%)
- Risk that items don't sell
- Time cost of listing

## Custom AH Addon Integration

To integrate your custom AH addon, implement this global function:

```lua
-- In your custom addon code:
function CustomAH_GetPrice(itemID)
    -- Your logic to get AH price for itemID
    -- Return price in copper, or nil if no data

    -- Example:
    local price = MyCustomAH_Database[itemID]
    if price and price > 0 then
        return price
    end
    return nil
end
```

**Requirements:**
- Function name must be: `CustomAH_GetPrice`
- Must be in global scope: `_G.CustomAH_GetPrice`
- Parameter: `itemID` (number)
- Return: Price in copper (number) or `nil` if no data
- Load your addon before GoldPH processes items

**Best Practices:**
- Return conservative prices (prefer low estimates)
- Return `nil` if confidence is low
- Use recent sale data, not listings
- Consider velocity (how fast items sell)

## Manual Overrides

Set specific prices for items:

```lua
/script GoldPH_DB.priceOverrides[4306] = 1500  -- Silk Cloth = 15 silver
/script GoldPH_DB.priceOverrides[2589] = 500   -- Linen Cloth = 5 silver
```

**Use Cases:**
- Override TSM/Custom addon for specific items
- Set prices for items that sell consistently
- Account for server-specific pricing

## Debugging

Check which price sources are available:
```
/goldph debug prices
```

Enable verbose logging to see which source is used for each item:
```
/goldph debug verbose on
```

When items are looted, you'll see:
```
[GoldPH Price] TSM: itemID=4306, price=1200
[GoldPH] Looted: Silk Cloth x5 (gathering, 12s each)
```

## Implementation Details

### Price Source Module

**File:** `GoldPH/PriceSources.lua`

**API:**
```lua
-- Get AH price for an item (checks all sources in priority order)
GoldPH_PriceSources:GetAHPrice(itemID) -> copper or nil

-- Check which sources are available
GoldPH_PriceSources:GetAvailableSources() -> array of strings
```

### Valuation Integration

**File:** `GoldPH/Valuation.lua`

**How prices are used:**

1. **Gathering items** (cloth, ore, herbs):
   - AH price with 0.85 friction
   - Falls back to vendor price if no AH data

2. **rare_multi items** (greens/blues/purples):
   - Formula: `EV = 0.50 * V_vendor + 0.35 * V_DE + 0.15 * V_AH`
   - Capped at: `1.25 * max(V_vendor, V_DE)`
   - V_AH comes from price sources
   - V_DE = 0 in current implementation

3. **vendor_trash items** (grays, white consumables):
   - Always uses vendor price (no AH lookup)

## Example: Custom AH Addon

Here's a complete example of integrating your custom addon:

```lua
-- CustomAH.lua - Your custom AH addon

local CustomAH_Prices = {}

-- Your addon's event handler loads price data
local function OnAuctionScan()
    -- Scan AH and populate CustomAH_Prices
    -- ... your logic here ...
end

-- GoldPH integration function (global scope)
function CustomAH_GetPrice(itemID)
    local data = CustomAH_Prices[itemID]

    if not data then
        return nil  -- No data for this item
    end

    -- Return conservative estimate (e.g., lowest recent sale)
    return data.minPrice
end

-- Register your addon
RegisterAddon("CustomAH", CustomAH_Init)
```

Then in-game:
```
/goldph debug prices
-- Output:
-- Available sources:
--   1. Custom AH
--   2. TSM
```

## No Price Data Available

If no price sources have data for an item:
- **Gathering items**: Falls back to vendor price
- **rare_multi items**: Uses vendor price in formula (V_AH = 0)
- **vendor_trash items**: Always vendor price anyway

This ensures GoldPH never overestimates value - vendor price is the guaranteed floor.

## Future Enhancements

Potential additions:
- Disenchant value estimation (V_DE in rare_multi formula)
- Server-specific price caching
- Price staleness checks (ignore old data)
- Velocity-based adjustments (penalize slow-moving items)
- RECrystallize integration (if popular on Classic Anniversary)
