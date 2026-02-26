--[[
    SessionManager.lua - Session lifecycle management for pH

    Handles session creation, persistence, and metrics computation.
]]

-- luacheck: globals GetMaxPlayerLevel UnitLevel UnitXP UnitXPMax UnitClass pH_DB_Account pH_Settings UnitName GetRealmName UnitFactionGroup pH_AutoSession pH_RepTurninCatalog GetNumFactions GetFactionInfo

local pH_SessionManager = {}
local DEFAULT_SHORT_SESSION_SEC = 300
local HISTORY_UNDO_WINDOW_SEC = 30
local HISTORY_UNDO_MAX = 20
local RATE_BUCKET_SIZE_SEC = 30
local RATE_BUCKET_MAX = 6

--------------------------------------------------
-- Owner identity (session belongs to current character)
--------------------------------------------------
local function SessionOwnedByCurrentPlayer(session)
    if not session or not session.character then
        return false
    end
    local char = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    local faction = UnitFactionGroup("player") or "Unknown"
    return session.character == char and session.realm == realm and session.faction == faction
end

local function GetSessionCharKey(session)
    if not session then
        return "Unknown-Unknown-Unknown"
    end
    local character = session.character or "Unknown"
    local realm = session.realm or "Unknown"
    local faction = session.faction or "Unknown"
    return character .. "-" .. realm .. "-" .. faction
end

local function GetCurrentCharKey()
    local character = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    local faction = UnitFactionGroup("player") or "Unknown"
    return character .. "-" .. realm .. "-" .. faction
end

local function EnsureActiveSessions()
    if not pH_DB_Account.activeSessions then
        pH_DB_Account.activeSessions = {}
    end
    return pH_DB_Account.activeSessions
end

local function IsSessionActiveAnywhere(sessionId)
    if not sessionId then
        return false
    end
    local activeSessions = EnsureActiveSessions()
    for _, active in pairs(activeSessions) do
        if active and tonumber(active.id) == tonumber(sessionId) then
            return true
        end
    end
    return false
end

local function ResolveSessionStorageKey(sessionId)
    if pH_DB_Account.sessions[sessionId] ~= nil then
        return sessionId
    end
    if type(sessionId) == "number" and pH_DB_Account.sessions[tostring(sessionId)] ~= nil then
        return tostring(sessionId)
    end
    if type(sessionId) == "string" then
        local asNum = tonumber(sessionId)
        if asNum and pH_DB_Account.sessions[asNum] ~= nil then
            return asNum
        end
    end
    return sessionId
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local result = {}
    seen[value] = result
    for k, v in pairs(value) do
        result[DeepCopy(k, seen)] = DeepCopy(v, seen)
    end
    return result
end

local function EnsureHistoryUndo()
    if not pH_DB_Account.meta then
        pH_DB_Account.meta = { lastSessionId = 0 }
    end
    if not pH_DB_Account.meta.historyUndo then
        pH_DB_Account.meta.historyUndo = {
            stack = {},
            maxEntries = HISTORY_UNDO_MAX,
        }
    end
    local hu = pH_DB_Account.meta.historyUndo
    if not hu.stack then
        hu.stack = {}
    end
    if not hu.maxEntries or hu.maxEntries < 1 then
        hu.maxEntries = HISTORY_UNDO_MAX
    end
    return hu
end

local function MarkIndexStale()
    if pH_Index then
        pH_Index:MarkStale()
    end
end

local function PushUndoEntry(entry)
    local hu = EnsureHistoryUndo()
    entry.expiresAt = time() + HISTORY_UNDO_WINDOW_SEC
    table.insert(hu.stack, entry)
    while #hu.stack > hu.maxEntries do
        table.remove(hu.stack, 1)
    end
end

