--[[
    Adapters/CombatLogAPI.lua - Normalizes the current combat log event.
]]

local _, HMF = ...

local CombatLog = {}
HMF.Adapters.CombatLog = CombatLog

-- Call from a COMBAT_LOG_EVENT_UNFILTERED handler.
function CombatLog.Read()
    local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()
    return {
        sub = sub, srcGUID = srcGUID, srcName = srcName,
        dstGUID = dstGUID, dstName = dstName,
        spellID = spellID, spellName = spellName,
    }
end
