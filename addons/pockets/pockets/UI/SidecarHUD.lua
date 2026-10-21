--[[
    UI/SidecarHUD.lua - Pockets' Sidecar HUD: the existing Mini with gold
    and ammo (icon + text on a soft dark pill) stacked to its right and the five newest recent items in a
    strip beneath it spanning exactly the same width (no outer frame).

    No labels. The root keeps the Mini footprint, so the Mini never moves;
    badges and strip are children of the root. Gold sits on the Mini midpoint alone,
    stacks above Ammo when present; the strip is content-sized and hidden
    when empty. Nothing
    here uses items - clicks only navigate. Reads domain state only; frames
    are built once.
]]

local _, Pockets = ...

Pockets.UI.SidecarHUD = Pockets.UI.SidecarHUD or {}
local SidecarHUD = Pockets.UI.SidecarHUD
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local L = Constants.LAYOUT

SidecarHUD.STRIP_SPEC = {
    icons = L.SIDECAR_STRIP_ICONS,
    icon = L.SIDECAR_STRIP_ICON,
    gap = L.SIDECAR_STRIP_GAP,
    padX = L.SIDECAR_STRIP_PAD_X,
    height = L.SIDECAR_STRIP_HEIGHT,
    backdrop = nil, -- no outer frame or background; the item borders are the frame
}

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Gold amount (copper) and ammo model (or nil when not applicable): an
-- ammo bag, or any carried ammo (any character can carry ammo, not just
-- ones with a quiver).
function SidecarHUD.BuildModel(gold, specialized, ammoItems)
    local ammoCount = 0
    for _, item in ipairs(ammoItems or {}) do
        ammoCount = ammoCount + (item.quantity or 0)
    end
    local ammo
    for _, cap in ipairs(specialized or {}) do
        if cap.class == "ammo" and (cap.total or 0) > 0 then
            ammo = { kind = "bag", cap = cap, isAmmo = true, ammoCount = ammoCount }
        end
    end
    -- Loose ammo with no quiver: icon + arrow count only.
    if not ammo and ammoCount > 0 then
        ammo = { kind = "ammo", item = ammoItems[1], ammoCount = ammoCount }
    end
    return { gold = gold or 0, ammo = ammo }
end

-- "18m to full" for the Mini's count badge, or nil. Prefers omission to a
-- noisy number: only the FILLING state with enough confidence shows one.
function SidecarHUD.FormatEta(state, confidence, seconds)
    if state ~= Constants.ESTIMATOR_STATE.FILLING or (confidence or 0) < 0.5 or not seconds then
        return nil
    end
    return Pockets.UI.Layout:FormatETA(seconds)
end

