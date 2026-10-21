--[[
    UI_History_Detail.lua - Detail pane with tabs for GoldPH History

    Shows session details across 4 tabs: Summary, Items, Gathering, Compare
]]

-- luacheck: globals GoldPH_Settings
-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local GoldPH_History_Detail = {
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
}

-- Item quality colors (WoW standard)
local QualityColors = {
    [0] = {0.6, 0.6, 0.6},  -- Poor (gray)
    [1] = {1, 1, 1},        -- Common (white)
    [2] = {0, 1, 0},        -- Uncommon (green)
    [3] = {0, 0.5, 1},      -- Rare (blue)
    [4] = {0.7, 0, 1},      -- Epic (purple)
    [5] = {1, 0.5, 0},      -- Legendary (orange)
}

local METRIC_ICONS = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    xp = "Interface\\Icons\\INV_Misc_Book_11",
    rep = "Interface\\Icons\\INV_Misc_Ribbon_01",
    honor = "Interface\\Icons\\inv_bannerpvp_02",
}

local METRIC_LABELS = {
    gold = "GOLD / HOUR",
    xp = "XP / HOUR",
    rep = "REP / HOUR",
    honor = "HONOR / HOUR",
}

local METRIC_COLORS = {
    gold = pH_Colors.METRIC_GOLD,
    xp = pH_Colors.METRIC_XP,
    rep = pH_Colors.METRIC_REP,
    honor = pH_Colors.METRIC_HONOR,
}

--------------------------------------------------
-- Initialize
--------------------------------------------------
function GoldPH_History_Detail:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    -- Create tab buttons (4 tabs)
    local tabNames = {
        {key = "summary", label = "Summary"},
        {key = "items", label = "Items"},
        {key = "gathering", label = "Gathering"},
        {key = "compare", label = "Compare"},
    }

    local tabWidth = 90
    local tabHeight = 25
    local tabSpacing = 2

    for i, tabInfo in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(tabWidth, tabHeight)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 5 + (i - 1) * (tabWidth + tabSpacing), -5)
        tab:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2}
        })
        local PH_BG_DARK = pH_Colors.BG_DARK
        local PH_DIVIDER = pH_Colors.DIVIDER
        tab:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.80)
        tab:SetBackdropBorderColor(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], 0.60)

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("CENTER")
        tabText:SetText(tabInfo.label)
        tab.text = tabText
        tab.key = tabInfo.key

        tab:SetScript("OnClick", function()
            GoldPH_History_Detail:SwitchTab(tabInfo.key)
        end)

        self.tabs[tabInfo.key] = tab
    end

    -- Create content frames for each tab
    for _, tabInfo in ipairs(tabNames) do
        local contentFrame = CreateFrame("ScrollFrame", nil, parent)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -35)
        contentFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 5)
        contentFrame:Hide()

        -- Scroll child
        local scrollChild = CreateFrame("Frame", nil, contentFrame)
        local scrollWidth = contentFrame:GetWidth() - 10
        scrollChild:SetSize(scrollWidth, 400)  -- Will expand as needed
        contentFrame:SetScrollChild(scrollChild)
        contentFrame.scrollChild = scrollChild

        -- Enable mouse wheel scrolling
        contentFrame:EnableMouseWheel(true)
        contentFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 20)))
            self:SetVerticalScroll(newScroll)
        end)

        self.contentFrames[tabInfo.key] = contentFrame
    end

    -- Show summary tab by default
    self:SwitchTab("summary")
end

--------------------------------------------------
-- Switch Tab
--------------------------------------------------
function GoldPH_History_Detail:SwitchTab(tabKey)
    -- Update tab appearance
    local SELECTED = pH_Colors.SELECTED
    local TEXT_PRIMARY = pH_Colors.TEXT_PRIMARY
    local PH_BG_DARK = pH_Colors.BG_DARK
    local TEXT_MUTED = pH_Colors.TEXT_MUTED

    for key, tab in pairs(self.tabs) do
        if key == tabKey then
            tab:SetBackdropColor(SELECTED[1], SELECTED[2], SELECTED[3], 1)
            tab.text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
        else
            tab:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.80)
            tab.text:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
        end
    end

    -- Hide all content frames
    for key, frame in pairs(self.contentFrames) do
        frame:Hide()
    end

    -- Show active content frame
    self.activeTab = tabKey
    self.contentFrames[tabKey]:Show()

    -- Render tab content
    self:RenderActiveTab()

    -- Save active tab preference
    if GoldPH_Settings then
        GoldPH_Settings.historyActiveTab = tabKey
    end
