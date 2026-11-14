--[[
    Core/Encounter.lua - Turns game signals into Tracker changes.

    Tracking starts when the player's Fear lands on a mob. A tracked mob
    keeps its marker/row until it dies or combat ends (after a short delay).
    Adapters are resolved at call time so tests can stub them.
]]

local _, HMF = ...

local Encounter = {}
HMF.Services.Encounter = Encounter

local C = HMF.Constants
local Tracker = HMF.Services.Tracker

local dead = {} -- GUIDs that died this encounter; never re-tracked

local function now()
    return GetTime and GetTime() or 0
end

local wantedSet
local function wanted()
    if not wantedSet then
        wantedSet = {}
        for _, name in ipairs(C.TRACKED_DEBUFFS) do wantedSet[name] = true end
    end
    return wantedSet
end

local function refreshDebuffs(entry, token)
    for _, d in ipairs(HMF.Adapters.Aura.PlayerDebuffs(token, wanted())) do
        Tracker.SetDebuff(entry.guid, d.name, { icon = d.icon, duration = d.duration, expires = d.expires, estimated = false })
    end
end

-- Apply the best Fear data for an entry: aura scan if a token reads, else estimate.
local function refreshFear(entry, token)
    if token then
        local duration, expires = HMF.Adapters.Aura.PlayerDebuff(token, C.FEAR_SPELL)
        if expires then
            Tracker.SetFear(entry.guid, expires, duration, false)
            return
        end
    end
end

-- Track a Fear target even when every marker is taken by unfeared mobs: drop one unfeared row.
local function trackForFear(guid, name)
    local entry = Tracker.Track(guid, name, "Fear applied")
    if entry then return entry end
    for _, e in ipairs(Tracker.List()) do
        if not e.fear then
            Encounter.Untrack(e.guid, "evicted for a Fear target")
            break
        end
    end
    return Tracker.Track(guid, name, "Fear applied (after eviction)")
end

function Encounter.TrackForFear(guid, name) return trackForFear(guid, name) end

-- A mob that died is dropped and never re-tracked this encounter (Forever: from UNIT_HEALTH).
function Encounter.MarkDead(guid)
    if not guid then return end
    dead[guid] = true
    if Tracker.Get(guid) then Encounter.Untrack(guid, "died") end
end

function Encounter.IsDead(guid) return dead[guid] == true end

-- Creature GUID that is fighting the player, from a damage/miss combat-log event.
local function engagedMob(ev, playerGUID)
    local sub = ev.sub
    if not (sub:find("_DAMAGE$") or sub:find("_MISSED$")) then return nil end
    if ev.srcGUID == playerGUID and ev.dstGUID and ev.dstGUID:find("^Creature") then
        return ev.dstGUID, ev.dstName
    elseif ev.dstGUID == playerGUID and ev.srcGUID and ev.srcGUID:find("^Creature") then
        return ev.srcGUID, ev.srcName
    end
end

function Encounter.OnCombatLog(ev)
    if ev.sub == "UNIT_DIED" then
        if ev.dstGUID then dead[ev.dstGUID] = true end
        if Tracker.Get(ev.dstGUID) then Encounter.Untrack(ev.dstGUID, "died") end
        return
    end
    local playerGUID = HMF.Adapters.Unit.PlayerGUID()
    if ev.srcGUID == playerGUID and wanted()[ev.spellName or ""] then
        Encounter.OnDebuffEvent(ev)
        return
    end
    if ev.spellName ~= C.FEAR_SPELL or ev.srcGUID ~= playerGUID then
        local guid, name = engagedMob(ev, playerGUID)
        if guid and not dead[guid] and not Tracker.Get(guid) then
            local token = HMF.Adapters.Unit.TokenFor(guid)
            if not token or HMF.Adapters.Unit.CanAttack(token) then
                if Tracker.Track(guid, name, "combat log " .. ev.sub) and token then Encounter.OnUnitSeen(token) end
            end
        end
        return
    end

    if ev.sub == "SPELL_AURA_APPLIED" or ev.sub == "SPELL_AURA_REFRESH" then
        if ev.dstGUID then dead[ev.dstGUID] = nil end
        local entry = trackForFear(ev.dstGUID, ev.dstName)
        if not entry then return end
        local token = HMF.Adapters.Unit.TokenFor(ev.dstGUID)
        Tracker.SetFear(ev.dstGUID, now() + C.DEFAULT_FEAR_DURATION, C.DEFAULT_FEAR_DURATION, true)
        if token then Encounter.OnUnitSeen(token) end
    elseif ev.sub == "SPELL_AURA_REMOVED" then
        -- Early break only when the duration was confirmed by an aura scan and plenty remained.
        local e = Tracker.Get(ev.dstGUID)
        local left = e and e.fear and not e.fear.estimated and Tracker.FearRemaining(e)
        Tracker.ClearFear(ev.dstGUID, "combat log: Fear removed", left and left > C.BROKEN_MIN_LEFT or false)
    end
