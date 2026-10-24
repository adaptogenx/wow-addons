--[[
    UI_Tooltip.lua - Tooltip placement for pH windows

    Tooltips are pinned beside the pH window that owns the hovered element: on the
    window's right edge when the window sits in the left half of the screen, on its
    left edge when it sits in the right half.
]]

-- luacheck: globals GameTooltip UIParent
local _, addon = ...
local PHUI = addon.UI.PHUI

local pH_Tooltip = {}

local HOST_FRAMES = { "pH_HUD_Frame", "pH_HistoryFrame" }

local function FindHost(owner)
    local frame = owner
    while frame do
        for _, name in ipairs(HOST_FRAMES) do
            if frame == _G[name] then return frame end
        end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return nil
end

-- Show the tooltip owner for `owner`, pinned to its pH window.
function pH_Tooltip:Own(owner)
    local host = FindHost(owner)
    local centerX = host and host:GetCenter()
    if not host or not centerX then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        return
    end
    GameTooltip:SetOwner(host, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if centerX < UIParent:GetWidth() / 2 then
        GameTooltip:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    else
        GameTooltip:SetPoint("TOPRIGHT", host, "TOPLEFT", -4, 0)
    end
end

PHUI.SetTooltipOwner(function(owner) pH_Tooltip:Own(owner) end)

_G.pH_Tooltip = pH_Tooltip
