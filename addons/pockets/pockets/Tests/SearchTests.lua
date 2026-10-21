--[[
    Tests/SearchTests.lua - Case-insensitive name matching (TDD §15, §24.1)
]]

local _, Pockets = ...

local Search = Pockets.UI.Search

Pockets.Tests.TestRunner:Register("Search: nil/empty query matches everything", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, nil) and Search:Matches(record, "")
    return ok, ok and "OK" or "expected nil/empty query to match"
end)

Pockets.Tests.TestRunner:Register("Search: case-insensitive substring match", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, "linen") and Search:Matches(record, "CLOTH") and Search:Matches(record, "en cl")
    return ok, ok and "OK" or "expected case-insensitive substring matches to succeed"
end)

Pockets.Tests.TestRunner:Register("Search: non-matching substring fails", function()
    local record = { name = "Linen Cloth" }
    local ok = Search:Matches(record, "silk") == false
    return ok, ok and "OK" or "expected non-matching substring to fail"
end)

Pockets.Tests.TestRunner:Register("Search: record with no name never matches a non-empty query", function()
    local record = { name = nil }
    local ok = Search:Matches(record, "anything") == false
    return ok, ok and "OK" or "expected nameless record to fail a non-empty query"
end)
