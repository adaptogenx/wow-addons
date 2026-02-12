--[[
    Index.lua - Data indexing and query engine for GoldPH History

    Builds fast lookup indexes and cached summaries for efficient querying
    of historical sessions. Designed for scalability (100+ sessions).
]]

-- luacheck: globals GoldPH_DB_Account GetRealmName UnitFactionGroup UnitName

local GoldPH_Index = {
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
-- Helper: Get character key
--------------------------------------------------
local function GetCharKey(character, realm, faction)
    return character .. "-" .. realm .. "-" .. faction
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
function GoldPH_Index:Build()
    local startTime = GetTime()

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

    -- Track processed session IDs to prevent duplicates
    local processedSessions = {}

    -- Scan all sessions (skip active session)
    for sessionId, session in pairs(GoldPH_DB_Account.sessions) do
        -- Skip if already processed (prevent duplicates)
        if processedSessions[sessionId] then
            if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format("[GoldPH Index] Warning: Duplicate session ID %d detected, skipping", sessionId))
            end
        else
            processedSessions[sessionId] = true
            
            -- Skip if this is the active session (should not be in history)
            local shouldProcess = true
            if GoldPH_DB_Account.activeSession and GoldPH_DB_Account.activeSession.id == sessionId then
                shouldProcess = false
            end

            -- Get metrics using SessionManager (source of truth)
            local metrics
            if shouldProcess then
                metrics = GoldPH_SessionManager:GetMetrics(session)
                if not metrics then
                    shouldProcess = false
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
            local summary = {
                id = sessionId,
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

            -- Store summary
            self.summaries[sessionId] = summary
            table.insert(self.sessions, sessionId)

            -- Build byZone index
            local zone = summary.zone
            if not self.byZone[zone] then
                self.byZone[zone] = {}
            end
            table.insert(self.byZone[zone], sessionId)

            -- Build byChar index
            if not self.byChar[charKey] then
                self.byChar[charKey] = {}
            end
            table.insert(self.byChar[charKey], sessionId)

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
                zt.bestSessionId = sessionId
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
            end  -- Close shouldProcess
        end  -- Close processedSessions check
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

    -- Build sorted arrays (deduplicate sessionIds first)
    -- Create a set to track seen session IDs
    local seen = {}
    local uniqueSessions = {}
    for _, sessionId in ipairs(self.sessions) do
        if not seen[sessionId] then
            seen[sessionId] = true
            table.insert(uniqueSessions, sessionId)
        end
    end
    self.sessions = uniqueSessions

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
    if GoldPH_DB_Account and GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH Index] Built index with %d sessions in %.3fs", #self.sessions, buildTime))
    end
end

--------------------------------------------------
-- Core: Query Sessions
--------------------------------------------------
function GoldPH_Index:QuerySessions(filters)
    -- Rebuild if stale
    if self.stale then
        self:Build()
    end

    -- Default filters
    filters = filters or {}
    local sort = filters.sort or "totalPerHour"
    local sortDesc = filters.sortDesc ~= false  -- Default true
    local search = filters.search or ""
    local charKeys = filters.charKeys  -- nil = all, else {charKey1=true, ...}
    local zone = filters.zone  -- nil = any
    local minPerHour = filters.minPerHour or 0
    local hasGathering = filters.hasGathering or false
    local hasPickpocket = filters.hasPickpocket or false
    local onlyXP = filters.onlyXP or false
    local onlyRep = filters.onlyRep or false
    local onlyHonor = filters.onlyHonor or false

    -- Start with pre-sorted base list
    local candidates = self.sorted[sort] or self.sorted.totalPerHour

    -- Single-pass filtering
    local results = {}
    for _, sessionId in ipairs(candidates) do
        local summary = self.summaries[sessionId]
        local passesFilters = true

        if not summary then
            passesFilters = false
        end

        -- Filter: character
        if passesFilters and charKeys and not charKeys[summary.charKey] then
            passesFilters = false
        end

        -- Filter: zone
        if passesFilters and zone and summary.zone ~= zone then
            passesFilters = false
        end

        -- Filter: min gold/hr
        if passesFilters and summary.totalPerHour < minPerHour then
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
function GoldPH_Index:GetSummary(sessionId)
    if self.stale then
        self:Build()
    end
    return self.summaries[sessionId]
end

--------------------------------------------------
-- API: Get Item Aggregates
--------------------------------------------------
function GoldPH_Index:GetItemAggregates(filters)
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
function GoldPH_Index:GetZoneAggregates()
    if self.stale then
        self:Build()
    end
    return self.zoneAgg
end

--------------------------------------------------
-- API: Mark Stale
--------------------------------------------------
function GoldPH_Index:MarkStale()
    self.stale = true
end

--------------------------------------------------
-- API: Get All Zones (for dropdown)
--------------------------------------------------
function GoldPH_Index:GetZones()
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
function GoldPH_Index:GetCharacters()
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
_G.GoldPH_Index = GoldPH_Index
