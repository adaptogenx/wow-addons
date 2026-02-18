--[[
    AutoSession.lua - Automatic session start/pause/resume management

    Handles:
    - Auto-start on meaningful activity (loot, combat, etc.)
    - Auto-pause on AFK or inactivity
    - Auto-resume on activity while paused
    - Instance entry detection (start paused, resume on first activity)
]]

-- luacheck: globals pH_SessionManager pH_Settings pH_HUD pH_Colors UnitIsAFK IsInInstance GetTime time

local pH_AutoSession = {}

-- Runtime state (not persisted)
local state = {
    lastActivityAt = nil,           -- Timestamp of last meaningful activity
    autoPausedReason = nil,         -- nil, "afk", or "inactivity" (tracks why session was auto-paused)
    inactivityToastShown = false,   -- Whether we've shown the 5-min inactivity prompt
    wasPausedLastCheck = nil,       -- True if session was paused last CheckInactivity (so we detect resume)
    toastFrame = nil,               -- Toast notification UI frame
    timerFrame = nil,               -- OnUpdate frame for inactivity checking
    afkFrame = nil,                 -- Frame for PLAYER_FLAGS_CHANGED event
}

-- Events that may update activity timestamp or trigger auto-resume (broad)
local TRIGGER_EVENTS = {
    CHAT_MSG_MONEY = true,
    CHAT_MSG_LOOT = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    PLAYER_XP_UPDATE = true,
    CHAT_MSG_COMBAT_HONOR_GAIN = true,
    QUEST_TURNED_IN = true,
    MERCHANT_SHOW = true,  -- Resume only, not start
}

-- Events that are allowed to auto-start a session (narrow: only clear earning activity)
-- Excludes UNIT_SPELLCAST_SUCCEEDED (fires on every spell: mount, buff, etc.) and
-- PLAYER_XP_UPDATE (can fire on login/sync). MERCHANT_SHOW never starts, only resumes.
local AUTO_START_EVENTS = {
    CHAT_MSG_MONEY = true,           -- Looted coin
    CHAT_MSG_LOOT = true,             -- Looted item
    QUEST_TURNED_IN = true,          -- Quest reward
    CHAT_MSG_COMBAT_HONOR_GAIN = true,-- Honor gain
}

-- Initialize the auto-session system
function pH_AutoSession:Initialize()
    -- Ensure settings exist
    if not pH_Settings.autoSession then
        pH_Settings.autoSession = {
            enabled = true,
            autoStart = true,
            instanceStart = true,
            afkPause = true,
            inactivityPromptMin = 5,
            inactivityPauseMin = 10,
            autoResume = true,
        }
    end

    -- Create timer frame for inactivity checking
    state.timerFrame = CreateFrame("Frame")
    state.timerFrame:SetScript("OnUpdate", function(self, elapsed)
        self.timer = (self.timer or 0) + elapsed
        if self.timer >= 10 then  -- Check every 10 seconds
            pH_AutoSession:CheckInactivity()
            self.timer = 0
        end
    end)

    -- Create AFK detection frame
    state.afkFrame = CreateFrame("Frame")
    state.afkFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
    state.afkFrame:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_FLAGS_CHANGED" and unit == "player" then
            pH_AutoSession:OnPlayerFlagsChanged(unit)
        end
    end)

    -- Initialize toast UI (created lazily on first use)
    -- Will be created in CreateToastUI() when needed
end

-- Returns true if this event+message should NOT trigger auto-start/resume (AH, mail)
local function ShouldSkipAutoStartForMessage(event, message)
    if event ~= "CHAT_MSG_MONEY" and event ~= "CHAT_MSG_LOOT" then
        return false
    end
    if not message or type(message) ~= "string" then
        return false
    end
    local lower = message:lower()
    return lower:find("auction") or lower:find("mail")
end

