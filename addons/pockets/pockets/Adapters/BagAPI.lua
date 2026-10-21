--[[
    Adapters/BagAPI.lua - Isolates direct bag/container API access (TDD §3.1, §8, §25.4)

    Rule: every other module must go through this adapter instead of calling
    Blizzard container APIs directly. This keeps client-version compatibility
    logic (Classic container API vs C_Container) in one place and lets
    the domain layer work against normalized Pockets-owned tables.
]]

-- luacheck: globals Enum GetInventoryItemTexture

local _, Pockets = ...

Pockets.Adapters.BagAPI = Pockets.Adapters.BagAPI or {}
local BagAPI = Pockets.Adapters.BagAPI

-- Backpack (0) + normal equipped bags (1-4) are general-purpose in WoW Classic.
-- Ammo/soul/quiver bags are detected by bag family and reported separately.
BagAPI.GENERAL_BAG_IDS = { 0, 1, 2, 3, 4 }

-- Dedicated reagent-bag slot (Forever / retail-style clients). The bagID is
-- feature-detected from Enum.BagIndex.ReagentBag - never hardcoded - and is
-- nil on clients without that slot (Classic/TBC).
function BagAPI:GetReagentBagID()
    if Enum and Enum.BagIndex and type(Enum.BagIndex.ReagentBag) == "number" then
        return Enum.BagIndex.ReagentBag
    end
    return nil
end

-- Every bagID Pockets scans: backpack, the four normal slots, and the
-- dedicated reagent slot when the client has one.
function BagAPI:GetScannedBagIDs()
    local ids = {}
    for _, bagID in ipairs(self.GENERAL_BAG_IDS) do
        table.insert(ids, bagID)
    end
    local reagent = self:GetReagentBagID()
    if reagent then
        table.insert(ids, reagent)
    end
    return ids
end

-- Bag item subclass (classID 1 "Container") -> specialized bag class key.
-- Subclass 0 is the plain bag. classID 11 (Quiver) is handled as "ammo".
-- Keys double as the tab label lookup below.
local CONTAINER_SUBCLASS_TO_CLASS = {
    [1] = "soul",
    [2] = "herbs",
    [3] = "enchanting",
    [4] = "engineering",
    [5] = "gems",
    [6] = "mining",
    [7] = "skinning", -- Leatherworking bag
    [8] = "inscription",
    [9] = "fishing",
    [10] = "cooking",
}
local ITEM_CLASS_CONTAINER, ITEM_CLASS_QUIVER = 1, 11

BagAPI.BAG_CLASS_LABEL = {
    ammo = "Ammo",
    reagents = "Reagents",
    soul = "Soul",
    herbs = "Herbs",
    enchanting = "Enchanting",
    engineering = "Engineering",
    gems = "Gems",
    mining = "Mining",
    skinning = "Skinning",
    inscription = "Inscription",
    fishing = "Fishing",
    cooking = "Cooking",
}

-- Stable tab order: Ammo -> Reagents -> the rest (spec §6.4).
BagAPI.BAG_CLASS_ORDER = { "ammo", "reagents", "soul", "herbs", "enchanting", "engineering",
    "gems", "mining", "skinning", "inscription", "fishing", "cooking" }

-- Pure: bag item class/subclass -> specialized class key, or nil for a
-- plain bag / unknown. Split out for tests.
function BagAPI.ClassifyBagItem(classID, subClassID)
    if classID == ITEM_CLASS_QUIVER then
        return "ammo"
    end
    if classID == ITEM_CLASS_CONTAINER then
        return CONTAINER_SUBCLASS_TO_CLASS[subClassID]
    end
    return nil
end

-- Last positive GetContainerNumSlots per bagID. Mail/AH scans can report
-- 0 for bags that are still equipped; we keep the known size so Glance
-- cannot collapse from e.g. 66/76 down to a single remaining bag.
BagAPI.lastSlotCount = BagAPI.lastSlotCount or {}

