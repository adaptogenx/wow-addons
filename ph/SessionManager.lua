--[[
    SessionManager.lua - Session lifecycle management for pH

    Handles session creation, persistence, and metrics computation.
]]

-- luacheck: globals GetMaxPlayerLevel UnitLevel UnitXP UnitXPMax UnitClass pH_DB_Account pH_Settings UnitName GetRealmName UnitFactionGroup pH_Index

local pH_SessionManager = {}
local DEFAULT_SHORT_SESSION_SEC = 300
local HISTORY_UNDO_WINDOW_SEC = 30
local HISTORY_UNDO_MAX = 20

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
function pH_SessionManager:StartSession()
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
            honor = { gained = 0, enabled = false, kills = 0 },
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
            honor = { gained = 0, enabled = false, kills = 0 },
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

            local mh = s.metrics.honor or {}
            merged.metrics.honor.gained = merged.metrics.honor.gained + (mh.gained or 0)
            merged.metrics.honor.enabled = merged.metrics.honor.enabled or (mh.enabled and true or false)
            merged.metrics.honor.kills = merged.metrics.honor.kills + (mh.kills or 0)
        end
    end

    merged.archived = false
    merged.archivedAt = nil
    merged.archivedReason = nil

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
function pH_SessionManager:PauseSession()
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
    return true, "Session paused"
end

-- Resume a paused session
function pH_SessionManager:ResumeSession()
    local session = self:GetActiveSession()
    if not session then
        return false, "No active session"
    end
    if not session.pausedAt then
        return false, "Session is not paused"
    end
    session.pausedAt = nil
    session.currentLoginAt = time()
    return true, "Session resumed"
end

-- Compute derived metrics for display
function pH_SessionManager:GetMetrics(session)
    if not session then
        return nil
    end

    local now = time()
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
    local invRareMulti = pH_Ledger:GetBalance(session, "Assets:Inventory:RareMulti")
    local invGathering = pH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local expectedInventory = invVendorTrash + invRareMulti + invGathering

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
        xpGained = session.metrics.xp.gained or 0
        xpEnabled = session.metrics.xp.enabled or false
        if durationHours > 0 and xpGained > 0 then
            xpPerHour = math.floor(xpGained / durationHours)
        end
    end

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
        invRareMulti = invRareMulti,
        invGathering = invGathering,

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
        xpEnabled = xpEnabled,
        repGained = repGained,
        repPerHour = repPerHour,
        repEnabled = repEnabled,
        repTopFactions = repTopFactions,
        honorGained = honorGained,
        honorPerHour = honorPerHour,
        honorEnabled = honorEnabled,
        honorKills = honorKills,
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
