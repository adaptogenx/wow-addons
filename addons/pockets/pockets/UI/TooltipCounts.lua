--[[
    UI/TooltipCounts.lua - Adds a carried-count line to item tooltips (TDD §16, PRD §3.10)

    Read-only consumer of InventoryState. Never triggers a bag scan from
    tooltip rendering.
]]

local _, Pockets = ...

Pockets.UI.TooltipCounts = Pockets.UI.TooltipCounts or {}
local TooltipCounts = Pockets.UI.TooltipCounts

local inCallback = false

function TooltipCounts:Initialize()
    Pockets.Adapters.TooltipAPI:OnItemTooltipShow(function(tooltip, itemID)
        -- Re-entrancy guard: tooltip:Show() re-runs tooltip data processing
        -- on modern clients, which re-enters this callback (freeze).
        if inCallback then
            return
        end
        inCallback = true
        local ok, err = pcall(function()
            local quantity = Pockets.Services.InventoryState:GetCarriedQuantity(itemID)
            if quantity > 0 then
                tooltip:AddLine(string.format("In your pockets: %d", quantity), 0.6, 0.8, 1.0)
                -- Resize after AddLine; guarded above against re-entry.
                tooltip:Show()
            end
        end)
        inCallback = false
        if not ok and Pockets.Debug then
            Pockets.Debug:LogError("TooltipCounts failed: " .. tostring(err))
        end
    end)
end
