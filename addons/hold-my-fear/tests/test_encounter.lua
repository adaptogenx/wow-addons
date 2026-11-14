-- Run: lua tests/test_encounter.lua (from addons/hold-my-fear).
-- Fills Encounter/Tracker gaps left by test_tracker.lua: scans, reset scheduling,
-- demo tracking, Fear refresh, event emission, eviction, marker cleanup.
local clock = 100
local timers, inCombat = {}, false
local env = setmetatable({
    GetTime = function() return clock end,
    InCombatLockdown = function() return inCombat end,
    C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end },
}, { __index = _G })
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

local markers, tokens, auras, units, dots, engaged
local deadTokens, calmTokens = {}, {}
HMF.Adapters.Unit = {
    PlayerGUID = function() return "Player-1" end,
    GUID = function(token) return units[token] and units[token].guid end,
    TokenFor = function(guid) return tokens[guid] end,
    Info = function(token) return units[token].name, units[token].level end,
    GetMarker = function(token) return markers[token] or 0 end,
    SetMarker = function(token, i) markers[token] = i end,
    CanAttack = function() return true end,
    SpellIcon = function(name) return "icon:" .. name end,
    EngagedTokens = function() return engaged end,
    IsDead = function(token) return deadTokens[token] or false end,
    InCombat = function(token) return not calmTokens[token] end,
}
HMF.Adapters.Aura = {
    PlayerDebuffs = function(token) return dots[token] or {} end,
    PlayerDebuff = function(token) local a = auras[token] if a then return a.duration, a.expires end end,
}

local function reset()
    E.Reset(); timers = {}; inCombat = false; clock = 100
    markers, tokens, auras, units, dots, engaged = {}, {}, {}, {}, {}, {}
    deadTokens, calmTokens = {}, {}
end
local function unit(token, guid, name, level)
    units[token] = { guid = guid, name = name, level = level or 1 }
    tokens[guid] = token
end
local function fearEv(sub, guid, name)
    return { sub = sub, srcGUID = "Player-1", dstGUID = guid, dstName = name, spellName = "Fear" }
end

