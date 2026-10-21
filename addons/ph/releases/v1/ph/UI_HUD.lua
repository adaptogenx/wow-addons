--[[
    UI_HUD.lua - Heads-up display for GoldPH

    Shows real-time session metrics in accounting-style layout.
]]

-- luacheck: globals GoldPH_Settings

local GoldPH_HUD = {}

local hudFrame = nil
local updateTimer = 0
local UPDATE_INTERVAL = 1.0 -- Update every 1 second

-- Layout constants
local PADDING = 12
local FRAME_WIDTH = 180
-- Base expanded height; actual height is dynamically adjusted based on visible rows
local FRAME_HEIGHT = 180
-- Calculate minimized height for horizontal bar:
-- Top padding: 12px (PADDING)
-- Title row: ~14px (12px font + line height)
-- Gap between title and tiles: 6px
-- Tile height: 18px (icon/text row 12px + 2px gap + bar 4px)
-- Bottom padding: 4px (reduced for compact layout)
-- Total: 12 + 14 + 6 + 18 + 4 = 54px
local FRAME_HEIGHT_MINI = 54  -- Minimized height with horizontal micro-bars
local SECTION_GAP = 4

-- Rectangular panel layout (PRD-aligned)
local FRAME_WIDTH_EXPANDED = 340     -- Wider frame for detailed breakdowns
local PANEL_FULL_WIDTH = 316         -- 340 - 2*PADDING (12px each side)
local PANEL_HALF_WIDTH = 155         -- (316 - 6 gap) / 2
local PANEL_GAP = 6                  -- Gap between panels
local PANEL_PADDING = 8              -- Internal panel padding
local MAX_PLAYER_LEVEL = 70          -- TBC max level

-- pH Brand colors (from PH_BRAND_BRIEF.md - Classic-safe)
local PH_TEXT_PRIMARY = {0.86, 0.82, 0.70}
local PH_TEXT_MUTED = {0.62, 0.58, 0.50}
local PH_ACCENT_GOOD = {0.25, 0.78, 0.42}
local PH_ACCENT_NEUTRAL = {0.55, 0.70, 0.55}
local PH_BG_DARK = {0.08, 0.07, 0.06, 0.85}
local PH_BG_PARCHMENT = {0.18, 0.16, 0.13, 0.85}
local PH_BORDER_BRONZE = {0.52, 0.42, 0.28}

-- Additional pH brand tokens
local PH_ACCENT_WARNING = {0.90, 0.65, 0.20}  -- Warm amber for expenses/warnings
local PH_ACCENT_GOLD_INCOME = {1.00, 0.82, 0.00}  -- Classic gold for income highlights
local PH_TEXT_DISABLED = {0.45, 0.42, 0.38}  -- Darker muted for disabled/inactive
local PH_HOVER = {0.22, 0.20, 0.17, 0.60}  -- Subtle hover state
local PH_SELECTED = {0.35, 0.32, 0.26, 0.75}  -- Selected row/item
local PH_DIVIDER = {0.28, 0.25, 0.22, 0.50}  -- Separator lines

-- Micro-bar colors (pH brand palette)
local MICROBAR_COLORS = {
    GOLD = {
        fill = {1.00, 0.82, 0.00, 0.85},  -- Classic gold
        bg = PH_BG_DARK
    },
    XP = {
        fill = {0.58, 0.51, 0.79, 0.85},  -- Classic purple XP bar
        bg = PH_BG_DARK
    },
    REP = {
        fill = PH_ACCENT_GOOD,  -- Alchemy green
        bg = PH_BG_DARK
    },
    HONOR = {
        fill = {0.90, 0.60, 0.20, 0.85},  -- Classic honor orange
        bg = PH_BG_DARK
    },
}

local METRIC_ICONS = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    xp = "Interface\\Icons\\INV_Misc_Book_11",  -- Book icon for learning/XP
    rep = "Interface\\Icons\\INV_Misc_Ribbon_01",  -- Ribbon for reputation
    honor = "Interface\\Icons\\inv_bannerpvp_02",  -- PvP banner (exists in Classic, wowhead 132486)
}

local METRIC_LABELS = {
    gold = "GOLD / HOUR",
    xp = "XP / HOUR",
    rep = "REP / HOUR",
    honor = "HONOR / HOUR",
}

-- Color keys mapping for micro-bar colors
local colorKeys = { gold = "GOLD", xp = "XP", rep = "REP", honor = "HONOR" }

