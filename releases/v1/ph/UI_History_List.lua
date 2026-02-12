--[[
    UI_History_List.lua - Virtualized session list for GoldPH History

    Displays sessions in a scrollable list with row pooling for performance.
]]

-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local GoldPH_History_List = {
    parent = nil,
    historyController = nil,
    contentFrame = nil,
    scrollBar = nil,

    rows = {},           -- Pool of row frames
    sessionIds = {},     -- Current filtered session IDs
    selectedId = nil,    -- Currently selected session ID

    rowHeight = 45,
    numVisibleRows = 8,  -- Calculated based on available height
}

-- pH brand colors for list rows
local TEXT_PRIMARY = pH_Colors.TEXT_PRIMARY
local TEXT_MUTED = pH_Colors.TEXT_MUTED
local ACCENT_GOLD = pH_Colors.ACCENT_GOLD
local HOVER = pH_Colors.HOVER
local SELECTED = pH_Colors.SELECTED

--------------------------------------------------
-- Initialize
--------------------------------------------------
function GoldPH_History_List:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    -- Calculate number of visible rows based on parent height
    local availableHeight = parent:GetHeight() - 10  -- 5px padding top/bottom
    self.numVisibleRows = math.floor(availableHeight / self.rowHeight)

    -- Create content frame (holds all rows) - simple Frame, not ScrollFrame
    local contentFrame = CreateFrame("Frame", nil, parent)
    contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    contentFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -25, 5)
    self.contentFrame = contentFrame

    -- Create scroll bar
    local scrollBar = CreateFrame("Slider", nil, parent, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -20)
    scrollBar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 20)
    scrollBar:SetMinMaxValues(0, 0)
    scrollBar:SetValueStep(1)
    scrollBar:SetWidth(16)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        GoldPH_History_List:OnScroll(value)
    end)
    self.scrollBar = scrollBar

    -- Create row pool
    for i = 1, self.numVisibleRows do
        local row = self:CreateRow(i)
        self.rows[i] = row
    end

    -- Enable mouse wheel scrolling on content frame
    contentFrame:EnableMouseWheel(true)
    contentFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = GoldPH_History_List.scrollBar:GetValue()
        local min, max = GoldPH_History_List.scrollBar:GetMinMaxValues()
        local newValue = math.max(min, math.min(max, current - delta))
        GoldPH_History_List.scrollBar:SetValue(newValue)
    end)
end

