--[[
    API.lua - Small public integration surface (TDD §18)

    Intentionally minimal. This is the seam future pH integration and any
    other consumer should use instead of reaching into Core/UI modules
    directly.
]]

local _, Pockets = ...

local API = Pockets.API

function API.GetBagStatus()
    return Pockets.Services.InventoryState:GetGeneralCapacity()
end

function API.GetAmmoStatus()
    return Pockets.Services.InventoryState:GetAmmoCapacity()
end

function API.GetBagETA()
    local estimator = Pockets.Services.CapacityEstimator
    return {
        state = estimator:GetState(),
        seconds = estimator:GetETA(),
        confidence = estimator:GetConfidence(),
    }
end

function API.GetRecentItems(limit)
    return Pockets.Services.RecentItems:GetRecent(limit)
end

-- Recent is a history view, not an assigned category (TDD §5.2/§10) - its
-- entries are resolved against current InventoryState here rather than in
-- UI code, so both the flyout and full inventory stay consistent
-- (UI_SPEC §9 "Recent Items", §10 "share item rendering code").
--
-- Deduplicated by itemID (newest acquisition wins position/ordering,
-- RecentItems:GetRecent is already newest-first) so repeated recent
-- pickups of the same item render as one aggregate entry, matching the
-- full-inventory grid's "one icon per itemID" rule. When still carried,
-- the displayed quantity is the true current total (GetCarriedQuantity),
-- not just whatever one physical stack happens to report.
--
-- v1 only presents still-carried acquisitions (UI_SPEC §9). There is no
-- consume-specific WoW event - crafting/vendoring/mailing just produce a
-- negative quantity delta on the next bag scan. The history queue keeps
-- those entries; this resolver omits them so a spent reagent cannot sit
-- in Recent as a ghost.
local function GetResolvedRecentItems()
    local out = {}
    local seen = {}
    for _, entry in ipairs(Pockets.Services.RecentItems:GetRecent(Pockets.Constants.RECENT_DISPLAY_LIMIT)) do
        if not seen[entry.itemID] then
            seen[entry.itemID] = true
            local live = Pockets.Services.InventoryState:FindLiveRecordByItemID(entry.itemID)
            if live then
                local carriedTotal = Pockets.Services.InventoryState:GetCarriedQuantity(entry.itemID)
                table.insert(out, {
                    itemID = entry.itemID,
                    itemLink = live.itemLink,
                    name = live.name,
                    quantity = carriedTotal > 0 and carriedTotal or live.quantity,
                    texture = live.texture,
                    quality = live.quality,
                    isLocked = live.isLocked,
                    bagID = live.bagID,
                    slotID = live.slotID,
                    interactive = true,
                })
            end
        end
    end
    return out
end

-- Returns the item records to render for a category or "recent" (TDD §5.1
-- GetItemsByCategory + the Recent resolution above). Read-only lookup over
-- already-precomputed state - performs no bag scan/categorization
-- (UI_SPEC §6), safe to call on every hover.
function API.GetCategoryItems(categoryID)
    if categoryID == Pockets.Constants.CATEGORY.RECENT then
        return GetResolvedRecentItems()
    end
    return Pockets.Services.InventoryState:GetItemsByCategory(categoryID)
end

-- Sort key for A-Z item ordering (.plans/Fix_TODO.md #1): case-insensitive by name,
-- with items missing a resolved name (ItemAPI still pending) sorted last
-- via their "item:<id>" fallback rather than as empty strings.
local function ItemSortKey(item)
    return item.name and item.name:lower() or ("item:" .. tostring(item.itemID))
end

local function SortItemsByName(items)
    table.sort(items, function(a, b)
        local aHasName, bHasName = a.name ~= nil, b.name ~= nil
        if aHasName ~= bHasName then
            return aHasName
        end
        return ItemSortKey(a) < ItemSortKey(b)
    end)
    return items
end

-- Same as GetCategoryItems, but collapsed to one entry per itemID
-- (InventoryState:AggregateRecords + ItemButtonPool.ToButtonRecord) -
-- an item spread across many bag slots renders as a single button with
-- a summed count everywhere Pockets shows an item grid (UI_SPEC §7/§10).
-- Recent is already itemID-deduped/button-shaped by GetCategoryItems, and
-- stays newest-first (recency is the point of that view), so it skips both
-- aggregation and the A-Z sort applied to every other category.
function API.GetAggregatedCategoryItems(categoryID)
    if categoryID == Pockets.Constants.CATEGORY.RECENT then
        return API.GetCategoryItems(categoryID)
    end
    local aggregates = Pockets.Services.InventoryState:AggregateRecords(API.GetCategoryItems(categoryID))
    local out = {}
    for _, agg in ipairs(aggregates) do
        table.insert(out, Pockets.UI.ItemButtonPool.ToButtonRecord(agg))
    end
    return SortItemsByName(out)
end

-- Every currently carried item collapsed to one entry per itemID, across
-- ALL categories at once (Glance Quick Search pass) - unlike
-- GetAggregatedCategoryItems, this is not scoped to a category and never
-- goes through Recent's history/dedupe path, so an item shows up exactly
-- once regardless of whether it was also recently acquired. Reads
-- InventoryState's already-scanned/aggregated snapshot only - no bag
-- rescan, safe to call on every Quick Search keystroke.
function API.GetAllAggregatedItems()
    local InventoryState = Pockets.Services.InventoryState
    local records = {}
    for _, record in pairs(InventoryState:GetItems()) do
        table.insert(records, record)
    end
    local aggregates = InventoryState:AggregateRecords(records)
    local out = {}
    for _, agg in ipairs(aggregates) do
        table.insert(out, Pockets.UI.ItemButtonPool.ToButtonRecord(agg))
    end
    return out
end

function API.GetCategorySummary()
    local summary = {}
    for _, categoryID in ipairs(Pockets.Constants.CATEGORY_ORDER) do
        local count
        if categoryID == Pockets.Constants.CATEGORY.RECENT then
            count = #GetResolvedRecentItems()
        else
            count = 0
            for _, item in ipairs(Pockets.Services.InventoryState:GetItemsByCategory(categoryID)) do
                count = count + item.quantity
            end
        end
        table.insert(summary, {
            categoryID = categoryID,
            label = Pockets.Constants.CATEGORY_LABEL[categoryID],
            icon = Pockets.Constants.CATEGORY_ICON[categoryID],
            count = count,
        })
    end
    return summary
end

function API.GetCarriedQuantity(itemID)
    return Pockets.Services.InventoryState:GetCarriedQuantity(itemID)
end

-- Open/Close/Toggle and the Shift-B binding all land in All Items directly
-- (.plans/Pockets_Glance_UI.md §4 "HUD +/expanded action -> ALL directly"),
-- never a second window - there is only the one Shell root frame.
function API.Open()
    Pockets.UI.Shell:SetState(Pockets.UI.Shell.STATE.ALL)
end

function API.Close()
    Pockets.UI.Shell:SetState(Pockets.UI.Shell.STATE.MENU)
end

function API.Toggle()
    Pockets.UI.Shell:ToggleAllItems()
end

function API.ToggleFullInventory()
    Pockets.UI.Shell:ToggleAllItems()
end

function API.Subscribe(eventName, callback, owner)
    Pockets.Services.EventBus:Subscribe(eventName, callback, owner)
end
