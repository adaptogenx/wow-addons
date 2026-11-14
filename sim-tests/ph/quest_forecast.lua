-- Quest XP forecast in the real addon load: module present, scan over a stubbed quest log,
-- HUD refresh does not error. (Sim has no real quest log, so C_QuestLog is stubbed.)
test("QuestForecast loaded", function()
    assertNotNil(_G.pH_QuestForecast)
    assertNotNil(_G.pH_API.GetQuestLogEntryCount)
end)

test("scan counts Ready + In progress, ignores not started and repeatable", function()
    local quests = {
        { info = { questID = 1, title = "Ready" }, ready = true, objs = {}, xp = 480 },
        { info = { questID = 2, title = "Prog" }, ready = false, objs = { { numFulfilled = 3, numRequired = 4, finished = false } }, xp = 700 },
        { info = { questID = 3, title = "New" }, ready = false, objs = { { numFulfilled = 0, numRequired = 12, finished = false } }, xp = 625 },
        { info = { questID = 4, title = "Daily" }, ready = true, objs = {}, xp = 300, repeatable = true },
    }
    local function byId(id) for _, q in ipairs(quests) do if q.info.questID == id then return q end end end
    local saved = { C_QuestLog = _G.C_QuestLog, xp = _G.GetQuestLogRewardXP }
    _G.C_QuestLog = {
        GetNumQuestLogEntries = function() return #quests end,
        GetInfo = function(i) return quests[i].info end,
        ReadyForTurnIn = function(id) return byId(id).ready end,
        IsComplete = function(id) return byId(id).ready end,
        GetQuestObjectives = function(id) return byId(id).objs end,
        IsRepeatableQuest = function(id) return byId(id).repeatable or false end,
    }
    _G.GetQuestLogRewardXP = function(id) return byId(id).xp end
    local ok, err = pcall(function() return pH_QuestForecast:Scan() end)
    _G.C_QuestLog, _G.GetQuestLogRewardXP = saved.C_QuestLog, saved.xp
    assert(ok, tostring(err))
    local f = pH_QuestForecast:Get()
    assertEquals(480, f.readyXP)
    assertEquals(700, f.progressXP)
    assertEquals(1180, f.total)
    assertEquals(true, f.hasData)
end)

test("HUD update with forecast data does not error", function()
    local ok, err = pcall(function() pH_HUD:Update() end)
    assert(ok, tostring(err))
end)
