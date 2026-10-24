--[[
    UI_History_Detail.lua - Detail pane with tabs for pH History

    Shows session details across 4 tabs: Summary, Items, Gathering, Compare
]]

-- luacheck: globals pH_Settings pH_Index pH_History pH_SessionManager pH_Ledger date time
local _, addon = ...
local PHUI = addon.UI.PHUI

-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local pH_History_Detail = {
    parent = nil,
    historyController = nil,

    -- Tab system
    tabs = {},
    activeTab = "summary",
    contentFrames = {},

    -- Current session
    currentSessionId = nil,
    currentSession = nil,
    currentMetrics = nil,

    -- "history" (archived, static) or "active" (in-progress session, live updates)
    mode = "history",
    live = false,
    liveFingerprint = nil,
}

local LIVE_TICK_SEC = 1.0

-- Item quality colors (WoW standard)
local QualityColors = {
    [0] = {0.6, 0.6, 0.6},  -- Poor (gray)
    [1] = {1, 1, 1},        -- Common (white)
    [2] = {0, 1, 0},        -- Uncommon (green)
    [3] = {0, 0.5, 1},      -- Rare (blue)
    [4] = {0.7, 0, 1},      -- Epic (purple)
    [5] = {1, 0.5, 0},      -- Legendary (orange)
}

--------------------------------------------------
-- Initialize
--------------------------------------------------
function pH_History_Detail:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    local tabNames = {
        {key = "summary", label = "Summary"},
        {key = "items", label = "Items"},
        {key = "gathering", label = "Gathering"},
        {key = "compare", label = "Compare"},
    }

    -- Tab strip (shared PHUI tabs)
    self.tabStrip = addon.UI.Tabs:Create(parent, {
        tabs = tabNames,
        tabWidth = 96,
        tabHeight = 24,
        onSelect = function(key) pH_History_Detail:ShowTab(key) end,
    })
    self.tabStrip.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)

    -- Content frames for each tab
    for _, tabInfo in ipairs(tabNames) do
        local contentFrame = CreateFrame("ScrollFrame", nil, parent)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -35)
        contentFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 5)
        contentFrame:Hide()

        local scrollChild = CreateFrame("Frame", nil, contentFrame)
        scrollChild:SetSize(math.max(1, contentFrame:GetWidth() or 1), 400)  -- Height grows with content
        contentFrame:SetScrollChild(scrollChild)
        contentFrame.scrollChild = scrollChild

        -- Keep the scroll child as wide as the viewport (anchors resolve after layout)
        contentFrame:SetScript("OnSizeChanged", function(_, w)
            if w and w > 0 then
                scrollChild:SetWidth(w)
                if tabInfo.key == "summary" and pH_History_Detail.summaryUI and pH_History_Detail.currentSession then
                    pH_History_Detail:UpdateSummary()
                end
            end
        end)

        contentFrame:EnableMouseWheel(true)
        contentFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 20)))
            self:SetVerticalScroll(newScroll)
        end)

        self.contentFrames[tabInfo.key] = contentFrame
    end

    -- Live ticker: child OnUpdate only runs while the pane is visible.
    local ticker = CreateFrame("Frame", nil, parent)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        if not pH_History_Detail.live then return end
        elapsed = elapsed + dt
        if elapsed < LIVE_TICK_SEC then return end
        elapsed = 0
        pH_History_Detail:LiveTick()
    end)

    -- Restore the last tab (default: summary)
    local saved = pH_Settings and pH_Settings.historyActiveTab
    if not (saved and self.contentFrames[saved]) then saved = "summary" end
    self:SwitchTab(saved)
end

--------------------------------------------------
-- Switch Tab (public) / ShowTab (strip callback)
--------------------------------------------------
function pH_History_Detail:SwitchTab(tabKey)
    self.tabStrip:Select(tabKey)  -- paints the strip and calls ShowTab
end

function pH_History_Detail:ShowTab(tabKey)
    for _, frame in pairs(self.contentFrames) do
        frame:Hide()
    end
    self.activeTab = tabKey
    self.contentFrames[tabKey]:Show()
    self:RenderActiveTab()
    if pH_Settings then
        pH_Settings.historyActiveTab = tabKey
    end
