--[[
    Tests/MailAPITests.lua - Adapters/MailAPI.lua (Mail Attach pass)

    SendMailFrame/GetSendMailItem only exist as real widgets/state while
    actually at a mailbox with compose open, so these stub the global
    surface MailAPI reads rather than requiring a live mailbox session -
    matches the pure-logic testing style already used for
    BagAPI:IsAmmoFamily etc.
]]

local _, Pockets = ...

local MailAPI = Pockets.Adapters.MailAPI

local function WithComposingMail(isShown, sendMailItems, fn)
    local originalFrame = _G.SendMailFrame
    local originalGetItem = _G.GetSendMailItem
    _G.SendMailFrame = { IsShown = function() return isShown end }
    _G.GetSendMailItem = function(index) return sendMailItems[index] end

    local ok, err = pcall(fn)

    _G.SendMailFrame = originalFrame
    _G.GetSendMailItem = originalGetItem
    if not ok then
        error(err, 0)
    end
end

Pockets.Tests.TestRunner:Register("MailAPI: IsComposingMail false when SendMailFrame is absent", function()
    local original = _G.SendMailFrame
    _G.SendMailFrame = nil
    local ok = MailAPI:IsComposingMail() == false
    _G.SendMailFrame = original
    return ok, ok and "OK" or "expected IsComposingMail false with no SendMailFrame"
end)

Pockets.Tests.TestRunner:Register("MailAPI: IsComposingMail reflects SendMailFrame:IsShown()", function()
    local ok
    WithComposingMail(true, {}, function()
        ok = MailAPI:IsComposingMail() == true
    end)
    return ok, ok and "OK" or "expected IsComposingMail true when SendMailFrame:IsShown() is true"
end)

Pockets.Tests.TestRunner:Register("MailAPI: FindEmptyAttachmentSlot returns the first empty slot", function()
    local slot
    WithComposingMail(true, { [1] = "Item One", [2] = "Item Two" }, function()
        slot = MailAPI:FindEmptyAttachmentSlot()
    end)
    local ok = slot == 3
    return ok, ok and "OK" or string.format("expected slot 3 (first empty), got %s", tostring(slot))
end)

Pockets.Tests.TestRunner:Register("MailAPI: FindEmptyAttachmentSlot returns nil when every slot is full", function()
    local slot
    local full = {}
    for i = 1, (_G.ATTACHMENTS_MAX_SEND or 12) do
        full[i] = "Item " .. i
    end
    WithComposingMail(true, full, function()
        slot = MailAPI:FindEmptyAttachmentSlot()
    end)
    local ok = slot == nil
    return ok, ok and "OK" or string.format("expected nil (full), got %s", tostring(slot))
end)

Pockets.Tests.TestRunner:Register("MailAPI: AttachItem is a no-op when mail isn't being composed", function()
    local original = _G.SendMailFrame
    _G.SendMailFrame = nil
    local ok = MailAPI:AttachItem(0, 1) == false
    _G.SendMailFrame = original
    return ok, ok and "OK" or "expected AttachItem to no-op when SendMailFrame is absent"
end)

Pockets.Tests.TestRunner:Register("MailAPI: AttachItem is a no-op without a resolved bagID/slotID", function()
    local ok
    WithComposingMail(true, {}, function()
        ok = MailAPI:AttachItem(nil, nil) == false
    end)
    return ok, ok and "OK" or "expected AttachItem to no-op with nil bagID/slotID"
end)

Pockets.Tests.TestRunner:Register("MailAPI: AttachItem is a no-op when every attachment slot is full", function()
    local ok
    local full = {}
    for i = 1, (_G.ATTACHMENTS_MAX_SEND or 12) do
        full[i] = "Item " .. i
    end
    WithComposingMail(true, full, function()
        ok = MailAPI:AttachItem(0, 1) == false
    end)
    return ok, ok and "OK" or "expected AttachItem to no-op when attachments are full"
end)

Pockets.Tests.TestRunner:Register("MailAPI: AttachItem picks up the item and sets it into the empty slot", function()
    local pickedUpBagID, pickedUpSlotID, setSlot
    local BagAPI = Pockets.Adapters.BagAPI
    local originalPickup = BagAPI.PickupItem
    local originalSetItem = _G.SetSendMailItem
    local originalClearCursor = _G.ClearCursor
    BagAPI.PickupItem = function(_, bagID, slotID)
        pickedUpBagID, pickedUpSlotID = bagID, slotID
    end
    _G.SetSendMailItem = function(index)
        setSlot = index
    end
    _G.ClearCursor = function() end

    local attached
    WithComposingMail(true, { [1] = "Item One" }, function()
        attached = MailAPI:AttachItem(0, 5)
    end)

    BagAPI.PickupItem = originalPickup
    _G.SetSendMailItem = originalSetItem
    _G.ClearCursor = originalClearCursor

    local ok = attached == true and pickedUpBagID == 0 and pickedUpSlotID == 5 and setSlot == 2
    return ok, ok and "OK" or string.format(
        "expected attach(true)/pickup(0,5)/slot(2), got attached=%s bagID=%s slotID=%s slot=%s",
        tostring(attached), tostring(pickedUpBagID), tostring(pickedUpSlotID), tostring(setSlot))
end)

-- Regression test: an earlier version of AttachItem never called
-- ClearCursor() after SetSendMailItem, matching Blizzard's own
-- SendMailAttachment_OnClick (which always does) - without it, the item
-- stays "held" on the player's cursor even though it was already
-- attached, which makes WoW route every subsequent click as "place this
-- cursor item" instead of a normal button press (looked like every
-- button, even unrelated ones, had stopped responding).
Pockets.Tests.TestRunner:Register("MailAPI: AttachItem clears the cursor after attaching (no stuck cursor item)", function()
    local BagAPI = Pockets.Adapters.BagAPI
    local originalPickup = BagAPI.PickupItem
    local originalSetItem = _G.SetSendMailItem
    local originalClearCursor = _G.ClearCursor
    local clearCursorCalled = false
    BagAPI.PickupItem = function() end
    _G.SetSendMailItem = function() end
    _G.ClearCursor = function() clearCursorCalled = true end

    WithComposingMail(true, {}, function()
        MailAPI:AttachItem(0, 5)
    end)

    BagAPI.PickupItem = originalPickup
    _G.SetSendMailItem = originalSetItem
    _G.ClearCursor = originalClearCursor

    local ok = clearCursorCalled == true
    return ok, ok and "OK" or "expected AttachItem to call ClearCursor() after SetSendMailItem"
end)
