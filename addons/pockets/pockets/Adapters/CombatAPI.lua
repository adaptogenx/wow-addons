--[[
    Adapters/CombatAPI.lua - Isolates combat-lockdown state (TDD §3.1, §11, §22)

    Combat state must be checked at the moment of interaction, not cached
    at load/frame-creation time (TDD §14).
]]

local _, Pockets = ...

Pockets.Adapters.CombatAPI = Pockets.Adapters.CombatAPI or {}
local CombatAPI = Pockets.Adapters.CombatAPI

function CombatAPI:IsInCombat()
    return InCombatLockdown() and true or false
end

-- True when `frame` may be shown/hidden/anchored/re-IDed right now. In
-- combat lockdown, protected frames reject those mutations; non-protected
-- frames are always mutable. Asked of the live frame (IsProtected) rather
-- than assumed, so the answer follows whatever the client's template is.
function CombatAPI:CanMutateProtected(frame)
    if not self:IsInCombat() then
        return true
    end
    if frame and frame.IsProtected then
        return not frame:IsProtected()
    end
    return true
end

