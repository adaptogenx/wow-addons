--[[
    UI_HUD.lua - Heads-up display for pH

    Shows real-time session metrics in accounting-style layout.
]]

-- luacheck: globals pH_Insights pH_Tooltip pH_Settings pH_History pH_Ledger pH_SessionManager pH_Index SlashCmdList pH_AutoSession

local _, addon = ...
local PHUI = addon.UI.PHUI

local pH_HUD = {}

local hudFrame = nil
local updateTimer = 0
local UPDATE_INTERVAL = 1.0 -- Update every 1 second
local UpdateStartPanelContent  -- Forward declaration (defined after Initialize)

-- Layout constants (single source of truth)
local PADDING = PHUI.Spacing.PADDING  -- Inner padding on all sides
local HEADER_HEIGHT = 20        -- Header row height (logo, buttons, icons)
local BODY_GAP = 6              -- Gap between header and body
local TILE_HEIGHT = 23          -- Metric cell: icon/rate row (12) + gap (3) + sparkline (8)
local TILE_WIDTH = 54
local TILE_GAP = 8              -- Divider sits centered in this gap
local SPARK_HEIGHT = 8

-- Frame heights computed from content
local function ComputeMicroFrameHeight()
    return PADDING + HEADER_HEIGHT + BODY_GAP + TILE_HEIGHT + PADDING  -- 68
end
local function ComputeStartCollapsedHeight()
    return PADDING + HEADER_HEIGHT + PADDING  -- 44, no body
end

local FRAME_WIDTH = 180
local FRAME_HEIGHT = 180        -- Base; expanded height computed dynamically
local FRAME_HEIGHT_MINI = ComputeMicroFrameHeight()

-- Glance width (unchanged from the original compact HUD)
local GLANCE_WIDTH = 266

-- Shared PHUI palette
local PH_TEXT_PRIMARY = PHUI.Colors.TEXT_PRIMARY
local PH_TEXT_MUTED = PHUI.Colors.TEXT_MUTED
local PH_ACCENT_GOOD = PHUI.Colors.ACCENT_GOOD
local PH_BG_DARK = PHUI.Colors.BG_DARK
local PH_BG_PARCHMENT = PHUI.Colors.BG_PARCHMENT
local PH_BORDER_BRONZE = PHUI.Colors.BORDER_BRONZE
local PH_ACCENT_BAD = PHUI.Colors.ACCENT_BAD
local PH_ACCENT_GOLD_INCOME = PHUI.Colors.ACCENT_GOLD

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

local METRIC_TOOLTIP_LABELS = {
    gold = "Gold / Hour",
    xp = "XP / Hour",
    rep = "Rep / Hour",
    honor = "Honor / Hour",
}

-- Header icon textures (Classic-safe, order: pause/resume, history, min/max)
local HEADER_ICON_PAUSE = "Interface\\TimeManager\\PauseButton"
local HEADER_ICON_PLAY = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
local HEADER_ICON_HISTORY = "Interface\\QUESTFRAME\\UI-QuestLog-BookIcon"
local HEADER_ICON_MINUS = "Interface\\Buttons\\UI-MinusButton-Up"
local HEADER_ICON_PLUS = "Interface\\Buttons\\UI-PlusButton-Up"
local HEADER_ICON_SETTINGS = "Interface\\Buttons\\UI-OptionsButton"
local ICON_GAP = PHUI.Spacing.ICON_GAP
local ICON_SIZE = PHUI.Spacing.ICON_BUTTON_SIZE  -- Match stop button height
local OVERFLOW_ICON_SIZE = 14
local PRIMARY_BTN_WIDTH = 78
local STOP_BTN_WIDTH = 48

-- Color keys mapping for micro-bar colors
local colorKeys = { gold = "GOLD", xp = "XP", rep = "REP", honor = "HONOR" }

