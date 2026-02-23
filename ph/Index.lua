--[[
    Index.lua - Data indexing and query engine for pH History

    Builds fast lookup indexes and cached summaries for efficient querying
    of historical sessions. Designed for scalability (100+ sessions).
]]

-- luacheck: globals pH_DB_Account pH_Settings GetRealmName UnitFactionGroup UnitName

local pH_Index = {
    stale = true,
    lastBuild = 0,

    -- All session IDs (sorted by ID descending)
    sessions = {},

    -- Precomputed summaries [sessionId] -> summary
    summaries = {},

    -- Fast lookup indexes
    byZone = {},      -- [zone] -> {sessionId1, sessionId2, ...}
    byChar = {},      -- [charKey] -> {sessionId1, sessionId2, ...}

    -- Pre-sorted arrays (sessionIds in sorted order)
    sorted = {
        totalPerHour = {},     -- Sorted by total gold/hr descending
        cashPerHour = {},      -- Sorted by cash gold/hr descending
        expectedPerHour = {},  -- Sorted by expected gold/hr descending
        date = {},             -- Sorted by endedAt descending (newest first)
        xpPerHour = {},        -- Sorted by XP/hr descending
        repPerHour = {},       -- Sorted by Rep/hr descending
        honorPerHour = {},     -- Sorted by Honor/hr descending
    },

    -- Item aggregates (across all sessions)
    itemAgg = {},  -- [itemID] -> {itemID, name, quality, bucket, totalValue, totalCount, avgValueEach, zones={}, chars={}}

    -- Node aggregates (across all sessions)
    nodeAgg = {},  -- [nodeName] -> {totalCount, zones={}, chars={}}

    -- Zone aggregates (for Compare tab)
    zoneAgg = {},  -- [zone] -> {sessionCount, avgTotalPerHour, bestTotalPerHour, bestSessionId, avgNodesPerHour, bestNodesPerHour}
}

