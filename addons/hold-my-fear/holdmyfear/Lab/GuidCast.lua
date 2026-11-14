--[[
    Lab/GuidCast.lua - Experiment 3: reliable one-click casting on a
    specific GUID.

    Scenario: fear two identical mobs, target a third, click each row.
    Rows are stable per GUID (row index == raid marker index). The secure
    button's `unit` is the current nameplate token for that GUID, re-resolved
    and re-bound out of combat only (and just-in-time in PreClick when out
    of combat). In combat a stale binding cannot be fixed, so the click is
    flagged and the Fear cast is cancelled at UNIT_SPELLCAST_START rather
    than silently hitting the wrong mob.
]]

local _, HMF = ...
local Lab = HMF.Lab

local ROWS = 4
local rows = {}
local dirty = false

local function Resolve(guid)
    if not guid then return nil end
    for i = 1, 40 do
        local t = "nameplate" .. i
        if UnitGUID(t) == guid then return t end
    end
    if UnitGUID("target") == guid then return "target" end
    if UnitGUID("focus") == guid then return "focus" end
end

local function Bind(row)
    if InCombatLockdown() then dirty = true return end
    local token = Resolve(row.guid)
    local current = row.btn:GetAttribute("unit")
    -- A non-existent token fails the cast instead of falling back to "target".
    local want = token or "nameplate99"
    if current ~= want then
        row.btn:SetAttribute("unit", want)
        Lab.Log("SECURE-BIND", "row %d (%s): %s -> %s", row.index, Lab.Short(row.guid), tostring(current), want)
    end
    if token and GetRaidTargetIndex(token) ~= row.index then SetRaidTarget(token, row.index) end
end

local function RebindAll()
    dirty = false
    for _, row in ipairs(rows) do if row.guid then Bind(row) end end
end

function Lab.TrackGUID(guid, name)
    if not guid then return end
    for _, row in ipairs(rows) do if row.guid == guid then return end end
    for _, row in ipairs(rows) do
        if not row.guid then
            row.guid, row.name = guid, name
            Lab.Log("INSECURE-TRACK", "row %d marker %d = %s (%s)", row.index, row.index, Lab.Short(guid), tostring(name))
            Bind(row)
            return
        end
    end
    Lab.Log("INSECURE-TRACK", "no free row for %s", Lab.Short(guid))
end

function Lab.Track()
    if UnitExists("target") and UnitCanAttack("player", "target") then
        Lab.TrackGUID(UnitGUID("target"), UnitName("target"))
    else
        Lab.Log("WARN", "target a hostile mob first")
    end
end

function Lab.ClearTracked()
    for _, row in ipairs(rows) do row.guid, row.name, row.last = nil, nil, nil end
    Lab.Log("INSECURE-TRACK", "rows cleared")
end

-- Mobs feared by the player get tracked automatically (scenario: fear two, target a third).
function Lab.OnFeared(guid, name) Lab.TrackGUID(guid, name) end

Lab.Cast.OnResult(function(pending, actual, subevent, ok)
    local row = pending.row and rows[pending.row]
    if not row then return end
    row.last = ("%s %s actual=%s"):format(ok and "OK" or "WRONG", subevent, Lab.Short(actual))
    if ok then
        Lab.Result("H one-click GUID-specific cast", "works", "last: " .. row.last)
    else
        Lab.Result("H one-click GUID-specific cast", "blocked", "wrong target: " .. row.last)
    end
end)

Lab.AddSection("Exp 3: one-click Fear on a tracked GUID (/hmflab track, or just Fear mobs)", ROWS * 26 + 30, function(parent)
    for i = 1, ROWS do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
        btn:SetSize(90, 22)
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        btn:SetText("Fear #" .. i)
        btn:RegisterForClicks("AnyDown", "AnyUp")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", "Fear")
        btn:SetAttribute("unit", "nameplate99")

        local icon = parent:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i)

        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)

        local row = { index = i, btn = btn, text = text }
        rows[i] = row
        btn:HookScript("PreClick", function()
            if not row.guid then
                Lab.Log("WARN", "row %d has no tracked GUID", i)
                Lab.Cast.Intend("exp3:" .. i, nil, "nameplate99", i)
                return
            end
            Bind(row) -- just-in-time refresh; no-op in combat
            Lab.Cast.Intend("exp3:" .. i, row.guid, btn:GetAttribute("unit"), i)
        end)
    end

    local track = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    track:SetSize(110, 22)
    track:SetPoint("TOPLEFT", 0, -ROWS * 26 - 4)
    track:SetText("Track target")
    track:SetScript("OnClick", Lab.Track)
    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetSize(80, 22)
    clear:SetPoint("LEFT", track, "RIGHT", 6, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", Lab.ClearTracked)

    Lab.OnTick(function()
        if dirty and not InCombatLockdown() then RebindAll() end
        for _, row in ipairs(rows) do
            if not row.guid then
                row.text:SetText("(empty)")
            else
                local cur = Resolve(row.guid)
                local bound = row.btn:GetAttribute("unit")
                local state
                if not cur then state = "UNAVAILABLE"
                elseif bound ~= cur then state = "STALE bound=" .. tostring(bound)
                else state = "OK" end
                row.text:SetText(("%s guid=%s tok=%s marker=%d %s %s"):format(tostring(row.name),
                    Lab.Short(row.guid), tostring(cur), row.index, state, row.last or ""))
            end
        end
    end)

    local ev = CreateFrame("Frame")
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        ev:RegisterEvent(e)
    end
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" or not InCombatLockdown() then RebindAll() else dirty = true end
    end)
end)