-- Tracker: events fired for every mutation, none for no-ops
reset()
local log = {}
T.Subscribe(function(ev) log[#log + 1] = ev end)
T.Track("a")                                  -- added
T.Track("a", "Late")                          -- updated (name backfill)
T.Track("a", "Other")                         -- no-op: name already set
T.SetFear("a", clock + 10, 10, true)          -- fear-set
T.SetFear("a", clock + 10, 10, true)          -- no-op: same timer
T.SetFear("a", clock + 10, 10, false)         -- fear-set: estimated flag changed
T.ClearFear("a"); T.ClearFear("a")            -- fear-cleared once
T.SetDebuff("a", "Corruption", { icon = "x", expires = clock + 5 })   -- debuff-set
T.SetDebuff("a", "Corruption", { icon = "y", expires = clock + 5 })   -- debuff-set: icon changed
T.ClearDebuff("a", "Corruption"); T.ClearDebuff("a", "Corruption")   -- debuff-cleared once
T.Untrack("a"); T.Untrack("a")                -- removed once
T.Reset("done")                               -- reset
eq(table.concat(log, ","), "added,updated,fear-set,fear-set,fear-cleared,debuff-set,debuff-set,debuff-cleared,removed,reset")
eq(T.Get("a"), nil)

-- Tracker: calls on unknown GUIDs are safe no-ops
reset()
T.SetFear("nope", clock + 1, 1, true); T.ClearFear("nope"); T.SetDebuff("nope", "Corruption", {})
T.ClearDebuff("nope", "Corruption"); T.SetInfo("nope", "x", 1)
eq(T.Count(), 0); eq(T.Track(nil), nil, "nil guid"); eq(#T.ActiveDebuffs(nil), 0); eq(T.FearRemaining(nil), nil)

-- Tracker: a subscriber error never breaks the others
reset()
local reached = false
T.Subscribe(function() error("boom") end)
T.Subscribe(function() reached = true end)
T.Track("a"); assert(reached, "later subscriber still runs")

-- Tracker: AnyFearActive follows the clock
reset()
T.Track("a"); T.Track("b")
eq(T.AnyFearActive(), false)
T.SetFear("b", clock + 3, 3, true); eq(T.AnyFearActive(), true)
clock = clock + 3; eq(T.AnyFearActive(), false, "expired exactly at deadline")

-- Tracker: Reset restarts marker cycling from the beginning
reset()
T.Track("a"); T.Track("b"); T.Reset()
eq(T.Track("c").marker, C.MARKER_ORDER[1], "cycle restarts"); eq(T.Count(), 1)

-- Fear refresh keeps the row and marker, extends the timer
reset()
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-1", "Mob"))
local e = T.Get("Creature-1"); local marker = e.marker
clock = clock + 10
E.OnCombatLog(fearEv("SPELL_AURA_REFRESH", "Creature-1", "Mob"))
eq(T.Get("Creature-1").marker, marker, "marker stable"); eq(T.Count(), 1)
eq(math.floor(T.FearRemaining(e)), C.DEFAULT_FEAR_DURATION, "timer reset by refresh")

-- Fear applied with a readable token: real duration wins immediately, marker is set
reset()
unit("nameplate1", "Creature-1", "Mob", 12)
auras["nameplate1"] = { duration = 8, expires = clock + 8 }
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-1", "Mob"))
e = T.Get("Creature-1")
eq(e.fear.estimated, false); eq(e.fear.duration, 8); eq(e.level, 12); eq(markers["nameplate1"], e.marker)

-- Marker is not rewritten when the unit already carries it
local sets = 0
local origSet = HMF.Adapters.Unit.SetMarker
HMF.Adapters.Unit.SetMarker = function(t, i) sets = sets + 1; origSet(t, i) end
E.OnUnitSeen("nameplate1"); E.OnUnitSeen("nameplate1")
eq(sets, 0, "no redundant SetMarker"); HMF.Adapters.Unit.SetMarker = origSet

-- OnUnitSeen ignores untracked and unreadable tokens
reset()
unit("nameplate9", "Creature-9", "Stranger")
E.OnUnitSeen("nameplate9"); E.OnUnitSeen("target")
eq(T.Count(), 0); eq(markers["nameplate9"], nil)

-- Non-damage creature events and non-creature sources do not engage
reset()
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Creature-1", dstGUID = "Player-1", spellName = "Slow" })
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Player-5", dstGUID = "Player-1" })
E.OnCombatLog({ sub = "SPELL_MISSED", srcGUID = "Creature-2", srcName = "Caster", dstGUID = "Player-1" })
eq(T.Count(), 1); eq(T.Get("Creature-2").name, "Caster", "_MISSED engages")

-- Combat-log engagement sets marker when a token is readable
reset()
unit("nameplate3", "Creature-3", "Wolf", 7)
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-3", srcName = "Wolf", dstGUID = "Player-1" })
eq(markers["nameplate3"], T.Get("Creature-3").marker); eq(T.Get("Creature-3").level, 7)

-- ScanEngaged: tracks new, skips tracked and dead, applies info/marker/fear/debuffs
reset()
unit("nameplate1", "Creature-1", "A", 10)
unit("nameplate2", "Creature-2", "B", 11)
unit("nameplate3", "Creature-3", "C", 12)
E.OnCombatLog({ sub = "UNIT_DIED", dstGUID = "Creature-3" })
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-2", srcName = "B", dstGUID = "Player-1" })
local before = T.Get("Creature-2")
auras["nameplate1"] = { duration = 20, expires = clock + 20 }
dots["nameplate1"] = { { name = "Corruption", icon = "c", duration = 18, expires = clock + 18 } }
engaged = {
    { token = "nameplate1", detail = "threat" },
    { token = "nameplate2", detail = "threat" },
    { token = "nameplate3", detail = "threat" },
}
E.ScanEngaged()
eq(T.Count(), 2, "dead mob skipped"); eq(T.Get("Creature-2"), before, "tracked mob untouched")
local a = T.Get("Creature-1")
eq(a.name, "A"); eq(a.level, 10); eq(markers["nameplate1"], a.marker)
assert(a.fear and not a.fear.estimated, "scan applied real fear")
eq(#T.ActiveDebuffs(a), 1)
E.ScanEngaged(); eq(T.Count(), 2, "idempotent")
engaged = {}; E.ScanEngaged(); eq(T.Count(), 2, "empty scan is safe")

-- ScanEngaged respects the marker cap
reset()
engaged = {}
for i = 1, #C.MARKER_ORDER + 3 do
    unit("np" .. i, "Creature-" .. i, "M" .. i)
    engaged[i] = { token = "np" .. i, detail = "threat" }
end
E.ScanEngaged(); eq(T.Count(), #C.MARKER_ORDER)

-- Untrack clears our marker but not a foreign one
reset()
unit("nameplate1", "Creature-1", "A")
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-1", "A"))
local mine = markers["nameplate1"]; assert(mine > 0)
E.Untrack("Creature-1", "test"); eq(markers["nameplate1"], 0, "own marker cleared"); eq(T.Get("Creature-1"), nil)
E.Untrack("Creature-1", "again") -- no error
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-1", "A"))
markers["nameplate1"] = 8 -- user re-marked it
E.Untrack("Creature-1", "test"); eq(markers["nameplate1"], 8, "foreign marker kept")

-- Eviction frees the evicted mob's marker on screen
reset()
for i = 1, #C.MARKER_ORDER do
    unit("np" .. i, "Creature-" .. i, "M" .. i)
    E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-" .. i, dstGUID = "Player-1" })
end
local evictedMarker = T.Get("Creature-1").marker
eq(markers["np1"], evictedMarker)
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-99", "New"))
eq(markers["np1"], 0, "evicted mob unmarked"); eq(T.Get("Creature-99").marker, evictedMarker, "freed marker reused")

-- Eviction never removes a feared mob; with every row feared the new Fear is dropped
reset()
for i = 1, #C.MARKER_ORDER do E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-" .. i, "M" .. i)) end
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-99", "New"))
eq(T.Get("Creature-99"), nil); eq(T.Count(), #C.MARKER_ORDER)
for i = 1, #C.MARKER_ORDER do assert(T.Get("Creature-" .. i), "feared mob kept") end

-- DoT stacking events and refresh restart the estimate; removal of an unknown DoT is safe
reset()
local function dot(sub, spell) return { sub = sub, srcGUID = "Player-1", dstGUID = "Creature-5", dstName = "Imp", spellName = spell } end
E.OnCombatLog(dot("SPELL_AURA_APPLIED", "Corruption"))
clock = clock + 10
E.OnCombatLog(dot("SPELL_AURA_REFRESH", "Corruption"))
eq(math.floor(T.ActiveDebuffs(T.Get("Creature-5"))[1].left), 18, "refresh restarts timer")
E.OnCombatLog(dot("SPELL_AURA_APPLIED_DOSE", "Corruption"))
E.OnCombatLog(dot("SPELL_AURA_REMOVED", "Immolate"))
eq(#T.ActiveDebuffs(T.Get("Creature-5")), 1)
E.OnCombatLog({ sub = "SPELL_AURA_REMOVED", srcGUID = "Player-1", dstGUID = "Creature-404", spellName = "Corruption" })
eq(T.Get("Creature-404"), nil, "removal for untracked mob does not track it")
E.OnCombatLog({ sub = "SPELL_AURA_APPLIED", srcGUID = "Player-1", spellName = "Corruption" }) -- nil dstGUID

-- Reset clears dead tombstones
reset()
E.OnCombatLog({ sub = "UNIT_DIED", dstGUID = "Creature-7" })
E.Reset()
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-7", dstGUID = "Player-1" })
assert(T.Get("Creature-7"), "tombstone cleared on reset")

-- ScheduleReset: waits RESET_DELAY, then resets
reset()
T.Track("a")
E.ScheduleReset()
eq(#timers, 1); eq(timers[1].delay, C.RESET_DELAY)
timers[1].fn(); eq(T.Count(), 0, "reset after delay")

-- ScheduleReset: still in combat -> no reset, no reschedule
reset()
T.Track("a"); inCombat = true
E.ScheduleReset(); timers[1].fn()
eq(T.Count(), 1, "kept in combat"); eq(#timers, 1, "no reschedule")

-- ScheduleReset: active Fear defers the reset; resets once it ends
reset()
T.Track("a"); T.SetFear("a", clock + 30, 30, true)
E.ScheduleReset()
timers[1].fn(); eq(T.Count(), 1, "kept while feared"); eq(#timers, 2, "rescheduled")
clock = clock + 31
timers[2].fn(); eq(T.Count(), 0, "reset after fear expires"); eq(#timers, 2)

-- TrackToken (/hmf demo)
reset()
eq(E.TrackToken("target"), nil, "no unit")
unit("target", "Creature-1", "Dummy", 60)
local d = E.TrackToken("target")
assert(d, "tracked"); eq(d.name, "Dummy"); eq(d.level, 60); eq(d.fear.estimated, true)
eq(markers["target"], d.marker)
reset()
for i = 1, #C.MARKER_ORDER do T.Track("full" .. i) end
unit("target", "Creature-1", "Dummy")
eq(E.TrackToken("target"), nil, "no free marker")

-- Prune: a dead mob whose UNIT_DIED was missed is dropped, even with a Fear or DoT, and stays dead
reset()
unit("nameplate1", "Creature-1", "Wyvern", 22)
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-1", dstGUID = "Player-1" })
E.OnCombatLog(fearEv("SPELL_AURA_APPLIED", "Creature-1", "Wyvern"))
E.Prune(); eq(T.Count(), 1, "alive mob kept")
deadTokens["nameplate1"] = true
E.Prune(); eq(T.Count(), 0, "dead mob pruned"); eq(markers["nameplate1"], 0, "marker cleared")
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-1", dstGUID = "Player-1" })
eq(T.Count(), 0, "pruned corpse not re-tracked")

-- Prune: idle mob that left combat goes after the grace period; feared or dotted mobs stay
reset()
unit("np1", "Creature-1", "Idle"); unit("np2", "Creature-2", "Feared"); unit("np3", "Creature-3", "Dotted")
for i = 1, 3 do E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-" .. i, dstGUID = "Player-1" }) end
T.SetFear("Creature-2", clock + 20, 20, true)
T.SetDebuff("Creature-3", "Corruption", { icon = "c", expires = clock + 18 })
calmTokens = { np1 = true, np2 = true, np3 = true }
E.Prune(); eq(T.Count(), 3, "grace period protects new rows")
clock = clock + C.PRUNE_GRACE + 1
E.Prune()
eq(T.Get("Creature-1"), nil, "idle mob pruned"); assert(T.Get("Creature-2"), "feared kept"); assert(T.Get("Creature-3"), "dotted kept")
clock = clock + 30 -- fear and dot timers run out
E.Prune(); eq(T.Count(), 0, "pruned once timers end")

-- Prune: a mob still in combat is kept
reset()
unit("np1", "Creature-1", "Fighter")
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-1", dstGUID = "Player-1" })
clock = clock + 60; E.Prune(); eq(T.Count(), 1, "in-combat mob kept")

-- Prune: unreadable idle mobs go stale; readable-again resets the clock; feared ones never go stale
reset()
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-1", dstGUID = "Player-1" })
E.OnCombatLog({ sub = "SWING_DAMAGE", srcGUID = "Creature-2", dstGUID = "Player-1" })
T.SetFear("Creature-2", clock + 100, 100, true)
clock = clock + C.STALE_SECONDS - 1; E.Prune(); eq(T.Count(), 2, "not stale yet")
unit("np1", "Creature-1", "One")
E.Prune(); clock = clock + C.STALE_SECONDS - 1; tokens["Creature-1"] = nil
E.Prune(); eq(T.Count(), 2, "seeing it reset the stale clock")
clock = clock + 2; E.Prune()
eq(T.Get("Creature-1"), nil, "stale idle mob pruned"); assert(T.Get("Creature-2"), "feared mob kept")

print("PASS encounter")

-- Targeting a hostile creature gives it a row; players, dead mobs and the friendly are skipped
reset()
units["target"] = { guid = "Creature-77", name = "Boar", level = 5 }
E.TrackTarget()
eq(T.Count(), 1); eq(T.Get("Creature-77").name, "Boar")
E.TrackTarget(); eq(T.Count(), 1, "no duplicate")
units["target"] = { guid = "Player-9", name = "Bob" }; E.TrackTarget(); eq(T.Count(), 1, "player skipped")
units["target"] = { guid = "Creature-78", name = "Dead" }; deadTokens["target"] = true; E.TrackTarget()
eq(T.Count(), 1, "dead skipped")
-- current target survives Prune; a former target (no combat) does not
calmTokens["target"] = true; clock = clock + 100
units["target"] = { guid = "Creature-77", name = "Boar" }; tokens["Creature-77"] = "target"; deadTokens["target"] = nil
E.Prune(); eq(T.Count(), 1, "target keeps its row")
units["target"] = nil; calmTokens["nameplate1"] = true; tokens["Creature-77"] = "nameplate1"
units["nameplate1"] = { guid = "Creature-77", name = "Boar" }
E.Prune(); eq(T.Count(), 0, "untargeted idle row pruned")
print("PASS target")

-- Out of combat, an idle row that is not your target goes at once (even with no token)
reset()
units["target"] = { guid = "Creature-90", name = "Wolf" }; tokens["Creature-90"] = "target"
E.TrackTarget(); eq(T.Count(), 1)
calmTokens["player"] = true
E.Prune(); eq(T.Count(), 1, "still your target")
units["target"] = nil; tokens["Creature-90"] = nil
E.Prune(); eq(T.Count(), 0, "clicked off, out of combat: removed")
-- In combat the row stays
reset()
units["target"] = { guid = "Creature-91", name = "Wolf" }; tokens["Creature-91"] = "target"
E.TrackTarget(); units["target"] = nil; tokens["Creature-91"] = nil
E.Prune(); eq(T.Count(), 1, "in combat: kept")
print("PASS idle prune")

-- Esc (target cleared): out of combat everything goes, even running Fear/DoTs; in combat only idle rows
local function seed()
    reset()
    T.Track("Creature-95", "Imp"); T.SetFear("Creature-95", clock + 10, 10, true)
    T.SetDebuff("Creature-95", "Corruption", { icon = "x", duration = 18, expires = clock + 18 })
    T.Track("Creature-96", "Idle")
end
seed(); calmTokens["player"] = true
eq(E.OnTargetCleared(), true, "out of combat: cleared"); eq(T.Count(), 0)
seed()
eq(E.OnTargetCleared(), false, "in combat: not cleared"); eq(T.Count(), 2, "in combat: rows kept (Prune only drops idle rows it can see leave combat)")
seed(); calmTokens["player"] = true; units["target"] = { guid = "Creature-95" }
eq(E.OnTargetCleared(), false, "still have a target: nothing"); eq(T.Count(), 2)
print("PASS esc clear")
