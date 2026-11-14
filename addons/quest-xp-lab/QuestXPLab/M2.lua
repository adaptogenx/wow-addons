--[[ M2: reward XP lookup without selecting quests, plus turn-in comparison.
     GetQuestLogRewardXP(questID) is the retail form. Classic form takes no args and reads
     the SELECTED quest; if the arg is ignored every quest returns the same value, which we
     flag as ARG_IGNORED (reported as unreliable, not silently used). ]]
local _, Lab = ...

Lab.xpSeen = {}  -- value -> count, for ARG_IGNORED detection within a scan

-- Returns xp or nil, reason
function Lab.RewardXP(questID, logIndex)
    local C = Lab.Resolve("C_QuestLog.GetQuestLogRewardXP")
    local fn = C or GetQuestLogRewardXP
    if not fn then return nil, "NO_API" end
    local st, v, err = Lab.Probe(fn, questID)
    if st ~= "READABLE" then return nil, st == "ERROR" and ("ERR:" .. tostring(err):sub(1, 40)) or st end
    if type(v) ~= "number" then return nil, "TYPE:" .. type(v) end
    return v
end

local function onTurnIn(questID, xpReward, money)
    local st, xp = Lab.Probe(function() return xpReward end)
    local before = Lab.last and Lab.last.rows
    local predicted, state
    if before then
        for _, r in ipairs(before) do if r.id == questID then predicted, state = r.xp, r.state end end
    end
    Lab.pendingTurnIn = { questID = questID, eventXP = (st == "READABLE") and xp or nil, predicted = predicted, state = state, xpBefore = Lab.xpBefore }
    Lab.Log("M2", "TURN_IN q=%s eventXP=%s predicted=%s lastState=%s level=%s", tostring(questID),
        Lab.Fmt(st, xp), tostring(predicted), tostring(state), tostring(UnitLevel("player")))
end

function Lab.OnXPUpdate()
    local p = Lab.pendingTurnIn
    local st, cur = Lab.Probe(UnitXP, "player")
    if p and st == "READABLE" and Lab.xpBefore then
        local delta = cur - Lab.xpBefore
        Lab.Log("M2", "XP_DELTA q=%s actual=%d eventXP=%s predicted=%s match=%s", tostring(p.questID), delta,
            tostring(p.eventXP), tostring(p.predicted), tostring(delta == p.predicted))
        Lab.pendingTurnIn = nil
    end
    if st == "READABLE" then Lab.xpBefore = cur end
end

Lab.m2events = CreateFrame("Frame")
Lab.m2events:RegisterEvent("QUEST_TURNED_IN")
Lab.m2events:RegisterEvent("PLAYER_XP_UPDATE")
Lab.m2events:RegisterEvent("PLAYER_LOGIN")
Lab.m2events:SetScript("OnEvent", function(_, e, ...)
    if e == "QUEST_TURNED_IN" then onTurnIn(...)
    elseif e == "PLAYER_XP_UPDATE" then Lab.OnXPUpdate()
    elseif e == "PLAYER_LOGIN" then local st, c = Lab.Probe(UnitXP, "player") if st == "READABLE" then Lab.xpBefore = c end end
end)

function Lab.RunM2()
    local rows = Lab.Scan()
    local counts, n = {}, 0
    for _, r in ipairs(rows) do if r.xp then counts[r.xp] = (counts[r.xp] or 0) + 1 n = n + 1 end end
    local maxSame = 0
    for _, c in pairs(counts) do if c > maxSame then maxSame = c end end
    local ignored = n >= 3 and maxSame == n
    Lab.Log("M2", "rewards readable=%d/%d allIdentical=%s %s", n, #rows, tostring(ignored),
        ignored and "=> ARG_IGNORED suspected (classic selected-quest form)" or "")
    local lvlSeen = {}
    for _, r in ipairs(rows) do Lab.Log("M2", "q%s lvl=%s %s xp=%s why=%s", r.id, tostring(r.level), r.state, tostring(r.xp), tostring(r.xpWhy)) end
end
Lab.AddCommand("m2", "reward-XP availability check (turn-ins are compared automatically)", Lab.RunM2)
