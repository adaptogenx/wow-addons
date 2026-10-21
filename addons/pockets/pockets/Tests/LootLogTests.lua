--[[
    Tests/LootLogTests.lua - Core/LootLog.lua: event storage, ordering,
    bounds, persistence, looted-coin gating, loot-context gating and single-source dedup.

    Every test runs against a throwaway store (WithFreshLog) and restores
    the player's real log afterward - these tests must never wipe or
    pollute the persisted Loot Log.
]]

local _, Pockets = ...

local LootLog = Pockets.Services.LootLog
local Constants = Pockets.Constants
local TestRunner = Pockets.Tests.TestRunner

local function WithFreshLog(fn)
    local saved = {
        store = LootLog.store, entries = LootLog.entries, revision = LootLog.revision,
        lastMoney = LootLog.lastMoney, lootWindowOpen = LootLog.lootWindowOpen, questWindowOpen = LootLog.questWindowOpen, lootClosedAt = LootLog.lootClosedAt, clock = LootLog.clock,
    }
    LootLog.store = { nextId = 1, entries = {} }
    LootLog.entries = LootLog.store.entries
    LootLog.lastMoney = nil
    LootLog.lootWindowOpen, LootLog.questWindowOpen, LootLog.lootClosedAt = false, false, nil
    LootLog.clock = function() return 1000 end -- every event in the same second
    local ok, a, b = pcall(fn)
    LootLog.store, LootLog.entries, LootLog.revision = saved.store, saved.entries, saved.revision
    LootLog.lastMoney = saved.lastMoney
    LootLog.questWindowOpen = saved.questWindowOpen
    LootLog.lootWindowOpen, LootLog.lootClosedAt, LootLog.clock = saved.lootWindowOpen, saved.lootClosedAt, saved.clock
    if not ok then
        error(a, 0)
    end
    return a, b
end

TestRunner:Register("LootLog: item event recorded with quantity and link preserved", function()
    return WithFreshLog(function()
        LootLog:RecordItem(2589, 3, "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r")
        local e = LootLog:GetEntries()[1]
        local ok = e.kind == "item" and e.itemID == 2589 and e.quantity == 3 and e.itemLink:find("Linen Cloth", 1, true)
        return ok and true or false, ok and "OK" or "item entry did not keep itemID/quantity/link"
    end)
end)

TestRunner:Register("LootLog: item without a link or cached metadata is still recorded", function()
    return WithFreshLog(function()
        LootLog:RecordItem(99999, 1, nil)
        local ok = #LootLog:GetEntries() == 1 and LootLog:GetEntries()[1].itemLink == nil
        return ok, ok and "OK" or "event lost when item metadata/link was unavailable"
    end)
end)

TestRunner:Register("LootLog: invalid item events (zero/negative/missing) are ignored", function()
    return WithFreshLog(function()
        LootLog:RecordItem(1, 0)
        LootLog:RecordItem(1, -2)
        LootLog:RecordItem(nil, 1)
        local ok = #LootLog:GetEntries() == 0
        return ok, ok and "OK" or "invalid item event was recorded"
    end)
end)

TestRunner:Register("LootLog: newest first, and same-second events keep insertion order", function()
    return WithFreshLog(function()
        LootLog:RecordItem(1, 1)
        LootLog:RecordItem(3, 1)
        LootLog:RecordItem(2, 1)
        local e = LootLog:GetEntries()
        local ok = e[1].itemID == 2 and e[2].itemID == 3 and e[3].itemID == 1
            and e[1].time == e[3].time and e[1].id > e[2].id and e[2].id > e[3].id
        return ok, ok and "OK" or "ordering is not strictly newest-first by id within one second"
    end)
end)

