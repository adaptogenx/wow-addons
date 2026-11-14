--[[
    M3: secure casting & raid markers.
    Rules: secure buttons are created/changed ONLY out of combat, only by explicit
    slash command. Nothing here invokes a protected action from insecure code.
    Casts/marks happen only when the PLAYER clicks a button or presses a bound key.
    If ADDON_ACTION_FORBIDDEN/BLOCKED fires, M3 halts (no repeated prompts).
]]
local _, Lab = ...

local M3 = { spell = "Fear", halted = false, blocked = 0, buttons = {}, intent = nil }
Lab.m3 = M3

local function buttonDefs()
    local S = M3.spell
    return {
        { "Fear@target", { type = "spell", spell = S, unit = "target" }, "target" },
        { "Fear@focus", { type = "macro", macrotext = "/cast [@focus,harm,nodead] " .. S }, "focus" },
        { "Fear@mouseover", { type = "macro", macrotext = "/cast [@mouseover,harm,nodead] " .. S }, "mouseover" },
        { "Fear@nameplate1", { type = "macro", macrotext = "/cast [@nameplate1,harm,nodead] " .. S }, "nameplate1" },
        { "/tm 5 (target)", { type = "macro", macrotext = "/tm 5" }, "target" },
        { "/tm 6 (mouseover)", { type = "macro", macrotext = "/tm [@mouseover,harm] 6" }, "mouseover" },
        { "/tm 7 (focus)", { type = "macro", macrotext = "/tm [@focus,harm] 7" }, "focus" },
    }
end

local function snap(token)
    local gs, g = Lab.Probe(UnitGUID, token)
    local ns, n = Lab.Probe(UnitName, token)
    return gs == "READABLE" and g or nil, ns == "READABLE" and n or nil
end

local owner, panel
local function onPreClick(label, token)
    return function()
        local g, n = snap(token)
        local tg, tn = snap("target")
        M3.intent = { label = label, token = token, guid = g, name = n, targetGuid = tg, t = GetTime() }
        Lab.Log("M3", "CLICK %s intended=%s guid=%s name=%s | target-at-click=%s(%s)", label, token, Lab.Short(g), tostring(n),
            Lab.Short(tg), tostring(tn))
    end
end

