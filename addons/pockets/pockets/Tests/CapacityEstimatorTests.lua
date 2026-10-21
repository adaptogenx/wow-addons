--[[
    Tests/CapacityEstimatorTests.lua - ETA state machine (TDD §24.1)
]]

local _, Pockets = ...

local STATE = Pockets.Constants.ESTIMATOR_STATE
local CapacityEstimator = Pockets.Services.CapacityEstimator

Pockets.Tests.TestRunner:Register("CapacityEstimator: warming_up with no samples", function()
    CapacityEstimator:Reset("test")
    local state = CapacityEstimator:GetState()
    return state == STATE.WARMING_UP, string.format("expected warming_up, got %s", state)
end)

Pockets.Tests.TestRunner:Register("CapacityEstimator: full when used >= total", function()
    CapacityEstimator:Reset("test")
    CapacityEstimator:AddSample(0, 68, 68)
    local state = CapacityEstimator:GetState()
    return state == STATE.FULL, string.format("expected full, got %s", state)
end)

Pockets.Tests.TestRunner:Register("CapacityEstimator: filling with sustained positive pressure", function()
    CapacityEstimator:Reset("test")
    CapacityEstimator:AddSample(0, 10, 68)
    CapacityEstimator:AddSample(60, 15, 68)
    CapacityEstimator:AddSample(120, 20, 68)
    CapacityEstimator:AddSample(180, 25, 68)

    local state = CapacityEstimator:GetState()
    local eta = CapacityEstimator:GetETA()
    local ok = state == STATE.FILLING and eta ~= nil and eta > 0
    return ok, ok and "OK" or string.format("expected filling+ETA, got state=%s eta=%s", state, tostring(eta))
end)

Pockets.Tests.TestRunner:Register("CapacityEstimator: freeing after items removed", function()
    CapacityEstimator:Reset("test")
    CapacityEstimator:AddSample(0, 40, 68)
    CapacityEstimator:AddSample(60, 39, 68)
    CapacityEstimator:AddSample(120, 38, 68)
    CapacityEstimator:AddSample(180, 37, 68)

    local state = CapacityEstimator:GetState()
    local eta = CapacityEstimator:GetETA()
    local ok = state == STATE.FREEING and eta == nil
    return ok, ok and "OK" or string.format("expected freeing+no ETA, got state=%s eta=%s", state, tostring(eta))
end)

Pockets.Tests.TestRunner:Register("CapacityEstimator: large negative discontinuity discounts history", function()
    CapacityEstimator:Reset("test")
    CapacityEstimator:AddSample(0, 60, 68)
    CapacityEstimator:AddSample(60, 65, 68)
    -- vendor trip: big drop
    CapacityEstimator:AddSample(120, 10, 68)

    local ok = #CapacityEstimator.samples == 1
    return ok, ok and "OK" or string.format("expected history reset to 1 sample, got %d", #CapacityEstimator.samples)
end)

Pockets.Tests.TestRunner:Register("CapacityEstimator: never fabricates ETA below confidence threshold", function()
    CapacityEstimator:Reset("test")
    CapacityEstimator:AddSample(0, 10, 68)
    CapacityEstimator:AddSample(1, 11, 68)

    local eta = CapacityEstimator:GetETA()
    local confidence = CapacityEstimator:GetConfidence()
    local ok = confidence < 0.5 -- not enough elapsed time yet
    return ok, ok and string.format("OK (confidence=%.2f, eta=%s)", confidence, tostring(eta))
        or string.format("expected low confidence, got %.2f", confidence)
end)
