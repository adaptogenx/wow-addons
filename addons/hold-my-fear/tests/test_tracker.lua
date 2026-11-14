-- Run: lua tests/test_tracker.lua (from addons/hold-my-fear). Tracker + Encounter logic with stubbed adapters.
local clock = 100
local env = setmetatable({ GetTime = function() return clock end }, { __index = _G })
env._G = env

local HMF = { Services = {}, Adapters = {}, UI = {}, Tests = {} }
local function load(path)
    local chunk = assert(loadfile(path, "t", env))
    chunk("HoldMyFear", HMF)
end
load("holdmyfear/Constants.lua")
load("holdmyfear/Core/Tracker.lua")
load("holdmyfear/Core/Encounter.lua")

local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

local T, E, C = HMF.Services.Tracker, HMF.Services.Encounter, HMF.Constants

-- Stub adapters
local markers, tokens, auras, units = {}, {}, {}, {}
HMF.Adapters.Unit = {
    PlayerGUID = function() return "Player-1" end,
    GUID = function(token) return units[token] and units[token].guid end,
    TokenFor = function(guid) return tokens[guid] end,
    Info = function(token) return units[token].name, units[token].level end,
    GetMarker = function(token) return markers[token] or 0 end,
    SetMarker = function(token, i) markers[token] = i end,
    CanAttack = function() return true end,
    SpellIcon = function(name) return "icon:" .. name end,
}
local dots = {}
HMF.Adapters.Aura = {
    PlayerDebuffs = function(token) return dots[token] or {} end, PlayerDebuff = function(token) local a = auras[token] if a then return a.duration, a.expires end end }

local function reset()
    E.Reset(); markers, tokens, auras, units = {}, {}, {}, {}
end

-- Marker assignment: unique, cycling order, capped
reset()
local seen = {}
for i = 1, #C.MARKER_ORDER do
    local e = T.Track("g" .. i, "m" .. i)
    assert(e and not seen[e.marker], "unique marker"); seen[e.marker] = true
    eq(e.marker, C.MARKER_ORDER[i], "order")
end
eq(T.Track("overflow", "x"), nil, "full")
eq(T.Count(), #C.MARKER_ORDER)
local _, isNew = T.Track("g1"); eq(isNew, false)

-- Untrack frees a marker; the next enemy takes the next free one after the cursor
T.Untrack("g3")
eq(T.Count(), #C.MARKER_ORDER - 1)
eq(T.Track("new", "n").marker, C.MARKER_ORDER[3], "freed marker reused")

-- Row order is insertion order
reset()
T.Track("a"); T.Track("b"); T.Track("c"); T.Untrack("b")
local list = T.List(); eq(#list, 2); eq(list[1].guid, "a"); eq(list[2].guid, "c")

-- Subscribers
reset()
local log = {}
T.Subscribe(function(ev, entry) log[#log + 1] = ev .. ":" .. tostring(entry and entry.guid) end)
T.Track("a"); T.SetInfo("a", "Mob", 20); T.SetInfo("a", "Mob", 20); T.Untrack("a")
eq(table.concat(log, ","), "added:a,updated:a,removed:a", "events (no dup update)")

-- Fear remaining
reset()
T.Track("a"); T.SetFear("a", clock + 10, 10, true)
eq(T.FearRemaining(T.Get("a")), 10); clock = clock + 4; eq(T.FearRemaining(T.Get("a")), 6)
clock = clock + 6; eq(T.FearRemaining(T.Get("a")), nil, "expired"); clock = 100

-- Encounter: player Fear applied -> tracked + estimated timer
reset()
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "m1", dstName = "Mob1", spellName = "Fear" })
local e = T.Get("m1"); assert(e, "tracked"); eq(e.name, "Mob1")
eq(e.fear.estimated, true); eq(e.fear.duration, C.DEFAULT_FEAR_DURATION)

-- Someone else's Fear / another spell is ignored
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Other", dstGUID = "m2", dstName = "Mob2", spellName = "Fear" })
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "m3", dstName = "Mob3", spellName = "Corruption" })
eq(T.Get("m2"), nil); eq(T.Get("m3"), nil)

-- Token seen: info, marker applied once, aura confirms real duration
units["nameplate1"] = { guid = "m1", name = "Mob1", level = 24 }
tokens["m1"] = "nameplate1"
auras["nameplate1"] = { duration = 12, expires = clock + 12 }
E.OnUnitSeen("nameplate1")
eq(e.level, 24); eq(markers["nameplate1"], e.marker)
eq(e.fear.estimated, false); eq(e.fear.duration, 12); eq(e.fear.expires, clock + 12)

-- A missing aura (e.g. lag while switching targets) never clears a running timer
auras["nameplate1"] = nil
E.OnUnitSeen("nameplate1"); assert(e.fear and not e.fear.estimated, "confirmed fear kept when aura scan misses")
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "m1", dstName = "Mob1", spellName = "Fear" })
tokens["m1"] = nil
E.OnUnitSeen("nameplate1"); assert(e.fear and e.fear.estimated, "estimate kept without token scan success")

