--[[
    Adapters/MoneyAPI.lua - Isolates the player-money read (Loot Log).

    PLAYER_MONEY fires for every money change (mob coin, quest reward,
    vendor sale/buy, repair, taxi, mail, AH). Core/LootLog diffs successive
    GetMoney() values instead of parsing chat text, and only records an
    increase that happens inside a loot context - see Core/LootLog.lua.
]]

local _, Pockets = ...

Pockets.Adapters.MoneyAPI = Pockets.Adapters.MoneyAPI or {}
local MoneyAPI = Pockets.Adapters.MoneyAPI

function MoneyAPI:GetMoney()
    return GetMoney() or 0
end
