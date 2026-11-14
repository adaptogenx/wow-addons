--[[ Pure recast-threshold math (no WoW APIs) so it is tested separately from timer rendering. ]]
local _, Lab = ...
Lab = Lab or {}
local T = {}
Lab.Threshold = T

-- Seconds left on an aura, or nil when expiration is unknown/not a number.
function T.Remaining(expiration, now)
    if type(expiration) ~= "number" or type(now) ~= "number" then return nil end
    return expiration - now
end

-- True when a recast should start now so the new Fear lands as the old one ends.
-- castTime: cast duration of the spell; buffer: latency/safety margin.
-- Returns nil (unknown) when the remaining time is unknown. Never guesses.
function T.IsRecastDue(expiration, now, castTime, buffer)
    local rem = T.Remaining(expiration, now)
    if rem == nil then return nil end
    return rem <= (castTime or 0) + (buffer or 0)
end

return T
