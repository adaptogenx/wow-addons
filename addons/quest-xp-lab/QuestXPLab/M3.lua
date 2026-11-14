--[[ M3: which events fire on Forever; rescan on each; diff vs previous scan; reload persistence. ]]
local _, Lab = ...

local EVENTS = { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "QUEST_WATCH_UPDATE", "QUEST_POI_UPDATE" }
Lab.eventCounts = {}
local f = CreateFrame("Frame")
Lab.m3frame = f
Lab.watching = false
local pending

local function snapshotOf(rows)
    local t = {}
    for _, r in ipairs(rows) do t[tostring(r.id)] = r.state .. "|" .. tostring(r.progress) .. "|" .. tostring(r.xp) end
    return t
end

local function rescan(reason)
    local prev = Lab.last and snapshotOf(Lab.last.rows) or {}
    local rows, s = Lab.Scan()
    local cur = snapshotOf(rows)
    local seen, dup = {}, 0
    for _, r in ipairs(rows) do if seen[r.id] then dup = dup + 1 end seen[r.id] = true end
    local changes = 0
    for k, v in pairs(cur) do if prev[k] ~= v then changes = changes + 1 Lab.Log("M3", "  CHG q%s %s -> %s", k, tostring(prev[k]), v) end end
    for k in pairs(prev) do if cur[k] == nil then changes = changes + 1 Lab.Log("M3", "  GONE q%s (was %s)", k, prev[k]) end end
    Lab.Log("M3", "rescan(%s) quests=%d changes=%d dupRows=%d %.2fms", reason, s.scanned, changes, dup, s.ms)
end

f:SetScript("OnEvent", function(_, e, ...)
    Lab.eventCounts[e] = (Lab.eventCounts[e] or 0) + 1
    local a = { ... }
    local parts = {}
    for i = 1, select("#", ...) do
        local x = a[i]
        parts[i] = (issecretvalue and issecretvalue(x)) and "<secret>" or tostring(x)
    end
    Lab.Log("M3", "EVENT %s(%s) #%d", e, table.concat(parts, ","), Lab.eventCounts[e])
    -- throttle: one rescan per 0.5s burst, never per frame
    if not pending then
        pending = true
        C_Timer.After(0.5, function() pending = false rescan(e) end)
    end
end)

function Lab.StartWatch()
    if Lab.watching then return end
    for _, e in ipairs(EVENTS) do
        local ok = pcall(f.RegisterEvent, f, e)
        Lab.Log("M3", "register %-24s %s", e, ok and "OK" or "REJECTED")
    end
    Lab.watching = true
end

function Lab.OnLoaded()
    -- reload persistence: compare saved snapshot from before the reload with a fresh scan once the log is ready
    local prior = Lab.db.priorSnapshot
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(3, function()
            local rows = Lab.Scan()
            local cur = snapshotOf(rows)
            if prior then
                local diff = 0
                for k, v in pairs(cur) do if prior[k] ~= v then diff = diff + 1 Lab.Log("M3", "RELOAD-DIFF q%s %s -> %s", k, tostring(prior[k]), v) end end
                for k in pairs(prior) do if cur[k] == nil then diff = diff + 1 Lab.Log("M3", "RELOAD-GONE q%s", k) end end
                Lab.Log("M3", "reload persistence: %d quests, %d differences", #rows, diff)
            else
                Lab.Log("M3", "reload persistence: no prior snapshot (run /qxplab scan before /reload)")
            end
            Lab.db.snapshot = cur
        end)
    end)
    Lab.StartWatch()
end

Lab.AddCommand("m3", "print event counts seen so far (events are always watched)", function()
    for _, e in ipairs(EVENTS) do Lab.Log("M3", "count %-24s %d", e, Lab.eventCounts[e] or 0) end
end)