-- Handle an event - may auto-start or auto-resume session
function pH_AutoSession:HandleEvent(event, ...)
    -- Early return if disabled
    if not pH_Settings.autoSession or not pH_Settings.autoSession.enabled then
        return
    end

    -- Check if this is a trigger event
    if not TRIGGER_EVENTS[event] then
        return
    end

    local session = pH_SessionManager:GetActiveSession()

    -- Case 1: No active session - auto-start only on clear earning events
    if not session then
        if pH_Settings.autoSession.autoStart and AUTO_START_EVENTS[event] then
            local msg = select(1, ...)
            if ShouldSkipAutoStartForMessage(event, msg) then
                return
            end
            local ok, message = pH_SessionManager:StartSession()
            if ok then
                state.lastActivityAt = GetTime()
                state.autoPausedReason = nil
                state.inactivityToastShown = false
                if pH_HUD then
                    pH_HUD:Update()
                end
                print("[pH] Auto-started session: " .. (message or ""))
            end
        end
        return
    end

    -- Case 2: Session is paused - auto-resume if enabled and was auto-paused
    if session.pausedAt then
        -- Only auto-resume if it was auto-paused (not manually paused)
        if pH_Settings.autoSession.autoResume and state.autoPausedReason then
            local msg = select(1, ...)
            if ShouldSkipAutoStartForMessage(event, msg) then
                return
            end
            local ok, message = pH_SessionManager:ResumeSession()
            if ok then
                state.lastActivityAt = GetTime()
                local reason = state.autoPausedReason
                state.autoPausedReason = nil
                state.inactivityToastShown = false
                if pH_HUD then
                    pH_HUD:Update()
                end
                if reason == "instance" then
                    print("[pH] Session resumed (first activity in instance).")
                else
                    print("[pH] Auto-resumed session: " .. (message or ""))
                end
            end
        end
        return
    end

    -- Case 3: Active session - update activity timestamp
    state.lastActivityAt = GetTime()
    state.inactivityToastShown = false  -- Reset toast flag on activity
end

-- Handle PLAYER_ENTERING_WORLD - check for instance entry
function pH_AutoSession:OnPlayerEnteringWorld()
    if not pH_Settings.autoSession or not pH_Settings.autoSession.enabled then
        return
    end

    if not pH_Settings.autoSession.instanceStart then
        return
    end

    -- Check if we're entering an instance
    local isInstance, instanceType = IsInInstance()
    if not isInstance then
        return
    end

    -- Only start if we don't already have an active session
    local session = pH_SessionManager:GetActiveSession()
    if session then
        return
    end

    -- Start session paused; will auto-resume on first activity (loot, XP, honor, etc.)
    local ok, message = pH_SessionManager:StartSession()
    if ok then
        pH_SessionManager:PauseSession()
        state.lastActivityAt = GetTime()
        state.autoPausedReason = "instance"
        state.inactivityToastShown = false
        if pH_HUD then
            pH_HUD:Update()
        end
        print("[pH] Session started (paused in instance). It will resume when you loot, gain XP, complete a quest, or earn honor.")
    end
end

-- Check for inactivity and show prompt or auto-pause
function pH_AutoSession:CheckInactivity()
    if not pH_Settings.autoSession or not pH_Settings.autoSession.enabled then
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    if not session then
        state.wasPausedLastCheck = nil
        return
    end

    -- Just resumed (was paused last check, now not paused): reset activity and don't show toast
    if session.pausedAt then
        state.wasPausedLastCheck = true
        return
    end
    if state.wasPausedLastCheck then
        state.lastActivityAt = GetTime()
        state.inactivityToastShown = false
        state.wasPausedLastCheck = false
        self:HideToast()
        return
    end
    state.wasPausedLastCheck = false

    -- If no activity timestamp yet, initialize it
    if not state.lastActivityAt then
        state.lastActivityAt = GetTime()
        return
    end

    local now = GetTime()
    local idleSeconds = now - state.lastActivityAt
    local promptMin = pH_Settings.autoSession.inactivityPromptMin or 5
    local pauseMin = pH_Settings.autoSession.inactivityPauseMin or 10

    -- Show prompt at 5 minutes
    if idleSeconds >= (promptMin * 60) and not state.inactivityToastShown then
        self:ShowInactivityToast()
        state.inactivityToastShown = true
    end

    -- Auto-pause at 10 minutes
    if idleSeconds >= (pauseMin * 60) then
        local ok, message = pH_SessionManager:PauseSession()
        if ok then
            state.autoPausedReason = "inactivity"
            state.inactivityToastShown = false
            self:HideToast()
            if pH_HUD then
                pH_HUD:Update()
            end
            print("[pH] Auto-paused session due to inactivity: " .. (message or ""))
        end
    end
end

