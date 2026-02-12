--[[
    SessionManager.lua - Session lifecycle management for GoldPH

    Handles session creation, persistence, and metrics computation.
]]

-- luacheck: globals GetMaxPlayerLevel UnitLevel UnitXP UnitXPMax UnitClass GoldPH_DB_Account GoldPH_Settings UnitName GetRealmName UnitFactionGroup

local GoldPH_SessionManager = {}

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

-- Start a new session
function GoldPH_SessionManager:StartSession()
    if self:GetActiveSession() then
        return false, "A session is already active. Stop it first with /goldph stop"
    end

    -- If another character has an active session, persist it to history so we don't lose it
    local other = GoldPH_DB_Account.activeSession
    if other and not SessionOwnedByCurrentPlayer(other) then
        local now = time()
        if other.currentLoginAt then
            other.accumulatedDuration = (other.accumulatedDuration or 0) + (now - other.currentLoginAt)
            other.currentLoginAt = nil
        end
        other.endedAt = now
        other.durationSec = other.accumulatedDuration or 0
        GoldPH_DB_Account.sessions[other.id] = other
        GoldPH_DB_Account.activeSession = nil
        if GoldPH_Index then
            GoldPH_Index:MarkStale()
        end
    end

    -- Increment session ID
    GoldPH_DB_Account.meta.lastSessionId = GoldPH_DB_Account.meta.lastSessionId + 1
    local sessionId = GoldPH_DB_Account.meta.lastSessionId

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
    }

    -- Initialize ledger
    GoldPH_Ledger:InitializeLedger(session)

    -- Initialize XP tracking (if not max level)
    -- GetMaxPlayerLevel() or fallback to 60 for Classic
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    if UnitLevel("player") < maxLevel then
        session.snapshots.xp.cur = UnitXP("player")
        session.snapshots.xp.max = UnitXPMax("player")
    end

    -- Initialize reputation tracking (via Events.lua after session created)

    -- Set as active session
    GoldPH_DB_Account.activeSession = session

    -- Verbose debug: log initial duration tracking state
    if GoldPH_DB_Account.debug.verbose then
        local dateStr
        if date then
            dateStr = date("%Y-%m-%d %H:%M:%S", session.startedAt)
        else
            dateStr = tostring(session.startedAt)
        end
        print(string.format(
            "[GoldPH Debug] Session #%d started at %s | accumulatedDuration=%d | currentLoginAt=%s",
            sessionId,
            dateStr,
            session.accumulatedDuration or 0,
            tostring(session.currentLoginAt)
        ))
    end

    return true, "Session #" .. sessionId .. " started"
end

-- Stop the active session (only for current character's session)
function GoldPH_SessionManager:StopSession()
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
    GoldPH_DB_Account.sessions[session.id] = session

    -- Clear active session
    GoldPH_DB_Account.activeSession = nil

    -- Mark index stale for rebuild
    if GoldPH_Index then
        GoldPH_Index:MarkStale()
    end

    return true, "Session #" .. session.id .. " stopped and saved (duration: " ..
                 self:FormatDuration(session.durationSec) .. ")"
end

-- Get the active session for the current character only (or nil if none or owned by another character)
function GoldPH_SessionManager:GetActiveSession()
    local session = GoldPH_DB_Account.activeSession
    if not session then
        return nil
    end
    if not SessionOwnedByCurrentPlayer(session) then
        return nil
    end
    return session
end

-- Return true if the session is paused (clock and events frozen)
function GoldPH_SessionManager:IsPaused(session)
    return session and session.pausedAt ~= nil
end

-- Pause the active session (stop clock and do not record events until resumed)
function GoldPH_SessionManager:PauseSession()
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
function GoldPH_SessionManager:ResumeSession()
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
function GoldPH_SessionManager:GetMetrics(session)
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
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashPerHour = 0
    if durationHours > 0 then
        cashPerHour = math.floor(cash / durationHours)
    end

    -- Phase 2: Income breakdown
    local income = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    -- Phase 2: Expense breakdown
    local expenseRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")
    local expenseVendorBuys = GoldPH_Ledger:GetBalance(session, "Expense:VendorBuys")
    local expenseTravel = GoldPH_Ledger:GetBalance(session, "Expense:Travel")  -- Phase 5
    local totalExpenses = expenseRepairs + expenseVendorBuys + expenseTravel

    -- Phase 5: Quest income
    local incomeQuest = GoldPH_Ledger:GetBalance(session, "Income:Quest")

    -- Phase 3: Expected inventory value
    local invVendorTrash = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:VendorTrash")
    local invRareMulti = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:RareMulti")
    local invGathering = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
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
    local incomePickpocketCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Coin")
    local incomePickpocketItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Items")
    local incomePickpocketFromLockboxCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Coin")
    local incomePickpocketFromLockboxItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Items")

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
    if not GoldPH_Settings then
        return {
            sampleInterval = 10,
            bufferMinutes = 60,
        }
    end
    if not GoldPH_Settings.metricCards then
        GoldPH_Settings.metricCards = {
            sampleInterval = 10,
            bufferMinutes = 60,
            sparklineMinutes = 15,
            showInactive = false,
        }
    end
    return GoldPH_Settings.metricCards
end

local function CreateMetricBuffer(capacity)
    return {
        samples = {},
        head = 0,
        count = 0,
        capacity = capacity,
    }
end

function GoldPH_SessionManager:EnsureMetricHistory(session)
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

function GoldPH_SessionManager:SampleMetricHistory(session, metrics)
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
function GoldPH_SessionManager:FormatDuration(seconds)
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
function GoldPH_SessionManager:GetSession(sessionId)
    return GoldPH_DB_Account.sessions[sessionId]
end

-- List all sessions (newest first)
function GoldPH_SessionManager:ListSessions(limit)
    local sessions = {}
    for _, session in pairs(GoldPH_DB_Account.sessions) do
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
function GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)
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
function GoldPH_SessionManager:AddGatherNode(session, nodeName)
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
_G.GoldPH_SessionManager = GoldPH_SessionManager