end

--------------------------------------------------
-- Set Session (called when user selects a session)
--------------------------------------------------
function pH_History_Detail:SetSession(sessionId)
    local session = pH_SessionManager:GetSession(sessionId)
    self:ShowSession(session, { mode = "history" })
    self.currentSessionId = sessionId
end

--------------------------------------------------
-- Show Session (archived or active; same renderers for both)
-- options: { mode = "history" | "active", live = boolean }
-- Active sessions are read straight from SessionManager - never copied or archived.
--------------------------------------------------
function pH_History_Detail:ShowSession(session, options)
    options = options or {}
    self.mode = options.mode or "history"
    self.live = options.live == true and self.mode == "active"
    self.currentSession = session
    self.currentSessionId = session and session.id or nil
    self.currentMetrics = session and pH_SessionManager:GetMetrics(session) or nil
    self.liveFingerprint = self.currentMetrics and self:ComputeFingerprint(session, self.currentMetrics) or nil

    self:RenderActiveTab()
end

-- Re-resolve the current session (after an edit such as zone rename).
function pH_History_Detail:Refresh()
    if self.mode == "active" then
        self:ShowSession(pH_SessionManager:GetActiveSession(), { mode = "active", live = true })
    else
        self:SetSession(self.currentSessionId)
    end
end

