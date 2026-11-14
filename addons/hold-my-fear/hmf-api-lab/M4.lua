--[[
    M4: integrated diagnostic HUD using ONLY mechanisms that passed M1-M3:
      - readable GUIDs from target/focus/mouseover/nameplates (M1)
      - secure mouseover/focus Fear + /tm marks via pre-created buttons and bound keys (M3)
      - player-cast ESTIMATED Fear timer, always labeled EST (M2). No aura reads.
    Unsupported features are shown as disabled, never simulated:
      Fear break/expire detection, authoritative Fear timer, marker readback.
    Row <-> mob mapping changes ONLY by a user action (mark key over a mob) and is logged.
]]
local _, Lab = ...

local M4 = { rows = {}, dur = 10, built = false, stats = { reassign = 0, conflict = 0, unattributed = 0, sentMismatch = 0 }, intent = nil }
Lab.m4 = M4
local NROWS = 4
local FEAR = { [5782] = true, [6213] = true, [6215] = true }

local function snap(token)
    local gs, g = Lab.Probe(UnitGUID, token)
    local ns, n = Lab.Probe(UnitName, token)
    return gs == "READABLE" and g or nil, ns == "READABLE" and n or nil
end

local function allTokens()
    local t = { "target", "focus", "mouseover" }
    local gp = Lab.Resolve("C_NamePlate.GetNamePlates")
    if gp then
        local ok, plates = pcall(gp)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                if type(p.namePlateUnitToken) == "string" then t[#t + 1] = p.namePlateUnitToken end
            end
        end
    end
    return t
end

local function liveToken(guid)
    for _, tok in ipairs(allTokens()) do
        local g = snap(tok)
        if g and g == guid then return tok end
    end
    return nil
end

local function rowOfGuid(guid)
    for i = 1, NROWS do if M4.rows[i] and M4.rows[i].guid == guid then return i end end
end

-- ===== HUD =====
local hud
local function buildHud()
    hud = CreateFrame("Frame", "HMFLabM4Hud", UIParent)
    hud:SetSize(330, NROWS * 34 + 40)
    hud:SetPoint("RIGHT", UIParent, "RIGHT", -20, 80)
    hud.title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hud.title:SetPoint("TOPLEFT", 4, -2)
    hud.title:SetText("HMF M4 diag  (Fear EST only)")
    hud.rows = {}
    for i = 1, NROWS do
        local r = CreateFrame("Frame", nil, hud)
        r:SetSize(326, 32)
        r:SetPoint("TOPLEFT", hud, "TOPLEFT", 2, -20 - (i - 1) * 34)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24) r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
        r.icon:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
        r.l1 = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.l1:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 4, 0) r.l1:SetJustifyH("LEFT")
        r.l2 = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        r.l2:SetPoint("TOPLEFT", r.l1, "BOTTOMLEFT", 0, -1) r.l2:SetJustifyH("LEFT")
        hud.rows[i] = r
    end
    hud.foot = hud:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hud.foot:SetPoint("BOTTOMLEFT", 4, 2)
    hud.foot:SetText("DISABLED: Fear break/expire detect, real Fear timer, marker readback")
end

local function refresh()
    if not hud then return end
    local now = GetTime()
    for i = 1, NROWS do
        local row, r = M4.rows[i], hud.rows[i]
        if not row then
            r.l1:SetText("|cff888888row " .. i .. ": empty (hover mob, press SHIFT-" .. i .. ")|r")
            r.l2:SetText("")
        else
            local tok = liveToken(row.guid)
            r.l1:SetText(("%s  %s"):format(tostring(row.name), Lab.Short(row.guid)))
            local est = "no Fear cast"
            if row.estExpire then
                local left = row.estExpire - now
                est = left > 0 and ("EST Fear ~%.0fs (not authoritative)"):format(left) or "EST Fear elapsed (unverified)"
            end
            r.l2:SetText(("%s | %s"):format(tok and ("visible:" .. tok) or "not visible", est))
        end
    end
end