-- Runtime state for micro-bars (not persisted)
local metricStates = {
    gold = { key = "gold", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    xp = { key = "xp", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    rep = { key = "rep", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    honor = { key = "honor", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
}

-- Fixed order for metric display: gold, rep, xp, honor
local METRIC_ORDER = { "gold", "rep", "xp", "honor" }

local lastUpdateTime = 0

--------------------------------------------------
-- Micro-Bar Helper Functions
--------------------------------------------------

-- Exponential smoothing for rate display
local function SmoothRate(prevDisplayRate, currentRate, alpha)
    if prevDisplayRate == 0 then
        return currentRate  -- First time: initialize
    end
    return (alpha * currentRate) + ((1 - alpha) * prevDisplayRate)
end

-- Normalize rate to [0,1] for micro-bar fill
local function NormalizeRate(displayRate, peak, minFloor)
    local refMax = math.max(peak, minFloor)
    if refMax == 0 then return 0 end
    return math.min(math.max(displayRate / refMax, 0), 1)
end

-- Optional peak decay over time
local function DecayPeak(currentPeak, currentRate, minutesSinceLastTick, cfg)
    if not cfg.peakDecay.enabled then
        return math.max(currentPeak, currentRate)
    end
    local decayFactor = 1 - (cfg.peakDecay.ratePerMin * minutesSinceLastTick)
    local decayedPeak = currentPeak * decayFactor
    return math.max(decayedPeak, currentRate)
end

-- Format rate for micro-bar display (ultra-compact, no /h suffix to save space)
local function FormatRateForMicroBar(metricKey, rate)
    if metricKey == "gold" then
        -- Inline FormatAccountingShort logic for gold
        if not rate or rate == 0 then
            return "0g"
        end
        local isNegative = rate < 0
        local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(rate))
        if isNegative and formatted ~= "0g" then
            return "(" .. formatted .. ")"
        else
            return formatted
        end
    elseif metricKey == "xp" then
        if rate >= 1000 then
            return string.format("%.1fk", rate / 1000)
        else
            return string.format("%d", rate)
        end
    elseif metricKey == "rep" then
        return string.format("%d", rate)
    elseif metricKey == "honor" then
        if rate >= 1000 then
            return string.format("%.1fk", rate / 1000)
        else
            return string.format("%d", rate)
        end
    end
end

-- Reposition tiles horizontally in fixed order (gold, rep, xp, honor)
local function RepositionTiles(isCollapsed)
    local tileWidth = 50
    local tileSpacing = 14
    local orderedTiles = {}
    
    -- Build ordered list of tiles (all tiles, in fixed order)
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile then
            table.insert(orderedTiles, state)
        end
    end
    
    local tileCount = #orderedTiles
    if tileCount == 0 then return end

    if isCollapsed then
        -- Horizontal layout: position tiles starting from left edge, below title row
        -- Anchor to hudFrame.TOPLEFT to prevent UI jumping when collapsing/expanding
        -- Calculate header height: top padding (12px) + title height (~14px) + gap (6px) = 32px
        local headerHeight = PADDING + 14 + 6  -- 32px total
        local headerYOffset = -headerHeight

        for i, state in ipairs(orderedTiles) do
            state.tile:ClearAllPoints()
            if i == 1 then
                -- First tile: anchor TOPLEFT to hudFrame.TOPLEFT (same coordinate as HUD frame)
                -- This ensures no visual jumping when frame size changes
                state.tile:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, headerYOffset)
            else
                -- Subsequent tiles: align top with first tile, position to right
                state.tile:SetPoint("TOP", orderedTiles[1].tile, "TOP", 0, 0)
                state.tile:SetPoint("LEFT", orderedTiles[i-1].tile, "RIGHT", tileSpacing, 0)
            end
        end
    else
        -- Expanded layout: centered below header timer (headerContainer removed)
        local totalWidth = (tileCount * tileWidth) + ((tileCount - 1) * tileSpacing)
        local startX = -totalWidth / 2 + tileWidth / 2
        for i, state in ipairs(orderedTiles) do
            local xOffset = startX + ((i - 1) * (tileWidth + tileSpacing))
            state.tile:ClearAllPoints()
            state.tile:SetPoint("TOP", hudFrame.headerTimer, "BOTTOM", xOffset, -8)
        end
    end
end

-- Update micro-bars for collapsed state
local function UpdateMicroBars(session, metrics)
    local cfg = GoldPH_Settings.microBars
    if not cfg then return end

    -- Skip if paused (freeze bars)
    local isPaused = GoldPH_SessionManager:IsPaused(session)
    if isPaused then
        -- When paused, keep current display but don't update
        RepositionTiles(true)
        return
    end

    -- Time delta for peak decay
    local now = GetTime()
    local deltaMinutes = (now - lastUpdateTime) / 60
    lastUpdateTime = now

    -- Update each metric in fixed order
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile then
            local rawRate = 0
            local isActive = false

            -- Extract raw rate from metrics
            if metricKey == "gold" then
                rawRate = metrics.totalPerHour
                isActive = true  -- Gold is always active
            elseif metricKey == "xp" then
                rawRate = metrics.xpPerHour or 0
                isActive = metrics.xpEnabled and rawRate > 0
            elseif metricKey == "rep" then
                rawRate = metrics.repPerHour or 0
                isActive = metrics.repEnabled and rawRate > 0
            elseif metricKey == "honor" then
                rawRate = metrics.honorPerHour or 0
                isActive = metrics.honorEnabled and rawRate > 0
            end

            -- Always show tiles, but gray out inactive ones
            state.tile:Show()
            state.icon:Show()  -- Ensure icon is always visible

            if isActive then
                -- Active: normal colors and updates
                -- Apply smoothing
                state.displayRate = SmoothRate(state.displayRate, rawRate, cfg.smoothingAlpha)

                -- Update peak (with optional decay)
                state.peak = DecayPeak(state.peak, state.displayRate, deltaMinutes, cfg.normalization)

                -- Normalize for bar
                local minFloor = cfg.minRefFloors[metricKey]
                local normalized = NormalizeRate(state.displayRate, state.peak, minFloor)

                -- Update bar fill
                state.bar:SetValue(normalized)

                -- Update text (avoid string churn)
                local newText = FormatRateForMicroBar(metricKey, state.displayRate)
                if state.lastUpdatedText ~= newText then
                    state.valueText:SetText(newText)
                    state.lastUpdatedText = newText
                end

                -- Set active colors (full opacity)
                state.icon:SetVertexColor(1, 1, 1)  -- Full color, no tinting
                state.icon:SetAlpha(1.0)  -- Full opacity
                state.valueText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
                local colorKey = colorKeys[metricKey]
                local fillColor = MICROBAR_COLORS[colorKey].fill
                state.bar:GetStatusBarTexture():SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
            else
                -- Inactive: gray out (reduced opacity)
                state.bar:SetValue(0)  -- Empty bar
                state.valueText:SetText("0")
                
                -- Gray out icon (keep visible but muted - use gray tint with reduced opacity)
                state.icon:SetVertexColor(0.6, 0.6, 0.6)  -- Gray tint
                state.icon:SetAlpha(0.7)  -- Reduced opacity but still visible
                state.icon:Show()  -- Ensure icon is always visible
                state.valueText:SetTextColor(0.4, 0.4, 0.4, 0.5)
                -- Gray out bar fill
                state.bar:GetStatusBarTexture():SetVertexColor(0.3, 0.3, 0.3, 0.3)
            end
        end
    end

    -- Reposition tiles horizontally in fixed order (collapsed layout)
    RepositionTiles(true)
end

--------------------------------------------------
-- Metric history helpers (for sparklines and cards)
--------------------------------------------------
local function GetBufferSample(buffer, offsetFromLatest)
    if not buffer or buffer.count == 0 then return nil end
    if offsetFromLatest >= buffer.count then return nil end
    local index = buffer.head - offsetFromLatest
    if index <= 0 then
        index = index + buffer.capacity
    end
    return buffer.samples[index]
end

--------------------------------------------------
-- Sparkline helper functions (shared between cards and focus panel)
--------------------------------------------------
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

local function UpdateSparkline(frame, buffer, barColor, height, maxSamplesLocal)
    if not frame or not frame.bars then return end
    local barCount = frame.barCount or 10
    local width = frame:GetWidth()
    if width == 0 then return end
    local gap = 2
    local barWidth = math.max(1, math.floor((width - (gap * (barCount - 1))) / barCount))
    local available = buffer and buffer.count or 0
    if maxSamplesLocal and maxSamplesLocal < available then
        available = maxSamplesLocal
    end
    local span = math.max(1, available)
    local maxValue = 0
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

--------------------------------------------------
-- Panel Helper Functions
--------------------------------------------------

-- Create a rectangular panel with header
local function CreateMetricPanel(parent, width, height)
    if not parent then
        print("GoldPH Error: CreateMetricPanel called with nil parent")
        return nil
    end

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if not panel then
        print("GoldPH Error: CreateFrame returned nil")
        return nil
    end

    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    panel:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.85)
    panel:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.9)

    -- Header row: icon + label + total (right-aligned)
    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(16, 16)
    panel.icon:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, -PANEL_PADDING)

    panel.label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.label:SetPoint("LEFT", panel.icon, "RIGHT", 6, 0)
    panel.label:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    -- Total aligned with title row (same vertical as label)
    panel.totalValue = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.totalValue:SetPoint("TOP", panel.label, "TOP", 0, 0)
    panel.totalValue:SetPoint("RIGHT", panel, "RIGHT", -PANEL_PADDING, 0)
    panel.totalValue:SetJustifyH("RIGHT")
    panel.totalValue:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    -- Primary stat: per-hour rate (large font for consistency with History cards)
    panel.rateText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.rateText:SetPoint("TOPLEFT", panel.icon, "BOTTOMLEFT", 0, -4)
    panel.rateText:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    -- Secondary stat: raw total
    panel.rawTotal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.rawTotal:SetPoint("LEFT", panel.rateText, "RIGHT", 8, 0)
    panel.rawTotal:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    -- Breakdown rows container
    panel.breakdownRows = {}

    return panel
