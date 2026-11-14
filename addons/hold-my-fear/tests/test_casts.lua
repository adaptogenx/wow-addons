-- Run: lua tests/test_casts.lua (from addons/hold-my-fear).
-- Forever tracking from the player's own casts: SENT locks a mob, SUCCEEDED tracks it.
local clock = 100
local env = setmetatable({
    GetTime = function() return clock end,
    C_Timer = { After = function() end },
}, { __index = _G })
env._G = env

local HMF = { Services = {}, Adapters = {}, UI = {}, Tests = {} }
local function load(path)
    assert(loadfile(path, "t", env))("HoldMyFear", HMF)
end
local locked = {}
HMF.Adapters.Unit = {
    PlayerGUID = function() return "Player-1" end,
    IsSecret = function(v) return v == "SECRET" end,
    TokenFor = function() return nil end,
    GetMarker = function() return 0 end,
    SetMarker = function() end,
    IsDead = function(token) return token == "deadplate" end,
    GUID = function(token) return token == "deadplate" and "dead-guid" or nil end,
    PlateGUID = function() return nil end,
    SpellIcon = function(name) return "icon:" .. name end,
}
load("holdmyfear/Constants.lua")
HMF.Adapters.Forever = {
    TrackedName = function(id) return HMF.Constants.SPELL_NAME_BY_ID[id] end,
    LockCast = function(name) return locked[name] end,
    IconFor = function(id) return "tex:" .. id end,
}
load("holdmyfear/Core/Tracker.lua")
load("holdmyfear/Core/Encounter.lua")
load("holdmyfear/Core/Casts.lua")

local T, E, Casts, C = HMF.Services.Tracker, HMF.Services.Encounter, HMF.Services.Casts, HMF.Constants
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

-- Fear rank 3 on a locked mob: tracked with a 20s estimate
locked["Boar"] = "Creature-1"
Casts.OnSent("Boar", "cast-1", 6215)
eq(T.Get("Creature-1"), nil, "not tracked before the cast lands")
Casts.OnSucceeded("cast-1")
local e = T.Get("Creature-1")
assert(e, "tracked after SUCCEEDED")
eq(e.name, "Boar")
eq(T.FearRemaining(e, clock), 20, "rank 3 Fear lasts 20s")
eq(e.fear.estimated, true)

-- Fear rank 1 lasts 10s
locked["Wolf"] = "Creature-2"
Casts.OnSent("Wolf", "cast-2", 5782); Casts.OnSucceeded("cast-2")
eq(T.FearRemaining(T.Get("Creature-2"), clock), 10)

-- DoT: tracked with its estimate and the cast's own icon
Casts.OnSent("Boar", "cast-3", 172); Casts.OnSucceeded("cast-3")
local d = T.AllDebuffs(T.Get("Creature-1"), clock)
eq(#d, 1); eq(d[1].name, "Corruption"); eq(d[1].icon, "tex:172"); eq(d[1].duration, 18)

-- Unlisted spell, no lockable mob, failed cast, secret args: all ignored
Casts.OnSent("Boar", "cast-4", 12345); Casts.OnSucceeded("cast-4")
Casts.OnSent("Nobody", "cast-5", 172); Casts.OnSucceeded("cast-5")
eq(T.Get("Creature-3"), nil)
Casts.OnSent("Boar", "cast-6", 172); Casts.OnFailed("cast-6"); Casts.OnSucceeded("cast-6")
Casts.OnSent("SECRET", "cast-7", 172); Casts.OnSent("Boar", "SECRET", 172); Casts.OnSent("Boar", "cast-8", "SECRET")
eq(T.Count(), 2, "only the two successful Fear targets")

-- Death by health event drops the mob and blocks re-tracking
locked["Dead"] = "dead-guid"
Casts.OnSent("Dead", "cast-9", 172)
Casts.OnHealth("deadplate") -- not tracked yet: no-op
Casts.OnSucceeded("cast-9")
eq(T.Count(), 3)
Casts.OnHealth("deadplate")
eq(T.Get("dead-guid"), nil, "dead mob dropped")
Casts.OnSent("Dead", "cast-10", 172); Casts.OnSucceeded("cast-10")
eq(T.Get("dead-guid"), nil, "dead mob not re-tracked")

-- Reconcile: engine bar gone after the grace period clears it (Fear as broken); still up past the estimate extends it
locked["Imp"] = "Creature-9"
Casts.OnSent("Imp", "c11", 6215); Casts.OnSucceeded("c11")
Casts.OnSent("Imp", "c12", 348); Casts.OnSucceeded("c12")
local F = C.FEAR_SPELL
Casts.Reconcile("Creature-9", F, false)
assert(T.FearRemaining(T.Get("Creature-9"), clock), "inside grace: kept")
clock = clock + 3
Casts.Reconcile("Creature-9", F, false)
eq(T.FearRemaining(T.Get("Creature-9"), clock), nil, "bar gone: Fear cleared")
eq(T.Get("Creature-9").fearBroken, true, "plenty left: counted as broken")
Casts.Reconcile("Creature-9", "Immolate", false)
eq(T.AllDebuffs(T.Get("Creature-9"), clock)[1].expired, true, "bar gone: DoT expired")
Casts.OnSent("Imp", "c13", 172); Casts.OnSucceeded("c13")
clock = clock + 19 -- past the 18s estimate
Casts.Reconcile("Creature-9", "Corruption", true)
eq(T.AllDebuffs(T.Get("Creature-9"), clock)[1].expired, false, "engine still shows it: kept alive")
Casts.Reconcile("Creature-9", "Corruption", nil) -- unreadable: no change

print("PASS test_casts")

-- Learned duration: bar seen up, then gone after a full run -> next cast uses the real length
HoldMyFearDB = nil
env.HoldMyFearDB = {}
locked["Rat"] = "Creature-20"
clock = 500
Casts.OnSent("Rat", "c20", 172); Casts.OnSucceeded("c20")
Casts.Reconcile("Creature-20", "Corruption", true)   -- seen up
clock = clock + 14.15
Casts.Reconcile("Creature-20", "Corruption", false)  -- gone
eq(env.HoldMyFearDB.learned.Corruption, 14, "learned the real duration")
Casts.OnSent("Rat", "c21", 172); Casts.OnSucceeded("c21")
eq(T.AllDebuffs(T.Get("Creature-20"), clock)[1].duration, 14, "next cast uses it")
print("PASS learned")

-- Predicted DoT damage: full damage x share of time left, summed; expired DoTs add nothing
HMF.Adapters.Unit.DotDamage = function(id) return ({ [172] = 800, [348] = 500 })[id] end
env.HoldMyFearDB.learned = nil -- the table durations, not the earlier learned one
clock = 1000
locked["Orc"] = "Creature-30"
Casts.OnSent("Orc", "d1", 172); Casts.OnSucceeded("d1")
Casts.OnSent("Orc", "d2", 348); Casts.OnSucceeded("d2")
local ent = T.Get("Creature-30")
eq(math.floor(T.PredictedDamage(ent, clock)), 1300, "full at cast")
clock = clock + 9   -- Corruption 18s (half left), Immolate 15s (6/15 left)
eq(math.floor(T.PredictedDamage(ent, clock) + 0.5), 600, "800*9/18 + 500*6/15")
clock = clock + 20
eq(T.PredictedDamage(ent, clock), 0, "all expired")
print("PASS predicted damage")
