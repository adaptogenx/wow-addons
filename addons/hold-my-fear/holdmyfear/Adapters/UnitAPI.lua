--[[
    Adapters/UnitAPI.lua - Unit/nameplate/marker access.

    Lab findings (.plans/LAB_REPORT.md): nameplate tokens are readable for
    GUID/name/level/portrait/markers but unusable as spell/target units.
]]

local _, HMF = ...

local Unit = {}
HMF.Adapters.Unit = Unit

local tokenByGUID = {} -- guid -> nameplate token
local guidByToken = {}
local plateMemory = {}    -- nameplate token -> guid, learned via UnitIsUnit when the plate's own GUID is secret

-- Forever hands out "secret values" in combat: they may be stored and passed on, never compared or
-- printed. Every reader below gives nil for one, so callers never touch a secret.
function Unit.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end
local isSecret = Unit.IsSecret

local function readGUID(token)
    local ok, guid = pcall(UnitGUID, token)
    if ok and type(guid) == "string" and not isSecret(guid) then return guid end
    return nil
end

-- Only booleans that are not secret count; a secret "true" is treated as false.
local function readTrue(fn, ...)
    local ok, value = pcall(fn, ...)
    return ok and not isSecret(value) and value == true
end

function Unit.PlayerGUID() return UnitGUID("player") end
function Unit.GUID(token) return readGUID(token) end

function Unit.OnPlateAdded(token)
    plateMemory[token] = nil
    local guid = readGUID(token)
    if not guid then Unit.LearnPlate(token) return nil end
    tokenByGUID[guid] = token
    guidByToken[token] = guid
    return guid
end

function Unit.OnPlateRemoved(token)
    plateMemory[token] = nil
    local guid = guidByToken[token]
    if guid and tokenByGUID[guid] == token then tokenByGUID[guid] = nil end
    guidByToken[token] = nil
end

-- A plate whose GUID is secret: learn which mob it shows from target/focus, whose GUIDs read fine.
function Unit.LearnPlate(token)
    if not UnitExists(token) then return end
    local guid = readGUID(token)
    if guid then
        tokenByGUID[guid], guidByToken[token] = token, guid
        return
    end
    for _, known in ipairs({ "target", "focus" }) do
        if readTrue(UnitIsUnit, token, known) then
            plateMemory[token] = readGUID(known) or plateMemory[token]
            return
        end
    end
end

function Unit.LearnPlates()
    for i = 1, 40 do Unit.LearnPlate("nameplate" .. i) end
end

-- The mob a nameplate token was learned to show (GUID secret), or nil.
function Unit.PlateGUID(token) return plateMemory[token] end

-- Best currently-valid token that reads this GUID, or nil. `stable` skips mouseover, which moves
-- with the pointer and has no event to rebind on (right for binding engine aura containers).
function Unit.TokenFor(guid, stable)
    local token = tokenByGUID[guid]
    if token and readGUID(token) == guid then return token end
    for _, t in ipairs({ "target", "focus", "mouseover" }) do
        if not (stable and t == "mouseover") and readGUID(t) == guid then return t end
    end
    for t, g in pairs(plateMemory) do
        if g == guid and UnitExists(t) then return t end
    end
    return nil
end

-- GUID of the player's current focus, or nil.
function Unit.FocusGUID()
    return UnitExists("focus") and readGUID("focus") or nil
end

function Unit.IsDead(token)
    return UnitExists(token) and readTrue(UnitIsDead, token)
end

function Unit.InCombat(token)
    return UnitExists(token) and readTrue(UnitAffectingCombat, token)
end

