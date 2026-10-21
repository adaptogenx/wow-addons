--[[
    Init.lua - Namespace bootstrap for Pockets

    Must load before every other Pockets file. Establishes the single
    addon-local namespace table and the sub-tables other modules attach to.
    See TDD §4 (Namespace and Dependency Model).
]]

local ADDON_NAME, Pockets = ...

Pockets.API = Pockets.API or {}
Pockets.Events = Pockets.Events or {}
Pockets.Services = Pockets.Services or {}
Pockets.Adapters = Pockets.Adapters or {}
Pockets.UI = Pockets.UI or {}
Pockets.Tests = Pockets.Tests or {}

Pockets.ADDON_NAME = ADDON_NAME

-- Recommended public integration root (TDD §4)
_G.Pockets = Pockets
