--[[
    UI/HUD.lua - Combat Minimal enemy list (TDD.md). One row per tracked GUID:
    raid marker outside left, portrait, DoT/curse icons, Fear icon pinned right, name underneath.
    Reads Tracker state only; non-secure, so it updates freely in combat.
]]

local _, HMF = ...

local HUD = {}
HMF.UI.HUD = HUD

local C = HMF.Constants
local K = C.HUD
local Tracker = HMF.Services.Tracker
local Focus = HMF.Services.Focus
local Unit = HMF.Adapters.Unit
local Forever = HMF.Adapters.Forever

-- Forever: enemy auras are unreadable, so Blizzard's aura engine draws the real timers into
-- slots over each icon (see Adapters/ForeverAPI.lua). Elsewhere the HUD draws from tracker state.
local useEngine = Unit.IsForever() and Forever.EngineAvailable()

local frame, handle, dragBG
local rows = {}
local ticker
local locked = true
local width = K.ROW_WIDTH

local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local TEXCOORD = { 0.07, 0.93, 0.07, 0.93 }
local MAX_ICONS = #C.TRACKED_DEBUFFS

local BACKDROP = {
    bgFile = WHITE,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}
local ICON_BACKDROP = { edgeFile = WHITE, edgeSize = 1 }

local BORDER = {
    normal   = { 0.62, 0.35, 0.9 },
    recast   = { 1, 0.7, 0.1 },
    critical = { 1, 0.15, 0.15 },
    broken   = { 1, 0.15, 0.15 },
    expired  = { 0.3, 0.3, 0.3 },
}

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    HoldMyFearDB.hud = HoldMyFearDB.hud or {}
    HoldMyFearDB.hud.point, HoldMyFearDB.hud.relPoint = point, relPoint
    HoldMyFearDB.hud.x, HoldMyFearDB.hud.y = x, y
end

local function ClampWidth(v)
    return math.max(K.WIDTH_MIN, math.min(K.WIDTH_MAX, tonumber(v) or K.ROW_WIDTH))
end

-- Layout geometry -----------------------------------------------------------

local function IconsLeft() return K.PAD + K.PORTRAIT + K.ICON_GAP end
local function IconY() return -(K.PAD + (K.PORTRAIT - K.ICON) / 2) end
local function FearLeft() return width - K.PAD - K.ICON end

-- How many spell icons fit between portrait and Fear.
local function Capacity()
    local avail = FearLeft() - K.ICON_GAP - IconsLeft()
    return math.max(1, math.floor((avail + K.ICON_GAP) / (K.ICON + K.ICON_GAP)))
end

-- Spell icon with horizontal desaturation depletion ------------------------

local function CreateSpellIcon(row)
    local f = CreateFrame("Frame", nil, row, "BackdropTemplate")
    f:SetSize(K.ICON, K.ICON)
    f:SetBackdrop(ICON_BACKDROP)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    -- Grey base shows the whole icon; the coloured layer is clipped from the left as time runs out.
    f.base = f:CreateTexture(nil, "ARTWORK", nil, 0)
    f.base:SetPoint("TOPLEFT", 1, -1)
    f.base:SetPoint("BOTTOMRIGHT", -1, 1)
    f.base:SetTexCoord(unpack(TEXCOORD))
    f.base:SetDesaturated(true)
    f.base:SetVertexColor(0.3, 0.3, 0.3)
    f.color = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.color:SetPoint("TOPLEFT", 1, -1)
    f.color:SetPoint("BOTTOMLEFT", 1, 1)
    -- Bright edge marks the depletion boundary so remaining time reads at a glance.
    f.edge = f:CreateTexture(nil, "OVERLAY")
    f.edge:SetColorTexture(1, 1, 1, 0.9)
    f.edge:SetWidth(1)
    f.edge:SetPoint("TOP", f.color, "TOPRIGHT", 0, 0)
    f.edge:SetPoint("BOTTOM", f.color, "BOTTOMRIGHT", 0, 0)
    f:Hide()
    return f
end

