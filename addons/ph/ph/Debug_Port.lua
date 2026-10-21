-- Debug_Port.lua - In-game self-tests for the client compatibility layer (Classic / Forever).
-- Run via /ph test run. Non-destructive: no sessions are created; DB fields are restored.

-- luacheck: globals pH_Debug pH_API pH_Events pH_DB_Account pH_EnsureAccountDB

local function Result(name, passed, message)
    pH_Debug:LogTestResult(name, passed, message)
    return { name = name, passed = passed, message = message }
end

local function Guard(name, fn)
    local ok, passed, message = pcall(fn)
    if not ok then
        return Result(name, false, "Lua error: " .. tostring(passed))
    end
    return Result(name, passed, message)
end

function pH_Debug:Test_Port_ClientDetection()
    return Guard("Port: Client Detection", function()
        local forever, classic = pH_API:IsForever(), pH_API:IsClassic()
        local _, _, _, toc = GetBuildInfo()
        local ok = (forever or classic) and not (forever and classic)
        return ok, string.format("toc=%s forever=%s classic=%s", tostring(toc), tostring(forever), tostring(classic))
    end)
end

function pH_Debug:Test_Port_PlayerAPIs()
    return Guard("Port: Money/XP/Level", function()
        local money, xp, xpMax = pH_API:GetMoney(), pH_API:GetXP(), pH_API:GetXPMax()
        local level, maxLevel = pH_API:GetPlayerLevel(), pH_API:GetMaxPlayerLevel(60)
        local ok = type(money) == "number" and type(xp) == "number" and type(xpMax) == "number"
            and level >= 1 and maxLevel >= level and (level >= maxLevel or xpMax > 0)
        return ok, string.format("money=%d xp=%d/%d level=%d/%d", money, xp, xpMax, level, maxLevel)
    end)
end

function pH_Debug:Test_Port_Metadata()
    return Guard("Port: Addon Metadata", function()
        local v = pH_API:GetAddonMetadata("ph", "Version") or pH_API:GetAddonMetadata("pH", "Version")
        return type(v) == "string" and v ~= "", "Version=" .. tostring(v)
    end)
end

function pH_Debug:Test_Port_Reputations()
    return Guard("Port: Reputation Normalization", function()
        local reps = pH_API:GetReputations()
        if type(reps) ~= "table" then return false, "not a table" end
        local factions, bad = 0, 0
        for _, r in ipairs(reps) do
            if not r.isHeader then
                factions = factions + 1
                if not (r.name and r.factionID and type(r.current) == "number") then bad = bad + 1 end
            end
        end
        return bad == 0, string.format("entries=%d factions=%d malformed=%d", #reps, factions, bad)
    end)
end

function pH_Debug:Test_Port_ItemAPIs()
    return Guard("Port: Item/Spell APIs", function()
        -- 6948 = Hearthstone, 8690 = Hearthstone spell. Uncached info may be nil; only errors/type failures fail.
        local name, _, quality = pH_API:GetItemInfo(6948)
        local count = pH_API:GetItemCount(6948)
        local spell = pH_API:GetSpellName(8690)
        local ok = type(count) == "number" and (name == nil or type(quality) == "number")
            and (spell == nil or type(spell) == "string")
        return ok, string.format("item=%s count=%s spell=%s", tostring(name), tostring(count), tostring(spell))
    end)
end

function pH_Debug:Test_Port_BagScan()
    return Guard("Port: Bag Scan vs Item Count", function()
        local snap = pH_Events:SnapshotBags()
        if type(snap) ~= "table" then return false, "no snapshot" end
        local items, mismatches, checked = 0, 0, 0
        for itemID, count in pairs(snap) do
            items = items + 1
            if type(itemID) ~= "number" or type(count) ~= "number" or count <= 0 then
                mismatches = mismatches + 1
            elseif checked < 5 then
                checked = checked + 1
                -- Bag scan covers bags only (no bank), matching includeBank=false
                if pH_API:GetItemCount(itemID, false) ~= count then mismatches = mismatches + 1 end
            end
        end
        return mismatches == 0, string.format("distinct=%d lastBag=%d checked=%d mismatches=%d",
            items, pH_API:GetLastBagIndex(), checked, mismatches)
    end)
end

function pH_Debug:Test_Port_SecretGuard()
    return Guard("Port: Secret Value Guard", function()
        local ok = pH_API:IsSecret(5) == false and pH_API:IsSecret(nil) == false and pH_API:IsSecret("x") == false
        return ok, "plain values are not secret; issecretvalue=" .. tostring(issecretvalue ~= nil)
    end)
end

function pH_Debug:Test_Port_DBRepair()
    return Guard("Port: SavedVariables Repair", function()
        if not pH_EnsureAccountDB then return false, "pH_EnsureAccountDB not exported" end
        local db = pH_DB_Account
        local saved = { db.activeSessions, db.priceOverrides, db.debug, db.meta.lastSessionId }
        local maxId = 0
        for id in pairs(db.sessions or {}) do
            if type(id) == "number" and id > maxId then maxId = id end
        end
        db.activeSessions, db.priceOverrides, db.debug, db.meta.lastSessionId = "bad", nil, 5, "bad"
        local ok, err = pcall(pH_EnsureAccountDB)
        local repaired = ok and type(db.activeSessions) == "table" and type(db.priceOverrides) == "table"
            and type(db.debug) == "table" and db.meta.lastSessionId == maxId
        db.activeSessions, db.priceOverrides, db.debug, db.meta.lastSessionId = saved[1], saved[2], saved[3], saved[4]
        return repaired, repaired and "repaired and restored" or ("repair failed: " .. tostring(err))
    end)
end

function pH_Debug:RunPortTests()
    local results = {}
    for _, name in ipairs({
        "Test_Port_ClientDetection", "Test_Port_PlayerAPIs", "Test_Port_Metadata",
        "Test_Port_Reputations", "Test_Port_ItemAPIs", "Test_Port_BagScan",
        "Test_Port_SecretGuard", "Test_Port_DBRepair",
    }) do
        results[#results + 1] = self[name](self)
    end
    return results
end