local function PopValidUndoEntry()
    local hu = EnsureHistoryUndo()
    local now = time()
    while #hu.stack > 0 do
        local entry = hu.stack[#hu.stack]
        table.remove(hu.stack, #hu.stack)
        if entry and entry.expiresAt and entry.expiresAt >= now then
            return entry
        end
    end
    return nil
end

-- Start a new session
function pH_SessionManager:StartSession(startReason, startSource)
    if self:GetActiveSession() then
        return false, "A session is already active. Stop it first with /goldph stop"
    end

    -- Increment session ID
    pH_DB_Account.meta.lastSessionId = pH_DB_Account.meta.lastSessionId + 1
    local sessionId = pH_DB_Account.meta.lastSessionId

    local now = time()

    -- Character class metadata (stored per-session; fallback for old sessions when displaying)
    local className
    if UnitClass then
        -- UnitClass returns localizedName, classToken, classID (varies slightly by client)
        local localizedName = UnitClass("player")
        if type(localizedName) == "string" and localizedName ~= "" then
            className = localizedName
        end
    end

    -- Create new session
    local session = {
        id = sessionId,
        startedAt = now,
        endedAt = nil,
        durationSec = 0,

        -- Phase 7: Accurate duration across logins
        accumulatedDuration = 0,  -- Total in-game seconds played this session
        currentLoginAt = now,     -- Timestamp of current login segment (nil when logged out)
        pausedAt = nil,           -- When set, session is paused (clock and events frozen)
        autoSessionPauseReason = nil,

        zone = GetZoneText() or "Unknown",

        -- Character attribution (for cross-character history filter)
        character = UnitName("player") or "Unknown",
        realm = GetRealmName() or "Unknown",
        faction = UnitFactionGroup("player") or "Unknown",
        class = className or "Unknown",

        -- Phase 3: Item tracking
        items = {},      -- [itemID] = ItemAgg (count, expected value, etc.)
        holdings = {},   -- [itemID] = { count, lots = { Lot, ... } }

        -- Phase 6: Pickpocket tracking
        pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        },

        -- Phase 6 / 7: Gathering nodes (per-session counts)
        gathering = {
            totalNodes = 0,
            nodesByType = {},
        },

        -- Phase 9: XP/Rep/Honor metrics
        metrics = {
            xp = { gained = 0, enabled = false },
            rep = { gained = 0, enabled = false, byFaction = {} },
            repPotential = {
                total = 0, byFaction = {}, byItem = {},
                eligibleTotal = 0, theoreticalTotal = 0,
                eligibleByFaction = {}, theoreticalByFaction = {},
            },
            honor = { gained = 0, enabled = false, kills = 0 },
            recentBuckets = {},
            recentBucketLastTotals = {},
        },

        -- Phase 9: Snapshots for delta computation
        snapshots = {
            xp = { cur = 0, max = 0 },
            rep = { byFactionID = {} },
        },

        archived = false,
        archivedAt = nil,
        archivedReason = nil,
    }

    -- Initialize ledger
    pH_Ledger:InitializeLedger(session)

    -- Initialize XP tracking (if not max level)
    -- GetMaxPlayerLevel() or fallback to 60 for Classic
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    if UnitLevel("player") < maxLevel then
        session.snapshots.xp.cur = UnitXP("player")
        session.snapshots.xp.max = UnitXPMax("player")
    end

    -- Initialize reputation tracking (via Events.lua after session created)

    -- Set as active session for the current character
    local activeSessions = EnsureActiveSessions()
    activeSessions[GetCurrentCharKey()] = session

    -- Verbose debug: log initial duration tracking state
    if pH_DB_Account.debug.verbose then
        local dateStr
        if date then
            dateStr = date("%Y-%m-%d %H:%M:%S", session.startedAt)
        else
            dateStr = tostring(session.startedAt)
        end
        print(string.format(
            "[pH Debug] Session #%d started at %s | accumulatedDuration=%d | currentLoginAt=%s",
            sessionId,
            dateStr,
            session.accumulatedDuration or 0,
            tostring(session.currentLoginAt)
        ))
    end

    if type(pH_AutoSession) == "table" and pH_AutoSession.OnSessionStarted then
        pH_AutoSession:OnSessionStarted(session, startReason or "manual", startSource)
    end

    return true, "Session #" .. sessionId .. " started"
end

-- Stop the active session (only for current character's session)
function pH_SessionManager:StopSession()
    local session = self:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    local now = time()

    -- Fold any active login segment into the accumulator
    if session.currentLoginAt then
        session.accumulatedDuration = session.accumulatedDuration + (now - session.currentLoginAt)
        session.currentLoginAt = nil
    end

    -- Finalize session
    session.endedAt = now
    session.durationSec = session.accumulatedDuration

    -- Save to history
    pH_DB_Account.sessions[session.id] = session

    -- Clear active session for current character only
    local activeSessions = EnsureActiveSessions()
    activeSessions[GetCurrentCharKey()] = nil

    if type(pH_AutoSession) == "table" and pH_AutoSession.OnSessionStopped then
        pH_AutoSession:OnSessionStopped(session)
    end

    -- Mark index stale for rebuild
    if pH_Index then
        pH_Index:MarkStale()
    end

    return true, "Session #" .. session.id .. " stopped and saved (duration: " ..
                 self:FormatDuration(session.durationSec) .. ")"
end

function pH_SessionManager:PersistOrphanedActiveSession()
    -- No-op with per-character active sessions.
    return
end

-- Get the active session for the current character only (or nil if none or owned by another character)
function pH_SessionManager:GetActiveSession()
    local activeSessions = EnsureActiveSessions()
    local session = activeSessions[GetCurrentCharKey()]
    if not session then
        return nil
    end
    if not SessionOwnedByCurrentPlayer(session) then
        return nil
    end
    return session
end

function pH_SessionManager:GetShortSessionThresholdSec()
    if pH_Settings and pH_Settings.historyCleanup and pH_Settings.historyCleanup.shortThresholdSec then
        return pH_Settings.historyCleanup.shortThresholdSec
    end
    return DEFAULT_SHORT_SESSION_SEC
end

function pH_SessionManager:IsShortSession(session, thresholdSec)
    if not session then return false end
    local threshold = thresholdSec or self:GetShortSessionThresholdSec()
    local metrics = self:GetMetrics(session)
    local duration = metrics and metrics.durationSec or session.durationSec or 0
    return duration < threshold
end

function pH_SessionManager:SetSessionArchived(sessionId, archived, reason)
    local storageKey = ResolveSessionStorageKey(sessionId)
    local session = self:GetSession(storageKey)
    if not session then
        return false, "Session not found"
    end
    if IsSessionActiveAnywhere(sessionId) then
        return false, "Cannot archive active session"
    end

    local previous = {
        archived = session.archived or false,
        archivedAt = session.archivedAt,
        archivedReason = session.archivedReason,
    }

    session.archived = archived and true or false
    if session.archived then
        session.archivedAt = time()
        session.archivedReason = reason or "manual"
    else
        session.archivedAt = nil
        session.archivedReason = nil
    end

    PushUndoEntry({
        type = "archive_state",
        sessionId = storageKey,
        previous = previous,
        next = {
            archived = session.archived,
            archivedAt = session.archivedAt,
            archivedReason = session.archivedReason,
        },
    })

    MarkIndexStale()

    local msg = archived and "archived" or "unarchived"
    return true, string.format("Session #%s %s", tostring(storageKey), msg), HISTORY_UNDO_WINDOW_SEC
end

function pH_SessionManager:ArchiveShortSessions(thresholdSec)
    local threshold = thresholdSec or self:GetShortSessionThresholdSec()
    local changed = {}

    for sessionId, session in pairs(pH_DB_Account.sessions) do
        if session and not session.archived and self:IsShortSession(session, threshold) then
            table.insert(changed, {
                sessionId = sessionId,
                previous = {
                    archived = session.archived or false,
                    archivedAt = session.archivedAt,
                    archivedReason = session.archivedReason,
                }
            })
            session.archived = true
            session.archivedAt = time()
            session.archivedReason = "auto-short"
        end
    end

    if #changed == 0 then
        return true, "No short sessions to archive", nil
    end

    PushUndoEntry({
        type = "archive_bulk_short",
        thresholdSec = threshold,
        changed = changed,
    })

    MarkIndexStale()
    return true, string.format("Archived %d short session(s) under %d minutes", #changed, math.floor(threshold / 60)), HISTORY_UNDO_WINDOW_SEC
end

function pH_SessionManager:DeleteSession(sessionId)
    local storageKey = ResolveSessionStorageKey(sessionId)
    local session = self:GetSession(storageKey)
    if not session then
        return false, "Session not found"
    end
    if IsSessionActiveAnywhere(sessionId) then
        return false, "Cannot delete active session"
    end

    local snapshot = DeepCopy(session)
    pH_DB_Account.sessions[storageKey] = nil

    PushUndoEntry({
        type = "delete_session",
        sessionId = storageKey,
        session = snapshot,
    })

    MarkIndexStale()
    return true, string.format("Session #%s deleted", tostring(storageKey)), HISTORY_UNDO_WINDOW_SEC
end

function pH_SessionManager:MergeSessions(sessionIds)
    if type(sessionIds) ~= "table" or #sessionIds < 2 then
        return false, "Need at least two session IDs to merge"
    end

    local unique = {}
    local sourceSessions = {}
    for _, id in ipairs(sessionIds) do
        local storageKey = ResolveSessionStorageKey(id)
        if not unique[storageKey] then
            unique[storageKey] = true
            local session = self:GetSession(storageKey)
            if not session then
                return false, string.format("Session #%s not found", tostring(id))
            end
            if IsSessionActiveAnywhere(id) then
                return false, "Cannot merge active session"
            end
            if session.archived then
                return false, string.format("Session #%s is archived; unarchive first", tostring(id))
            end
            table.insert(sourceSessions, { id = storageKey, session = session })
        end
    end

    if #sourceSessions < 2 then
        return false, "Need at least two unique sessions to merge"
    end

    local charKey = GetSessionCharKey(sourceSessions[1].session)
    for i = 2, #sourceSessions do
        if GetSessionCharKey(sourceSessions[i].session) ~= charKey then
            return false, "Merge blocked: sessions must belong to the same character"
        end
    end

    table.sort(sourceSessions, function(a, b)
        return (a.session.startedAt or 0) < (b.session.startedAt or 0)
    end)

    pH_DB_Account.meta.lastSessionId = (pH_DB_Account.meta.lastSessionId or 0) + 1
    local mergedId = pH_DB_Account.meta.lastSessionId

    local now = time()
    local first = sourceSessions[1].session
    local merged = {
        id = mergedId,
        startedAt = first.startedAt,
        endedAt = first.endedAt,
        durationSec = 0,
        accumulatedDuration = 0,
        currentLoginAt = nil,
        pausedAt = nil,
        zone = first.zone or "Merged",
        character = first.character or "Unknown",
        realm = first.realm or "Unknown",
        faction = first.faction or "Unknown",
        class = first.class or "Unknown",
        items = {},
        holdings = {},
        pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        },
        gathering = {
            totalNodes = 0,
            nodesByType = {},
        },
        metrics = {
            xp = { gained = 0, enabled = false },
            rep = { gained = 0, enabled = false, byFaction = {} },
            repPotential = {
                total = 0, byFaction = {}, byItem = {},
                eligibleTotal = 0, theoreticalTotal = 0,
                eligibleByFaction = {}, theoreticalByFaction = {},
            },
            honor = { gained = 0, enabled = false, kills = 0 },
            recentBuckets = {},
            recentBucketLastTotals = {},
        },
        snapshots = {
            xp = { cur = 0, max = 0 },
            rep = { byFactionID = {} },
        },
        mergedFrom = {},
        mergedAt = now,
    }
    pH_Ledger:InitializeLedger(merged)

    local function addBalanceMap(target, source)
        for k, v in pairs(source or {}) do
            target[k] = (target[k] or 0) + (v or 0)
        end
    end

    for _, src in ipairs(sourceSessions) do
        local s = src.session
        table.insert(merged.mergedFrom, src.id)
        merged.startedAt = math.min(merged.startedAt or s.startedAt or now, s.startedAt or now)
        merged.endedAt = math.max(merged.endedAt or s.endedAt or 0, s.endedAt or s.startedAt or 0)

        local metrics = self:GetMetrics(s)
        local dur = metrics and metrics.durationSec or s.durationSec or 0
        merged.durationSec = merged.durationSec + dur
        merged.accumulatedDuration = merged.durationSec

        addBalanceMap(merged.ledger.balances, s.ledger and s.ledger.balances or nil)

        for itemID, itemData in pairs(s.items or {}) do
            if not merged.items[itemID] then
                merged.items[itemID] = DeepCopy(itemData)
            else
                local dst = merged.items[itemID]
                dst.count = (dst.count or 0) + (itemData.count or 0)
                dst.countLooted = (dst.countLooted or 0) + (itemData.countLooted or 0)
                dst.expectedTotal = (dst.expectedTotal or 0) + (itemData.expectedTotal or 0)
            end
        end

        for itemID, holding in pairs(s.holdings or {}) do
            if not merged.holdings[itemID] then
                merged.holdings[itemID] = { count = 0, lots = {} }
            end
            merged.holdings[itemID].count = merged.holdings[itemID].count + (holding.count or 0)
            for _, lot in ipairs(holding.lots or {}) do
                table.insert(merged.holdings[itemID].lots, DeepCopy(lot))
            end
        end

        local sp = s.pickpocket or {}
        merged.pickpocket.gold = merged.pickpocket.gold + (sp.gold or 0)
        merged.pickpocket.value = merged.pickpocket.value + (sp.value or 0)
        merged.pickpocket.lockboxesLooted = merged.pickpocket.lockboxesLooted + (sp.lockboxesLooted or 0)
        merged.pickpocket.lockboxesOpened = merged.pickpocket.lockboxesOpened + (sp.lockboxesOpened or 0)
        if sp.fromLockbox then
            merged.pickpocket.fromLockbox.gold = merged.pickpocket.fromLockbox.gold + (sp.fromLockbox.gold or 0)
            merged.pickpocket.fromLockbox.value = merged.pickpocket.fromLockbox.value + (sp.fromLockbox.value or 0)
        end

        local sg = s.gathering or {}
        merged.gathering.totalNodes = merged.gathering.totalNodes + (sg.totalNodes or 0)
        for nodeName, count in pairs(sg.nodesByType or {}) do
            merged.gathering.nodesByType[nodeName] = (merged.gathering.nodesByType[nodeName] or 0) + count
        end

        if s.metrics then
            local mxp = s.metrics.xp or {}
            merged.metrics.xp.gained = merged.metrics.xp.gained + (mxp.gained or 0)
            merged.metrics.xp.enabled = merged.metrics.xp.enabled or (mxp.enabled and true or false)

            local mr = s.metrics.rep or {}
            merged.metrics.rep.gained = merged.metrics.rep.gained + (mr.gained or 0)
            merged.metrics.rep.enabled = merged.metrics.rep.enabled or (mr.enabled and true or false)
            for factionName, gain in pairs(mr.byFaction or {}) do
                merged.metrics.rep.byFaction[factionName] = (merged.metrics.rep.byFaction[factionName] or 0) + gain
            end

            local mrp = s.metrics.repPotential or {}
            merged.metrics.repPotential.total = (merged.metrics.repPotential.total or 0) + (mrp.total or 0)
            for factionName, value in pairs(mrp.byFaction or {}) do
                merged.metrics.repPotential.byFaction[factionName] = (merged.metrics.repPotential.byFaction[factionName] or 0) + value
            end

            local mh = s.metrics.honor or {}
            merged.metrics.honor.gained = merged.metrics.honor.gained + (mh.gained or 0)
            merged.metrics.honor.enabled = merged.metrics.honor.enabled or (mh.enabled and true or false)
            merged.metrics.honor.kills = merged.metrics.honor.kills + (mh.kills or 0)
        end
    end

    merged.archived = false
    merged.archivedAt = nil
    merged.archivedReason = nil

    -- Recompute rep potential from merged item counts using current rules.
    self:RecomputeRepPotentialForSession(merged)

    local removedSnapshots = {}
    for _, src in ipairs(sourceSessions) do
        removedSnapshots[src.id] = DeepCopy(src.session)
        pH_DB_Account.sessions[src.id] = nil
    end
    pH_DB_Account.sessions[mergedId] = merged

    PushUndoEntry({
        type = "merge_sessions",
        mergedSessionId = mergedId,
        mergedSession = DeepCopy(merged),
        sourceSessions = removedSnapshots,
    })

    MarkIndexStale()
    return true, string.format("Merged %d sessions into #%d", #sourceSessions, mergedId), HISTORY_UNDO_WINDOW_SEC
end

function pH_SessionManager:UndoLastHistoryAction()
    local entry = PopValidUndoEntry()
    if not entry then
        return false, "Nothing to undo (or undo window expired)"
    end

    if entry.type == "archive_state" then
        local session = self:GetSession(entry.sessionId)
        if not session then
            return false, "Undo failed: session not found"
        end
        session.archived = entry.previous.archived and true or false
        session.archivedAt = entry.previous.archivedAt
        session.archivedReason = entry.previous.archivedReason
        MarkIndexStale()
        return true, string.format("Undo complete for session #%s", tostring(entry.sessionId))
    end

    if entry.type == "archive_bulk_short" then
        local restored = 0
        for _, item in ipairs(entry.changed or {}) do
            local session = self:GetSession(item.sessionId)
            if session then
                session.archived = item.previous.archived and true or false
                session.archivedAt = item.previous.archivedAt
                session.archivedReason = item.previous.archivedReason
                restored = restored + 1
            end
        end
        MarkIndexStale()
        return true, string.format("Undo complete for %d session(s)", restored)
    end

    if entry.type == "delete_session" then
        local id = entry.sessionId
        if pH_DB_Account.sessions[id] then
            pH_DB_Account.meta.lastSessionId = (pH_DB_Account.meta.lastSessionId or 0) + 1
            local newId = pH_DB_Account.meta.lastSessionId
            local restored = DeepCopy(entry.session)
            restored.id = newId
            pH_DB_Account.sessions[newId] = restored
            MarkIndexStale()
            return true, string.format("Undo restored deleted session as #%d", newId)
        end
        pH_DB_Account.sessions[id] = DeepCopy(entry.session)
        MarkIndexStale()
        return true, string.format("Undo restored session #%s", tostring(id))
    end

    if entry.type == "merge_sessions" then
        pH_DB_Account.sessions[entry.mergedSessionId] = nil
        for id, session in pairs(entry.sourceSessions or {}) do
            pH_DB_Account.sessions[id] = DeepCopy(session)
        end
        MarkIndexStale()
        return true, "Undo restored pre-merge sessions"
    end

    return false, "Undo failed: unknown action type"
end

-- Return true if the session is paused (clock and events frozen)
function pH_SessionManager:IsPaused(session)
    return session and session.pausedAt ~= nil
end

-- Pause the active session (stop clock and do not record events until resumed)
function pH_SessionManager:PauseSession(pauseReason, pauseSource)
    local session = self:GetActiveSession()
    if not session then
        return false, "No active session"
    end
    if session.pausedAt then
        return false, "Session is already paused"
    end
    local now = time()
    if session.currentLoginAt then
        session.accumulatedDuration = session.accumulatedDuration + (now - session.currentLoginAt)
        session.currentLoginAt = nil
    end
    session.pausedAt = now
    session.autoSessionPauseReason = pauseReason or "manual"
    if type(pH_AutoSession) == "table" and pH_AutoSession.OnSessionPaused then
        pH_AutoSession:OnSessionPaused(session, session.autoSessionPauseReason, pauseSource)
    end
    return true, "Session paused"
end

-- Resume a paused session
function pH_SessionManager:ResumeSession(resumeReason, resumeSource)
    local session = self:GetActiveSession()
    if not session then
        return false, "No active session"
    end
    if not session.pausedAt then
        return false, "Session is not paused"
    end
    session.pausedAt = nil
    session.autoSessionPauseReason = nil
    session.currentLoginAt = time()
    if type(pH_AutoSession) == "table" and pH_AutoSession.OnSessionResumed then
        pH_AutoSession:OnSessionResumed(session, resumeReason or "manual", resumeSource)
    end
    return true, "Session resumed"
end

local STANDING_TO_ID = {
    hated = 1,
    hostile = 2,
    unfriendly = 3,
    neutral = 4,
    friendly = 5,
    honored = 6,
    revered = 7,
    exalted = 8,
}

local function NormalizeFactionKey(value)
    if not value then
        return nil
    end
    local s = string.lower(tostring(value))
    s = s:gsub("[^%w%s']", " ")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^the ", "")
    return s
end

local function ToStandingID(value)
    if value == nil then
        return nil
    end
    if type(value) == "number" then
        return value
    end
    local key = NormalizeFactionKey(value)
    return key and STANDING_TO_ID[key] or nil
end

local function BuildFactionStandingMap()
    local map = {}
    local count = GetNumFactions and GetNumFactions() or 0
    for i = 1, count do
        local name, _, standingID, _, _, _, _, _, isHeader = GetFactionInfo(i)
        if not isHeader and name and standingID then
            map[NormalizeFactionKey(name)] = standingID
        end
    end
    return map
end

local function IsStandingEligible(rule, standingID)
    if not rule then
        return false
    end
    if standingID == nil then
        return false
    end
    local minStandingID = ToStandingID(rule.minStanding) or 1
    local maxStandingID = ToStandingID(rule.maxStanding) or 8
    return standingID >= minStandingID and standingID <= maxStandingID
end

local function BuildRepPotentialEntry(itemID, itemName, count, rules, standingByFaction)
    if not rules or #rules == 0 then
        return nil
    end
    local entry = {
        count = count,
        bundleSize = math.max(1, tonumber(rules[1].bundleSize) or 1),
        repPerBundle = math.max(0, tonumber(rules[1].repPerBundle) or 0),
        potentialRep = 0,   -- Backward compatibility alias for eligibleRep
        eligibleRep = 0,
        theoreticalRep = 0,
        isApprox = false,
        factionKey = rules[1].factionKey or "Unknown",
        targets = {},
    }

    for _, rule in ipairs(rules) do
        local bundleSize = math.max(1, tonumber(rule.bundleSize) or 1)
        local repPerBundle = math.max(0, tonumber(rule.repPerBundle) or 0)
        local theoreticalRep = math.floor((count / bundleSize) * repPerBundle)
        local standingID = standingByFaction[NormalizeFactionKey(rule.factionKey)]
        local eligibleRep = IsStandingEligible(rule, standingID) and theoreticalRep or 0
        local isApprox = (count % bundleSize) ~= 0
        table.insert(entry.targets, {
            factionKey = rule.factionKey or "Unknown",
            bundleSize = bundleSize,
            repPerBundle = repPerBundle,
            theoreticalRep = theoreticalRep,
            eligibleRep = eligibleRep,
            isApprox = isApprox,
            standingID = standingID,
            minStanding = rule.minStanding,
            maxStanding = rule.maxStanding,
            turninNpc = rule.turninNpc,
            turninZone = rule.turninZone,
            turninMethod = rule.turninMethod,
            repeatable = rule.repeatable and true or false,
        })
        entry.theoreticalRep = entry.theoreticalRep + theoreticalRep
        entry.eligibleRep = entry.eligibleRep + eligibleRep
        entry.isApprox = entry.isApprox or isApprox
    end

    entry.potentialRep = entry.eligibleRep
    return entry
end

local function BuildRepPotentialItems(session)
    local out = {}
    local repPotential = session and session.metrics and session.metrics.repPotential or nil
    local byItem = repPotential and repPotential.byItem or nil
    if not byItem then
        return out
    end

    for itemID, entry in pairs(byItem) do
        local count = math.max(0, tonumber(entry.count) or 0)
        local bundleSize = math.max(1, tonumber(entry.bundleSize) or 1)
        local repPerBundle = math.max(0, tonumber(entry.repPerBundle) or 0)
        if count > 0 then
            local progressCount = count % bundleSize
            local neededForNext = (progressCount == 0) and 0 or (bundleSize - progressCount)
            local itemName = (session.items and session.items[itemID] and session.items[itemID].name) or GetItemInfo(itemID) or ("Item " .. tostring(itemID))
            local firstTarget = entry.targets and entry.targets[1] or nil
            table.insert(out, {
                itemID = itemID,
                itemName = itemName,
                count = count,
                bundleSize = bundleSize,
                repPerBundle = repPerBundle,
                potentialRep = math.max(0, tonumber(entry.potentialRep) or 0),
                eligibleRep = math.max(0, tonumber(entry.eligibleRep) or 0),
                theoreticalRep = math.max(0, tonumber(entry.theoreticalRep) or 0),
                factionKey = entry.factionKey or (firstTarget and firstTarget.factionKey) or "Unknown",
                progressCount = progressCount,
                neededForNext = neededForNext,
                turninNpc = (firstTarget and firstTarget.turninNpc) or nil,
                turninZone = (firstTarget and firstTarget.turninZone) or nil,
                turninMethod = (firstTarget and firstTarget.turninMethod) or nil,
                repeatable = (firstTarget and firstTarget.repeatable) and true or false,
                isApprox = entry.isApprox and true or false,
                targets = entry.targets or {},
            })
        end
    end

    table.sort(out, function(a, b)
        local ae = a.eligibleRep or a.potentialRep or 0
        local be = b.eligibleRep or b.potentialRep or 0
        if ae == be then
            local at = a.theoreticalRep or 0
            local bt = b.theoreticalRep or 0
            if at == bt then
                return (a.count or 0) > (b.count or 0)
            end
            return at > bt
        end
        return ae > be
    end)

    return out
end

function pH_SessionManager:EnsureRecentBucketsDefaults(session)
    if not session then return end
    if not session.metrics then
        session.metrics = {}
    end
    if type(session.metrics.recentBuckets) ~= "table" then
        session.metrics.recentBuckets = {}
    end
    if type(session.metrics.recentBucketLastTotals) ~= "table" then
        session.metrics.recentBucketLastTotals = {}
    end
    local keys = { "gold", "xp", "rep", "honor" }
    for i = 1, #keys do
        local key = keys[i]
        if type(session.metrics.recentBuckets[key]) ~= "table" then
            session.metrics.recentBuckets[key] = {
                bucketSizeSec = RATE_BUCKET_SIZE_SEC,
                maxBuckets = RATE_BUCKET_MAX,
                buckets = {},
            }
        else
            local bucket = session.metrics.recentBuckets[key]
            if type(bucket.buckets) ~= "table" then
                bucket.buckets = {}
            end
            bucket.bucketSizeSec = bucket.bucketSizeSec or RATE_BUCKET_SIZE_SEC
            bucket.maxBuckets = bucket.maxBuckets or RATE_BUCKET_MAX
        end
    end
end

function pH_SessionManager:RecordMetricDelta(session, metricKey, delta, atTime)
    if not session or not metricKey then return end
    self:EnsureRecentBucketsDefaults(session)
    local bucketState = session.metrics.recentBuckets[metricKey]
    if not bucketState then return end

    local value = tonumber(delta) or 0
    if value <= 0 then
        return
    end

    local at = math.floor(tonumber(atTime) or time())
    local size = bucketState.bucketSizeSec or RATE_BUCKET_SIZE_SEC
    local bucketStart = at - (at % size)
    local bucketEnd = bucketStart + size
    local buckets = bucketState.buckets
    local current = buckets[#buckets]
    if not current or current.startAt ~= bucketStart then
        current = { startAt = bucketStart, endAt = bucketEnd, delta = 0 }
        table.insert(buckets, current)
    end
    current.delta = (current.delta or 0) + value

    local maxBuckets = bucketState.maxBuckets or RATE_BUCKET_MAX
    while #buckets > maxBuckets do
        table.remove(buckets, 1)
    end
end

function pH_SessionManager:ComputeBucketedRecentRate(session, metricKey, nowTs)
    if not session or not metricKey then
        return 0
    end
    self:EnsureRecentBucketsDefaults(session)
    local bucketState = session.metrics.recentBuckets[metricKey]
    if not bucketState then
        return 0
    end
    local buckets = bucketState.buckets or {}
    local count = #buckets
    if count == 0 then
        return 0
    end

    local nowLocal = math.floor(tonumber(nowTs) or time())
    local size = bucketState.bucketSizeSec or RATE_BUCKET_SIZE_SEC
    local maxAgeSec = (bucketState.maxBuckets or RATE_BUCKET_MAX) * size
    local weights = {0.6, 0.3, 0.1}
    local weightedSum = 0
    local totalWeight = 0

    local used = 0
    for i = count, 1, -1 do
        if used >= 3 then
            break
        end
        local bucket = buckets[i]
        local endAt = tonumber(bucket and bucket.endAt) or 0
        local age = nowLocal - endAt
        if age <= maxAgeSec then
            local delta = tonumber(bucket and bucket.delta) or 0
            local rate = 0
            if delta > 0 then
                rate = (delta / size) * 3600
            end
            used = used + 1
            local w = weights[used] or 0
            weightedSum = weightedSum + (rate * w)
            totalWeight = totalWeight + w
        end
    end

    if totalWeight <= 0 then
        return 0
    end
    return math.floor(weightedSum / totalWeight)
end

-- Compute derived metrics for display
function pH_SessionManager:GetMetrics(session)
    if not session then
        return nil
    end
    self:EnsureRecentBucketsDefaults(session)

    -- Freeze "current time" during pause so recent-rate views remain stable for QA.
    local now = session.pausedAt or time()
    local durationSec

    -- When paused, use only accumulated duration (no live addition)
    if session.pausedAt then
        durationSec = session.accumulatedDuration or 0
    -- Phase 7: Use new duration tracking if available
    elseif session.accumulatedDuration then
        local accumulated = session.accumulatedDuration
        if session.currentLoginAt then
            durationSec = accumulated + (now - session.currentLoginAt)
        else
            durationSec = accumulated
        end
    else
        -- Backward compatibility: Fall back to legacy durationSec for old sessions
        durationSec = session.durationSec or 0
    end

    local durationHours = durationSec / 3600

    -- Phase 1 & 2: Cash and expenses
    local cash = pH_Ledger:GetBalance(session, "Assets:Cash")
    local cashPerHour = 0
    if durationHours > 0 then
        cashPerHour = math.floor(cash / durationHours)
    end

    -- Phase 2: Income breakdown
    local income = pH_Ledger:GetBalance(session, "Income:LootedCoin")

    -- Phase 2: Expense breakdown
    local expenseRepairs = pH_Ledger:GetBalance(session, "Expense:Repairs")
    local expenseVendorBuys = pH_Ledger:GetBalance(session, "Expense:VendorBuys")
    local expenseTravel = pH_Ledger:GetBalance(session, "Expense:Travel")  -- Phase 5
    local totalExpenses = expenseRepairs + expenseVendorBuys + expenseTravel

    -- Phase 5: Quest income
    local incomeQuest = pH_Ledger:GetBalance(session, "Income:Quest")

    -- Phase 3: Expected inventory value
    local invVendorTrash = pH_Ledger:GetBalance(session, "Assets:Inventory:VendorTrash")
    local invMarketItems = pH_Ledger:GetBalance(session, "Assets:Inventory:MarketItems")
    local invGathering = pH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local invEnchanting = pH_Ledger:GetBalance(session, "Assets:Inventory:Enchanting")
    local expectedInventory = invVendorTrash + invMarketItems + invGathering + invEnchanting

    local expectedPerHour = 0
    if durationHours > 0 then
        expectedPerHour = math.floor(expectedInventory / durationHours)
    end

    -- Phase 3: Total economic value (net worth change)
    local totalValue = cash + expectedInventory
    local totalPerHour = 0
    if durationHours > 0 then
        totalPerHour = math.floor(totalValue / durationHours)
    end
    local lastTotals = session.metrics.recentBucketLastTotals or {}
    local lastGoldTotal = tonumber(lastTotals.goldTotal) or nil
    if lastGoldTotal ~= nil then
        self:RecordMetricDelta(session, "gold", totalValue - lastGoldTotal, now)
    end
    lastTotals.goldTotal = totalValue
    session.metrics.recentBucketLastTotals = lastTotals

    -- Phase 6: Pickpocket metrics
    local pickpocketGold = 0
    local pickpocketValue = 0
    local lockboxesLooted = 0
    local lockboxesOpened = 0
    local fromLockboxGold = 0
    local fromLockboxValue = 0

    if session.pickpocket then
        pickpocketGold = session.pickpocket.gold or 0
        pickpocketValue = session.pickpocket.value or 0
        lockboxesLooted = session.pickpocket.lockboxesLooted or 0
        lockboxesOpened = session.pickpocket.lockboxesOpened or 0
        if session.pickpocket.fromLockbox then
            fromLockboxGold = session.pickpocket.fromLockbox.gold or 0
            fromLockboxValue = session.pickpocket.fromLockbox.value or 0
        end
    end

    -- Also get ledger balances for reporting (source of truth)
    local incomePickpocketCoin = pH_Ledger:GetBalance(session, "Income:Pickpocket:Coin")
    local incomePickpocketItems = pH_Ledger:GetBalance(session, "Income:Pickpocket:Items")
    local incomePickpocketFromLockboxCoin = pH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Coin")
    local incomePickpocketFromLockboxItems = pH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Items")

    -- Phase 9: Compute XP metrics
    local xpGained = 0
    local xpPerHour = 0
    local xpEnabled = false
    if session.metrics and session.metrics.xp then
        local xpMetrics = session.metrics.xp
        xpGained = xpMetrics.gained or 0
        xpEnabled = xpMetrics.enabled or false
        if durationHours > 0 and xpGained > 0 then
            xpPerHour = math.floor(xpGained / durationHours)
        end
    end
    local xpRecentPerHourBucketed = self:ComputeBucketedRecentRate(session, "xp", now)

    -- Phase 9: Compute Rep metrics
    local repGained = 0
    local repPerHour = 0
    local repEnabled = false
    local repTopFactions = {}
    if session.metrics and session.metrics.rep then
        repGained = session.metrics.rep.gained or 0
        repEnabled = session.metrics.rep.enabled or false
        if durationHours > 0 and repGained > 0 then
            repPerHour = math.floor(repGained / durationHours)
        end

        -- Extract top 3 factions by gain
        if session.metrics.rep.byFaction then
            local allFactions = {}
            for factionName, gain in pairs(session.metrics.rep.byFaction) do
                table.insert(allFactions, {name = factionName, gain = gain})
            end
            table.sort(allFactions, function(a, b) return a.gain > b.gain end)
            -- Take top 3
            for i = 1, math.min(3, #allFactions) do
                table.insert(repTopFactions, allFactions[i])
            end
        end
    end
    local repRecentPerHourBucketed = self:ComputeBucketedRecentRate(session, "rep", now)

    -- Phase 9: Compute Honor metrics
    local honorGained = 0
    local honorPerHour = 0
    local honorEnabled = false
    local honorKills = 0
    if session.metrics and session.metrics.honor then
        honorGained = session.metrics.honor.gained or 0
        honorEnabled = session.metrics.honor.enabled or false
        honorKills = session.metrics.honor.kills or 0
        if durationHours > 0 and honorGained > 0 then
            honorPerHour = math.floor(honorGained / durationHours)
        end
    end
    local honorRecentPerHourBucketed = self:ComputeBucketedRecentRate(session, "honor", now)
    local goldRecentPerHourBucketed = self:ComputeBucketedRecentRate(session, "gold", now)

    local repPotentialTotal = (session.metrics and session.metrics.repPotential and (session.metrics.repPotential.eligibleTotal or session.metrics.repPotential.total)) or 0
    local repPotentialTheoreticalTotal = (session.metrics and session.metrics.repPotential and session.metrics.repPotential.theoreticalTotal) or 0
    local repPotentialByFaction = {}
    if session.metrics and session.metrics.repPotential and (session.metrics.repPotential.eligibleByFaction or session.metrics.repPotential.byFaction) then
        local byFaction = session.metrics.repPotential.eligibleByFaction or session.metrics.repPotential.byFaction
        for factionName, value in pairs(byFaction) do
            repPotentialByFaction[factionName] = value
        end
    end
    local repPotentialTheoreticalByFaction = {}
    if session.metrics and session.metrics.repPotential and session.metrics.repPotential.theoreticalByFaction then
        for factionName, value in pairs(session.metrics.repPotential.theoreticalByFaction) do
            repPotentialTheoreticalByFaction[factionName] = value
        end
    end
    local repPotentialItems = BuildRepPotentialItems(session)
    local repPotentialApprox = false
    for _, item in ipairs(repPotentialItems) do
        if item and item.isApprox then
            repPotentialApprox = true
            break
        end
    end

    return {
        durationSec = durationSec,
        durationHours = durationHours,
        cash = cash,
        cashPerHour = cashPerHour,

        -- Phase 2: Income/Expense details
        income = income,
        expenses = totalExpenses,
        expenseRepairs = expenseRepairs,
        expenseVendorBuys = expenseVendorBuys,
        expenseTravel = expenseTravel,  -- Phase 5
        incomeQuest = incomeQuest,  -- Phase 5

        -- Phase 3: Expected inventory value
        expectedInventory = expectedInventory,
        expectedPerHour = expectedPerHour,
        invVendorTrash = invVendorTrash,
        invMarketItems = invMarketItems,
        invGathering = invGathering,
        invEnchanting = invEnchanting,

        -- Phase 3: Total economic value
        totalValue = totalValue,
        totalPerHour = totalPerHour,

        -- Phase 6: Pickpocket metrics
        pickpocketGold = pickpocketGold,
        pickpocketValue = pickpocketValue,
        lockboxesLooted = lockboxesLooted,
        lockboxesOpened = lockboxesOpened,
        fromLockboxGold = fromLockboxGold,
        fromLockboxValue = fromLockboxValue,
        -- Ledger balances (for reporting/debug)
        incomePickpocketCoin = incomePickpocketCoin,
        incomePickpocketItems = incomePickpocketItems,
        incomePickpocketFromLockboxCoin = incomePickpocketFromLockboxCoin,
        incomePickpocketFromLockboxItems = incomePickpocketFromLockboxItems,

        -- Phase 9: XP/Rep/Honor metrics
        xpGained = xpGained,
        xpPerHour = xpPerHour,
        xpRecentPerHourBucketed = xpRecentPerHourBucketed,
        xpEnabled = xpEnabled,
        repGained = repGained,
        repPerHour = repPerHour,
        repRecentPerHourBucketed = repRecentPerHourBucketed,
        repEnabled = repEnabled,
        repTopFactions = repTopFactions,
        repPotentialTotal = repPotentialTotal,
        repPotentialTheoreticalTotal = repPotentialTheoreticalTotal,
        repPotentialByFaction = repPotentialByFaction,
        repPotentialTheoreticalByFaction = repPotentialTheoreticalByFaction,
        repPotentialItems = repPotentialItems,
        repPotentialApprox = repPotentialApprox,
        honorGained = honorGained,
        honorPerHour = honorPerHour,
        honorRecentPerHourBucketed = honorRecentPerHourBucketed,
        honorEnabled = honorEnabled,
        honorKills = honorKills,
        goldRecentPerHourBucketed = goldRecentPerHourBucketed,
    }
end

--------------------------------------------------
-- Metric History (for expanded metric cards)
--------------------------------------------------
local function EnsureMetricHistoryDefaults()
    if not pH_Settings then
        return {
            sampleInterval = 10,
            bufferMinutes = 60,
        }
    end
    if not pH_Settings.metricCards then
        pH_Settings.metricCards = {
            sampleInterval = 10,
            bufferMinutes = 60,
            sparklineMinutes = 15,
            showInactive = false,
        }
    end
    return pH_Settings.metricCards
end

local function CreateMetricBuffer(capacity)
    return {
        samples = {},
        head = 0,
        count = 0,
        capacity = capacity,
    }
end

function pH_SessionManager:EnsureMetricHistory(session)
    if not session then return end
    if session.metricHistory then return end

    local cfg = EnsureMetricHistoryDefaults()
    local sampleInterval = cfg.sampleInterval or 10
    local bufferMinutes = cfg.bufferMinutes or 60
    local capacity = math.max(1, math.floor((bufferMinutes * 60) / sampleInterval))

    session.metricHistory = {
        sampleInterval = sampleInterval,
        lastSampleAt = 0,
        capacity = capacity,
        metrics = {
            gold = CreateMetricBuffer(capacity),
            xp = CreateMetricBuffer(capacity),
            rep = CreateMetricBuffer(capacity),
            honor = CreateMetricBuffer(capacity),
        },
    }
end

local function PushSample(buffer, value)
    local nextIndex = buffer.head + 1
    if nextIndex > buffer.capacity then
        nextIndex = 1
    end
    buffer.samples[nextIndex] = value
    buffer.head = nextIndex
    if buffer.count < buffer.capacity then
        buffer.count = buffer.count + 1
    end
end

function pH_SessionManager:SampleMetricHistory(session, metrics)
    if not session or not metrics then return end
    if self:IsPaused(session) then return end

    self:EnsureMetricHistory(session)
    local history = session.metricHistory
    if not history then return end

    local now = time()
    if history.lastSampleAt > 0 and (now - history.lastSampleAt) < history.sampleInterval then
        return
    end
    history.lastSampleAt = now

    local metricBuffers = history.metrics
    if not metricBuffers then return end

    PushSample(metricBuffers.gold, metrics.totalPerHour or 0)
    PushSample(metricBuffers.xp, metrics.xpPerHour or 0)
    PushSample(metricBuffers.rep, metrics.repPerHour or 0)
    PushSample(metricBuffers.honor, metrics.honorPerHour or 0)
end

-- Format duration in human-readable form
function pH_SessionManager:FormatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, mins, secs)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Get session by ID
function pH_SessionManager:GetSession(sessionId)
    local s = pH_DB_Account.sessions[sessionId]
    if not s and type(sessionId) == "number" then
        s = pH_DB_Account.sessions[tostring(sessionId)]
    elseif not s and type(sessionId) == "string" then
        s = pH_DB_Account.sessions[tonumber(sessionId)]
    end
    return s
end

-- List all sessions (newest first)
function pH_SessionManager:ListSessions(limit)
    local sessions = {}
    for _, session in pairs(pH_DB_Account.sessions) do
        table.insert(sessions, session)
    end

    -- Sort by ID descending (newest first)
    table.sort(sessions, function(a, b) return a.id > b.id end)

    if limit then
        local limited = {}
        for i = 1, math.min(limit, #sessions) do
            table.insert(limited, sessions[i])
        end
        return limited
    end

    return sessions
end

--------------------------------------------------
-- Phase 3: Item Aggregation
--------------------------------------------------

local function EnsureRepPotential(session)
    if not session.metrics then
        session.metrics = {}
    end
    if not session.metrics.repPotential then
        session.metrics.repPotential = {
            total = 0, byFaction = {}, byItem = {},
            eligibleTotal = 0, theoreticalTotal = 0,
            eligibleByFaction = {}, theoreticalByFaction = {},
        }
    end
    if session.metrics.repPotential.eligibleTotal == nil then
        session.metrics.repPotential.eligibleTotal = session.metrics.repPotential.total or 0
    end
    if session.metrics.repPotential.theoreticalTotal == nil then
        session.metrics.repPotential.theoreticalTotal = 0
    end
    if not session.metrics.repPotential.byFaction then
        session.metrics.repPotential.byFaction = {}
    end
    if not session.metrics.repPotential.byItem then
        session.metrics.repPotential.byItem = {}
    end
    if not session.metrics.repPotential.eligibleByFaction then
        session.metrics.repPotential.eligibleByFaction = {}
    end
    if not session.metrics.repPotential.theoreticalByFaction then
        session.metrics.repPotential.theoreticalByFaction = {}
    end
end

function pH_SessionManager:AdjustRepPotentialForItem(session, itemID, deltaCount, itemName)
    if not session or not itemID or not deltaCount or deltaCount == 0 then
        return
    end
    if not pH_RepTurninCatalog or not pH_RepTurninCatalog.GetRepRules then
        return
    end
    -- Source of truth is session.items count; recompute all per-item/faction totals.
    self:RecomputeRepPotentialForSession(session)
end

function pH_SessionManager:RecomputeRepPotentialForSession(session)
    if not session then
        return
    end
    EnsureRepPotential(session)
    session.metrics.repPotential.total = 0
    session.metrics.repPotential.eligibleTotal = 0
    session.metrics.repPotential.theoreticalTotal = 0
    session.metrics.repPotential.byFaction = {}
    session.metrics.repPotential.eligibleByFaction = {}
    session.metrics.repPotential.theoreticalByFaction = {}
    session.metrics.repPotential.byItem = {}

    local standings = BuildFactionStandingMap()
    for itemID, itemData in pairs(session.items or {}) do
        local count = (itemData and itemData.count) or 0
        local itemName = itemData and itemData.name or nil
        if count > 0 and pH_RepTurninCatalog and pH_RepTurninCatalog.GetRepRules then
            local rules = pH_RepTurninCatalog:GetRepRules(itemID, itemName)
            local entry = BuildRepPotentialEntry(itemID, itemName, count, rules, standings)
            if entry then
                session.metrics.repPotential.byItem[itemID] = entry
                session.metrics.repPotential.eligibleTotal = session.metrics.repPotential.eligibleTotal + (entry.eligibleRep or 0)
                session.metrics.repPotential.theoreticalTotal = session.metrics.repPotential.theoreticalTotal + (entry.theoreticalRep or 0)

                for _, target in ipairs(entry.targets or {}) do
                    local factionKey = target.factionKey or "Unknown"
                    session.metrics.repPotential.eligibleByFaction[factionKey] =
                        (session.metrics.repPotential.eligibleByFaction[factionKey] or 0) + (target.eligibleRep or 0)
                    session.metrics.repPotential.theoreticalByFaction[factionKey] =
                        (session.metrics.repPotential.theoreticalByFaction[factionKey] or 0) + (target.theoreticalRep or 0)
                end
            end
        end
    end

    -- Backward-compatible fields
    session.metrics.repPotential.total = session.metrics.repPotential.eligibleTotal
    for factionName, value in pairs(session.metrics.repPotential.eligibleByFaction) do
        session.metrics.repPotential.byFaction[factionName] = value
    end
end

function pH_SessionManager:RunPricingV2Migration()
    if not pH_DB_Account then
        return false, "No account DB"
    end
    pH_DB_Account.meta = pH_DB_Account.meta or {}
    pH_DB_Account.meta.migrations = pH_DB_Account.meta.migrations or {}
    if pH_DB_Account.meta.migrations.pricing_v2 then
        return false, "Already migrated"
    end

    local function MigrateSession(session)
        if not session then
            return
        end
        -- Migrate holdings lot buckets
        for _, holding in pairs(session.holdings or {}) do
            for _, lot in ipairs(holding.lots or {}) do
                if lot.bucket == "rare_multi" then
                    lot.bucket = "market_items"
                end
            end
        end

        -- Migrate aggregated item buckets
        for _, itemData in pairs(session.items or {}) do
            if itemData.bucket == "rare_multi" then
                itemData.bucket = "market_items"
            end
        end

        -- Migrate ledger accounts
        if session.ledger and session.ledger.balances then
            local balances = session.ledger.balances
            balances["Assets:Inventory:MarketItems"] =
                (balances["Assets:Inventory:MarketItems"] or 0) + (balances["Assets:Inventory:RareMulti"] or 0)
            balances["Income:ItemsLooted:MarketItems"] =
                (balances["Income:ItemsLooted:MarketItems"] or 0) + (balances["Income:ItemsLooted:RareMulti"] or 0)
            balances["Assets:Inventory:RareMulti"] = nil
            balances["Income:ItemsLooted:RareMulti"] = nil
        end

        EnsureRepPotential(session)
        self:RecomputeRepPotentialForSession(session)
    end

    for _, session in pairs(pH_DB_Account.sessions or {}) do
        MigrateSession(session)
    end
    for _, session in pairs(pH_DB_Account.activeSessions or {}) do
        MigrateSession(session)
    end

    pH_DB_Account.meta.migrations.pricing_v2 = true
    return true, "pricing_v2 migration complete"
end

local function ResolveItemMeta(itemID, itemData)
    local itemName, _, quality, _, _, _, _, _, _, _, _, itemClass, itemSubClass = GetItemInfo(itemID)
    if itemName then
        return itemName, quality, itemClass, itemSubClass
    end
    if itemData then
        return itemData.name, itemData.quality, nil, nil
    end
    return nil, nil, nil, nil
end

local function RebuildItemLedgerBalances(session)
    if not session or not session.ledger or not session.ledger.balances then
        return
    end

    local balances = session.ledger.balances
    local bucketToAccount = {
        vendor_trash = "VendorTrash",
        market_items = "MarketItems",
        gathering = "Gathering",
        enchanting = "Enchanting",
        container_lockbox = "Containers:Lockbox",
    }

    -- Reset item-ledger balances we own
    for _, accountSuffix in pairs(bucketToAccount) do
        balances["Income:ItemsLooted:" .. accountSuffix] = 0
        if accountSuffix ~= "Containers:Lockbox" then
            balances["Assets:Inventory:" .. accountSuffix] = 0
        end
    end
    -- Legacy cleanup
    balances["Income:ItemsLooted:RareMulti"] = nil
    balances["Assets:Inventory:RareMulti"] = nil

    -- Rebuild income from session item aggregates (looted value snapshot)
    for _, itemData in pairs(session.items or {}) do
        local bucket = itemData.bucket
        local accountSuffix = bucketToAccount[bucket]
        if accountSuffix and bucket ~= "container_lockbox" then
            local account = "Income:ItemsLooted:" .. accountSuffix
            balances[account] = (balances[account] or 0) + (itemData.expectedTotal or 0)
        end
    end

    -- Rebuild inventory assets from remaining holdings lots
    for _, holding in pairs(session.holdings or {}) do
        for _, lot in ipairs(holding.lots or {}) do
            local accountSuffix = bucketToAccount[lot.bucket]
            if accountSuffix and lot.bucket ~= "container_lockbox" then
                local account = "Assets:Inventory:" .. accountSuffix
                balances[account] = (balances[account] or 0) + ((lot.count or 0) * (lot.expectedEach or 0))
            end
        end
    end
end

function pH_SessionManager:RepriceSessionItems(session)
    if not session or not session.items then
        return false, "Invalid session", 0, 0
    end

    local repriced = 0
    local skipped = 0

    for itemID, itemData in pairs(session.items) do
        local itemName, quality, itemClass, itemSubClass = ResolveItemMeta(itemID, itemData)
        if not itemName then
            skipped = skipped + 1
        else
            local bucket = pH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
            local expectedEach = pH_Valuation:ComputeExpectedValue(itemID, bucket)
            local lootedCount = (itemData.countLooted or itemData.count or 0)
            itemData.bucket = bucket
            itemData.expectedTotal = lootedCount * expectedEach

            -- Keep remaining holdings lots aligned with repriced bucket/value
            local holding = session.holdings and session.holdings[itemID]
            if holding and holding.lots then
                for _, lot in ipairs(holding.lots) do
                    lot.bucket = bucket
                    lot.expectedEach = expectedEach
                end
            end

            repriced = repriced + 1
        end
    end

    -- Recompute rep potential from repriced item counts
    self:RecomputeRepPotentialForSession(session)
    RebuildItemLedgerBalances(session)
    return true, "Repriced session items", repriced, skipped
end

function pH_SessionManager:RepriceAllSessions()
    local totalSessions = 0
    local totalItems = 0
    local totalSkipped = 0

    for _, session in pairs(pH_DB_Account.sessions or {}) do
        totalSessions = totalSessions + 1
        local _, _, repriced, skipped = self:RepriceSessionItems(session)
        totalItems = totalItems + (repriced or 0)
        totalSkipped = totalSkipped + (skipped or 0)
    end

    for _, session in pairs(pH_DB_Account.activeSessions or {}) do
        totalSessions = totalSessions + 1
        local _, _, repriced, skipped = self:RepriceSessionItems(session)
        totalItems = totalItems + (repriced or 0)
        totalSkipped = totalSkipped + (skipped or 0)
    end

    MarkIndexStale()
    return true, string.format("Repriced %d items across %d sessions (skipped=%d)", totalItems, totalSessions, totalSkipped)
end

-- Add or update item in session.items aggregate
function pH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)
    if not session.items[itemID] then
        -- Create new item aggregate
        session.items[itemID] = {
            itemID = itemID,
            name = itemName,
            quality = quality,
            bucket = bucket,
            count = 0,
            countLooted = 0,
            expectedTotal = 0,
        }
    end

    -- Update counts
    session.items[itemID].count = session.items[itemID].count + count
    session.items[itemID].countLooted = (session.items[itemID].countLooted or 0) + count
    session.items[itemID].expectedTotal = session.items[itemID].expectedTotal + (count * expectedEach)

    self:AdjustRepPotentialForItem(session, itemID, count, itemName)
end

-- Increment gathering node counters
-- @param session: Active session
-- @param nodeName: Human-readable node name (e.g., "Copper Vein", "Peacebloom", "Fishing")
function pH_SessionManager:AddGatherNode(session, nodeName)
    if not session then
        return
    end

    -- Ensure gathering structure exists (backward compatibility for older sessions)
    if not session.gathering then
        session.gathering = {
            totalNodes = 0,
            nodesByType = {},
        }
    end

    local name = nodeName
    if not name or name == "" then
        name = "Unknown"
    end

    session.gathering.totalNodes = (session.gathering.totalNodes or 0) + 1
    if not session.gathering.nodesByType then
        session.gathering.nodesByType = {}
    end
    session.gathering.nodesByType[name] = (session.gathering.nodesByType[name] or 0) + 1
end

-- Export module
_G.pH_SessionManager = pH_SessionManager
