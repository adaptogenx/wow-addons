--[[
    Tests/ItemButtonPoolTests.lua - Count-fontstring visibility (TDD §24.1)
    and bag/slot ID binding for Blizzard's inherited
    ContainerFrameItemButtonTemplate right-click use/equip/disenchant-
    target behavior.

    These need a real button (ContainerFrameItemButtonTemplate), so they
    run in-client via /pockets test run - there is no secure-attribute
    bookkeeping left to exercise with a mock button anymore; Blizzard's
    own OnClick resolves bag/slot live from bagIndexFrame:GetID()/
    button:GetID(), which Configure() just keeps in sync.
]]

local _, Pockets = ...

local ItemButtonPool = Pockets.UI.ItemButtonPool
local BagAPI = Pockets.Adapters.BagAPI
local InventoryState = Pockets.Services.InventoryState

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure shows the Count text for quantity > 1", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, { itemID = 1, texture = 1, quantity = 63 })

    local ok = button.Count and button.Count:IsShown() and button.Count:GetText() == "63"
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected Count fontstring shown with text '63' for quantity 63"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure hides the Count text for quantity == 1", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, { itemID = 1, texture = 1, quantity = 1 })

    local ok = button.Count == nil or not button.Count:IsShown()
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected Count fontstring hidden for quantity 1"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: pooled buttons inherit ContainerFrameItemButtonTemplate", function()
    local button = ItemButtonPool:Acquire(UIParent)
    -- NewItemTexture is a field only ContainerFrameItemButtonTemplate
    -- provides (not plain ItemButtonTemplate) - its presence confirms the
    -- inheritance actually took, without guessing at a specific OnClick
    -- function reference (client-build-specific, verified manually
    -- in-client instead - see the plan's verification steps).
    local ok = button.NewItemTexture ~= nil
    ItemButtonPool:ReleaseAll(UIParent)
    return ok, ok and "OK" or "expected pooled item buttons to inherit ContainerFrameItemButtonTemplate (NewItemTexture missing)"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: OnClick is never overridden (stays Blizzard's own handler)", function()
    local button = ItemButtonPool:Acquire(UIParent)
    -- Pockets must never SetScript("OnClick", ...) on these buttons -
    -- doing so would replace Blizzard's own inherited use/equip/
    -- disenchant-target handler. GetScript("OnClick") returning nil here
    -- would mean either no template loaded (build error) or something
    -- clobbered it - both are failures.
    local onClick = button:GetScript("OnClick")
    local preClick = button:GetScript("PreClick")
    ItemButtonPool:ReleaseAll(UIParent)
    local ok = onClick ~= nil and preClick ~= nil
    return ok, ok and "OK" or "expected a Blizzard-provided OnClick plus Pockets' own PreClick, neither nil"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure binds bagIndexFrame/button IDs to the physical bag slot", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })
    local bagID = button.bagIndexFrame:GetID()
    local slotID = button:GetID()
    ItemButtonPool:ReleaseAll(UIParent)
    local ok = bagID == 0 and slotID == 5
    return ok, ok and "OK" or string.format(
        "expected bagIndexFrame ID 0 / button ID 5, got %s/%s", tostring(bagID), tostring(slotID))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Configure clears IDs to 0/0 on a non-interactive record", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, interactive = false,
    })
    local bagID = button.bagIndexFrame:GetID()
    local slotID = button:GetID()
    ItemButtonPool:ReleaseAll(UIParent)
    local ok = bagID == 0 and slotID == 0
    return ok, ok and "OK" or string.format(
        "expected cleared IDs 0/0, got bagID=%s slotID=%s", tostring(bagID), tostring(slotID))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: non-Recent item tooltip anchors to the HUD's top-right", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })

    button:GetScript("OnEnter")(button)
    local point, relativeTo, relativePoint = GameTooltip:GetPoint()
    GameTooltip:Hide()
    ItemButtonPool:ReleaseAll(UIParent)

    local ok = point == "TOPLEFT" and relativeTo == Pockets.UI.Shell:GetActiveFrame() and relativePoint == "TOPRIGHT"
    return ok, ok and "OK" or string.format(
        "expected TOPLEFT anchored to the HUD's TOPRIGHT, got point=%s relativeToHud=%s relativePoint=%s",
        tostring(point), tostring(relativeTo == Pockets.UI.Shell:GetActiveFrame()), tostring(relativePoint))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: Recent-item tooltip keeps its own per-button anchor (not the HUD's)", function()
    local button = ItemButtonPool:Acquire(UIParent)
    ItemButtonPool:Configure(button, {
        itemID = 1, texture = 1, quantity = 1, bagID = 0, slotID = 5,
    })
    button.isRecentItem = true

    button:GetScript("OnEnter")(button)
    local _, relativeTo = GameTooltip:GetPoint()
    GameTooltip:Hide()
    button.isRecentItem = nil -- this pool button is reused by later tests - don't leak the flag
    ItemButtonPool:ReleaseAll(UIParent)

    local ok = relativeTo ~= Pockets.UI.Shell:GetActiveFrame()
    return ok, ok and "OK" or "expected a Recent item's tooltip to stay anchored to itself, not redirected to the HUD"
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: HandleInsecureClick pickups on left-click and does not UseItem on right-click", function()
    local previousItems = InventoryState.items
    InventoryState.items = {
        ["0:1"] = { key = "0:1", bagID = 0, slotID = 1, itemID = 4242, quantity = 5 },
    }

    local used, pickedBag, pickedSlot = false, nil, nil
    local origUse, origPickup = BagAPI.UseItem, BagAPI.PickupItem
    BagAPI.UseItem = function()
        used = true
    end
    BagAPI.PickupItem = function(_, bagID, slotID)
        pickedBag, pickedSlot = bagID, slotID
    end

    local origModified = IsModifiedClick
    IsModifiedClick = function()
        return false
    end

    local button = {
        interactive = true,
        bagID = 0,
        slotID = 1,
        itemID = 4242,
        itemLink = "item:4242",
    }

    ItemButtonPool.HandleInsecureClick(button, "RightButton")
    local rightUsed, rightPicked = used, pickedBag
    local rightOk = rightUsed == false and rightPicked == nil

    ItemButtonPool.HandleInsecureClick(button, "LeftButton")
    local leftOk = pickedBag == 0 and pickedSlot == 1 and used == false

    BagAPI.UseItem = origUse
    BagAPI.PickupItem = origPickup
    IsModifiedClick = origModified
    InventoryState.items = previousItems

    local ok = rightOk and leftOk
    return ok, ok and "OK" or string.format(
        "right-click used=%s picked=%s; left-click bag=%s slot=%s used=%s",
        tostring(rightUsed), tostring(rightPicked), tostring(pickedBag), tostring(pickedSlot), tostring(used))
end)

Pockets.Tests.TestRunner:Register("ItemButtonPool: pooled buttons are uniquely named (modern templates resolve _G[name..'Count'])", function()
    local parent = CreateFrame("Frame")
    local a = Pockets.UI.ItemButtonPool:Acquire(parent)
    local b = Pockets.UI.ItemButtonPool:Acquire(parent)
    local nameA, nameB = a:GetName(), b:GetName()
    Pockets.UI.ItemButtonPool:ReleaseAll(parent)
    local ok = nameA ~= nil and nameB ~= nil and nameA ~= nameB
    return ok, ok and "OK" or string.format("names: %s / %s", tostring(nameA), tostring(nameB))
end)