-- The newest recent items for the strip (newest first, max 5).
function SidecarHUD.BuildRecent(recent)
    local out = {}
    for i = 1, math.min(#(recent or {}), SidecarHUD.STRIP_SPEC.icons) do
        out[i] = recent[i]
    end
    return out
end

-- Strip width for n icons: side padding + icons + gaps between them.
function SidecarHUD.StripWidth(n, spec)
    spec = spec or SidecarHUD.STRIP_SPEC
    n = math.max(1, math.min(n, spec.icons))
    return 2 * spec.padX + n * spec.icon + (n - 1) * spec.gap
end

-- Compact carried money that keeps its denomination: "45c", "12s",
-- "152g", "12.4kg", "1.2mg".
function SidecarHUD.FormatGold(copper)
    copper = math.floor(tonumber(copper) or 0)
    if copper < 0 then
        copper = 0
    end
    local gold = math.floor(copper / 10000)
    if gold >= 1000000 then
        return string.format("%.1fmg", gold / 1000000)
    elseif gold >= 10000 then
        return string.format("%.1fkg", gold / 1000)
    elseif gold > 0 then
        return string.format("%dg", gold)
    end
    local silver = math.floor(copper / 100)
    if silver > 0 then
        return string.format("%ds", silver)
    end
    return string.format("%dc", copper)
end

-- Stack-style count: "100", "9999", "12k".
function SidecarHUD.FormatCount(n)
    n = math.floor(tonumber(n) or 0)
    if n >= 10000 then
        return string.format("%dk", math.floor(n / 1000))
    end
    return tostring(n)
end

-- Gap between strip icons so five of them span exactly `width` (never less
-- than the minimum gap).
function SidecarHUD.StripGap(width)
    local spec = SidecarHUD.STRIP_SPEC
    return math.max(spec.gap, (width - spec.icons * spec.icon) / (spec.icons - 1))
end

-- Left offset of icon i (of n shown) in a strip `width` wide. Icons keep the
-- five-item slot spacing; align = "left" | "right" | "center".
function SidecarHUD.IconX(i, n, width, align)
    local spec = SidecarHUD.STRIP_SPEC
    local step = spec.icon + SidecarHUD.StripGap(width)
    local used = n * spec.icon + (n - 1) * (step - spec.icon)
    local start = 0
    if align == "right" then
        start = width - used
    elseif align == "center" then
        start = (width - used) / 2
    end
    return start + (i - 1) * step
end

-- Which side of the screen the HUD is on, by thirds of the Mini's centre.
function SidecarHUD.Align(centerX, screenW)
    if centerX < screenW / 3 then
        return "left"
    elseif centerX > screenW * 2 / 3 then
        return "right"
    end
    return "center"
end

-- Badge width: at least the spec width, grown to fit icon + text (no clipping).
function SidecarHUD.BadgeWidth(textWidth)
    return math.max(L.SIDECAR_BADGE_WIDTH,
        2 * L.SIDECAR_BADGE_PAD + L.SIDECAR_BADGE_GAP_ICON + L.SIDECAR_BADGE_ICON + (textWidth or 0))
end

--------------------------------------------------
-- Build / Render
--------------------------------------------------

local function CreateBadge(root, handlers)
    local badge = CreateFrame("Button", nil, root, "BackdropTemplate")
    badge:SetSize(L.SIDECAR_BADGE_WIDTH, L.SIDECAR_BADGE_HEIGHT)
    badge:RegisterForClicks("AnyUp")
    -- Soft dark rounded pill (translucent, faint bronze edge) so the value
    -- stays readable over bright scenery.
    PHUI.ApplyBackdrop(badge, {
        backdrop = PHUI.Backdrops.ROUNDED_SMALL,
        bgColor = PHUI.Colors.BADGE_BG,
        bgAlpha = 0.72,
        borderColor = PHUI.Colors.BORDER_BRONZE,
        borderAlpha = 0.55,
    })
    badge.icon = badge:CreateTexture(nil, "ARTWORK")
    badge.icon:SetSize(L.SIDECAR_BADGE_ICON, L.SIDECAR_BADGE_ICON)
    badge.icon:SetPoint("LEFT", badge, "LEFT", L.SIDECAR_BADGE_PAD, 0)
    badge.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge.text = PHUI.CreateLabel(badge, "primary", nil, PHUI.Fonts.SIDECAR_VALUE)
    badge.text:SetPoint("LEFT", badge.icon, "RIGHT", L.SIDECAR_BADGE_GAP_ICON, 0)
    badge.text:SetJustifyH("LEFT")
    badge:SetScript("OnEnter", function(self)
        if self.onEnter then self.onEnter(self) end
    end)
    badge:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.onLeave then self.onLeave(self) end
    end)
    badge:SetScript("OnClick", function(self)
        if self.handler then self.handler() end
    end)
    badge:RegisterForDrag("LeftButton")
    badge:SetScript("OnDragStart", handlers.dragStart)
    badge:SetScript("OnDragStop", handlers.dragStop)
    badge:Hide()
    return badge
end

-- Sets icon + text; returns the width this badge needs for its text.
local function SetBadge(badge, icon, text)
    badge.icon:SetTexture(icon)
    badge.text:SetText(text)
    return SidecarHUD.BadgeWidth(badge.text:GetStringWidth())