local function build()
    if InCombatLockdown() then Lab.Log("M3", "BUILD refused: in combat") return end
    if M3.halted then Lab.Log("M3", "BUILD refused: halted after blocked-action event") return end
    local defs = buttonDefs()
    if not panel then
        owner = CreateFrame("Frame", "HMFLabM3Owner", UIParent)
        panel = CreateFrame("Frame", "HMFLabM3Panel", UIParent)
        panel:SetSize(170, #defs * 26 + 6)
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 200)
        for i, d in ipairs(defs) do
            local name = "HMFLabM3Btn" .. i
            local b = CreateFrame("Button", name, panel, "SecureActionButtonTemplate,UIPanelButtonTemplate")
            b:SetSize(164, 24)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3 - (i - 1) * 26)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:HookScript("PreClick", onPreClick(d[1], d[3]))
            M3.buttons[i] = b
        end
        Lab.Log("M3", "BUILD created %d secure buttons (HMFLabM3Btn1..%d)", #defs, #defs)
    end
    for i, d in ipairs(defs) do
        local b = M3.buttons[i]
        for _, k in ipairs({ "type", "spell", "unit", "macrotext" }) do b:SetAttribute(k, nil) end
        for k, v in pairs(d[2]) do b:SetAttribute(k, v) end
        b:SetText(("%d %s"):format(i, d[1]))
    end
    panel:Show()
    Lab.Log("M3", "BUILD attributes applied spell=%s", M3.spell)
end

local function hide()
    if InCombatLockdown() then Lab.Log("M3", "HIDE refused: in combat") return end
    if panel then panel:Hide() end
end

local function bind(arg)
    if InCombatLockdown() then Lab.Log("M3", "BIND refused: in combat") return end
    if not panel then Lab.Log("M3", "BIND: run /hmflab m3build first") return end
    local n, key = (arg or ""):match("^(%d+)%s+(%S+)$")
    n = tonumber(n)
    if not n or not M3.buttons[n] then Lab.Log("M3", "BIND usage: /hmflab m3bind <1-7> <KEY e.g. ALT-F>") return end
    SetOverrideBindingClick(owner, true, key, "HMFLabM3Btn" .. n)
    Lab.Log("M3", "BIND %s -> button %d", key, n)
end

local function unbind()
    if InCombatLockdown() then Lab.Log("M3", "UNBIND refused: in combat") return end
    if owner then ClearOverrideBindings(owner) end
    Lab.Log("M3", "UNBIND all override bindings cleared")
end

local function spell(arg)
    if InCombatLockdown() then Lab.Log("M3", "SPELL refused: in combat") return end
    if arg and arg ~= "" then M3.spell = arg end
    Lab.Log("M3", "SPELL buttons will cast %q (re-run /hmflab m3build to apply)", M3.spell)
end

-- GetRaidTargetIndex accessibility
local function marks()
    local toks = { "player", "target", "focus", "mouseover" }
    local gp = Lab.Resolve("C_NamePlate.GetNamePlates")
    if gp then
        local ok, plates = pcall(gp)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                if type(p.namePlateUnitToken) == "string" then toks[#toks + 1] = p.namePlateUnitToken end
            end
        end
    end
    for _, t in ipairs(toks) do
        local st, v, err = Lab.Probe(GetRaidTargetIndex, t)
        local g = snap(t)
        Lab.Log("M3", "MARK %-12s guid=%s index=%s", t, Lab.Short(g), Lab.Fmt(st, v, err))
    end
end

-- Events: cast diagnostics, raid target updates, blocked actions
local ef = CreateFrame("Frame")
ef:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ef:RegisterEvent("ADDON_ACTION_BLOCKED")
ef:RegisterEvent("RAID_TARGET_UPDATE")
ef:RegisterEvent("UI_ERROR_MESSAGE")
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_SENT", "player")
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_FAILED", "player")
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_SUCCEEDED", "player")
ef:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
    if ev == "ADDON_ACTION_FORBIDDEN" or ev == "ADDON_ACTION_BLOCKED" then
        M3.blocked = M3.blocked + 1
        M3.halted = true
        Lab.Log("M3", "BLOCKED %s addon=%s func=%s -> M3 HALTED (no more secure setup)", ev, a1, a2)
        print("|cffff4444HMFLab M3: blocked-action event, halted. Tell Claude.|r")
    elseif ev == "RAID_TARGET_UPDATE" then
        Lab.Log("M3", "EVT RAID_TARGET_UPDATE")
    elseif ev == "UI_ERROR_MESSAGE" then
        local ms = Lab.Classify(true, a2)
        if ms == "READABLE" and M3.intent and GetTime() - M3.intent.t < 3 then Lab.Log("M3", "UIERR %s", a2) end
    elseif ev == "UNIT_SPELLCAST_SENT" then
        -- payload: unit, targetName, castGUID, spellID
        local ts = Lab.Classify(true, a2)
        local sid = (Lab.Classify(true, a4) == "READABLE") and a4 or nil
        local tg = snap("target")
        local i = M3.intent
        local verdict = "no-intent"
        if i and GetTime() - i.t < 3 then
            if ts == "READABLE" and i.name then verdict = (a2 == i.name) and "RECIPIENT_NAME_MATCH" or "RECIPIENT_NAME_MISMATCH"
            else verdict = "RECIPIENT_UNKNOWN(name " .. ts .. ")" end
            if i.targetGuid ~= tg then verdict = verdict .. " TARGET_CHANGED_BY_CAST" end
        end
        Lab.Log("M3", "SENT spell=%s sentTarget=%s intended=%s(%s) target-now=%s -> %s", tostring(sid), ts == "READABLE" and a2 or ts,
            i and i.token or "-", i and tostring(i.name) or "-", Lab.Short(tg), verdict)
    elseif ev == "UNIT_SPELLCAST_FAILED" then
        Lab.Log("M3", "FAILED spell=%s", Lab.Classify(true, a3) == "READABLE" and tostring(a3) or "unreadable")
    elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
        local i = M3.intent
        if i and GetTime() - i.t < 3 then Lab.Log("M3", "SUCCEEDED spell=%s after click %s", Lab.Classify(true, a3) == "READABLE" and tostring(a3) or "?", i.label) end
    end
end)

Lab.AddCommand("m3spell", "M3: set spell name for cast buttons (default Fear), out of combat", spell)
Lab.AddCommand("m3build", "M3: OUT OF COMBAT. Create/refresh the 7 secure test buttons (panel bottom-left)", build)
Lab.AddCommand("m3hide", "M3: hide panel (out of combat)", hide)
Lab.AddCommand("m3bind", "M3: OUT OF COMBAT. Bind key to button: /hmflab m3bind 3 ALT-F", bind)
Lab.AddCommand("m3unbind", "M3: OUT OF COMBAT. Clear M3 override bindings", unbind)
Lab.AddCommand("m3marks", "M3: GetRaidTargetIndex accessibility on player/target/focus/mouseover/plates", marks)
Lab.AddCommand("m3status", "M3: halted/blocked counters", function()
    Lab.Log("M3", "STATUS halted=%s blocked=%d built=%s", tostring(M3.halted), M3.blocked, tostring(panel ~= nil))
end)