end

-- Ensure metric panels exist (safe to call multiple times)
local function EnsureMetricPanels()
    if not hudFrame then
        return
    end

    -- Always ensure container exists first
    if not hudFrame.metricCardContainer then
        local metricCardContainer = CreateFrame("Frame", nil, hudFrame)
        -- Position below header timer (headerContainer removed, so -38 instead of -52)
        metricCardContainer:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, -38)
        metricCardContainer:SetSize(PANEL_FULL_WIDTH, 160)
        metricCardContainer:Hide()
        hudFrame.metricCardContainer = metricCardContainer
    end

    if not hudFrame.metricCards then
        hudFrame.metricCards = {}
    end

    -- Get container reference
    local container = hudFrame.metricCardContainer
    if not container then
        print("GoldPH Error: metricCardContainer is nil after creation")
        return
    end

    -- Check if all panels already exist
    if hudFrame.goldPanel and hudFrame.xpPanel and hudFrame.repPanel and hudFrame.honorPanel then
        return
    end

    -- Gold Panel (always visible, full width)
    if not hudFrame.goldPanel then
        local goldPanel = CreateMetricPanel(container, PANEL_FULL_WIDTH, 140)
        if goldPanel then
            goldPanel:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            goldPanel.label:SetText("GOLD")
            goldPanel.icon:SetTexture(METRIC_ICONS.gold)
            hudFrame.goldPanel = goldPanel
        end
    end

    -- XP Panel (left, conditional on not max level)
    if not hudFrame.xpPanel and hudFrame.goldPanel then
        local xpPanel = CreateMetricPanel(container, PANEL_HALF_WIDTH, 80)
        if xpPanel then
            xpPanel:SetPoint("TOPLEFT", hudFrame.goldPanel, "BOTTOMLEFT", 0, -PANEL_GAP)
            xpPanel.label:SetText("XP")
            xpPanel.icon:SetTexture(METRIC_ICONS.xp)
            -- Show by default (will be hidden by UpdateXPPanel if at max level)
            if UnitLevel("player") < MAX_PLAYER_LEVEL then
                xpPanel:Show()
            else
                xpPanel:Hide()
            end
            hudFrame.xpPanel = xpPanel
        end
    end

    -- Rep Panel (right, always visible)
    if not hudFrame.repPanel and hudFrame.goldPanel then
        local repPanel = CreateMetricPanel(container, PANEL_HALF_WIDTH, 80)
        if repPanel then
            repPanel:SetPoint("TOPLEFT", hudFrame.goldPanel, "BOTTOMLEFT", PANEL_HALF_WIDTH + PANEL_GAP, -PANEL_GAP)
            repPanel.label:SetText("Rep")
            repPanel.icon:SetTexture(METRIC_ICONS.rep)
            hudFrame.repPanel = repPanel
        end
    end

    -- Honor Panel (full width, conditional on honor > 0)
    if not hudFrame.honorPanel then
        local honorPanel = CreateMetricPanel(container, PANEL_FULL_WIDTH, 90)
        if honorPanel then
            -- Position will be dynamic based on whether XP panel is shown
            honorPanel.label:SetText("HONOR")
            honorPanel.icon:SetTexture(METRIC_ICONS.honor)
            honorPanel:Hide()  -- Hidden by default, shown when honorGained > 0
            hudFrame.honorPanel = honorPanel
        end
    end
end