local function SetFill(f, frac)
    f.base:SetAlpha(frac < 0 and 0.45 or 1)
    if frac < 0 then -- placeholder: spell known, not cast yet
        f.color:Hide() f.edge:Hide()
        f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
        return
    end
    if frac <= 0 then
        f.color:Hide() f.edge:Hide()
        f:SetBackdropBorderColor(0.9, 0.15, 0.15, 1) -- expired: red frame, dark icon
        return
    end
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f.edge:SetShown(frac < 1)
    local w = (K.ICON - 2) * frac
    f.color:SetWidth(math.max(w, 0.01))
    local l, r, t, b = unpack(TEXCOORD)
    f.color:SetTexCoord(l, l + (r - l) * frac, t, b)
    f.color:Show()
end

local function CreateFear(row)
    local f = CreateFrame("Frame", nil, row, "BackdropTemplate")
    f:SetSize(K.ICON, K.ICON)
    f:SetPoint("TOPRIGHT", row, "TOPRIGHT", -K.PAD, IconY())
    f:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    f.icon:SetTexCoord(unpack(TEXCOORD))
    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(K.ICON * 1.8, K.ICON * 1.8)
    f.glow:SetPoint("CENTER")
    f.glow:SetVertexColor(1, 0.7, 0.1)
    f.glow:SetAlpha(0)
    f.chain = f:CreateTexture(nil, "OVERLAY")
    f.chain:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    f.chain:SetAllPoints(f.icon)
    f.chain:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    f.text:SetPoint("CENTER", 0, 0)
    -- Where the engine draws the real Fear bar and seconds, inside the coloured border.
    f.engine = CreateFrame("Frame", nil, f)
    f.engine:SetPoint("TOPLEFT", 1, -1)
    f.engine:SetPoint("BOTTOMRIGHT", -1, 1)
    return f
end