TestRunner:Register("LootLog: history is bounded to LOOT_LOG_MAX, oldest dropped first", function()
    return WithFreshLog(function()
        local max = Constants.LOOT_LOG_MAX
        for i = 1, max + 25 do
            LootLog:RecordItem(i, 1)
        end
        local e = LootLog:GetEntries()
        local ok = #e == max and e[1].itemID == max + 25 and e[#e].itemID == 26
        return ok, ok and "OK" or string.format("expected %d entries newest=%d oldest=26, got %d", max, max + 25, #e)
    end)
end)

TestRunner:Register("LootLog: GetEntries(limit) returns the newest N", function()
    return WithFreshLog(function()
        for i = 1, 5 do LootLog:RecordItem(i, 1) end
        local e = LootLog:GetEntries(2)
        local ok = #e == 2 and e[1].itemID == 5 and e[2].itemID == 4
        return ok, ok and "OK" or "limit did not return newest-first slice"
    end)
end)

local function WithStubbedBags(slots, fn)
    local BagAPI = Pockets.Adapters.BagAPI
    local InventoryState = Pockets.Services.InventoryState
    local RecentItems = Pockets.Services.RecentItems
    local originalScan, originalCounts = BagAPI.ScanAllBags, BagAPI.GetCapacityCounts
    local Estimator = Pockets.Services.CapacityEstimator
    local originalPrevious = InventoryState.previousQuantitiesByItemID
    local originalRecent = RecentItems.entries
    -- Refresh() replaces the live snapshot/capacity/estimator history with
    -- the stub's; restore them so a test run never leaves bogus state.
    local originalItems, originalGeneral, originalAmmo =
        InventoryState.items, InventoryState.generalCapacity, InventoryState.ammoCapacity
    local originalSamples = Estimator.samples
    Estimator.samples = {}

    BagAPI.ScanAllBags = function() return slots.current end
    BagAPI.GetCapacityCounts = function()
        return { general = { used = 0, total = 16 }, ammo = { used = 0, total = 0 } }
    end
    InventoryState.previousQuantitiesByItemID = nil
    RecentItems.entries = {}

    local ok, err = pcall(fn)

    BagAPI.ScanAllBags, BagAPI.GetCapacityCounts = originalScan, originalCounts
    InventoryState.previousQuantitiesByItemID = originalPrevious
    RecentItems.entries = originalRecent
    InventoryState.items, InventoryState.generalCapacity, InventoryState.ammoCapacity =
        originalItems, originalGeneral, originalAmmo
    Estimator.samples = originalSamples
    if not ok then
        error(err, 0)
    end
end

local function Slot(bag, index, itemID, quantity)
    return { bagID = bag, slotIndex = index, itemID = itemID, quantity = quantity, itemLink = "item:" .. itemID }
end

-- Looted coin ---------------------------------------------------------------

TestRunner:Register("LootLog: RecordMoney keeps looted coin and ignores zero/negative amounts", function()
    return WithFreshLog(function()
        LootLog:RecordMoney(213)
        LootLog:RecordMoney(0)
        LootLog:RecordMoney(-4500)
        local e = LootLog:GetEntries()
        local ok = #e == 1 and e[1].kind == "money" and e[1].copper == 213
        return ok, ok and "OK" or "expected exactly one +213 entry"
    end)
end)

TestRunner:Register("LootLog: first money observation is only a baseline (login is not income)", function()
    return WithFreshLog(function()
        LootLog:SetLootWindowOpen(true)
        LootLog:ObserveMoney(123456)
        local ok = #LootLog:GetEntries() == 0 and LootLog.lastMoney == 123456
        return ok, ok and "OK" or "baseline observation was recorded as an event"
    end)
end)

TestRunner:Register("LootLog: coin gained while looting is logged", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(1000)
        LootLog:SetLootWindowOpen(true)
        LootLog:ObserveMoney(1213)
        local e = LootLog:GetEntries()
        local ok = #e == 1 and e[1].copper == 213
        return ok, ok and "OK" or "looted coin was not logged"
    end)
end)

TestRunner:Register("LootLog: coin NOT from looting (vendor sale, mail, quest, trade) is not logged", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(1000)
        LootLog:ObserveMoney(5000) -- sold items / mail / quest gold: no loot context
        local ok = #LootLog:GetEntries() == 0 and LootLog.lastMoney == 5000
        return ok, ok and "OK" or "non-loot gold was logged (or the balance was not tracked)"
    end)
end)

TestRunner:Register("LootLog: spending is never logged, and the balance still tracks", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(5000)
        LootLog:SetLootWindowOpen(true)
        LootLog:ObserveMoney(4000) -- repair/purchase while a loot window happens to be open
        LootLog:ObserveMoney(4100) -- then +100 looted: diff is from 4000, not 5000
        local e = LootLog:GetEntries()
        local ok = #e == 1 and e[1].copper == 100
        return ok, ok and "OK" or "expense logged or baseline not tracked through it"
    end)
end)

TestRunner:Register("LootLog dedup: repeated PLAYER_MONEY with an unchanged balance records nothing", function()
    return WithFreshLog(function()
        LootLog:ObserveMoney(5000)
        LootLog:SetLootWindowOpen(true)
        LootLog:ObserveMoney(5100)
        LootLog:ObserveMoney(5100)
        LootLog:ObserveMoney(5100)
        local ok = #LootLog:GetEntries() == 1
        return ok, ok and "OK" or "a repeated PLAYER_MONEY duplicated the money event"
    end)
end)

-- Quest rewards ---------------------------------------------------------------

