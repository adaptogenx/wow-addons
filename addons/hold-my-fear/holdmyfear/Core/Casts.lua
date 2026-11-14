--[[
    Core/Casts.lua - Tracking from the player's own casts (Forever has no combat log).

    Forever hides the combat log and enemy auras from addon code, so the only reliable signal is the
    player's casts. UNIT_SPELLCAST_SENT names the target (a name only), which is locked to a GUID as
    the cast starts; when the same cast SUCCEEDS the mob is tracked with an estimated timer from the
    spell's known duration. The real timer on screen is drawn by the aura engine (UI/HUD.lua);
    this estimate drives row state, Fear colours and the fallback when no unit token shows the mob.
    Known limit: a resist, an early break or a dispel cannot be seen, so the estimate keeps running.
]]

local _, HMF = ...

local Casts = {}
HMF.Services.Casts = Casts

local C = HMF.Constants
local Tracker = HMF.Services.Tracker
local Encounter = HMF.Services.Encounter

local pending = {} -- castGUID -> { spell, spellID, guid, name }
local PENDING_TTL = 60

local function now()
    return GetTime and GetTime() or 0
end

-- Duration to assume for a DoT: what the engine bar actually showed last time, else the table.
local function duration(spell)
    local learned = HoldMyFearDB and HoldMyFearDB.learned
    return (learned and learned[spell]) or C.DEBUFF_ESTIMATES[spell]
end

local function usable(value, kind)
    return value ~= nil and not HMF.Adapters.Unit.IsSecret(value) and type(value) == kind
end

-- UNIT_SPELLCAST_SENT: target (a name), castGUID, spellID.
function Casts.OnSent(target, castGUID, spellID)
    if not (usable(target, "string") and target ~= "" and usable(castGUID, "string") and usable(spellID, "number")) then return end
    local spell = HMF.Adapters.Forever.TrackedName(spellID)
    if not spell then return end
    local guid = HMF.Adapters.Forever.LockCast(target)
    if not guid then return end
    pending[castGUID] = { spell = spell, spellID = spellID, guid = guid, name = target }
    C_Timer.After(PENDING_TTL, function() pending[castGUID] = nil end)
end

-- UNIT_SPELLCAST_SUCCEEDED: only the mob locked as the cast started, never one found by name now.
function Casts.OnSucceeded(castGUID)
    if not usable(castGUID, "string") then return end
    local cast = pending[castGUID]
    pending[castGUID] = nil
    if not cast or Encounter.IsDead(cast.guid) then return end
    local t = now()
    if cast.spell == C.FEAR_SPELL then
        if not Encounter.TrackForFear(cast.guid, cast.name) then return end
        local duration = C.FEAR_DURATIONS[cast.spellID] or C.DEFAULT_FEAR_DURATION
        Tracker.SetFear(cast.guid, t + duration, duration, true)
    else
        if not Tracker.Track(cast.guid, cast.name, cast.spell .. " cast") then return end
        local length = duration(cast.spell)
        Tracker.SetDebuff(cast.guid, cast.spell, {
            icon = HMF.Adapters.Forever.IconFor(cast.spellID),
            duration = length,
            expires = length and (t + length) or nil,
            estimated = true,
            castAt = t,
            damage = C.DAMAGE_DOTS[cast.spell] and HMF.Adapters.Unit.DotDamage and HMF.Adapters.Unit.DotDamage(cast.spellID) or nil,
        })
    end
end

function Casts.OnFailed(castGUID)
    if usable(castGUID, "string") then pending[castGUID] = nil end
end

-- UNIT_HEALTH on a unit token: drop the mob when it reads dead.
function Casts.OnHealth(token)
    if not token or not HMF.Adapters.Unit.IsDead(token) then return end
    local guid = HMF.Adapters.Unit.GUID(token) or HMF.Adapters.Unit.PlateGUID(token)
    if guid and Tracker.Get(guid) then Encounter.MarkDead(guid) end
end

-- The aura engine's bar is the truth where a unit shows the mob. `shown` = whether it is drawing
-- this spell now (true/false, nil = unreadable). Gone shortly after the cast = resisted, broken,
-- dispelled or expired; still up past the estimate = the estimate was short, so keep it alive.
function Casts.Reconcile(guid, spell, shown)
    local entry = Tracker.Get(guid)
    if not entry or shown == nil then return end
    local t = now()
    if spell == C.FEAR_SPELL then
        local f = entry.fear
        if not f then return end
        if shown == false then
            if t - (f.expires - (f.duration or 0)) < C.RECONCILE_GRACE then return end
            local left = Tracker.FearRemaining(entry, t)
            Tracker.ClearFear(guid, "engine: Fear bar gone", left and left > C.BROKEN_MIN_LEFT or false)
        elseif f.estimated and t >= f.expires - 0.5 then
            Tracker.SetFear(guid, t + 1, f.duration, true)
        end
        return
    end
    local d = entry.debuffs and entry.debuffs[spell]
    if not d then return end
    if shown == false then
        local age = t - (d.castAt or t)
        if age < C.RECONCILE_GRACE then return end
        -- The bar was up and is now gone after a full run: that is the spell's real duration.
        if d.seenShown and age >= 3 and HoldMyFearDB then
            HoldMyFearDB.learned = HoldMyFearDB.learned or {}
            HoldMyFearDB.learned[spell] = math.floor((age - 0.15) * 10 + 0.5) / 10
        end
        Tracker.ClearDebuff(guid, spell, "engine: bar gone")
    else
        d.seenShown = true
        if d.expires and t >= d.expires - 0.5 then
            Tracker.SetDebuff(guid, spell, { icon = d.icon, duration = d.duration, castAt = d.castAt, estimated = true,
                seenShown = true, expires = t + 1, damage = d.damage })
        end
    end
end

function Casts.Reset() pending = {} end
