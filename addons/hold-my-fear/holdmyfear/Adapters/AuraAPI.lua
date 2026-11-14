--[[
    Adapters/AuraAPI.lua - Player-owned debuff lookup on a unit token.
]]

local _, HMF = ...

local Aura = {}
HMF.Adapters.Aura = Aura

-- Returns duration, expirationTime for a debuff the player applied, or nil.
local function PlayerDebuffRaw(token, spellName)
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        local data = C_UnitAuras.GetAuraDataBySpellName(token, spellName, "HARMFUL|PLAYER")
        if data and data.expirationTime and data.expirationTime > 0 then
            return data.duration, data.expirationTime
        end
        return nil
    end
    if UnitDebuff then
        for i = 1, 40 do
            local name, _, _, _, duration, expiration, caster = UnitDebuff(token, i)
            if not name then break end
            if name == spellName and caster == "player" and expiration and expiration > 0 then
                return duration, expiration
            end
        end
    end
    return nil
end

-- Every player-applied debuff on the unit whose name is in `wanted` (set).
-- Returns array of { name, icon, duration, expires } (expires nil when the aura has no timer).
local function PlayerDebuffsRaw(token, wanted)
    local out = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local d = C_UnitAuras.GetAuraDataByIndex(token, i, "HARMFUL|PLAYER")
            if not d then break end
            if wanted[d.name] then
                out[#out + 1] = {
                    name = d.name, icon = d.icon, duration = d.duration,
                    expires = (d.expirationTime and d.expirationTime > 0) and d.expirationTime or nil,
                }
            end
        end
    elseif UnitDebuff then
        for i = 1, 40 do
            local name, icon, _, _, duration, expiration, caster = UnitDebuff(token, i)
            if not name then break end
            if wanted[name] and caster == "player" then
                out[#out + 1] = {
                    name = name, icon = icon, duration = duration,
                    expires = (expiration and expiration > 0) and expiration or nil,
                }
            end
        end
    end
    return out
end

-- Forever blocks addon reads of enemy auras ("secret values"), which errors. Treat as unreadable;
-- callers then keep the combat-log estimates.
function Aura.PlayerDebuff(token, spellName)
    local ok, duration, expires = pcall(PlayerDebuffRaw, token, spellName)
    if ok then return duration, expires end
    return nil
end

function Aura.PlayerDebuffs(token, wanted)
    local ok, out = pcall(PlayerDebuffsRaw, token, wanted)
    if ok and out then return out end
    return {}
end
