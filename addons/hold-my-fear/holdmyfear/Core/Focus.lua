--[[
    Core/Focus.lua - Which tracked enemy should be the (single) focus target.

    Addon code cannot set focus itself (only a secure button the player presses can), so this
    only decides the *suggestion* the HUD shows. Rules, to keep it from jumping around:
      * The player's own focus on a tracked enemy wins and becomes the suggestion.
      * The suggestion never moves while that enemy is tracked and its Fear is running.
      * If the suggested enemy dies / is untracked, the next one is suggested at once.
      * If its Fear is over and another enemy has Fear running, hand off - but only after
        MIN_DWELL seconds, so quick re-Fear cycles do not flip it.
    Handoff picks the earliest-tracked (row order) enemy with Fear running; with none feared,
    the first tracked enemy is the primary so there is always one to focus.
]]

local _, HMF = ...

local Focus = {}
HMF.Services.Focus = Focus

local C = HMF.Constants
local Tracker = HMF.Services.Tracker

local suggested, since, lastActual

local function now()
    return GetTime and GetTime() or 0
end

local function pickBest(t)
    local list = Tracker.List()
    for _, entry in ipairs(list) do
        if Tracker.FearRemaining(entry, t) then return entry end
    end
    return list[1] -- nobody feared: the first tracked enemy is the primary
end

function Focus.Suggested() return suggested end

-- True when the player's actual focus is this GUID.
function Focus.IsFocused(guid)
    return guid ~= nil and HMF.Adapters.Unit.FocusGUID() == guid
end

-- Safe to call often (every HUD tick): changes only when a rule above says so.
function Focus.Evaluate(t)
    t = t or now()
    local actual = HMF.Adapters.Unit.FocusGUID()
    if actual ~= lastActual then
        lastActual = actual
        if actual and Tracker.Get(actual) then suggested, since = actual, t end
    end
    if suggested and not Tracker.Get(suggested) then suggested, since = nil, nil end

    local current = suggested and Tracker.Get(suggested)
    if not current then
        local best = pickBest(t)
        if best then suggested, since = best.guid, t end
    elseif not Tracker.FearRemaining(current, t) and t - since >= C.FOCUS.MIN_DWELL then
        local best = pickBest(t)
        if best and best.guid ~= suggested then suggested, since = best.guid, t end
    end
    return suggested
end

function Focus.Reset()
    suggested, since, lastActual = nil, nil, nil
end

Tracker.Subscribe(function(event)
    if event == "reset" then Focus.Reset() return end
    if event == "added" or event == "removed" or event == "fear-set" or event == "fear-cleared" then
        Focus.Evaluate()
    end
end)
