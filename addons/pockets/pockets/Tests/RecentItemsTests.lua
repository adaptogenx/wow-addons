--[[
    Tests/RecentItemsTests.lua - Recent-item queue behavior (TDD §24.1)
]]

local _, Pockets = ...

local RecentItems = Pockets.Services.RecentItems

Pockets.Tests.TestRunner:Register("RecentItems: newest first", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 1, quantity = 1, timestamp = 1 })
    RecentItems:Record({ itemID = 2, quantity = 1, timestamp = 2 })

    local recent = RecentItems:GetRecent(2)
    local ok = recent[1].itemID == 2 and recent[2].itemID == 1
    return ok, ok and "OK" or "expected newest-first ordering"
end)

Pockets.Tests.TestRunner:Register("RecentItems: preserves acquired quantity", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 5, quantity = 7, timestamp = 1 })

    local recent = RecentItems:GetRecent(1)
    local ok = recent[1].quantity == 7
    return ok, ok and "OK" or string.format("expected quantity 7, got %s", tostring(recent[1].quantity))
end)

Pockets.Tests.TestRunner:Register("RecentItems: bounded history queue", function()
    RecentItems:Clear()
    local max = Pockets.Constants.RECENT_ITEMS_MAX
    for i = 1, max + 10 do
        RecentItems:Record({ itemID = i, quantity = 1, timestamp = i })
    end

    local count = #RecentItems:GetRecent(max + 10)
    local ok = count == max
    return ok, ok and "OK" or string.format("expected bounded to %d, got %d", max, count)
end)

Pockets.Tests.TestRunner:Register("RecentItems: re-acquiring an already-recent item bumps it to newest, not a second row", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 1, quantity = 1, timestamp = 1 })
    RecentItems:Record({ itemID = 2, quantity = 1, timestamp = 2 })
    RecentItems:Record({ itemID = 1, quantity = 1, timestamp = 3 })

    local recent = RecentItems:GetRecent(10)
    local ok = #recent == 2 and recent[1].itemID == 1 and recent[2].itemID == 2
    return ok, ok and "OK" or string.format(
        "expected 2 unique entries with itemID 1 bumped to newest, got %d entries", #recent)
end)

Pockets.Tests.TestRunner:Register("RecentItems: repeated pickups of one item do not evict other unique recents", function()
    RecentItems:Clear()
    local max = Pockets.Constants.RECENT_ITEMS_MAX
    RecentItems:Record({ itemID = 999, quantity = 1, timestamp = 0 }) -- one unique item, recorded first
    for i = 1, max + 20 do
        RecentItems:Record({ itemID = 1, quantity = 1, timestamp = i }) -- same item, fished repeatedly
    end

    local recent = RecentItems:GetRecent(max + 20)
    local found999 = false
    for _, entry in ipairs(recent) do
        if entry.itemID == 999 then
            found999 = true
        end
    end
    local ok = #recent == 2 and found999
    return ok, ok and "OK" or string.format(
        "expected the unique itemID 999 to survive repeated pickups of another item, got %d entries (found999=%s)",
        #recent, tostring(found999))
end)

Pockets.Tests.TestRunner:Register("RecentItems: rejects zero/negative quantity", function()
    RecentItems:Clear()
    RecentItems:Record({ itemID = 9, quantity = 0, timestamp = 1 })
    RecentItems:Record({ itemID = 9, quantity = -1, timestamp = 1 })

    local count = #RecentItems:GetRecent(10)
    local ok = count == 0
    return ok, ok and "OK" or string.format("expected 0 entries, got %d", count)
end)

--------------------------------------------------
-- Persistence (Recent Items persistence pass)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("RecentItems: LoadPersisted restores a previous session's saved entries", function()
    local originalEntries = RecentItems.entries
    local saved = { { itemID = 42, quantity = 3, timestamp = 1, itemLink = "item:42" } }

    RecentItems:LoadPersisted(saved)
    local recent = RecentItems:GetRecent(1)
    local ok = recent[1] and recent[1].itemID == 42 and recent[1].quantity == 3

    RecentItems.entries = originalEntries
    return ok, ok and "OK" or "expected LoadPersisted to restore the saved entry"
end)

Pockets.Tests.TestRunner:Register("RecentItems: LoadPersisted drops corrupted entries (missing itemID/quantity)", function()
    local originalEntries = RecentItems.entries
    local saved = {
        { itemID = 1, quantity = 1 },
        { itemID = 2 }, -- missing quantity
        { quantity = 5 }, -- missing itemID
        "not a table",
    }

    RecentItems:LoadPersisted(saved)
    local recent = RecentItems:GetRecent(10)
    local ok = #recent == 1 and recent[1].itemID == 1

    RecentItems.entries = originalEntries
    return ok, ok and "OK" or string.format("expected only the 1 valid entry to survive, got %d", #recent)
end)

Pockets.Tests.TestRunner:Register("RecentItems: after LoadPersisted, Record/Clear mutate the SAME saved table (never replace it)", function()
    local originalEntries = RecentItems.entries
    local saved = {}

    RecentItems:LoadPersisted(saved)
    RecentItems:Record({ itemID = 7, quantity = 1, timestamp = 1 })
    local sameTableAfterRecord = RecentItems.entries == saved and #saved == 1

    RecentItems:Clear()
    local sameTableAfterClear = RecentItems.entries == saved and #saved == 0

    RecentItems.entries = originalEntries
    local ok = sameTableAfterRecord and sameTableAfterClear
    return ok, ok and "OK" or "expected Record/Clear to keep mutating the exact table LoadPersisted was given"
end)