--------------------------------------------------
-- Helper: Normalize character name for key (strip "Name-Realm" to "Name" if present)
-- WoW/other code may store character as "Bob-MyRealm"; we need just "Bob" for charKey.
--------------------------------------------------
local function NormalizeCharForKey(character, realm)
    if not character or character == "" then return "Unknown" end
    if not realm or realm == "" then return character end
    -- If character ends with "-Realm", strip it (realm is added separately in charKey)
    local suffix = "-" .. realm
    if #character > #suffix and character:sub(-#suffix) == suffix then
        return character:sub(1, -(#suffix + 1))
    end
    return character
end

--------------------------------------------------
-- Helper: Get character key (format: "Name-Realm-Faction")
--------------------------------------------------
local function GetCharKey(character, realm, faction)
    local name = NormalizeCharForKey(character or "Unknown", realm)
    return name .. "-" .. (realm or "Unknown") .. "-" .. (faction or "Unknown")
end

--------------------------------------------------
-- Helper: Extract top item from session
--------------------------------------------------
local function GetTopItem(session)
    if not session.items then
        return nil, 0
    end

    local topItemName = nil
    local topItemValue = 0

    for _, itemData in pairs(session.items) do
        if itemData.expectedTotal > topItemValue then
            topItemValue = itemData.expectedTotal
            topItemName = itemData.name
        end
    end

    return topItemName, topItemValue
end

--------------------------------------------------
-- Core: Build Index
--------------------------------------------------
function pH_Index:Build()
    local startTime = GetTime()
    local shortThreshold = 300
    if pH_Settings and pH_Settings.historyCleanup and pH_Settings.historyCleanup.shortThresholdSec then
        shortThreshold = pH_Settings.historyCleanup.shortThresholdSec
    end

    -- Reset structures
    self.sessions = {}
    self.summaries = {}
    self.byZone = {}
    self.byChar = {}
    self.sorted = {
        totalPerHour = {},
        cashPerHour = {},
        expectedPerHour = {},
        date = {},
        xpPerHour = {},
        repPerHour = {},
        honorPerHour = {},
    }
    self.itemAgg = {}
    self.nodeAgg = {}
    self.zoneAgg = {}

    -- Temporary storage for zone aggregates
    local zoneTotals = {}  -- [zone] -> {totalPerHourSum, count, bestPerHour, bestSessionId, nodesSum, nodesCount, bestNodes}

    -- Build a set of active session IDs (exclude from history)
    local activeSessionIds = {}
    if pH_DB_Account.activeSessions then
        for _, active in pairs(pH_DB_Account.activeSessions) do
            if active and active.id ~= nil then
                activeSessionIds[tostring(active.id)] = true
            end
        end
    end

    -- Scan all sessions (skip active sessions)
    for sessionId, session in pairs(pH_DB_Account.sessions) do
        -- Normalize key: WoW SavedVariables may use string keys ("165"); use numeric for consistency
        local key = (type(sessionId) == "number") and sessionId or tonumber(sessionId)
        key = key or sessionId  -- fallback for non-numeric keys

        -- Skip if this is an active session (should not be in history)
        local shouldProcess = not activeSessionIds[tostring(key)] and not activeSessionIds[tostring(sessionId)]

        -- Get metrics using SessionManager (source of truth)
        -- Wrap in pcall; skip sessions that error (e.g. legacy/malformed data)
        local metrics
        if shouldProcess then
            local ok, result = pcall(function()
                return pH_SessionManager:GetMetrics(session)
            end)
            if ok and result then
                metrics = result
            else
                shouldProcess = false
                if pH_DB_Account and pH_DB_Account.debug and pH_DB_Account.debug.verbose and not ok then
                    print(string.format("[pH Index] Skip session %s: %s", tostring(key), tostring(result)))
                end
            end
        end

        if shouldProcess then
            -- Build character key (use session metadata for cross-character filter; fallback for old sessions)
            local charKey = GetCharKey(
                session.character or UnitName("player") or "Unknown",
                session.realm or GetRealmName() or "Unknown",
                session.faction or UnitFactionGroup("player") or "Unknown"
            )

            -- Extract flags
            local hasGathering = session.gathering and session.gathering.totalNodes and session.gathering.totalNodes > 0
            local hasPickpocket = session.pickpocket and (
                (session.pickpocket.gold or 0) > 0 or
                (session.pickpocket.value or 0) > 0 or
                (session.pickpocket.lockboxesLooted or 0) > 0
            )

            -- Phase 9: Extract XP/Rep/Honor flags and values
            local hasXP = metrics.xpEnabled or false
            local xpGained = metrics.xpGained or 0
            local xpPerHour = metrics.xpPerHour or 0

            local hasRep = metrics.repEnabled or false
            local repGained = metrics.repGained or 0
            local repPerHour = metrics.repPerHour or 0

            local hasHonor = metrics.honorEnabled or false
            local honorGained = metrics.honorGained or 0
            local honorPerHour = metrics.honorPerHour or 0
            local honorKills = metrics.honorKills or 0

            -- Get top item
            local topItemName, topItemValue = GetTopItem(session)

            -- Build summary
            local isArchived = session.archived and true or false
            local isShort = (metrics.durationSec or 0) < shortThreshold
            local summary = {
                id = key,
                charKey = charKey,
                zone = session.zone or "Unknown",
                startedAt = session.startedAt,
                endedAt = session.endedAt,
                durationSec = metrics.durationSec,
                durationHours = metrics.durationHours,

                cash = metrics.cash,
                cashPerHour = metrics.cashPerHour,
                expectedInventory = metrics.expectedInventory,
                expectedPerHour = metrics.expectedPerHour,
                totalValue = metrics.totalValue,
                totalPerHour = metrics.totalPerHour,
                isArchived = isArchived,
                isShort = isShort,

                hasGathering = hasGathering,
                hasPickpocket = hasPickpocket,

                -- Phase 9: XP/Rep/Honor metrics
                hasXP = hasXP,
                xpGained = xpGained,
                xpPerHour = xpPerHour,
                hasRep = hasRep,
                repGained = repGained,
                repPerHour = repPerHour,
                hasHonor = hasHonor,
                honorGained = honorGained,
                honorPerHour = honorPerHour,
                honorKills = honorKills,

                topItemName = topItemName,
                topItemValue = topItemValue,
            }

            -- Store summary (use normalized key for consistent lookups)
            self.summaries[key] = summary
            table.insert(self.sessions, key)

            -- Build byZone index
            local zone = summary.zone
            if not self.byZone[zone] then
                self.byZone[zone] = {}
            end
            table.insert(self.byZone[zone], key)

            -- Build byChar index
            if not self.byChar[charKey] then
                self.byChar[charKey] = {}
            end
            table.insert(self.byChar[charKey], key)

            -- Aggregate items
            if session.items then
                for itemID, itemData in pairs(session.items) do
                    if not self.itemAgg[itemID] then
                        self.itemAgg[itemID] = {
                            itemID = itemID,
                            name = itemData.name,
                            quality = itemData.quality,
                            bucket = itemData.bucket,
                            totalValue = 0,
                            totalCount = 0,
                            avgValueEach = 0,
                            zones = {},
                            chars = {},
                        }
                    end

                    local agg = self.itemAgg[itemID]
                    agg.totalValue = agg.totalValue + itemData.expectedTotal
                    agg.totalCount = agg.totalCount + (itemData.countLooted or itemData.count)

                    -- Zone breakdown
                    if not agg.zones[zone] then
                        agg.zones[zone] = {value = 0, count = 0}
                    end
                    agg.zones[zone].value = agg.zones[zone].value + itemData.expectedTotal
                    agg.zones[zone].count = agg.zones[zone].count + (itemData.countLooted or itemData.count)

                    -- Char breakdown
                    if not agg.chars[charKey] then
                        agg.chars[charKey] = {value = 0, count = 0}
                    end
                    agg.chars[charKey].value = agg.chars[charKey].value + itemData.expectedTotal
                    agg.chars[charKey].count = agg.chars[charKey].count + itemData.count
                end
            end

            -- Aggregate nodes
            if session.gathering and session.gathering.nodesByType then
                for nodeName, count in pairs(session.gathering.nodesByType) do
                    if not self.nodeAgg[nodeName] then
                        self.nodeAgg[nodeName] = {
                            totalCount = 0,
                            zones = {},
                            chars = {},
                        }
                    end

                    local agg = self.nodeAgg[nodeName]
                    agg.totalCount = agg.totalCount + count

                    -- Zone breakdown
                    if not agg.zones[zone] then
                        agg.zones[zone] = 0
                    end
                    agg.zones[zone] = agg.zones[zone] + count

                    -- Char breakdown
                    if not agg.chars[charKey] then
                        agg.chars[charKey] = 0
                    end
                    agg.chars[charKey] = agg.chars[charKey] + count
                end
            end

            -- Aggregate zone stats
            -- Cleaned analytics: exclude short and archived sessions by default.
            if not isArchived and not isShort then
                if not zoneTotals[zone] then
                    zoneTotals[zone] = {
                        totalPerHourSum = 0,
                        count = 0,
                        bestPerHour = 0,
                        bestSessionId = nil,
                        nodesSum = 0,
                        nodesCount = 0,
                        bestNodes = 0,
                    }
                end

                local zt = zoneTotals[zone]
                zt.totalPerHourSum = zt.totalPerHourSum + summary.totalPerHour
                zt.count = zt.count + 1

                if summary.totalPerHour > zt.bestPerHour then
                    zt.bestPerHour = summary.totalPerHour
                    zt.bestSessionId = key
                end

                if hasGathering then
                    local nodesPerHour = 0
                    if metrics.durationHours > 0 then
                        nodesPerHour = session.gathering.totalNodes / metrics.durationHours
                    end
                    zt.nodesSum = zt.nodesSum + nodesPerHour
                    zt.nodesCount = zt.nodesCount + 1
                    if nodesPerHour > zt.bestNodes then
                        zt.bestNodes = nodesPerHour
                    end
                end
            end
        end  -- Close shouldProcess
    end

    -- Finalize item aggregates (compute avgValueEach)
    for itemID, agg in pairs(self.itemAgg) do
        if agg.totalCount > 0 then
            agg.avgValueEach = math.floor(agg.totalValue / agg.totalCount)
        end
    end

    -- Finalize zone aggregates
    for zone, zt in pairs(zoneTotals) do
        local avgNodesPerHour = 0
        if zt.nodesCount > 0 then
            avgNodesPerHour = zt.nodesSum / zt.nodesCount
        end

        self.zoneAgg[zone] = {
            sessionCount = zt.count,
            avgTotalPerHour = math.floor(zt.totalPerHourSum / zt.count),
            bestTotalPerHour = zt.bestPerHour,
            bestSessionId = zt.bestSessionId,
            avgNodesPerHour = avgNodesPerHour,
            bestNodesPerHour = zt.bestNodes,
        }
    end

    -- 1. Sort by totalPerHour descending
    local sortedByTotal = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByTotal, sessionId)
    end
    table.sort(sortedByTotal, function(a, b)
        return self.summaries[a].totalPerHour > self.summaries[b].totalPerHour
    end)
    self.sorted.totalPerHour = sortedByTotal

    -- 2. Sort by cashPerHour descending
    local sortedByCash = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByCash, sessionId)
    end
    table.sort(sortedByCash, function(a, b)
        return self.summaries[a].cashPerHour > self.summaries[b].cashPerHour
    end)
    self.sorted.cashPerHour = sortedByCash

    -- 3. Sort by expectedPerHour descending
    local sortedByExpected = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByExpected, sessionId)
    end
    table.sort(sortedByExpected, function(a, b)
        return self.summaries[a].expectedPerHour > self.summaries[b].expectedPerHour
    end)
    self.sorted.expectedPerHour = sortedByExpected

    -- 4. Sort by date descending (newest first)
    local sortedByDate = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByDate, sessionId)
    end
    table.sort(sortedByDate, function(a, b)
        local aEnd = self.summaries[a].endedAt or 0
        local bEnd = self.summaries[b].endedAt or 0
        return aEnd > bEnd
    end)
    self.sorted.date = sortedByDate

    -- Phase 9: Sort by xpPerHour descending
    local sortedByXP = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByXP, sessionId)
    end
    table.sort(sortedByXP, function(a, b)
        return (self.summaries[a].xpPerHour or 0) > (self.summaries[b].xpPerHour or 0)
    end)
    self.sorted.xpPerHour = sortedByXP

    -- Phase 9: Sort by repPerHour descending
    local sortedByRep = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByRep, sessionId)
    end
    table.sort(sortedByRep, function(a, b)
        return (self.summaries[a].repPerHour or 0) > (self.summaries[b].repPerHour or 0)
    end)
    self.sorted.repPerHour = sortedByRep

    -- Phase 9: Sort by honorPerHour descending
    local sortedByHonor = {}
    for _, sessionId in ipairs(self.sessions) do
        table.insert(sortedByHonor, sessionId)
    end
    table.sort(sortedByHonor, function(a, b)
        return (self.summaries[a].honorPerHour or 0) > (self.summaries[b].honorPerHour or 0)
    end)
    self.sorted.honorPerHour = sortedByHonor

    -- Mark as fresh
    self.stale = false
    self.lastBuild = GetTime()

    local buildTime = GetTime() - startTime
    if pH_DB_Account and pH_DB_Account.debug and pH_DB_Account.debug.verbose then
        print(string.format("[pH Index] Built index with %d sessions in %.3fs", #self.sessions, buildTime))
    end
end

--------------------------------------------------
-- Core: Query Sessions
--------------------------------------------------
function pH_Index:QuerySessions(filters)
    -- Rebuild if stale
    if self.stale then
        self:Build()
    end

    -- Sanity: if we have sessions in DB but index is empty, force rebuild once
    if #self.sessions == 0 and pH_DB_Account and pH_DB_Account.sessions then
        local dbCount = 0
        for _ in pairs(pH_DB_Account.sessions) do dbCount = dbCount + 1 end
        if dbCount > 0 then
            self.stale = true
            self:Build()
        end
    end

    -- Default filters
    filters = filters or {}
    local sort = filters.sort or "totalPerHour"
    local sortDesc = filters.sortDesc ~= false  -- Default true
    local search = filters.search or ""
    local charKeys = filters.charKeys  -- nil = all, else {charKey1=true, ...}
    local zone = filters.zone  -- nil = any
    local minPerHour = filters.minPerHour or 0
    local minDurationSec = filters.minDurationSec or 0
    local excludeShort = filters.excludeShort or false
    local excludeArchived = filters.excludeArchived
    if filters.includeArchived then
        excludeArchived = false
    elseif excludeArchived == nil then
        excludeArchived = false
    end
    local hasGathering = filters.hasGathering or false
    local hasPickpocket = filters.hasPickpocket or false
    local onlyXP = filters.onlyXP or false
    local onlyRep = filters.onlyRep or false
    local onlyHonor = filters.onlyHonor or false

    -- Start with pre-sorted base list (fallback to self.sessions if sort array empty)
    local candidates = self.sorted[sort] or self.sorted.totalPerHour
    if not candidates or #candidates == 0 then
        candidates = self.sessions or {}
    end

    -- Single-pass filtering
    local results = {}
    for _, sessionId in ipairs(candidates) do
        local summary = self.summaries[sessionId]
        local passesFilters = true

        if not summary then
            passesFilters = false
        end

        -- Filter: character (case-insensitive match for realm/name variations)
        if passesFilters and charKeys then
            local summaryKeyLower = string.lower(summary.charKey)
            local matched = false
            for k, _ in pairs(charKeys) do
                if k == summary.charKey or (type(k) == "string" and string.lower(k) == summaryKeyLower) then
                    matched = true
                    break
                end
            end
            if not matched then
                passesFilters = false
            end
        end

        -- Filter: zone
        if passesFilters and zone and summary.zone ~= zone then
            passesFilters = false
        end

        -- Filter: min gold/hr
        if passesFilters and summary.totalPerHour < minPerHour then
            passesFilters = false
        end

        -- Filter: min duration
        if passesFilters and (summary.durationSec or 0) < minDurationSec then
            passesFilters = false
        end

        -- Filter: short sessions
        if passesFilters and excludeShort and summary.isShort then
            passesFilters = false
        end

        -- Filter: archived sessions
        if passesFilters and excludeArchived and summary.isArchived then
            passesFilters = false
        end

        -- Filter: gathering flag
        if passesFilters and hasGathering and not summary.hasGathering then
            passesFilters = false
        end

        -- Filter: pickpocket flag
        if passesFilters and hasPickpocket and not summary.hasPickpocket then
            passesFilters = false
        end

        -- Phase 9: Filter: XP flag
        if passesFilters and onlyXP and not summary.hasXP then
            passesFilters = false
        end

        -- Phase 9: Filter: Rep flag
        if passesFilters and onlyRep and not summary.hasRep then
            passesFilters = false
        end

        -- Phase 9: Filter: Honor flag
        if passesFilters and onlyHonor and not summary.hasHonor then
            passesFilters = false
        end

        -- Filter: search text (match zone, character, or top item)
        if passesFilters and search ~= "" then
            local searchLower = search:lower()
            local matches = false

            if summary.zone:lower():find(searchLower, 1, true) then
                matches = true
            elseif summary.charKey:lower():find(searchLower, 1, true) then
                matches = true
            elseif summary.topItemName and summary.topItemName:lower():find(searchLower, 1, true) then
                matches = true
            end

            if not matches then
                passesFilters = false
            end
        end

        -- Add to results if passed all filters
        if passesFilters then
            table.insert(results, sessionId)
        end
    end

    return results
end

--------------------------------------------------
-- API: Get Summary
--------------------------------------------------
function pH_Index:GetSummary(sessionId)
    if self.stale then
        self:Build()
    end
    local s = self.summaries[sessionId]
    -- WoW SavedVariables may use string keys; try tonumber if lookup fails
    if not s and type(sessionId) == "string" then
        s = self.summaries[tonumber(sessionId)]
    elseif not s and type(sessionId) == "number" then
        s = self.summaries[tostring(sessionId)]
    end
    return s
end

--------------------------------------------------
-- API: Get Item Aggregates
--------------------------------------------------
function pH_Index:GetItemAggregates(filters)
    if self.stale then
        self:Build()
    end

    -- Optional filters (for future use)
    -- For now, return all items sorted by total value descending
    local items = {}
    for itemID, agg in pairs(self.itemAgg) do
        table.insert(items, agg)
    end

    table.sort(items, function(a, b)
        return a.totalValue > b.totalValue
    end)

    return items
end

--------------------------------------------------
-- API: Get Zone Aggregates
--------------------------------------------------
function pH_Index:GetZoneAggregates()
    if self.stale then
        self:Build()
    end
    return self.zoneAgg
end

--------------------------------------------------
-- API: Get Zone Stats (for start panel context)
--------------------------------------------------
function pH_Index:GetZoneStats(zoneName)
    if self.stale then
        self:Build()
    end
    
    local zoneAgg = self.zoneAgg[zoneName]
    if not zoneAgg then
        return nil  -- No data for this zone
    end
    
    -- Get last session in this zone (sorted by date descending)
    -- QuerySessions returns session IDs, so we need to fetch the actual session object
    local shortThreshold = 300
    if pH_Settings and pH_Settings.historyCleanup and pH_Settings.historyCleanup.shortThresholdSec then
        shortThreshold = pH_Settings.historyCleanup.shortThresholdSec
    end
    local zoneSessions = self:QuerySessions({
        zone = zoneName,
        sort = "date",
        excludeShort = true,
        minDurationSec = shortThreshold,
        excludeArchived = true,
    })
    local lastSession = nil
    if zoneSessions and zoneSessions[1] then
        local lastSessionId = zoneSessions[1]
        lastSession = pH_DB_Account.sessions[lastSessionId]
        if not lastSession and type(lastSessionId) == "number" then
            lastSession = pH_DB_Account.sessions[tostring(lastSessionId)]
        elseif not lastSession and type(lastSessionId) == "string" then
            lastSession = pH_DB_Account.sessions[tonumber(lastSessionId)]
        end
    end
    
    return {
        avgPerHour = zoneAgg.avgTotalPerHour,
        bestPerHour = zoneAgg.bestTotalPerHour,
        sessionCount = zoneAgg.sessionCount,
        lastSession = lastSession,  -- Now a session object, not an ID
        bestSessionId = zoneAgg.bestSessionId
    }
end

--------------------------------------------------
-- API: Get charKey for a session (same format as Index uses for filtering)
--------------------------------------------------
function pH_Index:GetCharKeyForSession(session)
    if not session then return "Unknown" end
    return GetCharKey(
        session.character or UnitName("player") or "Unknown",
        session.realm or GetRealmName() or "Unknown",
        session.faction or UnitFactionGroup("player") or "Unknown"
    )
end

--------------------------------------------------
-- API: Get current character key (same format as session charKeys)
--------------------------------------------------
function pH_Index:GetCurrentCharKey()
    local char = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    local faction = UnitFactionGroup("player") or "Unknown"
    return GetCharKey(char, realm, faction)
end

--------------------------------------------------
-- API: Mark Stale
--------------------------------------------------
function pH_Index:MarkStale()
    self.stale = true
end

--------------------------------------------------
-- API: Get All Zones (for dropdown)
--------------------------------------------------
function pH_Index:GetZones()
    if self.stale then
        self:Build()
    end

    local zones = {}
    for zone, _ in pairs(self.byZone) do
        table.insert(zones, zone)
    end

    table.sort(zones)
    return zones
end

--------------------------------------------------
-- API: Get All Characters (for dropdown)
--------------------------------------------------
function pH_Index:GetCharacters()
    if self.stale then
        self:Build()
    end

    local chars = {}
    for charKey, _ in pairs(self.byChar) do
        table.insert(chars, charKey)
    end

    table.sort(chars)
    return chars
end

-- Export module
_G.pH_Index = pH_Index
