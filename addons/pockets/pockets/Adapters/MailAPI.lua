--[[
    Adapters/MailAPI.lua - Isolates direct Blizzard mailbox API access
    (Mail Attach pass).

    Pockets does not implement any mail UI/reading/browsing - mail
    integration is an explicit v1 non-goal (Pockets_PRD.md §4, §23). This
    adapter exists ONLY to let a right-click on an item attach it to an
    ALREADY-OPEN compose-mail message, the same convenience Blizzard's
    own bag slots (and every bag-replacement addon) get "for free."
    Nothing here reads mail, browses inbox contents, or opens the
    mailbox itself.

    Attaching mail is not a protected/combat-gated action (mailboxes are
    always in a safe zone), so this never needs SecureActionButtonTemplate
    - plain insecure Lua calls. Picking the item up onto the cursor goes
    through Adapters/BagAPI.lua's own PickupItem (container/bag API calls
    are confined to that one file - scripts/static-checks.sh enforces
    this); only the mailbox-specific half (GetSendMailItem/SetSendMailItem)
    lives here. Prefers the modern C_MailInfo namespace when present,
    falling back to the legacy globals this client may still expose - the
    same C_Container-preferred/legacy-fallback pattern BagAPI.lua uses for
    container calls.
]]

local _, Pockets = ...

Pockets.Adapters.MailAPI = Pockets.Adapters.MailAPI or {}
local MailAPI = Pockets.Adapters.MailAPI

local BagAPI = Pockets.Adapters.BagAPI

local MAX_ATTACHMENTS = ATTACHMENTS_MAX_SEND or 12

function MailAPI:IsComposingMail()
    return SendMailFrame ~= nil and SendMailFrame:IsShown()
end

-- Index of the first empty attachment slot on the CURRENT compose-mail
-- message, or nil if it's already full (never guesses/overwrites a
-- filled slot).
function MailAPI:FindEmptyAttachmentSlot()
    for index = 1, MAX_ATTACHMENTS do
        local hasItem
        if C_MailInfo and C_MailInfo.GetSendMailItem then
            hasItem = C_MailInfo.GetSendMailItem(index) ~= nil
        else
            hasItem = GetSendMailItem(index) ~= nil
        end
        if not hasItem then
            return index
        end
    end
    return nil
end

-- Attaches bagID/slotID to the currently open compose-mail message.
-- No-op (returns false) when mail isn't being composed, the item has no
-- resolved location, or every attachment slot is already full.
function MailAPI:AttachItem(bagID, slotID)
    if not bagID or not slotID or not self:IsComposingMail() then
        return false
    end
    local slot = self:FindEmptyAttachmentSlot()
    if not slot then
        return false
    end

    BagAPI:PickupItem(bagID, slotID)

    if C_MailInfo and C_MailInfo.SetSendMailItem then
        C_MailInfo.SetSendMailItem(slot)
    else
        SetSendMailItem(slot)
    end

    -- Blizzard's own SendMailAttachment_OnClick calls ClearCursor()
    -- immediately after SetSendMailItem - without it the item stays
    -- "held" on the cursor even though it was already attached, which
    -- makes WoW route every subsequent click as "place this cursor item"
    -- instead of a normal button press (looks like every button, even
    -- unrelated ones, has stopped responding).
    ClearCursor()
    return true
end
