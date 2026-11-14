--[[
    Lab/Cast.lua - Intended-vs-actual cast tracking shared by experiments.

    The secure button casts Fear with a unit token. The only way an addon
    can observe who actually got hit is the combat log (destGUID), so every
    click records an "intent" (PreClick) and the combat log supplies the
    "actual". Mismatch is logged loudly, and an in-flight cast whose bound
    token no longer matches the intended GUID is cancelled.
]]

local _, HMF = ...
local Lab = HMF.Lab

if not HMF.IS_WARLOCK then return end

local Cast = {}
Lab.Cast = Cast

local SPELL = "Fear"
local INTENT_TTL = 4 -- seconds an intent stays matchable
local pending
local resultHandlers = {}

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return (GetSpellInfo(id))
end
Lab.SpellName = SpellName

function Cast.OnResult(fn) resultHandlers[#resultHandlers + 1] = fn end
function Cast.Pending() return pending end

-- Called from each lab button's PreClick. guid = who we MEAN to hit.
function Cast.Intend(source, guid, token, row)
    local now = token and UnitGUID(token)
    pending = {
        source = source, guid = guid, token = token, row = row, t = GetTime(),
        stale = token ~= nil and now ~= guid,
        targetBefore = UnitGUID("target"),
    }
    Lab.Log("CLICK", "%s intended=%s token=%s tokenGUID=%s target=%s", source, Lab.Short(guid),
        token, Lab.Short(now), Lab.Short(pending.targetBefore))
    if pending.stale then
        Lab.Log("STALE", "%s: token %s now resolves to %s, intended %s", source, token, Lab.Short(now), Lab.Short(guid))
    end
end

local function Fresh()
    return pending and (GetTime() - pending.t) <= INTENT_TTL
end

local function Result(subevent, destGUID, destName)
    if not Fresh() then
        Lab.Log("CAST", "%s on %s (%s) with no recent lab click", subevent, destName, Lab.Short(destGUID))
        return
    end
    local ok = pending.guid == nil or pending.guid == destGUID
    Lab.Log(ok and "CAST" or "WRONG", "%s intended=%s actual=%s (%s) targetNow=%s", subevent,
        Lab.Short(pending.guid), Lab.Short(destGUID), destName, Lab.Short(UnitGUID("target")))
    for _, fn in ipairs(resultHandlers) do fn(pending, destGUID, subevent, ok) end
end

local f = CreateFrame("Frame")
for _, e in ipairs({
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "COMBAT_LOG_EVENT_UNFILTERED", "UI_ERROR_MESSAGE",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}) do
    f:RegisterEvent(e)
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, sub, _, srcGUID, _, _, _, dstGUID, dstName, _, _, _, spellName = CombatLogGetCurrentEventInfo()
        if srcGUID ~= UnitGUID("player") or spellName ~= SPELL then return end
        if sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED" or sub == "SPELL_MISSED" then
            Result(sub, dstGUID, dstName)
            if sub == "SPELL_AURA_APPLIED" and Lab.OnFeared then Lab.OnFeared(dstGUID, dstName) end
        end
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        local addon, func = ...
        Lab.blocked = (Lab.blocked or 0) + 1
        Lab.lastBlocked = func
        Lab.Log("BLOCKED", "%s addon=%s func=%s", event, addon, func)
    elseif event == "UI_ERROR_MESSAGE" then
        if Fresh() then Lab.Log("ERROR", "%s", select(2, ...)) end
    else
        local unit, a2, a3, a4 = ...
        if unit ~= "player" then return end
        if Fresh() then Lab.Log("EVT", "%s spell=%s", event, tostring(SpellName(event == "UNIT_SPELLCAST_SENT" and a4 or a3))) end
        local spellID = (event == "UNIT_SPELLCAST_SENT") and a4 or a3
        if SpellName(spellID) ~= SPELL then return end
        if event == "UNIT_SPELLCAST_SENT" then
            Lab.Log("SENT", "target name=%s", a2)
        elseif event == "UNIT_SPELLCAST_START" then
            local nowGUID = Fresh() and pending.token and UnitGUID(pending.token)
            if Fresh() and pending.token and pending.guid and nowGUID ~= pending.guid then
                SpellStopCasting()
                Lab.Log("ABORT", "cast cancelled: token %s is %s, intended %s", pending.token,
                    Lab.Short(nowGUID), Lab.Short(pending.guid))
            else
                Lab.Log("START", "cast started")
            end
        else
            Lab.Log((event:gsub("UNIT_SPELLCAST_", "")), "cast event: mouseover=%s target=%s focus=%s speed=%s",
                Lab.Short(UnitGUID("mouseover")), Lab.Short(UnitGUID("target")), Lab.Short(UnitGUID("focus")),
                tostring(GetUnitSpeed("player")))
        end
    end
end)
