--[[
    Tests/CategorizerTests.lua - Category mapping and precedence (TDD §24.1)
]]

local _, Pockets = ...

local CATEGORY = Pockets.Constants.CATEGORY
local Categorizer = Pockets.Services.ItemCategorizer

Pockets.Tests.TestRunner:Register("Categorizer: quest override beats class", function()
    local category = Categorizer:Categorize({ itemID = 1, classID = 2, isQuestItem = true })
    return category == CATEGORY.QUEST, string.format("expected quest, got %s", category)
end)

Pockets.Tests.TestRunner:Register("Categorizer: ammo by capacityClass", function()
    local category = Categorizer:Categorize({
        itemID = 2,
        classID = 7,
        capacityClass = Pockets.Constants.CAPACITY_CLASS.AMMO,
    })
    return category == CATEGORY.AMMO, string.format("expected ammo, got %s", category)
end)

Pockets.Tests.TestRunner:Register("Categorizer: poor quality is junk before consumable", function()
    local category = Categorizer:Categorize({ itemID = 3, classID = 0, quality = 0 })
    return category == CATEGORY.JUNK, string.format("expected junk, got %s", category)
end)

Pockets.Tests.TestRunner:Register("Categorizer: consumable class", function()
    local category = Categorizer:Categorize({ itemID = 4, classID = 0, quality = 1 })
    return category == CATEGORY.CONSUMABLE, string.format("expected consumable, got %s", category)
end)

Pockets.Tests.TestRunner:Register("Categorizer: equipment (armor/weapon) class", function()
    local armor = Categorizer:Categorize({ itemID = 5, classID = 4, quality = 1 })
    local weapon = Categorizer:Categorize({ itemID = 6, classID = 2, quality = 1 })
    return armor == CATEGORY.EQUIPMENT and weapon == CATEGORY.EQUIPMENT,
        string.format("expected equipment/equipment, got %s/%s", armor, weapon)
end)

Pockets.Tests.TestRunner:Register("Categorizer: trade goods class", function()
    local category = Categorizer:Categorize({ itemID = 7, classID = 7, quality = 1 })
    return category == CATEGORY.TRADE_GOODS, string.format("expected trade_goods, got %s", category)
end)

Pockets.Tests.TestRunner:Register("Categorizer: unknown class falls back to other", function()
    local category = Categorizer:Categorize({ itemID = 8, classID = 99, quality = 1 })
    return category == CATEGORY.OTHER, string.format("expected other, got %s", category)
end)
