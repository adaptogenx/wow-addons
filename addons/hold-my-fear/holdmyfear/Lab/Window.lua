--[[
    Lab/Window.lua - /hmflab window: stacked experiment sections + log pane.
    Secure buttons live inside this frame, so show/hide is refused in combat.
]]

local _, HMF = ...
local Lab = HMF.Lab

if not HMF.IS_WARLOCK then return end

local WIDTH, LOG_HEIGHT, TITLE_H = 440, 110, 24
local frame

local function Build()
    local height = TITLE_H + LOG_HEIGHT + 16
    for _, s in ipairs(Lab.sections) do height = height + s.height + 18 end

    frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, height)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.88)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("HMF Targeting Lab  (/hmflab)")

    local y = -TITLE_H
    for _, s in ipairs(Lab.sections) do
        local head = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        head:SetPoint("TOPLEFT", 10, y - 2)
        head:SetText(s.title)
        local body = CreateFrame("Frame", nil, frame)
        body:SetPoint("TOPLEFT", 10, y - 18)
        body:SetSize(WIDTH - 20, s.height)
        s.build(body)
        y = y - s.height - 18
    end

    local log = CreateFrame("ScrollingMessageFrame", nil, frame)
    log:SetPoint("BOTTOMLEFT", 10, 8)
    log:SetSize(WIDTH - 20, LOG_HEIGHT)
    log:SetFontObject(ChatFontNormal)
    log:SetJustifyH("LEFT")
    log:SetMaxLines(200)
    log:SetFading(false)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    Lab.sink = function(line) log:AddMessage(line) end
    for _, line in ipairs(Lab.lines) do log:AddMessage(line) end

    C_Timer.NewTicker(0.25, function()
        if not frame:IsShown() then return end
        for _, fn in ipairs(Lab.tickers) do fn() end
    end)

    frame:Hide()
end

function Lab.Toggle()
    if not frame then Lab.Log("WINDOW", "not built (loaded in combat?); /reload out of combat") return end
    if InCombatLockdown() then
        Lab.Log("BLOCKED", "toggle refused: window holds secure frames, cannot show/hide in combat")
        return
    end
    frame:SetShown(not frame:IsShown())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if InCombatLockdown() then
            Lab.Log("WINDOW", "logged in during combat; secure frames cannot be built")
            return
        end
        Build()
        if GetCVar and GetCVar("nameplateShowEnemies") ~= "1" then
            Lab.Log("WARN", "nameplateShowEnemies is off; enemy nameplate tokens will not resolve")
        end
        local fear = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo("Fear") or (GetSpellInfo and GetSpellInfo("Fear"))
        Lab.Log("WINDOW", "Fear known=%s, ActionButtonUseKeyDown=%s", tostring(fear ~= nil), tostring(GetCVar("ActionButtonUseKeyDown")))
        Lab.Log("WINDOW", "ready; client build %s", select(4, GetBuildInfo()))
    elseif event == "PLAYER_LOGOUT" then
        HoldMyFearDB = HoldMyFearDB or {}
        HoldMyFearDB.labLog = Lab.lines
        HoldMyFearDB.labResults = Lab.results
    end
end)

SLASH_HMFLAB1 = "/hmflab"
SlashCmdList["HMFLAB"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "report" then
        Lab.Report()
    elseif msg == "track" and Lab.Track then
        Lab.Track()
    elseif msg == "clear" and Lab.ClearTracked then
        Lab.ClearTracked()
    else
        Lab.Toggle()
    end
end
