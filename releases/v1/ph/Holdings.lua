--[[
    Holdings.lua - FIFO inventory lot management

    Tracks items acquired during session with expected values snapshot.
    Phase 3: Creation only (no consumption)
    Phase 4: Add FIFO consumption for vendor sales
]]

-- luacheck: globals GoldPH_DB_Account

local GoldPH_Holdings = {}

--------------------------------------------------
-- FIFO Lot Creation (Phase 3)
--------------------------------------------------

-- Add items to holdings (create new FIFO lot)
-- @param session: Active session
-- @param itemID: Item ID
-- @param count: Number of items
-- @param expectedEach: Expected value per item in copper
-- @param bucket: Item bucket
function GoldPH_Holdings:AddLot(session, itemID, count, expectedEach, bucket)
    if not session or not session.holdings then
        error("GoldPH_Holdings:AddLot - Invalid session or missing holdings")
    end

    if count <= 0 then
        return -- No-op for zero count
    end

    -- Initialize holdings for this item if not exists
    if not session.holdings[itemID] then
        session.holdings[itemID] = {
            count = 0,
            lots = {}
        }
    end

    -- Create new lot
    local lot = {
        count = count,
        expectedEach = expectedEach,
        bucket = bucket,
    }

    -- Append to FIFO queue
    table.insert(session.holdings[itemID].lots, lot)

    -- Update total count
    session.holdings[itemID].count = session.holdings[itemID].count + count

    -- Debug logging
    if GoldPH_DB_Account.debug.verbose then
        print(string.format("[GoldPH Holdings] Added lot: itemID=%d, count=%d, expectedEach=%d, bucket=%s",
            itemID, count, expectedEach, bucket))
    end
end

-- Get total count for an item in holdings
function GoldPH_Holdings:GetCount(session, itemID)
    if not session or not session.holdings or not session.holdings[itemID] then
        return 0
    end

    return session.holdings[itemID].count
end

-- Get total expected value for an item in holdings
function GoldPH_Holdings:GetExpectedValue(session, itemID)
    if not session or not session.holdings or not session.holdings[itemID] then
        return 0
    end

    local totalValue = 0
    for _, lot in ipairs(session.holdings[itemID].lots) do
        totalValue = totalValue + (lot.count * lot.expectedEach)
    end

    return totalValue
end

-- Get total expected value for all holdings
function GoldPH_Holdings:GetTotalExpectedValue(session)
    if not session or not session.holdings then
        return 0
    end

    local totalValue = 0
    for itemID, _ in pairs(session.holdings) do
        totalValue = totalValue + self:GetExpectedValue(session, itemID)
    end

    return totalValue
end

--------------------------------------------------
-- FIFO Lot Consumption (Phase 4)
--------------------------------------------------

-- Consume items from holdings using FIFO
-- @param session: Active session
-- @param itemID: Item ID
-- @param count: Number of items to consume
-- @return bucketValues: Map of bucket -> total held expected value consumed
--
-- Phase 4: This will be used when vendoring items to reverse expected value
function GoldPH_Holdings:ConsumeFIFO(session, itemID, count)
    if not session or not session.holdings or not session.holdings[itemID] then
        -- Item not in holdings (pre-session item), return empty map
        return {}
    end

    local holdings = session.holdings[itemID]
    local remaining = count
    local bucketValues = {}

    -- Consume lots FIFO
    while remaining > 0 and #holdings.lots > 0 do
        local lot = holdings.lots[1]

        if lot.count <= remaining then
            -- Consume entire lot
            remaining = remaining - lot.count
            holdings.count = holdings.count - lot.count

            -- Track expected value by bucket
            local value = lot.count * lot.expectedEach
            bucketValues[lot.bucket] = (bucketValues[lot.bucket] or 0) + value

            -- Remove lot
            table.remove(holdings.lots, 1)
        else
            -- Consume partial lot
            lot.count = lot.count - remaining
            holdings.count = holdings.count - remaining

            -- Track expected value by bucket
            local value = remaining * lot.expectedEach
            bucketValues[lot.bucket] = (bucketValues[lot.bucket] or 0) + value

            remaining = 0
        end
    end

    -- Debug logging
    if GoldPH_DB_Account.debug.verbose then
        for bucket, value in pairs(bucketValues) do
            print(string.format("[GoldPH Holdings] Consumed FIFO: itemID=%d, bucket=%s, value=%d",
                itemID, bucket, value))
        end
    end

    return bucketValues
end

-- Export module
_G.GoldPH_Holdings = GoldPH_Holdings
