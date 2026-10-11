-- Run: lua tests/test_api.lua (from repo root)
local function load(env)
    setmetatable(env, { __index = _G })
    local src = io.open("ph/pH_API.lua"):read("a")
    local chunk = assert(_G.load(src, "pH_API", "t", env))
    chunk()
    return env.pH_API
end
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

-- Classic
local c = load({
    GetBuildInfo = function() return "1.15.4", "1", "d", 11504 end,
    GetMoney = function() return 1000 end, UnitXP = function() return 5 end,
    GetNumFactions = function() return 2 end,
    GetFactionInfo = function(i)
        if i == 1 then return "Hdr", "", 4, 0, 0, 0, 0, 0, true, 0, 0, 0, 0, nil end
        return "Org", "", 5, 3000, 9000, 4200, 0, 0, false, 0, 1, 0, 0, 76
    end,
    GetAddOnMetadata = function() return "1.0" end,
})
assert(c:IsClassic() and not c:IsForever())
eq(c:GetMoney(), 1000); eq(c:GetXP(), 5); eq(c:GetAddonMetadata("x", "Version"), "1.0")
local r = c:GetReputations(); eq(#r, 2); eq(r[2].current, 4200); eq(r[2].factionID, 76); assert(r[1].isHeader)

-- Forever (modern API, secret xp)
local secret = {}
local f = load({
    GetBuildInfo = function() return "1.0", "1", "d", 160001 end,
    UnitXP = function() return secret end, issecretvalue = function(v) return v == secret end,
    C_AddOns = { GetAddOnMetadata = function() return "2.0" end },
    C_Reputation = {
        GetNumFactions = function() return 1 end,
        GetFactionDataByIndex = function() return { factionID = 76, name = "Org", reaction = 5,
            currentStanding = 4200, currentReactionThreshold = 3000, nextReactionThreshold = 9000, isHeader = false } end,
    },
})
assert(f:IsForever() and not f:IsClassic())
eq(f:GetXP(), 0, "secret xp degrades"); eq(f:GetAddonMetadata("x", "Version"), "2.0")
r = f:GetReputations(); eq(#r, 1); eq(r[1].current, 4200); eq(r[1].max, 9000)
print("ok")
