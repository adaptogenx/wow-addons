--[[
    UI/PositionStrategy.lua - Root-frame anchor strategy (UI layout pass §2)

    Position and size are independent concerns: Shell resizes the root
    frame per state, this module owns where that frame's origin sits on
    screen. V1 is a single fixed TOPLEFT anchor/growth strategy - Glance
    and every expanded state share the same screen-space TOPLEFT, and
    resizing always grows right/down from it, never recenters.

    A future pass may pick the anchor/growth direction from where the
    player actually parked the frame (left edge -> grow right, bottom ->
    grow up, etc.) - that's why this is a seam (GetRootAnchor/
    ApplyRootPosition/CaptureSavedPosition) instead of Shell hardcoding
    "TOPLEFT" inline in multiple places.
]]

local _, Pockets = ...

Pockets.UI.PositionStrategy = Pockets.UI.PositionStrategy or {}
local PositionStrategy = Pockets.UI.PositionStrategy

-- V1: always TOPLEFT. A future strategy could inspect saved position vs.
-- screen bounds and return a different anchor per corner/edge.
function PositionStrategy:GetRootAnchor()
    return "TOPLEFT"
end

-- Where a w x h panel anchored at the saved TOPLEFT offset (x right, y down
-- is negative - UIParent TOPLEFT coordinates) must sit so it stays fully on
-- screen: shifted left/up only as far as needed, never past the screen's
-- left/top edge. Pure, so the expanded panel (which can't be re-anchored in
-- combat) is positioned ahead of time, out of combat.
function PositionStrategy.ClampToScreen(x, y, w, h, screenW, screenH)
    local left = math.max(0, math.min(x, screenW - w))
    local down = math.max(0, math.min(-y, screenH - h))
    return left, -down
end

-- Anchors `frame` to UIParent using the strategy's anchor on both sides,
-- so SetSize()-driven growth always extends away from that one fixed
-- point (right/down for TOPLEFT) regardless of current dimensions.
function PositionStrategy:ApplyRootPosition(frame, savedPosition)
    local anchor = self:GetRootAnchor()
    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, anchor, savedPosition.x or 0, savedPosition.y or 0)
end

-- Reads the frame's current position back out as a TOPLEFT-of-frame to
-- TOPLEFT-of-UIParent offset. Deliberately does NOT trust
-- frame:GetPoint()'s reported point/relativePoint/offsets - WoW's own
-- StartMoving()/StopMovingOrSizing() drag commit does not reliably keep
-- reporting the exact anchor pairing ApplyRootPosition set (this was
-- observed producing an impossible positive y offset - off the top of
-- the screen - after a real in-game drag). Absolute screen position
-- (GetLeft/GetTop, scale-corrected) is unambiguous regardless of which
-- corner/relativePoint the drag actually committed to, so the offset is
-- rederived from that instead of read back verbatim.
function PositionStrategy:CaptureSavedPosition(frame)
    local anchor = self:GetRootAnchor()

    local frameScale = frame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1

    -- GetLeft/GetTop are nil until the frame has a size and a completed
    -- layout pass (WoW does not report screen edges for a 0x0 unlaid-out
    -- frame). Fall back to the explicit SetPoint offsets so a capture
    -- during first-show/test setup never throws.
    local left, top = frame:GetLeft(), frame:GetTop()
    local parentLeft, parentTop = UIParent:GetLeft(), UIParent:GetTop()
    if not left or not top or not parentLeft or not parentTop then
        local _, _, _, x, y = frame:GetPoint()
        return { point = anchor, relativePoint = anchor, x = x or 0, y = y or 0 }
    end

    -- Absolute screen-pixel position of both TOPLEFT corners.
    local screenLeft = left * frameScale
    local screenTop = top * frameScale
    local parentScreenLeft = parentLeft * parentScale
    local parentScreenTop = parentTop * parentScale

    -- Back into UIParent's own coordinate space - the units SetPoint
    -- expects for offsets against a UIParent-relative anchor. A frame
    -- entirely on-screen always yields x >= 0 and y <= 0 here.
    local x = (screenLeft - parentScreenLeft) / parentScale
    local y = (screenTop - parentScreenTop) / parentScale

    return { point = anchor, relativePoint = anchor, x = x, y = y }
end
