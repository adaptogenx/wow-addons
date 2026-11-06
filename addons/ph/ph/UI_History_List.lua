--[[
    UI_History_List.lua - Virtualized session list for pH History

    Displays sessions in a scrollable list with row pooling for performance.
]]

-- luacheck: globals pH_Tooltip time date pH_Index pH_Ledger pH_SessionManager UnitName CreateFrame UIDropDownMenu_Initialize UIDropDownMenu_CreateInfo ToggleDropDownMenu CloseDropDownMenus DropDownList1 UIDROPDOWNMENU_OPEN_MENU GameTooltip
-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local pH_History_List = {
    parent = nil,
    historyController = nil,
    contentFrame = nil,
    scrollBar = nil,

    rows = {},           -- Pool of row frames
    sessionIds = {},     -- Current filtered session IDs
    selectedId = nil,    -- Currently selected session ID

    rowHeight = 45,
    poolSize = 8,        -- Row frames created (numVisibleRows shrinks by one while the active row shows)
    activeRow = nil,
    numVisibleRows = 8,  -- Calculated based on available height

    -- Row actions dropdown
    actionMenu = nil,
    actionMenuSessionId = nil,
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
function pH_History_List:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    -- Calculate number of visible rows based on parent height
    -- Clamp to at least 1: parent may have 0 height before layout (e.g. before Show)
    local availableHeight = math.max(0, (parent:GetHeight() or 0) - 10)  -- 5px padding top/bottom
    self.numVisibleRows = math.max(1, math.floor(availableHeight / self.rowHeight))

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
        pH_History_List:OnScroll(value)
    end)
    self.scrollBar = scrollBar

    self.poolSize = self.numVisibleRows

    -- Create row pool
    for i = 1, self.numVisibleRows do
        local row = self:CreateRow(i)
        self.rows[i] = row
    end

    -- Pinned "Current Session" row above the scrolling list
    self:CreateActiveRow()
    local ticker = CreateFrame("Frame", nil, parent)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end
        elapsed = 0
        pH_History_List:UpdateActive()
    end)

    -- Enable mouse wheel scrolling on content frame
    contentFrame:EnableMouseWheel(true)
    contentFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = pH_History_List.scrollBar:GetValue()
        local min, max = pH_History_List.scrollBar:GetMinMaxValues()
        local newValue = math.max(min, math.min(max, current - delta))
        pH_History_List.scrollBar:SetValue(newValue)
    end)

    -- Empty state message (when no sessions match filters)
    local emptyLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("CENTER", contentFrame, "CENTER", 0, 0)
    emptyLabel:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
    emptyLabel:SetText("No sessions found.\nTry Char: All or /ph debug data")
    emptyLabel:SetJustifyH("CENTER")
    emptyLabel:SetWidth(150)  -- wrap inside the narrow column
    emptyLabel:Hide()
    self.emptyLabel = emptyLabel
end