-- Runtime state for micro-bars (not persisted)
local metricStates = {
    gold = { key = "gold", displayRate = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    xp = { key = "xp", displayRate = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    rep = { key = "rep", displayRate = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil, hasProjected = false, projectedTotal = 0, projectedItems = {}, projectedItemCount = 0 },
    honor = { key = "honor", displayRate = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
}

-- Fixed order for metric display: gold, rep, xp, honor
local METRIC_ORDER = { "gold", "rep", "xp", "honor" }

local HideOverflowMenu
local LayoutHeader
local lastSessionStateKey = nil

--------------------------------------------------
-- Micro-Bar Helper Functions
--------------------------------------------------

local FormatRateBase

-- Format rate for the Glance cell (compact; callers add the /h suffix)
local function FormatRateForMicroBar(metricKey, rate)
    return FormatRateBase(metricKey, rate)
end

function FormatRateBase(metricKey, rate)
    if metricKey == "gold" then
        -- Inline FormatAccountingShort logic for gold
        if not rate or rate == 0 then
            return "0g"
        end
        local isNegative = rate < 0
        local formatted = pH_Ledger:FormatMoneyShort(math.abs(rate))
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

local FormatEtaInfinity = pH_Insights.FormatEtaInfinity
local FormatEtaCompact = pH_Insights.FormatEtaCompact
local FormatInt = pH_Insights.FormatInt
local BuildXPEtaData = pH_Insights.BuildXPEtaData
local BuildEtaRangeText = pH_Insights.BuildEtaRangeText

local function BuildXPEtaLine(data)
    local remainingXP = data and tonumber(data.remainingXP) or 0
    local etaText = BuildEtaRangeText(
        data and tonumber(data.etaRecentSec) or nil,
        data and tonumber(data.etaSessionSec) or nil
    )
    return string.format("To level: %s xp (%s)", FormatInt(remainingXP), etaText)
end

local function BuildXPSessionAvgLine(data)
    local sessionRate = data and tonumber(data.sessionPerHour) or 0
    return string.format("Session avg: %s/hr", FormatInt(sessionRate))
end

local function BuildXPRecentAvgLine(data)
    local recentRate = data and tonumber(data.recentPerHour) or 0
    return string.format("Recent avg: %s/hr", FormatInt(recentRate))
end

local function BuildXPSourcesHeaderLine(metrics)
    local totalXP = (metrics and tonumber(metrics.xpGained)) or 0
    return string.format("Total XP: %s", FormatInt(totalXP))
end

local function BuildXPMobSourceLine(metrics)
    local sources = (metrics and metrics.xpBySource) or {}
    local mobXP = tonumber(sources.mob) or 0
    return string.format("  - Mob +%s", FormatInt(mobXP))
end

local function BuildXPQuestSourceLine(metrics)
    local sources = (metrics and metrics.xpBySource) or {}
    local questXP = tonumber(sources.quest) or 0
    return string.format("  - Quest +%s", FormatInt(questXP))
end

local function BuildXPOtherSourceLine(metrics)
    local sources = (metrics and metrics.xpBySource) or {}
    local otherXP = tonumber(sources.other) or 0
    if otherXP <= 0 then
        return nil
    end
    return string.format("  - Other +%s", FormatInt(otherXP))
end

local BuildRepTooltipModel = pH_Insights.BuildRepModel

local function RenderRepTooltip(model)
    local data = model or {}
    local sessionAvg = tonumber(data.sessionAvg) or 0
    local currentAvg = tonumber(data.currentAvg) or 0
    local gainedFactions = data.gainedFactions or {}
    local potentialRows = data.potentialRows or {}

    GameTooltip:AddLine(string.format("Session avg: %s/hr", FormatInt(sessionAvg)), 0.86, 0.82, 0.70)
    GameTooltip:AddLine(string.format("Current avg: %s/hr", FormatInt(currentAvg)), 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ", 0.62, 0.58, 0.50)

    if #gainedFactions == 0 then
        GameTooltip:AddLine("No faction rep gained yet.", 0.86, 0.82, 0.70)
    else
        for i = 1, #gainedFactions do
            local row = gainedFactions[i]
            GameTooltip:AddLine(
                string.format(
                    "%s +%s",
                    row.name or "Unknown",
                    FormatInt(row.gain or 0)
                ),
                0.86, 0.82, 0.70
            )
            GameTooltip:AddLine(
                string.format(
                    "- %s / %s to %s",
                    FormatInt(row.remainingRep or 0),
                    row.etaSessionText or FormatEtaInfinity()
                    ,
                    row.nextStanding or "Unknown"
                ),
                0.8, 0.8, 0.8
            )
        end
    end
    GameTooltip:AddLine(" ", 0.62, 0.58, 0.50)

    if #potentialRows == 0 then
        GameTooltip:AddLine("Potential rep: none", 0.3, 1.0, 0.3)
    else
        GameTooltip:AddLine("Potential rep:", 0.3, 1.0, 0.3)
        for i = 1, #potentialRows do
            local row = potentialRows[i]
            GameTooltip:AddLine(
                string.format("%s +%s", row.factionName or "Unknown", FormatInt(row.potentialRep or 0)),
                0.86, 0.82, 0.70
            )
            local hintList = row.hintList or {}
            if #hintList > 0 then
                local parts = {}
                for j = 1, #hintList do
                    local hint = hintList[j]
                    table.insert(parts, string.format("%s/%s %s", FormatInt(hint.count or 0), FormatInt(hint.bundleSize or 1), hint.itemName or "Rep Item"))
                end
                GameTooltip:AddLine(
                    "- " .. table.concat(parts, ", "),
                    0.8, 0.8, 0.8
                )
            else
                GameTooltip:AddLine(
                    "- no contributing items tracked",
                    0.8, 0.8, 0.8
                )
            end
        end
    end

    GameTooltip:AddLine(" ", 0.62, 0.58, 0.50)
    GameTooltip:AddLine("- Potential rep means rep you could gain if turning in quest items (normalized per item).", 0.62, 0.58, 0.50, true)
    GameTooltip:AddLine("- Potential rep will be converted to gained rep if turned in during this session.", 0.62, 0.58, 0.50, true)
    GameTooltip:AddLine("- Sparkline: recent rate samples (last 30 min).", 0.62, 0.58, 0.50, true)
end

local function FormatMetricRateTooltip(metricKey, ratePerHour)
    local value = tonumber(ratePerHour) or 0
    if metricKey == "gold" then
        return string.format("%s/hr", pH_Ledger:FormatMoneyShort(value))
    end
    return string.format("%s/hr", FormatInt(value))
end

local function ShowMicroMetricTooltip(anchor, metricKey, state)
    if not anchor or not metricKey or not state then
        return
    end
    local headerText = METRIC_TOOLTIP_LABELS[metricKey] or metricKey
    if metricKey == "rep" then
        headerText = "Rep/Hour"
    end
    local currentText = state.lastUpdatedText ~= "" and state.lastUpdatedText or "0"
    pH_Tooltip:Own(anchor)
    GameTooltip:SetText(headerText)
    if metricKey ~= "rep" and metricKey ~= "xp" then
        GameTooltip:AddLine(string.format("Current: %s", currentText), 0.86, 0.82, 0.70)
        GameTooltip:AddLine("Recent avg: " .. FormatMetricRateTooltip(metricKey, state.recentAvgRate or 0), 0.8, 0.8, 0.8)
    end
    if metricKey == "xp" then
        local xpData = state.tooltipData or {}
        GameTooltip:AddLine(BuildXPSessionAvgLine(xpData), 0.86, 0.82, 0.70)
        GameTooltip:AddLine(BuildXPRecentAvgLine(xpData), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(BuildXPEtaLine(state.tooltipData), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(BuildXPSourcesHeaderLine(state.metrics), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(BuildXPMobSourceLine(state.metrics), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(BuildXPQuestSourceLine(state.metrics), 0.8, 0.8, 0.8)
        local otherLine = BuildXPOtherSourceLine(state.metrics)
        if otherLine then
            GameTooltip:AddLine(otherLine, 0.8, 0.8, 0.8)
        end
        if xpData.etaAdjusted then
            GameTooltip:AddLine("Recent pace adjusted for burst XP", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine(" ", 0.62, 0.58, 0.50)
        GameTooltip:AddLine("Sparkline: recent rate samples (last 30 min).", 0.62, 0.58, 0.50, true)
    elseif metricKey == "rep" then
        RenderRepTooltip(state.tooltipData)
    else
        GameTooltip:AddLine("Sparkline: recent rate samples (last 30 min).", 0.62, 0.58, 0.50, true)
        if state.icon and state.icon:GetAlpha() < 1 then
            GameTooltip:AddLine("No tracked gain this session.", 0.62, 0.58, 0.50)
        end
    end
    GameTooltip:Show()
end

-- Reposition tiles horizontally in fixed order (gold, rep, xp, honor) and
-- place a divider in the gap between neighbouring visible tiles.
local function RepositionTiles()
    local orderedTiles = {}
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile and state.tile:IsShown() then
            table.insert(orderedTiles, state)
        end
    end

    local dividers = hudFrame.tileDividers or {}
    for i, state in ipairs(orderedTiles) do
        state.tile:ClearAllPoints()
        if i == 1 then
            state.tile:SetPoint("TOPLEFT", hudFrame.bodyContainer, "TOPLEFT", 0, 0)
        else
            state.tile:SetPoint("TOPLEFT", orderedTiles[i - 1].tile, "TOPRIGHT", TILE_GAP, 0)
        end
    end
    for i, divider in ipairs(dividers) do
        divider:ClearAllPoints()
        local left = orderedTiles[i]
        if left and orderedTiles[i + 1] then
            divider:SetPoint("TOP", left.tile, "TOPRIGHT", TILE_GAP / 2, 0)
            divider:SetPoint("BOTTOM", left.tile, "BOTTOMRIGHT", TILE_GAP / 2, 0)
            divider:Show()
        else
            divider:Hide()
        end
    end
end

local SPARK_MINUTES = 30

-- Redraw a tile's sparkline only when a new sample has been recorded.
local function RefreshSparkline(state, metricKey, session, color)
    local history = session and session.metricHistory
    local stamp = history and history.lastSampleAt or 0
    local sig = tostring(session and session.id) .. ":" .. stamp .. ":" .. tostring(color)
    if state.sparkSig == sig then return end
    state.sparkSig = sig
    state.spark:SetColor(color)
    state.spark:SetValues((pH_SessionManager:GetMetricSeries(session, metricKey, SPARK_MINUTES)))
end

-- Update micro-bars for collapsed state
local function UpdateMicroBars(session, metrics)
    local cfg = pH_Settings.microBars
    if not cfg then return end

    -- Update each metric in fixed order
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile then
            local sessionAvgRate = 0
            local recentAvgRate = 0

            -- Extract raw rate from metrics
            if metricKey == "gold" then
                sessionAvgRate = metrics.totalPerHour or 0
                recentAvgRate = metrics.goldRecentPerHourBucketed or 0
            elseif metricKey == "xp" then
                sessionAvgRate = metrics.xpPerHour or 0
                recentAvgRate = metrics.xpRecentPerHourBucketed or 0
                state.tooltipData = BuildXPEtaData(metrics)
            elseif metricKey == "rep" then
                sessionAvgRate = metrics.repPerHour or 0
                recentAvgRate = metrics.repRecentPerHourBucketed or 0
                local projectedTotal = metrics.repPotentialTotal or 0
                local projectedItems = metrics.repPotentialItems or {}
                local projectedApprox = metrics.repPotentialApprox and true or false
                state.hasProjected = (#projectedItems > 0)
                state.projectedTotal = projectedTotal
                state.projectedApprox = projectedApprox
                state.projectedItemCount = #projectedItems
                state.projectedItems = projectedItems
                state.tooltipData = BuildRepTooltipModel(metrics, sessionAvgRate, recentAvgRate)
            elseif metricKey == "honor" then
                sessionAvgRate = metrics.honorPerHour or 0
                recentAvgRate = metrics.honorRecentPerHourBucketed or 0
            end

            -- Hide XP tile at max level; always show other tiles (gray out if inactive)
            if metricKey == "xp" and pH_API:GetPlayerLevel() >= pH_API:GetMaxPlayerLevel(70) then
                state.tile:Hide()
            else
                state.tile:Show()
                state.icon:Show()  -- Ensure icon is always visible
            end
            state.sessionAvgRate = sessionAvgRate
            state.recentAvgRate = recentAvgRate
            state.metrics = metrics

            local isActive = (sessionAvgRate > 0) or (recentAvgRate > 0)

            if isActive then
                -- Keep tile text stable with session context while bar fill reflects recent pace.
                state.displayRate = sessionAvgRate
                -- Update text (avoid string churn)
                local newText = FormatRateForMicroBar(metricKey, state.displayRate)
                if metricKey == "rep" and state.hasProjected then
                    newText = newText .. "*"
                end
                if state.lastUpdatedText ~= newText then
                    state.valueText:SetText(newText)
                    state.lastUpdatedText = newText
                end

                -- Set active colors (full opacity)
                state.icon:SetVertexColor(1, 1, 1)  -- Full color, no tinting
                state.icon:SetAlpha(1.0)  -- Full opacity
                state.valueText:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
                local colorKey = colorKeys[metricKey]
                RefreshSparkline(state, metricKey, session, MICROBAR_COLORS[colorKey].fill)
            else
                -- Inactive: gray out (reduced opacity)
                local inactiveText = "0"
                if metricKey == "rep" and state.hasProjected then
                    inactiveText = "0*"
                end
                state.valueText:SetText(inactiveText)
                state.lastUpdatedText = inactiveText
                
                -- Gray out icon (keep visible but muted - use gray tint with reduced opacity)
                state.icon:SetVertexColor(0.6, 0.6, 0.6)  -- Gray tint
                state.icon:SetAlpha(0.7)  -- Reduced opacity but still visible
                state.icon:Show()  -- Ensure icon is always visible
                state.valueText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3], 0.8)
                -- Flat, dimmed sparkline
                RefreshSparkline(state, metricKey, session, PHUI.Colors.TEXT_DISABLED)
            end
        end
    end

    -- Reposition tiles horizontally in fixed order (collapsed layout)
    RepositionTiles()
end

-- CreateHeaderIcons - icon row shared by all HUD states
-- Order (right to left): Session detail | History | Overflow
-- Re-anchor the header controls for the current state (called from Update).
LayoutHeader = function(hasSession)
    local gap = ICON_GAP
    hudFrame.stopBtn:ClearAllPoints()
    hudFrame.stopBtn:SetPoint("RIGHT", hudFrame.minMaxBtn, "LEFT", -gap, 0)
    hudFrame.pauseBtn:ClearAllPoints()
    hudFrame.pauseBtn:SetPoint("RIGHT", hudFrame.stopBtn, "LEFT", -gap, 0)
    hudFrame.overflowBtn:ClearAllPoints()
    hudFrame.overflowBtn:SetPoint("RIGHT", hasSession and hudFrame.pauseBtn or hudFrame.stopBtn, "LEFT", -gap, 0)
    hudFrame.historyBtn:ClearAllPoints()
    hudFrame.historyBtn:SetPoint("RIGHT", hasSession and hudFrame.pauseBtn or hudFrame.stopBtn, "LEFT", -gap, 0)
end

local function SetMinMaxGlyph(btn, texture, tooltip)
    btn.icon:SetTexture(texture)
    btn.tooltipText = tooltip
end

local function CreateHeaderIcons(parent)
    if not parent then return end

    -- Detail / start-panel toggle (rightmost). Boxed shared icon button; glyph and
    -- tooltip are swapped per state via SetMinMaxGlyph.
    local minMaxBtn = PHUI.CreateIconButton(parent, ICON_SIZE, HEADER_ICON_PLUS)
    minMaxBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PADDING, -PADDING)
    minMaxBtn.tooltipText = "Session detail"
    minMaxBtn:HookScript("OnEnter", function(self)
        if self.tooltipText then
            pH_Tooltip:Own(self)
            GameTooltip:SetText(self.tooltipText)
            GameTooltip:Show()
        end
    end)
    minMaxBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    minMaxBtn:SetScript("OnClick", function()
        HideOverflowMenu()
        pH_HUD:OpenSessionDetail()
    end)
    parent.minMaxBtn = minMaxBtn

    -- History (middle)
    local historyBtn = PHUI.CreateIconButton(parent, ICON_SIZE, HEADER_ICON_HISTORY, {
        tooltipText = "View session history",
        onClick = function()
            HideOverflowMenu()
            pH_History:Toggle()
        end,
    })
    historyBtn:SetPoint("RIGHT", minMaxBtn, "LEFT", -ICON_GAP, 0)
    parent.historyBtn = historyBtn

    -- Overflow menu trigger (leftmost icon)
    local overflowBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    overflowBtn:SetSize(ICON_SIZE, ICON_SIZE)
    overflowBtn:SetPoint("RIGHT", historyBtn, "LEFT", -ICON_GAP, 0)
    overflowBtn:SetBackdrop(PHUI.Backdrops.ICON_BUTTON)
    overflowBtn:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.9)
    overflowBtn:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
    local overflowText = overflowBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    overflowText:SetPoint("CENTER", 0, 0)
    overflowText:SetText("...")
    overflowText:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
    overflowBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3], 1.0)
        pH_Tooltip:Own(self)
        GameTooltip:SetText("More actions")
        GameTooltip:Show()
    end)
    overflowBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
        GameTooltip:Hide()
    end)
    parent.overflowBtn = overflowBtn
end

HideOverflowMenu = function()
    if not hudFrame then return end
    if hudFrame.overflowMenuBackdrop then
        hudFrame.overflowMenuBackdrop:Hide()
    end
    if hudFrame.overflowMenu then
        hudFrame.overflowMenu:Hide()
    end
end

local function ToggleOverflowMenu()
    if not hudFrame or not hudFrame.overflowMenu or not hudFrame.overflowBtn then
        return
    end

    if hudFrame.overflowMenu:IsShown() then
        HideOverflowMenu()
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    local isPaused = session and pH_SessionManager:IsPaused(session)
    local function SetOverflowItemState(btn, tooltipText, isDisabled)
        if not btn then
            return
        end
        btn.tooltipText = tooltipText
        btn.isActionDisabled = isDisabled and true or false
        local alpha = btn.isActionDisabled and 0.45 or 1.0
        if btn.icon then
            btn.icon:SetAlpha(alpha)
        end
        if btn.text then
            btn.text:SetAlpha(alpha)
        end
    end

    if hudFrame.overflowPauseBtn and hudFrame.overflowPauseBtn.icon then
        if not session then
            hudFrame.overflowPauseBtn.icon:SetTexture(HEADER_ICON_PAUSE)
            SetOverflowItemState(hudFrame.overflowPauseBtn, "Pause session (no active session)", true)
        elseif isPaused then
            hudFrame.overflowPauseBtn.icon:SetTexture(HEADER_ICON_PLAY)
            SetOverflowItemState(hudFrame.overflowPauseBtn, "Resume session", false)
        else
            hudFrame.overflowPauseBtn.icon:SetTexture(HEADER_ICON_PAUSE)
            SetOverflowItemState(hudFrame.overflowPauseBtn, "Pause session", false)
        end
    end

    if hudFrame.overflowStopBtn then
        if session then
            SetOverflowItemState(hudFrame.overflowStopBtn, "Stop session", false)
        else
            SetOverflowItemState(hudFrame.overflowStopBtn, "Stop session (no active session)", true)
        end
    end

    hudFrame.overflowMenu:ClearAllPoints()
    hudFrame.overflowMenu:SetPoint("TOPLEFT", hudFrame.overflowBtn, "BOTTOMLEFT", 0, -4)

    if hudFrame.overflowMenuBackdrop then
        hudFrame.overflowMenuBackdrop:Show()
    end
    hudFrame.overflowMenu:Show()
end

-- Initialize HUD
function pH_HUD:Initialize()
    -- Create main frame with BackdropTemplate for border support
    hudFrame = CreateFrame("Frame", "pH_HUD_Frame", UIParent, "BackdropTemplate")
    hudFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    hudFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)

    PHUI.ApplyBackdrop(hudFrame, { backdrop = PHUI.Backdrops.PANEL })

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

    -- Header icon row (pause/resume, history, minimize/maximize) - visible in all three states
    CreateHeaderIcons(hudFrame)

    -- Primary session button (Start/Stop/Resume based on state)
    local stopBtn = CreateFrame("Button", nil, hudFrame, "BackdropTemplate")
    stopBtn:SetSize(PRIMARY_BTN_WIDTH, 20)
    stopBtn:SetPoint("RIGHT", hudFrame.overflowBtn, "LEFT", -ICON_GAP, 0)
    stopBtn:SetBackdrop(PHUI.Backdrops.ICON_BUTTON)
    stopBtn:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.9)
    stopBtn:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
    local stopBtnText = stopBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stopBtnText:SetPoint("CENTER", 0, 0)
    stopBtnText:SetText("Stop")
    stopBtnText:SetTextColor(PH_ACCENT_BAD[1], PH_ACCENT_BAD[2], PH_ACCENT_BAD[3])
    stopBtn.textObj = stopBtnText  -- for Update() to switch Start/Stop
    hudFrame.stopBtn = stopBtn
    hudFrame.primarySessionBtn = stopBtn

    -- Pause / resume toggle (active session only), left of Stop
    local headerPauseBtn = PHUI.CreateIconButton(hudFrame, ICON_SIZE, HEADER_ICON_PAUSE)
    headerPauseBtn.tooltipText = "Pause session"
    headerPauseBtn:HookScript("OnEnter", function(self)
        pH_Tooltip:Own(self)
        GameTooltip:SetText(self.tooltipText)
        GameTooltip:Show()
    end)
    headerPauseBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    headerPauseBtn:SetScript("OnClick", function()
        HideOverflowMenu()
        local active = pH_SessionManager:GetActiveSession()
        if not active then return end
        local ok, message
        if pH_SessionManager:IsPaused(active) then
            ok, message = pH_SessionManager:ResumeSession("manual", "hud_pause")
        else
            ok, message = pH_SessionManager:PauseSession("manual", "hud_pause")
        end
        if ok then pH_HUD:Update() end
        if message then print("[pH] " .. message) end
    end)
    headerPauseBtn:Hide()
    hudFrame.pauseBtn = headerPauseBtn

    --------------------------------------------------
    -- Header row (fixed height, all elements vertically centered)
    --------------------------------------------------
    local HEADER_ROW_HEIGHT = HEADER_HEIGHT
    local headerRow = CreateFrame("Frame", nil, hudFrame)
    headerRow:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 0, -PADDING)
    headerRow:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", 0, -PADDING)
    headerRow:SetHeight(HEADER_ROW_HEIGHT)
    hudFrame.headerRow = headerRow

    -- Reposition icons to center in header row
    hudFrame.minMaxBtn:ClearAllPoints()
    hudFrame.minMaxBtn:SetPoint("RIGHT", headerRow, "RIGHT", -PADDING, 0)

    -- Title (always visible) - "pH" branding (lowercase p, uppercase H)
    local title = PHUI.CreateLabel(hudFrame, "primary", "pH", PHUI.Fonts.HEADER)
    title:SetPoint("LEFT", headerRow, "LEFT", PADDING, 0)
    hudFrame.title = title

    -- Timer (always visible, next to title)
    local headerTimer = PHUI.CreateLabel(hudFrame, "primary", "0m", PHUI.Fonts.NORMAL)
    headerTimer:SetPoint("LEFT", title, "RIGHT", 6, 0)
    headerTimer:SetPoint("RIGHT", hudFrame.pauseBtn, "LEFT", -6, 0)
    headerTimer:SetJustifyH("LEFT")
    hudFrame.headerTimer = headerTimer

    -- Header container (for backward compatibility, positioned below header row)
    -- Hidden - second line removed per user request
    local headerContainer = CreateFrame("Frame", nil, hudFrame)
    headerContainer:SetPoint("TOP", headerRow, "BOTTOM", 0, -4)
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
    -- Body region (all body content goes here - tiles, panels, start content)
    --------------------------------------------------
    local bodyYOffset = -(PADDING + HEADER_HEIGHT + BODY_GAP)
    local bodyContainer = CreateFrame("Frame", nil, hudFrame)
    bodyContainer:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, bodyYOffset)
    bodyContainer:SetPoint("RIGHT", hudFrame, "RIGHT", -PADDING, 0)
    -- Height set per-state; micro uses TILE_HEIGHT, expanded uses dynamic
    bodyContainer:SetHeight(TILE_HEIGHT)
    hudFrame.bodyContainer = bodyContainer

    --------------------------------------------------
    -- Micro-bar metric tiles (for collapsed state - single horizontal line)
    --------------------------------------------------
    for metricKey, state in pairs(metricStates) do
        local key = metricKey
        local metricState = state
        local tile = CreateFrame("Frame", nil, bodyContainer)
        tile:SetSize(TILE_WIDTH, TILE_HEIGHT)
        tile:EnableMouse(true)
        tile:SetScript("OnEnter", function(self)
            ShowMicroMetricTooltip(self, key, metricState)
        end)
        tile:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        tile:SetScript("OnMouseUp", function()
            HideOverflowMenu()
            pH_HUD:OpenSessionDetail(key)
        end)
        state.tile = tile

        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        icon:SetTexture(METRIC_ICONS[metricKey])
        state.icon = icon

        local rateText = PHUI.CreateLabel(tile, "primary", "0", PHUI.Fonts.SMALL)
        rateText:SetPoint("LEFT", icon, "RIGHT", 3, 0)
        rateText:SetJustifyH("LEFT")
        state.valueText = rateText

        local spark = addon.UI.Sparkline:Create(tile, {
            width = TILE_WIDTH,
            height = SPARK_HEIGHT,
            color = MICROBAR_COLORS[colorKeys[metricKey]].fill,
        })
        spark:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, -(12 + 3))
        state.spark = spark

        tile:Hide()
    end

    -- Dividers between metric cells (3 gaps for 4 cells)
    hudFrame.tileDividers = {}
    for i = 1, 3 do
        hudFrame.tileDividers[i] = addon.UI.Panel:CreateDivider(bodyContainer, "vertical")
        hudFrame.tileDividers[i]:Hide()
    end

    --------------------------------------------------
    -- Start screen (shown when no session active)
    -- Single line: logo | Start | History | ... | Min/Max
    --------------------------------------------------
    local bodyTopOffset = -(PADDING + HEADER_HEIGHT + BODY_GAP)
    -- Header right side (right to left): Expand | Stop/Start | Pause (session) or History (no session)
    -- Pause is active-session only and History is start-screen only, so the
    -- chain is re-anchored per state by LayoutHeader().
    hudFrame.minMaxBtn:ClearAllPoints()
    hudFrame.minMaxBtn:SetPoint("RIGHT", headerRow, "RIGHT", -PADDING, 0)
    LayoutHeader(true)

    -- Overflow menu and outside-click catcher
    local overflowBackdrop = CreateFrame("Button", nil, UIParent)
    overflowBackdrop:SetAllPoints(UIParent)
    overflowBackdrop:SetFrameStrata("DIALOG")
    overflowBackdrop:SetFrameLevel(300)
    overflowBackdrop:EnableMouse(true)
    overflowBackdrop:SetScript("OnClick", function()
        HideOverflowMenu()
    end)
    overflowBackdrop:Hide()
    hudFrame.overflowMenuBackdrop = overflowBackdrop

    local overflowMenu = CreateFrame("Frame", nil, hudFrame, "BackdropTemplate")
    overflowMenu:SetSize(32, 112)
    overflowMenu:SetFrameStrata("DIALOG")
    overflowMenu:SetFrameLevel(301)
    overflowMenu:SetBackdrop(PHUI.Backdrops.PANEL)
    overflowMenu:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], 0.95)
    overflowMenu:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 1.0)
    overflowMenu:Hide()
    hudFrame.overflowMenu = overflowMenu

    local function CreateMenuIconButton(parent, texturePath, yOffset, tooltipText, onClick, textGlyph, textColor)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("TOP", parent, "TOP", 0, yOffset)
        btn.isActionDisabled = false
        btn:SetBackdrop(PHUI.Backdrops.ICON_BUTTON)
        btn:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.9)
        btn:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)

        local iconFrame = CreateFrame("Frame", nil, btn)
        iconFrame:SetSize(OVERFLOW_ICON_SIZE, OVERFLOW_ICON_SIZE)
        iconFrame:SetPoint("CENTER", btn, "CENTER", 0, 0)
        btn.iconFrame = iconFrame

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(OVERFLOW_ICON_SIZE, OVERFLOW_ICON_SIZE)
        btn.icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        if texturePath then
            btn.icon:SetTexture(texturePath)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            btn.icon:Hide()
        end
        if textGlyph then
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn.text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
            btn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            btn.text:SetText(textGlyph)
            if textColor then
                btn.text:SetTextColor(textColor[1], textColor[2], textColor[3])
            else
                btn.text:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
            end
        end
        btn.tooltipText = tooltipText
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        btn:SetScript("OnClick", function()
            if btn.isActionDisabled then
                return
            end
            HideOverflowMenu()
            onClick()
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3], 1.0)
            if self.tooltipText then
                pH_Tooltip:Own(self)
                GameTooltip:SetText(self.tooltipText)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
            GameTooltip:Hide()
        end)
        return btn
    end

    local pauseBtn = CreateMenuIconButton(overflowMenu, HEADER_ICON_PAUSE, -6, "Pause session", function()
        local session = pH_SessionManager:GetActiveSession()
        if not session then return end
        if pH_SessionManager:IsPaused(session) then
            local ok, message = pH_SessionManager:ResumeSession("manual", "overflow")
            if message then print("[pH] " .. message) end
            if ok then pH_HUD:Update() end
        else
            local ok, message = pH_SessionManager:PauseSession("manual", "overflow")
            if message then print("[pH] " .. message) end
            if ok then pH_HUD:Update() end
        end
    end)
    overflowMenu.pauseBtn = pauseBtn
    hudFrame.overflowPauseBtn = pauseBtn

    local stopMenuBtn = CreateMenuIconButton(overflowMenu, "Interface\\RAIDFRAME\\ReadyCheck-NotReady", -28, "Stop session", function()
        local ok, message = pH_SessionManager:StopSession()
        if message then print("[pH] " .. message) end
        if ok then pH_HUD:Update() end
    end)
    overflowMenu.stopBtn = stopMenuBtn
    hudFrame.overflowStopBtn = stopMenuBtn

    local helpMenuBtn = CreateMenuIconButton(overflowMenu, nil, -50, "Help", function()
        if SlashCmdList["PH"] then
            SlashCmdList["PH"]("help")
        else
            print("[pH] Type /ph help for commands")
        end
    end, "?")
    overflowMenu.helpBtn = helpMenuBtn

    local settingsMenuBtn = CreateMenuIconButton(overflowMenu, HEADER_ICON_SETTINGS, -72, "Settings", function()
        if type(pH_AutoSession) == "table" and pH_AutoSession.OpenSettingsPanel then
            pH_AutoSession:OpenSettingsPanel()
        elseif SlashCmdList["PH"] then
            SlashCmdList["PH"]("auto status")
        end
    end)
    overflowMenu.settingsBtn = settingsMenuBtn

    hudFrame.overflowBtn:SetScript("OnClick", function()
        ToggleOverflowMenu()
    end)

    -- Placeholder startScreen (empty - expanded panel uses startExpanded; collapsed uses header row only)
    local startScreen = CreateFrame("Frame", nil, hudFrame)
    startScreen:SetSize(1, 1)
    startScreen:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 0, bodyTopOffset)
    startScreen:Hide()
    hudFrame.startScreen = startScreen

    --------------------------------------------------
    -- Expanded start panel content (Option D - Smart Context)
    --------------------------------------------------
    local START_EXPANDED_WIDTH = 340
    local START_EXPANDED_HEIGHT = 120  -- Will adjust based on content
    
    local startExpanded = CreateFrame("Frame", nil, hudFrame)
    startExpanded:SetSize(START_EXPANDED_WIDTH, START_EXPANDED_HEIGHT)
    startExpanded:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, bodyTopOffset)
    startExpanded:SetFrameLevel(hudFrame:GetFrameLevel() + 1)
    startExpanded:Hide()
    
    -- Zone/Context title
    local zoneTitle = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    zoneTitle:SetPoint("TOPLEFT", startExpanded, "TOPLEFT", PADDING, -2)
    zoneTitle:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    zoneTitle:SetJustifyH("LEFT")
    zoneTitle:SetWidth(START_EXPANDED_WIDTH - 2*PADDING)
    
    -- Main content text (stats or tips) - PH_TEXT_PRIMARY for readability
    local contentLine1 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentLine1:SetPoint("TOPLEFT", zoneTitle, "BOTTOMLEFT", 0, -8)
    contentLine1:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    contentLine1:SetJustifyH("LEFT")
    contentLine1:SetWidth(START_EXPANDED_WIDTH - 2*PADDING)
    
    local contentLine2 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentLine2:SetPoint("TOPLEFT", contentLine1, "BOTTOMLEFT", 0, -4)
    contentLine2:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    contentLine2:SetJustifyH("LEFT")
    contentLine2:SetWidth(START_EXPANDED_WIDTH - 2*PADDING)
    
    local contentLine3 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentLine3:SetPoint("TOPLEFT", contentLine2, "BOTTOMLEFT", 0, -4)
    contentLine3:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    contentLine3:SetJustifyH("LEFT")
    contentLine3:SetWidth(START_EXPANDED_WIDTH - 2*PADDING)
    
    local contentLine4 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    contentLine4:SetPoint("TOPLEFT", contentLine3, "BOTTOMLEFT", 0, -4)
    contentLine4:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    contentLine4:SetJustifyH("LEFT")
    contentLine4:SetWidth(START_EXPANDED_WIDTH - 2*PADDING)
    
    -- Tip section (with icon)
    local tipIcon = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipIcon:SetPoint("TOPLEFT", contentLine4, "BOTTOMLEFT", 0, -12)
    tipIcon:SetText("")  -- Will be set to emoji or bullet
    tipIcon:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
    
    local tipText1 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipText1:SetPoint("LEFT", tipIcon, "RIGHT", 4, 0)
    tipText1:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    tipText1:SetJustifyH("LEFT")
    tipText1:SetWidth(START_EXPANDED_WIDTH - 2*PADDING - 20)
    
    local tipText2 = startExpanded:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tipText2:SetPoint("TOPLEFT", tipText1, "BOTTOMLEFT", 0, -4)
    tipText2:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    tipText2:SetJustifyH("LEFT")
    tipText2:SetWidth(START_EXPANDED_WIDTH - 2*PADDING - 20)
    
    hudFrame.startExpanded = startExpanded
    hudFrame.startExpandedContent = {
        zoneTitle = zoneTitle,
        contentLine1 = contentLine1,
        contentLine2 = contentLine2,
        contentLine3 = contentLine3,
        contentLine4 = contentLine4,
        tipIcon = tipIcon,
        tipText1 = tipText1,
        tipText2 = tipText2,
    }

    -- Update loop
    hudFrame:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed

        -- Dynamic update interval
        local interval = UPDATE_INTERVAL  -- Default 1.0s
        local cfg = pH_Settings.microBars
        if cfg and cfg.enabled then
            interval = cfg.updateInterval  -- 0.25s for micro-bars
        end

        if updateTimer >= interval then
            pH_HUD:Update()
            updateTimer = 0
        end
    end)
    
    -- Zone change event handling (for start panel content updates)
    hudFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    hudFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "ZONE_CHANGED_NEW_AREA" then
            HideOverflowMenu()
            -- Only update if no active session and start panel is expanded
            local session = pH_SessionManager:GetActiveSession()
            if not session and pH_Settings.startPanelExpanded then
                UpdateStartPanelContent()
            end
        end
    end)

    -- Initial state: show start screen if no session, or active HUD if session exists
    local session = pH_SessionManager:GetActiveSession()
    if not session then
        hudFrame:Show()
        if hudFrame.startScreen then
            hudFrame.startScreen:Show()
        end
    else
        hudFrame:Show()
    end