-- Removed aura clears timer but keeps the row
E.OnCombatLog({ sub = "SPELL_AURA_REMOVED", srcGUID = "Player-1", dstGUID = "m1", spellName = "Fear" })
eq(e.fear, nil); assert(T.Get("m1"), "row kept")

-- Death untracks and clears our marker
tokens["m1"] = "nameplate1"; markers["nameplate1"] = e.marker
E.OnCombatLog({ sub = "UNIT_DIED", dstGUID = "m1" })
eq(T.Get("m1"), nil); eq(markers["nameplate1"], 0, "marker cleared")

-- Reset clears markers we own, leaves foreign markers
reset()
units["nameplate2"] = { guid = "m2", name = "Mob2", level = 5 }
tokens["m2"] = "nameplate2"
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "m2", dstName = "Mob2", spellName = "Fear" })
local mine = markers["nameplate2"]; assert(mine and mine > 0)
markers["nameplate2"] = 7 -- user changed the marker themselves
E.Reset(); eq(markers["nameplate2"], 7, "foreign marker kept"); eq(T.Count(), 0)

-- Engaged mobs are tracked from combat-log damage involving the player (no Fear needed)
reset()
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-1", srcName = "Gnoll", dstGUID = "Player-1" })
E.OnCombatLog({ sub = "SPELL_DAMAGE", srcGUID = "Player-1", dstGUID = "Creature-2", dstName = "Boar" })
E.OnCombatLog({ sub = "SPELL_DAMAGE", srcGUID = "Player-1", dstGUID = "Player-9", dstName = "Rogue" }) -- not a creature
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-3", dstGUID = "Pet-1" }) -- not fighting the player
eq(T.Count(), 2); eq(T.Get("Creature-1").name, "Gnoll"); eq(T.Get("Creature-2").name, "Boar")
assert(not T.Get("Creature-1").fear, "engaged row has no fear yet")
-- Fear then lands on an engaged mob: same row/marker, timer starts
local m = T.Get("Creature-1").marker
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "Creature-1", dstName = "Gnoll", spellName = "Fear" })
eq(T.Get("Creature-1").marker, m); assert(T.Get("Creature-1").fear)
-- Untokened hostility check is skipped; a token that cannot be attacked is not tracked
HMF.Adapters.Unit.CanAttack = function() return false end
tokens["Creature-4"] = "nameplate4"; units["nameplate4"] = { guid = "Creature-4", name = "Friendly", level = 1 }
E.OnCombatLog({ sub = "SPELL_DAMAGE", srcGUID = "Player-1", dstGUID = "Creature-4", dstName = "Friendly" })
eq(T.Get("Creature-4"), nil, "friendly not tracked"); HMF.Adapters.Unit.CanAttack = function() return true end

