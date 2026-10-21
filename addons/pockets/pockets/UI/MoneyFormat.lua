--[[
    UI/MoneyFormat.lua - Copper -> display-string formatting for Glance's
    Gold row.

    Reproduces pH's Ledger module's FormatMoney output contract
    (gold/silver/copper breakdown, thousands-separated gold, copper
    omitted once gold >= 1) as standalone Pockets code - Pockets must not
    depend on the pH addon or its Ledger module being loaded (CLAUDE.md
    "Pockets is a standalone addon"). Pure/stateless so it's directly
    unit-testable without a live frame, and reusable anywhere else
    Pockets needs a money string later.
]]

local _, Pockets = ...

Pockets.UI.MoneyFormat = Pockets.UI.MoneyFormat or {}
local MoneyFormat = Pockets.UI.MoneyFormat

-- Standard Lua comma-grouping idiom: repeatedly inserts a comma before
-- the last 3 digits of whatever's left until no more 4+-digit runs remain.
local function WithThousandsSeparator(number)
    local formatted = tostring(number)
    while true do
        local replaced, count = formatted:gsub("^(%d+)(%d%d%d)", "%1,%2")
        formatted = replaced
        if count == 0 then
            break
        end
    end
    return formatted
end

-- copper -> "1,234g 56s" | "1,234g" | "56s 78c" | "78c" (pH's Ledger
-- module's contract). Copper is always dropped once gold >= 1 - never
-- fake precision the player doesn't need at that scale.
--
-- Negative amounts (Loot Log expenses) render with a leading "-" on the
-- same breakdown, matching pH's Ledger (never for zero).
-- The coin icon for an amount's largest denomination: gold coin once there
-- is at least a full gold, silver below that, copper below a full silver.
function MoneyFormat:CoinIcon(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper >= 10000 then
        return Pockets.Constants.GOLD_ICON
    elseif copper >= 100 then
        return Pockets.Constants.SILVER_ICON
    end
    return Pockets.Constants.COPPER_ICON
end

function MoneyFormat:Format(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then
        return "-" .. self:Format(-copper)
    end

    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperRemainder = copper % 100

    if gold > 0 then
        if silver > 0 then
            return string.format("%sg %ds", WithThousandsSeparator(gold), silver)
        end
        return string.format("%sg", WithThousandsSeparator(gold))
    elseif silver > 0 then
        if copperRemainder > 0 then
            return string.format("%ds %dc", silver, copperRemainder)
        end
        return string.format("%ds", silver)
    end
    return string.format("%dc", copperRemainder)
end
