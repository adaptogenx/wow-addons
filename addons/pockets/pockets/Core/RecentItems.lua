--[[
    Core/RecentItems.lua - Bounded queue of true acquisitions (TDD §5.3, §8.2)

    Records acquisition deltas only - stack movement between bags must never
    appear here (PRD §3.3, TDD §8.2, §12.3). Callers (InventoryState's diff
    step) are responsible for distinguishing acquisition from movement
    before calling Record.

    Persistence (Recent Items persistence pass): self.entries is
    reassigned to PocketsCharDB.recentItems's own table at load time (via
    LoadPersisted, called from Events.lua once PocketsCharDB is
    available) rather than a copy - every Record()/Clear() mutation is
    then automatically captured by WoW's SavedVariablesPerCharacter write
    at logout/reload, with no separate save step (same in-place-mutation
    reliance UI/PositionStrategy.lua's SavePosition already uses for hud
    position). Per-CHARACTER, not per-account, since acquisitions are
    character-specific. `timestamp` uses GetTime() (session-relative
    uptime, not wall-clock) - fine today since nothing compares it across
    sessions (GetSince is same-session only), but a persisted entry's
    timestamp is not meaningfully comparable after a reload/relog.
]]

local _, Pockets = ...

Pockets.Services.RecentItems = Pockets.Services.RecentItems or {}
local RecentItems = Pockets.Services.RecentItems

RecentItems.entries = RecentItems.entries or {}
RecentItems.revision = RecentItems.revision or 0

local MAX_ENTRIES = Pockets.Constants.RECENT_ITEMS_MAX

-- delta: { itemID, quantity, timestamp, itemLink }
--
-- Unique-by-itemID (Fix_TODO.md #2): re-acquiring an already-recent item
-- bumps it to newest instead of adding a second row. Without this, farming
-- many stacks of one item (e.g. fishing) fills MAX_ENTRIES with that one
-- itemID and evicts every other unique recent before the display-time
-- dedupe in API.GetCategoryItems ever runs.
function RecentItems:Record(delta)
    if not delta or not delta.itemID or not delta.quantity or delta.quantity <= 0 then
        return
    end

    for i, entry in ipairs(self.entries) do
        if entry.itemID == delta.itemID then
            table.remove(self.entries, i)
            break
        end
    end

    table.insert(self.entries, 1, {
        itemID = delta.itemID,
        quantity = delta.quantity,
        timestamp = delta.timestamp or GetTime(),
        itemLink = delta.itemLink,
    })

    while #self.entries > MAX_ENTRIES do
        table.remove(self.entries)
    end

    self.revision = self.revision + 1
    Pockets.Services.EventBus:Publish(Pockets.Constants.DOMAIN_EVENT.ITEM_ACQUIRED, delta)
end

-- Returns the `limit` most recent entries, newest first.
function RecentItems:GetRecent(limit)
    if not limit or limit >= #self.entries then
        return self.entries
    end
    local out = {}
    for i = 1, limit do
        out[i] = self.entries[i]
    end
    return out
end

function RecentItems:GetSince(timestamp)
    local out = {}
    for _, entry in ipairs(self.entries) do
        if entry.timestamp >= timestamp then
            table.insert(out, entry)
        end
    end
    return out
end

-- Mutates self.entries in place (never reassigns to a new table) - once
-- LoadPersisted has pointed self.entries at PocketsCharDB.recentItems,
-- replacing the reference here would silently break persistence for
-- every entry recorded after this call until the next reload.
function RecentItems:Clear()
    for i = #self.entries, 1, -1 do
        table.remove(self.entries, i)
    end
    self.revision = self.revision + 1
end

-- Restores acquisition history saved from a previous session (Recent
-- Items persistence pass). Reassigns self.entries to savedEntries
-- ITSELF, not a copy, so subsequent Record()/Clear() calls keep writing
-- into the exact table WoW will persist again at the next logout/reload.
-- Called once from Events.lua's ADDON_LOADED handler, after
-- PocketsCharDB.recentItems is confirmed to exist. Validates
-- defensively - a corrupted/hand-edited save, or an entry missing
-- itemID/quantity, is dropped rather than trusted (Record already
-- requires both, so nothing downstream expects to handle their absence).
function RecentItems:LoadPersisted(savedEntries)
    if type(savedEntries) ~= "table" then
        return
    end
    for i = #savedEntries, 1, -1 do
        local entry = savedEntries[i]
        if type(entry) ~= "table" or not entry.itemID or not entry.quantity then
            table.remove(savedEntries, i)
        end
    end
    self.entries = savedEntries
    self.revision = self.revision + 1
end

function RecentItems:GetRevision()
    return self.revision
end
