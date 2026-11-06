--[[
    Insights.lua - Derived XP / reputation figures shared by the HUD tooltips and the
    session detail window (level ETA, recent averages, per-faction progress, potential rep).

    Pure data builders. ETA and faction progress read the live character (pH_API), so
    they only describe the active session.
]]

-- luacheck: globals pH_API
local pH_Insights = {}

local function FormatEtaInfinity()
    return "∞"
end

local function FormatEtaCompact(seconds)
    if not seconds or seconds <= 0 then
        return "<1m"
    end
    if seconds < 60 then
        return "<1m"
    end

    local totalMinutes = math.floor(seconds / 60)
    if totalMinutes < 60 then
        return string.format("%dm", totalMinutes)
    end

    local hours = math.floor(totalMinutes / 60)
    local minutes = totalMinutes % 60
    return string.format("%dh %02dm", hours, minutes)
end

local function FormatInt(value)
    local n = tonumber(value) or 0
    local isNegative = n < 0
    n = math.floor(math.abs(n))
    local s = tostring(n)
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    if isNegative then
        return "-" .. formatted
    end
    return formatted
end

local function GetStandingLabel(standingID)
    local globalLabel = _G["FACTION_STANDING_LABEL" .. tostring(standingID)]
    if globalLabel and globalLabel ~= "" then
        return globalLabel
    end
    local fallback = {
        [1] = "Hated",
        [2] = "Hostile",
        [3] = "Unfriendly",
        [4] = "Neutral",
        [5] = "Friendly",
        [6] = "Honored",
        [7] = "Revered",
        [8] = "Exalted",
    }
    return fallback[standingID] or "Unknown"
end

local function BuildXPEtaData(metrics)
    local maxLevel = pH_API:GetMaxPlayerLevel(70)
    local level = pH_API:GetPlayerLevel() or 0
    local currentXP = pH_API:GetXP() or 0
    local maxXP = pH_API:GetXPMax() or 0
    local remainingXP = math.max(0, maxXP - currentXP)
    local recentPerHour = metrics and (tonumber(metrics.xpEtaRecentPerHour) or tonumber(metrics.xpRecentPerHourBucketed) or 0) or 0
    local sessionPerHour = metrics and (tonumber(metrics.xpPerHour) or 0) or 0
    local sessionEtaEligible = metrics and (metrics.xpSessionEtaEligible and true or false) or false
    local etaAdjusted = metrics and (metrics.xpEtaAdjusted and true or false) or false
    local capped = level >= maxLevel
    local etaRecentSec = nil
    local etaSessionSec = nil
    if (not capped) and recentPerHour > 0 then
        etaRecentSec = math.floor((remainingXP / recentPerHour) * 3600)
    end
    if (not capped) and sessionPerHour > 0 and sessionEtaEligible then
        etaSessionSec = math.floor((remainingXP / sessionPerHour) * 3600)
    end

    if etaRecentSec and etaSessionSec and etaRecentSec < math.floor(etaSessionSec * 0.5) then
        etaRecentSec = math.floor(etaSessionSec * 0.5)
        etaAdjusted = true
    end

    if (not sessionEtaEligible) and etaSessionSec and etaRecentSec and etaSessionSec > etaRecentSec then
        -- Allow conservative upper bound before warm-up.
    elseif not sessionEtaEligible then
        etaSessionSec = nil
    end

    return {
        isCapped = capped,
        recentPerHour = recentPerHour,
        sessionPerHour = sessionPerHour,
        remainingXP = capped and 0 or remainingXP,
        etaRecentSec = etaRecentSec,
        etaSessionSec = etaSessionSec,
        etaAdjusted = etaAdjusted,
    }
end

local function BuildEtaRangeText(aSec, bSec)
    if not aSec and not bSec then
        return FormatEtaInfinity()
    end
    if aSec and (not bSec) then
        return FormatEtaCompact(aSec)
    end
    if bSec and (not aSec) then
        return FormatEtaCompact(bSec)
    end
    local lo = math.min(aSec, bSec)
    local hi = math.max(aSec, bSec)
    if lo == hi then
        return FormatEtaCompact(lo)
    end
    return string.format("%s - %s", FormatEtaCompact(lo), FormatEtaCompact(hi))
end

