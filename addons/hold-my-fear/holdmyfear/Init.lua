--[[
    Init.lua - Namespace bootstrap for Hold My Fear

    Must load before every other HoldMyFear file. Establishes the single
    addon-local namespace table and the sub-tables other modules attach to.
]]

local ADDON_NAME, HMF = ...

HMF.Adapters = HMF.Adapters or {}
HMF.Services = HMF.Services or {}
HMF.UI = HMF.UI or {}
HMF.Tests = HMF.Tests or {}

HMF.ADDON_NAME = ADDON_NAME

-- Current version supports Warlocks only; other classes load inert.
HMF.IS_WARLOCK = select(2, UnitClass("player")) == "WARLOCK"

_G.HoldMyFear = HMF
