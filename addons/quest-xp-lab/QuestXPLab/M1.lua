--[[ M1: enumerate + classify quests. States: READY / IN_PROGRESS / NOT_STARTED / UNKNOWN.
     Never infers state from titles; no numeric objective => UNKNOWN (never NOT_STARTED). ]]
local _, Lab = ...

-- Number of log entries incl. headers. Returns count, source.
function Lab.NumEntries()
    local fn = Lab.Resolve("C_QuestLog.GetNumQuestLogEntries")
    if fn then
        local st, v = Lab.Probe(fn)
        if st == "READABLE" and type(v) == "number" then return v, "C_QuestLog" end
    end
    local st, v = Lab.Probe(GetNumQuestLogEntries)
    if st == "READABLE" and type(v) == "number" then return v, "classic" end
    return 0, "none"
end

-- Normalised entry: { questID, title, level, isHeader, isComplete, src }
function Lab.EntryInfo(i)
    local fn = Lab.Resolve("C_QuestLog.GetInfo")
    if fn then
        local st, t = Lab.Probe(fn, i)
        if st == "READABLE" and type(t) == "table" then
            return { questID = t.questID, title = t.title, level = t.level, isHeader = t.isHeader,
                isComplete = t.isComplete, isTask = t.isTask, isHidden = t.isHidden, src = "C_QuestLog" }
        end
        Lab.Log("M1", "C_QuestLog.GetInfo(%d) -> %s", i, Lab.Fmt(st, t))
    end
    local st, title, level, _, isHeader, _, isComplete, _, questID = Lab.Probe(GetQuestLogTitle, i)
    if st == "READABLE" then
        local r = { pcall(GetQuestLogTitle, i) }
        return { title = r[2], level = r[3], isHeader = r[5], isComplete = r[7], questID = r[9], src = "classic" }
    end
end

-- Returns state, progressText, rawObjectives
function Lab.Classify1(e)
    local ready
    local st, v = Lab.Probe(Lab.Resolve("C_QuestLog.ReadyForTurnIn"), e.questID)
    if st == "READABLE" then ready = v end
    if ready == nil then
        local st2, v2 = Lab.Probe(Lab.Resolve("C_QuestLog.IsComplete"), e.questID)
        if st2 == "READABLE" then ready = v2 end
    end
    if ready == nil and e.isComplete ~= nil and not (issecretvalue and issecretvalue(e.isComplete)) then
        ready = (e.isComplete == true or e.isComplete == 1)
    end
    if ready == true then return "READY", "done" end

    local ost, objs, err = Lab.Probe(Lab.Resolve("C_QuestLog.GetQuestObjectives"), e.questID)
    if ost ~= "READABLE" or type(objs) ~= "table" then return "UNKNOWN", "?", Lab.Fmt(ost, objs, err) end
    local measurable, any, f, r = false, false, 0, 0
    for _, o in ipairs(objs) do
        local nf, nr = o.numFulfilled, o.numRequired
        if type(nf) == "number" and type(nr) == "number" and nr > 0 then
            measurable = true
            f, r = f + nf, r + nr
            if nf > 0 or o.finished then any = true end
        elseif o.finished then any = true end
    end
    if not measurable then return "UNKNOWN", any and "finished-obj" or "?", objs end
    if any then return "IN_PROGRESS", f .. "/" .. r, objs end
    return "NOT_STARTED", f .. "/" .. r, objs
end

-- Full scan. Returns rows, summary. Uses reward from M2 (Lab.RewardXP).
function Lab.Scan()
    local t0 = debugprofilestop()
    local n, src = Lab.NumEntries()
    local rows, sum = {}, { ready = 0, prog = 0, excl = 0, unknown = 0, rewardFail = 0, scanned = 0 }
    for i = 1, n do
        local e = Lab.EntryInfo(i)
        if e and not e.isHeader and e.questID then
            sum.scanned = sum.scanned + 1
            local state, prog, raw = Lab.Classify1(e)
            local xp, why = Lab.RewardXP(e.questID, i)
            local row = { id = e.questID, title = e.title, level = e.level, state = state, progress = prog, xp = xp, xpWhy = why }
            rows[#rows + 1] = row
            if xp == nil then sum.rewardFail = sum.rewardFail + 1 end
            if state == "READY" then sum.ready = sum.ready + (xp or 0)
            elseif state == "IN_PROGRESS" then sum.prog = sum.prog + (xp or 0)
            elseif state == "NOT_STARTED" then sum.excl = sum.excl + (xp or 0)
            else sum.unknown = sum.unknown + 1 end
            if Lab.debug then Lab.Log("RAW", "q%s state=%s raw=%s", e.questID, state, type(raw) == "table" and (#raw .. " objectives") or tostring(raw)) end
        end
    end
    sum.ms = debugprofilestop() - t0
    sum.entries, sum.src = n, src
    Lab.last = { rows = rows, sum = sum }
    return rows, sum
end

function Lab.PrintScan()
    local rows, s = Lab.Scan()
    local lvl = UnitLevel("player")
    local st1, cur = Lab.Probe(UnitXP, "player")
    local st2, max = Lab.Probe(UnitXPMax, "player")
    local need = (st1 == "READABLE" and st2 == "READABLE") and (max - cur) or nil
    print(("[QuestXP] Level %s | XP needed: %s"):format(tostring(lvl), need and Lab.Comma(need) or "UNKNOWN"))
    print("ID     State         Progress    Reward")
    for _, r in ipairs(rows) do
        print(("%-6s %-13s %-11s %s"):format(tostring(r.id), r.state, tostring(r.progress),
            r.xp and Lab.Comma(r.xp) or ("UNKNOWN" .. (r.xpWhy and (" (" .. r.xpWhy .. ")") or ""))))
    end
    print(("Ready XP:          %s"):format(Lab.Comma(s.ready)))
    print(("In-progress XP:    %s"):format(Lab.Comma(s.prog)))
    print(("Excluded XP:       %s"):format(Lab.Comma(s.excl)))
    print(("Unknown quests:    %d"):format(s.unknown))
    if need then
        print(("Ready to level:    %s"):format(s.ready >= need and "YES" or "NO"))
        print(("Potential to level: %s"):format(s.ready + s.prog >= need and "YES" or "NO"))
    end
    Lab.Log("M1", "scan: entries=%d quests=%d ready=%d prog=%d excl=%d unknown=%d rewardFail=%d %.2fms",
        s.entries, s.scanned, s.ready, s.prog, s.excl, s.unknown, s.rewardFail, s.ms)
    for _, r in ipairs(rows) do
        Lab.Log("ROW", "id=%s lvl=%s %s %s xp=%s why=%s '%s'", r.id, tostring(r.level), r.state, r.progress, tostring(r.xp), tostring(r.xpWhy), tostring(r.title))
    end
    Lab.db.snapshot = {}
    for _, r in ipairs(rows) do Lab.db.snapshot[tostring(r.id)] = r.state .. "|" .. tostring(r.progress) .. "|" .. tostring(r.xp) end
end
Lab.AddCommand("scan", "scan quest log, print state/XP table", Lab.PrintScan)
Lab.AddCommand("debug", "toggle raw per-quest debug lines in log", function() Lab.debug = not Lab.debug print("QXPLab debug", Lab.debug and "on" or "off") end)
