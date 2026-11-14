--[[
    M2: Fear & debuff tracking probes.
    - spells: learned Warlock spell IDs
    - auras:  GetUnitAuraBySpellID + per-field accessibility
    - enum:   aura enumeration, gated by C_Secrets answers
    - secrecy: C_Secrets.Should* answers (log in and out of combat)
    - aurawatch on|off: UNIT_AURA payload accessibility + add/refresh/remove tracking
    - auracontainer: inspect Forever's native aura widgets (names/types only)
    - m2hud on|off: diagnostic cooldown widgets for target/focus (native vs addon-side)
    Estimated timers are logged as ESTIMATE only and never drive state.
]]
local _, Lab = ...

local CANDIDATES = {
    Fear = { 5782, 6213, 6215 },
    Corruption = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },
    ["Curse of Agony"] = { 980, 1014, 6217, 11711, 11712, 11713 },
    Immolate = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },
    ["Curse of Weakness"] = { 702, 1108, 6205, 7646, 11707, 11708 },
    ["Curse of Recklessness"] = { 704, 7658, 7659, 11717 },
    ["Siphon Life"] = { 18265, 18879, 18880, 18881 },
    ["Death Coil"] = { 6789, 17925, 17926 },
    ["Howl of Terror"] = { 5484, 17928 },
}
local ORDER = { "Fear", "Corruption", "Curse of Agony", "Immolate", "Curse of Weakness", "Curse of Recklessness",
    "Siphon Life", "Death Coil", "Howl of Terror" }
local FIELDS = { "name", "spellId", "auraInstanceID", "duration", "expirationTime", "applications", "sourceUnit",
    "isHarmful", "icon", "dispelName", "timeMod" }

local known = {}   -- spellID -> family name
local knownList = {}
local stats = {}   -- field -> status -> count
local payload = {} -- label -> status -> count
local tracked = {} -- unit..":"..instanceID -> info
local loggedSig = {}
local m2 = { stats = stats, payload = payload, tracked = tracked, est = {} }
Lab.m2 = m2

local function bump(t, a, b) t[a] = t[a] or {} t[a][b] = (t[a][b] or 0) + 1 end

local function isKnownSpell(id)
    for _, name in ipairs({ "IsPlayerSpell", "IsSpellKnown" }) do
        local fn = _G[name]
        if fn then
            local st, v = Lab.Probe(fn, id)
            if st == "READABLE" and v then return true end
        end
    end
    local sb = Lab.Resolve("C_SpellBook.IsSpellKnown")
    if sb then local st, v = Lab.Probe(sb, id) return st == "READABLE" and v and true or false end
    return false
end

local function spellName(id)
    local gi = Lab.Resolve("C_Spell.GetSpellInfo")
    if gi then
        local ok, i = pcall(gi, id)
        if ok and type(i) == "table" then return i.name end
    end
    return nil
end