-- ===== secure buttons =====
local owner, panel
local BTN = {}
local function defs()
    local S = "Fear"
    local d = {}
    for i = 1, NROWS do
        d[#d + 1] = { "Mark row " .. i .. " (mouseover)", { type = "macro", macrotext = ("/tm [@mouseover,harm,nodead] %d"):format(i) }, "mark", i, "SHIFT-" .. i }
    end
    d[#d + 1] = { "Fear @mouseover", { type = "macro", macrotext = "/cast [@mouseover,harm,nodead] " .. S }, "fear", "mouseover", "SHIFT-F" }
    d[#d + 1] = { "Fear @focus", { type = "macro", macrotext = "/cast [@focus,harm,nodead] " .. S }, "fear", "focus", "SHIFT-D" }
    d[#d + 1] = { "Focus <- mouseover", { type = "macro", macrotext = "/focus [@mouseover,harm,nodead]" }, "focus", "mouseover", "SHIFT-R" }
    return d
end

local function assignRow(i, guid, name)
    local old = M4.rows[i]
    local other = rowOfGuid(guid)
    if other and other ~= i then
        M4.stats.conflict = M4.stats.conflict + 1
        Lab.Log("M4", "CONFLICT guid=%s already row %d; user marked it as row %d -> moving (user action)", Lab.Short(guid), other, i)
        M4.rows[other] = nil
    end
    if old and old.guid ~= guid then
        M4.stats.reassign = M4.stats.reassign + 1
        Lab.Log("M4", "REASSIGN row %d %s -> %s (USER ACTION)", i, Lab.Short(old.guid), Lab.Short(guid))
    elseif not old then
        Lab.Log("M4", "ASSIGN row %d = %s (%s) marker %d", i, Lab.Short(guid), tostring(name), i)
    end
    if not old or old.guid ~= guid then M4.rows[i] = { guid = guid, name = name } end
    refresh()
end

local function onPreClick(d)
    return function()
        local kind = d[3]
        if kind == "mark" then
            local g, n = snap("mouseover")
            if g then assignRow(d[4], g, n) else Lab.Log("M4", "MARK row %d clicked with no readable mouseover; no row change", d[4]) end
        elseif kind == "fear" then
            local g, n = snap(d[4])
            M4.intent = { token = d[4], guid = g, name = n, t = GetTime() }
            Lab.Log("M4", "FEARCLICK %s guid=%s name=%s row=%s", d[4], Lab.Short(g), tostring(n), tostring(g and rowOfGuid(g) or nil))
        elseif kind == "focus" then
            local g, n = snap("mouseover")
            Lab.Log("M4", "FOCUSCLICK mouseover guid=%s name=%s", Lab.Short(g), tostring(n))
        end
    end
end

local function build()
    if InCombatLockdown() then Lab.Log("M4", "BUILD refused: in combat") return end
    if Lab.m3 and Lab.m3.halted then Lab.Log("M4", "BUILD refused: blocked-action seen earlier") return end
    if not hud then buildHud() end
    local ds = defs()
    if not panel then
        owner = CreateFrame("Frame", "HMFLabM4Owner", UIParent)
        panel = CreateFrame("Frame", "HMFLabM4Panel", UIParent)
        panel:SetSize(170, #ds * 26 + 6)
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 420)
        for i, d in ipairs(ds) do
            local b = CreateFrame("Button", "HMFLabM4Btn" .. i, panel, "SecureActionButtonTemplate,UIPanelButtonTemplate")
            b:SetSize(164, 24)
            b:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3 - (i - 1) * 26)
            b:RegisterForClicks("AnyUp", "AnyDown")
            b:HookScript("PreClick", onPreClick(d))
            BTN[i] = b
        end
        Lab.Log("M4", "BUILD created %d secure buttons", #ds)
    end
    for i, d in ipairs(ds) do
        for _, k in ipairs({ "type", "macrotext" }) do BTN[i]:SetAttribute(k, nil) end
        for k, v in pairs(d[2]) do BTN[i]:SetAttribute(k, v) end
        BTN[i]:SetText(d[1] .. " [" .. d[5] .. "]")
    end
    ClearOverrideBindings(owner)
    for i, d in ipairs(ds) do SetOverrideBindingClick(owner, true, d[5], "HMFLabM4Btn" .. i) end
    panel:Show() hud:Show()
    M4.built = true
    Lab.Log("M4", "BUILD done. Keys: SHIFT-1..4 mark rows, SHIFT-F fear mouseover, SHIFT-D fear focus, SHIFT-R focus<-mouseover")
    refresh()
end

-- ===== events =====
local ef = CreateFrame("Frame")
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "RAID_TARGET_UPDATE" }) do pcall(ef.RegisterEvent, ef, ev) end
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_SENT", "player")
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_SUCCEEDED", "player")
pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_FAILED", "player")
ef:SetScript("OnEvent", function(_, ev, a1, a2, a3, a4)
    if ev == "UNIT_SPELLCAST_SENT" then
        local i = M4.intent
        if i and GetTime() - i.t < 3 then
            local ts = Lab.Classify(true, a2)
            local v = (ts == "READABLE" and i.name) and ((a2 == i.name) and "NAME_MATCH" or "NAME_MISMATCH") or "NAME_UNKNOWN"
            if v == "NAME_MISMATCH" then M4.stats.sentMismatch = M4.stats.sentMismatch + 1 end
            Lab.Log("M4", "SENT to=%s intended=%s(%s) -> %s", ts == "READABLE" and a2 or ts, i.token, tostring(i.name), v)
        end
    elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
        if Lab.Classify(true, a3) ~= "READABLE" or not FEAR[a3] then return end
        local i = M4.intent
        if i and GetTime() - i.t < 3 and i.guid then
            local r = rowOfGuid(i.guid)
            if r then
                M4.rows[r].estExpire = GetTime() + M4.dur
                Lab.Log("M4", "EST_FEAR row %d guid=%s est %ds (ESTIMATE, not authoritative)", r, Lab.Short(i.guid), M4.dur)
            else
                Lab.Log("M4", "FEAR landed on unrowed guid=%s (mark it first with SHIFT-1..4)", Lab.Short(i.guid))
            end
            M4.intent = nil
        else
            M4.stats.unattributed = M4.stats.unattributed + 1
            Lab.Log("M4", "FEAR cast UNATTRIBUTED (not via M4 buttons); no timer started")
        end
        refresh()
    elseif ev == "UNIT_SPELLCAST_FAILED" then
        if Lab.Classify(true, a3) == "READABLE" and FEAR[a3] then
            M4.intent = nil
            Lab.Log("M4", "FEAR cast FAILED; no timer started")
        end
    else
        refresh()
    end
end)

C_Timer.NewTicker(0.25, function() if hud and hud:IsShown() then refresh() end end)

Lab.AddCommand("m4build", "M4: OUT OF COMBAT. Build HUD + secure buttons + key bindings (re-run after every /reload)", build)
Lab.AddCommand("m4dur", "M4: set ESTIMATED Fear duration seconds (default 10)", function(a) M4.dur = tonumber(a) or M4.dur Lab.Log("M4", "DUR est=%ds", M4.dur) end)
Lab.AddCommand("m4reset", "M4: clear rows (out of combat)", function()
    if InCombatLockdown() then Lab.Log("M4", "RESET refused: in combat") return end
    for i = 1, NROWS do M4.rows[i] = nil end
    Lab.Log("M4", "RESET rows cleared") refresh()
end)
Lab.AddCommand("m4hide", "M4: hide HUD/panel (out of combat)", function()
    if InCombatLockdown() then return end
    if hud then hud:Hide() end if panel then panel:Hide() end
end)
Lab.AddCommand("m4stats", "M4: counters and current rows", function()
    local s = M4.stats
    Lab.Log("M4", "STATS reassign=%d conflict=%d unattributed=%d sentMismatch=%d", s.reassign, s.conflict, s.unattributed, s.sentMismatch)
    for i = 1, NROWS do
        local r = M4.rows[i]
        Lab.Log("M4", "ROW %d %s", i, r and ("guid=" .. Lab.Short(r.guid) .. " name=" .. tostring(r.name) .. " live=" .. tostring(liveToken(r.guid))) or "empty")
    end
end)