end

--------------------------------------------------
-- Update Start Panel Content (Option D - Smart Context)
--------------------------------------------------
UpdateStartPanelContent = function()
    if not hudFrame or not hudFrame.startExpandedContent then
        return
    end
    
    local content = hudFrame.startExpandedContent
    local currentZone = GetZoneText() or "Unknown"
    
    -- Get zone stats and overall session count
    local zoneStats = pH_Index:GetZoneStats(currentZone)
    local allSessions = pH_SessionManager:ListSessions(100)  -- Get up to 100 sessions
    local totalSessionCount = #allSessions
    
    -- Option D Logic: Adaptive content based on context
    if zoneStats and zoneStats.sessionCount > 0 then
        -- Case 1: You have sessions in current zone
        content.zoneTitle:SetText("Welcome back to " .. currentZone)
        
        local avgGold = pH_Ledger:FormatMoneyShort(zoneStats.avgPerHour)
        local bestGold = pH_Ledger:FormatMoneyShort(zoneStats.bestPerHour)
        content.contentLine1:SetText("You usually make " .. avgGold .. "/hr here")
        
        if zoneStats.lastSession then
            local metrics = pH_SessionManager:GetMetrics(zoneStats.lastSession)
            local lastGold = pH_Ledger:FormatMoneyShort(metrics.totalPerHour or 0)
            local lastTime = zoneStats.lastSession.endedAt or zoneStats.lastSession.startedAt
            local timeDiff = time() - lastTime
            local timeAgo = ""
            if timeDiff < 3600 then
                timeAgo = math.floor(timeDiff / 60) .. "m ago"
            elseif timeDiff < 86400 then
                timeAgo = math.floor(timeDiff / 3600) .. "h ago"
            else
                timeAgo = math.floor(timeDiff / 86400) .. "d ago"
            end
            
            local sessionInfo = lastGold .. "/hr"
            if zoneStats.lastSession.gathering and zoneStats.lastSession.gathering.totalNodes then
                sessionInfo = sessionInfo .. " - " .. zoneStats.lastSession.gathering.totalNodes .. " nodes"
            end
            
            content.contentLine2:SetText("Last session: " .. timeAgo .. " - " .. sessionInfo)
        else
            content.contentLine2:SetText("")
        end
        
        content.contentLine3:SetText("")
        content.contentLine4:SetText("")
        
        -- Tip: Best performance
        content.tipIcon:SetText(">")
        content.tipText1:SetText("Tip: Your best here was " .. bestGold .. "/hr")
        content.tipText2:SetText("    Use /ph pause to pause tracking anytime")
        
    elseif totalSessionCount > 0 then
        -- Case 2: First time in this zone, but have sessions elsewhere
        content.zoneTitle:SetText("First time tracking in " .. currentZone .. "!")
        
        -- Find best zones
        local zoneAgg = pH_Index:GetZoneAggregates()
        local bestZones = {}
        for zone, stats in pairs(zoneAgg) do
            table.insert(bestZones, {zone = zone, perHour = stats.avgTotalPerHour, count = stats.sessionCount})
        end
        table.sort(bestZones, function(a, b) return a.perHour > b.perHour end)
        
        if bestZones[1] then
            local zone1 = bestZones[1].zone
            local gold1 = pH_Ledger:FormatMoneyShort(bestZones[1].perHour)
            local count1 = bestZones[1].count
            content.contentLine1:SetText("Your best zones so far:")
            content.contentLine2:SetText("  " .. zone1 .. ": " .. gold1 .. "/hr (" .. count1 .. " sessions)")
            
            if bestZones[2] then
                local zone2 = bestZones[2].zone
                local gold2 = pH_Ledger:FormatMoneyShort(bestZones[2].perHour)
                local count2 = bestZones[2].count
                content.contentLine3:SetText("  " .. zone2 .. ": " .. gold2 .. "/hr (" .. count2 .. " sessions)")
            else
                content.contentLine3:SetText("")
            end
        else
            content.contentLine1:SetText("")
            content.contentLine2:SetText("")
            content.contentLine3:SetText("")
        end
        
        content.contentLine4:SetText("")
        
        -- Tip: Pause reminder
        content.tipIcon:SetText(">")
        content.tipText1:SetText("Tip: Pause anytime with /ph pause")
        content.tipText2:SetText("    Resume with /ph resume")
        
    else
        -- Case 3: Brand new user, no sessions at all
        content.zoneTitle:SetText("Ready to track your earnings!")
        content.contentLine1:SetText("")
        content.contentLine2:SetText("pH tracks gold, XP, rep, and honor per hour")
        content.contentLine3:SetText("while you farm, quest, or gather.")
        content.contentLine4:SetText("")
        
        -- Tips for getting started
        content.tipIcon:SetText(">")
        content.tipText1:SetText("Tips: Click Start, then go about your usual activities")
        content.tipText2:SetText("      View History to see detailed breakdowns")
    end
    
    -- The HUD keeps one constant width; long lines truncate instead of wrapping
    -- into the line below.
    local measuredLines = {content.zoneTitle, content.contentLine1, content.contentLine2,
                           content.contentLine3, content.contentLine4, content.tipText1, content.tipText2}
    local textWidth = GLANCE_WIDTH - 2 * PADDING
    hudFrame.startExpanded:SetSize(GLANCE_WIDTH, 120)
    for _, line in ipairs(measuredLines) do
        line:SetWordWrap(false)
        line:SetWidth(textWidth)
    end
