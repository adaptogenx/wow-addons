--[[
    Shared/CapacityRing.lua - Reusable circular capacity gauge (Mini HUD TDD §2, §4)

    A clockwise-filling ring built from a fixed pool of small rotated colour
    segments (no radial-mask / cooldown-swipe dependency, so it behaves the
    same on every client). Generic: it knows only a 0..1 fraction and a
    colour - no Pockets strings, thresholds or inventory APIs.

    Segments are created once; SetFraction/SetColor only re-colour them.
]]

local _, Pockets = ...

Pockets.UI.CapacityRing = Pockets.UI.CapacityRing or {}
local CapacityRing = Pockets.UI.CapacityRing

local WHITE = "Interface\\Buttons\\WHITE8X8"

CapacityRing.DEFAULT_SEGMENTS = 40
local TRACK = { 0.380, 0.333, 0.255, 0.8 } -- unfilled / zero-capacity neutral

--------------------------------------------------
-- Pure helpers (unit-testable)
--------------------------------------------------

-- Clamp to 0..1; nil/NaN/non-number -> 0 (zero capacity is safe).
function CapacityRing.ClampFraction(fraction)
    if type(fraction) ~= "number" or fraction ~= fraction then
        return 0
    end
    return math.max(0, math.min(1, fraction))
end

-- How many of `segments` are lit for `fraction`. Any non-zero fill shows at
-- least one segment; only a full ring lights all of them.
function CapacityRing.LitSegments(fraction, segments)
    local f = CapacityRing.ClampFraction(fraction)
    if f <= 0 then
        return 0
    end
    if f >= 1 then
        return segments
    end
    return math.min(segments - 1, math.max(1, math.floor(f * segments + 0.5)))
end

--------------------------------------------------
-- Build
--------------------------------------------------

-- opts: diameter (outer, px), thickness (px), segments (default 40).
-- The ring is centred in its own square frame; the caller anchors it.
function CapacityRing:Create(parent, opts)
    opts = opts or {}
    local diameter = opts.diameter or 48
    local thickness = opts.thickness or 4
    local count = opts.segments or CapacityRing.DEFAULT_SEGMENTS

    local ring = CreateFrame("Frame", nil, parent)
    ring:SetSize(diameter, diameter)
    ring:EnableMouse(false)
    ring.segmentCount = count
    ring.segments = {}
    ring.fraction = 0
    ring.lit = 0
    ring.color = { 1, 1, 1 }

    local radius = diameter / 2 - thickness / 2 -- centre line of the band
    local length = (2 * math.pi * radius) / count + 0.6 -- slight overlap: no gaps
    for i = 1, count do
        local angle = 2 * math.pi * (i - 1) / count -- 0 = 12 o'clock, clockwise
        local seg = ring:CreateTexture(nil, "ARTWORK")
        seg:SetSize(length, thickness)
        seg:SetPoint("CENTER", ring, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
        seg:SetTexture(WHITE)
        seg:SetRotation(-angle) -- rotation is counter-clockwise; tangent to the ring
        seg:SetVertexColor(TRACK[1], TRACK[2], TRACK[3], TRACK[4])
        ring.segments[i] = seg
    end

    function ring:Refresh()
        local c = self.color
        local fn = self.colorFn
        for i, seg in ipairs(self.segments) do
            if i <= self.lit then
                if fn then
                    -- Zoned ring: each lit segment takes the colour of its
                    -- own position (e.g. green, then yellow, then red).
                    local r, g, b = fn((i - 0.5) / self.segmentCount)
                    seg:SetVertexColor(r, g, b, 1)
                else
                    seg:SetVertexColor(c[1], c[2], c[3], 1)
                end
            else
                seg:SetVertexColor(TRACK[1], TRACK[2], TRACK[3], TRACK[4])
            end
        end
    end
    function ring:SetFraction(fraction)
        self.fraction = CapacityRing.ClampFraction(fraction)
        local lit = CapacityRing.LitSegments(self.fraction, self.segmentCount)
        if lit ~= self.lit then
            self.lit = lit
            self:Refresh()
        end
    end
    -- fn(fraction 0..1) -> r, g, b; nil goes back to the single colour.
    function ring:SetColorFn(fn)
        self.colorFn = fn
        self:Refresh()
    end
    function ring:SetColor(r, g, b)
        self.color = { r, g, b }
        self:Refresh()
    end
    function ring:GetLitCount() return self.lit end

    return ring
end
