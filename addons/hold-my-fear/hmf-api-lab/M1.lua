--[[
    M1: enemy identity & discovery. Read-only probes of unit tokens, GUID
    mapping with validation, nameplate + target/focus/mouseover events,
    player UNIT_SPELLCAST_SUCCEEDED payload accessibility.
]]
local _, Lab = ...

local PROBES = { "UnitExists", "UnitGUID", "UnitName", "UnitAffectingCombat", "UnitThreatSituation", "UnitCanAttack" }
local map = {}          -- token -> guid (readable only)
local stats = { assoc = 0, mismatch = 0, added = 0, removed = 0, secretSkips = 0 }
Lab.m1 = { map = map, stats = stats }

local function probeUnit(token)
    local parts, readable = {}, {}
    for _, fname in ipairs(PROBES) do
        local fn = _G[fname]
        local st, v, err
        if fname == "UnitCanAttack" then
            st, v, err = Lab.Probe(fn, "player", token)
        else
            st, v, err = Lab.Probe(fn, token)
        end
        parts[#parts + 1] = ("%s=%s"):format(fname:gsub("^Unit", ""), st == "READABLE" and (fname == "UnitGUID" and Lab.Short(v) or tostring(v)) or Lab.Fmt(st, v, err))
        readable[fname] = (st == "READABLE") and v or nil
    end
    return table.concat(parts, " "), readable
end

local function plateTokens()
    local out = {}
    local gp = Lab.Resolve("C_NamePlate.GetNamePlates")
    if gp then
        local ok, plates = pcall(gp)
        if ok and type(plates) == "table" then
            for _, p in ipairs(plates) do
                local tok = p.namePlateUnitToken
                if tok == nil and p.UnitFrame then tok = p.UnitFrame.unit end
                if type(tok) == "string" then out[#out + 1] = tok end
            end
            return out, "C_NamePlate"
        end
    end
    for i = 1, 40 do
        local tok = "nameplate" .. i
        local st, v = Lab.Probe(UnitExists, tok)
        if st == "READABLE" and v then out[#out + 1] = tok end
    end
    return out, "token-loop"
end

local function units()
    local seen = {}  -- name -> { guid -> true }
    local function record(token)
        local line, r = probeUnit(token)
        Lab.Log("M1", "UNIT %-12s %s", token, line)
        if r.UnitGUID then
            map[token] = r.UnitGUID
            local n = r.UnitName or "?"
            seen[n] = seen[n] or {}
            seen[n][r.UnitGUID] = true
        else
            map[token] = nil
        end
    end
    for _, t in ipairs({ "target", "focus", "mouseover" }) do record(t) end
    local plates, how = plateTokens()
    Lab.Log("M1", "PLATES %d visible via %s", #plates, how)
    for _, t in ipairs(plates) do record(t) end
    -- identical-mob distinction
    for name, guids in pairs(seen) do
        local c = 0
        for _ in pairs(guids) do c = c + 1 end
        if c > 1 then Lab.Log("M1", "DISTINCT %q has %d distinct readable GUIDs -> identical mobs distinguishable", name, c) end
    end
end

-- Re-verify the stored mapping; a mismatch means a stale/incorrect association.
local function verify(reason)
    -- Only nameplate tokens are expected to keep their unit between events.
    -- target/focus/mouseover legitimately change, so they are not "stale".
    for token, guid in pairs(map) do
      if token:find("^nameplate") then
        local st, v = Lab.Probe(UnitGUID, token)
        stats.assoc = stats.assoc + 1
        if st == "READABLE" then
            if v ~= guid then
                stats.mismatch = stats.mismatch + 1
                Lab.Log("M1", "MISMATCH %s was %s now %s (%s)", token, Lab.Short(guid), Lab.Short(v), reason)
                map[token] = v
            end
        elseif st == "NIL" then
            Lab.Log("M1", "STALE %s was %s now nil (%s)", token, Lab.Short(guid), reason)
            map[token] = nil
        else
            stats.secretSkips = stats.secretSkips + 1
            Lab.Log("M1", "UNVERIFIABLE %s status=%s (%s)", token, st, reason)
        end
      end
    end
end

local function snapshotToken(tag, token)
    local st, v, err = Lab.Probe(UnitGUID, token)
    if st == "READABLE" then
        map[token] = v
        local nst, nv, nerr = Lab.Probe(UnitName, token)
        Lab.Log("M1", "%s %s guid=%s name=%s", tag, token, Lab.Short(v), Lab.Fmt(nst, nv, nerr))
    else
        map[token] = nil
        Lab.Log("M1", "%s %s guid=%s", tag, token, Lab.Fmt(st, v, err))
    end
end

local f = CreateFrame("Frame")
local function register()
    for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED",
        "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
        local ok, err = pcall(f.RegisterEvent, f, ev)
        if not ok then Lab.Log("M1", "REGISTER %s FAILED %s", ev, tostring(err)) end
    end
    local ok, err = pcall(f.RegisterUnitEvent, f, "UNIT_SPELLCAST_SUCCEEDED", "player")
    Lab.Log("M1", "REGISTER UNIT_SPELLCAST_SUCCEEDED(player) %s", ok and "ok" or ("FAILED " .. tostring(err)))
end

f:SetScript("OnEvent", function(_, ev, a1, a2, a3)
    if ev == "NAME_PLATE_UNIT_ADDED" then
        stats.added = stats.added + 1
        local st = Lab.Classify(true, a1)
        if st ~= "READABLE" then Lab.Log("M1", "EVT %s payload token=%s", ev, st) return end
        snapshotToken("PLATE+", a1)
    elseif ev == "NAME_PLATE_UNIT_REMOVED" then
        stats.removed = stats.removed + 1
        local st = Lab.Classify(true, a1)
        if st ~= "READABLE" then Lab.Log("M1", "EVT %s payload token=%s", ev, st) return end
        Lab.Log("M1", "PLATE- %s (had guid=%s)", a1, Lab.Short(map[a1]))
        map[a1] = nil
    elseif ev == "PLAYER_TARGET_CHANGED" then
        verify("target changed")
        snapshotToken("TARGET", "target")
    elseif ev == "PLAYER_FOCUS_CHANGED" then
        snapshotToken("FOCUS", "focus")
    elseif ev == "UPDATE_MOUSEOVER_UNIT" then
        snapshotToken("MOUSEOVER", "mouseover")
    elseif ev == "PLAYER_REGEN_DISABLED" then
        Lab.Log("M1", "COMBAT start")
    elseif ev == "PLAYER_REGEN_ENABLED" then
        Lab.Log("M1", "COMBAT end")
    elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
        local su, sc, ss = Lab.Classify(true, a1), Lab.Classify(true, a2), Lab.Classify(true, a3)
        local spellID = (ss == "READABLE") and a3 or nil
        local tg = Lab.Probe(UnitGUID, "target")
        local tgs, tgv = Lab.Probe(UnitGUID, "target")
        local fcs, fcv = Lab.Probe(UnitGUID, "focus")
        local mos, mov = Lab.Probe(UnitGUID, "mouseover")
        Lab.Log("M1", "CAST unit=%s castGUID=%s spellID=%s | target=%s focus=%s mouseover=%s",
            su, sc, spellID or ss,
            tgs == "READABLE" and Lab.Short(tgv) or tgs, fcs == "READABLE" and Lab.Short(fcv) or fcs,
            mos == "READABLE" and Lab.Short(mov) or mos)
    end
end)

Lab.OnLoaded = function() register() end

Lab.AddCommand("units", "M1: probe target/focus/mouseover/nameplates; report identical-mob distinction", units)
Lab.AddCommand("verify", "M1: re-check stored GUID->token map for stale/incorrect entries", function() verify("manual") end)
Lab.AddCommand("m1stats", "M1: counters (assoc checks, mismatches, plate add/remove)", function()
    local n = 0
    for _ in pairs(map) do n = n + 1 end
    Lab.Log("M1", "STATS mapped=%d assocChecks=%d mismatches=%d unverifiable=%d plateAdd=%d plateRemove=%d",
        n, stats.assoc, stats.mismatch, stats.secretSkips, stats.added, stats.removed)
end)