-- Container family bits (ItemAPI:GetItemFamily's return value is a bitmask, not
-- an enum) for the two specialized ammo-storage bag types Classic/TBC
-- actually ship: Quiver (bit 0x2) and Ammo Pouch (bit 0x4). Either one
-- creates an Ammo capacity pool.
local AMMO_BAG_FAMILY_MASK = 2 + 4

-- Returns the number of slots for a given bag ID, or 0 if the bag doesn't exist.
-- Prefers the larger of C_Container and the legacy API: during mailbox/
-- auction-house interaction one of the two can briefly report 0 for bags
-- that are still equipped.
function BagAPI:GetBagSlotCount(bagID)
    local ClientAPI = Pockets.Adapters.ClientAPI
    local modern = 0
    if C_Container and C_Container.GetContainerNumSlots then
        modern = C_Container.GetContainerNumSlots(bagID) or 0
    end
    local legacy = 0
    if GetContainerNumSlots then
        legacy = GetContainerNumSlots(bagID) or 0
    end
    -- Secret/non-numeric counts are unusable: report 0 (unknown) so the
    -- existing cached-size / incomplete-scan protection takes over.
    if type(modern) ~= "number" or ClientAPI:IsSecret(modern) then
        modern = 0
    end
    if type(legacy) ~= "number" or ClientAPI:IsSecret(legacy) then
        legacy = 0
    end
    if modern > legacy then
        return modern
    end
    return legacy
end

-- Resolves a container bagID to its equipped inventory slot ID. Prefers
-- C_Container (the bare global was removed on this client - every other
-- installed addon on this machine, e.g. ItemRack/Syndicator/BagBrother,
-- only ever calls C_Container.ContainerIDToInventoryID). Checking the
-- bare global first left it nil for every non-backpack bag, which made
-- HasEquippedBag/IsAmmoBag silently treat bags 1-4 as never equipped -
-- Glance permanently undercounted capacity to just the backpack.
function BagAPI:ContainerIDToInventoryID(bagID)
    if C_Container and C_Container.ContainerIDToInventoryID then
        return C_Container.ContainerIDToInventoryID(bagID)
    end
    if ContainerIDToInventoryID then
        return ContainerIDToInventoryID(bagID)
    end
    return nil
end

-- True if this bag slot currently has a bag item equipped (backpack always).
function BagAPI:HasEquippedBag(bagID)
    if bagID == 0 then
        return true
    end
    local invSlot = self:ContainerIDToInventoryID(bagID)
    if not invSlot then
        return false
    end
    local bagLink = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
    return bagLink ~= nil
end

-- Pure: pick a slot count when the live API reports 0 for an equipped bag.
-- Unequipped bags drop to 0 (and forget any cache). Equipped bags with a
-- cached size keep that size. Equipped bags with no live count and no
-- cache are incomplete (caller should not clobber a known-good snapshot).
function BagAPI.ResolveSlotCount(apiCount, cachedCount, isEquipped)
    apiCount = apiCount or 0
    cachedCount = cachedCount or 0
    if not isEquipped then
        return 0, false
    end
    if apiCount > 0 then
        return apiCount, false
    end
    if cachedCount > 0 then
        return cachedCount, false
    end
    return 0, true
end

-- Returns a normalized slot info table, or nil if the slot is empty.
-- Shape: { itemID, itemLink, quantity, quality, locked, texture }
function BagAPI:GetSlotInfo(bagID, slotIndex)
    local itemID, itemLink, quantity, quality, locked, texture

    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotIndex)
        if not info then
            return nil
        end
        itemID = info.itemID
        itemLink = info.hyperlink
        quantity = info.stackCount
        quality = info.quality
        locked = info.isLocked
        texture = info.iconFileID
    else
        local icon, count, isLocked, itemQuality
        icon, count, isLocked, itemQuality = GetContainerItemInfo(bagID, slotIndex)
        if not icon then
            return nil
        end
        itemLink = GetContainerItemLink and GetContainerItemLink(bagID, slotIndex)
        quantity = count
        quality = itemQuality
        locked = isLocked
        texture = icon
        itemID = GetContainerItemID and GetContainerItemID(bagID, slotIndex)
    end

    if not itemID then
        return nil
    end

    -- Secret Values can't be summed/compared/indexed. Treat such a slot
    -- as unreadable (skipped) instead of erroring in aggregation.
    local ClientAPI = Pockets.Adapters.ClientAPI
    if ClientAPI:IsSecret(itemID) or ClientAPI:IsSecret(quantity) or ClientAPI:IsSecret(quality) then
        return nil
    end

    return {
        itemID = itemID,
        itemLink = itemLink,
        quantity = quantity or 1,
        quality = quality,
        isLocked = locked and true or false,
        texture = texture,
    }