-- Initialize HUD
function GoldPH_HUD:Initialize()
    -- Create main frame with BackdropTemplate for border support
    hudFrame = CreateFrame("Frame", "GoldPH_HUD_Frame", UIParent, "BackdropTemplate")
    hudFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)

    -- Apply WoW-themed backdrop with pH brand colors
    hudFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    -- Use pH brand parchment background
    hudFrame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], PH_BG_PARCHMENT[4])
    -- Use pH brand bronze border
    hudFrame:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 1)

    -- Make it movable
    hudFrame:SetMovable(true)
    hudFrame:EnableMouse(true)
    hudFrame:RegisterForDrag("LeftButton")
    hudFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    hudFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- Pause/Resume button (left of minimize) - same style as collapse/expand: two vertical lines (pause), right arrow (play)
    local pauseBtn = CreateFrame("Button", nil, hudFrame)
    pauseBtn:SetSize(16, 16)
    pauseBtn:SetPoint("TOPRIGHT", -4, -4)
    -- Same texture style as minMaxBtn (16x16 small button + same highlight)
    pauseBtn:SetNormalTexture("Interface\\Buttons\\UI-Button-Up")
    pauseBtn:SetPushedTexture("Interface\\Buttons\\UI-Button-Down")
    pauseBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    -- Symbol on top: two vertical bars (pause) or right arrow (play); updated in Update()
    local pauseBarLeft = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pauseBarLeft:SetPoint("CENTER", -2, 0)
    pauseBarLeft:SetText("|")
    pauseBarLeft:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    local pauseBarRight = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pauseBarRight:SetPoint("CENTER", 2, 0)
    pauseBarRight:SetText("|")
    pauseBarRight:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    local pausePlayArrow = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pausePlayArrow:SetPoint("CENTER", 0, 0)
    pausePlayArrow:SetText(">")
    pausePlayArrow:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    pausePlayArrow:Hide()
    hudFrame.pauseBarLeft = pauseBarLeft
    hudFrame.pauseBarRight = pauseBarRight
    hudFrame.pausePlayArrow = pausePlayArrow
    pauseBtn:SetScript("OnClick", function()
        local session = GoldPH_SessionManager:GetActiveSession()
        if not session then return end
        if GoldPH_SessionManager:IsPaused(session) then
            GoldPH_SessionManager:ResumeSession()
        else
            GoldPH_SessionManager:PauseSession()
        end
        GoldPH_HUD:Update()
    end)
    pauseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local session = GoldPH_SessionManager:GetActiveSession()
        if session and GoldPH_SessionManager:IsPaused(session) then
            GameTooltip:SetText("Resume session")
        else
            GameTooltip:SetText("Pause session")
        end
        GameTooltip:Show()
    end)
    pauseBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    hudFrame.pauseBtn = pauseBtn

    -- Minimize/Maximize button (stock WoW +/- buttons)
    local minMaxBtn = CreateFrame("Button", nil, hudFrame)
    minMaxBtn:SetSize(16, 16)
    minMaxBtn:SetPoint("TOPRIGHT", pauseBtn, "TOPLEFT", -2, 0)
    minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    minMaxBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    minMaxBtn:SetScript("OnClick", function()
        GoldPH_HUD:ToggleMinimize()
    end)
    hudFrame.minMaxBtn = minMaxBtn

    --------------------------------------------------
    -- Header (always visible in both collapsed and expanded states)
    --------------------------------------------------
    local headerYPos = -PADDING

    -- Title (always visible) - "pH" branding (lowercase p, uppercase H)
    local title = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PADDING, headerYPos)
    title:SetText("pH")
    title:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])  -- pH brand primary text
    -- Apply Friz Quadrata font per brand brief (WoW's built-in font)
    title:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    hudFrame.title = title

    -- Timer (always visible, next to title)
    local headerTimer = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTimer:SetPoint("LEFT", title, "RIGHT", 6, 0)
    headerTimer:SetJustifyH("LEFT")
    headerTimer:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])  -- pH brand muted text
    headerTimer:SetText("0m")
    hudFrame.headerTimer = headerTimer

    -- Header container (for backward compatibility, positioned below title row for expanded state)
    -- Hidden - second line removed per user request
    local headerContainer = CreateFrame("Frame", nil, hudFrame)
    headerContainer:SetPoint("TOP", title, "BOTTOM", 0, -4)
    headerContainer:SetSize(FRAME_WIDTH, 14)  -- Height for one line
    headerContainer:Hide()  -- Hidden by default - second line removed
    hudFrame.headerContainer = headerContainer

    -- Gold portion (for expanded state)
    local headerGold = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerGold:SetPoint("RIGHT", headerContainer, "CENTER", -6, 0)
    headerGold:SetJustifyH("RIGHT")
    headerGold:SetText("0g")
    hudFrame.headerGold = headerGold

    -- Separator (for expanded state)
    local headerSep = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerSep:SetPoint("CENTER", headerContainer, "CENTER", 0, 0)
    headerSep:SetText(" | ")
    headerSep:SetTextColor(0.7, 0.7, 0.7)
    hudFrame.headerSep = headerSep

    -- Timer duplicate for expanded state (keep for compatibility)
    local headerTimer2 = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTimer2:SetPoint("LEFT", headerContainer, "CENTER", 6, 0)
    headerTimer2:SetJustifyH("LEFT")
    headerTimer2:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
    headerTimer2:SetText("0m")
    hudFrame.headerTimer2 = headerTimer2

    --------------------------------------------------
    -- Micro-bar metric tiles (for collapsed state - single horizontal line)
    --------------------------------------------------
    local tileWidth = 50
    -- Tile height: 18px (icon/text row 12px + 2px gap + bar 4px)
    local tileHeight = 18

    for metricKey, state in pairs(metricStates) do
        -- Create tile container
        local tile = CreateFrame("Frame", nil, hudFrame)
        tile:SetSize(tileWidth, tileHeight)
        state.tile = tile

        -- Icon (compact, positioned at top left) - 12px for ultra-compact
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        icon:SetTexture(METRIC_ICONS[metricKey])
        state.icon = icon

        -- Rate text (pH brand muted color, compact) - positioned after icon, top-aligned
        local rateText = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rateText:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        rateText:SetPoint("TOP", tile, "TOP", 0, 0)
        rateText:SetJustifyH("LEFT")
        rateText:SetText("0")
        rateText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
        state.valueText = rateText

        -- Micro-bar background (pH brand dark background) - full width below icon/text, 4px height
        local barBg = CreateFrame("Frame", nil, tile, "BackdropTemplate")
        -- Bar spans from left edge to right edge of tile (full width)
        barBg:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, -14)  -- Below icon/text row (12px + 2px gap)
        barBg:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, -14)
        barBg:SetHeight(4)  -- 4px tall bar
        barBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
        })
        local colorKey = colorKeys[metricKey]
        local bgColor = MICROBAR_COLORS[colorKey].bg
        barBg:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        -- StatusBar fill (pH brand colors)
        local bar = CreateFrame("StatusBar", nil, barBg)
        bar:SetAllPoints(barBg)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local fillColor = MICROBAR_COLORS[colorKey].fill
        bar:GetStatusBarTexture():SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
        state.bar = bar

        -- Initially hidden (will be shown and positioned by UpdateMicroBars when session is active)
        tile:Hide()
    end

    --------------------------------------------------
    -- Expanded metric cards container
    --------------------------------------------------
    EnsureMetricPanels()

    -- Focus panel (modal overlay for metric drill-down)
    local focusPanel = CreateFrame("Frame", "GoldPH_FocusPanel", UIParent, "BackdropTemplate")
    focusPanel:SetSize(380, 240)
    focusPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    focusPanel:SetFrameStrata("DIALOG")
    focusPanel:SetFrameLevel(200)
    focusPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    focusPanel:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.98)
    focusPanel:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 1)
    focusPanel:Hide()
    focusPanel:EnableMouse(true)  -- Block click-through

    hudFrame.focusPanel = focusPanel

    -- Add focus panel components
    focusPanel.icon = focusPanel:CreateTexture(nil, "ARTWORK")
    focusPanel.icon:SetSize(20, 20)
    focusPanel.icon:SetPoint("TOPLEFT", focusPanel, "TOPLEFT", 12, -12)

    focusPanel.header = focusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    focusPanel.header:SetPoint("LEFT", focusPanel.icon, "RIGHT", 8, 0)
    focusPanel.header:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    focusPanel.closeBtn = CreateFrame("Button", nil, focusPanel, "UIPanelCloseButton")
    focusPanel.closeBtn:SetSize(24, 24)
    focusPanel.closeBtn:SetPoint("TOPRIGHT", focusPanel, "TOPRIGHT", -4, -4)
    focusPanel.closeBtn:SetScript("OnClick", function()
        GoldPH_HUD:HideFocusPanel()
    end)

    focusPanel.statsText = focusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    focusPanel.statsText:SetPoint("TOPLEFT", focusPanel.icon, "BOTTOMLEFT", 0, -8)
    focusPanel.statsText:SetPoint("RIGHT", focusPanel, "RIGHT", -12, 0)
    focusPanel.statsText:SetJustifyH("LEFT")
    focusPanel.statsText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    focusPanel.sparklineFrame = CreateFrame("Frame", nil, focusPanel)
    focusPanel.sparklineFrame:SetPoint("TOPLEFT", focusPanel.statsText, "BOTTOMLEFT", 0, -12)
    focusPanel.sparklineFrame:SetPoint("RIGHT", focusPanel, "RIGHT", -12, 0)
    focusPanel.sparklineFrame:SetHeight(50)
    EnsureSparkline(focusPanel.sparklineFrame, 30)  -- 30 bars for extended view

    focusPanel.breakdownText = focusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    focusPanel.breakdownText:SetPoint("TOPLEFT", focusPanel.sparklineFrame, "BOTTOMLEFT", 0, -12)
    focusPanel.breakdownText:SetPoint("BOTTOMRIGHT", focusPanel, "BOTTOMRIGHT", -12, 40)
    focusPanel.breakdownText:SetJustifyH("LEFT")
    focusPanel.breakdownText:SetJustifyV("TOP")
    focusPanel.breakdownText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    focusPanel.backBtn = focusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    focusPanel.backBtn:SetPoint("BOTTOMRIGHT", focusPanel, "BOTTOMRIGHT", -12, 12)
    focusPanel.backBtn:SetText("[Back]")
    focusPanel.backBtn:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])

    local backBtnClickFrame = CreateFrame("Button", nil, focusPanel)
    backBtnClickFrame:SetAllPoints(focusPanel.backBtn)
    backBtnClickFrame:SetScript("OnClick", function()
        GoldPH_HUD:HideFocusPanel()
    end)

    -- Update loop
    hudFrame:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed

        -- Dynamic update interval
        local interval = UPDATE_INTERVAL  -- Default 1.0s
        local cfg = GoldPH_Settings.microBars
        if cfg and cfg.enabled and GoldPH_Settings.hudMinimized then
            interval = cfg.updateInterval  -- 0.25s for micro-bars
        end

        if updateTimer >= interval then
            GoldPH_HUD:Update()
            updateTimer = 0
        end
    end)

    -- Initial state: hide until session starts
    hudFrame:Hide()
