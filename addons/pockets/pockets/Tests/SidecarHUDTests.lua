--[[
    Tests/SidecarHUDTests.lua - Sidecar HUD: layout tokens, gold fixed /
    ammo conditional, content-sized recent strip, no leftover pieces,
    anchor, and click routing.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Shell = Pockets.UI.Shell
local SidecarHUD = Pockets.UI.SidecarHUD
local Constants = Pockets.Constants
local L = Constants.LAYOUT

local function WithMini(fn)
    Shell:SetState(Shell.STATE.GLANCE)
    local ok, a = pcall(fn)
    Shell:SetState(Shell.STATE.GLANCE)
    if not ok then
        error(a)
    end
    return a
end

TestRunner:Register("Sidecar: layout tokens match the spec", function()
    local S = SidecarHUD.STRIP_SPEC
    local ok = L.SIDECAR_BADGE_HEIGHT == 24 and L.SIDECAR_BADGE_GAP == 3 and L.SIDECAR_MINI_GAP == 4
        and S.icon == 22 and S.gap == 2 and S.padX == 0 and S.height == 22 and S.icons == 5
        and S.backdrop == nil and L.SIDECAR_STRIP_BELOW == 4
        -- Mini + gap + minimum column fits five icons with their minimum gaps.
        and L.MINI_WIDTH + L.SIDECAR_MINI_GAP + L.SIDECAR_BADGE_WIDTH >= 5 * 22 + 4 * 2
    return ok, ok and "OK" or "bad sidecar tokens"
end)

TestRunner:Register("Sidecar: gold always present; ammo only when applicable", function()
    local none = SidecarHUD.BuildModel(5, {}, {})
    local quiver = SidecarHUD.BuildModel(5, {
        { class = "ammo", used = 1, total = 18, label = "Ammo" },
    }, {})
    local loose = SidecarHUD.BuildModel(5, {}, { { itemID = 1, texture = 9, quantity = 187 } })
    local bagOnly = SidecarHUD.BuildModel(5, {
        { class = "herbs", used = 1, total = 20, label = "Herbs" },
    }, {})
    local ok = none.gold == 5 and none.ammo == nil and quiver.ammo ~= nil and quiver.ammo.isAmmo
        and loose.ammo and loose.ammo.ammoCount == 187 and bagOnly.ammo == nil
    return ok, ok and "OK" or "bad sidecar model"
end)

TestRunner:Register("Sidecar: strip spans the container; icons spaced evenly; aligned by screen side", function()
    local W = 118
    local five = {}
    for i = 1, 5 do five[i] = SidecarHUD.IconX(i, 5, W, "left") end
    local wide = SidecarHUD.StripGap(140)
    local ok = SidecarHUD.StripGap(W) == 2
        and five[1] == 0 and five[2] == 24 and five[5] + 22 == W
        and wide > 2 and SidecarHUD.IconX(5, 5, 140, "left") + 22 == 140
        and SidecarHUD.IconX(1, 2, W, "right") == W - (2 * 22 + 2)
        and SidecarHUD.IconX(1, 3, W, "center") == (W - (3 * 22 + 2 * 2)) / 2
        and SidecarHUD.Align(100, 1000) == "left" and SidecarHUD.Align(500, 1000) == "center"
        and SidecarHUD.Align(900, 1000) == "right"
        and SidecarHUD.BadgeWidth(10) == L.SIDECAR_BADGE_WIDTH and SidecarHUD.BadgeWidth(80) > L.SIDECAR_BADGE_WIDTH
    return ok, ok and "OK" or "bad strip math"
end)

TestRunner:Register("Sidecar: keeps the Mini footprint and anchor", function()
    local p0, _, rp0, x0, y0 = Shell.root:GetPoint()
    local ok = WithMini(function()
        local w, h = Shell.root:GetSize()
        local p1, _, rp1, x1, y1 = Shell.root:GetPoint()
        return w == L.MINI_WIDTH and h == L.MINI_HEIGHT and Shell.mini:IsShown()
            and p0 == p1 and rp0 == rp1 and x0 == x1 and y0 == y1
            and Shell.sidecar.gold:IsShown()
    end)
    return ok, ok and "OK" or "sidecar footprint or anchor wrong"
end)

TestRunner:Register("Sidecar: gold centres on the Mini when ammo hides; Mini click opens the list", function()
    local result = WithMini(function()
        local sidecar = Shell.sidecar
        local InventoryState = Pockets.Services.InventoryState
        local original = InventoryState.GetSpecializedCapacities
        InventoryState.GetSpecializedCapacities = function()
            return { { class = "ammo", used = 1, total = 18, utilization = 1 / 18, label = "Ammo", texture = 1 } }
        end
        SidecarHUD:Render(sidecar)
        local _, _, _, _, gy1 = sidecar.gold:GetPoint()
        local ammoShown = sidecar.ammo:IsShown()
        InventoryState.GetSpecializedCapacities = function() return {} end
        local api = Pockets.API.GetAggregatedCategoryItems
        Pockets.API.GetAggregatedCategoryItems = function() return {} end
        SidecarHUD:Render(sidecar)
        local _, _, _, _, gy2 = sidecar.gold:GetPoint()
        local ammoHidden = not sidecar.ammo:IsShown()
        local stripHidden = not sidecar.strip:IsShown()
        Pockets.API.GetAggregatedCategoryItems = api
        InventoryState.GetSpecializedCapacities = original
        Shell.root:Click()
        local centred = math.abs(gy2 + (L.MINI_PORTRAIT_SIZE - L.SIDECAR_BADGE_HEIGHT) / 2) < 0.01
        return ammoShown and ammoHidden and stripHidden and centred and gy1 > gy2
            and Shell:GetState() == Shell.STATE.MENU
    end)
    return result, result and "OK" or "ammo/gold/strip/click behavior wrong"
end)

TestRunner:Register("Sidecar: gold stays compact and keeps its denomination", function()
    local F = SidecarHUD.FormatGold
    local ok = F(0) == "0c" and F(45) == "45c" and F(1200) == "12s" and F(1520000) == "152g"
        and F(124000000) == "12.4kg" and F(12000000000) == "1.2mg" and F(-5) == "0c" and F(nil) == "0c"
    return ok, ok and "OK" or string.format("%s %s %s", F(1520000), F(124000000), F(12000000000))
end)

TestRunner:Register("Sidecar: ETA shows only when filling with enough confidence", function()
    local E = Constants.ESTIMATOR_STATE
    local ok = SidecarHUD.FormatEta(E.FILLING, 0.8, 13 * 60) == "13m to full"
        and SidecarHUD.FormatEta(E.FILLING, 0.8, 20) == "<1m to full"
        and SidecarHUD.FormatEta(E.FILLING, 0.4, 13 * 60) == nil
        and SidecarHUD.FormatEta(E.FILLING, 0.8, nil) == nil
        and SidecarHUD.FormatEta(E.STABLE, 1, 13 * 60) == nil
        and SidecarHUD.FormatEta(E.WARMING_UP, 1, 13 * 60) == nil
        and SidecarHUD.FormatEta(E.FULL, 1, nil) == nil
    return ok, ok and "OK" or "ETA gating wrong"
end)

TestRunner:Register("Sidecar: ETA pill sits on the same side as the gold/ammo badges, level with the Mini's count badge", function()
    local sidecar = Shell.sidecar
    if not sidecar.eta then
        return false, "no sidecar.eta"
    end
    SidecarHUD:Layout(sidecar)
    local etaPoint, _, etaRel, _, etaY = sidecar.eta:GetPoint()
    local goldPoint = sidecar.gold:GetPoint()
    local centre = -etaY + sidecar.eta:GetHeight() / 2
    local want = L.MINI_HEIGHT - L.MINI_BADGE_HEIGHT / 2
    local ok = etaPoint == goldPoint and etaRel == "TOPLEFT" and math.abs(centre - want) < 0.01
    return ok, ok and "OK" or string.format("eta=%s gold=%s centre=%s want=%s",
        tostring(etaPoint), tostring(goldPoint), tostring(centre), tostring(want))
end)
