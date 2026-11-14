--[[
    Debug.lua - Debug output and slash subcommands
]]

local _, HMF = ...

HMF.Debug = HMF.Debug or {}

function HMF.Debug.Print(...)
    print("|cff66ccffHMF|r", ...)
end

local HELP = "commands: unlock | lock | reset | demo (track target) | resetpos | scale <0.5-1.5> | width <240-340> | arrow (diagnose) | focus (diagnose) | bind <KEY> | macro | skip <hud|focus|events> | trace | test run"

local tracing = false
function HMF.Debug.StartTrace()
    if HMF.Debug.traceHooked then return end
    HMF.Debug.traceHooked = true
    HMF.Services.Tracker.Subscribe(function(event, entry, reason)
        if not tracing then return end
        HMF.Debug.Print("trace", event, entry and (entry.name or entry.guid) or "-", reason or "")
    end)
end

function HMF.Debug.HandleSlash(msg)
    msg = (msg or ""):lower()
    local scale = msg:match("^scale%s+([%d%.]+)$")
    if scale then
        HMF.Debug.Print("scale", HMF.UI.HUD.SetScale(scale))
        return
    end
    local skipName = msg:match("^skip%s+(%a+)$")
    if skipName then
        HoldMyFearDB.skip = HoldMyFearDB.skip or {}
        HoldMyFearDB.skip[skipName] = not HoldMyFearDB.skip[skipName] or nil
        HMF.Debug.Print("skip", skipName, HoldMyFearDB.skip[skipName] and "ON" or "off", "- /reload to apply")
        return
    end
    if msg == "macro" then
        local _, message = HMF.UI.FocusButton.CreateMacro()
        HMF.Debug.Print(message)
        return
    end
    local key = msg:match("^bind%s+(%S+)$")
    if msg == "bind" or key then
        local _, message = HMF.UI.FocusButton.Bind(key)
        HMF.Debug.Print(message)
        return
    end
    local w = msg:match("^width%s+(%d+)$")
    if w then
        HMF.Debug.Print("width", HMF.UI.HUD.SetWidth(w))
        return
    end
    if msg == "unlock" then
        HMF.UI.HUD.SetLocked(false)
    elseif msg == "lock" then
        HMF.UI.HUD.SetLocked(true)
    elseif msg == "reset" then
        HMF.Services.Encounter.Reset("manual /hmf reset")
    elseif msg == "arrow" then
        local U = HMF.Adapters.Unit
        local function report(label, token)
            local bearing, why = U.WorldBearing(token)
            HMF.Debug.Print("arrow", label, token, bearing and ("bearing " .. bearing .. " via " .. tostring(why)) or why,
                "facing", tostring(U.Facing()), "combat", tostring(InCombatLockdown()))
        end
        local function pos(token)
            if not UnitPosition then return "UnitPosition missing" end
            local ok, y, x, z, inst = pcall(UnitPosition, token)
            return ok and ("y=" .. tostring(y) .. " x=" .. tostring(x) .. " z=" .. tostring(z) .. " inst=" .. tostring(inst)) or tostring(y)
        end
        HMF.Debug.Print("arrow UnitPosition player:", pos("player"))
        HMF.Debug.Print("arrow UnitPosition target:", pos("target"))
        if UnitExists("target") then report("target", "target") else HMF.Debug.Print("arrow", "no target") end
        for _, e in ipairs(HMF.Services.Tracker.List()) do
            report(e.name or e.guid, U.TokenFor(e.guid) or "none")
        end
    elseif msg == "focus" then
        local F = HMF.Services.Focus
        local function nm(g) local e = g and HMF.Services.Tracker.Get(g) return e and (e.name or g) or tostring(g) end
        local FB = HMF.UI.FocusButton
        HMF.Debug.Print("button exists:", tostring(FB.button ~= nil), "clicks:", tostring(FB.clicks),
            FB.lastClick and ("last " .. ("%.1f"):format(GetTime() - FB.lastClick) .. "s ago") or "never", FB.seen or "")
        HMF.Debug.Print("bound action for key 6:", tostring(GetBindingAction("6")), "| keys for button:",
            tostring((GetBindingKey("CLICK HMFSetFocusButton:LeftButton"))))
        local mi = GetMacroIndexByName and GetMacroIndexByName("HMF Focus")
        HMF.Debug.Print("macro index:", tostring(mi), (mi and mi > 0) and ((GetMacroBody(mi) or "?"):gsub("\n", " | ")) or "")
        HMF.Debug.Print("focus unit now:", tostring(UnitName("focus")))
        local sug = F.Suggested()
        for i, e in ipairs(HMF.Services.Tracker.List()) do
            local left = HMF.Services.Tracker.FearRemaining(e)
            HMF.Debug.Print("row", i, e.name or "?", left and ("fear " .. math.ceil(left) .. "s") or "no fear",
                e.guid == sug and "<- SUGGESTED" or "", F.IsFocused(e.guid) and "<- FOCUSED" or "")
        end
        HMF.Debug.Print("focus key:", tostring(HMF.UI.FocusButton.Key() or "unbound (use /hmf bind <KEY>)"))
        HMF.Debug.Print("focus actual:", nm(HMF.Adapters.Unit.FocusGUID()), "suggested:", nm(F.Evaluate()))
        -- Minimap tracking entries mentioning focus (Blizzard's "Focus Target" blip).
        local n = GetNumTrackingTypes and GetNumTrackingTypes() or 0
        for i = 1, n do
            local name, _, active = GetTrackingInfo(i)
            if name and name:lower():find("focus") then HMF.Debug.Print("tracking", i, name, "active", tostring(active)) end
        end
        HMF.Debug.Print("tracking entries scanned:", n)
    elseif msg == "trace" then
        HMF.Debug.StartTrace()
        tracing = not tracing
        HMF.Debug.Print("trace", tracing and "on" or "off")
    elseif msg == "dots" then
        -- What the DoT damage read finds in each spell's description (for the "will it die" estimate).
        for _, name in ipairs(HMF.Constants.TRACKED_DEBUFFS) do
            if HMF.Constants.DAMAGE_DOTS[name] then
                local dmg, text = HMF.Adapters.Unit.DotDamage(name)
                if not dmg and HMF.Constants.SPELL_ALIASES[name] then
                    dmg, text = HMF.Adapters.Unit.DotDamage(HMF.Constants.SPELL_ALIASES[name])
                end
                HMF.Debug.Print(name, dmg or "no damage found", text and ("| " .. text) or "| no description")
            end
        end
    elseif msg == "health" then
        -- What health reads give addon code (run in combat on a target/focus/mouseover).
        local U = HMF.Adapters.Unit
        local function show(v) return tostring(U.IsSecret(v) and "SECRET" or v) end
        for _, token in ipairs({ "target", "focus", "mouseover" }) do
            if UnitExists(token) then
                local cur, max = U.Health(token)
                HMF.Debug.Print(token, "combat", tostring(InCombatLockdown()), "cur", show(cur), "max", show(max),
                    "pct", tostring(U.HealthPercentValue(token)), "api", tostring(UnitHealthPercent ~= nil))
            end
        end
    elseif msg == "resetpos" then
        HMF.UI.HUD.ResetPosition()
    elseif msg == "demo" then
        if not HMF.Services.Encounter.TrackToken("target") then
            HMF.Debug.Print("target an enemy first (or all markers in use)")
        end
    elseif msg == "test run" and HMF.Tests.Run then
        HMF.Tests.Run()
    else
        HMF.Debug.Print(HELP)
    end
end
