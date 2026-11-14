--[[
    Lab/Combat.lua - Experiment 2: can secure frames acquire NEW hostile
    unit references during combat?

    Terminology used in all logs:
      INSECURE-TRACK  addon Lua noticed a GUID (events, nameplates). Free
                      in combat, but cannot touch secure attributes.
      SECURE-BIND     a button's `unit` attribute actually changed. Only
                      allowed from (a) out-of-combat insecure code or
                      (b) a restricted snippet run by a secure handler.

    Four buttons + one SecureHandler are created before combat. Approaches:
      A  insecure SetAttribute on a button in combat        (expect blocked)
      B  insecure SetAttribute on the handler in combat     (expect blocked)
      C  state-driver-triggered snippet writes an attribute  (in combat)
      D  which unit APIs exist inside the restricted env
      E  snippet rescans nameplates by raid marker and rebinds buttons
      F  target change / ALT re-run the snippet in combat via state drivers
    Marker i is permanently tied to slot/button i; insecure code stamps the
    marker on a newly seen mob, the snippet finds it by marker.
]]

local _, HMF = ...
local Lab = HMF.Lab

local SLOTS = 4

-- Restricted-environment snippets (plain strings; run by the secure handler).
local SNIPPET_PROBE = [[
    local caps = ""
    if UnitExists then caps = caps .. "UnitExists " end
    if UnitGUID then caps = caps .. "UnitGUID " end
    if UnitIsUnit then caps = caps .. "UnitIsUnit " end
    if UnitName then caps = caps .. "UnitName " end
    if UnitIsEnemy then caps = caps .. "UnitIsEnemy " end
    if GetRaidTargetIndex then caps = caps .. "GetRaidTargetIndex " end
    local n = (self:GetAttribute("n") or 0) + 1
    self:SetAttribute("n", n)
    self:SetAttribute("caps", n .. "|" .. caps)
]]

local SNIPPET_REBIND = [[
    local n = (self:GetAttribute("n") or 0) + 1
    self:SetAttribute("n", n)
    self:SetAttribute("out", n .. "|" .. stateid .. "=" .. newstate .. " entered")
    local msg = ""
    for i = 1, 4 do
        local b = self:GetFrameRef("b" .. i)
        local want = self:GetAttribute("marker" .. i)
        if GetRaidTargetIndex and want then
            for n = 1, 40 do
                local t = "nameplate" .. n
                if GetRaidTargetIndex(t) == want then
                    b:SetAttribute("unit", t)
                    msg = msg .. i .. "=" .. t .. " "
                    break
                end
            end
        end
    end
    -- Proof a snippet can write secure attributes mid-combat, independent of D/E.
    self:GetFrameRef("b1"):SetAttribute("hmfproof", stateid .. "=" .. newstate)
    n = n + 1
    self:SetAttribute("n", n)
    self:SetAttribute("out", n .. "|" .. stateid .. "=" .. newstate .. " rebound: " .. msg)
]]

local buttons, handler = {}, nil
local slotGUID = {}

local function MarkVisible()
    if InCombatLockdown() then Lab.Log("BLOCKED", "mark/bind refused in combat (use auto-track)") return end
    local slot = 0
    for i = 1, 40 do
        local t = "nameplate" .. i
        if UnitExists(t) and UnitCanAttack("player", t) and slot < SLOTS then
            slot = slot + 1
            slotGUID[slot] = UnitGUID(t)
            SetRaidTarget(t, slot)
            buttons[slot]:SetAttribute("unit", t)
            Lab.Log("SECURE-BIND", "out of combat: slot %d -> %s (%s)", slot, t, Lab.Short(slotGUID[slot]))
        end
    end
end

-- Newly seen hostile in combat: track + stamp marker (both insecure, allowed).
local function OnNewEnemy(token)
    local guid = UnitGUID(token)
    if not guid or not UnitCanAttack("player", token) then return end
    for i = 1, SLOTS do if slotGUID[i] == guid then return end end
    for i = 1, SLOTS do
        if not slotGUID[i] then
            slotGUID[i] = guid
            SetRaidTarget(token, i)
            Lab.Log("INSECURE-TRACK", "%s (%s) -> slot %d, marker %d; button NOT rebound until a secure trigger (target change / ALT)",
                token, Lab.Short(guid), i, i)
            Lab.Result("G insecure detection of new enemies (nameplate event)", "works", "NAME_PLATE_UNIT_ADDED fires in combat")
            return
        end
    end
    Lab.Log("INSECURE-TRACK", "%s (%s) has no free slot", token, Lab.Short(guid))
