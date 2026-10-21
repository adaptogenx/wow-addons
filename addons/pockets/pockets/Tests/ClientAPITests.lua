--[[
    Tests/ClientAPITests.lua - Forever M1 adapter cases: client detection,
    addon metadata, modern-vs-legacy item/bag shims, Secret Values, and
    tooltip degradation. Each test swaps globals and restores them.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local ClientAPI = Pockets.Adapters.ClientAPI
local ItemAPI = Pockets.Adapters.ItemAPI
local BagAPI = Pockets.Adapters.BagAPI
local TooltipAPI = Pockets.Adapters.TooltipAPI

-- Runs fn with the named globals replaced (false = set nil), then restores.
local function WithGlobals(overrides, fn)
    local saved = {}
    for k in pairs(overrides) do saved[k] = _G[k] end
    for k, v in pairs(overrides) do
        if v == false then _G[k] = nil else _G[k] = v end
    end
    local ok, result = pcall(fn)
    for k, v in pairs(saved) do _G[k] = v end
    if not ok then return false end
    return result
end

TestRunner:Register("ClientAPI: interface numbers classify Forever / Classic / unknown", function()
    local C = ClientAPI.ClassifyInterface
    local ok = C(16001) == "forever" and C(11509) == "classic" and C(20504) == "classic"
        and C(110000) == "unknown" and C(nil) == "unknown" and C("x") == "unknown"
    return ok, ok and "OK" or "bad classification"
end)

TestRunner:Register("ClientAPI: GetAddonMetadata prefers C_AddOns, falls back to legacy global", function()
    local modern = WithGlobals({
        C_AddOns = { GetAddOnMetadata = function() return "modern" end },
        GetAddOnMetadata = function() return "legacy" end,
    }, function() return ClientAPI:GetAddonMetadata("Pockets", "Version") == "modern" end)
    local legacy = WithGlobals({
        C_AddOns = false,
        GetAddOnMetadata = function() return "legacy" end,
    }, function() return ClientAPI:GetAddonMetadata("Pockets", "Version") == "legacy" end)
    local none = WithGlobals({ C_AddOns = false, GetAddOnMetadata = false },
        function() return ClientAPI:GetAddonMetadata("Pockets", "Version") == nil end)
    local ok = modern and legacy and none
    return ok, ok and "OK" or "addon metadata shim wrong"
end)

TestRunner:Register("ClientAPI: IsSecret is false without issecretvalue, honors it when present", function()
    local absent = WithGlobals({ issecretvalue = false }, function() return ClientAPI:IsSecret(5) == false end)
    local present = WithGlobals({ issecretvalue = function(v) return v == "S" end },
        function() return ClientAPI:IsSecret("S") == true and ClientAPI:IsSecret(5) == false end)
    local ok = absent and present
    return ok, ok and "OK" or "IsSecret wrong"
end)

TestRunner:Register("ItemAPI: metadata comes from C_Item.GetItemInfo when present (Forever)", function()
    local result = WithGlobals({
        C_Item = { GetItemInfo = function()
            return "Linen", "item:1", 1, 1, 1, "Trade Goods", "Cloth", 20, "", 123, 0, 7, 5, 0, 0, 0, true
        end },
        GetItemInfo = function() error("legacy GetItemInfo must not be used") end,
    }, function()
        ItemAPI:ResetCache()
        local m = ItemAPI:GetItemMetadata(2589)
        ItemAPI:ResetCache()
        return m.status == "ready" and m.name == "Linen" and m.classID == 7 and m.maxStack == 20
            and m.isCraftingReagent == true
    end)
    return result, result and "OK" or "C_Item metadata not normalized"
end)

TestRunner:Register("ItemAPI: Classic fallback uses legacy GetItemInfo", function()
    local result = WithGlobals({
        C_Item = false,
        GetItemInfo = function() return "Linen", "item:1", 1, 1, 1, "Trade Goods", "Cloth", 20, "", 123, 0, 7, 5 end,
    }, function()
        ItemAPI:ResetCache()
        local m = ItemAPI:GetItemMetadata(2589)
        ItemAPI:ResetCache()
        return m.status == "ready" and m.name == "Linen"
    end)
    return result, result and "OK" or "legacy fallback failed"
end)

TestRunner:Register("ItemAPI: unresolved item stays pending, requests load, then resolves", function()
    local requested, known = {}, false
    local result = WithGlobals({
        C_Item = {
            GetItemInfo = function()
                if known then return "Linen", "l", 1, 1, 1, "TG", "C", 20, "", 1, 0, 7, 5 end
            end,
            RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
        },
    }, function()
        ItemAPI:ResetCache()
        local first = ItemAPI:GetItemMetadata(2589)
        local pendingOK = first.status == "pending" and ItemAPI:IsPending(2589) and requested[1] == 2589
        known = true
        local second = ItemAPI:GetItemMetadata(2589)
        ItemAPI:ResetCache()
        return pendingOK and second.status == "ready" and second.name == "Linen"
    end)
    return result, result and "OK" or "pending->ready transition failed"
end)

TestRunner:Register("ItemAPI: Secret Value metadata degrades to pending, no error", function()
    local result = WithGlobals({
        issecretvalue = function(v) return v == "SECRET" end,
        C_Item = { GetItemInfo = function() return "SECRET", "l", 1, 1, 1, "TG", "C", 20, "", 1, 0, 7, 5 end },
    }, function()
        ItemAPI:ResetCache()
        local m = ItemAPI:GetItemMetadata(2589)
        ItemAPI:ResetCache()
        return m.status == "pending"
    end)
    return result, result and "OK" or "secret metadata not treated as pending"
end)

TestRunner:Register("ItemAPI: GetItemFamily prefers C_Item, falls back to legacy", function()
    local modern = WithGlobals({
        C_Item = { GetItemFamily = function() return 2 end },
        GetItemFamily = function() return 99 end,
    }, function() return ItemAPI:GetItemFamily("item:1") == 2 end)
    local legacy = WithGlobals({ C_Item = false, GetItemFamily = function() return 4 end },
        function() return ItemAPI:GetItemFamily("item:1") == 4 end)
    local ok = modern and legacy
    return ok, ok and "OK" or "family shim wrong"
end)

TestRunner:Register("BagAPI: quiver / ammo pouch / normal bag classify via modern family API", function()
    local function Classify(family)
        return WithGlobals({
            C_Container = { ContainerIDToInventoryID = function() return 20 end },
            GetInventoryItemLink = function() return "item:1" end,
            C_Item = { GetItemFamily = function() return family end },
        }, function() return BagAPI:IsAmmoBag(1) end)
    end
    local ok = Classify(2) == true and Classify(4) == true and Classify(0) == false and Classify(1) == false
    return ok, ok and "OK" or "ammo family classification wrong"
end)

TestRunner:Register("BagAPI: empty bag slot is not ammo and not equipped", function()
    local r = WithGlobals({
        C_Container = { ContainerIDToInventoryID = function() return 20 end },
        GetInventoryItemLink = function() return nil end,
    }, function() return BagAPI:IsAmmoBag(2) == false and BagAPI:HasEquippedBag(2) == false end)
    return r, r and "OK" or "empty bag slot misdetected"
end)

TestRunner:Register("BagAPI: Secret slot count is treated as unknown (0), not an error", function()
    local r = WithGlobals({
        issecretvalue = function(v) return v == -1 end,
        C_Container = { GetContainerNumSlots = function() return -1 end },
        GetContainerNumSlots = false,
    }, function() return BagAPI:GetBagSlotCount(1) == 0 end)
    return r, r and "OK" or "secret slot count not handled"
end)

TestRunner:Register("BagAPI: Secret slot contents are skipped, not aggregated", function()
    local r = WithGlobals({
        issecretvalue = function(v) return v == "S" end,
        C_Container = { GetContainerItemInfo = function()
            return { itemID = 1, stackCount = "S", hyperlink = "l", quality = 1, isLocked = false, iconFileID = 1 }
        end },
    }, function() return BagAPI:GetSlotInfo(0, 1) == nil end)
    return r, r and "OK" or "secret slot not skipped"
end)

TestRunner:Register("BagAPI: modern slot info normalizes to the Pockets contract", function()
    local r = WithGlobals({
        issecretvalue = false,
        C_Container = { GetContainerItemInfo = function()
            return { itemID = 2589, stackCount = 7, hyperlink = "link", quality = 1, isLocked = true, iconFileID = 99 }
        end },
    }, function()
        local slot = BagAPI:GetSlotInfo(0, 1)
        return slot.itemID == 2589 and slot.quantity == 7 and slot.itemLink == "link"
            and slot.quality == 1 and slot.isLocked == true and slot.texture == 99
    end)
    return r, r and "OK" or "slot contract wrong"
end)

TestRunner:Register("TooltipAPI: legacy item handler detected only when present", function()
    local gone = { HookScript = function() error("must not hook") end, HasScript = function() return false end }
    local here = { HookScript = function() end, HasScript = function() return true end }
    local r = TooltipAPI:HasLegacyItemHandler(gone) == false
        and TooltipAPI:HasLegacyItemHandler(nil) == false
        and TooltipAPI:HasLegacyItemHandler(here) == true
    return r, r and "OK" or "legacy handler detection wrong"
end)

TestRunner:Register("BindingsAPI: SaveBindings set is always 1 or 2 (Forever usage error)", function()
    local N = Pockets.Adapters.BindingsAPI.NormalizeBindingSet
    local ok = N(1) == 1 and N(2) == 2 and N(0) == 1 and N(3) == 1 and N(nil) == 1
    return ok, ok and "OK" or "binding set not normalized"
end)

TestRunner:Register("TooltipAPI: ExtractItem reads id/hyperlink, rejects secret and non-numeric ids", function()
    local E = TooltipAPI.ExtractItem
    local id, link = E({ id = 6948, hyperlink = "|Hitem:6948|h" })
    local noSecret = function() return false end
    local allSecret = function() return true end
    local ok = id == 6948 and link == "|Hitem:6948|h"
        and E(nil) == nil and E({ id = "x" }) == nil
        and E({ id = 6948 }, allSecret) == nil
        and E({ id = 6948 }, noSecret) == 6948
    return ok, ok and "OK" or "bad ExtractItem"
end)

TestRunner:Register("TooltipAPI: modern pipeline detected only when fully present", function()
    local full = WithGlobals({
        TooltipDataProcessor = { AddTooltipPostCall = function() end },
        Enum = { TooltipDataType = { Item = 0 } },
    }, function() return TooltipAPI:HasModernPipeline() == true end)
    local none = WithGlobals({ TooltipDataProcessor = false },
        function() return TooltipAPI:HasModernPipeline() == false end)
    local ok = full and none
    return ok, ok and "OK" or "bad pipeline detection"
end)
