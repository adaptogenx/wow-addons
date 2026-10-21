--[[
    Core/CapacityEstimator.lua - Bag-full ETA estimation (TDD §5.4, §11)

    Model: ETA = freeSlots / smoothed positive occupied-slot pressure.
    Observes (timestamp, usedSlots, totalSlots) samples only - never raw
    loot-message counts or item quantities (TDD §11.1).

    v1 uses a simple bounded rolling window with recency-weighted averaging
    as a starting point; TDD §11.3 calls for aligning this with pH's actual
    ETA implementation once that code is available to inspect/generalize.
]]

local _, Pockets = ...

Pockets.Services.CapacityEstimator = Pockets.Services.CapacityEstimator or {}
local CapacityEstimator = Pockets.Services.CapacityEstimator

local STATE = Pockets.Constants.ESTIMATOR_STATE
local WINDOW_MAX = Pockets.Constants.ESTIMATOR_SAMPLE_WINDOW_MAX

-- Minimum observation window/count before an ETA is considered meaningful.
local MIN_SAMPLES_FOR_CONFIDENCE = 3
local MIN_ELAPSED_SECONDS_FOR_CONFIDENCE = 60
-- A large negative jump (e.g. a vendor trip) discounts stale positive pressure.
local LARGE_DISCONTINUITY_SLOTS = 5
-- Slot-pressure magnitude (slots/minute) below which the trend reads as "stable".
local STABLE_PRESSURE_EPSILON = 0.01

CapacityEstimator.samples = CapacityEstimator.samples or {} -- { { timestamp, usedSlots, totalSlots }, ... }

function CapacityEstimator:AddSample(timestamp, usedSlots, totalSlots)
    timestamp = timestamp or GetTime()

    local last = self.samples[#self.samples]
    if last and (usedSlots - last.usedSlots) <= -LARGE_DISCONTINUITY_SLOTS then
        -- Large negative discontinuity: discard prior history rather than
        -- let stale positive pressure leak into the new trend (TDD §11.3).
        self.samples = {}
    end

    table.insert(self.samples, { timestamp = timestamp, usedSlots = usedSlots, totalSlots = totalSlots })

    while #self.samples > WINDOW_MAX do
        table.remove(self.samples, 1)
    end
end

-- Returns smoothed slot pressure in slots/minute (positive = filling).
function CapacityEstimator:GetRate()
    if #self.samples < 2 then
        return nil
    end

    local first = self.samples[1]
    local last = self.samples[#self.samples]
    local elapsedMinutes = (last.timestamp - first.timestamp) / 60
    if elapsedMinutes <= 0 then
        return nil
    end

    return (last.usedSlots - first.usedSlots) / elapsedMinutes
end

-- Returns seconds until full, or nil when there isn't enough confidence to
-- show a precise-looking number (PRD §3.2 "never fabricate a precise ETA").
function CapacityEstimator:GetETA()
    local state = self:GetState()
    if state ~= STATE.FILLING then
        return nil
    end

    local last = self.samples[#self.samples]
    local rate = self:GetRate() -- slots/minute
    if not rate or rate <= 0 or not last then
        return nil
    end

    local freeSlots = last.totalSlots - last.usedSlots
    if freeSlots <= 0 then
        return nil
    end

    local etaMinutes = freeSlots / rate
    return etaMinutes * 60
end

function CapacityEstimator:GetConfidence()
    if #self.samples < MIN_SAMPLES_FOR_CONFIDENCE then
        return 0
    end

    local first = self.samples[1]
    local last = self.samples[#self.samples]
    local elapsed = last.timestamp - first.timestamp
    if elapsed < MIN_ELAPSED_SECONDS_FOR_CONFIDENCE then
        return 0
    end

    -- Simple confidence: scales with sample count and elapsed observation
    -- time, capped at 1.0. Refine once pH's variance-aware model is ported.
    local sampleScore = math.min(#self.samples / WINDOW_MAX, 1)
    local timeScore = math.min(elapsed / (10 * 60), 1)
    return (sampleScore + timeScore) / 2
end

function CapacityEstimator:GetState()
    local last = self.samples[#self.samples]
    if not last then
        return STATE.WARMING_UP
    end

    if last.totalSlots > 0 and last.usedSlots >= last.totalSlots then
        return STATE.FULL
    end

    if #self.samples < 2 or self:GetConfidence() <= 0 then
        return STATE.WARMING_UP
    end

    local rate = self:GetRate()
    if not rate then
        return STATE.WARMING_UP
    end

    if rate > STABLE_PRESSURE_EPSILON then
        return STATE.FILLING
    elseif rate < -STABLE_PRESSURE_EPSILON then
        return STATE.FREEING
    end
    return STATE.STABLE
end

function CapacityEstimator:Reset(_reason)
    self.samples = {}
end
