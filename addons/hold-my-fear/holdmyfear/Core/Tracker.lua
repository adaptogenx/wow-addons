--[[
    Core/Tracker.lua - Tracked enemies keyed by GUID.

    Each tracked enemy gets a stable raid marker and a stable row position
    (insertion order) for the whole encounter. No frames, no WoW API beyond
    GetTime; UI subscribes via Tracker.Subscribe.
]]

local _, HMF = ...

local Tracker = {}
HMF.Services.Tracker = Tracker

local C = HMF.Constants

local entries = {} -- guid -> entry
local order = {}   -- guids in row order
local byMarker = {} -- marker index -> guid
local cursor = 0
local subscribers = {}

local function now()
    return GetTime and GetTime() or 0
end

local function emit(event, entry, reason)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, event, entry, reason)
        if not ok and HMF.Debug and HMF.Debug.Print then HMF.Debug.Print("subscriber error:", err) end
    end
end

local function nextMarker()
    local n = #C.MARKER_ORDER
    for i = 1, n do
        local idx = (cursor + i - 1) % n + 1
        local marker = C.MARKER_ORDER[idx]
        if not byMarker[marker] then
            cursor = idx
            return marker
        end
    end
end

function Tracker.Subscribe(fn)
    subscribers[#subscribers + 1] = fn
end

function Tracker.Get(guid)
    return entries[guid]
end

-- Entries in row order. Returns a fresh array.
function Tracker.List()
    local list = {}
    for i, guid in ipairs(order) do list[i] = entries[guid] end
    return list
end

function Tracker.Count()
    return #order
end

-- Returns entry, isNew. Returns nil when all markers are in use.
function Tracker.Track(guid, name, reason)
    if not guid then return nil end
    local existing = entries[guid]
    if existing then
        if name and not existing.name then
            existing.name = name
            emit("updated", existing)
        end
        return existing, false
    end
    local marker = nextMarker()
    if not marker then return nil end
    local entry = { guid = guid, name = name, marker = marker, addedAt = now() }
    entries[guid] = entry
    byMarker[marker] = guid
    order[#order + 1] = guid
    emit("added", entry, reason)
    return entry, true
end

function Tracker.Untrack(guid, reason)
    local entry = entries[guid]
    if not entry then return nil end
    entries[guid] = nil
    byMarker[entry.marker] = nil
    for i, g in ipairs(order) do
        if g == guid then table.remove(order, i) break end
    end
    emit("removed", entry, reason)
    return entry
end

function Tracker.Reset(reason)
    entries, order, byMarker, cursor = {}, {}, {}, 0
    emit("reset", nil, reason)
end

function Tracker.SetInfo(guid, name, level)
    local entry = entries[guid]
    if not entry then return end
    local changed = false
    if name and entry.name ~= name then entry.name, changed = name, true end
    if level and entry.level ~= level then entry.level, changed = level, true end
    if changed then emit("updated", entry) end
end

-- estimated = true while the duration is a guess (no aura scan yet).
local function sameTimer(a, b, expires, estimated)
    return a and a.estimated == estimated and ((a.expires == nil and expires == nil)
        or (a.expires and expires and math.abs(a.expires - expires) < 0.05))
end

function Tracker.SetFear(guid, expires, duration, estimated)
    local entry = entries[guid]
    if not entry then return end
    estimated = estimated and true or false
    if sameTimer(entry.fear, nil, expires, estimated) then return end
    entry.fear = { expires = expires, duration = duration, estimated = estimated }
    entry.fearBroken = nil
    emit("fear-set", entry)
end

-- broken = true only with reliable evidence Fear ended early (set by Encounter).
function Tracker.ClearFear(guid, reason, broken)
    local entry = entries[guid]
    if not entry or not entry.fear then return end
    entry.fear = nil
    entry.fearBroken = broken and true or nil
    emit("fear-cleared", entry, reason)
end

-- True while any tracked enemy still has Fear time left.
function Tracker.AnyFearActive(t)
    for _, guid in ipairs(order) do
        if Tracker.FearRemaining(entries[guid], t) then return true end
    end
    return false
end

-- Seconds of Fear left, or nil when none.
function Tracker.FearRemaining(entry, t)
    if not entry or not entry.fear then return nil end
    local left = entry.fear.expires - (t or now())
    if left <= 0 then return nil end
    return left
end

-- Last known compass bearing toward the enemy (radians). Silent: updates every tick.
function Tracker.SetBearing(guid, bearing)
    local entry = entries[guid]
    if not entry then return end
    entry.bearing, entry.bearingAt = bearing, now()
end

-- Player debuffs other than Fear. data = { icon, expires (nil = unknown), duration, estimated }.
function Tracker.SetDebuff(guid, spell, data)
    local entry = entries[guid]
    if not entry then return end
    entry.debuffs = entry.debuffs or {}
    entry.known = entry.known or {}
    entry.known[spell] = true
    entry.icons = entry.icons or {}
    if data.icon then entry.icons[spell] = data.icon end
    local old = entry.debuffs[spell]
    data.estimated = data.estimated and true or false
    if old and old.icon == data.icon and sameTimer(old, nil, data.expires, data.estimated) then return end
    entry.debuffs[spell] = data
    emit("debuff-set", entry)
end

function Tracker.ClearDebuff(guid, spell, reason)
    local entry = entries[guid]
    if not entry or not entry.debuffs or not entry.debuffs[spell] then return end
    entry.debuffs[spell] = nil
    emit("debuff-cleared", entry, reason)
end

-- Debuffs still running, in TRACKED_DEBUFFS order: { name, icon, left (nil = no timer), estimated }.
function Tracker.ActiveDebuffs(entry, t)
    local list = {}
    if not entry or not entry.debuffs then return list end
    t = t or now()
    for name, d in pairs(entry.debuffs) do
        local left = d.expires and (d.expires - t) or nil
        if not left or left > 0 then
            list[#list + 1] = { name = name, icon = d.icon, left = left, estimated = d.estimated }
        end
    end
    table.sort(list, function(a, b) return C.DEBUFF_INDEX[a.name] < C.DEBUFF_INDEX[b.name] end)
    return list
end

-- Damage the tracked DoTs still have to do: each DoT's full damage times the share of its time left.
function Tracker.PredictedDamage(entry, t)
    local total = 0
    if not entry or not entry.debuffs then return total end
    t = t or now()
    for _, d in pairs(entry.debuffs) do
        if d.damage and d.expires and d.duration and d.duration > 0 then
            local left = d.expires - t
            if left > 0 then total = total + d.damage * math.min(1, left / d.duration) end
        end
    end
    return total
end

-- Every debuff the player has applied to this enemy, expired ones included (kept for recasting),
-- in TRACKED_DEBUFFS order: { name, icon, left (nil = no timer), duration, expired }.
function Tracker.AllDebuffs(entry, t)
    local list = {}
    if not entry or not entry.known then return list end
    t = t or now()
    for name in pairs(entry.known) do
        local d = entry.debuffs and entry.debuffs[name]
        local left = d and d.expires and (d.expires - t) or nil
        local expired = (not d) or (left ~= nil and left <= 0)
        list[#list + 1] = {
            name = name, icon = entry.icons and entry.icons[name], left = (not expired) and left or nil,
            duration = d and d.duration, expired = expired, castAt = d and d.castAt,
        }
    end
    table.sort(list, function(a, b) return C.DEBUFF_INDEX[a.name] < C.DEBUFF_INDEX[b.name] end)
    return list
end