--------------------------------------------------
-- Create Row Frame
--------------------------------------------------
function GoldPH_History_List:CreateRow(index)
    local row = CreateFrame("Button", nil, self.contentFrame, "BackdropTemplate")
    row:SetHeight(self.rowHeight)
    row:SetPoint("TOPLEFT", self.contentFrame, "TOPLEFT", 5, -(index - 1) * self.rowHeight)
    row:SetPoint("RIGHT", self.contentFrame, "RIGHT", -5, 0)  -- Stretch to right edge

    -- Backdrop (for hover/selection)
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true,
        tileSize = 16,
    })
    row:SetBackdropColor(0, 0, 0, 0)  -- Transparent by default

    -- Line 1: Total gold/hr (right-aligned)
    local goldPerHour = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldPerHour:SetPoint("TOPRIGHT", row, "TOPRIGHT", -5, -4)
    goldPerHour:SetJustifyH("RIGHT")
    goldPerHour:SetTextColor(ACCENT_GOLD[1], ACCENT_GOLD[2], ACCENT_GOLD[3])
    row.goldPerHour = goldPerHour

    -- Line 2: Zone and duration (left-aligned)
    local zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneText:SetPoint("TOPLEFT", row, "TOPLEFT", 5, -4)
    zoneText:SetJustifyH("LEFT")
    zoneText:SetPoint("RIGHT", goldPerHour, "LEFT", -10, 0)  -- Extend to left of gold/hr text
    row.zoneText = zoneText

    local durationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationText:SetPoint("TOPLEFT", zoneText, "BOTTOMLEFT", 0, -2)
    durationText:SetJustifyH("LEFT")
    durationText:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
    row.durationText = durationText

    -- Line 3: Character and badges (left-aligned)
    local charText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charText:SetPoint("TOPLEFT", durationText, "BOTTOMLEFT", 0, -2)
    charText:SetJustifyH("LEFT")
    charText:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
    row.charText = charText

    -- Badges (G = gathering, P = pickpocket)
    local badgesText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgesText:SetPoint("LEFT", charText, "RIGHT", 5, 0)
    badgesText:SetJustifyH("LEFT")
    row.badgesText = badgesText

    -- Click handler
    row:SetScript("OnClick", function()
        if row.sessionId then
            GoldPH_History_List.historyController:SelectSession(row.sessionId)
        end
    end)

    -- Hover effect with tooltip
    row:SetScript("OnEnter", function(self)
        if self.sessionId ~= GoldPH_History_List.selectedId then
            self:SetBackdropColor(HOVER[1], HOVER[2], HOVER[3], 0.5)
        end

        -- Show tooltip
        if self.sessionId then
            local summary = GoldPH_Index:GetSummary(self.sessionId)
            if summary then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Session #" .. summary.id, 1, 0.82, 0)
                GameTooltip:AddLine(summary.zone or "Unknown", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Total g/hr:", GoldPH_Ledger:FormatMoneyShort(summary.totalPerHour), 0.7, 0.7, 0.7, 1, 0.82, 0)
                GameTooltip:AddDoubleLine("Gold g/hr:", GoldPH_Ledger:FormatMoneyShort(summary.cashPerHour), 0.7, 0.7, 0.7, 0, 1, 0)
                GameTooltip:AddDoubleLine("Expected g/hr:", GoldPH_Ledger:FormatMoneyShort(summary.expectedPerHour), 0.7, 0.7, 0.7, 0.5, 0.8, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Duration:", GoldPH_History_List:FormatDurationShort(summary.durationSec), 0.7, 0.7, 0.7, 1, 1, 1)

                if summary.hasGathering or summary.hasPickpocket then
                    GameTooltip:AddLine(" ")
                    if summary.hasGathering then
                        GameTooltip:AddLine("|cff00ff00[G]|r Gathering nodes collected", 0.7, 0.7, 0.7)
                    end
                    if summary.hasPickpocket then
                        GameTooltip:AddLine("|cffff00ff[P]|r Pickpocketing performed", 0.7, 0.7, 0.7)
                    end
                end

                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.sessionId ~= GoldPH_History_List.selectedId then
            self:SetBackdropColor(0, 0, 0, 0)
        end
        GameTooltip:Hide()
    end)

    row.sessionId = nil
    row:Hide()

    return row
end

--------------------------------------------------
-- Set Sessions (from query)
--------------------------------------------------
function GoldPH_History_List:SetSessions(sessionIds)
    self.sessionIds = sessionIds

    -- Update scroll bar range
    local maxScroll = math.max(0, #sessionIds - self.numVisibleRows)
    self.scrollBar:SetMinMaxValues(0, maxScroll)
    self.scrollBar:SetValue(0)

    -- Render visible rows
    self:RenderVisibleRows(0)
end

--------------------------------------------------
-- On Scroll
--------------------------------------------------
function GoldPH_History_List:OnScroll(offset)
    self:RenderVisibleRows(offset)
end

--------------------------------------------------
-- Render Visible Rows
--------------------------------------------------
function GoldPH_History_List:RenderVisibleRows(offset)
    offset = math.floor(offset)

    for i = 1, self.numVisibleRows do
        local row = self.rows[i]
        local dataIndex = offset + i

        if dataIndex <= #self.sessionIds then
            local sessionId = self.sessionIds[dataIndex]
            local summary = GoldPH_Index:GetSummary(sessionId)

            if summary then
                -- Update row content
                row.goldPerHour:SetText(GoldPH_Ledger:FormatMoneyShort(summary.totalPerHour) .. "/hr")

                -- Zone (truncate if too long)
                local zoneName = summary.zone
                if #zoneName > 20 then
                    zoneName = zoneName:sub(1, 17) .. "..."
                end
                row.zoneText:SetText(zoneName)

                -- Duration
                row.durationText:SetText(self:FormatDurationShort(summary.durationSec))

                -- Character (show only character name, not full key)
                local charName = summary.charKey:match("^([^-]+)")
                row.charText:SetText(charName or summary.charKey)

                -- Badges
                local badges = ""
                if summary.hasGathering then
                    badges = badges .. "|cff00ff00[G]|r "
                end
                if summary.hasPickpocket then
                    badges = badges .. "|cffff00ff[P]|r "
                end
                -- Phase 9: XP/Rep/Honor badges
                if summary.hasXP then
                    badges = badges .. "|cff80ccff[XP]|r "  -- Blue
                end
                if summary.hasRep then
                    badges = badges .. "|cff4dff4d[Rep]|r "  -- Green
                end
                if summary.hasHonor then
                    badges = badges .. "|cffff8000[Hon]|r"  -- Orange
                end
                row.badgesText:SetText(badges)

                -- Selection highlight
                if sessionId == self.selectedId then
                    row:SetBackdropColor(SELECTED[1], SELECTED[2], SELECTED[3], 0.75)
                else
                    row:SetBackdropColor(0, 0, 0, 0)
                end

                row.sessionId = sessionId
                row:Show()
            else
                row:Hide()
            end
        else
            row:Hide()
        end
    end
end

--------------------------------------------------
-- Set Selection
--------------------------------------------------
function GoldPH_History_List:SetSelection(sessionId)
    self.selectedId = sessionId

    -- Re-render to update highlights
    local offset = self.scrollBar:GetValue()
    self:RenderVisibleRows(offset)
end

--------------------------------------------------
-- Scroll To Selection (for keyboard navigation)
--------------------------------------------------
function GoldPH_History_List:ScrollToSelection(index)
    -- Get current scroll position
    local currentOffset = self.scrollBar:GetValue()

    -- Check if selected item is visible
    local firstVisible = currentOffset + 1
    local lastVisible = currentOffset + self.numVisibleRows

    if index < firstVisible then
        -- Scroll up to show selected item at top
        self.scrollBar:SetValue(index - 1)
    elseif index > lastVisible then
        -- Scroll down to show selected item at bottom
        self.scrollBar:SetValue(index - self.numVisibleRows)
    end
    -- Otherwise, item is already visible, no scroll needed
end

--------------------------------------------------
-- Helper: Format Duration (short version)
--------------------------------------------------
function GoldPH_History_List:FormatDurationShort(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    else
        return string.format("%dm", mins)
    end
end

-- Export module
_G.GoldPH_History_List = GoldPH_History_List
