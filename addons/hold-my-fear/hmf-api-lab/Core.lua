--[[
    HMF_API_Lab Core: bounded log, safe value classification, helpers.
    Rules: no COMBAT_LOG_EVENT_UNFILTERED, no SetRaidTarget, no secure
    frames, no secret-value comparison. pcall is used ONLY to capture
    errors from read-only probes, never to bypass a protected action.
]]
local ADDON, Lab = ...
_G.HMF_API_Lab = Lab

local MAX_LINES = 600
Lab.lines = {}
Lab.scenario = "-"
Lab.handlers = {}   -- subcommand -> function(args)
Lab.helptext = {}

-- classify(ok, value) -> status, detail
-- status: ERROR | SECRET | INACCESSIBLE | NIL | READABLE
-- Order matters: never compare/inspect a value before the secret check.
function Lab.Classify(ok, v)
    if not ok then return "ERROR", tostring(v) end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    if canaccessvalue and not canaccessvalue(v) then return "INACCESSIBLE" end
    if v == nil then return "NIL" end
    return "READABLE"
end

-- Call fn(...) as a read-only probe. Returns status, value (value only if READABLE), errtext.
function Lab.Probe(fn, ...)
    if type(fn) ~= "function" then return "MISSING" end
    local ok, v = pcall(fn, ...)
    local st, detail = Lab.Classify(ok, v)
    if st == "READABLE" then return st, v end
    return st, nil, detail
end

function Lab.Fmt(st, v, err)
    if st == "READABLE" then return tostring(v) end
    if st == "ERROR" then return "ERROR(" .. tostring(err):sub(1, 80) .. ")" end
    return st
end

function Lab.Short(guid)
    if type(guid) ~= "string" then return tostring(guid) end
    return guid:match("%-(%d+%-%x+)$") or guid
end

function Lab.Log(tag, fmt, ...)
    local n = select("#", ...)
    local msg = fmt
    if n > 0 then
        local a = { ... }
        for i = 1, n do
            local x = a[i]
            -- never stringify a secret value
            if issecretvalue and issecretvalue(x) then x = "<secret>" end
            a[i] = tostring(x)
        end
        msg = fmt:format(unpack(a, 1, n))
    end
    local line = ("%s [%s|%s%s] %s"):format(date("%H:%M:%S"), tag, Lab.scenario,
        InCombatLockdown() and "|COMBAT" or "", msg)
    local lines = Lab.lines
    lines[#lines + 1] = line
    if #lines > MAX_LINES then table.remove(lines, 1) end
    if Lab.echo then print("|cff88ccffHMFLab|r " .. line) end
end

-- Resolve a dotted global path safely ("C_UnitAuras.GetAuraDataByIndex").
function Lab.Resolve(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
        if cur == nil then return nil end
    end
    return cur
end

function Lab.AddCommand(name, help, fn)
    Lab.handlers[name] = fn
    Lab.helptext[#Lab.helptext + 1] = ("/hmflab %s - %s"):format(name, help)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    HMF_API_LabDB = HMF_API_LabDB or {}
    -- Persist the buffer so results can be read from SavedVariables after /reload.
    local old = HMF_API_LabDB.lines or {}
    Lab.lines = old
    HMF_API_LabDB.lines = Lab.lines
    Lab.Log("LOAD", "HMF_API_Lab loaded (buffer %d lines)", #Lab.lines)
    if Lab.OnLoaded then Lab.OnLoaded() end
end)