-- A secret answer counts as "yes" so an unreadable plate is not dropped (Forever's WTF does the same).
function Unit.CanAttack(token)
    if not UnitExists(token) then return false end
    local ok, value = pcall(UnitCanAttack, "player", token)
    if not ok then return false end
    if isSecret(value) then return true end
    return value and true or false
end

-- Hostile unit that is in combat with the player (on its threat list, or targeting the player).
-- Returns engaged (bool), detail string for tracing.
function Unit.IsEngaged(token)
    if not UnitExists(token) or readTrue(UnitIsDead, token) then return false, "dead/none" end
    if not (Unit.CanAttack(token) and Unit.InCombat(token)) then return false, "not hostile+combat" end
    local ok, threat = pcall(UnitThreatSituation, "player", token)
    if not ok or isSecret(threat) or type(threat) ~= "number" then threat = nil end
    local onMe = readTrue(UnitIsUnit, token .. "target", "player")
    if onMe or (threat and threat > 0) then
        return true, ("threat=%s targetingMe=%s"):format(tostring(threat), tostring(onMe))
    end
    return false, ("threat=%s targetingMe=false"):format(tostring(threat))
end

-- Tokens (nameplates + target) currently engaged with the player.
function Unit.EngagedTokens()
    local list = {}
    for token in pairs(guidByToken) do
        local ok, detail = Unit.IsEngaged(token)
        if ok then list[#list + 1] = { token = token, detail = detail } end
    end
    local ok, detail = Unit.IsEngaged("target")
    if ok then list[#list + 1] = { token = "target", detail = detail } end
    return list
end

-- Returns name, level (level -1 = unknown/skull).
function Unit.Info(token)
    local okN, name = pcall(UnitName, token)
    local okL, level = pcall(UnitLevel, token)
    if not okN or isSecret(name) or type(name) ~= "string" then name = nil end
    if not okL or isSecret(level) or type(level) ~= "number" then level = nil end
    return name, level
end

function Unit.GetMarker(token)
    local ok, index = pcall(GetRaidTargetIndex, token)
    if not ok or isSecret(index) then return nil end
    return index
end

-- Forever build interface numbers are 16xxx (same rule as Pockets' ClientAPI).
function Unit.IsForever()
    local toc = GetBuildInfo and select(4, GetBuildInfo())
    toc = tonumber(toc)
    return toc ~= nil and toc >= 16000 and toc <= 16999
end

-- Forever blocks addons from calling SetRaidTarget (Blizzard "blocked action" prompt, even under
-- pcall), so markers are HUD-only there. Never call it on Forever.
function Unit.SetMarker(token, index)
    if Unit.IsForever() then return false end
    return pcall(SetRaidTarget, token, index)
end

function Unit.SetPortrait(texture, token)
    SetPortraitTexture(texture, token)
end

-- Icon of a spell the player knows (nil if unknown).
function Unit.SpellIcon(spellName)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellName) end
    return GetSpellTexture and GetSpellTexture(spellName)
end

-- Health for a StatusBar: (current, max), which may be secret on Forever. A StatusBar takes secrets
-- (SetMinMaxValues/SetValue); never compare or do arithmetic on them. nil when unreadable.
function Unit.Health(token)
    if not UnitExists(token) then return nil end
    local ok, cur, max = pcall(function() return UnitHealth(token), UnitHealthMax(token) end)
    if not ok or cur == nil or max == nil then return nil end
    return cur, max
end

-- "73%" for a FontString (the text may be a secret string: only pass it to SetText), or "".
function Unit.HealthPercentText(token)
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, text = pcall(function()
            return string.format("%d%%", UnitHealthPercent(token, true, CurveConstants.ScaleTo100))
        end)
        if ok and text then return text end
    end
    local cur, max = Unit.Health(token)
    if cur and max and not isSecret(cur) and not isSecret(max) and type(cur) == "number" and max > 0 then
        return string.format("%d%%", math.floor(cur / max * 100 + 0.5))
    end
    return ""
end

-- A plain number for the health %, or nil when secret/unreadable.
function Unit.HealthPercentValue(token)
    if not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100) then return nil end
    local ok, pct = pcall(UnitHealthPercent, token, true, CurveConstants.ScaleTo100)
    if ok and type(pct) == "number" and not isSecret(pct) then return pct end
    return nil
end

-- Total damage a DoT does over its full duration at the player's current power, read from the
-- spell's own description ("... 822 Shadow damage over 18 sec"); nil when it cannot be read.
-- `spell` is a name (highest known rank) or a spell ID.
function Unit.DotDamage(spell)
    local text
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, value = pcall(C_Spell.GetSpellDescription, spell)
        if ok then text = value end
    elseif GetSpellDescription then
        local ok, value = pcall(GetSpellDescription, spell)
        if ok then text = value end
    end
    if type(text) ~= "string" or isSecret(text) then return nil end
    local last
    for num in text:gmatch("(%d[%d,]*)%s+%a+%s+damage over") do last = num end
    if not last then
        for num in text:gmatch("(%d[%d,]*)%s+damage over") do last = num end
    end
    last = last and tonumber((last:gsub(",", "")))
    return last, text
end

-- The name to put in a /cast macro for a tracked spell: its own name, else its Forever alias,
-- whichever the player knows (the macro then casts the highest known rank). nil when unknown.
function Unit.CastName(name)
    for _, n in ipairs({ name, HMF.Constants.SPELL_ALIASES[name] }) do
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(n)
        if info then return n end
    end
    return nil
end

-- Does the player know this spell (any rank, or its Forever alias)? Cached; call InvalidateKnown on SPELLS_CHANGED.
local knownCache = {}
function Unit.InvalidateKnown() knownCache = {} end
function Unit.Knows(name)
    local cached = knownCache[name]
    if cached ~= nil then return cached end
    local C = HMF.Constants
    local known = false
    for _, id in ipairs(C.SPELL_IDS[name] or {}) do
        if IsPlayerSpell and IsPlayerSpell(id) then known = true break end
    end
    if not known then
        for _, n in ipairs({ name, C.SPELL_ALIASES[name] }) do
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(n)
            if info then known = true break end
        end
    end
    knownCache[name] = known
    return known
end

function Unit.FearIcon()
    return Unit.SpellIcon(HMF.Constants.FEAR_SPELL)
end

-- Player's actual Fear cast time in seconds (includes haste/talent modifiers), or nil.
function Unit.FearCastTime()
    local ms
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(HMF.Constants.FEAR_SPELL)
        ms = info and info.castTime
    elseif GetSpellInfo then
        ms = select(4, GetSpellInfo(HMF.Constants.FEAR_SPELL))
    end
    return ms and ms > 0 and ms / 1000 or nil
end

function Unit.Facing() return GetPlayerFacing and GetPlayerFacing() or nil end

-- Horizontal centre of a unit's nameplate in UIParent coordinates, or nil + reason.
-- Nameplates can be restricted (measuring errors), so every strategy runs under pcall.
-- Never anchor our own frames to a nameplate: Forever treats that as a blocked protected action.
local function Measure(region)
    local ok, x = pcall(region.GetCenter, region)
    if ok and x then return x * region:GetEffectiveScale() / UIParent:GetEffectiveScale() end
    return nil, ok and "nil centre" or tostring(x)
end

local STRATEGIES = {
    { "plate", function(plate) return Measure(plate) end },
    { "unitframe", function(plate) return plate.UnitFrame and Measure(plate.UnitFrame) end },
    { "healthbar", function(plate)
        return plate.UnitFrame and plate.UnitFrame.healthBar and Measure(plate.UnitFrame.healthBar)
    end },
}

-- Returns x, strategyName on success; nil, "name: reason; ..." on failure.
local function PlateX(token)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(token)
    if not plate then return nil, "no plate" end
    if not plate:IsVisible() then return nil, "plate hidden" end
    local why = {}
    for _, st in ipairs(STRATEGIES) do
        local x, err = st[2](plate)
        if x then return x, st[1] end
        why[#why + 1] = st[1] .. ": " .. tostring(err)
    end
    return nil, table.concat(why, "; ")
end

-- Compass bearing (radians, counter-clockwise like GetPlayerFacing) toward a unit, from where its
-- nameplate sits on screen. Assumes the camera looks along the player's heading.
-- UnitPosition does not work on hostile NPCs, so this is the only source.
function Unit.WorldBearing(token)
    local facing = Unit.Facing()
    if not facing then return nil, "no facing" end
    local x, via = PlateX(token)
    if not x then return nil, via end
    local half = UIParent:GetWidth() / 2
    local frac = math.max(-1, math.min(1, (x - half) / half))
    return facing - math.atan(frac * math.tan(HMF.Constants.HUD.ARROW_HALF_FOV)), via
end