end

-- Update HUD display
function pH_HUD:Update()
    if not hudFrame then
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    local sessionStateKey
    if not session then
        sessionStateKey = "none"
    elseif pH_SessionManager:IsPaused(session) then
        sessionStateKey = "paused"
    else
        sessionStateKey = "running"
    end
    if lastSessionStateKey ~= sessionStateKey then
        HideOverflowMenu()
        lastSessionStateKey = sessionStateKey
    end

    if not session then
        -- No active session: show start panel (collapsed or expanded)
        local isExpanded = pH_Settings.startPanelExpanded
        
        -- Toggle expand/collapse behavior for start panel
        hudFrame.minMaxBtn:SetScript("OnClick", function()
            HideOverflowMenu()
            pH_Settings.startPanelExpanded = not pH_Settings.startPanelExpanded
            pH_HUD:Update()
        end)
        
        if isExpanded then
            -- Expanded start panel
            if hudFrame.startScreen then
                hudFrame.startScreen:Hide()
            end
            if hudFrame.startExpanded then
                hudFrame.startExpanded:Show()
                UpdateStartPanelContent()
            end
            
            -- Update expand button icon
            SetMinMaxGlyph(hudFrame.minMaxBtn, HEADER_ICON_MINUS, "Collapse start panel")
            
            -- Frame size: expanded with content (width set by adaptive calc, fallback 340)
            local expWidth = GLANCE_WIDTH
            local startBodyHeight = 120  -- Zone context + tips content
            local expHeight = PADDING + HEADER_HEIGHT + BODY_GAP + startBodyHeight + PADDING
            hudFrame:Show()
            hudFrame:SetSize(expWidth, expHeight)
            hudFrame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], 0.95)
            
        else
            -- Collapsed start panel (single line: logo | ? | settings | Start | icons)
            if hudFrame.startScreen then
                hudFrame.startScreen:Hide()
            end
            if hudFrame.startExpanded then
                hudFrame.startExpanded:Hide()
            end
            
            -- Update expand button icon
            SetMinMaxGlyph(hudFrame.minMaxBtn, HEADER_ICON_PLUS, "Expand start panel")
            
            -- Frame size: header only
            hudFrame:Show()
            hudFrame:SetSize(GLANCE_WIDTH, ComputeStartCollapsedHeight())
            hudFrame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], PH_BG_PARCHMENT[4])
        end
        
        -- Header: show title, primary button, icon row; hide timer
        hudFrame.title:Show()
        hudFrame.headerTimer:Hide()
        if hudFrame.stopBtn then
            hudFrame.stopBtn:Show()
            hudFrame.stopBtn:SetWidth(PRIMARY_BTN_WIDTH)
            hudFrame.stopBtn.textObj:SetText("Start")
            hudFrame.stopBtn.textObj:SetTextColor(PH_ACCENT_GOOD[1], PH_ACCENT_GOOD[2], PH_ACCENT_GOOD[3])
            hudFrame.stopBtn:SetScript("OnClick", function()
                local ok, message = pH_SessionManager:StartSession("manual", "hud_start")
                print("[pH] " .. message)
                if ok then
                    pH_Settings.hudMinimized = true
                    pH_HUD:Update()
                end
            end)
            hudFrame.stopBtn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(PH_ACCENT_GOOD[1], PH_ACCENT_GOOD[2], PH_ACCENT_GOOD[3], 1.0)
                pH_Tooltip:Own(self)
                GameTooltip:SetText("Start tracking gold, XP, rep, and honor per hour", nil, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            hudFrame.stopBtn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
                GameTooltip:Hide()
            end)
        end

        -- Icon row: all right-side controls visible (no pause without a session)
        LayoutHeader(false)
        hudFrame.pauseBtn:Hide()
        hudFrame.historyBtn:Show()
        hudFrame.historyBtn:Enable()
        hudFrame.historyBtn:SetAlpha(1)
        hudFrame.overflowBtn:Hide()  -- "More actions" removed for now; Help/Settings live in the detail window
        hudFrame.minMaxBtn:Show()
        hudFrame.minMaxBtn:Enable()
        hudFrame.minMaxBtn:SetAlpha(1)

        -- Hide metric components
        for _, state in pairs(metricStates) do
            if state.tile then state.tile:Hide() end
            state.displayRate = 0
            state.lastUpdatedText = ""
        end

        return
    end

    -- Session is active: hide start screen, show active components
    if hudFrame.startScreen then
        hudFrame.startScreen:Hide()
    end
    if hudFrame.startExpanded then
        hudFrame.startExpanded:Hide()
    end
    -- Restore normal bg opacity
    hudFrame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], PH_BG_PARCHMENT[4])

    hudFrame.title:Show()
    hudFrame.headerTimer:Show()
    local isPaused = pH_SessionManager:IsPaused(session)
    LayoutHeader(true)

    -- Stop is always Stop; pause/resume has its own button.
    hudFrame.stopBtn:Show()
    hudFrame.stopBtn:SetWidth(STOP_BTN_WIDTH)
    hudFrame.stopBtn.textObj:SetText("Stop")
    hudFrame.stopBtn.textObj:SetTextColor(PH_ACCENT_BAD[1], PH_ACCENT_BAD[2], PH_ACCENT_BAD[3])
    hudFrame.stopBtn:SetScript("OnClick", function()
        local ok, message = pH_SessionManager:StopSession()
        if ok then
            print("[pH] " .. message)
            pH_HUD:Update()
        end
    end)
    hudFrame.stopBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(PH_ACCENT_BAD[1], PH_ACCENT_BAD[2], PH_ACCENT_BAD[3], 1.0)
        pH_Tooltip:Own(self)
        GameTooltip:SetText("Stop session and save results")
        GameTooltip:Show()
    end)
    hudFrame.stopBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 0.8)
        GameTooltip:Hide()
    end)

    hudFrame.pauseBtn:Show()
    hudFrame.pauseBtn.icon:SetTexture(isPaused and HEADER_ICON_PLAY or HEADER_ICON_PAUSE)
    hudFrame.pauseBtn.tooltipText = isPaused and "Resume session" or "Pause session"

    -- Icon row: History lives in the session detail window while a session runs
    hudFrame.historyBtn:Hide()
    hudFrame.overflowBtn:Hide()
    hudFrame.minMaxBtn:Show()
    hudFrame.minMaxBtn:Enable()
    hudFrame.minMaxBtn:SetAlpha(1)
    SetMinMaxGlyph(hudFrame.minMaxBtn, HEADER_ICON_PLUS, "Session detail")
    hudFrame.minMaxBtn:SetScript("OnClick", function()
        HideOverflowMenu()
        pH_HUD:OpenSessionDetail()
    end)

    -- Show HUD if session active
    if not hudFrame:IsShown() then
        hudFrame:Show()
    end

    -- Glance is always compact; detail lives in the History window.
    hudFrame:SetWidth(GLANCE_WIDTH)
    hudFrame:SetHeight(FRAME_HEIGHT_MINI)

    -- Get metrics
    local metrics = pH_SessionManager:GetMetrics(session)

    -- Update timers (both collapsed and expanded versions) with pH brand colors
    local timerText = pH_SessionManager:FormatDuration(metrics.durationSec)

    hudFrame.headerTimer:SetText(timerText)
    hudFrame.headerTimer:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])

    -- Second header line removed - no longer updating headerGold or headerTimer2

    -- Update micro-bars
    local cfg = pH_Settings.microBars
    if cfg and cfg.enabled then
        UpdateMicroBars(session, metrics)
    end

    -- Keep the recorded time-series growing for Session Detail sparklines.
    -- (SampleMetricHistory self-throttles to its sampleInterval.)
    pH_SessionManager:SampleMetricHistory(session, metrics)