local function BuildRepTooltipModel(metrics, sessionAvgOverride, recentAvgOverride)
    local sessionAvg = tonumber(sessionAvgOverride) or (metrics and tonumber(metrics.repPerHour)) or 0
    local currentAvg = tonumber(recentAvgOverride) or (metrics and tonumber(metrics.repRecentPerHourBucketed)) or 0
    local gainedFactions = {}
    local sourceFactions = (metrics and metrics.repFactions) or (metrics and metrics.repTopFactions) or {}
    for i = 1, #sourceFactions do
        local row = sourceFactions[i]
        local name = row and row.name or nil
        local gain = row and tonumber(row.gain) or 0
        if name and name ~= "" and gain > 0 then
            local remainingRep = 0
            local nextStanding = "Unknown"
            local etaSessionText = FormatEtaInfinity()
            for _, rep in ipairs(pH_API:GetReputations()) do
                local factionName, standingID, barMax, barValue, isHeader = rep.name, rep.standingID, rep.max, rep.current, rep.isHeader
                if not isHeader and factionName == name then
                    local standing = tonumber(standingID) or 0
                    local isCapped = standing >= 8
                    remainingRep = math.max(0, (tonumber(barMax) or 0) - (tonumber(barValue) or 0))
                    nextStanding = GetStandingLabel(isCapped and standing or (standing + 1))
                    if (not isCapped) and sessionAvg > 0 then
                        etaSessionText = FormatEtaCompact(math.floor((remainingRep / sessionAvg) * 3600))
                    end
                    break
                end
            end
            table.insert(gainedFactions, {
                name = name,
                gain = gain,
                remainingRep = remainingRep,
                nextStanding = nextStanding,
                etaSessionText = etaSessionText,
            })
        end
    end

    local potentialByFaction = {}
    local potentialItems = (metrics and metrics.repPotentialItems) or {}
    for i = 1, #potentialItems do
        local item = potentialItems[i]
        if item then
            local itemName = item.itemName or "Rep Item"
            local count = tonumber(item.count) or 0
            local bundleSize = tonumber(item.bundleSize) or 1
            local targets = item.targets or {}
            for j = 1, #targets do
                local target = targets[j]
                local factionName = target and (target.factionKey or target.factionName) or nil
                local eligibleRep = target and (tonumber(target.eligibleRep) or tonumber(target.potentialRep)) or 0
                if factionName and factionName ~= "" and eligibleRep > 0 then
                    local row = potentialByFaction[factionName]
                    if not row then
                        row = {
                            factionName = factionName,
                            potentialRep = 0,
                            hints = {},
                        }
                        potentialByFaction[factionName] = row
                    end
                    row.potentialRep = row.potentialRep + eligibleRep
                    local hintKey = tostring(itemName)
                    local prevHint = row.hints[hintKey]
                    if (not prevHint) or eligibleRep > (prevHint.rep or 0) then
                        row.hints[hintKey] = {
                            itemName = itemName,
                            count = count,
                            bundleSize = bundleSize,
                            rep = eligibleRep,
                        }
                    end
                end
            end
        end
    end

    local potentialRows = {}
    for _, row in pairs(potentialByFaction) do
        table.insert(potentialRows, row)
    end

    if #potentialRows == 0 and metrics and metrics.repPotentialByFaction then
        for factionName, amount in pairs(metrics.repPotentialByFaction) do
            local value = tonumber(amount) or 0
            if value > 0 then
                table.insert(potentialRows, {
                    factionName = factionName,
                    potentialRep = value,
                })
            end
        end
    end

    table.sort(potentialRows, function(a, b)
        local av = tonumber(a.potentialRep) or 0
        local bv = tonumber(b.potentialRep) or 0
        if av == bv then
            return (a.factionName or "") < (b.factionName or "")
        end
        return av > bv
    end)
    while #potentialRows > 3 do
        table.remove(potentialRows)
    end

    for i = 1, #potentialRows do
        local row = potentialRows[i]
        local hintList = {}
        local hints = row.hints or {}
        for _, hint in pairs(hints) do
            table.insert(hintList, hint)
        end
        table.sort(hintList, function(a, b)
            local ar = tonumber(a.rep) or 0
            local br = tonumber(b.rep) or 0
            if ar == br then
                return (a.itemName or "") < (b.itemName or "")
            end
            return ar > br
        end)
        while #hintList > 2 do
            table.remove(hintList)
        end
        row.hintList = hintList
        row.hints = nil
    end

    return {
        sessionAvg = sessionAvg,
        currentAvg = currentAvg,
        gainedFactions = gainedFactions,
        potentialRows = potentialRows,
    }
end


pH_Insights.FormatEtaInfinity = FormatEtaInfinity
pH_Insights.FormatEtaCompact = FormatEtaCompact
pH_Insights.FormatInt = FormatInt
pH_Insights.BuildXPEtaData = BuildXPEtaData
pH_Insights.BuildEtaRangeText = BuildEtaRangeText
pH_Insights.BuildRepModel = BuildRepTooltipModel

_G.pH_Insights = pH_Insights
