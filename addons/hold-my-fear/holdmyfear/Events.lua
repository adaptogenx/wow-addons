--[[
    Events.lua - Cross-cutting event wiring and slash commands
]]

local _, HMF = ...

if not HMF.IS_WARLOCK then return end

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_AURA",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELLS_CHANGED", "UNIT_THREAT_LIST_UPDATE",
    "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED",
}) do
    frame:RegisterEvent(event)
end
-- Forever restricts addon access to the combat log: registering for it raises the Blizzard
-- "blocked action" prompt at load. Suspected (not yet confirmed) - skip it there.
local FOREVER = HMF.Adapters.Unit.IsForever()
if not FOREVER then
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
else
    -- Forever: track from the player's own casts, and learn deaths from health updates.
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    frame:RegisterEvent("UNIT_HEALTH")
end

local function Rebind()
    if FOREVER and HMF.UI.HUD.Rebind then HMF.UI.HUD.Rebind() end
end

local function Seen(token)
    if token and UnitExists(token) then HMF.Services.Encounter.OnUnitSeen(token) end
end

-- Blocked/forbidden protected calls: print which function and from where (once per function),
-- since the Blizzard prompt itself does not say.
local reported = {}
local function ReportBlocked(event, addon, func)
    if addon ~= HMF.ADDON_NAME then return end
    local key = tostring(func)
    if reported[key] then return end
    reported[key] = true
    local stack = (debugstack and debugstack(3, 8, 0)) or "no stack"
    print("|cffff5555HMF BLOCKED|r", event, key)
    -- Saved to disk so it can be read from the SavedVariables file after /logout.
    HoldMyFearDB = HoldMyFearDB or {}
    HoldMyFearDB.blocked = HoldMyFearDB.blocked or {}
    HoldMyFearDB.blocked[#HoldMyFearDB.blocked + 1] = { event = event, func = key, stack = stack }
end

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "SPELLS_CHANGED" then
        HMF.Adapters.Unit.InvalidateKnown()
        if HMF.UI.CastButtons then HMF.UI.CastButtons.Refresh() end
        if FOREVER and HMF.UI.HUD.RefreshFilters then HMF.UI.HUD.RefreshFilters() end
        return
    elseif event == "UNIT_SPELLCAST_SENT" then
        HMF.Services.Casts.OnSent(arg2, arg3, arg4) -- unit, target name, castGUID, spellID
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        HMF.Services.Casts.OnSucceeded(arg2) -- unit, castGUID
        return
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        HMF.Services.Casts.OnFailed(arg2)
        return
    elseif event == "UNIT_HEALTH" then
        if type(arg1) == "string" and (arg1 == "target" or arg1 == "focus" or arg1:find("^nameplate")) then
            HMF.Services.Casts.OnHealth(arg1)
        end
        return
    end
    if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
        ReportBlocked(event, arg1, arg2)
        return
    end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        HMF.Services.Encounter.OnCombatLog(HMF.Adapters.CombatLog.Read())
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        HMF.Adapters.Unit.OnPlateAdded(arg1)
        Rebind()
        Seen(arg1)
        if InCombatLockdown() then HMF.Services.Encounter.ScanEngaged() end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        HMF.Adapters.Unit.OnPlateRemoved(arg1)
        Rebind()
    elseif event == "UNIT_AURA" then
        if arg1 and (arg1:find("^nameplate") or arg1 == "target" or arg1 == "focus") then Seen(arg1) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if not HMF.Adapters.Unit.GUID("target") then
            HMF.Services.Encounter.OnTargetCleared() -- Esc: clear everything out of combat
        else
            HMF.Services.Encounter.TrackTarget()
            HMF.Services.Encounter.Prune() -- the mob you clicked off of goes now, not at the next sweep
        end
        if HMF.UI.HUD.UpdateFocusRows then HMF.UI.HUD.UpdateFocusRows() end -- click blockers follow the target
        Rebind()
        Seen("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if HMF.UI.HUD.UpdateFocusRows then HMF.UI.HUD.UpdateFocusRows() end
        Rebind()
        Seen("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Seen("mouseover")
    elseif event == "PLAYER_REGEN_DISABLED" then
        HMF.Services.Encounter.ScanEngaged()
        C_Timer.After(0.3, HMF.Services.Encounter.ScanEngaged)
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        if InCombatLockdown() then HMF.Services.Encounter.ScanEngaged() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        HMF.Services.Encounter.ScheduleReset()
    elseif event == "ADDON_LOADED" and arg1 == HMF.ADDON_NAME then
        HoldMyFearDB = HoldMyFearDB or {}
    elseif event == "PLAYER_LOGIN" then
        local skip = HoldMyFearDB.skip or {} -- bisect switches: /hmf skip hud|focus|events
        if not skip.hud then
            HMF.UI.HUD.Init()
            if FOREVER then HMF.UI.HUD.RefreshFilters() end
        end
        if not skip.focus then HMF.UI.FocusButton.Init() end
        if skip.events then frame:UnregisterAllEvents() end
        C_Timer.NewTicker(HMF.Constants.HUD.TICK, function()
            if HMF.Services.Tracker.Count() > 0 then HMF.Services.Encounter.UpdateBearings() end
        end)
        C_Timer.NewTicker(HMF.Constants.PRUNE_TICK, function()
            if HMF.Services.Tracker.Count() > 0 then HMF.Services.Encounter.Prune() end
        end)
    end
end)

SLASH_HOLDMYFEAR1 = "/hmf"
SlashCmdList["HOLDMYFEAR"] = function(msg)
    HMF.Debug.HandleSlash(msg)
end