end

-- Pure bitmask check, split out from IsAmmoBag so the actual detection
-- rule is unit-testable without a live bag/inventory API (bug found here
-- previously: IsAmmoBag was reading GetItemInfo()'s 9th return value -
-- itemEquipLoc, a STRING like "INVTYPE_BAG" - and comparing it to the
-- number 2, which can never be true. Bag family isn't part of
-- GetItemInfo's return list at all; it comes from GetItemFamily()).
function BagAPI:IsAmmoFamily(bagFamily)
    if not bagFamily then
        return false
    end
    if bit and bit.band then
        return bit.band(bagFamily, AMMO_BAG_FAMILY_MASK) ~= 0
    end
    -- bit.band should always be present in the WoW Lua environment; this
    -- is a defensive fallback, not the expected path.
    return bagFamily == 2 or bagFamily == 4
end

-- Returns whether the given bagID is an ammo pouch/quiver, using the
-- bag's item family (GetItemFamily - see IsAmmoFamily's note for the bug
-- this replaced). Treats unknown/undetectable bag families conservatively
-- as non-ammo rather than ammo (TDD §22 Error Handling).
function BagAPI:IsAmmoBag(bagID)
    if bagID == 0 then
        return false -- backpack is never a specialized bag
    end

    local invSlot = self:ContainerIDToInventoryID(bagID)
    if not invSlot then
        return false
    end

    local bagLink = GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
    if not bagLink then
        return false
    end

    local bagFamily = Pockets.Adapters.ItemAPI:GetItemFamily(bagLink)
    return self:IsAmmoFamily(bagFamily)
end

-- Specialized class key for an equipped bag ("ammo", "reagents", "herbs",
-- ...), or nil for the backpack / a plain bag. Treats unknown/undetectable
-- bags conservatively as plain (general), except the dedicated reagent slot,
-- which is always "reagents" (spec §2: never mislabel; generic Reagents if
-- the bag type cannot be identified).
function BagAPI:GetBagClass(bagID)
    if bagID == 0 then
        return nil
    end
    if bagID == self:GetReagentBagID() then
        return "reagents"
    end
    local invSlot = self:ContainerIDToInventoryID(bagID)
    local bagLink = invSlot and GetInventoryItemLink and GetInventoryItemLink("player", invSlot)
    if not bagLink then
        return nil
    end
    local classID, subClassID = Pockets.Adapters.ItemAPI:GetInstantClass(bagLink)
    local byItem = self.ClassifyBagItem(classID, subClassID)
    if byItem then
        return byItem
    end
    if self:IsAmmoBag(bagID) then
        return "ammo"
    end
    return nil
end

-- Icon of the equipped bag item itself (exact art, never a guessed path).
function BagAPI:GetBagTexture(bagID)
    local invSlot = self:ContainerIDToInventoryID(bagID)
    if invSlot and GetInventoryItemTexture then
        return GetInventoryItemTexture("player", invSlot)
    end
    return nil
end

