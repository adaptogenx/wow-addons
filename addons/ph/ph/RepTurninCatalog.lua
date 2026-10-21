--[[
    RepTurninCatalog.lua - Rules for reputation turn-in items.

    TBC-focused repeatable turn-ins with standing-aware metadata.
]]

local pH_RepTurninCatalog = {}

-- Rule shape:
-- {
--   factionKey = string,
--   bundleSize = number,
--   repPerBundle = number,
--   ahPreferred = bool,
--   minStanding = string|number|nil,
--   maxStanding = string|number|nil,
--   turninNpc = string,
--   turninZone = string,
--   turninMethod = string,
--   repeatable = bool,
-- }

local function CloneRules(rules)
    local out = {}
    for i, rule in ipairs(rules or {}) do
        local copy = {}
        for k, v in pairs(rule) do
            copy[k] = v
        end
        out[i] = copy
    end
    return out
end

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

local CATALOG = {
    {
        ids = {25719},
        names = {"Arakkoa Feather"},
        rules = {
            {
                factionKey = "Lower City", bundleSize = 30, repPerBundle = 250, ahPreferred = true,
                turninNpc = "Vekax", turninZone = "Shattrath City", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Aldor
    {
        ids = {29425},
        names = {"Mark of Kil'jaeden", "Mark of the Kil'jaeden"},
        rules = {
            {
                factionKey = "The Aldor", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Adyen the Lightwarden", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {30809},
        names = {"Mark of Sargeras"},
        rules = {
            {
                factionKey = "The Aldor", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                turninNpc = "Adyen the Lightwarden", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {29740},
        names = {"Fel Armament"},
        rules = {
            {
                factionKey = "The Aldor", bundleSize = 1, repPerBundle = 350, ahPreferred = true,
                turninNpc = "Ishanah", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {29444},
        names = {"Dreadfang Venom Sac"},
        rules = {
            {
                factionKey = "The Aldor", bundleSize = 8, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Veynna Dawnstar", turninZone = "Shattrath City (Aldor Rise)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Scryers
    {
        ids = {29426},
        names = {"Firewing Signet"},
        rules = {
            {
                factionKey = "The Scryers", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Magister Fyalenn", turninZone = "Shattrath City (Scryer's Tier)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {30810},
        names = {"Sunfury Signet"},
        rules = {
            {
                factionKey = "The Scryers", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                turninNpc = "Magister Fyalenn", turninZone = "Shattrath City (Scryer's Tier)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {29739},
        names = {"Arcane Tome"},
        rules = {
            {
                factionKey = "The Scryers", bundleSize = 1, repPerBundle = 350, ahPreferred = true,
                turninNpc = "Vor'en'thal the Seer", turninZone = "Shattrath City (Scryer's Tier)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {},
        names = {"Dampscale Basilisk Eye"},
        rules = {
            {
                factionKey = "The Scryers", bundleSize = 8, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Arcanist Adyria", turninZone = "Shattrath City (Scryer's Tier)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Sha'tari Skyguard
    {
        ids = {},
        names = {"Shadow Dust"},
        rules = {
            {
                factionKey = "Sha'tari Skyguard", bundleSize = 6, repPerBundle = 150, ahPreferred = true,
                turninNpc = "Severin", turninZone = "Terokkar Forest (Blackwind Landing)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Netherwing
    {
        ids = {},
        names = {"Netherwing Egg"},
        rules = {
            {
                factionKey = "Netherwing", bundleSize = 1, repPerBundle = 250, ahPreferred = false,
                turninNpc = "Yarzill the Merc", turninZone = "Shadowmoon Valley", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Cenarion Expedition
    {
        ids = {},
        names = {"Unidentified Plant Parts"},
        rules = {
            {
                factionKey = "Cenarion Expedition", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Lauranna Thar'well", turninZone = "Zangarmarsh (Cenarion Refuge)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {24368},
        names = {"Coilfang Armaments"},
        rules = {
            {
                factionKey = "Cenarion Expedition", bundleSize = 1, repPerBundle = 75, ahPreferred = true,
                turninNpc = "Ysiel Windsinger", turninZone = "Zangarmarsh (Cenarion Refuge)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Sporeggar
    {
        ids = {24291},
        names = {"Bog Lord Tendril"},
        rules = {
            {
                factionKey = "Sporeggar", bundleSize = 6, repPerBundle = 750, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Fahssn", turninZone = "Zangarmarsh (Sporeggar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {24290},
        names = {"Mature Spore Sac"},
        rules = {
            {
                factionKey = "Sporeggar", bundleSize = 10, repPerBundle = 750, ahPreferred = true,
                turninNpc = "Gshaff", turninZone = "Zangarmarsh (Sporeggar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {},
        names = {"Fertile Spores"},
        rules = {
            {
                factionKey = "Sporeggar", bundleSize = 6, repPerBundle = 750, ahPreferred = true,
                maxStanding = "Friendly",
                turninNpc = "Fahssn", turninZone = "Zangarmarsh (Sporeggar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {24246},
        names = {"Sanguine Hibiscus"},
        rules = {
            {
                factionKey = "Sporeggar", bundleSize = 1, repPerBundle = 750, ahPreferred = false,
                turninNpc = "Gzhun'tt", turninZone = "Zangarmarsh (Sporeggar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {24245},
        names = {"Glowcap"},
        rules = {
            {
                factionKey = "Sporeggar", bundleSize = 10, repPerBundle = 750, ahPreferred = true,
                maxStanding = "Friendly",
                turninNpc = "Msshi'fn", turninZone = "Zangarmarsh (Sporeggar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },

    -- Consortium
    {
        ids = {},
        names = {"Zaxxis Insignia"},
        rules = {
            {
                factionKey = "The Consortium", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                maxStanding = "Honored",
                turninNpc = "Consortium Recruiter", turninZone = "Netherstorm (Area 52)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {},
        names = {"Oshu'gun Crystal Fragment", "Oshu'gun Crystal Fragments"},
        rules = {
            {
                factionKey = "The Consortium", bundleSize = 10, repPerBundle = 250, ahPreferred = true,
                turninNpc = "Hataaru", turninZone = "Nagrand (Aerist Landing)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {29460},
        names = {"Ethereum Prisoner I.D. Tag"},
        rules = {
            {
                factionKey = "The Consortium", bundleSize = 1, repPerBundle = 500, ahPreferred = true,
                turninNpc = "Nether-Stalker Khay'ji", turninZone = "Netherstorm (Area 52)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
    {
        ids = {25433},
        names = {"Obsidian Warbeads"},
        rules = {
            {
                factionKey = "The Consortium", bundleSize = 10, repPerBundle = 500, ahPreferred = true,
                turninNpc = "Hataaru", turninZone = "Nagrand (Aerist Landing)", turninMethod = "Item hand-in", repeatable = true,
            },
            {
                factionKey = "Kurenai", bundleSize = 10, repPerBundle = 500, ahPreferred = true,
                turninNpc = "Warden Moi'bff Jill", turninZone = "Nagrand (Telaar)", turninMethod = "Item hand-in", repeatable = true,
            },
            {
                factionKey = "The Mag'har", bundleSize = 10, repPerBundle = 500, ahPreferred = true,
                turninNpc = "Warden Bullrok", turninZone = "Nagrand (Garadar)", turninMethod = "Item hand-in", repeatable = true,
            },
        },
    },
}

local RULES_BY_ID = {}
local RULES_BY_NAME = {}

for _, entry in ipairs(CATALOG) do
    local rulesCopy = CloneRules(entry.rules)
    for _, itemID in ipairs(entry.ids or {}) do
        RULES_BY_ID[itemID] = { rules = CloneRules(rulesCopy) }
    end
    for _, itemName in ipairs(entry.names or {}) do
        local key = NormalizeName(itemName)
        if key then
            RULES_BY_NAME[key] = { rules = CloneRules(rulesCopy) }
        end
    end
end

function pH_RepTurninCatalog:IsRepTurninItem(itemID, itemName)
    if itemID and RULES_BY_ID[itemID] then
        return true
    end
    local key = NormalizeName(itemName)
    return key and RULES_BY_NAME[key] ~= nil
end

function pH_RepTurninCatalog:GetRepRules(itemID, itemName)
    if itemID and RULES_BY_ID[itemID] then
        return CloneRules(RULES_BY_ID[itemID].rules)
    end
    local key = NormalizeName(itemName)
    if key and RULES_BY_NAME[key] then
        return CloneRules(RULES_BY_NAME[key].rules)
    end
    return nil
end

function pH_RepTurninCatalog:GetPreferredRepRule(itemID, itemName, playerFactionHint)
    local rules = self:GetRepRules(itemID, itemName)
    if not rules or #rules == 0 then
        return nil
    end
    if playerFactionHint then
        local hint = NormalizeName(playerFactionHint)
        for _, rule in ipairs(rules) do
            local key = NormalizeName(rule.factionKey)
            if key and hint and key == hint then
                return rule
            end
        end
    end
    for _, rule in ipairs(rules) do
        if rule.ahPreferred then
            return rule
        end
    end
    return rules[1]
end

-- Backward-compatible shim for existing callsites.
function pH_RepTurninCatalog:GetRepRule(itemID, itemName, playerFactionHint)
    return self:GetPreferredRepRule(itemID, itemName, playerFactionHint)
end

function pH_RepTurninCatalog:GetAllRules()
    return {
        byID = RULES_BY_ID,
        byName = RULES_BY_NAME,
    }
end

_G.pH_RepTurninCatalog = pH_RepTurninCatalog