--------------------------------------------------
-- Create Row Frame
--------------------------------------------------
function pH_History_List:CreateRow(index)
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
    zoneText:SetWordWrap(false)
    zoneText:SetPoint("RIGHT", goldPerHour, "LEFT", -6, 0)  -- Extend to left of gold/hr text
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

    -- Click/right-click handler
    row:SetScript("OnMouseUp", function(self, button)
        if not row.sessionId then
            return
        end
        if button == "RightButton" then
            pH_History_List:ShowRowMenu(self, row.sessionId)
        else
            pH_History_List.historyController:SelectSession(row.sessionId)
        end
    end)

    -- Hover effect with tooltip
    row:SetScript("OnEnter", function(self)
        if self.sessionId ~= pH_History_List.selectedId then
            self:SetBackdropColor(HOVER[1], HOVER[2], HOVER[3], 0.5)
        end

        -- Show tooltip
        if self.sessionId then
            local summary = pH_Index:GetSummary(self.sessionId)
            if summary then
                pH_Tooltip:Own(self)
                GameTooltip:SetText("Session #" .. summary.id, 1, 0.82, 0)
                GameTooltip:AddLine(summary.zone or "Unknown", 1, 1, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Total g/hr:", pH_Ledger:FormatMoneyShort(summary.totalPerHour), 0.7, 0.7, 0.7, 1, 0.82, 0)
                GameTooltip:AddDoubleLine("Gold g/hr:", pH_Ledger:FormatMoneyShort(summary.cashPerHour), 0.7, 0.7, 0.7, 0, 1, 0)
                GameTooltip:AddDoubleLine("Expected g/hr:", pH_Ledger:FormatMoneyShort(summary.expectedPerHour), 0.7, 0.7, 0.7, 0.5, 0.8, 1)
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Duration:", pH_History_List:FormatDurationShort(summary.durationSec), 0.7, 0.7, 0.7, 1, 1, 1)

                if summary.hasGathering or summary.hasPickpocket then
                    GameTooltip:AddLine(" ")
                    if summary.hasGathering then
                        GameTooltip:AddLine("|cff00ff00[G]|r Gathering nodes collected", 0.7, 0.7, 0.7)
                    end
                    if summary.hasPickpocket then
                        GameTooltip:AddLine("|cffff00ff[P]|r Pickpocketing performed", 0.7, 0.7, 0.7)
                    end
                end

                if summary.isShort or summary.isArchived then
                    GameTooltip:AddLine(" ")
                    if summary.isShort then
                        GameTooltip:AddLine("|cffffaa00[S]|r Short session (<5m)", 0.7, 0.7, 0.7)
                    end
                    if summary.isArchived then
                        GameTooltip:AddLine("|cff99aabb[A]|r Archived", 0.7, 0.7, 0.7)
                    end
                end

                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cffbbbbbbRight-click for actions|r", 0.7, 0.7, 0.7)

                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.sessionId ~= pH_History_List.selectedId then
            self:SetBackdropColor(0, 0, 0, 0)
        end
        GameTooltip:Hide()
    end)

    row.sessionId = nil
    row:Hide()

    return row
end

--------------------------------------------------
-- Active session row (always first when a session is running)
--------------------------------------------------
function pH_History_List:CreateActiveRow()
    -- Same factory as every other row; only anchoring and click behavior differ.
    local row = self:CreateRow(1)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 10, -5)
    row:SetPoint("RIGHT", self.parent, "RIGHT", -30, 0)
    row:SetScript("OnMouseUp", function()
        pH_History_List.historyController:ShowActive()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.isSelected then self:SetBackdropColor(HOVER[1], HOVER[2], HOVER[3], 0.5) end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.isSelected then self:SetBackdropColor(0, 0, 0, 0) end
    end)
    self.activeRow = row
end

-- Show/hide and refresh the pinned row; shifts the list down by one row while visible.
function pH_History_List:UpdateActive()
    local row = self.activeRow
    if not row then return end
    local session = pH_SessionManager:GetActiveSession()
    local wasShown = row:IsShown()

    if not session then
        row:Hide()
        if wasShown then self:ApplyActiveLayout(false) end
        self:RefreshEmptyLabel()
        return
    end

    local metrics = pH_SessionManager:GetMetrics(session)
    row.goldPerHour:SetText(pH_Ledger:FormatMoneyShort(metrics.totalPerHour or 0) .. "/hr")

    local zoneName = session.zone or "Unknown"
    if #zoneName > 20 then
        zoneName = zoneName:sub(1, 17) .. "..."
    end
    row.zoneText:SetText(zoneName)

    local state = pH_SessionManager:IsPaused(session) and "Paused" or "In progress"
    row.durationText:SetText(self:FormatDurationShort(metrics.durationSec) .. "  ·  " .. state)

    row.charText:SetText(UnitName("player") or "")

    local badges = ""
    if metrics.xpGained and metrics.xpGained > 0 then badges = badges .. "|cff80ccff[XP]|r " end
    if metrics.repGained and metrics.repGained > 0 then badges = badges .. "|cff4dff4d[Rep]|r " end
    if metrics.honorGained and metrics.honorGained > 0 then badges = badges .. "|cffff8000[Hon]|r" end
    row.badgesText:SetText(badges)

    local selected = self.historyController and self.historyController:IsActiveSelected()
    row.isSelected = selected
    if selected then
        row:SetBackdropColor(SELECTED[1], SELECTED[2], SELECTED[3], 0.75)
    else
        row:SetBackdropColor(0, 0, 0, 0)
    end

    row:Show()
    if not wasShown then self:ApplyActiveLayout(true) end
    self:RefreshEmptyLabel()
end

-- "No sessions found" only when there is nothing to show at all: no history rows
-- and no running session (the pinned Current Session row counts as a session).
function pH_History_List:RefreshEmptyLabel()
    if not self.emptyLabel then return end
    local hasActive = self.activeRow and self.activeRow:IsShown()
    self.emptyLabel:SetShown(#self.sessionIds == 0 and not hasActive)
end

function pH_History_List:ApplyActiveLayout(hasActive)
    local offset = hasActive and self.rowHeight or 0
    self.contentFrame:ClearAllPoints()
    self.contentFrame:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 5, -5 - offset)
    self.contentFrame:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", -25, 5)
    self.numVisibleRows = math.max(1, self.poolSize - (hasActive and 1 or 0))
    self:SetSessions(self.sessionIds)
end