end

-- Format money for accounting display (uses parentheses for negatives)
local function FormatAccounting(copper)
    if not copper or copper == 0 then
        return "0c"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoney(math.abs(copper))
    
    -- Never show parentheses for zero values
    if isNegative and formatted ~= "0c" then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Format money short for accounting display (uses parentheses for negatives)
local function FormatAccountingShort(copper)
    if not copper or copper == 0 then
        return "0g"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(copper))
    
    -- Never show parentheses for zero values
    if isNegative and formatted ~= "0g" then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Format number helper (for XP display)
local function FormatNumber(num)
    if not num or num == 0 then
        return "0"
    end
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fk", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

-- Add breakdown row to panel
local function AddBreakdownRow(panel, yOffset, label, perHourValue, totalValue, pctValue)
    local row = CreateFrame("Frame", nil, panel)
    local rowWidth = panel:GetWidth() - 2 * PANEL_PADDING
    row:SetSize(rowWidth, 14)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, yOffset)

    -- Column layout (right-aligned numeric columns, flexible label column)
    local gap = 6
    local pctWidth = 30
    local totalWidth = 84
    local rateWidth = 74
    local pctLeft = rowWidth - pctWidth
    local totalRight = pctLeft - gap
    local totalLeft = totalRight - totalWidth
    local rateRight = totalLeft - gap
    local rateLeft = rateRight - rateWidth

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row, "LEFT", rateLeft - gap, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(label)
    if row.label.SetWordWrap then
        row.label:SetWordWrap(false)
    end
    row.label:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    row.perHour = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.perHour:SetPoint("LEFT", row, "LEFT", rateLeft, 0)
    row.perHour:SetPoint("RIGHT", row, "LEFT", rateRight, 0)
    row.perHour:SetJustifyH("RIGHT")
    row.perHour:SetText(perHourValue)
    row.perHour:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.total:SetPoint("LEFT", row, "LEFT", totalLeft, 0)
    row.total:SetPoint("RIGHT", row, "LEFT", totalRight, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetText(totalValue)
    row.total:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pct:SetPoint("LEFT", row, "LEFT", pctLeft, 0)
    row.pct:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetText(pctValue)
    row.pct:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    table.insert(panel.breakdownRows, row)
    return row
end

-- Add rep breakdown row (label + total only, no per-hour column)
local function AddRepBreakdownRow(panel, yOffset, label, totalValue)
    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(panel:GetWidth() - 2*PANEL_PADDING, 14)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, yOffset)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetText(label)
    row.label:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.total:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.total:SetText(totalValue)
    row.total:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    table.insert(panel.breakdownRows, row)
    return row
end

--------------------------------------------------
-- Metric history helpers (for expanded cards / sparklines)
--------------------------------------------------
local function GetMetricHistory(session)
    return session and session.metricHistory or nil
end

local function GetMetricBuffer(history, metricKey)
    if not history or not history.metrics then return nil end
    return history.metrics[metricKey]
end

-- Update Gold Panel with breakdown
local function UpdateGoldPanel(panel, metrics, session)
    -- Header: Total value (right-aligned)
    panel.totalValue:SetText(string.format("Total: %s", FormatAccounting(metrics.totalValue)))

    -- Primary: Per-hour rate (large)
    panel.rateText:SetText(FormatAccountingShort(metrics.totalPerHour) .. "/hr")

    -- Secondary: Raw total
    panel.rawTotal:SetText(FormatAccounting(metrics.totalValue) .. " (raw)")

    -- Get breakdown values from ledger (use : colon-call with session, not . dot-call with ledger)
    local rawGold = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin") or 0
    -- NOTE: Ledger posts vendor trash income to Income:ItemsLooted:VendorTrash
    local vendorTrash = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:VendorTrash") or 0
    local rareItems = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:RareMulti") or 0
    local gathering = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering") or 0
    local questRewards = GoldPH_Ledger:GetBalance(session, "Income:Quest") or 0
    local vendorSales = GoldPH_Ledger:GetBalance(session, "Income:VendorSales") or 0

    -- Pickpocketing total (all 4 sources)
    local pickpocketCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Coin") or 0
    local pickpocketItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Items") or 0
    local lockboxCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Coin") or 0
    local lockboxItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Items") or 0
    local pickpocketTotal = pickpocketCoin + pickpocketItems + lockboxCoin + lockboxItems

    local totalGold = rawGold + vendorTrash + rareItems + gathering + questRewards + vendorSales + pickpocketTotal

    -- Ensure sparkline exists and update it
    if not panel.sparklineFrame then
        panel.sparklineFrame = CreateFrame("Frame", nil, panel)
        panel.sparklineFrame:SetPoint("TOPLEFT", panel.rateText, "BOTTOMLEFT", 0, -4)
        panel.sparklineFrame:SetPoint("RIGHT", panel, "RIGHT", -PANEL_PADDING, 0)
        panel.sparklineFrame:SetHeight(18)
        EnsureSparkline(panel.sparklineFrame, 15)
    end
    local history = GetMetricHistory(session)
    local goldBuffer = GetMetricBuffer(history, "gold")
    local goldColor = MICROBAR_COLORS.GOLD and MICROBAR_COLORS.GOLD.fill or {1, 0.82, 0, 0.85}
    local cardCfg = GoldPH_Settings.metricCards
    local sampleInterval = (history and history.sampleInterval) or (cardCfg and cardCfg.sampleInterval) or 10
    local sparkMinutes = (cardCfg and cardCfg.sparklineMinutes) or 15
    local maxSamples = history and math.floor((sparkMinutes * 60) / sampleInterval) or 90
    UpdateSparkline(panel.sparklineFrame, goldBuffer, goldColor, 18, maxSamples)

    -- Clear old breakdown rows
    for _, row in ipairs(panel.breakdownRows) do
        row:Hide()
    end
    panel.breakdownRows = {}

    -- Add breakdown rows (only show non-zero values); start below sparkline
    local rowHeight = 14
    local rowStep = 14
    local firstRowOffset = -74  -- Pull line items closer to sparkline
    local yOffset = firstRowOffset
    local categories = {
        {"Raw Gold", rawGold},
        {"Quest Rewards", questRewards},
        {"Vendor Sales", vendorSales},
        {"Vendor Trash", vendorTrash},
        {"AH / Rare Items", rareItems},
        {"Gathering", gathering},
        {"Pickpocketing", pickpocketTotal},
    }

    local durationHours = metrics.durationSec / 3600
    if durationHours == 0 then durationHours = 1 end  -- Avoid division by zero

    local rowCount = 0
    for _, cat in ipairs(categories) do
        local label, value = cat[1], cat[2]
        if value > 0 then
            local perHour = math.floor(value / durationHours)
            local pct = totalGold > 0 and math.floor((value / totalGold) * 100) or 0
            AddBreakdownRow(panel, yOffset, label,
                FormatAccountingShort(perHour) .. "/hr",
                FormatAccounting(value),
                string.format("%d%%", pct))
            yOffset = yOffset - rowStep
            rowCount = rowCount + 1
        end
    end
    -- If we have session total but no category breakdown (e.g. ledger mismatch), show at least session total
    if totalGold > 0 and rowCount == 0 then
        local perHour = durationHours > 0 and math.floor(totalGold / durationHours) or 0
        AddBreakdownRow(panel, yOffset, "Session total",
            FormatAccountingShort(perHour) .. "/hr",
            FormatAccounting(totalGold),
            "100%")
        rowCount = 1
    end

    -- Optional: show compact gathering nodes/hr summary when node data exists
    if session.gathering and session.gathering.totalNodes and session.gathering.totalNodes > 0 then
        local nodesPerHour = 0
        if metrics.durationHours and metrics.durationHours > 0 then
            nodesPerHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end

        local gatherLabel = string.format(
            "Nodes: %d (%d/hr)",
            session.gathering.totalNodes or 0,
            nodesPerHour
        )

        AddBreakdownRow(
            panel,
            yOffset,
            gatherLabel,
            "",
            "",
            ""
        )
        yOffset = yOffset - rowStep  -- luacheck: ignore 311
        rowCount = rowCount + 1
    end

    -- Resize panel to fit all breakdown rows without clipping.
    local rowsHeight = 0
    if rowCount > 0 then
        rowsHeight = ((rowCount - 1) * rowStep) + rowHeight
    end
    local contentBottom = math.abs(firstRowOffset) + rowsHeight + 10
    local goldPanelHeight = contentBottom
    if goldPanelHeight < 140 then goldPanelHeight = 140 end
    panel:SetHeight(goldPanelHeight)
    panel.goldPanelHeight = goldPanelHeight  -- So Update() can read it for container layout

    panel:Show()
