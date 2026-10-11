-- Run: lua tests/test_loot_defer.lua (repo root). Loot cache-miss deferral, no double count.
local env = setmetatable({}, { __index = _G })
env._G = env
local timers, items, requested = {}, {}, {}
env.GetTime = function() return 100 end
env.GetBuildInfo = function() return "x", "1", "d", 160001 end
env.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
env.C_Item = {
    GetItemInfo = function(id) local i = items[id]; if i then return i.name, "l", i.q, 1, 1, "t", "s", 1, "e", 0, i.vp, i.c, i.sc end end,
    RequestLoadItemDataByID = function(id) requested[#requested + 1] = id end,
}
env.C_Container = { GetContainerNumSlots = function() return 0 end }
env.pH_DB_Account = { debug = { verbose = false, enabled = false }, meta = { lastSessionId = 0 }, sessions = {} }
env.pH_DB = { meta = {}, sessions = {} }
env.pH_Settings = {}
env.CreateFrame = function() return setmetatable({}, { __index = function() return function() end end }) end
env.hooksecurefunc = function() end
env.UnitName = function() return "T" end
env.GetRealmName = function() return "R" end
env.UnitFactionGroup = function() return "Alliance" end
env.UnitClass = function() return "Rogue", "ROGUE" end
env.time = os.time
for _, n in ipairs({"GetZoneText","GetSubZoneText","GetRealZoneText","GetMinimapZoneText"}) do env[n] = function() return "Zone" end end
env.UnitLevel = function() return 10 end
env.UnitXP = function() return 0 end
env.UnitXPMax = function() return 100 end
env.GetMoney = function() return 0 end
env.GetNumFactions = function() return 0 end
env.GetFactionInfo = function() end
env.IsInInstance = function() return false end
env.UnitIsAFK = function() return false end
env.pH_HUD = { Update = function() end }

for _, f in ipairs({ "pH_API", "Ledger", "PriceSources", "EnchantingCatalog", "RepTurninCatalog", "Valuation", "Holdings", "SessionManager", "Events" }) do
    local fh = assert(io.open("ph/" .. f .. ".lua")); local src = fh:read("a"); fh:close()
    local chunk = assert(load(src, f, "t", env))
    chunk("pH", {})
end

local ev, sm = env.pH_Events, env.pH_SessionManager
sm:StartSession()
local session = sm:GetActiveSession()
assert(session, "session")
local msg = "You receive loot: |cff9d9d9d|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|rx2."
local function cash() return session.ledger.balances end

-- cache miss: deferred, nothing booked yet
ev:OnLootedItem(msg)
assert(#requested == 1 and requested[1] == 2589, "requested item data")
local before = 0; for k, v in pairs(cash()) do if k:match("^Assets:Inventory") then before = before + v end end
assert(before == 0, "nothing booked while pending")

-- data arrives: booked once; timeout afterwards is a no-op
items[2589] = { name = "Linen Cloth", q = 1, vp = 13, c = 7, sc = 5 }
ev:OnItemInfoReceived(2589)
for _, t in ipairs(timers) do t() end
local lots = session.holdings[2589] and session.holdings[2589].lots
assert(lots and #lots == 1 and lots[1].count == 2, "single lot of 2")
print("ok")
