--[[ M0: API baseline. Existence/type checks only. No protected operations. ]]
local _, Lab = ...

local CAPS = {
    "UnitGUID", "UnitName", "UnitPosition", "UnitExists", "UnitAffectingCombat",
    "UnitThreatSituation", "UnitCanAttack", "GetRaidTargetIndex",
    "C_UnitAuras", "C_UnitAuras.GetUnitAuraBySpellID", "C_UnitAuras.GetAuraDataByIndex",
    "C_UnitAuras.GetAuraDataByAuraInstanceID", "C_UnitAuras.GetAuraDuration",
    "issecretvalue", "canaccessvalue", "issecrettable", "C_Secrets",
    "C_DamageMeter", "C_NamePlate", "C_NamePlate.GetNamePlates", "C_NamePlate.GetNamePlateForUnit",
    "C_EventUtils.IsEventValid", "C_XMLUtil.GetTemplateInfo", "C_Spell.GetSpellInfo",
    "AuraUtil", "AuraUtil.ForEachAura", "AuraUtil.UnpackAuraData",
    "AuraContainerMixin", "AuraButtonMixin", "AuraFrameMixin", "CooldownFrame_Set",
    "SecureActionButtonTemplate", "SecureHandlerBaseTemplate", "InCombatLockdown",
}

-- Templates we can ask the XML layer about without creating frames.
local TEMPLATES = {
    "SecureActionButtonTemplate", "SecureUnitButtonTemplate", "AuraContainerTemplate",
    "AuraButtonTemplate", "AuraFrameTemplate", "CooldownFrameTemplate",
    "CompactAuraTemplate", "TargetDebuffFrameTemplate", "TargetBuffFrameTemplate",
}

local EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "UNIT_TARGET", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "RAID_TARGET_UPDATE",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_FLAGS",
}

local function keysOf(t, limit)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do if type(k) == "string" then out[#out + 1] = k end end
    table.sort(out)
    return out
end

local function info()
    local version, build, bdate, toc = GetBuildInfo()
    Lab.Log("M0", "BUILD version=%s build=%s date=%s toc=%s", version, build, bdate, toc)
    Lab.Log("M0", "PROJECT WOW_PROJECT_ID=%s locale=%s", Lab.Resolve("WOW_PROJECT_ID") or "nil", GetLocale())
    local ids = {}
    for _, n in ipairs({ "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC", "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
        "WOW_PROJECT_WRATH_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC" }) do
        if _G[n] ~= nil then ids[#ids + 1] = n .. "=" .. tostring(_G[n]) end
    end
    Lab.Log("M0", "PROJECT_CONSTS %s", #ids > 0 and table.concat(ids, " ") or "none")
    local _, class = UnitClass("player")
    Lab.Log("M0", "PLAYER class=%s level=%s", class, UnitLevel("player"))
    Lab.Log("M0", "TARGET_BUILD interface=%s (want 16001) -> %s", toc, toc == 16001 and "MATCH" or "MISMATCH: not Forever?")
end

local function caps()
    for _, path in ipairs(CAPS) do
        local v = Lab.Resolve(path)
        local t = v == nil and "ABSENT" or type(v)
        Lab.Log("M0", "CAP %-45s %s", path, t)
    end
    -- namespace member inventories (names only; nothing is called)
    for _, ns in ipairs({ "C_UnitAuras", "C_Secrets", "C_DamageMeter", "C_NamePlate" }) do
        local t = Lab.Resolve(ns)
        if type(t) == "table" then
            Lab.Log("M0", "NS %s = %s", ns, table.concat(keysOf(t), ", "))
        else
            Lab.Log("M0", "NS %s = ABSENT", ns)
        end
    end
    -- Template existence via XML layer (no frame creation).
    local gt = Lab.Resolve("C_XMLUtil.GetTemplateInfo")
    for _, name in ipairs(TEMPLATES) do
        if gt then
            local st, v, err = Lab.Probe(gt, name)
            Lab.Log("M0", "TEMPLATE %-30s %s", name, st == "READABLE" and ("present type=" .. tostring(type(v) == "table" and v.type or "?"))
                or (st == "NIL" and "absent" or Lab.Fmt(st, v, err)))
        else
            Lab.Log("M0", "TEMPLATE %-30s UNVERIFIED (C_XMLUtil.GetTemplateInfo missing)", name)
        end
    end
    -- Event validity (does not register anything).
    local iv = Lab.Resolve("C_EventUtils.IsEventValid")
    for _, ev in ipairs(EVENTS) do
        if iv then
            local st, v, err = Lab.Probe(iv, ev)
            Lab.Log("M0", "EVENT %-28s %s", ev, st == "READABLE" and (v and "valid" or "INVALID") or Lab.Fmt(st, v, err))
        else
            Lab.Log("M0", "EVENT %-28s UNVERIFIED", ev)
        end
    end
    Lab.Log("M0", "EVENT COMBAT_LOG_EVENT_UNFILTERED not touched (known blocked on Forever)")
end

-- Scan _G names for aura / secret related symbols (names + types only).
local function scan()
    local hits = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and (k:find("Secret") or k:find("secret") or k:find("^Aura") or k:find("AuraContainer")
            or k:find("AuraButton") or k:find("DamageMeter")) then
            hits[#hits + 1] = k .. ":" .. type(v)
        end
    end
    table.sort(hits)
    Lab.Log("M0", "GSCAN %d names", #hits)
    local chunk = {}
    for i, h in ipairs(hits) do
        chunk[#chunk + 1] = h
        if #chunk == 6 or i == #hits then
            Lab.Log("M0", "GSCAN %s", table.concat(chunk, " "))
            chunk = {}
        end
    end
end

local function sanity()
    -- Self-test of the classifier on non-secret values.
    local st1 = Lab.Classify(true, 1)
    local st2 = Lab.Classify(true, nil)
    local st3 = Lab.Classify(false, "boom")
    Lab.Log("M0", "SANITY classify(1)=%s classify(nil)=%s classify(err)=%s", st1, st2, st3)
    if C_Secrets then
        for _, fname in ipairs({ "HasSecretRestrictions" }) do
            if C_Secrets[fname] then
                Lab.Log("M0", "SECRETS %s -> %s", fname, Lab.Fmt(Lab.Probe(C_Secrets[fname])))
            end
        end
    end
end

Lab.AddCommand("info", "M0: build, interface, game type", info)
Lab.AddCommand("caps", "M0: capability inventory (APIs, templates, events)", caps)
Lab.AddCommand("scan", "M0: scan globals for aura/secret/damage-meter names", scan)
Lab.AddCommand("m0", "M0: run info + caps + scan + sanity", function()
    info(); caps(); scan(); sanity()
    Lab.Log("M0", "UNVERIFIED: Forever UI source/event payload fields cannot be read from the client; check in-game /dump and Blizzard source dumps")
end)
