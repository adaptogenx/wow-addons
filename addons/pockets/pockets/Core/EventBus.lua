--[[
    Core/EventBus.lua - Addon-local publish/subscribe bus (TDD §5.5)

    Domain events are Pockets-internal (POCKETS_*), not WoW events exposed
    directly to consumers. UI modules subscribe here instead of rescanning
    bags or polling domain state.
]]

local _, Pockets = ...

Pockets.Services.EventBus = Pockets.Services.EventBus or {}
local EventBus = Pockets.Services.EventBus

-- subscribers[eventName] = { { callback = fn, owner = owner }, ... }
EventBus.subscribers = EventBus.subscribers or {}

function EventBus:Subscribe(eventName, callback, owner)
    if type(callback) ~= "function" then
        return
    end
    self.subscribers[eventName] = self.subscribers[eventName] or {}
    table.insert(self.subscribers[eventName], { callback = callback, owner = owner })
end

-- Removes every subscription registered by a given owner, across all events.
function EventBus:UnsubscribeOwner(owner)
    if owner == nil then
        return
    end
    for eventName, list in pairs(self.subscribers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then
                table.remove(list, i)
            end
        end
        self.subscribers[eventName] = list
    end
end

function EventBus:Publish(eventName, payload)
    local list = self.subscribers[eventName]
    if not list then
        return
    end
    -- Iterate over a snapshot so a callback unsubscribing mid-publish is safe.
    local snapshot = {}
    for i, entry in ipairs(list) do
        snapshot[i] = entry
    end
    for _, entry in ipairs(snapshot) do
        local ok, err = pcall(entry.callback, payload)
        if not ok and Pockets.Debug then
            Pockets.Debug:LogError(string.format("EventBus subscriber error on %s: %s", eventName, tostring(err)))
        end
    end
end
