-- Run: lua tests/test_quest_forecast.lua (from addons/ph). Classification, summary, thresholds, scan.
local timers = {}
local entries, state = {}, { level = 30, xp = 1000, xpMax = 5000 }
local env = setmetatable({}, { __index = _G })
env._G = env
env.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
env.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
env.pH_API = {
    GetPlayerLevel = function() return state.level end,
    GetMaxPlayerLevel = function() return 70 end,
    GetXP = function() return state.xp end,
    GetXPMax = function() return state.xpMax end,
    GetQuestLogEntryCount = function() return #entries end,
    GetQuestLogEntry = function(_, i) return entries[i].info end,
    IsQuestReady = function(_, id) for _, e in ipairs(entries) do if e.info.questID == id then return e.ready end end end,
    GetQuestObjectives = function(_, id) for _, e in ipairs(entries) do if e.info.questID == id then return e.objs end end end,
    IsQuestRepeatable = function(_, id) for _, e in ipairs(entries) do if e.info.questID == id then return e.repeatable end end end,
    GetQuestRewardXP = function(_, id) for _, e in ipairs(entries) do if e.info.questID == id then return e.xp end end end,
}
assert(load(io.open("ph/QuestForecast.lua"):read("a"), "QuestForecast", "t", env))()
local Q = env.pH_QuestForecast
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end
local function obj(f, r, fin) return { numFulfilled = f, numRequired = r, finished = fin or false } end

-- Classify
eq(Q.Classify(true, {}), "READY")
eq(Q.Classify(true, nil), "READY", "ready wins even with unreadable objectives")
eq(Q.Classify(false, { obj(0, 10) }), "NOT_STARTED")
eq(Q.Classify(false, { obj(3, 10) }), "IN_PROGRESS")
eq(Q.Classify(false, { obj(0, 8), obj(1, 3) }), "IN_PROGRESS", "multi-objective, one progressing")
eq(Q.Classify(false, { obj(0, 5, true) }), "IN_PROGRESS", "finished objective")
eq(Q.Classify(false, {}), "UNKNOWN", "no objectives is never not-started")
eq(Q.Classify(false, { { finished = false } }), "UNKNOWN", "no numeric objective")
eq(Q.Classify(false, nil), "UNKNOWN", "unreadable objectives")
eq(Q.Classify(nil, { obj(0, 10) }), "UNKNOWN", "unreadable readiness")

-- Summarize: not-started ignored, nil xp counts as 0, unknown counted separately
local s = Q.Summarize({
    { state = "READY", xp = 480 }, { state = "READY", xp = nil }, { state = "IN_PROGRESS", xp = 700 },
    { state = "NOT_STARTED", xp = 9999 }, { state = "UNKNOWN", xp = nil },
})
eq(s.readyXP, 480); eq(s.progressXP, 700); eq(s.total, 1180)
eq(s.readyCount, 2); eq(s.progressCount, 1); eq(s.unmeasured, 1)

-- Thresholds
local r, p = Q.Thresholds({ readyXP = 4000, total = 4000 }, 4000); eq(r, true); eq(p, true)
r, p = Q.Thresholds({ readyXP = 3999, total = 4500 }, 4000); eq(r, false); eq(p, true)
r, p = Q.Thresholds({ readyXP = 100, total = 200 }, 4000); eq(r, false); eq(p, false)
r, p = Q.Thresholds({ readyXP = 100, total = 200 }, 0); eq(r, false, "xpNeeded 0 -> no claim")

-- Scan: headers/tasks/hidden/repeatable skipped, not-started excluded from totals
local function q(id, ready, objs, xp, extra)
    local info = { questID = id, isHeader = false }
    for k, v in pairs(extra or {}) do info[k] = v end
    return { info = info, ready = ready, objs = objs, xp = xp, repeatable = extra and extra.repeatable or false }
end
entries = {
    { info = { isHeader = true, title = "Zone" } },
    q(1, true, {}, 480),
    q(2, false, { obj(3, 4) }, 700),
    q(3, false, { obj(0, 12) }, 625),
    q(4, true, {}, 300, { repeatable = true }),
    q(5, false, {}, 200),
    q(6, true, {}, 999, { isTask = true }),
}
local sum = Q:Scan()
eq(sum.readyXP, 480); eq(sum.progressXP, 700); eq(sum.total, 1180); eq(sum.unmeasured, 1)
local f = Q:Get()
eq(f.xpNeeded, 4000); eq(f.readyToLevel, false); eq(f.potentialToLevel, false); eq(f.hasData, true)

state.xp = 4900 -- 100 left: ready quests (480) now level the character
f = Q:Get(); eq(f.readyToLevel, true); eq(f.potentialToLevel, true)

-- Max level: forecast cleared
state.level = 70
Q:Scan(); eq(Q:Get().hasData, false)
state.level = 30

-- Debounce: many requests -> one scan
timers = {}
for _ = 1, 10 do Q:RequestRefresh() end
eq(#timers, 1, "debounced to one timer")
timers[1]()
Q:RequestRefresh(); eq(#timers, 2, "new request allowed after the timer fires")
print("quest forecast tests: ok")
