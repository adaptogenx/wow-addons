--[[ M0: API reconnaissance. Existence + status/type of each candidate quest API. ]]
local _, Lab = ...

local PATHS = {
    "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
    "C_QuestLog.IsComplete", "C_QuestLog.ReadyForTurnIn", "C_QuestLog.GetQuestIDForLogIndex",
    "C_QuestLog.GetSelectedQuest", "C_QuestLog.IsOnQuest", "C_QuestLog.IsRepeatableQuest",
    "C_QuestLog.GetQuestLogMajorFactionReputationRewards",
    "GetQuestLogRewardXP", "GetNumQuestLogEntries", "GetQuestLogTitle",
    "GetQuestLogLeaderBoard", "GetNumQuestLeaderBoards", "GetQuestLogSelection",
    "GetQuestLogRewardMoney", "GetQuestLogRewardMoney", "UnitXP", "UnitXPMax", "UnitLevel",
}

-- First real (non-header) quest index and its questID, for probe arguments.
function Lab.FirstQuest()
    local n = Lab.NumEntries and Lab.NumEntries() or 0
    for i = 1, n do
        local e = Lab.EntryInfo(i)
        if e and e.questID and not e.isHeader then return i, e.questID end
    end
end

function Lab.RunM0()
    Lab.Log("M0", "client interface=%s project=%s", select(4, GetBuildInfo()), tostring(WOW_PROJECT_ID))
    for _, p in ipairs(PATHS) do
        local fn = Lab.Resolve(p)
        Lab.Log("M0", "%-52s %s", p, type(fn) == "function" and "EXISTS" or ("MISSING(" .. type(fn) .. ")"))
    end
    local i, qid = Lab.FirstQuest()
    if not i then Lab.Log("M0", "no quests in log; accept one and rerun") return end
    Lab.Log("M0", "probing with logIndex=%d questID=%s", i, tostring(qid))
    local function p(label, path, ...)
        local st, v, err = Lab.Probe(Lab.Resolve(path), ...)
        Lab.Log("M0", "%-44s -> %s (%s)", label, Lab.Fmt(st, v, err), type(v))
    end
    p("C_QuestLog.GetNumQuestLogEntries()", "C_QuestLog.GetNumQuestLogEntries")
    p("C_QuestLog.IsComplete(qid)", "C_QuestLog.IsComplete", qid)
    p("C_QuestLog.ReadyForTurnIn(qid)", "C_QuestLog.ReadyForTurnIn", qid)
    p("C_QuestLog.GetQuestIDForLogIndex(i)", "C_QuestLog.GetQuestIDForLogIndex", i)
    p("C_QuestLog.GetSelectedQuest()", "C_QuestLog.GetSelectedQuest")
    p("GetQuestLogRewardXP(qid)", "GetQuestLogRewardXP", qid)
    p("GetQuestLogRewardXP()  [selected-quest form]", "GetQuestLogRewardXP")
    p("C_QuestLog.GetInfo(i)", "C_QuestLog.GetInfo", i)
    local st, objs, err = Lab.Probe(Lab.Resolve("C_QuestLog.GetQuestObjectives"), qid)
    Lab.Log("M0", "GetQuestObjectives(qid) -> %s (%s)", Lab.Fmt(st, objs, err), type(objs))
    if st == "READABLE" and type(objs) == "table" then
        for k, o in ipairs(objs) do
            Lab.Log("M0", "  obj%d text=%s fulfilled=%s required=%s finished=%s type=%s", k,
                tostring(o.text), tostring(o.numFulfilled), tostring(o.numRequired),
                tostring(o.finished), tostring(o.type))
        end
    end
end
Lab.AddCommand("m0", "API reconnaissance", Lab.RunM0)
