--[[
    RepTurninCatalog.lua - Rules for reputation turn-in items.

    This is used for shadow rep-potential metrics and valuation routing.
]]

local pH_RepTurninCatalog = {}

-- Rule shape:
-- itemID = {
--   factionKey = string, bundleSize = number, repPerBundle = number, ahPreferred = bool,
--   turninNpc = string, turninZone = string, turninMethod = string, repeatable = bool
-- }
local RULES = {
    [25719] = {
        factionKey = "Lower City", bundleSize = 30, repPerBundle = 250, ahPreferred = true,
        turninNpc = "Vekax", turninZone = "Shattrath City", turninMethod = "Item hand-in", repeatable = true,
    }, -- Arakkoa Feather
    [30809] = {
        factionKey = "Aldor", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
        turninNpc = "Adyen the Lightwarden", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
    }, -- Mark of Sargeras
    [29425] = {
        factionKey = "Aldor", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
        turninNpc = "Adyen the Lightwarden", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
    }, -- Mark of Kil'jaeden
}

local NAME_RULES = {
    ["arakkoa feather"] = RULES[25719],
    ["mark of sargeras"] = RULES[30809],
    ["mark of kil'jaeden"] = RULES[29425],
    ["mark of the kil'jaeden"] = RULES[29425], -- common naming typo
}

local function NormalizeName(itemName)
    if not itemName then
        return nil
    end
    local s = string.lower(tostring(itemName))
    s = s:gsub("’", "'")
    s = s:gsub("[^%w%s']", " ")
    s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

function pH_RepTurninCatalog:IsRepTurninItem(itemID, itemName)
    if itemID and RULES[itemID] then
        return true
    end
    local key = NormalizeName(itemName)
    return key and NAME_RULES[key] ~= nil
end

function pH_RepTurninCatalog:GetRepRule(itemID, itemName)
    if itemID and RULES[itemID] then
        return RULES[itemID]
    end
    local key = NormalizeName(itemName)
    if key then
        return NAME_RULES[key]
    end
    return nil
end

function pH_RepTurninCatalog:GetAllRules()
    return RULES
end

_G.pH_RepTurninCatalog = pH_RepTurninCatalog
