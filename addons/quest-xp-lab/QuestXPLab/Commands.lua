--[[ /qxplab dispatcher. ]]
local _, Lab = ...

Lab.AddCommand("report", "print last N log lines (default 60)", function(n)
    n = tonumber(n) or 60
    local from = math.max(1, #Lab.lines - n + 1)
    print(("|cff88ccffQXPLab|r %d of %d lines"):format(#Lab.lines - from + 1, #Lab.lines))
    for i = from, #Lab.lines do print(Lab.lines[i]) end
end)
Lab.AddCommand("scenario", "tag following logs, e.g. /qxplab scenario kill-3of10", function(a) Lab.scenario = (a and a ~= "") and a or "-" Lab.Log("NOTE", "scenario set") end)
Lab.AddCommand("note", "free-text note", function(a) Lab.Log("NOTE", "%s", a or "") end)
Lab.AddCommand("echo", "toggle live echo of log to chat", function() Lab.echo = not Lab.echo print("QXPLab echo", Lab.echo and "on" or "off") end)
Lab.AddCommand("clear", "clear log", function() for i = #Lab.lines, 1, -1 do Lab.lines[i] = nil end end)

SLASH_QXPLAB1 = "/qxplab"
SlashCmdList["QXPLAB"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
    local h = Lab.handlers[cmd:lower()]
    if h then
        h(rest)
    else
        print("|cff88ccffQXPLab|r commands:")
        for _, t in ipairs(Lab.helptext) do print("  " .. t) end
    end
end