-- Enumerates every bag currently equipped (backpack + all four bag slots),
-- returning { bagID = ..., slotCount = ... } for bags with a known size.
-- Second return is true when at least one equipped bag has no live slot
-- count and no cached size - InventoryState should skip applying that
-- partial scan over a known-good snapshot.
function BagAPI:GetEquippedBags()
    local bags = {}
    local incomplete = false
    for _, bagID in ipairs(self:GetScannedBagIDs()) do
        local apiCount = self:GetBagSlotCount(bagID)
        local equipped = self:HasEquippedBag(bagID)
        local slotCount, bagIncomplete = self.ResolveSlotCount(
            apiCount, self.lastSlotCount[bagID], equipped)

        if not equipped then
            self.lastSlotCount[bagID] = nil
        elseif apiCount > 0 then
            self.lastSlotCount[bagID] = apiCount
        end

        if bagIncomplete then
            incomplete = true
        elseif slotCount > 0 then
            table.insert(bags, { bagID = bagID, slotCount = slotCount })
        end
    end
    return bags, incomplete
end

-- Takes a full scan snapshot of all equipped bags.
-- Returns an array of { bagID, slotIndex, itemID, itemLink, quantity, quality, isLocked, texture, capacityClass }.
function BagAPI:ScanAllBags()
    local snapshot = {}
    local bags, incomplete = self:GetEquippedBags()
    for _, bag in ipairs(bags) do
        local capacityClass = self:GetBagClass(bag.bagID) == "ammo"
            and Pockets.Constants.CAPACITY_CLASS.AMMO
            or Pockets.Constants.CAPACITY_CLASS.GENERAL

        for slotIndex = 1, bag.slotCount do
            local slot = self:GetSlotInfo(bag.bagID, slotIndex)
            if slot then
                slot.bagID = bag.bagID
                slot.slotIndex = slotIndex
                slot.capacityClass = capacityClass
                table.insert(snapshot, slot)
            end
        end
    end
    return snapshot, incomplete
end

-- Pure aggregation step, split out from GetCapacityCounts so the class
-- split is unit-testable without a live bag scan (TESTING_GUIDE.md).
-- bagEntries: array of { bagClass (nil = general, else a BAG_CLASS key),
-- slotCount, usedSlots, bagID?, texture? }. Legacy `isAmmo` is still
-- honored. `general` counts ONLY plain bags - ammo, reagents and
-- profession bags are reported separately (never double-counted);
-- `specialized[key]` carries one pool per class with merged capacities.
function BagAPI:ClassifyCapacity(bagEntries)
    local generalUsed, generalTotal = 0, 0
    local ammoUsed, ammoTotal = 0, 0
    local specialized = {}

    for _, entry in ipairs(bagEntries) do
        local bagClass = entry.bagClass or (entry.isAmmo and "ammo" or nil)
        if bagClass == nil then
            generalTotal = generalTotal + entry.slotCount
            generalUsed = generalUsed + entry.usedSlots
        else
            local pool = specialized[bagClass]
            if not pool then
                pool = { used = 0, total = 0, bagIDs = {} }
                specialized[bagClass] = pool
            end
            pool.total = pool.total + entry.slotCount
            pool.used = pool.used + entry.usedSlots
            if entry.bagID then
                table.insert(pool.bagIDs, entry.bagID)
            end
            pool.texture = pool.texture or entry.texture
            if bagClass == "ammo" then
                ammoTotal = ammoTotal + entry.slotCount
                ammoUsed = ammoUsed + entry.usedSlots
            end
        end
    end

    return {
        general = { used = generalUsed, total = generalTotal },
        ammo = { used = ammoUsed, total = ammoTotal },
        specialized = specialized,
    }
end

-- Returns { general = {used,total}, ammo = {used,total}, specialized =
-- { [class] = {used,total,bagIDs,texture} } } slot counts. Classes are
-- keyed off the equipped bag itself (GetBagClass), never off what item
-- category is carried (PRD §3.9, TDD §7).
function BagAPI:GetCapacityCounts()
    local bagEntries = {}
    for _, bag in ipairs(self:GetEquippedBags()) do
        local bagClass = self:GetBagClass(bag.bagID)
        table.insert(bagEntries, {
            bagClass = bagClass,
            bagID = bag.bagID,
            texture = bagClass and self:GetBagTexture(bag.bagID) or nil,
            slotCount = bag.slotCount,
            usedSlots = self:CountUsedSlots(bag.bagID, bag.slotCount),
        })
    end
    return self:ClassifyCapacity(bagEntries)
end

