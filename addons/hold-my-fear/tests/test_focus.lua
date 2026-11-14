-- Run: lua tests/test_focus.lua (from addons/hold-my-fear). Focus suggestion rules with stubbed adapters.
local clock = 100
local env = setmetatable({ GetTime = function() return clock end }, { __index = _G })
env._G = env

local HMF = { Services = {}, Adapters = {}, UI = {}, Tests = {} }
local function load(path) assert(loadfile(path, "t", env))("HoldMyFear", HMF) end
load("holdmyfear/Constants.lua")
load("holdmyfear/Core/Tracker.lua")

local actualFocus
HMF.Adapters.Unit = { FocusGUID = function() return actualFocus end }
load("holdmyfear/Core/Focus.lua")

local T, F = HMF.Services.Tracker, HMF.Services.Focus
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end
local function fear(guid, secs) T.Track(guid, guid) T.SetFear(guid, clock + secs, secs, false) end

-- First Fear'd mob becomes the suggestion; later ones do not steal it
fear("A", 20); eq(F.Suggested(), "A")
fear("B", 20); eq(F.Suggested(), "A", "no jumping while A's Fear runs")
clock = clock + 10; F.Evaluate(); eq(F.Suggested(), "A")

-- A dies: next one is suggested immediately (no dwell)
T.Untrack("A", "died"); eq(F.Suggested(), "B", "handoff on death")

-- Player's own focus on a tracked mob wins
fear("C", 20); eq(F.Suggested(), "B")
actualFocus = "C"; F.Evaluate(); eq(F.Suggested(), "C", "user focus adopted")
eq(F.IsFocused("C"), true); eq(F.IsFocused("B"), false)

-- Fear on the suggested mob ends: handoff only after MIN_DWELL
T.ClearFear("C", "expired"); eq(F.Suggested(), "C", "held during dwell")
clock = clock + HMF.Constants.FOCUS.MIN_DWELL; F.Evaluate()
eq(F.Suggested(), "B", "handoff after dwell to a mob with Fear running")

-- Manual focus is not overridden by the same-evaluation adoption loop
actualFocus = "B"; F.Evaluate(); eq(F.Suggested(), "B")

-- Nothing feared: suggestion kept if still tracked; cleared on reset
T.ClearFear("B", "expired"); clock = clock + 30; F.Evaluate(); eq(F.Suggested(), "B", "no candidate: keep")
T.Reset("done"); eq(F.Suggested(), nil, "reset clears")

-- Untracked focus unit is ignored
actualFocus = "Z"; fear("D", 20); eq(F.Suggested(), "D")

-- A tracked mob with no Fear is still suggested; a Fear'd mob takes over after the dwell
T.Reset("x"); actualFocus = nil
T.Track("E", "E"); eq(F.Suggested(), "E", "unfeared first mob is primary")
T.SetFear("E", clock + 20, 20, false); T.ClearFear("E", "expired")
fear("G", 20); eq(F.Suggested(), "E", "held during dwell")
clock = clock + HMF.Constants.FOCUS.MIN_DWELL; F.Evaluate(); eq(F.Suggested(), "G")

print("PASS focus")
