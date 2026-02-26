--[[
    EnchantingCatalog.lua - Enchanting material identification

    Provides a curated itemID catalog plus runtime fallback checks so
    enchanting materials can be routed to the dedicated enchanting bucket.
]]

local pH_EnchantingCatalog = {}

-- Item class constants
local CLASS_TRADE_GOODS = 7

-- Curated list of classic/tbc enchanting materials
local MAT_IDS = {
    -- Dusts
    [10940] = true, -- Strange Dust
    [11083] = true, -- Soul Dust
    [11137] = true, -- Vision Dust
    [11176] = true, -- Dream Dust
    [16204] = true, -- Illusion Dust
    [22445] = true, -- Arcane Dust

    -- Essences
    [10938] = true, -- Lesser Magic Essence
    [10939] = true, -- Greater Magic Essence
    [10998] = true, -- Lesser Astral Essence
    [11082] = true, -- Greater Astral Essence
    [11134] = true, -- Lesser Mystic Essence
    [11135] = true, -- Greater Mystic Essence
    [11174] = true, -- Lesser Nether Essence
    [11175] = true, -- Greater Nether Essence
    [16202] = true, -- Lesser Eternal Essence
    [16203] = true, -- Greater Eternal Essence
    [22446] = true, -- Greater Planar Essence
    [22447] = true, -- Lesser Planar Essence

    -- Shards
    [10978] = true, -- Small Glimmering Shard
    [11084] = true, -- Large Glimmering Shard
    [11138] = true, -- Small Glowing Shard
    [11139] = true, -- Large Glowing Shard
    [14343] = true, -- Small Brilliant Shard
    [14344] = true, -- Large Brilliant Shard
    [22448] = true, -- Small Prismatic Shard
    [22449] = true, -- Large Prismatic Shard

    -- Crystals
    [20725] = true, -- Nexus Crystal
    [22450] = true, -- Void Crystal
}

local function NameLooksEnchantingMat(itemName)
    if type(itemName) ~= "string" then
        return false
    end

    local lower = itemName:lower()
    return lower:find("dust", 1, true) ~= nil
        or lower:find("essence", 1, true) ~= nil
        or lower:find("shard", 1, true) ~= nil
        or lower:find("crystal", 1, true) ~= nil
end

function pH_EnchantingCatalog:IsEnchantingMat(itemID, itemClass, itemSubClass, itemName)
    if itemID and MAT_IDS[itemID] then
        return true
    end

    -- Runtime fallback: trade goods with recognizable enchanting material naming
    if itemClass == CLASS_TRADE_GOODS and NameLooksEnchantingMat(itemName) then
        return true
    end

    return false
end

function pH_EnchantingCatalog:GetAllKnownMats()
    return MAT_IDS
end

_G.pH_EnchantingCatalog = pH_EnchantingCatalog