local function CreateRow(i)
    local row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    row:SetSize(width, K.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * (K.ROW_HEIGHT + K.ROW_GAP))
    row:SetBackdrop(BACKDROP)
    row:SetBackdropColor(0.04, 0.04, 0.05, 0.8)
    row:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    row.marker = row:CreateTexture(nil, "OVERLAY")
    row.marker:SetSize(K.MARKER, K.MARKER)
    row.marker:SetPoint("RIGHT", row, "LEFT", -4, 0)

    row.arrow = row:CreateTexture(nil, "OVERLAY")
    row.arrow:SetSize(K.ARROW, K.ARROW)
    row.arrow:SetPoint("LEFT", row, "RIGHT", 4, 0)
    row.arrow:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")
    row.arrow:Hide()

    row.portrait = row:CreateTexture(nil, "ARTWORK")
    row.portrait:SetSize(K.PORTRAIT, K.PORTRAIT)
    row.portrait:SetPoint("TOPLEFT", K.PAD, -K.PAD)

    -- One frame per tracked spell, moved into the next free slot by UpdateIcons.
    row.icons = {}
    for _, name in ipairs(C.TRACKED_DEBUFFS) do row.icons[name] = CreateSpellIcon(row) end

    row.more = row:CreateFontString(nil, "OVERLAY")
    row.more:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    row.more:SetTextColor(0.85, 0.85, 0.85)
    row.more:Hide()

    row.fear = CreateFear(row)

    if useEngine then
        row.container = Forever.NewContainer(row)
        if row.container then
            Forever.AddSlot(row.container, C.FEAR_SPELL, row.fear.engine, { text = true })
            for _, name in ipairs(C.TRACKED_DEBUFFS) do Forever.AddSlot(row.container, name, row.icons[name]) end
        end
    end

    -- Mob health (WTF's approach): a StatusBar fed straight from UnitHealth/UnitHealthMax, which
    -- accepts Forever's secret values. Name, % and focus tag sit on a layer above the bar.
    row.health = CreateFrame("StatusBar", nil, row)
    row.health:SetPoint("TOPLEFT", row, "TOPLEFT", K.PAD, -(K.PAD + K.PORTRAIT + 2))
    row.health:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -K.PAD, K.PAD - 1)
    row.health:SetStatusBarTexture(WHITE)
    row.health:SetStatusBarColor(0.6, 0.12, 0.12, 0.75)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    row.health.bg = row.health:CreateTexture(nil, "BACKGROUND")
    row.health.bg:SetAllPoints()
    row.health.bg:SetColorTexture(0, 0, 0, 0.35)
    row.health:Hide()

    -- DoT damage still to come: fills back from the health bar's current edge, full when it kills.
    -- Its max is the mob's current health, which may be secret; a StatusBar takes that as is.
    row.dmgbar = CreateFrame("StatusBar", nil, row)
    row.dmgbar:SetPoint("TOPLEFT", row.health, "TOPLEFT")
    row.dmgbar:SetPoint("BOTTOMRIGHT", row.health:GetStatusBarTexture(), "BOTTOMRIGHT")
    row.dmgbar:SetFrameLevel(row.health:GetFrameLevel() + 1)
    row.dmgbar:SetStatusBarTexture(WHITE)
    row.dmgbar:SetStatusBarColor(0.55, 0.25, 0.85, 0.9)
    if row.dmgbar.SetReverseFill then row.dmgbar:SetReverseFill(true) end
    row.dmgbar:SetMinMaxValues(0, 1)
    row.dmgbar:Hide()

    row.layer = CreateFrame("Frame", nil, row)
    row.layer:SetAllPoints(row)
    row.layer:SetFrameLevel(row.health:GetFrameLevel() + 2)

    row.name = row.layer:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(STANDARD_TEXT_FONT, K.NAME_SIZE, "OUTLINE")
    row.name:SetTextColor(0.95, 0.95, 0.95)
    row.name:SetPoint("LEFT", row.health, "LEFT", 40, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetWidth(width - 2 * K.PAD - K.FOCUS_TAG_W - 36)

    row.pct = row.layer:CreateFontString(nil, "OVERLAY")
    row.pct:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.pct:SetPoint("RIGHT", row.health, "RIGHT", -4, 0)
    row.pct:SetWidth(K.PCT_W)
    row.pct:SetJustifyH("RIGHT")

    row.dmg = row.layer:CreateFontString(nil, "OVERLAY")
    row.dmg:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    row.dmg:SetTextColor(0.85, 0.6, 1)
    row.dmg:SetPoint("RIGHT", row.pct, "LEFT", -4, 0)
    row.dmg:SetWidth(K.DMG_W)
    row.dmg:SetJustifyH("RIGHT")

    -- Secret-safe "DIES": a clip frame that follows the purple fill; the text sits at the bar's far
    -- left, so it shows only when the fill (damage / current health) reaches all the way across.
    row.diesClip = CreateFrame("Frame", nil, row)
    row.diesClip:SetPoint("TOPLEFT", row.dmgbar:GetStatusBarTexture(), "TOPLEFT")
    row.diesClip:SetPoint("BOTTOMRIGHT", row.dmgbar:GetStatusBarTexture(), "BOTTOMRIGHT")
    row.diesClip:SetFrameLevel(row.dmgbar:GetFrameLevel() + 3)
    if row.diesClip.SetClipsChildren then row.diesClip:SetClipsChildren(true) end
    row.diesClip:Hide()
    row.diesFull = row.diesClip:CreateFontString(nil, "OVERLAY")
    row.diesFull:SetFont(STANDARD_TEXT_FONT, 12, "THICKOUTLINE")
    row.diesFull:SetTextColor(0.2, 1, 0.2)
    row.diesFull:SetText("DIES")
    row.diesFull:SetPoint("LEFT", row.health, "LEFT", 4, 0)

    row.dies = row.layer:CreateFontString(nil, "OVERLAY")
    row.dies:SetFont(STANDARD_TEXT_FONT, 12, "THICKOUTLINE")
    row.dies:SetTextColor(1, 0.1, 0.1)
    row.dies:SetText("DIES")
    row.dies:SetPoint("RIGHT", row.dmg, "LEFT", -4, 0)
    row.dies:Hide()

    row.focusTag = row.layer:CreateFontString(nil, "OVERLAY")
    row.focusTag:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    row.focusTag:SetPoint("RIGHT", row.health, "RIGHT", -(4 + K.PCT_W + 4 + K.DMG_W + 4 + 34), 0)
    row.focusTag:SetJustifyH("RIGHT")

    row:Hide()
    return row
end

-- Updates -------------------------------------------------------------------

local function UpdatePortrait(row, entry)
    local token = HMF.Adapters.Unit.TokenFor(entry.guid)
    if token then
        HMF.Adapters.Unit.SetPortrait(row.portrait, token)
        row.portrait:SetTexCoord(0, 1, 0, 1)
        row.hasPortrait = entry.guid
    elseif row.hasPortrait ~= entry.guid then
        row.portrait:SetTexture(QUESTION)
        row.portrait:SetTexCoord(unpack(TEXCOORD))
    end
end

local function FearState(entry, left, cast)
    if left then
        if left <= cast then return "critical" end
        if left <= cast + K.FEAR_BUFFER then return "recast" end
        return "normal"
    end
    return entry.fearBroken and "broken" or "expired"
end

local function UpdateFear(row, entry, t)
    local f = row.fear
    local left = Tracker.FearRemaining(entry, t)
    local cast = HMF.Adapters.Unit.FearCastTime() or K.DEFAULT_CAST
    local state = FearState(entry, left, cast)

    if f.state ~= state then
        if state == "recast" then f.glowUntil = t + 1 end
        f.state = state
        local c = BORDER[state]
        f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        local gray = state == "expired" or state == "broken"
        f.icon:SetDesaturated(state == "expired")
        f.chain:SetShown(state == "broken")
        if gray then f.icon:SetVertexColor(0.45, 0.45, 0.45) else f.icon:SetVertexColor(0.5, 0.5, 0.5) end
        if state == "critical" then f.text:SetTextColor(1, 0.25, 0.25) else f.text:SetTextColor(1, 1, 1) end
        if not left then f.text:SetText("") f.shown = nil end
    end

    if left then
        local secs = math.ceil(left)
        if f.shown ~= secs then
            f.text:SetText(secs)
            f.shown = secs
        end
    end

    local glow = 0
    if f.glowUntil and t < f.glowUntil then glow = (f.glowUntil - t) end
    if f.glowShown ~= glow then f.glow:SetAlpha(glow) f.glowShown = glow end
end

-- Points toward the enemy relative to where the player now faces; dims when the nameplate is gone.
local function UpdateArrow(row, entry, t)
    local facing = HMF.Adapters.Unit.Facing()
    if not entry.bearing or not facing then row.arrow:Hide() return end
    local rot = entry.bearing - facing
    if not row.arrowRot or math.abs(rot - row.arrowRot) > 0.02 then
        row.arrow:SetRotation(rot)
        row.arrowRot = rot
    end
    local alpha = (t - entry.bearingAt) <= K.ARROW_STALE and 1 or 0.4
    if row.arrowAlpha ~= alpha then row.arrow:SetAlpha(alpha) row.arrowAlpha = alpha end
    row.arrow:Show()
end

-- Focus tag text removed: the row's focus state is still tracked, nothing is drawn on the bar.
local function UpdateFocus(row, entry)
    row.focusTag:SetText("")
end

local function UpdateIcons(row, entry, t)
    local list = Tracker.AllDebuffs(entry, t)
    local cap = Capacity()
    -- Dim placeholders for known DoTs not cast yet; real debuffs win the space.
    local have = {}
    for _, d in ipairs(list) do have[d.name] = true end
    local fill = {}
    for _, name in ipairs(C.PLACEHOLDER_DOTS) do
        if not have[name] and Unit.Knows(name) then fill[#fill + 1] = name end
    end
    -- Known DoTs always get their fixed slot (the click buttons sit there), whatever the width.
    local extra = {}
    for i = 1, #fill do
        extra[fill[i]] = true
    end
    for name in pairs(extra) do
        local id = C.SPELL_IDS[name] and C.SPELL_IDS[name][1]
        list[#list + 1] = { name = name, placeholder = true, expired = false,
            icon = (id and Forever.IconFor(id)) or Unit.SpellIcon(name) }
    end
    table.sort(list, function(a, b) return C.DEBUFF_INDEX[a.name] < C.DEBUFF_INDEX[b.name] end)
    local shown = #list
    local overflow = 0
    if shown > cap then
        shown = cap - 1
        overflow = #list - shown
    end

    -- Each spell keeps its own frame (the engine slot sits on it); frames move into position order.
    local sig = {}
    for i = 1, shown do sig[i] = list[i].name end
    sig = table.concat(sig, ",")
    if row.iconSig ~= sig or row.iconWidth ~= width then
        row.iconSig, row.iconWidth = sig, width
        for i = 1, shown do
            local icon = row.icons[list[i].name]
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", row, "TOPLEFT", IconsLeft() + (i - 1) * (K.ICON + K.ICON_GAP), IconY())
        end
        row.more:ClearAllPoints()
        row.more:SetPoint("LEFT", row, "TOPLEFT", IconsLeft() + shown * (K.ICON + K.ICON_GAP), IconY() - K.ICON / 2)
    end

    local visible = {}
    for i = 1, shown do
        local d = list[i]
        local icon = row.icons[d.name]
        visible[d.name] = true
        local tex = d.icon or QUESTION
        if icon.tex ~= tex then
            icon.base:SetTexture(tex)
            icon.color:SetTexture(tex)
            icon.tex = tex
        end
        local frac
        if d.placeholder then frac = -1
        elseif d.expired then frac = 0
        elseif d.left and d.duration and d.duration > 0 then frac = math.min(1, d.left / d.duration)
        else frac = 1 end
        if icon.frac ~= frac then
            icon.frac = frac
            SetFill(icon, frac)
        end
        icon:Show()
    end
    for name, icon in pairs(row.icons) do
        if not visible[name] then icon:Hide() end
    end

    if overflow > 0 then
        row.more:SetText("+" .. overflow)
        row.more:Show()
    else
        row.more:Hide()
    end
end

-- Sum of the DoTs' remaining damage, a purple block on the health bar, and "DIES" when the numbers
-- say it kills. Mob health is secret in combat: the block still draws (StatusBar takes secrets);
-- "DIES" needs a readable health, or a cached max health times a readable percent.
local function UpdateDamage(row, entry, cur, hp)
    local dmg = Tracker.PredictedDamage(entry, GetTime())
    if dmg < 1 then
        row.dmgbar:Hide() row.diesClip:Hide() row.dmg:SetText("") row.dies:Hide()
        return
    end
    -- Verdict when health is known: DIES (green) or LIVES (red) replaces the raw number.
    if hp ~= nil and hp > 0 then
        row.dmg:SetText("")
        if dmg >= hp then
            row.dies:SetText("DIES") row.dies:SetTextColor(0.2, 1, 0.2)
        else
            row.dies:SetText("LIVES") row.dies:SetTextColor(1, 0.3, 0.3)
        end
        row.dies:Show()
    else
        row.dmg:SetText("") -- health is secret: the purple fill (and DIES when it spans the bar) is the answer
        row.dies:Hide()
    end
    if cur and row.health:IsShown() and not (type(cur) == "number" and not Unit.IsSecret(cur) and cur <= 0) then
        row.dmgbar:SetMinMaxValues(0, cur)
        row.dmgbar:SetValue(dmg)
        row.dmgbar:Show()
        row.diesClip:SetShown(hp == nil)
    else
        row.dmgbar:Hide()
        row.diesClip:Hide()
    end
end

-- Health bar and %: live where a unit token shows the mob; otherwise the last value stays, dimmed.
local function UpdateHealth(row, entry)
    local bar = row.health
    local token = Unit.TokenFor(entry.guid, true)
    local cur, max
    if token then cur, max = Unit.Health(token) end
    -- Numeric health, when the game lets us know it: the value itself, else cached max x percent.
    local hp
    if row.healthGUID ~= entry.guid then row.maxHealth = nil end -- a reused row must not keep another mob's max
    if cur then
        bar:SetMinMaxValues(0, max)
        bar:SetValue(cur)
        bar:SetAlpha(1)
        bar:Show()
        row.pct:SetText(Unit.HealthPercentText(token))
        row.healthGUID = entry.guid
        if type(max) == "number" and not Unit.IsSecret(max) and max > 0 then row.maxHealth = max end
        if type(cur) == "number" and not Unit.IsSecret(cur) then
            hp = cur
        else
            local pct = Unit.HealthPercentValue(token)
            if pct and row.maxHealth and row.healthGUID == entry.guid then hp = row.maxHealth * pct / 100 end
        end
    elseif row.healthGUID == entry.guid then
        bar:SetAlpha(0.4)
        row.pct:SetText("")
    else
        bar:Hide()
        row.pct:SetText("")
    end
    UpdateDamage(row, entry, cur, hp)
end

local function UpdateRow(row, entry)
    local t = GetTime()
    row.marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.marker)
    row.name:SetText(entry.name or "Unknown")
    row.fear.icon:SetTexture(HMF.Adapters.Unit.FearIcon() or "Interface\\Icons\\Spell_Shadow_Possession")
    UpdatePortrait(row, entry)
    UpdateFear(row, entry, t)
    UpdateIcons(row, entry, t)
    UpdateArrow(row, entry, t)
    UpdateFocus(row, entry)
    UpdateHealth(row, entry)
end

-- Keep each row's aura container bound to a unit token that shows its mob (never mouseover, which
-- moves with the pointer). No token: released, and the estimate under the slot shows instead.
local function BindRows()
    if not useEngine or not frame then return end
    local list = Tracker.List()
    for i, row in ipairs(rows) do
        if row.container then
            local entry = list[i]
            local token = entry and Unit.TokenFor(entry.guid, true) or nil
            local key = (entry and entry.guid or "") .. "|" .. (token or "")
            if row.boundKey ~= key then
                row.boundKey = key
                row.boundAt = GetTime()
                Forever.Bind(row.container, token)
            end
        end
    end