-- Cheap change detector: totals only (rates drift every second and would force rebuilds).
function pH_History_Detail:ComputeFingerprint(session, metrics)
    return table.concat({
        tostring(metrics.totalValue or 0),
        tostring(metrics.xpGained or 0),
        tostring(metrics.repGained or 0),
        tostring(metrics.honorGained or 0),
        tostring(session.pausedAt ~= nil),
        tostring(session.zone or ""),
        tostring(session.activityLog and #session.activityLog or 0),
        tostring(session.metricHistory and session.metricHistory.lastSampleAt or 0),
    }, "|")
end

-- Called ~1/sec while an active session is displayed and the pane is visible.
function pH_History_Detail:LiveTick()
    if self.mode ~= "active" then return end

    local active = pH_SessionManager:GetActiveSession()
    local shown = self.currentSession

    if active and shown and active.id == shown.id then
        local metrics = pH_SessionManager:GetMetrics(active)
        self.currentSession = active
        self.currentMetrics = metrics
        local fp = self:ComputeFingerprint(active, metrics)
        if fp ~= self.liveFingerprint then
            self.liveFingerprint = fp
            self:RenderActiveTab()
        elseif self.activeTab == "summary" then
            self:UpdateSummaryClock()
        end
        return
    end

    if active then
        -- A different session started while the detail was open.
        self:ShowSession(active, { mode = "active", live = true })
        return
    end

    -- Session ended (stopped/archived or reset).
    local finalized = shown and pH_SessionManager:GetSession(shown.id)
    if pH_History and pH_History.OnActiveSessionEnded then
        pH_History:OnActiveSessionEnded(finalized)
    elseif finalized then
        self:SetSession(finalized.id)
    else
        self:ShowSession(nil, { mode = "active", live = true })
    end
end

--------------------------------------------------
-- Render Active Tab
--------------------------------------------------
function pH_History_Detail:RenderActiveTab()
    if not self.currentSession or not self.currentMetrics then
        self:RenderEmptyState()
        return
    end

    if self.activeTab == "summary" then
        self:RenderSummaryTab()
    elseif self.activeTab == "items" then
        self:RenderItemsTab()
    elseif self.activeTab == "gathering" then
        self:RenderGatheringTab()
    elseif self.activeTab == "compare" then
        self:RenderCompareTab()
    end
end

--------------------------------------------------
-- Clear Content Helper
--------------------------------------------------
local function ClearScrollChild(scrollChild)
    -- Hide all children
    local children = {scrollChild:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:ClearAllPoints()
    end

    -- Hide all font strings
    local regions = {scrollChild:GetRegions()}
    for _, region in ipairs(regions) do
        if region.GetText then  -- It's a FontString
            region:Hide()
            region:ClearAllPoints()
        end
    end
end

--------------------------------------------------
-- Render Empty State
--------------------------------------------------
function pH_History_Detail:RenderEmptyState()
    local frame = self.contentFrames[self.activeTab]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local emptyText = scrollChild.emptyText
    if not emptyText then
        emptyText = PHUI.CreateLabel(scrollChild, "disabled", "", PHUI.Fonts.NORMAL)
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        scrollChild.emptyText = emptyText
    end
    emptyText:SetText(self.mode == "active" and "No active session" or "No session selected")
    emptyText:Show()
end

--------------------------------------------------
-- Render Items Tab
--------------------------------------------------
function pH_History_Detail:RenderItemsTab()
    local frame = self.contentFrames["items"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession

    -- Check if session has items
    if not session.items or next(session.items) == nil then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("No items looted in this session")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    -- Convert items table to sorted array
    local itemsArray = {}
    for itemID, itemData in pairs(session.items) do
        table.insert(itemsArray, itemData)
    end

    -- Sort by total value descending
    table.sort(itemsArray, function(a, b)
        return a.expectedTotal > b.expectedTotal
    end)

    local yOffset = -10

    -- Add header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Items Looted")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Column headers
    local colHeaders = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHeaders:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    colHeaders:SetText("Item Name")
    colHeaders:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colQty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colQty:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -150, yOffset)
    colQty:SetText("Qty")
    colQty:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colValue = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colValue:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -50, yOffset)
    colValue:SetText("Value")
    colValue:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Render each item
    for _, itemData in ipairs(itemsArray) do
        -- Item name with quality color
        local itemName = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemName:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        itemName:SetText(itemData.name or "Unknown Item")
        itemName:SetJustifyH("LEFT")

        -- Apply quality color
        local quality = itemData.quality or 1
        local qColor = QualityColors[quality] or QualityColors[1]
        itemName:SetTextColor(qColor[1], qColor[2], qColor[3])

        -- Quantity
        local qtyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -150, yOffset)
        qtyText:SetText(tostring(itemData.countLooted or itemData.count))
        qtyText:SetJustifyH("RIGHT")

        -- Value
        local valueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
        valueText:SetText(pH_Ledger:FormatMoneyShort(itemData.expectedTotal))
        valueText:SetJustifyH("RIGHT")

        yOffset = yOffset - 16
    end

    -- Summary at bottom
    yOffset = yOffset - 10
    local totalItems = 0
    local totalValue = 0
    for _, itemData in ipairs(itemsArray) do
        totalItems = totalItems + (itemData.countLooted or itemData.count)
        totalValue = totalValue + itemData.expectedTotal
    end

    local summaryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    summaryText:SetText(string.format("Total: %d items worth %s",
        totalItems,
        pH_Ledger:FormatMoney(totalValue)))
    summaryText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    yOffset = yOffset - 20

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Render Gathering Tab
--------------------------------------------------
function pH_History_Detail:RenderGatheringTab()
    local frame = self.contentFrames["gathering"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics

    -- Check if session has gathering data
    if not session.gathering or not session.gathering.totalNodes or session.gathering.totalNodes == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("No gathering data for this session")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    local yOffset = -10

    -- Add header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Gathering Statistics")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Total nodes summary
    local totalNodes = session.gathering.totalNodes
    local nodesPerHour = 0
    if metrics.durationHours > 0 then
        nodesPerHour = math.floor(totalNodes / metrics.durationHours)
    end

    local summaryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    summaryText:SetText(string.format("Total Nodes: %d  |  Nodes/Hour: %d", totalNodes, nodesPerHour))
    summaryText:SetTextColor(pH_Colors.ACCENT_GOOD[1], pH_Colors.ACCENT_GOOD[2], pH_Colors.ACCENT_GOOD[3])
    yOffset = yOffset - 25

    -- Node breakdown header
    local breakdownHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    breakdownHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    breakdownHeader:SetText("Node Breakdown")
    breakdownHeader:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 20

    -- Column headers
    local colNode = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNode:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    colNode:SetText("Node Type")
    colNode:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colCount = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colCount:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -100, yOffset)
    colCount:SetText("Count")
    colCount:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colPercent = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colPercent:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
    colPercent:SetText("% of Total")
    colPercent:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Sort nodes by count
    local nodesArray = {}
    if session.gathering.nodesByType then
        for nodeName, count in pairs(session.gathering.nodesByType) do
            table.insert(nodesArray, {name = nodeName, count = count})
        end
    end

    table.sort(nodesArray, function(a, b)
        return a.count > b.count
    end)

    -- Render each node type
    for _, nodeData in ipairs(nodesArray) do
        local nodeName = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nodeName:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        nodeName:SetText(nodeData.name)
        nodeName:SetJustifyH("LEFT")

        local nodeCount = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nodeCount:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -100, yOffset)
        nodeCount:SetText(tostring(nodeData.count))
        nodeCount:SetJustifyH("RIGHT")

        local percent = math.floor((nodeData.count / totalNodes) * 100)
        local percentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        percentText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
        percentText:SetText(percent .. "%")
        percentText:SetJustifyH("RIGHT")

        yOffset = yOffset - 16
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Helper: Format percentage difference
--------------------------------------------------
local function FormatPercentDiff(current, baseline)
    if baseline == 0 then return "N/A" end
    local diff = current - baseline
    local percent = math.floor((diff / baseline) * 100)

    if percent > 0 then
        return string.format("|cff00ff00^%d%%|r", percent)  -- Green up arrow
    elseif percent < 0 then
        return string.format("|cffff0000v%d%%|r", math.abs(percent))  -- Red down arrow
    else
        return "|cff888888=0%|r"  -- Gray equals for equal
    end
