--[[
    UI_History.lua - Main history frame controller for pH

    Manages the session history window with filters, list, and detail panes.
]]

-- luacheck: globals pH_Settings pH_Index UnitName GetRealmName UnitFactionGroup StaticPopupDialogs StaticPopup_Show
-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local pH_History = {
    frame = nil,
    listPane = nil,
    detailPane = nil,
    filtersPane = nil,
    isInitialized = false,

    -- Current state
    selectedSessionId = nil,
    filterState = {
        mode = "gold",
        search = "",
        sort = "totalPerHour",
        sortDesc = true,
        charKeys = nil,
        zone = nil,
        minPerHour = 0,
        excludeShort = true,
        excludeArchived = true,
        hasGathering = false,
        hasPickpocket = false,
    },
}

local function EnsureHistoryPopups()
    if StaticPopupDialogs["PH_ARCHIVE_SESSION"] then
        return
    end

    StaticPopupDialogs["PH_ARCHIVE_SESSION"] = {
        text = "Archive session #%d?\n\nYou can undo for 30 seconds.",
        button1 = "Archive",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self, data)
            pH_History:RunArchiveAction(data and data.sessionId, true)
        end,
    }

    StaticPopupDialogs["PH_UNARCHIVE_SESSION"] = {
        text = "Unarchive session #%d?\n\nYou can undo for 30 seconds.",
        button1 = "Unarchive",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self, data)
            pH_History:RunArchiveAction(data and data.sessionId, false)
        end,
    }

    StaticPopupDialogs["PH_DELETE_SESSION"] = {
        text = "Delete session #%d permanently?\n\nThis removes it from history. Undo is available for 30 seconds.",
        button1 = "Delete",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self, data)
            pH_History:RunDeleteAction(data and data.sessionId)
        end,
    }

    StaticPopupDialogs["PH_MERGE_SESSIONS"] = {
        text = "Merge session #%d into session #%d?\n\nBoth sessions must be on the same character. Undo is available for 30 seconds.",
        button1 = "Merge",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self, data)
            pH_History:RunMergeAction(data and data.sourceId, data and data.targetId)
        end,
    }

    StaticPopupDialogs["PH_ARCHIVE_SHORT"] = {
        text = "Archive all short sessions under %d minutes?\n\nYou can undo for 30 seconds.",
        button1 = "Archive",
        button2 = "Cancel",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(self, data)
            pH_History:RunArchiveShortAction(data and data.thresholdSec)
        end,
    }
end

--------------------------------------------------
-- Initialize
--------------------------------------------------
function pH_History:Initialize()
    if self.isInitialized then
        return
    end

    -- Create main frame (640x480, centered)
    local frame = CreateFrame("Frame", "pH_HistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    -- Enable Escape key to close (taint-free method)
    table.insert(UISpecialFrames, "pH_HistoryFrame")

    -- Enable keyboard: handle Escape + Up/Down for list; propagate all keys to game so movement works
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        pH_History:OnKeyDown(key)
    end)

    -- Backdrop (pH brand colors)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    local PH_BG_PARCHMENT = pH_Colors.BG_PARCHMENT
    local PH_BORDER_BRONZE = pH_Colors.BORDER_BRONZE
    frame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], 0.95)
    frame:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 1)

    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Session History")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        pH_History:Hide()
    end)

    -- Filters pane (top, 40px height)
    local filtersPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    filtersPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    filtersPane:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -35)
    filtersPane:SetHeight(40)
    self.filtersPane = filtersPane

    -- List pane (left, 240px width) - pH brand colors
    local listPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listPane:SetPoint("TOPLEFT", filtersPane, "BOTTOMLEFT", 0, -5)
    listPane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    listPane:SetWidth(240)
    listPane:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    local PH_BG_DARK = pH_Colors.BG_DARK
    local PH_DIVIDER = pH_Colors.DIVIDER
    listPane:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.90)
    listPane:SetBackdropBorderColor(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], 0.80)
    self.listPane = listPane

    -- Detail pane (right, remaining width) - pH brand colors
    local detailPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailPane:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 5, 0)
    detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    detailPane:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    detailPane:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.90)
    detailPane:SetBackdropBorderColor(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], 0.80)
    self.detailPane = detailPane

    self.frame = frame

    -- Initialize sub-components
    pH_History_Filters:Initialize(self.filtersPane, self)
    pH_History_List:Initialize(self.listPane, self)
    pH_History_Detail:Initialize(self.detailPane, self)

    self.isInitialized = true
end