end

-- Show HUD
function pH_HUD:Show()
    if not hudFrame then
        self:Initialize()
    end

    if hudFrame then
        hudFrame:Show()
        self:ApplyMinimizeState()

        -- Save visibility state
        pH_Settings.hudVisible = true
    end
end

-- Hide HUD
function pH_HUD:Hide()
    if hudFrame then
        HideOverflowMenu()
        hudFrame:Hide()

        -- Save visibility state
        pH_Settings.hudVisible = false
    end
end

-- Toggle HUD visibility
function pH_HUD:Toggle()
    if not hudFrame then
        return
    end

    if hudFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Open the active session in the unified Session Detail (History window).
-- The Glance HUD is left untouched.
function pH_HUD:OpenSessionDetail(metricKey)
    if pH_SessionManager:GetActiveSession() then
        pH_History:ShowActive(metricKey)
    else
        pH_History:Show()
    end
end

-- Glance is the only HUD layout now; keep the legacy flag true so older
-- code paths and saved settings stay consistent.
function pH_HUD:ApplyMinimizeState()
    if not hudFrame then
        return
    end
    HideOverflowMenu()
    pH_Settings.hudMinimized = true

    local session = pH_SessionManager:GetActiveSession()
    if not session then
        return  -- Start screen sizes itself in Update()
    end

    local point, relativeTo, relativePoint, xOfs, yOfs = hudFrame:GetPoint()
    hudFrame:SetHeight(FRAME_HEIGHT_MINI)
    hudFrame:SetWidth(GLANCE_WIDTH)
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

    RepositionTiles()
    self:Update()
end

-- Export module
_G.pH_HUD = pH_HUD
