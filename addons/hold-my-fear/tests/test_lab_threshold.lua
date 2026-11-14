-- Offline test for hmf-api-lab/Threshold.lua
local chunk = assert(loadfile("hmf-api-lab/Threshold.lua"))
local T = chunk(nil, {})
local function eq(a, b, m) if a ~= b then error(m .. ": got " .. tostring(a) .. " want " .. tostring(b)) end end
eq(T.Remaining(110, 100), 10, "remaining")
eq(T.Remaining(nil, 100), nil, "nil exp")
eq(T.Remaining("x", 100), nil, "non-number exp")
eq(T.IsRecastDue(110, 100, 1.5, 0.3), false, "10s left")
eq(T.IsRecastDue(101.8, 100, 1.5, 0.3), true, "exactly at threshold")
eq(T.IsRecastDue(101.9, 100, 1.5, 0.3), false, "just above threshold")
eq(T.IsRecastDue(99, 100, 1.5, 0.3), true, "already expired")
eq(T.IsRecastDue(nil, 100, 1.5, 0.3), nil, "unknown not guessed")
print("PASS lab threshold")