end

--------------------------------------------------
-- Set Session (called when user selects a session)
--------------------------------------------------
function GoldPH_History_Detail:SetSession(sessionId)
    self.currentSessionId = sessionId
    self.currentSession = GoldPH_SessionManager:GetSession(sessionId)
    self.currentMetrics = self.currentSession and GoldPH_SessionManager:GetMetrics(self.currentSession) or nil

    -- Render active tab
    self:RenderActiveTab()
end

--------------------------------------------------
-- Render Active Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderActiveTab()
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
function GoldPH_History_Detail:RenderEmptyState()
    local frame = self.contentFrames[self.activeTab]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER")
    emptyText:SetText("No session selected")
    emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
end

--------------------------------------------------
-- Helper: Format friendly date
--------------------------------------------------
local function FormatFriendlyDate(timestamp)
    if not timestamp then return "Unknown" end

    local now = time()
    local diff = now - timestamp

    -- Less than 1 hour ago
    if diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. " min" .. (mins ~= 1 and "s" or "") .. " ago"
    end

    -- Less than 24 hours ago
    if diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. " hour" .. (hours ~= 1 and "s" or "") .. " ago"
    end

    -- Less than 7 days ago
    if diff < 604800 then
        local days = math.floor(diff / 86400)
        return days .. " day" .. (days ~= 1 and "s" or "") .. " ago"
    end

    -- More than 7 days: show date
    return date("%b %d, %Y", timestamp)
end

--------------------------------------------------
-- Metric history helpers (expanded cards)
--------------------------------------------------
local function GetMetricHistory(session)
    return session and session.metricHistory or nil
end

local function GetMetricBuffer(history, metricKey)
    if not history or not history.metrics then return nil end
    return history.metrics[metricKey]
end

local function GetBufferSample(buffer, offsetFromLatest)
    if not buffer or buffer.count == 0 then return nil end
    if offsetFromLatest >= buffer.count then return nil end
    local index = buffer.head - offsetFromLatest
    if index <= 0 then
        index = index + buffer.capacity
    end
    return buffer.samples[index]
end

local function ComputePeak(buffer, maxSamples)
    if not buffer or buffer.count == 0 then return 0 end
    local peak = 0
    local count = buffer.count
    if maxSamples and maxSamples < count then
        count = maxSamples
    end
    for i = 0, count - 1 do
        local v = GetBufferSample(buffer, i) or 0
        if v > peak then
            peak = v
        end
    end
    return peak
end

local function FormatMetricRate(metricKey, rate)
    if metricKey == "gold" then
        return GoldPH_Ledger:FormatMoneyShort(rate) .. "/hr"
    end
    if metricKey == "xp" or metricKey == "honor" then
        if rate >= 1000 then
            return string.format("%.1fk/hr", rate / 1000)
        end
        return string.format("%d/hr", rate)
    end
    if metricKey == "rep" then
        return string.format("%d/hr", rate)
    end
    return tostring(rate)
end

local function FormatMetricTotal(metricKey, total)
    if metricKey == "gold" then
        return GoldPH_Ledger:FormatMoney(total)
    end
    return tostring(total)
end

