--[[ M4: restrictions + performance. Captures forbidden-action events, Lua errors mentioning this
     addon, selected-quest stability, scan timing in/out of combat. ]]
local _, Lab = ...

Lab.perf = { scans = 0, totalMs = 0, maxMs = 0, combatScans = 0, forbidden = 0, errors = 0 }

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:SetScript("OnEvent", function(_, e, addon, func)
    if issecretvalue and (issecretvalue(addon) or issecretvalue(func)) then addon, func = "<secret>", "<secret>" end
    if addon == "QuestXPLab" then
        Lab.perf.forbidden = Lab.perf.forbidden + 1
        Lab.Log("M4", "%s addon=%s func=%s", e, tostring(addon), tostring(func))
    end
end)

-- Wrap Scan with timing + selected-quest stability check.
local origScan = Lab.Scan
local function selected()
    local st, v = Lab.Probe(Lab.Resolve("C_QuestLog.GetSelectedQuest"))
    if st ~= "READABLE" then st, v = Lab.Probe(GetQuestLogSelection) end
    return st == "READABLE" and v or nil
end
function Lab.Scan(...)
    local before = selected()
    local rows, s = origScan(...)
    local after = selected()
    local p = Lab.perf
    p.scans, p.totalMs = p.scans + 1, p.totalMs + s.ms
    if s.ms > p.maxMs then p.maxMs = s.ms end
    if InCombatLockdown() then p.combatScans = p.combatScans + 1 end
    if before ~= after then Lab.Log("M4", "SELECTED QUEST CHANGED by scan: %s -> %s", tostring(before), tostring(after)) end
    return rows, s
end

-- Wrap addon errors: count Lua errors mentioning QuestXPLab.
local prevHandler = geterrorhandler()
seterrorhandler(function(msg)
    if type(msg) == "string" and msg:find("QuestXPLab", 1, true) then
        Lab.perf.errors = Lab.perf.errors + 1
        Lab.Log("M4", "LUA ERROR: %s", msg:sub(1, 200))
    end
    if prevHandler then return prevHandler(msg) end
end)

function Lab.RunM4()
    local p = Lab.perf
    for i = 1, 20 do Lab.Scan() end
    Lab.Log("M4", "20 rescans done. scans=%d avg=%.2fms max=%.2fms combatScans=%d quests=%d unknown=%d rewardFail=%d forbidden=%d luaErrors=%d inCombat=%s",
        p.scans, p.totalMs / math.max(1, p.scans), p.maxMs, p.combatScans, Lab.last.sum.scanned,
        Lab.last.sum.unknown, Lab.last.sum.rewardFail, p.forbidden, p.errors, tostring(InCombatLockdown()))
end
Lab.AddCommand("m4", "run 20 timed rescans + print restriction/perf counters (run once out of combat, once in)", Lab.RunM4)