-- Full list of unfeared mobs: a Fear still gets a row by evicting an unfeared one
reset()
for i = 1, #C.MARKER_ORDER do E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-" .. i, dstGUID = "Player-1" }) end
eq(T.Count(), #C.MARKER_ORDER)
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", dstGUID = "Creature-99", dstName = "New", spellName = "Fear" })
assert(T.Get("Creature-99") and T.Get("Creature-99").fear, "feared mob gets a row"); eq(T.Count(), #C.MARKER_ORDER)
eq(T.Get("Creature-1"), nil, "oldest unfeared evicted")

-- A mob that died is not re-tracked by late damage events; a new Fear on it clears the tombstone
reset()
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-7", srcName = "Creeper", dstGUID = "Player-1" })
E.OnCombatLog({ sub = "UNIT_DIED", dstGUID = "Creature-7" })
eq(T.Get("Creature-7"), nil)
E.OnCombatLog({ sub = "SPELL_PERIODIC_DAMAGE", srcGUID = "Player-1", dstGUID = "Creature-7", dstName = "Creeper" })
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-7", dstGUID = "Player-1" })
eq(T.Get("Creature-7"), nil, "dead mob not re-added")

-- Debuffs (M2): player's DoT applied -> tracked + estimated timer + icon
reset(); dots = {}
local function dotEv(sub, spell, src, dst) return { sub = sub, srcGUID = src or "Player-1", dstGUID = dst or "Creature-5", dstName = "Imp", spellName = spell } end
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Corruption"))
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Curse of Agony"))
local de = T.Get("Creature-5"); assert(de, "DoT tracks the mob")
local act = T.ActiveDebuffs(de)
eq(#act, 2); eq(act[1].name, "Corruption", "slot order"); eq(act[2].name, "Curse of Agony")
eq(act[1].icon, "icon:Corruption"); eq(act[1].estimated, true); eq(math.floor(act[1].left), 18)

-- Someone else's DoT / untracked spell / non-creature ignored
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Immolate", "Other"))
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Rejuvenation"))
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Immolate", "Player-1", "Player-9"))
eq(#T.ActiveDebuffs(de), 2)

-- Scan confirms the real duration and icon; a missed scan keeps timers
units["nameplate5"] = { guid = "Creature-5", name = "Imp", level = 10 }
tokens["Creature-5"] = "nameplate5"
dots["nameplate5"] = { { name = "Corruption", icon = "real", duration = 14, expires = clock + 14 } }
E.OnUnitSeen("nameplate5")
act = T.ActiveDebuffs(de); eq(act[1].icon, "real"); eq(act[1].estimated, false); eq(math.floor(act[1].left), 14)
dots["nameplate5"] = {}
E.OnUnitSeen("nameplate5"); eq(#T.ActiveDebuffs(de), 2, "missed scan keeps debuffs")

-- Removed event drops one; expiry hides without a removed event
E.OnCombatLog(dotEv("SPELL_AURA_REMOVED", "Corruption")); act = T.ActiveDebuffs(de)
eq(#act, 1); eq(act[1].name, "Curse of Agony")
clock = clock + 25; eq(#T.ActiveDebuffs(de), 0, "expired hidden"); clock = 100
T.ClearDebuff("Creature-5", "Curse of Agony")

-- Spell with no estimate shows an icon with no timer until the aura scan gives one
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Curse of Weakness"))
act = T.ActiveDebuffs(de); eq(act[#act].name, "Curse of Weakness"); eq(act[#act].left, nil)

-- Identical updates do not re-emit (UNIT_AURA spam)
local n = 0
T.Subscribe(function(ev) if ev == "debuff-set" then n = n + 1 end end)
dots["nameplate5"] = { { name = "Immolate", icon = "i", duration = 15, expires = clock + 15 } }
E.OnUnitSeen("nameplate5"); E.OnUnitSeen("nameplate5"); E.OnUnitSeen("nameplate5")
eq(n, 1, "no duplicate emits")

-- Dead mob drops its debuffs with the row
E.OnCombatLog({ sub = "UNIT_DIED", dstGUID = "Creature-5" }); eq(T.Get("Creature-5"), nil)
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Corruption")); eq(T.Get("Creature-5"), nil, "no re-add after death")

-- Expired DoTs stay listed (for recast); Fear break only with confirmed duration
reset(); dots = {}
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Corruption"))
E.OnCombatLog(dotEv("SPELL_AURA_REMOVED", "Corruption"))
local all = T.AllDebuffs(T.Get("Creature-5"))
eq(#all, 1); eq(all[1].expired, true); eq(all[1].icon, "icon:Corruption"); eq(#T.ActiveDebuffs(T.Get("Creature-5")), 0)
E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Corruption")); eq(T.AllDebuffs(T.Get("Creature-5"))[1].expired, false)
local function fearEv(sub) return { sub = sub, srcGUID = "Player-1", dstGUID = "Creature-5", dstName = "Imp", spellName = "Fear" } end
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED"))
E.OnCombatLog(fearEv("SPELL_AURA_REMOVED")); eq(T.Get("Creature-5").fearBroken, nil, "estimated timer: no break inference")
T.SetFear("Creature-5", clock + 10, 20, false)
E.OnCombatLog(fearEv("SPELL_AURA_REMOVED")); eq(T.Get("Creature-5").fearBroken, true, "confirmed + time left = broken")
T.SetFear("Creature-5", clock + 10, 20, false); eq(T.Get("Creature-5").fearBroken, nil, "recast clears broken")
T.SetFear("Creature-5", clock + 0.5, 20, false)
E.OnCombatLog(fearEv("SPELL_AURA_REMOVED")); eq(T.Get("Creature-5").fearBroken, nil, "natural expiry")

-- Bearing: updated only when a bearing is readable; stale value kept otherwise
reset(); E.OnCombatLog(dotEv("SPELL_AURA_APPLIED", "Corruption"))
units["nameplate5"] = { guid = "Creature-5", name = "Imp", level = 10 }; tokens["Creature-5"] = "nameplate5"
local bearing = 1.25
HMF.Adapters.Unit.WorldBearing = function() return bearing end
E.UpdateBearings(); eq(T.Get("Creature-5").bearing, 1.25)
bearing = nil; E.UpdateBearings(); eq(T.Get("Creature-5").bearing, 1.25, "kept when nameplate gone")
T.SetBearing("nope", 1)

print("PASS tracker")