end

-- root: the HUD root (TOPLEFT = Mini's top-left). handlers: { openRecent,
-- openAmmo, dragStart, dragStop }.
function SidecarHUD:Build(root, handlers)
    local sidecar = { root = root, handlers = handlers }
    sidecar.gold = CreateBadge(root, handlers)
    sidecar.ammo = CreateBadge(root, handlers)
    -- Bag-full ETA: a text-only pill beside the Mini's count badge (right of
    -- it, or left when the HUD is on the right of the screen).
    sidecar.eta = CreateBadge(root, handlers)
    sidecar.eta:SetHeight(L.SIDECAR_BADGE_HEIGHT - 2)
    sidecar.eta.icon:Hide()
    sidecar.eta.text:ClearAllPoints()
    sidecar.eta.text:SetPoint("CENTER", sidecar.eta, "CENTER", 0, 0)
    PHUI.ApplyTextStyle(sidecar.eta.text, "muted")
    -- The recent strip is the same real-item-button strip Glance uses
    -- (UI/RecentItemStrip.lua): right-click uses the item, tooltips, drag and
    -- the big preview all work. Icons are placed by SidecarHUD:Layout.
    local spec = SidecarHUD.STRIP_SPEC
    sidecar.strip = Pockets.UI.RecentItemStrip:Create(root, {
        width = SidecarHUD.StripWidth(spec.icons, spec),
        iconSize = spec.icon,
        gap = spec.gap,
    })
    sidecar.strip:Hide()
    return sidecar
end

-- The Mini plus the gold/ammo column form one container; the recent strip
-- spans exactly that width (shared left and right boundaries). Gold/ammo sit
-- 4px right of the Mini (left of it when the HUD is on the right of the
-- screen, mirroring the whole container); the strip is 4px beneath the Mini.
-- Icons are left-aligned on the left of the screen, right-aligned on the
-- right, centred otherwise. Near the bottom edge the strip moves above the
-- Mini. The Mini never moves.
function SidecarHUD:Layout(sidecar)
    local root = sidecar.root
    local left, top = root:GetLeft(), root:GetTop()
    local screenW = UIParent:GetWidth()
    local sideW = sidecar.sideW or L.SIDECAR_BADGE_WIDTH
    local containerW = L.MINI_WIDTH + L.SIDECAR_MINI_GAP + sideW
    local align, flip, stripAbove = "left", false, false
    if left and top then
        align = SidecarHUD.Align(left + L.MINI_WIDTH / 2, screenW)
        flip = align == "right" or left + containerW > screenW
        if flip and left + L.MINI_WIDTH - containerW < 0 then
            flip = false -- no room on the left either
        end
        stripAbove = top - L.MINI_HEIGHT - L.SIDECAR_STRIP_BELOW - L.SIDECAR_STRIP_HEIGHT < 0
    end

    -- Badge column, vertically centred on the Mini portrait: gold + ammo as
    -- a pair, or gold alone on the portrait's midpoint.
    local column = 2 * L.SIDECAR_BADGE_HEIGHT + L.SIDECAR_BADGE_GAP
    local columnTop = -(L.MINI_PORTRAIT_SIZE - column) / 2
    local function place(badge, y)
        badge:SetWidth(sideW)
        badge:ClearAllPoints()
        if flip then
            badge:SetPoint("TOPRIGHT", root, "TOPLEFT", -L.SIDECAR_MINI_GAP, y)
        else
            badge:SetPoint("TOPLEFT", root, "TOPLEFT", L.MINI_WIDTH + L.SIDECAR_MINI_GAP, y)
        end
    end
    if sidecar.ammo:IsShown() then
        place(sidecar.gold, columnTop)
        place(sidecar.ammo, columnTop - L.SIDECAR_BADGE_HEIGHT - L.SIDECAR_BADGE_GAP)
    else
        place(sidecar.gold, -(L.MINI_PORTRAIT_SIZE - L.SIDECAR_BADGE_HEIGHT) / 2)
        place(sidecar.ammo, columnTop - L.SIDECAR_BADGE_HEIGHT - L.SIDECAR_BADGE_GAP)
    end

    -- ETA pill: vertically centred on the Mini's count badge, same side as
    -- the other badges.
    local eta = sidecar.eta
    local etaCentre = L.MINI_HEIGHT - L.MINI_BADGE_HEIGHT / 2
    local etaTop = -(etaCentre - eta:GetHeight() / 2)
    eta:ClearAllPoints()
    if flip then
        eta:SetPoint("TOPRIGHT", root, "TOPLEFT", -L.SIDECAR_MINI_GAP, etaTop)
    else
        eta:SetPoint("TOPLEFT", root, "TOPLEFT", L.MINI_WIDTH + L.SIDECAR_MINI_GAP, etaTop)
    end

    local strip = sidecar.strip
    strip:SetWidth(containerW)
    strip._width = containerW
    strip:ClearAllPoints()
    local side = flip and "RIGHT" or "LEFT"
    if stripAbove then
        strip:SetPoint("BOTTOM" .. side, root, "TOP" .. side, 0, L.SIDECAR_STRIP_BELOW)
    else
        strip:SetPoint("TOP" .. side, root, "BOTTOM" .. side, 0, -L.SIDECAR_STRIP_BELOW)
    end
    strip.positionFor = function(i, shown)
        return SidecarHUD.IconX(i, shown, containerW, align)
    end
    local shown = strip:SetItems(sidecar.recent or {})
    strip:SetShown(shown > 0)