local function refreshKnown()
    for k in pairs(known) do known[k] = nil end
    for i = #knownList, 1, -1 do knownList[i] = nil end
    for _, fam in ipairs(ORDER) do
        for _, id in ipairs(CANDIDATES[fam]) do
            if isKnownSpell(id) then known[id] = fam; knownList[#knownList + 1] = id end
        end
    end
end

local function spells()
    refreshKnown()
    Lab.Log("M2", "SPELLS known=%d (IsPlayerSpell/IsSpellKnown)", #knownList)
    for _, id in ipairs(knownList) do Lab.Log("M2", "SPELL %d %s family=%s", id, tostring(spellName(id)), known[id]) end
end

local function field(aura, f)
    local st, v, err = Lab.Probe(function() return aura[f] end)
    bump(stats, f, st)
    return st, v, err
end

local function probeAura(tag, unit, spellID, aura)
    local ts = Lab.Classify(true, aura)
    bump(stats, "<table>", ts)
    if ts ~= "READABLE" then Lab.Log("M2", "%s %s spell=%d TABLE=%s", tag, unit, spellID, ts) return end
    if issecrettable and issecrettable(aura) then
        bump(stats, "<secrettable>", "TRUE")
        Lab.Log("M2", "%s %s spell=%d TABLE is secret-table", tag, unit, spellID)
        return
    end
    local parts = {}
    for _, f in ipairs(FIELDS) do
        local st, v, err = field(aura, f)
        parts[#parts + 1] = f .. "=" .. Lab.Fmt(st, v, err)
    end
    Lab.Log("M2", "%s %s spell=%d %s", tag, unit, spellID, table.concat(parts, " "))
end

local function tokenList()
    local t = { "target", "focus", "mouseover" }
    local gp = Lab.Resolve("C_NamePlate.GetNamePlates")
    if gp then
        local ok, plates = pcall(gp)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                if type(p.namePlateUnitToken) == "string" then t[#t + 1] = p.namePlateUnitToken end
            end
        end
    end
    return t
end

local function auras(arg)
    if #knownList == 0 then refreshKnown() end
    local fn = Lab.Resolve("C_UnitAuras.GetUnitAuraBySpellID")
    if not fn then Lab.Log("M2", "AURAS GetUnitAuraBySpellID MISSING") return end
    local units = (arg and arg ~= "") and { arg } or tokenList()
    for _, unit in ipairs(units) do
        local es, ev = Lab.Probe(UnitExists, unit)
        if es == "READABLE" and ev then
            local gs, gv = Lab.Probe(UnitGUID, unit)
            local found = 0
            for _, id in ipairs(knownList) do
                local st, aura, err = Lab.Probe(fn, unit, id)
                if st == "READABLE" then found = found + 1; probeAura("AURA", unit, id, aura)
                elseif st ~= "NIL" then Lab.Log("M2", "AURA %s spell=%d call=%s", unit, id, Lab.Fmt(st, aura, err)); bump(stats, "<call>", st)
                else bump(stats, "<call>", "NIL") end
            end
            Lab.Log("M2", "AURAS %s guid=%s found=%d of %d known", unit, gs == "READABLE" and Lab.Short(gv) or gs, found, #knownList)
        elseif unit == "target" or unit == "focus" then
            Lab.Log("M2", "AURAS %s exists=%s", unit, Lab.Fmt(es, ev))
        end
    end
end

local SECRET_FNS = { "ShouldAurasBeSecret", "ShouldUnitAuraIndexBeSecret", "ShouldUnitAuraInstanceBeSecret",
    "ShouldUnitAuraSlotBeSecret", "ShouldUnitIdentityBeSecret", "ShouldUnitComparisonBeSecret", "CanCompareUnitTokens",
    "ShouldUnitSpellCastBeSecret", "ShouldUnitThreatStateBeSecret", "HasSecretRestrictions" }

local function secrecy(unit)
    unit = (unit and unit ~= "") and unit or "target"
    local cs = Lab.Resolve("C_Secrets")
    if not cs then Lab.Log("M2", "SECRECY C_Secrets MISSING") return end
    for _, name in ipairs(SECRET_FNS) do
        local fn = cs[name]
        if fn then
            local a, av, ae = Lab.Probe(fn)
            local b, bv, be = Lab.Probe(fn, unit)
            local c, cv, ce = Lab.Probe(fn, unit, 1)
            Lab.Log("M2", "SECRECY %s() -> %s | (%s) -> %s | (%s,1) -> %s", name, Lab.Fmt(a, av, ae), unit, Lab.Fmt(b, bv, be), unit, Lab.Fmt(c, cv, ce))
        end
    end
    -- per-spell aura secrecy for Fear
    local sa = cs.GetSpellAuraSecrecy
    if sa then
        for _, id in ipairs(knownList) do
            local st, v, err = Lab.Probe(sa, id)
            Lab.Log("M2", "SECRECY GetSpellAuraSecrecy(%d %s) -> %s", id, tostring(known[id]), Lab.Fmt(st, v, err))
        end
    end
end

-- Enumeration, only when the client says it is not restricted.
local function enum(unit)
    unit = (unit and unit ~= "") and unit or "target"
    local cs = Lab.Resolve("C_Secrets")
    local gate = cs and cs.ShouldUnitAuraIndexBeSecret
    local ok2, gv
    if gate then ok2, gv = Lab.Probe(gate, unit, 1) end
    if ok2 ~= "READABLE" or gv ~= false then
        Lab.Log("M2", "ENUM %s SKIPPED: gate=%s (only enumerate when explicitly false)", unit, Lab.Fmt(ok2 or "NOGATE", gv))
        return
    end
    local fn = Lab.Resolve("C_UnitAuras.GetAuraDataByIndex")
    for i = 1, 40 do
        local st, aura, err = Lab.Probe(fn, unit, i, "HARMFUL")
        if st ~= "READABLE" then Lab.Log("M2", "ENUM %s idx=%d %s", unit, i, Lab.Fmt(st, aura, err)) break end
        probeAura("ENUM", unit, i, aura)
    end
end

-- ===== UNIT_AURA watch =====
local af = CreateFrame("Frame")
local est = m2.est

local function watched(unit)
    return unit == "target" or unit == "focus" or unit:find("^nameplate")
end

local function expiryOf(aura)
    local ds, dv = field(aura, "duration")
    local es, ev = field(aura, "expirationTime")
    return (es == "READABLE" and type(ev) == "number") and ev or nil, (ds == "READABLE") and dv or nil
end

local function onAdded(unit, aura, what)
    local ts = Lab.Classify(true, aura)
    if ts ~= "READABLE" then bump(payload, what, ts) return end
    local ss, sid = field(aura, "spellId")
    local is, iid = field(aura, "auraInstanceID")
    if ss ~= "READABLE" or not known[sid] then bump(payload, what .. ".spellId", ss) return end
    local gs, guid = Lab.Probe(UnitGUID, unit)
    local exp, dur = expiryOf(aura)
    local key = (is == "READABLE") and (unit .. ":" .. tostring(iid)) or nil
    if key then tracked[key] = { spell = sid, guid = (gs == "READABLE") and guid or nil, t = GetTime(), exp = exp, dur = dur } end
    Lab.Log("M2", "%s %s guid=%s spell=%d(%s) instance=%s duration=%s expires=%s now=%.1f", what, unit,
        gs == "READABLE" and Lab.Short(guid) or gs, sid, known[sid], Lab.Fmt(is, iid), dur and ("%.1f"):format(dur) or "unreadable",
        exp and ("%.1f"):format(exp) or "unreadable", GetTime())
end

local function onRemoved(unit, iid)
    local key = unit .. ":" .. tostring(iid)
    local tr = tracked[key]
    if not tr then bump(payload, "removed.untracked", "n") return end
    tracked[key] = nil
    local now = GetTime()
    local gs, g = Lab.Probe(UnitGUID, unit)
    local ds, dead = Lab.Probe(UnitIsDead, unit)
    local verdict
    if ds == "READABLE" and dead then verdict = "DEATH?"
    elseif gs == "READABLE" and tr.guid and g ~= tr.guid then verdict = "TOKEN_REASSIGNED(not a break)"
    elseif tr.exp then
        local rem = tr.exp - now
        verdict = (math.abs(rem) <= 0.6) and "EXPIRED" or (rem > 0 and ("EARLY_BREAK(%.1fs early)"):format(rem) or ("LATE(%.1fs)"):format(-rem))
    else verdict = "UNKNOWN(expiration unreadable)" end
    Lab.Log("M2", "REMOVED %s guid=%s spell=%d(%s) elapsed=%.1f verdict=%s", unit, Lab.Short(tr.guid), tr.spell, known[tr.spell],
        now - tr.t, verdict)
end

local function listField(info, f)
    local st, v = Lab.Probe(function() return info[f] end)
    bump(payload, f, st)
    return st, v
end

af:SetScript("OnEvent", function(_, ev, unit, info)
    if ev ~= "UNIT_AURA" then return end
    if Lab.Classify(true, unit) ~= "READABLE" or type(unit) ~= "string" or not watched(unit) then return end
    local is = Lab.Classify(true, info)
    bump(payload, "updateInfo", is)
    if is ~= "READABLE" then
        local sig = "info:" .. is
        if not loggedSig[sig] then loggedSig[sig] = true Lab.Log("M2", "UNIT_AURA %s updateInfo=%s", unit, is) end
        return
    end
    local fs, fv = listField(info, "isFullUpdate")
    local as, av = listField(info, "addedAuras")
    local us, uv = listField(info, "updatedAuraInstanceIDs")
    local rs, rv = listField(info, "removedAuraInstanceIDs")
    local sig = ("payload:%s/%s/%s/%s"):format(fs, as, us, rs)
    if not loggedSig[sig] then loggedSig[sig] = true Lab.Log("M2", "UNIT_AURA payload shape full=%s added=%s updated=%s removed=%s", fs, as, us, rs) end
    if fs == "READABLE" and fv then
        Lab.Log("M2", "FULLUPDATE %s -> rescanning", unit)
        auras(unit)
    end
    if as == "READABLE" and type(av) == "table" then
        for _, aura in ipairs(av) do onAdded(unit, aura, "ADDED") end
    end
    if us == "READABLE" and type(uv) == "table" then
        local fn = Lab.Resolve("C_UnitAuras.GetAuraDataByAuraInstanceID")
        for _, iid in ipairs(uv) do
            if Lab.Classify(true, iid) == "READABLE" then
                local key = unit .. ":" .. tostring(iid)
                local st, aura = Lab.Probe(fn, unit, iid)
                if tracked[key] and st == "READABLE" then
                    local exp, dur = expiryOf(aura)
                    local old = tracked[key]
                    Lab.Log("M2", "REFRESH %s guid=%s spell=%d(%s) duration=%s expires=%s (prev exp=%s) now=%.1f", unit,
                        Lab.Short(old.guid), old.spell, known[old.spell], dur and ("%.1f"):format(dur) or "unreadable",
                        exp and ("%.1f"):format(exp) or "unreadable", old.exp and ("%.1f"):format(old.exp) or "?", GetTime())
                    old.exp, old.dur = exp, dur
                elseif not tracked[key] and st == "READABLE" then
                    onAdded(unit, aura, "UPDATED-NEW")
                end
            end
        end
    end
    if rs == "READABLE" and type(rv) == "table" then
        for _, iid in ipairs(rv) do
            if Lab.Classify(true, iid) == "READABLE" then onRemoved(unit, iid) else bump(payload, "removedID", "secret") end
        end
    end
end)

local function aurawatch(arg)
    if arg == "off" then af:UnregisterAllEvents() Lab.Log("M2", "AURAWATCH off") return end
    if #knownList == 0 then refreshKnown() end
    local ok, err = pcall(af.RegisterEvent, af, "UNIT_AURA")
    Lab.Log("M2", "AURAWATCH on register=%s known=%d", ok and "ok" or tostring(err), #knownList)
end

-- Player casts: ESTIMATE only (never authoritative).
local cf = CreateFrame("Frame")
cf:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if Lab.Classify(true, spellID) ~= "READABLE" or not known[spellID] then return end
    local gs, g = Lab.Probe(UnitGUID, "target")
    est[#est + 1] = { spell = spellID, guid = gs == "READABLE" and g or nil, t = GetTime() }
    Lab.Log("M2", "ESTIMATE cast %d(%s) on probable target=%s at %.1f (not authoritative)", spellID, known[spellID],
        gs == "READABLE" and Lab.Short(g) or gs, GetTime())
end)
pcall(cf.RegisterUnitEvent, cf, "UNIT_SPELLCAST_SUCCEEDED", "player")

-- ===== native widget inspection =====
local function names(t, filter)
    local out = {}
    if type(t) == "table" then
        for k, v in pairs(t) do
            if type(k) == "string" and (not filter or k:find(filter)) then out[#out + 1] = k .. ":" .. type(v) end
        end
    end
    table.sort(out)
    return out
end

local function logList(tag, label, list)
    Lab.Log("M2", "%s %s (%d)", tag, label, #list)
    local chunk = {}
    for i, n in ipairs(list) do
        chunk[#chunk + 1] = n
        if #chunk == 6 or i == #list then Lab.Log("M2", "%s   %s", tag, table.concat(chunk, " ")) chunk = {} end
    end
end

local function shallow(t)
    local out = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "number" or tv == "boolean" or tv == "string" then out[#out + 1] = tostring(k) .. "=" .. tostring(v)
        else out[#out + 1] = tostring(k) .. ":" .. tv end
    end
    table.sort(out)
    return out
end

local function auracontainer()
    for _, n in ipairs({ "AuraContainerMixin", "AuraButtonMixin", "AuraFrameMixin", "C_AuraContainerUtil" }) do
        logList("M2", "NATIVE " .. n, names(Lab.Resolve(n)))
    end
    for _, n in ipairs({ "AuraContainerAuraDataType", "AuraContainerSortMethod", "AuraContainerInbound", "CustomAuraContainerAuraProcessingPolicy",
        "CustomAuraContainerSlotDefaultOptions", "CustomAuraContainerGroupDefaultOptions", "CustomAuraContainerLayoutDefaults",
        "CustomAuraContainerProcessAuraPolicyDefaultOptions", "TargetFrameAuraContainerDefaults", "AuraContainerFrameRefreshResult" }) do
        local t = Lab.Resolve(n)
        if type(t) == "table" then logList("M2", "NATIVE " .. n, shallow(t)) else Lab.Log("M2", "NATIVE %s ABSENT", n) end
    end
    local cd = CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate")
    local mt = getmetatable(cd)
    local idx = mt and mt.__index
    logList("M2", "NATIVE Cooldown methods w/ Duration|Secret|Aura|Countdown", names(idx, "Duration") )
    logList("M2", "NATIVE Cooldown methods Countdown|Secret|Aura", names(idx, "[Cc]ountdown") )
    logList("M2", "NATIVE Cooldown methods SetCooldown*", names(idx, "^SetCooldown") )
    cd:Hide()
end

-- ===== diagnostic HUD: native path (instance IDs -> duration object -> Cooldown), no spell lookup =====
local hud
local SLOTS = { "target", "focus" }
local SUBS = 4
local function newSlot(i)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(4 * 46, 44)
    f:SetPoint("LEFT", UIParent, "LEFT", 40, 120 - (i - 1) * 90)
    f.subs = {}
    for j = 1, SUBS do
        local s = CreateFrame("Frame", nil, f)
        s:SetSize(44, 44)
        s:SetPoint("LEFT", f, "LEFT", (j - 1) * 46, 0)
        s.icon = s:CreateTexture(nil, "ARTWORK") s.icon:SetAllPoints()
        s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
        s.cd:SetAllPoints()
        if s.cd.SetHideCountdownNumbers then s.cd:SetHideCountdownNumbers(false) end
        f.subs[j] = s
    end
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.label:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
    f.label:SetJustifyH("LEFT")
    return f
end

-- Collect player-cast harmful aura instance IDs without reading them (they may be secret).
local function collectIds(unit)
    local ids, how = {}, "none"
    local gi = Lab.Resolve("C_UnitAuras.GetUnitAuraInstanceIDs")
    if gi then
        local ok, t = pcall(gi, unit, "HARMFUL|PLAYER")
        if ok and type(t) == "table" then
            pcall(function() for _, id in ipairs(t) do ids[#ids + 1] = id end end)
            if #ids > 0 then return ids, "GetUnitAuraInstanceIDs" end
        end
    end
    local ga = Lab.Resolve("C_UnitAuras.GetUnitAuras")
    if ga then
        local ok, t = pcall(ga, unit, "HARMFUL|PLAYER")
        if ok and type(t) == "table" then
            pcall(function() for _, a in ipairs(t) do ids[#ids + 1] = a.auraInstanceID end end)
            if #ids > 0 then return ids, "GetUnitAuras" end
        end
    end
    return ids, how
end

local lastSig = {}
local function renderSlot(slot, unit)
    for _, s in ipairs(slot.subs) do s.cd:Clear() s.icon:SetTexture(nil) end
    local es, ev = Lab.Probe(UnitExists, unit)
    if es ~= "READABLE" or not ev then slot.label:SetText(unit .. ": none") return end
    local ids, how = collectIds(unit)
    local gd = Lab.Resolve("C_UnitAuras.GetAuraDuration")
    local gdata = Lab.Resolve("C_UnitAuras.GetAuraDataByAuraInstanceID")
    local results = {}
    for j = 1, math.min(#ids, SUBS) do
        local s, id = slot.subs[j], ids[j]
        local okD, dobj = pcall(gd, unit, id)
        local okC = okD and dobj ~= nil and pcall(s.cd.SetCooldownFromDurationObject, s.cd, dobj)
        local okA, data = pcall(gdata, unit, id)
        local okI = okA and data ~= nil and pcall(function() s.icon:SetTexture(data.icon) end)
        results[#results + 1] = ("%d:dur=%s cd=%s icon=%s"):format(j, tostring(okD and dobj ~= nil), tostring(okC and true or false), tostring(okI and true or false))
    end
    local sig = unit .. "|" .. how .. "|" .. table.concat(results, ",")
    slot.label:SetText(("%s via %s: %d auras"):format(unit, how, #ids))
    if lastSig[unit] ~= sig then
        lastSig[unit] = sig
        local gs, gv = Lab.Probe(UnitGUID, unit)
        Lab.Log("M2", "HUD %s guid=%s ids=%d via=%s %s", unit, gs == "READABLE" and Lab.Short(gv) or gs, #ids, how, table.concat(results, " "))
    end
end

local function hudRefresh()
    if not hud then return end
    for i, unit in ipairs(SLOTS) do renderSlot(hud[i], unit) end
end

local hf = CreateFrame("Frame")
hf:SetScript("OnEvent", function(_, ev, unit)
    if ev == "UNIT_AURA" and unit ~= "target" and unit ~= "focus" then return end
    hudRefresh()
end)

local function m2hud(arg)
    if arg == "off" then
        if hud then for _, s in ipairs(hud) do s:Hide() end end
        hf:UnregisterAllEvents()
        Lab.Log("M2", "HUD off")
        return
    end
    if #knownList == 0 then refreshKnown() end
    if not hud then hud = { newSlot(1), newSlot(2) } end
    for _, s in ipairs(hud) do s:Show() end
    hf:RegisterEvent("UNIT_AURA")
    hf:RegisterEvent("PLAYER_TARGET_CHANGED")
    hf:RegisterEvent("PLAYER_FOCUS_CHANGED")
    hudRefresh()
    Lab.Log("M2", "HUD on (target+focus slots, left of screen)")
end

local function m2stats()
    local function dump(title, t)
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local parts = {}
            for st, n in pairs(t[k]) do parts[#parts + 1] = st .. "=" .. n end
            table.sort(parts)
            Lab.Log("M2", "%s %-22s %s", title, k, table.concat(parts, " "))
        end
    end
    dump("FIELDSTAT", stats)
    dump("PAYLOAD", payload)
end

local function thresholdtest()
    local T = Lab.Threshold
    local r = {
        T.IsRecastDue(110, 100, 1.5, 0.3) == false,  -- 10s left
        T.IsRecastDue(101.5, 100, 1.5, 0.3) == true, -- 1.5s left
        T.IsRecastDue(nil, 100, 1.5, 0.3) == nil,    -- unknown never guessed
        T.Remaining("x", 100) == nil,
    }
    local n = 0
    for _, b in ipairs(r) do if b then n = n + 1 end end
    Lab.Log("M2", "THRESHOLD synthetic tests %d/%d pass", n, #r)
end

Lab.AddCommand("spells", "M2: list learned Warlock Fear/DoT/curse spell IDs", spells)
Lab.AddCommand("auras", "M2: GetUnitAuraBySpellID + per-field probe [unit] (default target/focus/mouseover/plates)", auras)
Lab.AddCommand("secrecy", "M2: log C_Secrets.Should* answers [unit] (run out of combat AND in combat)", secrecy)
Lab.AddCommand("enum", "M2: aura enumeration, only if C_Secrets says not restricted [unit]", enum)
Lab.AddCommand("aurawatch", "M2: on|off UNIT_AURA payload + add/refresh/remove tracking", aurawatch)
Lab.AddCommand("auracontainer", "M2: inspect native aura/cooldown widget API names", auracontainer)
Lab.AddCommand("m2hud", "M2: on|off diagnostic Fear/DoT cooldown widgets for target & focus", m2hud)
Lab.AddCommand("m2stats", "M2: per-field and payload accessibility counters", m2stats)
Lab.AddCommand("thresholdtest", "M2: recast-threshold math self-test (no game data)", thresholdtest)

-- Enum tables that describe secrecy levels (names/values only), to decode GetSpellAuraSecrecy.
Lab.AddCommand("secretenums", "M2: log Enum.* tables related to secrecy", function()
    local E = Lab.Resolve("Enum")
    local n = 0
    if type(E) == "table" then
        for k, t in pairs(E) do
            if type(k) == "string" and k:find("Secre") and type(t) == "table" then
                n = n + 1
                logList("M2", "ENUM " .. k, shallow(t))
            end
        end
    end
    Lab.Log("M2", "SECRETENUMS found %d", n)
end)

-- Combat-capable paths: what can be obtained for the target, field by field.
Lab.AddCommand("paths", "M2: try every aura read path on [unit] (default target); run IN COMBAT", function(unit)
    unit = (unit and unit ~= "") and unit or "target"
    local U = Lab.Resolve("C_UnitAuras")
    local function try(label, fn, ...)
        local st, v, err = Lab.Probe(fn, ...)
        local extra = ""
        if st == "READABLE" and type(v) == "table" then
            local n = 0
            pcall(function() for _ in pairs(v) do n = n + 1 end end)
            extra = " (table n=" .. n .. (issecrettable and issecrettable(v) and " SECRETTABLE" or "") .. ")"
        end
        Lab.Log("M2", "PATH %-34s %s%s", label, Lab.Fmt(st, v, err), extra)
        return st, v
    end
    try("GetUnitAuraInstanceIDs HARMFUL|PLAYER", U.GetUnitAuraInstanceIDs, unit, "HARMFUL|PLAYER")
    try("GetUnitAuras HARMFUL|PLAYER", U.GetUnitAuras, unit, "HARMFUL|PLAYER")
    try("GetAuraSlots HARMFUL", U.GetAuraSlots, unit, "HARMFUL")
    try("GetAuraDataBySpellName Corruption", U.GetAuraDataBySpellName, unit, "Corruption", "HARMFUL|PLAYER")
    try("GetUnitAuraBySpellID 172", U.GetUnitAuraBySpellID, unit, 172)
    try("GetDebuffDataByIndex 1", U.GetDebuffDataByIndex, unit, 1)
    local st, ids = try("(ids) GetUnitAuraInstanceIDs HARMFUL", U.GetUnitAuraInstanceIDs, unit, "HARMFUL")
    local first
    pcall(function() first = ids and ids[1] end)
    if first ~= nil then
        Lab.Log("M2", "PATH first instance id class=%s", Lab.Classify(true, first))
        local _, d = try("GetAuraDuration(first)", U.GetAuraDuration, unit, first)
        try("GetAuraDataByAuraInstanceID(first)", U.GetAuraDataByAuraInstanceID, unit, first)
        try("DoesAuraHaveExpirationTime(first)", U.DoesAuraHaveExpirationTime, unit, first)
        try("GetAuraCasterGUID(first)", U.GetAuraCasterGUID, unit, first)
        try("GetAuraApplicationDisplayCount(first)", U.GetAuraApplicationDisplayCount, unit, first, 2, 99)
        if d ~= nil then
            local mt = getmetatable(d)
            Lab.Log("M2", "PATH duration object type=%s", type(d))
            if mt and type(mt.__index) == "table" then logList("M2", "DURATIONOBJ methods", names(mt.__index)) end
            for _, m in ipairs({ "GetRemainingDuration", "GetElapsedDuration", "GetTotalDuration", "GetEndTime" }) do
                if d[m] then local st2, v2, e2 = Lab.Probe(d[m], d) Lab.Log("M2", "PATH durobj:%s -> %s", m, Lab.Fmt(st2, v2, e2)) end
            end
        end
    end
end)

-- Find the native "custom aura container" API: create one unparented-to-nameplate, log its methods.
Lab.AddCommand("containerapi", "M2: create an AuraContainerTemplate frame and log its methods/fields (no unit set)", function()
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, "AuraContainerTemplate")
    if not ok then Lab.Log("M2", "CONTAINER create ERROR %s", tostring(f):sub(1, 120)) return end
    f:Hide()
    local mt = getmetatable(f)
    local idx = mt and mt.__index
    local own = {}
    for k, v in pairs(f) do if type(k) == "string" then own[#own + 1] = k .. ":" .. type(v) end end
    table.sort(own)
    logList("M2", "CONTAINER own fields", own)
    local m = {}
    if type(idx) == "table" then
        for k, v in pairs(idx) do
            if type(k) == "string" and k:find("Aura") or (type(k) == "string" and (k:find("Unit") or k:find("Group") or k:find("Slot") or k:find("Custom"))) then
                m[#m + 1] = k .. ":" .. type(v)
            end
        end
    end
    table.sort(m)
    logList("M2", "CONTAINER methods (Aura|Unit|Group|Slot|Custom)", m)
    for _, n in ipairs({ "AuraButtonTemplate", "AuraFrameTemplate" }) do
        local ok2, b = pcall(CreateFrame, n == "AuraButtonTemplate" and "Button" or "Frame", nil, UIParent, n)
        if ok2 then
            local bm = getmetatable(b)
            local l = {}
            for k, v in pairs(b) do if type(k) == "string" then l[#l + 1] = k .. ":" .. type(v) end end
            table.sort(l)
            logList("M2", n .. " own fields", l)
            b:Hide()
        else Lab.Log("M2", "%s create ERROR %s", n, tostring(b):sub(1, 100)) end
    end
end)
