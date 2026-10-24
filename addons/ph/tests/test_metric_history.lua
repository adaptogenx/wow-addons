-- Run: lua tests/test_metric_history.lua (from addons/ph). Whole-session overview stays bounded.
local env = setmetatable({}, { __index = _G })
env._G = env
local clock = 1000
env.time = function() return clock end
env.pH_DB_Account = { debug = { verbose = false }, meta = {}, sessions = {} }
env.pH_Settings = {}
assert(load(io.open("ph/SessionManager.lua"):read("a"), "SessionManager", "t", env))()
local SM = env.pH_SessionManager
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

local session = { items = {} }
-- 600 minutes of play, one tick per minute, gold rate = minute index
for minute = 1, 600 do
    clock = clock + 60
    SM:SampleMetricHistory(session, { totalPerHour = minute, xpPerHour = 0, repPerHour = 0, honorPerHour = 0 })
end
local ov = session.metricHistory.overview
assert(#ov.metrics.gold <= 360, "bounded: " .. #ov.metrics.gold)
eq(#ov.metrics.xp, #ov.metrics.gold, "metrics stay aligned")
assert(ov.interval >= 120, "interval doubled after filling: " .. ov.interval)

local series, interval = SM:GetMetricSeries(session, "gold")
assert(#series * interval >= 590 * 60 and #series * interval <= 620 * 60, "covers whole session: " .. #series * interval / 60 .. "m")
assert(series[#series] > series[1], "rate trend preserved after decimation")

-- a windowed request still reads the recent ring (10s samples), not the overview
local recent, rinterval = SM:GetMetricSeries(session, "gold", 30)
eq(rinterval, 10)
assert(#recent <= 180)

-- paused sessions record nothing
local paused = { items = {}, pausedAt = clock }
SM:SampleMetricHistory(paused, { totalPerHour = 5 })
eq(paused.metricHistory, nil, "paused session untouched")
print("PASS metric history overview")