end

-- layout: pass false in combat (anchors are left untouched).
function SidecarHUD:Render(sidecar, layout)
    local InventoryState = Pockets.Services.InventoryState
    local model = SidecarHUD.BuildModel(
        Pockets.Adapters.MoneyAPI:GetMoney(),
        InventoryState:GetSpecializedCapacities(),
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.AMMO))
    local recent = SidecarHUD.BuildRecent(
        Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.RECENT))
    Pockets.UI.ItemPreview:Hide()
    sidecar.model = model

    local gold = sidecar.gold
    local sideW = SetBadge(gold, Pockets.UI.MoneyFormat:CoinIcon(model.gold), SidecarHUD.FormatGold(model.gold))
    local money = Pockets.UI.MoneyFormat:Format(model.gold)
    gold.onEnter = function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(money)
        GameTooltip:Show()
    end
    gold:Show()

    local ammo = sidecar.ammo
    if model.ammo then
        local m = model.ammo
        local icon = m.kind == "ammo" and m.item.texture or m.cap.texture
        sideW = math.max(sideW, SetBadge(ammo, icon, SidecarHUD.FormatCount(m.ammoCount or 0)))
        ammo.onEnter = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Ammo: " .. (m.ammoCount or 0))
            GameTooltip:Show()
        end
        ammo.handler = sidecar.handlers.openAmmo
        ammo:Show()
    else
        ammo:Hide()
    end

    sidecar.sideW = sideW

    local estimator = Pockets.Services.CapacityEstimator
    local etaText = SidecarHUD.FormatEta(estimator:GetState(), estimator:GetConfidence(), estimator:GetETA())
    local eta = sidecar.eta
    if etaText then
        eta.text:SetText(etaText)
        eta:SetWidth(2 * L.SIDECAR_BADGE_PAD + eta.text:GetStringWidth())
        eta:Show()
    else
        eta:Hide()
    end
    -- The strip's real item buttons are protected in combat: they are only
    -- re-laid-out (in Layout) out of combat.
    sidecar.recent = recent

    if layout ~= false then
        self:Layout(sidecar)
    end
end

function SidecarHUD:SetShown(sidecar, shown)
    if not shown then
        sidecar.gold:Hide()
        sidecar.ammo:Hide()
        sidecar.eta:Hide()
        sidecar.strip:Hide()
    end
end