function BagAPI:CountUsedSlots(bagID, slotCount)
    local used = 0
    for slotIndex = 1, slotCount do
        if self:GetSlotInfo(bagID, slotIndex) then
            used = used + 1
        end
    end
    return used
end

--------------------------------------------------
-- Real item-button interactions (UI_SPEC §8)
--
-- Item icons rendered by Pockets must be real, clickable, draggable item
-- buttons backed by their current bag+slot - not decorative textures.
-- These wrappers are the only place button click/drag/tooltip code is
-- allowed to reach into bag APIs (keeps the rule in the file header true).
--------------------------------------------------

-- True when item buttons must run right-click use through Blizzard's
-- SECURE action handler (type2="item", item2="<bag> <slot>") instead of
-- ContainerFrameItemButtonTemplate's own Lua OnClick. On WoW Forever the
-- latter is blocked for protected item use ("Pockets has been blocked from
-- an action only available to the Blizzard UI" on consumables). Classic/
-- TBC keep the existing, working template path.
function BagAPI:UsesSecureItemAttributes()
    return Pockets.Adapters.ClientAPI:IsForever()
end

-- Left-click/drag-start behavior: picks the item up onto the cursor (or
-- swaps with whatever's already on the cursor) - identical to Blizzard's
-- own ContainerFrameItemButton_OnClick/OnDragStart.
function BagAPI:PickupItem(bagID, slotIndex)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bagID, slotIndex)
    else
        PickupContainerItem(bagID, slotIndex)
    end
end

-- Right-click behavior: normal WoW "use" semantics (equip/consume/open/etc).
function BagAPI:UseItem(bagID, slotIndex)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bagID, slotIndex)
    else
        UseContainerItem(bagID, slotIndex)
    end
end

-- Shift+left-click-drag split-stack behavior, called back by
-- OpenStackSplitFrame once the player confirms a split amount.
function BagAPI:SplitStack(bagID, slotIndex, amount)
    if C_Container and C_Container.SplitContainerItem then
        C_Container.SplitContainerItem(bagID, slotIndex, amount)
    else
        SplitContainerItem(bagID, slotIndex, amount)
    end
end

-- True while a chat edit box is open/focused (shift-click should link).
-- Tries the legacy global, the modern ChatFrameUtil, then the keyboard
-- focus itself (chat edit boxes carry a .chatFrame field).
function BagAPI:IsChatEditActive()
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
        return true
    end
    if ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow() then
        return true
    end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    return focus ~= nil and focus.chatFrame ~= nil
end

function BagAPI:CanSplit()
    return OpenStackSplitFrame ~= nil or (StackSplitFrame ~= nil and StackSplitFrame.OpenStackSplitFrame ~= nil)
end

-- Opens Blizzard's stack-split dialog for `owner` (which must implement
-- :SplitStack(amount)). The bare OpenStackSplitFrame global is gone on
-- modern clients (Forever); the dialog is a method on StackSplitFrame.
-- Returns false when no split dialog is available.
function BagAPI:OpenSplitFrame(maxQuantity, owner, anchor, anchorTo)
    if OpenStackSplitFrame then
        OpenStackSplitFrame(maxQuantity, owner, anchor, anchorTo)
        return true
    end
    if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
        StackSplitFrame:OpenStackSplitFrame(maxQuantity, owner, anchor, anchorTo)
        return true
    end
    return false
end

-- Shift-click/ctrl-click/etc: delegates to Blizzard's own modified-click
-- handler (chat link, delete-confirm, etc.) rather than reimplementing it.
function BagAPI:HandleModifiedItemClick(itemLink)
    if itemLink and HandleModifiedItemClick then
        HandleModifiedItemClick(itemLink)
    end
end

-- Points a GameTooltip at the live item in a bag/slot (shows durability,
-- comparison, etc. - richer than a plain SetHyperlink). SetBagItem is a
-- stable GameTooltip method, not a container-API call, so no branching.
function BagAPI:SetTooltipToBagItem(tooltip, bagID, slotIndex)
    tooltip:SetBagItem(bagID, slotIndex)
end
