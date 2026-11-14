--[[
    UI/FocusButton.lua - Secure "set focus" button, driven by a key in Key Bindings > AddOns.

    Sets focus to the mouseover enemy if there is one, else to the target (lab: `/focus target`
    works in and out of combat; nameplate tokens are rejected, so the player hovers or targets
    the enemy the HUD suggests). Created once, out of combat; never touched afterwards.
]]

local _, HMF = ...

local FocusButton = {}
HMF.UI.FocusButton = FocusButton

local NAME = "HMFSetFocusButton"
local MACRO = "/focus [@mouseover,harm,nodead] mouseover; [harm,nodead] target"

-- No Bindings.xml / BINDING_* globals on purpose: on Forever Blizzard's keybinding settings read
-- them at login and the tainted read gets "blocked" (prompt). Players use /hmf bind or the macro.

local function Build()
    if FocusButton.button then return end
    local btn = CreateFrame("Button", NAME, UIParent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyDown", "AnyUp")
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", MACRO)
    -- Diagnostics: proves whether the click reached the button, and which unit it saw.
    FocusButton.clicks = 0
    btn:HookScript("PreClick", function()
        FocusButton.clicks = FocusButton.clicks + 1
        FocusButton.lastClick = GetTime()
        FocusButton.seen = ("target=%s mouseover=%s focusBefore=%s"):format(
            tostring(UnitName("target")), tostring(UnitName("mouseover")), tostring(UnitName("focus")))
    end)
    FocusButton.button = btn
end

function FocusButton.Init()
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            Build()
        end)
        return
    end
    Build()
end

-- Bind a key straight to the button (fallback when Key Bindings > AddOns does not list it).
-- Returns ok, message. Out of combat only.
function FocusButton.Bind(key)
    if InCombatLockdown() then return false, "not in combat" end
    if not FocusButton.button then return false, "button not created yet" end
    key = key and key:upper():gsub("%s", "")
    if not key or key == "" then return false, "usage: /hmf bind <KEY>  e.g. /hmf bind ALT-F" end
    local old = GetBindingAction(key)
    if not SetBindingClick(key, NAME, "LeftButton") then return false, "could not bind " .. key end
    SaveBindings(GetCurrentBindingSet())
    return true, key .. " now sets focus" .. ((old and old ~= "") and (" (replaced " .. old .. ")") or "")
end

-- Short label of the key bound to the button ("ALT-F"), "macro" when only the HMF Focus macro
-- exists, or nil when neither.
function FocusButton.Key()
    local key = GetBindingKey("CLICK " .. NAME .. ":LeftButton")
    if not key then
        local index = GetMacroIndexByName("HMF Focus")
        return (index and index > 0) and "macro" or nil
    end
    return (GetBindingText(key, "KEY_", true)) or key
end

-- Create/update a character macro "HMF Focus" that clicks the button, so it can sit on an action bar.
-- Returns ok, message. Out of combat only.
local MACRO_NAME = "HMF Focus"
function FocusButton.CreateMacro()
    if InCombatLockdown() then return false, "not in combat" end
    local body = "#showtooltip\n/click " .. NAME
    local icon = HMF.Adapters.Unit.FearIcon() or "INV_MISC_QUESTIONMARK"
    local index = GetMacroIndexByName(MACRO_NAME)
    if index and index > 0 then
        EditMacro(index, MACRO_NAME, icon, body)
        return true, 'macro "' .. MACRO_NAME .. '" updated. Open /macro > Character Macros and drag it to a bar.'
    end
    if not CreateMacro(MACRO_NAME, icon, body, true) then
        return false, "could not create the macro (character macro slots full?)"
    end
    return true, 'macro "' .. MACRO_NAME .. '" created. Open /macro > Character Macros and drag it to a bar.'
end
