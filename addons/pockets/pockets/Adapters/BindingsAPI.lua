--[[
    Adapters/BindingsAPI.lua - Isolates keybinding registration (TDD §3.1, §17)

    Defines the binding header/name strings consumed by Bindings.xml and
    routes the bound action to Pockets.API so the binding is never coupled
    directly to a frame instance.
]]

local _, Pockets = ...

Pockets.Adapters.BindingsAPI = Pockets.Adapters.BindingsAPI or {}

-- Binding header shown in Key Bindings UI, and the action name/label.
_G.BINDING_HEADER_POCKETS = "Pockets"
_G.BINDING_NAME_POCKETS_TOGGLE_FULL_INVENTORY = "Toggle Full Inventory"

-- Called by Bindings.xml via the POCKETS_TOGGLE_FULL_INVENTORY binding action.
function Pockets_ToggleFullInventory()
    if Pockets.API and Pockets.API.ToggleFullInventory then
        Pockets.API.ToggleFullInventory()
    end
end

-- Pure: SaveBindings only accepts 1 (account) or 2 (character). Modern
-- clients can report another value (or nothing) from GetCurrentBindingSet,
-- which made SaveBindings throw "Usage: SaveBindings(1|2)" on Forever.
function Pockets.Adapters.BindingsAPI.NormalizeBindingSet(set)
    if set == 1 or set == 2 then
        return set
    end
    return 1
end

-- Binds `key` to `action` unless the action already has a key. Returns
-- true if a binding was added. Errors propagate (caller pcalls).
function Pockets.Adapters.BindingsAPI:EnsureDefaultBinding(key, action)
    if GetBindingKey(action) then
        return false
    end
    SetBinding(key, action)
    SaveBindings(self.NormalizeBindingSet(GetCurrentBindingSet and GetCurrentBindingSet()))
    return true
end
