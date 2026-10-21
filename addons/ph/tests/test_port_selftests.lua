-- Run: lua tests/test_port_selftests.lua. Exercises Debug_Port.lua against mocked WoW APIs.
local env = setmetatable({}, { __index = _G }); env._G = env
local bag = { [0] = { { 6948, 1 } } }
env.GetBuildInfo = function() return "x", "1", "d", 160001 end
env.GetMoney = function() return 12345 end
env.UnitXP = function() return 10 end
env.UnitXPMax = function() return 100 end
env.UnitLevel = function() return 20 end
env.GetMaxPlayerLevel = function() return 60 end
env.C_AddOns = { GetAddOnMetadata = function() return "0.15.3" end }
env.C_Reputation = { GetNumFactions = function() return 1 end, GetFactionDataByIndex = function()
    return { factionID = 1, name = "F", reaction = 4, currentStanding = 5, currentReactionThreshold = 0, nextReactionThreshold = 10 } end }
env.C_Item = { GetItemInfo = function() return "Hearthstone", "l", 1 end, GetItemCount = function() return 1 end }
env.C_Spell = { GetSpellName = function() return "Hearthstone" end }
env.pH_DB_Account = { meta = { lastSessionId = 7 }, sessions = { [3] = {}, [7] = {} }, activeSessions = {}, priceOverrides = {}, debug = {} }
env.pH_Debug = { LogTestResult = function(_, n, p, m) print((p and "PASS " or "FAIL ") .. n .. ": " .. m) end }
env.pH_Events = { SnapshotBags = function() return { [6948] = 1 } end }
env.pH_EnsureAccountDB = function()
    local db = env.pH_DB_Account
    if type(db.activeSessions) ~= "table" then db.activeSessions = {} end
    if type(db.priceOverrides) ~= "table" then db.priceOverrides = {} end
    if type(db.debug) ~= "table" then db.debug = {} end
    if type(db.meta.lastSessionId) ~= "number" then db.meta.lastSessionId = 7 end
end
for _, f in ipairs({ "pH_API", "Debug_Port" }) do
    local fh = io.open("ph/" .. f .. ".lua"); local src = fh:read("a"); fh:close()
    assert(load(src, f, "t", env))()
end
local fails = 0
for _, r in ipairs(env.pH_Debug:RunPortTests()) do if not r.passed then fails = fails + 1 end end
assert(fails == 0, fails .. " failed")
assert(env.pH_DB_Account.meta.lastSessionId == 7, "restored")
print("ok")
