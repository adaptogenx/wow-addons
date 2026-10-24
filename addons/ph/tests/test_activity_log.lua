-- Run: lua tests/test_activity_log.lua (from addons/ph). Activity feed is bounded and display-only.
local env = setmetatable({}, { __index = _G })
env._G = env
env.time = os.time
env.pH_DB_Account = { debug = { verbose = false }, meta = {}, sessions = {} }
env.pH_Settings = {}
local src = io.open("ph/SessionManager.lua"):read("a")
assert(load(src, "SessionManager", "t", env))()
local SM = env.pH_SessionManager
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

local session = { items = {} }
SM:LogActivity(session, "gold", "Looted coin", 120)
eq(#session.activityLog, 1); eq(session.activityLog[1].value, 120); eq(session.activityLog[1].kind, "gold")
SM:LogActivity(nil, "gold", "x", 1)            -- no session: ignored
SM:LogActivity(session, nil, "x", 1)           -- no kind: ignored
eq(#session.activityLog, 1)

for i = 1, 80 do SM:LogActivity(session, "xp", "n" .. i, i) end
eq(#session.activityLog, 50, "bounded to 50")
eq(session.activityLog[50].text, "n80", "newest kept")
eq(session.activityLog[1].text, "n31", "oldest dropped")

-- RecordMetricDelta logs xp/rep/honor but ignores non-positive deltas
local s2 = { metrics = {}, items = {} }
SM:RecordMetricDelta(s2, "xp", 100, 1000)
eq(s2.activityLog and #s2.activityLog or 0, 1); eq(s2.activityLog[1].kind, "xp")
SM:RecordMetricDelta(s2, "xp", 0, 1000)
eq(#s2.activityLog, 1)
print("PASS activity log")