end

--------------------------------------------------
-- Render Compare Tab
--------------------------------------------------
function pH_History_Detail:RenderCompareTab()
    local frame = self.contentFrames["compare"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics

    -- Get zone aggregates
    local zoneAgg = pH_Index:GetZoneAggregates()
    local thisZone = session.zone or "Unknown"
    local zoneStats = zoneAgg[thisZone]

    -- Check if we have comparison data
    if not zoneStats or zoneStats.sessionCount < 2 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("Not enough sessions in this zone for comparison\n(Need at least 2 sessions)")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    local yOffset = -10

    -- Header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Zone Performance Comparison")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Subheader
    local subheader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subheader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    subheader:SetText(string.format("Comparing against %d session%s in %s",
        zoneStats.sessionCount - 1,  -- Exclude current session
        (zoneStats.sessionCount - 1) ~= 1 and "s" or "",
        thisZone))
    subheader:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    yOffset = yOffset - 25

    -- Comparison table header
    local function AddComparisonRow(label, thisValue, avgValue, bestValue)
        -- Label
        local labelText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        labelText:SetText(label)
        labelText:SetJustifyH("LEFT")

        -- This session value
        local thisText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        thisText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 180, yOffset)
        thisText:SetText(thisValue)
        thisText:SetJustifyH("LEFT")

        -- Zone average
        local avgText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avgText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 250, yOffset)
        avgText:SetText(avgValue)
        avgText:SetJustifyH("LEFT")
        avgText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        -- Difference
        local diffText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 320, yOffset)

        -- Calculate numeric values for comparison
        local thisNumeric = tonumber(thisValue:match("%d+")) or 0
        local avgNumeric = tonumber(avgValue:match("%d+")) or 0
        diffText:SetText(FormatPercentDiff(thisNumeric, avgNumeric))
        diffText:SetJustifyH("LEFT")

        yOffset = yOffset - 18
    end

    -- Column headers
    local colThis = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colThis:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 180, yOffset)
    colThis:SetText("This")
    colThis:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colAvg = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colAvg:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 250, yOffset)
    colAvg:SetText("Zone Avg")
    colAvg:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colDiff = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colDiff:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 320, yOffset)
    colDiff:SetText("Diff")
    colDiff:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Gold/hour comparison
    AddComparisonRow(
        "Total g/hr",
        pH_Ledger:FormatMoneyShort(metrics.totalPerHour),
        pH_Ledger:FormatMoneyShort(zoneStats.avgTotalPerHour),
        nil
    )

    AddComparisonRow(
        "Gold g/hr",
        pH_Ledger:FormatMoneyShort(metrics.cashPerHour),
        "N/A",  -- We don't track cash avg in zoneAgg yet
        nil
    )

    AddComparisonRow(
        "Expected g/hr",
        pH_Ledger:FormatMoneyShort(metrics.expectedPerHour),
        "N/A",  -- We don't track expected avg in zoneAgg yet
        nil
    )

    -- Gathering comparison (if applicable)
    if session.gathering and session.gathering.totalNodes > 0 and zoneStats.avgNodesPerHour > 0 then
        yOffset = yOffset - 10

        local nodesPerHour = 0
        if metrics.durationHours > 0 then
            nodesPerHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end

        AddComparisonRow(
            "Nodes/hr",
            tostring(nodesPerHour),
            tostring(math.floor(zoneStats.avgNodesPerHour)),
            nil
        )
    end

    yOffset = yOffset - 15

    -- Insights section
    local insightsHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    insightsHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    insightsHeader:SetText("Insights")
    insightsHeader:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 20

    -- Calculate rank in zone
    local threshold = 300
    if pH_Settings and pH_Settings.historyCleanup and pH_Settings.historyCleanup.shortThresholdSec then
        threshold = pH_Settings.historyCleanup.shortThresholdSec
    end
    local allZoneSessions = pH_Index:QuerySessions({
        zone = thisZone,
        sort = "totalPerHour",
        excludeShort = true,
        minDurationSec = threshold,
        excludeArchived = true,
    }) or {}
    local rank = 1
    for _, otherSessionId in ipairs(allZoneSessions) do
        if otherSessionId ~= session.id then
            local otherSummary = pH_Index:GetSummary(otherSessionId)
            if otherSummary and otherSummary.totalPerHour > metrics.totalPerHour then
                rank = rank + 1
            end
        end
    end

    -- Insight: Performance vs average
    local perfDiff = metrics.totalPerHour - zoneStats.avgTotalPerHour
    local perfPercent = math.floor((perfDiff / zoneStats.avgTotalPerHour) * 100)
    local perfInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    perfInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)

    if perfPercent > 10 then
        perfInsight:SetText(string.format("* Great session! %d%% above zone average", perfPercent))
        perfInsight:SetTextColor(pH_Colors.ACCENT_GOOD[1], pH_Colors.ACCENT_GOOD[2], pH_Colors.ACCENT_GOOD[3])
    elseif perfPercent < -10 then
        perfInsight:SetText(string.format("* Below average by %d%% - room for improvement", math.abs(perfPercent)))
        perfInsight:SetTextColor(pH_Colors.ACCENT_BAD[1], pH_Colors.ACCENT_BAD[2], pH_Colors.ACCENT_BAD[3])
    else
        perfInsight:SetText("* Performing close to zone average")
        perfInsight:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    end
    yOffset = yOffset - 18

    -- Insight: Rank
    local rankInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    rankInsight:SetText(string.format("* Ranked #%d of %d sessions in this zone", rank, #allZoneSessions))
    rankInsight:SetTextColor(pH_Colors.TEXT_PRIMARY[1], pH_Colors.TEXT_PRIMARY[2], pH_Colors.TEXT_PRIMARY[3])
    yOffset = yOffset - 18

    -- Insight: Best session reference
    if zoneStats.bestSessionId and zoneStats.bestSessionId ~= session.id then
        local bestInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bestInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        bestInsight:SetText(string.format("* Best session in zone: %s/hr (Session #%d)",
            pH_Ledger:FormatMoneyShort(zoneStats.bestTotalPerHour),
            zoneStats.bestSessionId))
        bestInsight:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        yOffset = yOffset - 18
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

-- Export module
_G.pH_History_Detail = pH_History_Detail
