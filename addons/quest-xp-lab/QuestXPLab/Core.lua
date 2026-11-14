--[[ QuestXPLab Core: bounded persisted log, safe probing. Read-only; pcall only
     captures errors from probes. No SelectQuestLogEntry, no tooltips, no protected calls. ]]
local ADDON, Lab = ...
_G.QuestXPLab = Lab

local MAX_LINES = 800
Lab.lines = {}
Lab.scenario = "-"
Lab.echo = true -- print log lines to chat; /qxplab echo toggles
Lab.handlers, Lab.helptext = {}, {}

-- status: ERROR | SECRET | INACCESSIBLE | NIL | READABLE (secret check before any inspection)
function Lab.Classify(ok, v)
    if not ok then return "ERROR", tostring(v) end
    if issecretvalue and issecretvalue(v) then return "SECRET" end
    if canaccessvalue and not canaccessvalue(v) then return "INACCESSIBLE" end
    if v == nil then return "NIL" end
    return "READABLE"
end

-- Probe(fn, ...) -> status, firstValue(if READABLE), errtext, allResults(table, readable only)
function Lab.Probe(fn, ...)
    if type(fn) ~= "function" then return "MISSING" end
    local r = { pcall(fn, ...) }
    local ok = table.remove(r, 1)
    local st, detail = Lab.Classify(ok, r[1])
    if st == "READABLE" then return st, r[1], nil, r end
    return st, nil, detail
end

function Lab.Fmt(st, v, err)
    if st == "READABLE" then return tostring(v) end
    if st == "ERROR" then return "ERROR(" .. tostring(err):sub(1, 80) .. ")" end
    return st
end

function Lab.Resolve(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
        if cur == nil then return nil end
    end
    return cur
end

function Lab.Log(tag, fmt, ...)
    local n = select("#", ...)
    local msg = fmt
    if n > 0 then
        local a = { ... }
        for i = 1, n do
            local x = a[i]
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
    if Lab.echo then print("|cff88ccffQXPLab|r " .. line) end
end

function Lab.AddCommand(name, help, fn)
    Lab.handlers[name] = fn
    Lab.helptext[#Lab.helptext + 1] = ("/qxplab %s - %s"):format(name, help)
end

function Lab.Comma(n)
    if type(n) ~= "number" then return tostring(n) end
    local s = tostring(math.floor(n))
    while true do
        local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = r
        if k == 0 then break end
    end
    return s
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    QuestXPLabDB = QuestXPLabDB or {}
    Lab.db = QuestXPLabDB
    Lab.lines = Lab.db.lines or {}
    Lab.db.lines = Lab.lines
    Lab.db.priorSnapshot = Lab.db.snapshot -- from before reload (M3 persistence check)
    Lab.Log("LOAD", "QuestXPLab loaded (%d lines buffered)", #Lab.lines)
    if Lab.OnLoaded then Lab.OnLoaded() end
end)