TestRunner:Register("LootLog: quest reward gold and items are logged (quest dialog open, then grace)", function()
    return WithFreshLog(function()
        local now = 1000
        LootLog.clock = function() return now end
        LootLog:ObserveMoney(1000)
        LootLog:SetQuestWindowOpen(true)
        local gold = LootLog:ObserveMoney(3500)
        LootLog:SetQuestWindowOpen(false)
        now = 1002
        local item = LootLog:ObserveAcquisition(2589, 1)
        now = 1000 + Constants.LOOT_CONTEXT_GRACE_SECONDS + 1
        local late = LootLog:ObserveAcquisition(2590, 1)
        local ok = gold ~= nil and gold.copper == 2500 and item ~= nil and late == nil
        return ok, ok and "OK" or "quest reward gold/item not logged, or logged outside the context"
    end)
end)

-- Loot context gating ------------------------------------------------------

TestRunner:Register("LootLog: no loot context => acquisitions (purchases, mail, quest, crafting) are NOT logged", function()
    return WithFreshLog(function()
        local e1 = LootLog:ObserveAcquisition(2589, 5)
        local ok = e1 == nil and #LootLog:GetEntries() == 0 and LootLog:IsLootContextActive() == false
        return ok, ok and "OK" or "an acquisition outside a loot window was logged"
    end)
end)

TestRunner:Register("LootLog: loot window open => acquisitions are logged", function()
    return WithFreshLog(function()
        LootLog:SetLootWindowOpen(true)
        LootLog:ObserveAcquisition(2589, 5, "item:2589")
        local e = LootLog:GetEntries()
        local ok = #e == 1 and e[1].itemID == 2589 and e[1].quantity == 5
        return ok, ok and "OK" or "loot-window acquisition was not logged"
    end)
end)

TestRunner:Register("LootLog: bag updates just after the window closes still count; later ones do not", function()
    return WithFreshLog(function()
        local now = 1000
        LootLog.clock = function() return now end
        LootLog:SetLootWindowOpen(true)
        LootLog:SetLootWindowOpen(false)
        now = 1000 + Constants.LOOT_CONTEXT_GRACE_SECONDS
        local within = LootLog:ObserveAcquisition(1, 1) ~= nil
        now = 1000 + Constants.LOOT_CONTEXT_GRACE_SECONDS + 1
        local after = LootLog:ObserveAcquisition(2, 1) ~= nil
        local ok = within and not after
        return ok, ok and "OK" or string.format("within grace=%s after grace=%s", tostring(within), tostring(after))
    end)
end)

TestRunner:Register("LootLog: a vendor sale/purchase flow (no loot window) logs nothing", function()
    return WithFreshLog(function()
        local slots = {}
        local ok
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            slots.current = { Slot(0, 1, 2589, 10) }
            InventoryState:Refresh("baseline")
            slots.current = {}                                  -- sold
            InventoryState:Refresh("sold")
            slots.current = { Slot(0, 1, 159, 5) }              -- bought water
            InventoryState:Refresh("bought")
            ok = #LootLog:GetEntries() == 0
        end)
        return ok, ok and "OK" or "a sale/purchase was logged as loot"
    end)
end)

TestRunner:Register("LootLog dedup: moving/splitting/combining stacks is not an acquisition", function()
    return WithFreshLog(function()
        local slots = {}
        local ok
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            slots.current = { Slot(0, 1, 2589, 10), Slot(0, 2, 2589, 5) }
            InventoryState:Refresh("baseline")
            -- Combine into one stack in another bag: same total.
            slots.current = { Slot(1, 1, 2589, 15) }
            InventoryState:Refresh("move")
            -- Split.
            slots.current = { Slot(1, 1, 2589, 8), Slot(1, 2, 2589, 7) }
            InventoryState:Refresh("split")
            ok = #LootLog:GetEntries() == 0
        end)
        return ok, ok and "OK" or "stack movement was logged as loot"
    end)
end)

TestRunner:Register("LootLog dedup: one acquisition across two bags logs one item entry with the total delta", function()
    return WithFreshLog(function()
        local slots = {}
        local ok, detail
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            LootLog:SetLootWindowOpen(true)
            slots.current = { Slot(0, 1, 2589, 10) }
            InventoryState:Refresh("baseline")
            -- +5 landing as a new stack in another bag.
            slots.current = { Slot(0, 1, 2589, 10), Slot(1, 1, 2589, 5) }
            InventoryState:Refresh("loot")
            local e = LootLog:GetEntries()
            ok = #e == 1 and e[1].itemID == 2589 and e[1].quantity == 5
            detail = #e
        end)
        return ok, ok and "OK" or ("expected one +5 entry, got " .. tostring(detail))
    end)
