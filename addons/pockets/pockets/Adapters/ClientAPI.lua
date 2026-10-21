--[[
    Adapters/ClientAPI.lua - Client detection + small cross-client shims
    (Forever M1 §8)

    Core/UI never branch on the client. Anything that differs between
    Classic/TBC and WoW Forever is resolved inside an adapter; this file
    holds the detection signal and the few shims that don't belong to
    bags/items/tooltips.
]]

local _, Pockets = ...

Pockets.Adapters.ClientAPI = Pockets.Adapters.ClientAPI or {}
local ClientAPI = Pockets.Adapters.ClientAPI

-- Interface (TOC) number ranges. WOW_PROJECT_ID is deliberately NOT used:
-- it is unverified for the Forever beta. The build's interface number is
-- the signal; unknown numbers are neither Forever nor Classic.
local FOREVER_MIN, FOREVER_MAX = 16000, 16999

-- Pure: classify an interface number. Split out for tests.
function ClientAPI.ClassifyInterface(interfaceNumber)
    if type(interfaceNumber) ~= "number" then
        return "unknown"
    end
    if interfaceNumber >= FOREVER_MIN and interfaceNumber <= FOREVER_MAX then
        return "forever"
    end
    if interfaceNumber >= 11000 and interfaceNumber < 30000 then
        return "classic" -- Anniversary (11xxx) and TBC (20xxx)
    end
    return "unknown"
end

function ClientAPI:GetInterfaceNumber()
    if GetBuildInfo then
        local _, _, _, toc = GetBuildInfo()
        return tonumber(toc)
    end
    return nil
end

function ClientAPI:GetClientType()
    return self.ClassifyInterface(self:GetInterfaceNumber())
end

function ClientAPI:IsForever()
    return self:GetClientType() == "forever"
end

-- True when a value is a Secret Value (modern clients). Such values cannot
-- be compared, indexed, or used in arithmetic; callers treat them as
-- unavailable instead of erroring. Always false on clients without it.
function ClientAPI:IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Addon metadata: C_AddOns on modern clients, legacy global otherwise.
function ClientAPI:GetAddonMetadata(addon, field)
    local value
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        value = C_AddOns.GetAddOnMetadata(addon, field)
    elseif GetAddOnMetadata then
        value = GetAddOnMetadata(addon, field)
    end
    return value
end