end

-- A token (nameplate/target/focus/mouseover) became readable or its auras changed.
function Encounter.OnUnitSeen(token)
    local guid = HMF.Adapters.Unit.GUID(token)
    local entry = guid and Tracker.Get(guid)
    if not entry then return end
    entry.lastSeen = now()
    local name, level = HMF.Adapters.Unit.Info(token)
    Tracker.SetInfo(guid, name, level)
    if HMF.Adapters.Unit.GetMarker(token) ~= entry.marker then
        HMF.Adapters.Unit.SetMarker(token, entry.marker)
    end
    refreshFear(entry, token)
    refreshDebuffs(entry, token)
end

-- Player-applied tracked debuff (DoT/curse) landed, refreshed or ended.
function Encounter.OnDebuffEvent(ev)
    local guid, spell = ev.dstGUID, ev.spellName
    if not guid then return end
    if ev.sub == "SPELL_AURA_REMOVED" then
        Tracker.ClearDebuff(guid, spell, "combat log: " .. spell .. " removed")
        return
    end
    if ev.sub ~= "SPELL_AURA_APPLIED" and ev.sub ~= "SPELL_AURA_REFRESH" and ev.sub ~= "SPELL_AURA_APPLIED_DOSE" then return end
    if dead[guid] or not guid:find("^Creature") then return end
    local entry = Tracker.Track(guid, ev.dstName, spell .. " applied")
    if not entry then return end
    local estimate = C.DEBUFF_ESTIMATES[spell]
    Tracker.SetDebuff(guid, spell, {
        icon = HMF.Adapters.Unit.SpellIcon(spell),
        duration = estimate,
        expires = estimate and (now() + estimate) or nil,
        estimated = true,
        damage = C.DAMAGE_DOTS[spell] and HMF.Adapters.Unit.DotDamage and HMF.Adapters.Unit.DotDamage(spell) or nil,
    })
    local token = HMF.Adapters.Unit.TokenFor(guid)
    if token then Encounter.OnUnitSeen(token) end
end

-- Targeting a living hostile creature gives it a row at once (no cast needed). Rows with no Fear,
-- no DoTs and no combat go again via Prune once the target moves on.
function Encounter.TrackTarget()
    local Unit = HMF.Adapters.Unit
    local guid = Unit.GUID("target")
    if not guid or dead[guid] or not (guid:find("^Creature") or guid:find("^Vehicle")) then return end
    if not Unit.CanAttack("target") or Unit.IsDead("target") then return end
    if Tracker.Get(guid) then return end
    local name = Unit.Info("target")
    if Tracker.Track(guid, name, "target") then Encounter.OnUnitSeen("target") end
end

-- Target cleared (Esc or a click on nothing): out of combat that drops every row, Fear and DoT
-- timers included. In combat only idle rows go (Prune), so nothing running is lost mid-fight.
-- Returns true when everything was cleared.
function Encounter.OnTargetCleared()
    if HMF.Adapters.Unit.GUID("target") then return false end
    if HMF.Adapters.Unit.InCombat("player") then
        Encounter.Prune()
        return false
    end
    Encounter.Reset("target cleared out of combat")
    return true
end