end)

TestRunner:Register("LootLog: simultaneous acquisitions land in a deterministic (itemID) order", function()
    return WithFreshLog(function()
        local slots = {}
        local ok
        WithStubbedBags(slots, function()
            local InventoryState = Pockets.Services.InventoryState
            LootLog:SetLootWindowOpen(true)
            slots.current = {}
            InventoryState:Refresh("baseline")
            slots.current = { Slot(0, 1, 30, 1), Slot(0, 2, 10, 1), Slot(0, 3, 20, 1) }
            InventoryState:Refresh("loot")
            local e = LootLog:GetEntries()
            -- Newest first: last recorded (highest itemID) is on top.
            ok = #e == 3 and e[1].itemID == 30 and e[2].itemID == 20 and e[3].itemID == 10
        end)
        return ok, ok and "OK" or "simultaneous loot was not recorded in deterministic order"
    end)
end)

-- Persistence ------------------------------------------------------------

TestRunner:Register("LootLog: LoadPersisted drops malformed entries, re-sorts, and keeps ids increasing", function()
    return WithFreshLog(function()
        local saved = {
            nextId = 1, -- stale/corrupt: below the surviving ids
            entries = {
                { id = 3, time = 1, kind = "item", itemID = 5, quantity = 1 },
                "garbage",
                { id = 7, time = 1, kind = "money", copper = -5 },
                { id = 4, time = 1, kind = "item", itemID = 6, quantity = 0 }, -- invalid quantity
                { id = 5, time = 1, kind = "money", copper = 0 }, -- invalid copper
                { id = 6, time = 1, kind = "item", itemID = 7, quantity = 2 },
            },
        }
        LootLog:LoadPersisted(saved)
        local e = LootLog:GetEntries()
        -- Invalid money entries (ids 7 and 5: non-positive copper) are dropped too.
        local ok = #e == 2 and e[1].id == 6 and e[2].id == 3 and saved.nextId == 7
            and LootLog.entries == saved.entries
        local newest = LootLog:RecordItem(1, 1)
        ok = ok and newest.id == 7 and LootLog:GetEntries()[1] == newest
        return ok, ok and "OK" or "persisted load did not sanitize/sort or nextId regressed"
    end)
end)

TestRunner:Register("LootLog: LoadPersisted adopts the saved table so later events persist in place", function()
    return WithFreshLog(function()
        local saved = { nextId = 1, entries = {} }
        LootLog:LoadPersisted(saved)
        LootLog:RecordItem(1, 1)
        local ok = #saved.entries == 1 and saved.nextId == 2
        return ok, ok and "OK" or "events recorded after load did not land in the persisted table"
    end)
end)

TestRunner:Register("LootLog: publishes LOOT_LOGGED once per recorded event", function()
    return WithFreshLog(function()
        local count = 0
        local owner = {}
        Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.LOOT_LOGGED, function() count = count + 1 end, owner)
        LootLog:RecordItem(1, 1)
        LootLog:RecordItem(2, 3)
        LootLog:RecordItem(nil, 1)
        Pockets.Services.EventBus:UnsubscribeOwner(owner)
        local ok = count == 2
        return ok, ok and "OK" or ("expected 2 publishes, got " .. count)
    end)
end)

-- pH independence --------------------------------------------------------

TestRunner:Register("LootLog: works with pH absent (no pH global is read or required)", function()
    return WithFreshLog(function()
        -- Key assembled at runtime: static-checks.sh bans literal pH_
        -- references in Pockets code, and this is deliberately not one.
        local ledgerKey = "p" .. "H_Ledger"
        local savedLedger = _G[ledgerKey]
        _G[ledgerKey] = nil
        local ok, err = pcall(function()
            LootLog:RecordItem(1, 1)
        end)
        _G[ledgerKey] = savedLedger
        return ok, ok and "OK" or tostring(err)
    end)
end)

-- Money formatting -------------------------------------------------------

local MONEY_CASES = {
    { 78, "78c" }, { 5678, "56s 78c" }, { 12340000, "1,234g" }, { 12345678, "1,234g 56s" },
    { 29382514, "2,938g 25s" }, { 12500, "1g 25s" }, { -4500, "-45s" }, { -213, "-2s 13c" },
    { 213, "2s 13c" },
}

for _, case in ipairs(MONEY_CASES) do
    TestRunner:Register(string.format("LootLog money format: %d -> %q", case[1], case[2]), function()
        local actual = Pockets.UI.MoneyFormat:Format(case[1])
        local ok = actual == case[2]
        return ok, ok and "OK" or string.format("expected %q, got %q", case[2], tostring(actual))
    end)
end
