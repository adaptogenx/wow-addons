--[[
    UI/Layout.lua - Pockets-specific layout logic (TDD §13.5, UI_RULES.md)

    Fixed pixel geometry (widths/heights/columns) lives in
    Constants.LAYOUT so it has exactly one source of truth across Shell's
    Glance/Menu/Category/All states (UI_SPEC §4, §7, §16). Generic theme
    primitives (fonts, colors, backdrops) live in the
    shared Shared/PHUI.lua library instead - this module holds only
    Pockets-domain layout logic (currently: capacity-color mapping).
]]

local _, Pockets = ...

Pockets.UI.Layout = Pockets.UI.Layout or {}
local Layout = Pockets.UI.Layout
local PHUI = Pockets.UI.PHUI

Layout.PADDING = 8

-- "13m to full" (or "<1m to full"). No "~" prefix - fake precision is
-- worse than the plain number (.plans/Pockets_Glance_UI.md §9). Returns
-- nil when there's no ETA to show; callers decide what "no ETA" means.
function Layout:FormatETA(seconds)
    if not seconds then
        return nil
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then
        return "<1m to full"
    end
    return string.format("%dm to full", minutes)
end

-- " · 13m to full" - leading separator included so callers can just
-- append this straight after a capacity string (Shell's footer).
function Layout:FormatETASuffix(seconds)
    local eta = self:FormatETA(seconds)
    if not eta then
        return ""
    end
    return " \194\183 " .. eta
end

function Layout:GetCapacityColor(utilization)
    local thresholds = Pockets.Constants.CAPACITY_COLOR_THRESHOLDS
    local colors = PHUI.Colors

    if utilization >= thresholds.RED_AT then
        return { r = colors.ACCENT_BAD[1], g = colors.ACCENT_BAD[2], b = colors.ACCENT_BAD[3] }
    elseif utilization >= thresholds.YELLOW_AT then
        return { r = colors.ACCENT_WARNING[1], g = colors.ACCENT_WARNING[2], b = colors.ACCENT_WARNING[3] }
    end
    return { r = colors.ACCENT_GOOD[1], g = colors.ACCENT_GOOD[2], b = colors.ACCENT_GOOD[3] }
end
