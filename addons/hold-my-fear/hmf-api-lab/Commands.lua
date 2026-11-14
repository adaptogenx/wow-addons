--[[ /hmflab dispatcher, report, scenario tagging. ]]
local _, Lab = ...

local function report(n)
    n = tonumber(n) or 60
    local lines = Lab.lines
    local from = math.max(1, #lines - n + 1)
    print(("|cff88ccffHMFLab|r report: %d of %d lines"):format(#lines - from + 1, #lines))
    for i = from, #lines do print(lines[i]) end
end

Lab.AddCommand("report", "print last N log lines (default 60; full buffer also saved to SavedVariables)", report)
Lab.AddCommand("scenario", "tag following logs, e.g. /hmflab scenario ooc-two-mobs", function(a) Lab.scenario = (a and a ~= "") and a or "-" Lab.Log("NOTE", "scenario set") end)
Lab.AddCommand("note", "add a free-text note to the log", function(a) Lab.Log("NOTE", "%s", a or "") end)
Lab.AddCommand("echo", "toggle live echo of log lines to chat", function() Lab.echo = not Lab.echo print("HMFLab echo", Lab.echo and "on" or "off") end)
Lab.AddCommand("clear", "clear log buffer", function() for i = #Lab.lines, 1, -1 do Lab.lines[i] = nil end print("HMFLab cleared") end)

SLASH_HMFLAB1 = "/hmflab"
SlashCmdList["HMFLAB"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local h = Lab.handlers[cmd]
    if h then
        h(rest)
        if cmd ~= "report" and cmd ~= "clear" then print("|cff88ccffHMFLab|r " .. cmd .. " done; /hmflab report 80") end
    else
        print("|cff88ccffHMFLab|r commands:")
        for _, t in ipairs(Lab.helptext) do print("  " .. t) end
    end
end
