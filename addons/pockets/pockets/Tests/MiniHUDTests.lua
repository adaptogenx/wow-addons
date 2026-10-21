--[[
    Tests/MiniHUDTests.lua - Mini HUD TDD §6: count formatting, threshold
    boundaries, ring fraction/segments, main-bag-only counts, 
    anchor preservation, and click -> category list.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Shell = Pockets.UI.Shell
local MiniHUD = Pockets.UI.MiniHUD
local CapacityRing = Pockets.UI.CapacityRing
local PHUI = Pockets.UI.PHUI
local Constants = Pockets.Constants
local L = Constants.LAYOUT

-- Runs fn from the idle (closed) state, then returns to it.
local function WithMini(fn)
    Shell:SetState(Shell.STATE.GLANCE)
    local ok, a, b = pcall(fn)
    Shell:SetState(Shell.STATE.GLANCE)
    if not ok then
        error(a)
    end
    return a, b
end

local function Cap(used, total)
    return { used = used, total = total, utilization = total > 0 and used / total or 0 }
end

TestRunner:Register("Mini: count formatting", function()
    local ok = MiniHUD.FormatCount(0, 46) == "0/46" and MiniHUD.FormatCount(32, 46) == "32/46"
        and MiniHUD.FormatCount(43, 46) == "43/46" and MiniHUD.FormatCount(46, 46) == "46/46"
        and MiniHUD.FormatCount(0, 0) == "0/0" and MiniHUD.FormatCount(nil, nil) == "0/0"
    return ok, ok and "OK" or "bad count text"
end)

TestRunner:Register("Mini: ring color thresholds (69.9 green, 70 yellow, 89.9 yellow, 90 red, 100 red)", function()
    local C = PHUI.Colors
    local function is(color, r, g, b) return color[1] == r and color[2] == g and color[3] == b end
    local function colorAt(pct)
        local r, g, b = MiniHUD.GetColor(Cap(pct, 100))
        return { r, g, b }
    end
    -- 69.9% / 89.9% cannot be a whole slot count; use a large total.
    local function at(frac)
        local r, g, b = MiniHUD.GetColor({ used = frac * 1000, total = 1000 })
        return { r, g, b }
    end
    local g, y, rd = C.ACCENT_GOOD, C.ACCENT_WARNING, C.ACCENT_BAD
    local ok = is(at(0.699), g[1], g[2], g[3]) and is(at(0.70), y[1], y[2], y[3])
        and is(at(0.899), y[1], y[2], y[3]) and is(at(0.90), rd[1], rd[2], rd[3])
        and is(colorAt(100), rd[1], rd[2], rd[3])
    return ok, ok and "OK" or "bad threshold color"
end)

TestRunner:Register("Mini: ring fraction clamps to [0,1]; zero capacity is safe and neutral", function()
    local m = PHUI.Colors.TEXT_MUTED
    local r, g, b = MiniHUD.GetColor(Cap(0, 0))
    local ok = CapacityRing.ClampFraction(-1) == 0 and CapacityRing.ClampFraction(2) == 1
        and CapacityRing.ClampFraction(0 / 0) == 0 and CapacityRing.ClampFraction(nil) == 0
        and MiniHUD.GetFraction(Cap(0, 0)) == 0 and MiniHUD.GetFraction(Cap(50, 46)) == 1
        and r == m[1] and g == m[2] and b == m[3]
    return ok, ok and "OK" or "bad fraction/neutral"
end)

TestRunner:Register("Mini: ring lights segments proportionally (0 none, full all, partial in between)", function()
    local n = CapacityRing.DEFAULT_SEGMENTS
    local ok = CapacityRing.LitSegments(0, n) == 0 and CapacityRing.LitSegments(1, n) == n
        and CapacityRing.LitSegments(0.5, n) == n / 2 and CapacityRing.LitSegments(0.001, n) == 1
        and CapacityRing.LitSegments(0.999, n) == n - 1
    return ok, ok and "OK" or "bad segment count"
end)

TestRunner:Register("Mini: Render fills the ring and badge from main-bag capacity", function()
    local InventoryState = Pockets.Services.InventoryState
    local original = InventoryState.GetGeneralCapacity
    InventoryState.GetGeneralCapacity = function() return Cap(23, 46) end
    local ok, text, lit = pcall(function()
        return WithMini(function()
            return Shell.mini.badge.text:GetText(), Shell.mini.ring:GetLitCount()
        end)
    end)
    InventoryState.GetGeneralCapacity = original
    local pass = ok and text == "23/46" and lit == CapacityRing.LitSegments(0.5, Shell.mini.ring.segmentCount)
    return pass, pass and "OK" or string.format("text=%s lit=%s", tostring(text), tostring(lit))
end)

TestRunner:Register("Mini: footprint matches the Mini layout tokens", function()
    local detail
    local ok = WithMini(function()
        local w, h = Shell.root:GetSize()
        local bw, bh = Shell.mini.badge:GetSize()
        detail = string.format("root=%sx%s want %sx%s; badge=%sx%s want %sx%s; shown=%s",
            tostring(w), tostring(h), tostring(L.MINI_WIDTH), tostring(L.MINI_HEIGHT),
            tostring(bw), tostring(bh), tostring(L.MINI_BADGE_WIDTH), tostring(L.MINI_BADGE_HEIGHT),
            tostring(Shell.mini:IsShown()))
        return w == L.MINI_WIDTH and h == L.MINI_HEIGHT
            and h == L.MINI_PORTRAIT_SIZE - L.MINI_BADGE_OVERLAP + L.MINI_BADGE_HEIGHT
            and bw == L.MINI_BADGE_WIDTH and bh == L.MINI_BADGE_HEIGHT and Shell.mini:IsShown()
    end)
    return ok, ok and "OK" or detail
end)

TestRunner:Register("Mini: clicking opens the category list (Menu) directly, not Glance", function()
    local state = WithMini(function()
        Shell.root:Click()
        return Shell:GetState()
    end)
    local ok = state == Shell.STATE.MENU
    return ok, ok and "OK" or ("state=" .. tostring(state))
end)

TestRunner:Register("Mini: count text stays cream under 70%, then yellow, then red", function()
    local C = PHUI.Colors
    local function is(color, r, g, b) return r == color[1] and g == color[2] and b == color[3] end
    local function at(used, total) return MiniHUD.GetTextColor({ used = used, total = total }) end
    local ok = is(C.TEXT_PRIMARY, at(500, 1000)) and is(C.TEXT_PRIMARY, at(699, 1000))
        and is(C.ACCENT_WARNING, at(800, 1000)) and is(C.ACCENT_BAD, at(950, 1000))
        and is(C.ACCENT_BAD, at(46, 46)) and is(C.TEXT_PRIMARY, at(0, 0))
    return ok, ok and "OK" or "bad count text colours"
end)