end

-- Where a unit shows the mob, ask the engine whether each of our spells' bars is up and let that
-- correct the estimates (aura gone early, or still up past the estimate).
local function Reconcile()
    local t = GetTime()
    local list = Tracker.List()
    local todo = {}
    for i, row in ipairs(rows) do
        local entry = list[i]
        if entry and row.container and row.boundAt and row.boundKey:find("|.") and t - row.boundAt > 1 then
            if entry.fear then todo[#todo + 1] = { entry.guid, C.FEAR_SPELL, Forever.SlotShown(row.container, C.FEAR_SPELL) } end
            for spell in pairs(entry.debuffs or {}) do
                todo[#todo + 1] = { entry.guid, spell, Forever.SlotShown(row.container, spell) }
            end
        end
    end
    for _, job in ipairs(todo) do HMF.Services.Casts.Reconcile(job[1], job[2], job[3]) end
end

-- Spellbook or cast IDs changed: let every slot accept them.
function HUD.RefreshFilters()
    if not useEngine then return end
    Unit.InvalidateKnown()
    Forever.ScanSpellbook()
    for _, row in ipairs(rows) do
        if row.container then Forever.RefreshFilters(row.container) end
    end
end

-- Focus or target changed: re-evaluate every row's focus tag and click blocker at once (in combat too).
function HUD.UpdateFocusRows()
    if not frame then return end
    Focus.Evaluate(GetTime())
    local list = Tracker.List()
    for i, entry in ipairs(list) do
        if rows[i] then UpdateFocus(rows[i], entry) end
    end
    HMF.UI.CastButtons.UpdateBlockers(list)
end

-- Left edge and top offset of icon slot i (the click buttons are placed on these).
function HUD.SlotX(i) return IconsLeft() + (i - 1) * (K.ICON + K.ICON_GAP) end
function HUD.SlotY() return IconY() end

-- Target, focus or a nameplate changed: relearn plates, then rebind.
function HUD.Rebind()
    if not useEngine then return end
    Unit.LearnPlates()
    BindRows()
    if Forever.idsChanged then
        Forever.idsChanged = false
        HUD.RefreshFilters()
    end
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

local tickCount = 0

local function Tick()
    local t = GetTime()
    Focus.Evaluate(t)
    tickCount = tickCount + 1
    if useEngine and tickCount % 10 == 0 then
        HUD.Rebind() -- a plate's GUID may become readable
    end
    if useEngine and tickCount % 3 == 0 then Reconcile() end
    for i, entry in ipairs(Tracker.List()) do
        local row = rows[i]
        if row then
            UpdateFear(row, entry, t)
            UpdateIcons(row, entry, t)
            UpdateArrow(row, entry, t)
            UpdateFocus(row, entry)
            if tickCount % 2 == 0 then UpdateHealth(row, entry) end
        end
    end
    HMF.UI.CastButtons.UpdateBlockers(Tracker.List())
end

function HUD.Refresh()
    if not frame then return end
    local list = Tracker.List()
    for i = 1, #C.MARKER_ORDER do
        local row, entry = rows[i], list[i]
        if entry then
            UpdateRow(row, entry)
            row:Show()
        else
            row:Hide()
        end
    end
    BindRows()
    HMF.UI.CastButtons.UpdateBlockers(list)
    -- The frame itself never resizes, shows or hides here: the secure click layer is attached to it,
    -- which makes it protected in combat. Only the rows come and go.
    local n = #list
    if n > 0 and not ticker then
        ticker = C_Timer.NewTicker(K.TICK, Tick)
    elseif n == 0 then
        StopTicker()
    end
end

function HUD.SetLocked(value)
    locked = value
    HoldMyFearDB.hud = HoldMyFearDB.hud or {}
    HoldMyFearDB.hud.locked = value
    if frame then
        frame:EnableMouse(not value)
        handle:SetShown(not value)
        dragBG:SetShown(not value)
        HUD.Refresh()
    end
end

function HUD.SetScale(value)
    value = math.max(K.SCALE_MIN, math.min(K.SCALE_MAX, tonumber(value) or 1))
    HoldMyFearDB.hud = HoldMyFearDB.hud or {}
    HoldMyFearDB.hud.scale = value
    if frame and not InCombatLockdown() then frame:SetScale(value) end
    return value
end

function HUD.SetWidth(value)
    if InCombatLockdown() then return width end -- the frame carries the secure click layer
    width = ClampWidth(value)
    HoldMyFearDB.hud = HoldMyFearDB.hud or {}
    HoldMyFearDB.hud.width = width
    if frame then
        for _, row in ipairs(rows) do
            row:SetWidth(width)
            row.name:SetWidth(width - 2 * K.PAD - K.FOCUS_TAG_W - 36)
        end
        frame:SetWidth(width)
        HUD.Refresh()
    end
    return width
end

function HUD.ResetPosition()
    if InCombatLockdown() then return end
    HoldMyFearDB.hud = { locked = locked, width = width, scale = frame:GetScale() }
    frame:ClearAllPoints()
    frame:SetPoint(K.DEFAULT_POINT[1], UIParent, K.DEFAULT_POINT[2], K.DEFAULT_POINT[3], K.DEFAULT_POINT[4])
end

function HUD.Init()
    HoldMyFearDB.hud = HoldMyFearDB.hud or {}
    local saved = HoldMyFearDB.hud
    locked = saved.locked ~= false
    width = ClampWidth(saved.width)

    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(width, #C.MARKER_ORDER * (K.ROW_HEIGHT + K.ROW_GAP)) -- fixed: see CastButtons.lua
    frame:SetFrameStrata("MEDIUM")
    frame:SetScale(math.max(K.SCALE_MIN, math.min(K.SCALE_MAX, tonumber(saved.scale) or 1)))
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if saved.point then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint(K.DEFAULT_POINT[1], UIParent, K.DEFAULT_POINT[2], K.DEFAULT_POINT[3], K.DEFAULT_POINT[4])
    end

    dragBG = frame:CreateTexture(nil, "BACKGROUND")
    dragBG:SetAllPoints()
    dragBG:SetColorTexture(0.2, 0.8, 0.3, 0.35)

    handle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    handle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    handle:SetText("Drag to move\n/hmf lock when done")

    for i = 1, #C.MARKER_ORDER do rows[i] = CreateRow(i) end

    HMF.UI.CastButtons.Build(frame, #rows, HUD.SlotX, HUD.SlotY)
    Tracker.Subscribe(function() HUD.Refresh() end)
    HUD.SetLocked(locked)
end