--------------------------------------------------
-- Show/Hide/Toggle
--------------------------------------------------
function pH_History:Show()
    if not self.isInitialized then
        self:Initialize()
    end

    -- Show frame first
    self.frame:Show()

    if not pH_Index then
        print("|cffff8000[pH]|r pH_Index not ready. Retry opening History.")
        return
    end

    EnsureHistoryPopups()

    -- Build index if stale (with loading message)
    if pH_Index.stale then
        -- Show loading message
        local loadingText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        loadingText:SetPoint("CENTER", self.frame, "CENTER")
        loadingText:SetText("Building index...")
        local PH_TEXT_MUTED = pH_Colors.TEXT_MUTED
        loadingText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])

        -- Build index
        pH_Index:Build()

        -- Remove loading message
        loadingText:Hide()
    end

    -- Restore position if saved
    if pH_Settings.historyPosition then
        local pos = pH_Settings.historyPosition
        self.frame:ClearAllPoints()
        self.frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    end

    -- Restore persistent list settings.
    if pH_Settings.historyFilters then
        self.filterState.sort = pH_Settings.historyFilters.sort or "totalPerHour"
        self.filterState.sortDesc = pH_Settings.historyFilters.sortDesc ~= false
        self.filterState.excludeShort = pH_Settings.historyFilters.excludeShort ~= false
        self.filterState.excludeArchived = pH_Settings.historyFilters.excludeArchived ~= false
    end

    -- Reset non-persistent filters on open.
    local currentCharKey = pH_Index:GetCurrentCharKey()
    if currentCharKey then
        self.filterState.charKeys = { [currentCharKey] = true }
    else
        self.filterState.charKeys = nil
    end
    self.filterState.zone = nil
    self.filterState.search = ""
    self.filterState.minPerHour = 0
    self.filterState.hasGathering = false
    self.filterState.hasPickpocket = false
    self.filterState.onlyXP = false
    self.filterState.onlyRep = false
    self.filterState.onlyHonor = false

    -- Sync filter UI to match
    pH_History_Filters:SyncFromFilterState()

    -- Force index rebuild so we have fresh data (e.g. sessions persisted on char switch)
    pH_Index:MarkStale()

    -- Apply filters and refresh list
    self:RefreshList()

    -- Auto-select first session if none selected
    if not self.selectedSessionId then
        local sessionIds = pH_Index:QuerySessions(self.filterState)
        if #sessionIds > 0 then
            self:SelectSession(sessionIds[1])
        end
    end

    pH_Settings.historyVisible = true
end

function pH_History:Hide()
    if not self.frame then
        return
    end

    -- Save position
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    pH_Settings.historyPosition = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }

    -- Save filter state
    pH_Settings.historyFilters = {}
    for k, v in pairs(self.filterState) do
        pH_Settings.historyFilters[k] = v
    end

    self.frame:Hide()
    pH_Settings.historyVisible = false
end

function pH_History:Toggle()
    if not self.isInitialized then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------
-- Refresh List (called when filters change)
--------------------------------------------------
function pH_History:RefreshList()
    -- Query sessions with current filters
    local sessionIds = pH_Index:QuerySessions(self.filterState)

    -- Update list component
    pH_History_List:SetSessions(sessionIds)
end

--------------------------------------------------
-- Select Session (called when user clicks a session)
--------------------------------------------------
function pH_History:SelectSession(sessionId)
    self.selectedSessionId = sessionId

    -- Notify list to update highlight
    pH_History_List:SetSelection(sessionId)

    -- Notify detail pane to show session
    pH_History_Detail:SetSession(sessionId)
end

--------------------------------------------------
-- Get Selected Session ID
--------------------------------------------------
function pH_History:GetSelectedSession()
    return self.selectedSessionId
end

