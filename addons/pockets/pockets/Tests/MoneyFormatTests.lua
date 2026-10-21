--[[
    Tests/MoneyFormatTests.lua - UI/MoneyFormat.lua's pH Ledger-compatible
    output contract. Pure/stateless - no live frame needed.
]]

local _, Pockets = ...

local MoneyFormat = Pockets.UI.MoneyFormat

local CASES = {
    { copper = 12345678, expected = "1,234g 56s" },
    { copper = 12340000, expected = "1,234g" },
    { copper = 5678, expected = "56s 78c" },
    { copper = 78, expected = "78c" },
}

for _, case in ipairs(CASES) do
    Pockets.Tests.TestRunner:Register(
        string.format("MoneyFormat: %d copper -> %q", case.copper, case.expected), function()
            local actual = MoneyFormat:Format(case.copper)
            local ok = actual == case.expected
            return ok, ok and "OK" or string.format("expected %q, got %q", case.expected, tostring(actual))
        end)
end

Pockets.Tests.TestRunner:Register("MoneyFormat: copper is omitted once gold >= 1", function()
    local ok = MoneyFormat:Format(10001) == "1g" -- 1g 0s 1c
    return ok, ok and "OK" or string.format("expected copper dropped at >=1g, got %q", MoneyFormat:Format(10001))
end)

Pockets.Tests.TestRunner:Register("MoneyFormat: gold uses thousands separators", function()
    local ok = MoneyFormat:Format(12345670000) == "1,234,567g"
    return ok, ok and "OK" or string.format("got %q", MoneyFormat:Format(12345670000))
end)

Pockets.Tests.TestRunner:Register("MoneyFormat: zero copper still renders (never blank)", function()
    local actual = MoneyFormat:Format(0)
    local ok = actual == "0c"
    return ok, ok and "OK" or string.format("expected \"0c\", got %q", tostring(actual))
end)

Pockets.Tests.TestRunner:Register("MoneyFormat: coin icon follows the largest denomination", function()
    local C = Pockets.Constants
    local F = Pockets.UI.MoneyFormat
    local ok = F:CoinIcon(0) == C.COPPER_ICON and F:CoinIcon(99) == C.COPPER_ICON
        and F:CoinIcon(100) == C.SILVER_ICON and F:CoinIcon(9999) == C.SILVER_ICON
        and F:CoinIcon(10000) == C.GOLD_ICON and F:CoinIcon(123456789) == C.GOLD_ICON
        and F:CoinIcon(nil) == C.COPPER_ICON
    return ok, ok and "OK" or "bad coin icon"
end)