--------------------------------------------------
-- Set Sessions (from query)
--------------------------------------------------
function pH_History_List:SetSessions(sessionIds)
    self.sessionIds = sessionIds

    self:RefreshEmptyLabel()

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
function pH_History_List:OnScroll(offset)
    self:RenderVisibleRows(offset)
end

--------------------------------------------------
-- Render Visible Rows
--------------------------------------------------
function pH_History_List:RenderVisibleRows(offset)
    offset = math.floor(offset)

    for i = self.numVisibleRows + 1, #self.rows do
        self.rows[i]:Hide()
    end
    for i = 1, self.numVisibleRows do
        local row = self.rows[i]
        local dataIndex = offset + i

        if dataIndex <= #self.sessionIds then
            local sessionId = self.sessionIds[dataIndex]
            local summary = pH_Index:GetSummary(sessionId)

            if summary then
                -- Update row content
                row.goldPerHour:SetText(pH_Ledger:FormatMoneyShort(summary.totalPerHour) .. "/hr")

                -- Zone (truncate if too long)
                local zoneName = summary.zone
                if #zoneName > 20 then
                    zoneName = zoneName:sub(1, 17) .. "..."
                end
                row.zoneText:SetText(zoneName)

                -- Duration and how long ago
                local durationStr = self:FormatDurationShort(summary.durationSec)
                local agoStr = self:FormatTimeAgo(summary.endedAt or summary.startedAt)
                row.durationText:SetText(durationStr .. (agoStr ~= "" and "  ·  " .. agoStr or ""))

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
                if summary.isShort then
                    badges = badges .. " |cffffaa00[S]|r"
                end
                if summary.isArchived then
                    badges = badges .. " |cff99aabb[A]|r"
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

function pH_History_List:ShowRowMenu(anchor, sessionId)
    if not self.actionMenu then
        self.actionMenu = CreateFrame("Frame", "pH_HistoryRowActionMenu", anchor, "UIDropDownMenuTemplate")
    end
    local menu = self.actionMenu
    self.actionMenuSessionId = sessionId

    -- Toggle closed if already open
    if DropDownList1 and DropDownList1:IsShown() and UIDROPDOWNMENU_OPEN_MENU == menu then
        CloseDropDownMenus()
        return
    end

    local summary = pH_Index:GetSummary(sessionId)
    UIDropDownMenu_Initialize(menu, function()
        local archiveInfo = UIDropDownMenu_CreateInfo()
        archiveInfo.text = (summary and summary.isArchived) and "Unarchive session" or "Archive session"
        archiveInfo.func = function()
            pH_History_List.historyController:ConfirmArchive(sessionId, not (summary and summary.isArchived))
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(archiveInfo)

        local deleteInfo = UIDropDownMenu_CreateInfo()
        deleteInfo.text = "Delete permanently"
        deleteInfo.func = function()
            pH_History_List.historyController:ConfirmDelete(sessionId)
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(deleteInfo)

        local selectedId = pH_History_List.historyController:GetSelectedSession()
        local mergeInfo = UIDropDownMenu_CreateInfo()
        if selectedId and selectedId ~= sessionId then
            mergeInfo.text = string.format("Merge into selected (#%s)", tostring(selectedId))
            mergeInfo.func = function()
                pH_History_List.historyController:ConfirmMerge(sessionId, selectedId)
                CloseDropDownMenus()
            end
            mergeInfo.disabled = false
        else
            mergeInfo.text = "Merge into selected (select another session first)"
            mergeInfo.disabled = true
        end
        UIDropDownMenu_AddButton(mergeInfo)
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, anchor, 0, 0)
end

--------------------------------------------------
-- Set Selection
--------------------------------------------------
function pH_History_List:SetSelection(sessionId)
    self.selectedId = sessionId

    -- Re-render to update highlights
    local offset = self.scrollBar:GetValue()
    self:RenderVisibleRows(offset)
end

--------------------------------------------------
-- Scroll To Selection (for keyboard navigation)
--------------------------------------------------
function pH_History_List:ScrollToSelection(index)
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
function pH_History_List:FormatDurationShort(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    else
        return string.format("%dm", mins)
    end
end

--------------------------------------------------
-- Helper: Format "how long ago" for a timestamp
--------------------------------------------------
function pH_History_List:FormatTimeAgo(epoch)
    if not epoch then return "" end
    local now = time()
    local diff = now - epoch
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        local m = math.floor(diff / 60)
        return m .. "m ago"
    elseif diff < 86400 then
        local h = math.floor(diff / 3600)
        return h .. "h ago"
    elseif diff < 604800 then
        local d = math.floor(diff / 86400)
        return d .. "d ago"
    else
        return date("%b %d", epoch)
    end
end

-- Export module
_G.pH_History_List = pH_History_List
