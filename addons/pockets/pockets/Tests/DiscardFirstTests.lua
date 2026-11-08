--[[
    Tests/DiscardFirstTests.lua - "Discard first" candidate selection.
]]

local _, Pockets = ...

local TestRunner = Pockets.Tests.TestRunner
local DiscardFirst = Pockets.Services.DiscardFirst
local C = Pockets.Constants

local function Rec(id, qty, price, extra)
    local r = { itemID = id, quantity = qty, sellPrice = price, name = "i" .. id, quality = 1,
        categoryID = C.CATEGORY.OTHER, capacityClass = C.CAPACITY_CLASS.GENERAL }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

TestRunner:Register("DiscardFirst: lowest total stack value first, stacks aggregate", function()
    local out = DiscardFirst.Select({
        Rec(1, 5, 10), Rec(1, 5, 10), -- 100 total
        Rec(2, 1, 50),                -- 50
        Rec(3, 20, 1),                -- 20
    })
    local ok = #out == 3 and out[1].itemID == 3 and out[2].itemID == 2 and out[3].itemID == 1
    return ok, ok and "OK" or "wrong order"
end)

TestRunner:Register("DiscardFirst: skips quest, ammo, hearthstone, unknown and zero-price non-junk", function()
    local out = DiscardFirst.Select({
        Rec(1, 1, 5, { categoryID = C.CATEGORY.QUEST }),
        Rec(2, 1, 5, { categoryID = C.CATEGORY.AMMO }),
        Rec(6948, 1, 0),
        Rec(4, 1, nil),
        Rec(5, 1, 0),                    -- quality 1, unsellable: skip
        Rec(6, 1, 0, { quality = 0 }),   -- poor, worthless: ok
        Rec(7, 1, 3),
    })
    local ok = #out == 2 and out[1].itemID == 6 and out[2].itemID == 7
    return ok, ok and "OK" or "unexpected candidates"
end)

TestRunner:Register("DiscardFirst: limit and activation threshold", function()
    local recs = {}
    for i = 1, 9 do recs[i] = Rec(i, 1, i) end
    local ok = #DiscardFirst.Select(recs, 5) == 5
        and DiscardFirst.IsActive({ total = 20, utilization = 0.9 })
        and not DiscardFirst.IsActive({ total = 20, utilization = 0.85 })
        and not DiscardFirst.IsActive({ total = 0, utilization = 1 })
    return ok, ok and "OK" or "limit/threshold wrong"
end)

TestRunner:Register("DiscardFirst: skips profession tools and materials by default", function()
    local out = DiscardFirst.Select({
        Rec(1, 1, 1, { classID = 2, subclassID = 20 }), -- fishing pole
        Rec(2, 1, 1, { classID = 2, subclassID = 14 }), -- skinning knife style
        Rec(7005, 1, 1),                                -- Skinning Knife by ID
        Rec(4, 20, 1, { classID = 7 }),                 -- trade good
        Rec(5, 1, 1, { classID = 9 }),                  -- recipe
        Rec(6, 1, 1, { classID = 2, subclassID = 7 }),  -- ordinary weapon
    })
    local ok = #out == 1 and out[1].itemID == 6
    return ok, ok and "OK" or "profession items offered"
end)
