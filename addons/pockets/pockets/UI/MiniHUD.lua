--[[
    UI/MiniHUD.lua - Pockets' Mini HUD (Mini HUD TDD): one round bag
    portrait, a clockwise capacity ring, and a small used/total badge.

    Composes the generic CircularPortrait + CapacityRing with Pockets data
    (InventoryState:GetGeneralCapacity - the same main-bag count Glance uses,
    specialized bags excluded). It owns no click handling: the Shell root
    frame is the single click/drag target and routes a click to the category
    list. Reads domain state only; values update in place.
]]

local _, Pockets = ...

Pockets.UI.MiniHUD = Pockets.UI.MiniHUD or {}
local MiniHUD = Pockets.UI.MiniHUD
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- "43/46" (no spaces); "0/0" when capacity is unknown. Never divides.
function MiniHUD.FormatCount(used, total)
    if type(total) ~= "number" or total <= 0 then
        return "0/0"
    end
    return string.format("%d/%d", used or 0, total)
end

-- Ring fraction 0..1 from the capacity record; 0 when total == 0.
function MiniHUD.GetFraction(capacity)
    if not capacity or type(capacity.total) ~= "number" or capacity.total <= 0 then
        return 0
    end
    return Pockets.UI.CapacityRing.ClampFraction((capacity.used or 0) / capacity.total)
end

-- r, g, b for the ring: existing Pockets thresholds (green <70%, yellow
-- <90%, red >=90%); muted neutral when there is no capacity.
function MiniHUD.GetColor(capacity)
    if not capacity or type(capacity.total) ~= "number" or capacity.total <= 0 then
        local m = PHUI.Colors.TEXT_MUTED
        return m[1], m[2], m[3]
    end
    local c = Pockets.UI.Layout:GetCapacityColor(MiniHUD.GetFraction(capacity))
    return c.r, c.g, c.b
end

-- r, g, b for the count text: cream while there's room, then the ring's
-- yellow / red as the bags fill (same thresholds as the ring).
function MiniHUD.GetTextColor(capacity)
    local fraction = MiniHUD.GetFraction(capacity)
    if fraction >= Constants.CAPACITY_COLOR_THRESHOLDS.YELLOW_AT then
        return MiniHUD.GetColor(capacity)
    end
    local c = PHUI.Colors.TEXT_PRIMARY
    return c[1], c[2], c[3]
end

--------------------------------------------------
-- Build / Render
--------------------------------------------------

-- parent: the HUD root. Returns the mini frame (TOPLEFT of parent, fixed
-- footprint, mouse-transparent so the root is the one click target).
function MiniHUD:Build(parent)
    local L = Constants.LAYOUT
    local mini = Pockets.UI.CircularPortrait:Create(parent, {
        size = L.MINI_PORTRAIT_SIZE,
        icon = Constants.HUD_ICON,
        iconSize = L.MINI_ICON_SIZE,
        iconTexCoord = { 0, 1, 0, 1 }, -- whole bag, not a zoomed crop
        rimColor = PHUI.Colors.BORDER_BRONZE,
        badge = {
            width = L.MINI_BADGE_WIDTH,
            height = L.MINI_BADGE_HEIGHT,
            overlap = L.MINI_BADGE_OVERLAP,
            font = PHUI.Fonts.MINI_COUNT,
            backdrop = PHUI.Backdrops.ROUNDED_SMALL,
            bgColor = PHUI.Colors.BADGE_BG,
            borderColor = PHUI.Colors.BORDER_BRONZE,
            textColor = PHUI.Colors.TEXT_PRIMARY,
        },
    })
    mini:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

    -- Ring sits just inside the portrait rim, above the portrait art.
    local ring = Pockets.UI.CapacityRing:Create(mini.portrait, {
        diameter = L.MINI_PORTRAIT_SIZE - 2 * L.MINI_RING_INSET,
        thickness = L.MINI_RING_THICKNESS,
    })
    ring:SetPoint("CENTER", mini.portrait, "CENTER", 0, 0)
    ring:SetFrameLevel(mini.portrait:GetFrameLevel() + 10)
    -- Zoned gauge: green up to the yellow threshold, then yellow, then red,
    -- by each segment's own position around the ring.
    ring:SetColorFn(function(fraction)
        local c = Pockets.UI.Layout:GetCapacityColor(fraction)
        return c.r, c.g, c.b
    end)
    mini.ring = ring
    return mini
end

function MiniHUD:Render(mini)
    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    mini.ring:SetFraction(MiniHUD.GetFraction(capacity))
    mini:SetBadgeText(MiniHUD.FormatCount(capacity.used, capacity.total))
    mini.badge.text:SetTextColor(MiniHUD.GetTextColor(capacity))
end