-- Track every mob already fighting the player (combat start, new nameplates, threat updates).
function Encounter.ScanEngaged()
    for _, hit in ipairs(HMF.Adapters.Unit.EngagedTokens()) do
        local token = hit.token
        local guid = HMF.Adapters.Unit.GUID(token)
        if guid and not dead[guid] and not Tracker.Get(guid) then
            local name = HMF.Adapters.Unit.Info(token)
            if Tracker.Track(guid, name, "scan " .. token .. " " .. hit.detail) then Encounter.OnUnitSeen(token) end
        end
    end
end

-- Safety net for rows whose death/leave event was missed. Drops a row when its unit reads dead,
-- or when it has no Fear and no DoTs and either left combat (readable) or has been unreadable
-- for STALE_SECONDS. Never touches a row with a running Fear. Called on a timer from Events.lua.
function Encounter.Prune()
    local t = now()
    for _, e in ipairs(Tracker.List()) do
        local token = HMF.Adapters.Unit.TokenFor(e.guid)
        if token then e.lastSeen = t end
        if token and HMF.Adapters.Unit.IsDead(token) then
            dead[e.guid] = true
            Encounter.Untrack(e.guid, "pruned: dead")
        elseif HMF.Adapters.Unit.GUID("target") == e.guid then
            e.lastSeen = t -- your current target keeps its row
        elseif not Tracker.FearRemaining(e, t) and #Tracker.ActiveDebuffs(e, t) == 0 then
            if not HMF.Adapters.Unit.InCombat("player") then
                -- Idle (no Fear, no DoTs), not your target, and you are out of combat: nothing to manage.
                Encounter.Untrack(e.guid, "pruned: idle, out of combat")
            elseif token then
                if t - e.addedAt > C.PRUNE_GRACE and not HMF.Adapters.Unit.InCombat(token) then
                    Encounter.Untrack(e.guid, "pruned: left combat")
                end
            elseif t - (e.lastSeen or e.addedAt) > C.STALE_SECONDS then
                Encounter.Untrack(e.guid, "pruned: stale")
            end
        end
    end
end

-- Refresh the bearing of every enemy whose nameplate is readable. Called from a timer in Events.lua.
function Encounter.UpdateBearings()
    for _, e in ipairs(Tracker.List()) do
        local token = HMF.Adapters.Unit.TokenFor(e.guid)
        local bearing = token and HMF.Adapters.Unit.WorldBearing(token)
        if bearing then Tracker.SetBearing(e.guid, bearing) end
    end
end

function Encounter.Untrack(guid, reason)
    local entry = Tracker.Get(guid)
    if not entry then return end
    local token = HMF.Adapters.Unit.TokenFor(guid)
    if token and HMF.Adapters.Unit.GetMarker(token) == entry.marker then HMF.Adapters.Unit.SetMarker(token, 0) end
    Tracker.Untrack(guid, reason)
end

function Encounter.Reset(reason)
    for _, entry in ipairs(Tracker.List()) do
        local token = HMF.Adapters.Unit.TokenFor(entry.guid)
        if token and HMF.Adapters.Unit.GetMarker(token) == entry.marker then HMF.Adapters.Unit.SetMarker(token, 0) end
    end
    dead = {}
    Tracker.Reset(reason or "reset")
end

-- After combat ends, wait RESET_DELAY, then reset - but never while a Fear is still counting down
-- (feared mobs often drop combat; the player is still managing them).
function Encounter.ScheduleReset()
    C_Timer.After(C.RESET_DELAY, function()
        if InCombatLockdown() then return end
        if Tracker.AnyFearActive() then
            Encounter.ScheduleReset()
        else
            Encounter.Reset("combat ended")
        end
    end)
end

-- Debug helper (/hmf demo): track a token as if it had just been feared.
function Encounter.TrackToken(token)
    local guid = HMF.Adapters.Unit.GUID(token)
    if not guid then return nil end
    local name = HMF.Adapters.Unit.Info(token)
    local entry = Tracker.Track(guid, name, "demo")
    if not entry then return nil end
    Tracker.SetFear(guid, now() + C.DEFAULT_FEAR_DURATION, C.DEFAULT_FEAR_DURATION, true)
    Encounter.OnUnitSeen(token)
    return entry
end
