-- Run: lua tests/test_insights.lua (from addons/ph). Level ETA and rep model builders.
local env = setmetatable({}, { __index = _G })
env._G = env
env.pH_API = {
    GetMaxPlayerLevel = function() return 70 end,
    GetPlayerLevel = function() return 30 end,
    GetXP = function() return 1000 end,
    GetXPMax = function() return 5000 end,
    GetReputations = function()
        return { { name = "Org", standingID = 5, max = 9000, current = 4200, isHeader = false } }
    end,
}
assert(load(io.open("ph/Insights.lua"):read("a"), "Insights", "t", env))()
local I = env.pH_Insights
local function eq(a, b, m) assert(a == b, (m or "") .. " expected " .. tostring(b) .. " got " .. tostring(a)) end

eq(I.FormatEtaCompact(30), "<1m"); eq(I.FormatEtaCompact(600), "10m"); eq(I.FormatEtaCompact(3900), "1h 05m")
eq(I.BuildEtaRangeText(nil, nil), I.FormatEtaInfinity())
eq(I.BuildEtaRangeText(600, 600), "10m"); eq(I.BuildEtaRangeText(3600, 600), "10m - 1h 00m")
eq(I.FormatInt(1234567), "1,234,567")

-- 4000 xp left at 2000/hr recent and 1000/hr session (eligible) -> 2h recent, 4h session
local eta = I.BuildXPEtaData({ xpEtaRecentPerHour = 2000, xpPerHour = 1000, xpSessionEtaEligible = true })
eq(eta.remainingXP, 4000); eq(eta.etaRecentSec, 7200); eq(eta.etaSessionSec, 14400); eq(eta.isCapped, false)

-- recent ETA is floored at half the session ETA (burst protection) and flagged
eta = I.BuildXPEtaData({ xpEtaRecentPerHour = 100000, xpPerHour = 1000, xpSessionEtaEligible = true })
eq(eta.etaRecentSec, 7200); eq(eta.etaAdjusted, true)

local model = I.BuildRepModel({ repPerHour = 100, repRecentPerHourBucketed = 50,
    repFactions = { { name = "Org", gain = 300 } }, repPotentialItems = {} })
eq(model.sessionAvg, 100); eq(model.currentAvg, 50)
eq(#model.gainedFactions, 1); eq(model.gainedFactions[1].remainingRep, 4800)
eq(model.gainedFactions[1].nextStanding, "Honored"); eq(model.gainedFactions[1].etaSessionText, "48h 00m")
print("PASS insights")
