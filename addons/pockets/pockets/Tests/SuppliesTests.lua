--[[
    Tests/SuppliesTests.lua - Soul shard / water / food supply counters.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local Supplies = Pockets.Services.Supplies
local SidecarHUD = Pockets.UI.SidecarHUD

local function Drink(itemID, qty)
    return { itemID = itemID, quantity = qty, classID = 0, subclassID = 5, name = "w" .. itemID, minLevel = 1 }
end
local function Food(itemID, qty, minLevel)
    return { itemID = itemID, quantity = qty, classID = 0, subclassID = 5, name = "f" .. itemID, minLevel = minLevel }
end
local SHARD = { itemID = 6265, quantity = 7, classID = 7, subclassID = 0, name = "Soul Shard" }

TestRunner:Register("Supplies: water rolls up all sources; best by rank", function()
    local out = Supplies.Compute({ Drink(159, 20), Drink(8079, 10), Drink(1179, 5) }, "MAGE", {})
    local water = out[1]
    local ok = #out == 1 and water.kind == "water" and water.count == 35 and water.bestItemID == 8079
    return ok, ok and "OK" or "bad water rollup"
end)

TestRunner:Register("Supplies: food excludes water, best by required level", function()
    local out = Supplies.Compute(
        { Drink(159, 20), Food(4540, 10, 1), Food(4599, 3, 15) }, "WARRIOR", { showFood = true })
    local food = out[1]
    local ok = #out == 1 and food.kind == "food" and food.count == 13 and food.bestItemID == 4599
    return ok, ok and "OK" or "bad food rollup"
end)

TestRunner:Register("Supplies: class and setting gating", function()
    local items = { SHARD, Drink(159, 5), Food(4540, 2, 1) }
    local warlock = Supplies.Compute(items, "WARLOCK", {})
    local warlockFood = Supplies.Compute(items, "WARLOCK", { showFood = true })
    local warrior = Supplies.Compute(items, "WARRIOR", {})
    local ok = #warlock == 2 and warlock[1].kind == "shards" and warlock[1].count == 7
        and warlock[2].kind == "water" and #warlockFood == 3 and #warrior == 0
        and #Supplies.Compute(items, "MAGE", {}) == 1
    return ok, ok and "OK" or "bad gating"
end)

TestRunner:Register("Supplies: eligible kinds with none carried still listed at zero", function()
    local out = Supplies.Compute({}, "PRIEST", {})
    local ok = #out == 1 and out[1].count == 0 and out[1].bestItemID == nil
    return ok, ok and "OK" or "bad empty supplies"
end)

TestRunner:Register("Sidecar: supplies in model; column height maths", function()
    local model = SidecarHUD.BuildModel(5, {}, {}, { { kind = "water", label = "Water", count = 3 } })
    local lines = SidecarHUD.SupplyTooltip({ label = "Water", count = 3, bestName = "Crystal" })
    local ok = #model.supplies == 1 and SidecarHUD.ColumnHeight(0) == 0
        and SidecarHUD.ColumnHeight(1) == 24 and SidecarHUD.ColumnHeight(3) == 78
        and lines[1] == "Water: 3" and lines[2] == "Best: Crystal"
    return ok, ok and "OK" or "bad sidecar supplies"
end)