end

-- Update XP Panel
local function UpdateXPPanel(panel, metrics)
    -- Always show in expanded mode to maintain middle row layout
    -- Only hide if player is at max level
    if UnitLevel("player") >= MAX_PLAYER_LEVEL then
        panel:Hide()
        return
    end

    -- Always show XP panel (even with 0 XP) to maintain layout on fresh start
    panel:Show()

    local xpGained = metrics.xpGained or 0
    local xpPerHour = metrics.xpPerHour or 0

    panel.totalValue:SetText(string.format("Total: %s", FormatNumber(xpGained)))
    panel.rateText:SetText(FormatNumber(xpPerHour) .. "/hr")
    panel.rawTotal:SetText(string.format("%s XP", FormatNumber(xpGained)))

    -- XP sources (TODO: need to add quest vs mob tracking to SessionManager)
    -- For now, show placeholder or single total
    -- Future: show Quest XP and Mob XP with percentages
end

-- Update Rep Panel
local function UpdateRepPanel(panel, metrics)
    local totalRep = metrics.repGained or 0
    local repHr = metrics.repPerHour or 0
    local totalStr = totalRep >= 0 and string.format("Total: +%d", totalRep) or string.format("Total: %d", totalRep)
    local rateStr = repHr >= 0 and string.format("+%d/hr", repHr) or string.format("%d/hr", repHr)
    panel.totalValue:SetText(totalStr)
    panel.rateText:SetText(rateStr)
    panel.rawTotal:SetText("")  -- Clear raw total for rep

    -- Clear old rows
    for _, row in ipairs(panel.breakdownRows) do
        row:Hide()
    end
    panel.breakdownRows = {}

    -- Show top 2 factions (SessionManager uses .gain per faction, can be negative)
    local factions = metrics.repTopFactions or {}
    local yOffset = -44  -- Tighter gap below rate text so 2 rows fit in 80px panel

    for i = 1, math.min(2, #factions) do
        local faction = factions[i]
        if not faction then break end
        local gain = faction.gain or 0  -- .gain from SessionManager (not .gained)
        local gainStr = gain >= 0 and string.format("+%d", gain) or string.format("%d", gain)
        AddRepBreakdownRow(panel, yOffset, faction.name or "?", gainStr)
        yOffset = yOffset - 16
    end

    -- "+X more..." text if more than 2 factions
    if #factions > 2 then
        local moreText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        moreText:SetPoint("TOPLEFT", panel, "TOPLEFT", PANEL_PADDING, yOffset)
        moreText:SetText(string.format("+%d more…", #factions - 2))
        moreText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
        -- Add to breakdown rows so it gets cleaned up next update
        table.insert(panel.breakdownRows, {Hide = function() moreText:Hide() end, moreText = moreText})
    end

    panel:Show()
end

-- Update Honor Panel
local function UpdateHonorPanel(panel, metrics)
    if not metrics.honorEnabled or (metrics.honorGained or 0) == 0 then
        panel:Hide()
        return
    end

    panel.totalValue:SetText(string.format("Total: %d", metrics.honorGained))
    panel.rateText:SetText(string.format("%d/hr", metrics.honorPerHour or 0))
    panel.rawTotal:SetText(string.format("%d honor", metrics.honorGained))

    -- Honor breakdown (TODO: need to add BG vs kills tracking to SessionManager)
    -- For now, show placeholder
    -- Future: show "Battleground / Bonus Honor" and "Honor from Kills" with percentages

    -- Reposition panel based on whether XP panel is shown
    panel:ClearAllPoints()
    if hudFrame.xpPanel:IsShown() then
        panel:SetPoint("TOPLEFT", hudFrame.xpPanel, "BOTTOMLEFT", 0, -PANEL_GAP)
    else
        panel:SetPoint("TOPLEFT", hudFrame.goldPanel, "BOTTOMLEFT", 0, -PANEL_GAP)
    end

    panel:Show()
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

local function FormatRateForCard(metricKey, rate)
    if metricKey == "gold" then
        return FormatAccountingShort(rate) .. "/hr"
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

local function FormatTotalForCard(metricKey, total)
    if metricKey == "gold" then
        return FormatAccounting(total)
    end
    return tostring(total)
end

-- Dynamically adjust HUD height based on the last visible row
-- Calculate grid positions for metric cards based on count
local function CalculateCardPositions(metricCount)
    local positions = {}

    if metricCount == 1 then
        -- Single card: centered in 242px container
        positions[1] = { x = 62, y = 0 }
    elseif metricCount == 2 then
        -- Two cards: horizontal row
        positions[1] = { x = 0, y = 0 }
        positions[2] = { x = 125, y = 0 }
    elseif metricCount == 3 then
        -- Three cards: 2x2 grid with bottom-right empty
        positions[1] = { x = 0, y = 0 }
        positions[2] = { x = 125, y = 0 }
        positions[3] = { x = 0, y = -108 }
    else
        -- Four cards: full 2x2 grid
        positions[1] = { x = 0, y = 0 }
        positions[2] = { x = 125, y = 0 }
        positions[3] = { x = 0, y = -108 }
        positions[4] = { x = 125, y = -108 }
    end

    return positions
end

-- Get metric breakdown for focus panel
local function GetMetricBreakdown(metricKey, session, metrics)
    if metricKey == "gold" then
        -- Parse Income:ItemsLooted:* accounts from ledger
    local vendorTrash = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:VendorTrash") or 0
    local rareMulti = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:RareMulti") or 0
    local gathering = GoldPH_Ledger:GetBalance(session, "Income:ItemsLooted:Gathering") or 0
        local total = vendorTrash + rareMulti + gathering

        if total > 0 then
            local pctVendor = math.floor((vendorTrash / total) * 100)
            local pctRare = math.floor((rareMulti / total) * 100)
            local pctGath = math.floor((gathering / total) * 100)
            return string.format("Loot Breakdown: Vendor %d%% | Rare %d%% | Gathering %d%%",
                pctVendor, pctRare, pctGath)
        end
    elseif metricKey == "rep" then
        -- Show top 3 factions if available
        if metrics.repTopFactions and #metrics.repTopFactions > 0 then
            local lines = {"Top Factions:"}
            for i = 1, math.min(3, #metrics.repTopFactions) do
                local faction = metrics.repTopFactions[i]
                table.insert(lines, string.format("  %s: +%d", faction.name, faction.gained))
            end
            return table.concat(lines, "\n")
        end
    elseif metricKey == "honor" then
        -- Show kills if available
        if metrics.honorKills and metrics.honorKills > 0 then
            local avgPerKill = math.floor(metrics.honorGained / metrics.honorKills)
            return string.format("Kills: %d  (Avg: %d honor/kill)", metrics.honorKills, avgPerKill)
        end
    end
    return nil  -- No breakdown available
end

-- Get metric data for a specific key (helper for focus panel)
local function GetMetricDataForKey(metricKey, metrics, session)
    local history = GetMetricHistory(session)
    local cardCfg = GoldPH_Settings.metricCards
    local sparkMinutes = (cardCfg and cardCfg.sparklineMinutes) or 15
    local sampleInterval = history and history.sampleInterval or (cardCfg and cardCfg.sampleInterval) or 10
    local maxSamples = math.floor((sparkMinutes * 60) / sampleInterval)
    if maxSamples <= 0 then maxSamples = nil end

    local buffer = GetMetricBuffer(history, metricKey)
    local rate = 0
    local total = 0
    local isActive = false

    if metricKey == "gold" then
        rate = metrics.totalPerHour
        total = metrics.totalValue
        isActive = true
    elseif metricKey == "xp" then
        rate = metrics.xpPerHour or 0
        total = metrics.xpGained or 0
        isActive = metrics.xpEnabled and rate > 0
    elseif metricKey == "rep" then
        rate = metrics.repPerHour or 0
        total = metrics.repGained or 0
        isActive = metrics.repEnabled and rate > 0
    elseif metricKey == "honor" then
        rate = metrics.honorPerHour or 0
        total = metrics.honorGained or 0
        isActive = metrics.honorEnabled and rate > 0
    end

    local peak = buffer and ComputePeak(buffer, maxSamples) or rate

    return {
        key = metricKey,
        label = METRIC_LABELS[metricKey] or metricKey,
        icon = METRIC_ICONS[metricKey],
        color = MICROBAR_COLORS[string.upper(metricKey)].fill,
        rate = rate,
        total = total,
        peak = peak,
        buffer = buffer,
        maxSamples = maxSamples,
        isActive = isActive,
    }
end

-- Render focus panel for a specific metric
local function RenderFocusPanel(metricKey)
    local session = GoldPH_SessionManager:GetActive()
    if not session or not hudFrame.focusPanel then return end

    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local focusPanel = hudFrame.focusPanel

    -- Get metric data
    local metricData = GetMetricDataForKey(metricKey, metrics, session)
    if not metricData then return end

    -- Set header
    focusPanel.icon:SetTexture(metricData.icon)
    focusPanel.header:SetText("Focus: " .. metricData.label)

    -- Stats line: "124g/hr  Total: 1,560g  Peak: 185g/hr"
    local statsLine = string.format("%s  Total: %s  Peak: %s",
        FormatRateForCard(metricKey, metricData.rate),
        FormatTotalForCard(metricKey, metricData.total),
        FormatRateForCard(metricKey, metricData.peak))
    focusPanel.statsText:SetText(statsLine)

    -- Extended sparkline (30-60 min window, 30 bars)
    local buffer = metricData.buffer
    local maxSamples = math.min(buffer and buffer.count or 0, 360)  -- 60 min at 10s intervals
    UpdateSparkline(focusPanel.sparklineFrame, buffer, metricData.color, 50, maxSamples)

    -- Breakdown (conditional based on metric type)
    local breakdownText = GetMetricBreakdown(metricKey, session, metrics)
    if breakdownText then
        focusPanel.breakdownText:SetText(breakdownText)
        focusPanel.breakdownText:Show()
    else
        focusPanel.breakdownText:Hide()
    end
end

-- Update HUD display
function GoldPH_HUD:Update()
    if not hudFrame then
        return
    end

    local session = GoldPH_SessionManager:GetActiveSession()

    if not session then
        hudFrame:Hide()
        -- Reset metric states on session end
        for _, state in pairs(metricStates) do
            state.displayRate = 0
            state.peak = 0
            state.lastUpdatedText = ""
        end
        return
    end

    -- Show HUD if session active
    if not hudFrame:IsShown() then
        hudFrame:Show()
    end

    -- Get metrics
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local isPaused = GoldPH_SessionManager:IsPaused(session)

    -- Pause button: two vertical bars (||) when running, right arrow (>) when paused
    if hudFrame.pauseBarLeft and hudFrame.pauseBarRight and hudFrame.pausePlayArrow then
        if isPaused then
            hudFrame.pauseBarLeft:Hide()
            hudFrame.pauseBarRight:Hide()
            hudFrame.pausePlayArrow:Show()
        else
            hudFrame.pauseBarLeft:Show()
            hudFrame.pauseBarRight:Show()
            hudFrame.pausePlayArrow:Hide()
        end
    end

    -- Update timers (both collapsed and expanded versions) with pH brand colors
    local timerText = GoldPH_SessionManager:FormatDuration(metrics.durationSec)
    -- Use pH ACCENT_BAD for paused (red), pH TEXT_MUTED for normal
    local timerColor = isPaused and {0.78, 0.32, 0.28} or PH_TEXT_MUTED

    hudFrame.headerTimer:SetText(timerText)
    hudFrame.headerTimer:SetTextColor(timerColor[1], timerColor[2], timerColor[3])

    -- Second header line removed - no longer updating headerGold or headerTimer2

    -- Update micro-bars if collapsed and enabled
    local cfg = GoldPH_Settings.microBars
    if cfg and cfg.enabled and GoldPH_Settings.hudMinimized then
        UpdateMicroBars(session, metrics)
    end

    -- Expanded rectangular panels (only when expanded and enabled)
    local cardCfg = GoldPH_Settings.metricCards
    -- Default to enabled if not set (for backward compatibility)
    local cardsEnabled = cardCfg and (cardCfg.enabled ~= false)
    local useRectangularPanels = not GoldPH_Settings.hudMinimized and cardsEnabled
    if useRectangularPanels then
        -- Hide old metric cards if they exist
        if hudFrame.metricCards then
            for _, card in pairs(hudFrame.metricCards) do
                card:Hide()
            end
        end

        -- Ensure panels exist before updating
        EnsureMetricPanels()

        -- Update panels (with nil checks)
        if hudFrame.goldPanel then
            UpdateGoldPanel(hudFrame.goldPanel, metrics, session)
        end
        if hudFrame.xpPanel then
            UpdateXPPanel(hudFrame.xpPanel, metrics)
        end
        if hudFrame.repPanel then
            UpdateRepPanel(hudFrame.repPanel, metrics)
        end
        if hudFrame.honorPanel then
            UpdateHonorPanel(hudFrame.honorPanel, metrics)
        end

        -- Calculate container height dynamically (gold panel height grows with breakdown rows)
        local goldPanelHeight = (hudFrame.goldPanel and hudFrame.goldPanel.goldPanelHeight) or 140
        local containerHeight = goldPanelHeight
        if hudFrame.xpPanel:IsShown() or hudFrame.repPanel:IsShown() then
            containerHeight = containerHeight + PANEL_GAP + 80  -- Middle row
        end
        if hudFrame.honorPanel:IsShown() then
            containerHeight = containerHeight + PANEL_GAP + 90  -- Honor panel
        end

        hudFrame.metricCardContainer:SetHeight(containerHeight)
        hudFrame.metricCardContainer:Show()

        -- Update HUD frame height to fit panels + padding
        -- Top: PADDING (12) + title/timer row (~14) + gap to container (12) = 38px
        -- Content: containerHeight (gold 140 + optional middle row 6+80 + optional honor 6+90)
        -- Bottom: padding + backdrop inset so content isn't clipped
        local expandedHeaderHeight = 38
        local bottomPadding = 12 + 4  -- padding + backdrop bottom inset
        local totalHeight = expandedHeaderHeight + containerHeight + bottomPadding
        hudFrame:SetHeight(totalHeight)

        -- Sample metric history for future use (sparklines, etc.)
        GoldPH_SessionManager:SampleMetricHistory(session, metrics)
    else
        -- Minimized or cards disabled: hide panel container
        if hudFrame.metricCardContainer then
            hudFrame.metricCardContainer:Hide()
        end
    end
end

-- Show HUD
function GoldPH_HUD:Show()
    if not hudFrame then
        self:Initialize()
    end

    if hudFrame then
        hudFrame:Show()
        -- Apply minimize state so frame size (width/height) and content match hudMinimized
        self:ApplyMinimizeState()

        -- Save visibility state
        GoldPH_Settings.hudVisible = true
    end
end

-- Hide HUD
function GoldPH_HUD:Hide()
    if hudFrame then
        hudFrame:Hide()

        -- Save visibility state
        GoldPH_Settings.hudVisible = false
    end
end

-- Toggle HUD visibility
function GoldPH_HUD:Toggle()
    if not hudFrame then
        return
    end

    if hudFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Toggle minimize state
function GoldPH_HUD:ToggleMinimize()
    if not hudFrame then
        return
    end

    -- Toggle the minimized state
    GoldPH_Settings.hudMinimized = not GoldPH_Settings.hudMinimized
    self:ApplyMinimizeState()
end

-- Apply minimize/expand state to HUD
function GoldPH_HUD:ApplyMinimizeState()
    if not hudFrame then
        return
    end

    local isMinimized = GoldPH_Settings.hudMinimized

    -- Update button texture: "+" when minimized, "-" when expanded
    if isMinimized then
        hudFrame.minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        hudFrame.minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    else
        hudFrame.minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        hudFrame.minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    end

    -- Header: title always visible; second line (gold | timer) removed per user request
    -- headerContainer remains hidden

    -- Only toggle expanded content below header
    local cardCfg = GoldPH_Settings.metricCards
    -- Default to enabled if not set (for backward compatibility)
    local cardsEnabled = cardCfg and (cardCfg.enabled ~= false)
    local useCards = not isMinimized and cardsEnabled
    
    if useCards then
        if hudFrame.metricCardContainer then
            hudFrame.metricCardContainer:Show()
        end
    else
        if hudFrame.metricCardContainer then
            hudFrame.metricCardContainer:Hide()
        end
    end

    -- Show/hide micro-bar tiles based on state
    -- When minimized: tiles are always shown (grayed out if inactive)
    -- When expanded: hide tiles (expanded view shows full details)
    if isMinimized then
        -- Tiles will be positioned and updated by UpdateMicroBars
        RepositionTiles(true)
    else
        -- Expanded: hide microbar tiles (full expanded view is shown instead)
        for _, metricKey in ipairs(METRIC_ORDER) do
            local state = metricStates[metricKey]
            if state and state.tile then
                state.tile:Hide()
            end
        end
    end

    -- Close focus panel if currently open when minimizing
    if isMinimized and hudFrame.focusPanel and hudFrame.focusPanel:IsShown() then
        GoldPH_HUD:HideFocusPanel()
    end

    -- Adjust frame size while maintaining top position
    -- Store current top position before changing size
    local point, relativeTo, relativePoint, xOfs, yOfs = hudFrame:GetPoint()

    if isMinimized then
        hudFrame:SetHeight(FRAME_HEIGHT_MINI)
        -- Frame width for exactly 4 metrics: left pad + 4*tile + 3*gap + right pad
        -- PADDING (12) + 4*50 + 3*14 + PADDING (12) = 12 + 200 + 42 + 12 = 266
        hudFrame:SetWidth(266)
    else
        -- Expanded: width for rectangular panels; height set in Update()
        hudFrame:SetWidth(FRAME_WIDTH_EXPANDED)
    end

    -- Restore top position to prevent jumping
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

    -- Update display
    self:Update()
end

-- Show focus panel for the selected metric
function GoldPH_HUD:ShowFocusPanel()
    if not hudFrame or not hudFrame.focusPanel then return end
    local key = hudFrame.metricFocusKey
    if not key then return end

    RenderFocusPanel(key)
    hudFrame.focusPanel:Show()
end

-- Hide focus panel
function GoldPH_HUD:HideFocusPanel()
    if not hudFrame or not hudFrame.focusPanel then return end
    hudFrame.metricFocusKey = nil
    hudFrame.focusPanel:Hide()
end

-- Export module
_G.GoldPH_HUD = GoldPH_HUD
