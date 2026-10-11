-- pH_API.lua
-- Client compatibility boundary (Classic Anniversary / WoW Forever).
-- Only wraps APIs that actually differ between clients. Domain modules call
-- pH_API and stay unaware of which client they run on.

-- luacheck: globals GetBuildInfo GetMoney UnitXP UnitXPMax UnitLevel GetMaxPlayerLevel GetNumFactions GetFactionInfo GetAddOnMetadata C_AddOns C_Reputation NUM_BAG_SLOTS NUM_REAGENTBAG_SLOTS hooksecurefunc UseContainerItem C_Spell C_Item GetItemInfo GetItemCount GetSpellInfo issecretvalue

pH_API = {}

local FOREVER_MIN_TOC = 160000

local clientType -- "forever" | "classic" | "unknown"

local function DetectClient()
    if clientType then return clientType end
    local toc = 0
    if GetBuildInfo then
        local _, _, _, tocVersion = GetBuildInfo()
        toc = tonumber(tocVersion) or 0
    end
    if toc >= FOREVER_MIN_TOC then
        clientType = "forever"
    elseif toc > 0 then
        clientType = "classic"
    else
        clientType = "unknown"
    end
    return clientType
end

function pH_API:IsForever() return DetectClient() == "forever" end
function pH_API:IsClassic() return DetectClient() == "classic" end

-- Secret values cannot be used in arithmetic/comparison. Return nil for them.
local function SafeNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

function pH_API:GetMoney()
    return SafeNumber(GetMoney and GetMoney()) or 0
end

function pH_API:GetXP()
    return SafeNumber(UnitXP and UnitXP("player")) or 0
end

function pH_API:GetXPMax()
    return SafeNumber(UnitXPMax and UnitXPMax("player")) or 0
end

function pH_API:GetPlayerLevel()
    return SafeNumber(UnitLevel and UnitLevel("player")) or 0
end

-- default: value to use when the client cannot report a max level
function pH_API:GetMaxPlayerLevel(default)
    local v = GetMaxPlayerLevel and SafeNumber(GetMaxPlayerLevel())
    return v or default or 60
end

function pH_API:GetAddonMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata(addon, field)
    end
    return nil
end

-- Normalized reputation list (same visible-entry semantics as the legacy API):
-- { { factionID, name, standingID, current, min, max, isHeader }, ... }
function pH_API:GetReputations()
    local list = {}

    if GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() or 0 do
            local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, _, _, _, factionID = GetFactionInfo(i)
            list[#list + 1] = {
                factionID = factionID,
                name = name,
                standingID = standingID,
                current = barValue,
                min = barMin,
                max = barMax,
                isHeader = isHeader and true or false,
            }
        end
        return list
    end

    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() or 0 do
            local d = C_Reputation.GetFactionDataByIndex(i)
            if d then
                list[#list + 1] = {
                    factionID = d.factionID,
                    name = d.name,
                    standingID = d.reaction,
                    current = SafeNumber(d.currentStanding),
                    min = SafeNumber(d.currentReactionThreshold),
                    max = SafeNumber(d.nextReactionThreshold),
                    isHeader = d.isHeader and true or false,
                }
            end
        end
    end
    return list
end

-- Spell name from spell ID (GetSpellInfo was removed on Forever).
function pH_API:GetSpellName(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    if GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
    return nil
end

-- Same return signature as the classic GetItemInfo.
function pH_API:GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(item)
    end
    if GetItemInfo then
        return GetItemInfo(item)
    end
    return nil
end

function pH_API:GetItemCount(item, includeBank)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(item, includeBank)
    end
    if GetItemCount then
        return GetItemCount(item, includeBank)
    end
    return 0
end

-- True if v is a Secret Value (unusable for arithmetic/comparison/indexing).
function pH_API:IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

-- Ask the client to load item data; GET_ITEM_INFO_RECEIVED fires when ready.
-- Returns true if a request was made, false if unsupported on this client.
function pH_API:RequestItemData(itemID)
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
        return true
    end
    return false
end

-- Highest bag index to scan (backpack 0, bags 1..N, plus reagent bag on Forever).
function pH_API:GetLastBagIndex()
    return (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0)
end

-- Hook container item use (global on Classic, C_Container on Forever).
function pH_API:HookUseContainerItem(fn)
    if not hooksecurefunc then return false end
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", fn)
        return true
    end
    if UseContainerItem then
        hooksecurefunc("UseContainerItem", fn)
        return true
    end
    return false
end