end

local function CombatStartTests()
    local b1 = buttons[1]
    local before = b1:GetAttribute("unit")
    local blockedBefore = Lab.blocked or 0
    pcall(b1.SetAttribute, b1, "unit", "nameplate9")
    local changed = b1:GetAttribute("unit") ~= before
    Lab.Result("A insecure SetAttribute(button) in combat", changed and "works" or "blocked",
        ("blocked events +%d"):format((Lab.blocked or 0) - blockedBefore))
    if changed then b1:SetAttribute("unit", before) end

    blockedBefore = Lab.blocked or 0
    pcall(handler.SetAttribute, handler, "marker1", 7)
    Lab.Result("B insecure SetAttribute(handler) in combat",
        handler:GetAttribute("marker1") == 7 and "works" or "blocked",
        ("blocked events +%d"):format((Lab.blocked or 0) - blockedBefore))
end

Lab.AddSection("Exp 2: new enemies in combat (secure handler + state drivers)", SLOTS * 26 + 30, function(parent)
    handler = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate,SecureHandlerAttributeTemplate")
    handler:SetAttribute("_onstate-combat", SNIPPET_REBIND)
    handler:SetAttribute("_onstate-tgt", SNIPPET_REBIND)
    handler:SetAttribute("_onstate-alt", SNIPPET_REBIND)
    handler:SetAttribute("_onattributechanged", [[
        if name == "probe" then ]] .. SNIPPET_PROBE .. [[ end
    ]])

    local rows = {}
    for i = 1, SLOTS do
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
        btn:SetSize(120, 22)
        btn:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
        btn:SetText("Fear slot " .. i)
        btn:RegisterForClicks("AnyDown", "AnyUp")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", "Fear")
        btn:SetAttribute("unit", "nameplate" .. i)
        btn:HookScript("PreClick", function()
            Lab.Cast.Intend("exp2:slot" .. i, slotGUID[i], btn:GetAttribute("unit"), nil)
        end)
        buttons[i] = btn
        handler:SetFrameRef("b" .. i, btn)
        handler:SetAttribute("marker" .. i, i)

        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", btn, "RIGHT", 8, 0)
        rows[i] = text
    end

    local mark = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    mark:SetSize(170, 22)
    mark:SetPoint("TOPLEFT", 0, -SLOTS * 26 - 4)
    mark:SetText("Mark + bind visible enemies")
    mark:SetScript("OnClick", MarkVisible)

    -- Secure triggers: these re-run the snippet during combat with no addon action.
    RegisterStateDriver(handler, "combat", "[combat] in; out")
    RegisterStateDriver(handler, "tgt", "[@target,exists] has; none")
    RegisterStateDriver(handler, "alt", "[mod:alt] down; up")

    handler:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "out" then
            Lab.Log("SECURE-BIND", "snippet ran: %s", value)
            Lab.Result("C secure snippet SetAttribute in combat (state driver)",
                InCombatLockdown() and "works" or "unknown", "see hmfproof attribute")
            Lab.Result("F state drivers (target/ALT/combat) re-run snippet in combat", "works", value)
        elseif name == "caps" then
            Lab.Result("D restricted env unit APIs", "works", value)
            Lab.Result("E marker-based secure rebind", value:find("GetRaidTargetIndex") and "works" or "blocked",
                value:find("GetRaidTargetIndex") and "GetRaidTargetIndex available in snippet" or "no GetRaidTargetIndex in restricted env")
        end
    end)

    Lab.OnTick(function()
        for i = 1, SLOTS do
            local unit = buttons[i]:GetAttribute("unit")
            rows[i]:SetText(("slot %d marker %d bound=%s guid(bound)=%s tracked=%s proof=%s"):format(i, i,
                tostring(unit), Lab.Short(unit and UnitGUID(unit)), Lab.Short(slotGUID[i]),
                tostring(buttons[1]:GetAttribute("hmfproof"))))
        end
    end)

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    ev:SetScript("OnEvent", function(_, event, token)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Lockdown is not yet active inside this event; test a beat later.
            C_Timer.After(0.2, function()
                if InCombatLockdown() then CombatStartTests() end
            end)
        elseif InCombatLockdown() then
            OnNewEnemy(token)
        end
    end)

    -- Capability probe: set from the secure side's own attribute change, out of combat.
    handler:SetAttribute("probe", GetTime())
end)