--------------------------------------------------
-- Keyboard Navigation
--------------------------------------------------
function pH_History:OnKeyDown(key)
    if key == "UP" or key == "DOWN" then
        -- Get current filtered session list
        local sessionIds = pH_Index:QuerySessions(self.filterState)
        if #sessionIds == 0 then
            return
        end

        -- Find current selection index
        local currentIndex = 1
        if self.selectedSessionId then
            for i, sessionId in ipairs(sessionIds) do
                if sessionId == self.selectedSessionId then
                    currentIndex = i
                    break
                end
            end
        end

        -- Move up or down
        if key == "UP" then
            currentIndex = math.max(1, currentIndex - 1)
        else -- DOWN
            currentIndex = math.min(#sessionIds, currentIndex + 1)
        end

        -- Select new session
        self:SelectSession(sessionIds[currentIndex])

        -- Scroll list to make selection visible
        pH_History_List:ScrollToSelection(currentIndex)
    end
end

--------------------------------------------------
-- History Actions (archive/delete/merge/undo)
--------------------------------------------------
function pH_History:ShowUndoNotice(message, undoSec)
    print("[pH] " .. message)
    if undoSec then
        print(string.format("[pH] Undo available for %ds: /ph history undo", undoSec))
    end
end

function pH_History:ConfirmArchive(sessionId, archived)
    if not sessionId then return end
    EnsureHistoryPopups()
    if archived then
        StaticPopup_Show("PH_ARCHIVE_SESSION", sessionId, nil, { sessionId = sessionId })
    else
        StaticPopup_Show("PH_UNARCHIVE_SESSION", sessionId, nil, { sessionId = sessionId })
    end
end

function pH_History:ConfirmArchiveShort(thresholdSec)
    EnsureHistoryPopups()
    local threshold = thresholdSec or (pH_Settings and pH_Settings.historyCleanup and pH_Settings.historyCleanup.shortThresholdSec) or 300
    local mins = math.floor(threshold / 60)
    StaticPopup_Show("PH_ARCHIVE_SHORT", mins, nil, { thresholdSec = threshold })
end

function pH_History:RunArchiveShortAction(thresholdSec)
    local ok, message, undoSec = pH_SessionManager:ArchiveShortSessions(thresholdSec or 300)
    self:ShowUndoNotice(message, ok and undoSec or nil)
    self:RefreshList()
    local sessionIds = pH_Index:QuerySessions(self.filterState)
    if #sessionIds > 0 then
        self:SelectSession(sessionIds[1])
    else
        self.selectedSessionId = nil
        pH_History_Detail:SetSession(nil)
    end
end

function pH_History:RunArchiveAction(sessionId, archived)
    if not sessionId then return end
    local ok, message, undoSec = pH_SessionManager:SetSessionArchived(sessionId, archived, "manual")
    self:ShowUndoNotice(message, ok and undoSec or nil)
    self:RefreshList()
    local sessionIds = pH_Index:QuerySessions(self.filterState)
    local selectedVisible = false
    if self.selectedSessionId then
        for _, id in ipairs(sessionIds) do
            if id == self.selectedSessionId then
                selectedVisible = true
                break
            end
        end
    end
    if selectedVisible then
        pH_History_Detail:SetSession(self.selectedSessionId)
    elseif #sessionIds > 0 then
        self:SelectSession(sessionIds[1])
    else
        self.selectedSessionId = nil
        pH_History_Detail:SetSession(nil)
    end
end

function pH_History:ConfirmDelete(sessionId)
    if not sessionId then return end
    EnsureHistoryPopups()
    StaticPopup_Show("PH_DELETE_SESSION", sessionId, nil, { sessionId = sessionId })
end

function pH_History:RunDeleteAction(sessionId)
    if not sessionId then return end
    local ok, message, undoSec = pH_SessionManager:DeleteSession(sessionId)
    self:ShowUndoNotice(message, ok and undoSec or nil)
    if ok and self.selectedSessionId == sessionId then
        self.selectedSessionId = nil
    end
    self:RefreshList()
    if not self.selectedSessionId then
        local sessionIds = pH_Index:QuerySessions(self.filterState)
        if #sessionIds > 0 then
            self:SelectSession(sessionIds[1])
        else
            pH_History_Detail:SetSession(nil)
        end
    end
end

function pH_History:ConfirmMerge(sourceId, targetId)
    if not sourceId or not targetId or sourceId == targetId then
        return
    end
    EnsureHistoryPopups()
    StaticPopup_Show("PH_MERGE_SESSIONS", sourceId, targetId, {
        sourceId = sourceId,
        targetId = targetId,
    })
end

function pH_History:RunMergeAction(sourceId, targetId)
    if not sourceId or not targetId then
        return
    end
    local ok, message, undoSec = pH_SessionManager:MergeSessions({ sourceId, targetId })
    self:ShowUndoNotice(message, ok and undoSec or nil)
    if ok then
        self.selectedSessionId = nil
    end
    self:RefreshList()
    local sessionIds = pH_Index:QuerySessions(self.filterState)
    if #sessionIds > 0 then
        self:SelectSession(sessionIds[1])
    else
        pH_History_Detail:SetSession(nil)
    end
end

-- Export module
_G.pH_History = pH_History
