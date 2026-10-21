--[[
    Adapters/ItemAPI.lua - Isolates direct item-info lookups (TDD §3.1, §9)

    Normalizes GetItemInfo's asynchronous/nil-until-cached behavior into a
    small metadata cache with a "pending" state, so the rest of Pockets
    never has to special-case missing item data.
]]

local _, Pockets = ...

Pockets.Adapters.ItemAPI = Pockets.Adapters.ItemAPI or {}
local ItemAPI = Pockets.Adapters.ItemAPI

-- ItemCache[itemID] = { status = "ready" | "pending", name, quality, classID, subclassID, maxStack, texture, itemLink }
ItemAPI.ItemCache = ItemAPI.ItemCache or {}

-- Raw item-info lookup: C_Item on modern clients (Forever), legacy global
-- on Classic/TBC. Same return order on both. Returns nothing when the
-- client hasn't cached the item yet.
function ItemAPI:RawGetItemInfo(itemLinkOrID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemLinkOrID)
    end
    if GetItemInfo then
        return GetItemInfo(itemLinkOrID)
    end
    return nil
end

-- Item family bitmask (bag type for bag items). Nil when unavailable.
function ItemAPI:GetItemFamily(itemLinkOrID)
    if not itemLinkOrID then
        return nil
    end
    local family
    if C_Item and C_Item.GetItemFamily then
        family = C_Item.GetItemFamily(itemLinkOrID)
    elseif GetItemFamily then
        family = GetItemFamily(itemLinkOrID)
    end
    if Pockets.Adapters.ClientAPI:IsSecret(family) then
        return nil
    end
    return family
end

-- classID, subClassID for an item/link without needing it cached (the
-- "instant" lookup). Nil when unavailable or Secret.
function ItemAPI:GetInstantClass(itemLinkOrID)
    if not itemLinkOrID then
        return nil
    end
    local classID, subClassID
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, c, sc = C_Item.GetItemInfoInstant(itemLinkOrID)
        classID, subClassID = c, sc
    elseif GetItemInfoInstant then
        local _, _, _, _, _, c, sc = GetItemInfoInstant(itemLinkOrID)
        classID, subClassID = c, sc
    end
    local ClientAPI = Pockets.Adapters.ClientAPI
    if type(classID) ~= "number" or ClientAPI:IsSecret(classID) or ClientAPI:IsSecret(subClassID) then
        return nil
    end
    return classID, subClassID
end

-- Asks the client to load item data; the answer arrives later via
-- GET_ITEM_INFO_RECEIVED. Legacy GetItemInfo already queues the request.
function ItemAPI:RequestItemData(itemID)
    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Returns cached metadata for an item, requesting it from the WoW API if
-- not already cached. Never blocks; returns a pending entry when the
-- client hasn't cached the item yet.
function ItemAPI:GetItemMetadata(itemID, itemLink)
    if not itemID then
        return nil
    end

    local cached = self.ItemCache[itemID]
    if cached and cached.status == "ready" then
        return cached
    end

    local name, link, quality, _, _, itemClass, itemSubClass, maxStack, _, texture, _, classID, subclassID,
        _, _, _, isCraftingReagent = self:RawGetItemInfo(itemLink or itemID)

    -- A Secret Value anywhere in the fields Pockets compares/sorts/indexes
    -- means the metadata is unusable: stay pending rather than error.
    local ClientAPI = Pockets.Adapters.ClientAPI
    if name and (ClientAPI:IsSecret(name) or ClientAPI:IsSecret(quality)
        or ClientAPI:IsSecret(classID) or ClientAPI:IsSecret(subclassID)
        or ClientAPI:IsSecret(maxStack)) then
        name = nil
    end

    if not name then
        self:RequestItemData(itemID)
        if not cached then
            self.ItemCache[itemID] = { status = "pending" }
        end
        return self.ItemCache[itemID]
    end

    local entry = {
        status = "ready",
        name = name,
        itemLink = link,
        quality = quality,
        classID = classID,
        subclassID = subclassID,
        itemClass = itemClass,
        itemSubClass = itemSubClass,
        maxStack = maxStack,
        texture = texture,
        isCraftingReagent = isCraftingReagent,
    }
    self.ItemCache[itemID] = entry
    return entry
end

-- Returns true if the item's metadata is not yet resolved.
function ItemAPI:IsPending(itemID)
    local cached = self.ItemCache[itemID]
    return cached == nil or cached.status == "pending"
end

-- Icon texture for an item, or nil if the client can't resolve it yet.
-- Prefers already-cached metadata; GetItemIcon needs no item-cache round
-- trip for most items, so Loot Log rows get their icon immediately.
function ItemAPI:GetIcon(itemID)
    if not itemID then
        return nil
    end
    local cached = self.ItemCache[itemID]
    if cached and cached.status == "ready" and cached.texture then
        return cached.texture
    end
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    end
    return GetItemIcon and GetItemIcon(itemID) or nil
end

-- Clears the metadata cache. Intended for tests/debug only.
function ItemAPI:ResetCache()
    self.ItemCache = {}
end