--------------------------------------------------
-- Render Summary Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderSummaryTab()
    local frame = self.contentFrames["summary"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics
    local cfg = GoldPH_Settings and GoldPH_Settings.metricCards or {}
    local showInactive = cfg.showInactive == true
    local sparklineMinutes = cfg.sparklineMinutes or 15
    local yOffset = -10

    local headerText = scrollChild.headerText
    if not headerText then
        headerText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        scrollChild.headerText = headerText
    end
    headerText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    headerText:SetText("Session #" .. session.id .. " - " .. (session.zone or "Unknown"))
    headerText:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    headerText:Show()
    yOffset = yOffset - 20

    local subText = scrollChild.subText
    if not subText then
        subText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        scrollChild.subText = subText
    end
    subText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    subText:SetText(string.format("Started %s  |  Duration %s",
        FormatFriendlyDate(session.startedAt),
        GoldPH_SessionManager:FormatDuration(metrics.durationSec)))
    subText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    subText:Show()
    yOffset = yOffset - 20

    local metricContainer = scrollChild.metricContainer
    if not metricContainer then
        metricContainer = CreateFrame("Frame", nil, scrollChild)
        scrollChild.metricContainer = metricContainer
    end
    metricContainer:ClearAllPoints()
    metricContainer:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    metricContainer:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
    metricContainer:Show()

    local history = GetMetricHistory(session)
    local metricData = {}
    local metricOrder = { "gold", "xp", "rep", "honor" }
    local metricMap = {}

    local function AddMetric(metricKey, isActive, rate, total)
        -- Always add all 4 metrics, even if no data
        local buffer = GetMetricBuffer(history, metricKey)
        local maxSamples = nil
        if history and history.sampleInterval then
            maxSamples = math.floor((sparklineMinutes * 60) / history.sampleInterval)
            if maxSamples <= 0 then maxSamples = nil end
        end
        local peak = buffer and ComputePeak(buffer, maxSamples) or rate
        local data = {
            key = metricKey,
            label = METRIC_LABELS[metricKey],
            icon = METRIC_ICONS[metricKey],
            color = METRIC_COLORS[metricKey],
            rate = rate or 0,
            total = total or 0,
            peak = peak or 0,
            buffer = buffer,
            maxSamples = maxSamples,
            isActive = isActive,
        }
        table.insert(metricData, data)
        metricMap[metricKey] = data
    end

    -- Always show all 4 metric cards
    AddMetric("gold", true, metrics.totalPerHour or 0, metrics.totalValue or 0)
    AddMetric("xp", metrics.xpEnabled and metrics.xpGained > 0, metrics.xpPerHour or 0, metrics.xpGained or 0)
    AddMetric("rep", metrics.repEnabled and metrics.repGained > 0, metrics.repPerHour or 0, metrics.repGained or 0)
    AddMetric("honor", metrics.honorEnabled and metrics.honorGained > 0, metrics.honorPerHour or 0, metrics.honorGained or 0)

    local containerWidth = (frame:GetWidth() > 0 and frame:GetWidth() or 380) - 20
    local cardGap = 10
    local cardHeight = 110
    local cardWidth = containerWidth  -- luacheck: ignore 311
    if #metricData > 1 then
        cardWidth = math.floor((containerWidth - cardGap) / 2)
    else
        cardWidth = math.min(260, containerWidth)
    end

    local function EnsureSparkline(frame, barCount)
        if frame.bars then return end
        frame.bars = {}
        frame.barCount = barCount
        for i = 1, barCount do
            local bar = frame:CreateTexture(nil, "ARTWORK")
            bar:SetColorTexture(1, 1, 1, 0.7)
            frame.bars[i] = bar
        end
    end

    local function UpdateSparkline(frame, buffer, barColor, height, maxSamples)
        if not frame or not frame.bars then return end
        local barCount = frame.barCount or 12
        local width = frame:GetWidth()
        if not width or width <= 0 then
            local parent = frame:GetParent()
            if parent and parent.GetWidth then
                local insetLeft = frame.insetLeft or 8
                local insetRight = frame.insetRight or 8
                width = parent:GetWidth() - insetLeft - insetRight
            end
        end
        if not width or width <= 0 then
            -- First paint can occur before anchors resolve. Retry once next frame.
            if C_Timer and C_Timer.After then
                frame._sparklinePending = {
                    buffer = buffer,
                    barColor = barColor,
                    height = height,
                    maxSamples = maxSamples,
                }
                if not frame._sparklineRetryQueued then
                    frame._sparklineRetryQueued = true
                    C_Timer.After(0, function()
                        if not frame then return end
                        frame._sparklineRetryQueued = nil
                        local pending = frame._sparklinePending
                        if not pending then return end
                        frame._sparklinePending = nil
                        UpdateSparkline(
                            frame,
                            pending.buffer,
                            pending.barColor,
                            pending.height,
                            pending.maxSamples
                        )
                    end)
                end
            end
            return
        end
        local gap = 2
        local barWidth = math.max(1, math.floor((width - (gap * (barCount - 1))) / barCount))
        local maxValue = 0
        local available = buffer and buffer.count or 0
        if maxSamples and maxSamples < available then
            available = maxSamples
        end
        local span = math.max(1, available)
        for i = 0, barCount - 1 do
            local offset = math.floor((i / barCount) * (span - 1))
            local v = buffer and GetBufferSample(buffer, offset) or 0
            if v > maxValue then maxValue = v end
        end
        if maxValue == 0 then maxValue = 1 end
        for i = 1, barCount do
            local offset = math.floor(((barCount - i) / barCount) * (span - 1))
            local v = buffer and GetBufferSample(buffer, offset) or 0
            local normalized = math.min(math.max(v / maxValue, 0), 1)
            local barHeight = math.max(2, math.floor(height * normalized))
            local bar = frame.bars[i]
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", (i - 1) * (barWidth + gap), 0)
            bar:SetSize(barWidth, barHeight)
            bar:SetColorTexture(barColor[1], barColor[2], barColor[3], barColor[4] or 0.85)
            bar:Show()
        end
    end

    local function EnsureCard(metricKey)
        scrollChild.metricCards = scrollChild.metricCards or {}
        local card = scrollChild.metricCards[metricKey]
        if card then
            return card
        end
        card = CreateFrame("Button", nil, metricContainer, "BackdropTemplate")
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 12,
            insets = {left = 3, right = 3, top = 3, bottom = 3},
        })
        card:SetBackdropColor(pH_Colors.BG_DARK[1], pH_Colors.BG_DARK[2], pH_Colors.BG_DARK[3], 0.85)
        card:SetBackdropBorderColor(pH_Colors.BORDER_BRONZE[1], pH_Colors.BORDER_BRONZE[2], pH_Colors.BORDER_BRONZE[3], 0.9)

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
        card.icon = icon

        local header = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        header:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        card.headerText = header

        local rateText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rateText:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -28)
        rateText:SetTextColor(pH_Colors.TEXT_PRIMARY[1], pH_Colors.TEXT_PRIMARY[2], pH_Colors.TEXT_PRIMARY[3])
        card.rateText = rateText

        local totalText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        totalText:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -50)
        totalText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        card.totalText = totalText

        local peakText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        peakText:SetPoint("LEFT", totalText, "RIGHT", 10, 0)
        peakText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        card.peakText = peakText

        local sparkline = CreateFrame("Frame", nil, card)
        sparkline:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 6)
        sparkline:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 6)
        sparkline:SetHeight(18)
        sparkline.insetLeft = 8
        sparkline.insetRight = 8
        EnsureSparkline(sparkline, 12)
        card.sparkline = sparkline

        scrollChild.metricCards[metricKey] = card
        return card
    end

    local function UpdateCard(card, data)
        card.icon:SetTexture(data.icon)
        card.headerText:SetText(data.label)
        card.rateText:SetText(FormatMetricRate(data.key, data.rate))
        card.totalText:SetText("Total: " .. FormatMetricTotal(data.key, data.total))
        card.peakText:SetText("Peak: " .. FormatMetricRate(data.key, data.peak))

        local color = data.color or pH_Colors.ACCENT_GOLD
        UpdateSparkline(card.sparkline, data.buffer, color, 18, data.maxSamples)

        card:SetScript("OnClick", function()
            self.focusMetricKey = data.key
            self:RenderSummaryTab()
        end)
    end

    -- Focus panel spacing constants to keep header/sparkline/rows consistent
    -- and prevent overlap with the bottom border/back button.
    local FOCUS_BASE_HEIGHT = 178
    local FOCUS_HEADER_TOP = -120
    local FOCUS_DIVIDER_TOP = -128
    local FOCUS_ROW_START = -136
    local FOCUS_ROW_STEP = 14
    local FOCUS_ROW_HEIGHT = 14
    local FOCUS_BOTTOM_CLEARANCE = 34

    local function EnsureFocusPanel()
        local panel = scrollChild.focusPanel
        if panel then return panel end
        panel = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 14,
            insets = {left = 4, right = 4, top = 4, bottom = 4},
        })
        panel:SetBackdropColor(pH_Colors.BG_PARCHMENT[1], pH_Colors.BG_PARCHMENT[2], pH_Colors.BG_PARCHMENT[3], 0.9)
        panel:SetBackdropBorderColor(pH_Colors.BORDER_BRONZE[1], pH_Colors.BORDER_BRONZE[2], pH_Colors.BORDER_BRONZE[3], 1)

        panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
        panel.title:SetTextColor(pH_Colors.TEXT_PRIMARY[1], pH_Colors.TEXT_PRIMARY[2], pH_Colors.TEXT_PRIMARY[3])

        panel.stats = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        panel.stats:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -32)
        panel.stats:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        panel.sparkline = CreateFrame("Frame", nil, panel)
        panel.sparkline:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -58)
        panel.sparkline:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -58)
        panel.sparkline:SetHeight(36)
        panel.sparkline.insetLeft = 10
        panel.sparkline.insetRight = 10
        EnsureSparkline(panel.sparkline, 24)

        panel.breakdown = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        panel.breakdown:SetPoint("TOPLEFT", panel.sparkline, "BOTTOMLEFT", 0, -8)
        panel.breakdown:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        panel.breakdownHeader = {
            source = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
            rate = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
            total = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
            pct = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        }
        panel.breakdownHeader.source:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, FOCUS_HEADER_TOP)
        -- Match row column right edges exactly (row frame right is panel right minus 16)
        panel.breakdownHeader.rate:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -166, FOCUS_HEADER_TOP)
        panel.breakdownHeader.total:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -76, FOCUS_HEADER_TOP)
        panel.breakdownHeader.pct:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, FOCUS_HEADER_TOP)

        panel.breakdownHeader.source:SetText("Source")
        panel.breakdownHeader.rate:SetText("g/hr")
        panel.breakdownHeader.total:SetText("Total")
        panel.breakdownHeader.pct:SetText("%")
        panel.breakdownHeader.source:SetJustifyH("LEFT")
        panel.breakdownHeader.rate:SetJustifyH("RIGHT")
        panel.breakdownHeader.total:SetJustifyH("RIGHT")
        panel.breakdownHeader.pct:SetJustifyH("RIGHT")

        panel.breakdownHeader.source:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        panel.breakdownHeader.rate:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        panel.breakdownHeader.total:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        panel.breakdownHeader.pct:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        -- Divider under header row to improve legibility in lieu of true bold font weight
        panel.breakdownHeaderDivider = panel:CreateTexture(nil, "BORDER")
        panel.breakdownHeaderDivider:SetColorTexture(pH_Colors.DIVIDER[1], pH_Colors.DIVIDER[2], pH_Colors.DIVIDER[3], 0.9)
        panel.breakdownHeaderDivider:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, FOCUS_DIVIDER_TOP)
        panel.breakdownHeaderDivider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, FOCUS_DIVIDER_TOP)
        panel.breakdownHeaderDivider:SetHeight(1)

        panel.breakdownHeader.source:Hide()
        panel.breakdownHeader.rate:Hide()
        panel.breakdownHeader.total:Hide()
        panel.breakdownHeader.pct:Hide()
        panel.breakdownHeaderDivider:Hide()

        panel.breakdownRows = {}

        panel.backBtn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        panel.backBtn:SetSize(50, 18)
        panel.backBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 10, 8)
        panel.backBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2},
        })
        panel.backBtn:SetBackdropColor(pH_Colors.BG_DARK[1], pH_Colors.BG_DARK[2], pH_Colors.BG_DARK[3], 0.8)
        panel.backBtn:SetBackdropBorderColor(pH_Colors.DIVIDER[1], pH_Colors.DIVIDER[2], pH_Colors.DIVIDER[3], 0.6)
        panel.backBtnText = panel.backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        panel.backBtnText:SetPoint("CENTER")
        panel.backBtnText:SetText("Back")
        panel.backBtn:SetScript("OnClick", function()
            self.focusMetricKey = nil
            self:RenderSummaryTab()
        end)

        scrollChild.focusPanel = panel
        return panel
    end

    local function AddFocusBreakdownRow(panel, yOffset, label, perHourValue, totalValue, pctValue)
        local panelWidth = panel:GetWidth()
        if not panelWidth or panelWidth <= 0 then
            panelWidth = (scrollChild and scrollChild:GetWidth() and scrollChild:GetWidth() > 0)
                and (scrollChild:GetWidth() - 20)
                or 360
        end
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(panelWidth - 32, 14)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, yOffset)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetText(label)
        row.label:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        row.perHour = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.perHour:SetPoint("RIGHT", row, "RIGHT", -150, 0)
        row.perHour:SetJustifyH("RIGHT")
        row.perHour:SetText(perHourValue)
        row.perHour:SetTextColor(pH_Colors.TEXT_PRIMARY[1], pH_Colors.TEXT_PRIMARY[2], pH_Colors.TEXT_PRIMARY[3])

        row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.total:SetPoint("RIGHT", row, "RIGHT", -60, 0)
        row.total:SetJustifyH("RIGHT")
        row.total:SetText(totalValue)
        row.total:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.pct:SetJustifyH("RIGHT")
        row.pct:SetText(pctValue)
        row.pct:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        table.insert(panel.breakdownRows, row)
        return row
    end

    local function ShowFocusPanel(data)
        local panel = EnsureFocusPanel()
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
        panel:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
        panel:Show()

        panel.title:SetText(data.label or "Metric")
        panel.stats:SetText(string.format("%s  |  Total %s",
            FormatMetricRate(data.key, data.rate),
            FormatMetricTotal(data.key, data.total)))
        if panel.sparkline then
            local panelWidth = panel:GetWidth()
            if panelWidth and panelWidth > 0 then
                panel.sparkline:SetWidth(math.max(1, panelWidth - 20))
            end
        end
        UpdateSparkline(panel.sparkline, data.buffer, data.color or pH_Colors.ACCENT_GOLD, 36, data.maxSamples)

        -- Clear old breakdown rows
        for _, row in ipairs(panel.breakdownRows) do
            row:Hide()
        end
        panel.breakdownRows = {}
        if panel.breakdownHeader then
            panel.breakdownHeader.source:Hide()
            panel.breakdownHeader.rate:Hide()
            panel.breakdownHeader.total:Hide()
            panel.breakdownHeader.pct:Hide()
            panel.breakdownHeaderDivider:Hide()
        end

        if data.key == "gold" and session and metrics and metrics.totalValue and metrics.totalValue > 0 then
            local goldPct = math.floor((metrics.cash / metrics.totalValue) * 100)
            local expectedPct = 100 - goldPct
            panel.breakdown:SetText(string.format("Breakdown: Gold %d%% | Expected %d%%", goldPct, expectedPct))
            panel.breakdown:Show()
            if panel.breakdownHeader then
                panel.breakdownHeader.source:Show()
                panel.breakdownHeader.rate:Show()
                panel.breakdownHeader.total:Show()
                panel.breakdownHeader.pct:Show()
                panel.breakdownHeaderDivider:Show()
            end

            -- Source breakdown (same categories as HUD gold panel)
            local rawGold = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin") or 0
            -- NOTE: Ledger posts vendor trash income to Income:ItemsLooted:VendorTrash
            local vendorTrash = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:VendorTrash") or 0
            local rareItems = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:RareMulti") or 0
            local gathering = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering") or 0
            local questRewards = GoldPH_Ledger:GetBalance(session, "Income:Quest") or 0
            local vendorSales = GoldPH_Ledger:GetBalance(session, "Income:VendorSales") or 0
            local pickpocketCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Coin") or 0
            local pickpocketItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Items") or 0
            local lockboxCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Coin") or 0
            local lockboxItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Items") or 0
            local pickpocketTotal = pickpocketCoin + pickpocketItems + lockboxCoin + lockboxItems
            local totalGold = rawGold + vendorTrash + rareItems + gathering + questRewards + vendorSales + pickpocketTotal

            local durationHours = metrics.durationSec / 3600
            if durationHours == 0 then durationHours = 1 end

            local categories = {
                {"Raw Gold", rawGold},
                {"Quest Rewards", questRewards},
                {"Vendor Sales", vendorSales},
                {"Vendor Trash", vendorTrash},
                {"AH / Rare Items", rareItems},
                {"Gathering", gathering},
                {"Pickpocketing", pickpocketTotal},
            }

            local rowY = FOCUS_ROW_START
            local rowCount = 0
            for _, cat in ipairs(categories) do
                local label, value = cat[1], cat[2]
                if value > 0 then
                    local perHour = math.floor(value / durationHours)
                    local pct = totalGold > 0 and math.floor((value / totalGold) * 100) or 0
                    AddFocusBreakdownRow(panel, rowY, label,
                        GoldPH_Ledger:FormatMoneyShort(perHour) .. "/hr",
                        GoldPH_Ledger:FormatMoney(value),
                        string.format("%d%%", pct))
                    rowY = rowY - FOCUS_ROW_STEP
                    rowCount = rowCount + 1
                end
            end

            local rowsHeight = 0
            if rowCount > 0 then
                rowsHeight = ((rowCount - 1) * FOCUS_ROW_STEP) + FOCUS_ROW_HEIGHT
            end
            local requiredHeight = math.abs(FOCUS_ROW_START) + rowsHeight + FOCUS_BOTTOM_CLEARANCE
            panel:SetHeight(math.max(FOCUS_BASE_HEIGHT, requiredHeight))
            return panel:GetHeight() + 20
        else
            panel.breakdown:SetText("")
            panel.breakdown:Hide()
            panel:SetHeight(FOCUS_BASE_HEIGHT)
            return panel:GetHeight() + 20
        end
    end

    if self.focusMetricKey and metricMap[self.focusMetricKey] then
        metricContainer:Hide()
        local focusContentHeight = ShowFocusPanel(metricMap[self.focusMetricKey])
        scrollChild:SetHeight(math.abs(yOffset) + focusContentHeight)
        return
    end

    if scrollChild.focusPanel then
        scrollChild.focusPanel:Hide()
    end

    -- Always show all 4 metric cards (even if no data)
    for _, metricKey in ipairs(metricOrder) do
        local card = EnsureCard(metricKey)
        local data = metricMap[metricKey]
        if data then
            card:SetSize(cardWidth, cardHeight)
            if card.sparkline then
                card.sparkline:SetWidth(math.max(1, cardWidth - 16))
            end
            card:Show()
            UpdateCard(card, data)
        else
            -- Create empty data for missing metrics
            local emptyData = {
                key = metricKey,
                label = METRIC_LABELS[metricKey],
                icon = METRIC_ICONS[metricKey],
                color = METRIC_COLORS[metricKey],
                rate = 0,
                total = 0,
                peak = 0,
                buffer = nil,
                maxSamples = nil,
                isActive = false,
            }
            card:SetSize(cardWidth, cardHeight)
            if card.sparkline then
                card.sparkline:SetWidth(math.max(1, cardWidth - 16))
            end
            card:Show()
            UpdateCard(card, emptyData)
        end
    end

    -- Layout cards in 2x2 grid (always 4 cards)
    for i, metricKey in ipairs(metricOrder) do
        local card = scrollChild.metricCards[metricKey]
        if card then
            local row = math.floor((i - 1) / 2)
            local col = (i - 1) % 2
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", metricContainer, "TOPLEFT",
                col * (cardWidth + cardGap),
                -(row * (cardHeight + cardGap)))
        end
    end

    local containerHeight = (2 * cardHeight) + cardGap  -- Always 2 rows
    metricContainer:SetHeight(containerHeight)
    yOffset = yOffset - containerHeight - 10

    -- Helper function to add section header
    local function AddHeader(text)
        local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
        header:SetText(text)
        header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
        yOffset = yOffset - 20
        return header
    end

    -- Helper function to add label + value row
    local function AddRow(label, value, valueColor)
        local labelText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        labelText:SetText(label .. ":")
        labelText:SetJustifyH("LEFT")
        labelText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        local valueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valueText:SetPoint("LEFT", labelText, "RIGHT", 10, 0)
        valueText:SetText(value)
        valueText:SetJustifyH("LEFT")
        if valueColor then
            valueText:SetTextColor(valueColor[1], valueColor[2], valueColor[3])
        else
            valueText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        end

        yOffset = yOffset - 18
        return labelText, valueText
    end

    yOffset = yOffset - 10

    -- Economic Summary
    AddHeader("Economic Summary")
    AddRow("Total Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.totalPerHour) .. "/hr", pH_Colors.TEXT_MUTED)
    AddRow("Gold Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour) .. "/hr", pH_Colors.ACCENT_GOOD)
    AddRow("Expected Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.expectedPerHour) .. "/hr", pH_Colors.TEXT_MUTED)

    yOffset = yOffset - 10

    -- Gold flow (income / expenses)
    AddHeader("Income / Expenses")
    AddRow("Looted Coin", GoldPH_Ledger:FormatMoney(metrics.income))
    AddRow("Quest Rewards", GoldPH_Ledger:FormatMoney(metrics.incomeQuest))
    AddRow("Vendor Sales", GoldPH_Ledger:FormatMoney(GoldPH_Ledger:GetBalance(session, "Income:VendorSales")))
    -- Expenses: only show negative sign and red color if value is non-zero
    local repairsText = metrics.expenseRepairs > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseRepairs)) or GoldPH_Ledger:FormatMoney(metrics.expenseRepairs)
    AddRow("Repairs", repairsText, metrics.expenseRepairs > 0 and pH_Colors.ACCENT_BAD or nil)
    local vendorBuysText = metrics.expenseVendorBuys > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseVendorBuys)) or GoldPH_Ledger:FormatMoney(metrics.expenseVendorBuys)
    AddRow("Vendor Purchases", vendorBuysText, metrics.expenseVendorBuys > 0 and pH_Colors.ACCENT_BAD or nil)
    local travelText = metrics.expenseTravel > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseTravel)) or GoldPH_Ledger:FormatMoney(metrics.expenseTravel)
    AddRow("Travel", travelText, metrics.expenseTravel > 0 and pH_Colors.ACCENT_BAD or nil)

    yOffset = yOffset - 10

    -- Inventory Breakdown
    AddHeader("Inventory Expected")
    AddRow("Vendor Trash", GoldPH_Ledger:FormatMoney(metrics.invVendorTrash))
    AddRow("Rare/Multi", GoldPH_Ledger:FormatMoney(metrics.invRareMulti))
    AddRow("Gathering", GoldPH_Ledger:FormatMoney(metrics.invGathering))

    -- Pickpocket Summary (if present)
    if session.pickpocket and (metrics.pickpocketGold > 0 or metrics.pickpocketValue > 0) then
        yOffset = yOffset - 10
        AddHeader("Pickpocket")
        AddRow("Coin", GoldPH_Ledger:FormatMoney(metrics.pickpocketGold))
        AddRow("Items Value", GoldPH_Ledger:FormatMoney(metrics.pickpocketValue))
        AddRow("Lockboxes Looted", tostring(metrics.lockboxesLooted))
        AddRow("Lockboxes Opened", tostring(metrics.lockboxesOpened))
        if metrics.fromLockboxGold > 0 or metrics.fromLockboxValue > 0 then
            AddRow("From Lockbox Coin", GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold))
            AddRow("From Lockbox Items", GoldPH_Ledger:FormatMoney(metrics.fromLockboxValue))
        end
    end

    -- Gathering Summary (if present)
    if session.gathering and session.gathering.totalNodes and session.gathering.totalNodes > 0 then
        yOffset = yOffset - 10
        AddHeader("Gathering")
        AddRow("Total Nodes", tostring(session.gathering.totalNodes))

        local nodesPerHour = 0
        if metrics.durationHours > 0 then
            nodesPerHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end
        AddRow("Nodes Per Hour", tostring(nodesPerHour))
    end

    -- Phase 9: XP Summary (if present)
    if metrics.xpEnabled and metrics.xpGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Experience")
        AddRow("XP Gained", string.format("%d", metrics.xpGained))
        AddRow("XP Per Hour", string.format("%d/hr", metrics.xpPerHour), {0.5, 0.8, 1})  -- Blue
    end

    -- Phase 9: Reputation Summary (if present)
    if metrics.repEnabled and metrics.repGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Reputation")
        AddRow("Rep Gained", string.format("%d", metrics.repGained))
        AddRow("Rep Per Hour", string.format("%d/hr", metrics.repPerHour), {0.3, 1, 0.3})  -- Green

        -- Show top 3 factions
        if metrics.repTopFactions and #metrics.repTopFactions > 0 then
            yOffset = yOffset - 5
            local topFactionsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            topFactionsLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
            topFactionsLabel:SetText("Top Factions:")
            topFactionsLabel:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
            yOffset = yOffset - 16

            for _, factionData in ipairs(metrics.repTopFactions) do
                AddRow("  " .. factionData.name, string.format("+%d", factionData.gain), {0.7, 0.7, 0.7})
            end
        end
    end

    -- Phase 9: Honor Summary (if present)
    if metrics.honorEnabled and metrics.honorGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Honor")
        AddRow("Honor Gained", string.format("%d", metrics.honorGained))
        AddRow("Honor Per Hour", string.format("%d/hr", metrics.honorPerHour), {1, 0.5, 0.3})  -- Orange
        if metrics.honorKills > 0 then
            AddRow("Honorable Kills", tostring(metrics.honorKills))
        end
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Render Items Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderItemsTab()
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
        valueText:SetText(GoldPH_Ledger:FormatMoneyShort(itemData.expectedTotal))
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
        GoldPH_Ledger:FormatMoney(totalValue)))
    summaryText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    yOffset = yOffset - 20

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Render Gathering Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderGatheringTab()
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
function GoldPH_History_Detail:RenderCompareTab()
    local frame = self.contentFrames["compare"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics

    -- Get zone aggregates
    local zoneAgg = GoldPH_Index:GetZoneAggregates()
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
        GoldPH_Ledger:FormatMoneyShort(metrics.totalPerHour),
        GoldPH_Ledger:FormatMoneyShort(zoneStats.avgTotalPerHour),
        nil
    )

    AddComparisonRow(
        "Gold g/hr",
        GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour),
        "N/A",  -- We don't track cash avg in zoneAgg yet
        nil
    )

    AddComparisonRow(
        "Expected g/hr",
        GoldPH_Ledger:FormatMoneyShort(metrics.expectedPerHour),
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
    local allZoneSessions = GoldPH_Index.byZone[thisZone] or {}
    local rank = 1
    for _, otherSessionId in ipairs(allZoneSessions) do
        if otherSessionId ~= session.id then
            local otherSummary = GoldPH_Index:GetSummary(otherSessionId)
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
            GoldPH_Ledger:FormatMoneyShort(zoneStats.bestTotalPerHour),
            zoneStats.bestSessionId))
        bestInsight:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        yOffset = yOffset - 18
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

-- Export module
_G.GoldPH_History_Detail = GoldPH_History_Detail
