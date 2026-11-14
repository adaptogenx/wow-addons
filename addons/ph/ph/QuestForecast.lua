--[[
    QuestForecast.lua - XP sitting in the quest log (Ready + In progress).

    Forecast only: runtime state, never persisted, never added to earned XP or the ledger.
    Not-started quests are ignored. Repeatable quests are not counted. Quests whose progress
    cannot be measured are counted as "unmeasured", never as not started.
]]

-- luacheck: globals pH_API pH_HUD C_Timer CreateFrame
local pH_QuestForecast = {}

local READY, IN_PROGRESS, NOT_STARTED, UNKNOWN = "READY", "IN_PROGRESS", "NOT_STARTED", "UNKNOWN"
local REFRESH_DELAY = 0.5

local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_ACCEPTED",
    "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "PLAYER_ENTERING_WORLD",
}

local empty = { readyXP = 0, progressXP = 0, readyCount = 0, progressCount = 0, unmeasured = 0, total = 0 }
local current = empty

-- Pure: state for one quest. `ready` is true/false/nil, `objectives` is an array or nil.
function pH_QuestForecast.Classify(ready, objectives)
    if ready == true then return READY end
    if type(objectives) ~= "table" then return UNKNOWN end
    local measurable, progressed = false, false
    for _, o in ipairs(objectives) do
        local nf, nr = o.numFulfilled, o.numRequired
        if type(nf) == "number" and type(nr) == "number" and nr > 0 then
            measurable = true
            if nf > 0 or o.finished then progressed = true end
        elseif o.finished then
            progressed = true
        end
    end
    if not measurable then return UNKNOWN end
    if ready == nil then return UNKNOWN end -- readiness unreadable: do not guess
    return progressed and IN_PROGRESS or NOT_STARTED
end

-- Pure: rows = array of { state, xp (number|nil) }. Not-started rows are ignored.
function pH_QuestForecast.Summarize(rows)
    local s = { readyXP = 0, progressXP = 0, readyCount = 0, progressCount = 0, unmeasured = 0, total = 0 }
    for _, r in ipairs(rows) do
        if r.state == READY then
            s.readyCount = s.readyCount + 1
            s.readyXP = s.readyXP + (r.xp or 0)
        elseif r.state == IN_PROGRESS then
            s.progressCount = s.progressCount + 1
            s.progressXP = s.progressXP + (r.xp or 0)
        elseif r.state == UNKNOWN then
            s.unmeasured = s.unmeasured + 1
        end
    end
    s.total = s.readyXP + s.progressXP
    return s
end

-- Pure: level thresholds against XP still needed this level.
function pH_QuestForecast.Thresholds(summary, xpNeeded)
    if not xpNeeded or xpNeeded <= 0 then
        return false, false
    end
    return summary.readyXP >= xpNeeded, summary.total >= xpNeeded
end

local function IsMaxLevel()
    return pH_API:GetPlayerLevel() >= pH_API:GetMaxPlayerLevel(70)
end

function pH_QuestForecast:Scan()
    if IsMaxLevel() then
        current = empty
        return current
    end
    local rows = {}
    local n = pH_API:GetQuestLogEntryCount() or 0
    for i = 1, n do
        local e = pH_API:GetQuestLogEntry(i)
        if e and e.questID and not e.isHeader and not e.isTask and not e.isHidden
            and pH_API:IsQuestRepeatable(e.questID) ~= true then
            local state = self.Classify(pH_API:IsQuestReady(e.questID), pH_API:GetQuestObjectives(e.questID))
            local xp
            if state == READY or state == IN_PROGRESS then
                xp = pH_API:GetQuestRewardXP(e.questID)
            end
            rows[#rows + 1] = { id = e.questID, state = state, xp = xp }
        end
    end
    current = self.Summarize(rows)
    return current
end

-- Snapshot for UI: summary plus level thresholds. Always a table.
function pH_QuestForecast:Get()
    local need = math.max(0, (pH_API:GetXPMax() or 0) - (pH_API:GetXP() or 0))
    local readyToLevel, potentialToLevel = self.Thresholds(current, need)
    return {
        readyXP = current.readyXP, progressXP = current.progressXP,
        readyCount = current.readyCount, progressCount = current.progressCount,
        unmeasured = current.unmeasured, total = current.total,
        xpNeeded = need, readyToLevel = readyToLevel, potentialToLevel = potentialToLevel,
        hasData = (current.total > 0),
    }
end

local pending = false
function pH_QuestForecast:RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, function()
        pending = false
        self:Scan()
        if type(pH_HUD) == "table" and pH_HUD.Update then
            pH_HUD:Update()
        end
    end)
end

function pH_QuestForecast:Initialize()
    if self.frame then return end
    local f = CreateFrame("Frame")
    for _, e in ipairs(EVENTS) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_QUEST_LOG_CHANGED" and unit ~= "player" then return end
        self:RequestRefresh()
    end)
    self.frame = f
    self:RequestRefresh()
end

_G.pH_QuestForecast = pH_QuestForecast
