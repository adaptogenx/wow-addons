--[[
    Lab/Log.lua - Shared logging + result registry for the targeting lab
    (.plans/prompts/experiment1-3.txt). Lab code is throwaway research
    code: it is allowed to touch Blizzard APIs and secure attributes
    directly, unlike the production layers.
]]

local _, HMF = ...

local Lab = {}
HMF.Lab = Lab

local MAX_LINES = 400

Lab.lines = {}
Lab.sections = {}
Lab.tickers = {}
Lab.results = {}
Lab.sink = nil -- set by Window.lua: function(line)

function Lab.Short(guid)
    if not guid then return "nil" end
    local tail = guid:match("%-(%d+%-%x+)$")
    return tail or guid
end

function Lab.Log(tag, fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local args = { ... }
        for i = 1, select("#", ...) do args[i] = tostring(args[i]) end
        msg = fmt:format(unpack(args))
    end
    local line = ("%.1f [%s] %s%s"):format(GetTime() % 10000, tag, InCombatLockdown() and "(combat) " or "", msg)
    local lines = Lab.lines
    lines[#lines + 1] = line
    if #lines > MAX_LINES then table.remove(lines, 1) end
    if Lab.sink then Lab.sink(line) end
end

-- Record an experiment outcome: status is "works" | "blocked" | "unknown".
function Lab.Result(key, status, detail)
    Lab.results[key] = { status = status, detail = detail }
    Lab.Log("RESULT", "%s -> %s%s", key, status, detail and (" (" .. detail .. ")") or "")
end

function Lab.AddSection(title, height, build)
    Lab.sections[#Lab.sections + 1] = { title = title, height = height, build = build }
end

-- Run fn every tick while the lab window is shown.
function Lab.OnTick(fn)
    Lab.tickers[#Lab.tickers + 1] = fn
end

function Lab.Report()
    Lab.Log("REPORT", "---- lab results (in-game, current client) ----")
    local keys = {}
    for k in pairs(Lab.results) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then Lab.Log("REPORT", "no results recorded yet; run the scenarios") end
    for _, k in ipairs(keys) do
        local r = Lab.results[k]
        Lab.Log("REPORT", "%s: %s%s", k, r.status, r.detail and (" - " .. r.detail) or "")
    end
end