-- Handle AFK flag changes
function pH_AutoSession:OnPlayerFlagsChanged(unit)
    if not pH_Settings.autoSession or not pH_Settings.autoSession.enabled then
        return
    end

    if not pH_Settings.autoSession.afkPause then
        return
    end

    local session = pH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    local isAFK = UnitIsAFK("player")

    if isAFK and not session.pausedAt then
        -- Pause on AFK
        local ok, message = pH_SessionManager:PauseSession()
        if ok then
            state.autoPausedReason = "afk"
            state.inactivityToastShown = false
            self:HideToast()
            if pH_HUD then
                pH_HUD:Update()
            end
            print("[pH] Auto-paused session (AFK): " .. (message or ""))
        end
    elseif not isAFK and session.pausedAt and state.autoPausedReason == "afk" then
        -- Resume on un-AFK (only if it was auto-paused due to AFK)
        if pH_Settings.autoSession.autoResume then
            local ok, message = pH_SessionManager:ResumeSession()
            if ok then
                state.lastActivityAt = GetTime()
                state.autoPausedReason = nil
                state.inactivityToastShown = false
                if pH_HUD then
                    pH_HUD:Update()
                end
                print("[pH] Auto-resumed session (no longer AFK): " .. (message or ""))
            end
        end
    end
end

-- Create toast UI frame (lazy initialization)
local function CreateToastUI()
    if state.toastFrame then
        return state.toastFrame
    end

    local toast = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    toast:SetSize(300, 100)
    toast:SetFrameStrata("DIALOG")
    toast:SetFrameLevel(1000)
    toast:SetMovable(false)
    toast:EnableMouse(true)
    toast:Hide()

    -- Background
    local bg = toast:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(pH_Colors.BG_PARCHMENT))

    -- Border
    toast:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    toast:SetBackdropBorderColor(unpack(pH_Colors.BORDER_BRONZE))

    -- Message text (anchored above button row so it never overlaps)
    local messageText = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("TOP", toast, "TOP", 0, -12)
    messageText:SetPoint("LEFT", toast, "LEFT", 12, 0)
    messageText:SetPoint("RIGHT", toast, "RIGHT", -12, 0)
    messageText:SetPoint("BOTTOM", toast, "BOTTOM", 0, 44)
    messageText:SetJustifyH("CENTER")
    messageText:SetJustifyV("TOP")
    messageText:SetTextColor(unpack(pH_Colors.TEXT_PRIMARY))
    messageText:SetWordWrap(true)
    toast.messageText = messageText

    -- Action button (e.g., "Pause" or "Start")
    local actionBtn = CreateFrame("Button", nil, toast, "UIPanelButtonTemplate")
    actionBtn:SetSize(90, 24)
    actionBtn:SetPoint("BOTTOMLEFT", toast, "BOTTOM", 12, 10)
    actionBtn:SetText("Pause")
    actionBtn:SetScript("OnClick", function()
        toast.actionCallback()
        pH_AutoSession:HideToast()
    end)
    toast.actionBtn = actionBtn

    -- Dismiss button
    local dismissBtn = CreateFrame("Button", nil, toast, "UIPanelButtonTemplate")
    dismissBtn:SetSize(90, 24)
    dismissBtn:SetPoint("BOTTOMRIGHT", toast, "BOTTOM", -12, 10)
    dismissBtn:SetText("Dismiss")
    dismissBtn:SetScript("OnClick", function()
        pH_AutoSession:HideToast()
    end)
    toast.dismissBtn = dismissBtn

    -- Auto-dismiss timer
    toast.autoDismissTimer = 0

    toast:SetScript("OnUpdate", function(self, elapsed)
        self.autoDismissTimer = self.autoDismissTimer + elapsed
        if self.autoDismissTimer >= 30 then
            pH_AutoSession:HideToast()
        end
    end)

    state.toastFrame = toast
    return toast
end

-- Show inactivity toast prompt
function pH_AutoSession:ShowInactivityToast()
    local toast = CreateToastUI()
    if not toast then
        return
    end

    -- Position below HUD if it exists
    local hudFrame = _G["pH_HUD_Frame"]
    if hudFrame and hudFrame:IsVisible() then
        toast:SetPoint("TOP", hudFrame, "BOTTOM", 0, -8)
    else
        toast:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end

    toast.messageText:SetText("No activity detected. Pause session?")
    toast.actionBtn:SetText("Pause")
    toast.actionCallback = function()
        local ok, message = pH_SessionManager:PauseSession()
        if ok then
            state.autoPausedReason = "inactivity"
            state.inactivityToastShown = false
            if pH_HUD then
                pH_HUD:Update()
            end
            print("[pH] Session paused: " .. (message or ""))
        end
    end

    toast.autoDismissTimer = 0
    toast:Show()
end

-- Hide toast
function pH_AutoSession:HideToast()
    if state.toastFrame then
        state.toastFrame:Hide()
    end
end

-- Export
_G.pH_AutoSession = pH_AutoSession
