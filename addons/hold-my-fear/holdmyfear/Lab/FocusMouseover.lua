--[[
    Lab/FocusMouseover.lua - Experiment 4: do `focus` and `mouseover`
    work as secure spell targets (nameplate tokens do not, Exp 1)?

    Focus:     secure macro `/focus target` sets it (also works in combat);
               `/cast [@focus,harm,nodead] Fear` and unit=focus cast on it.
    Mouseover: window buttons cannot be the mouseover unit, so these two
               buttons are driven by override bindings (ALT-F, ALT-G) set
               once at build time, out of combat.
    Intended GUID is read at PreClick; the combat log supplies the actual.
    Mouseover is passed with token=nil so a moving mouse during the 1.5s
    cast is not treated as a stale binding.
]]

local _, HMF = ...
local Lab = HMF.Lab

local KEY_MACRO, KEY_UNIT = "ALT-F", "ALT-G"
local LINES = 13

local INSTRUCTIONS = table.concat({
    "SETUP: 2 enemies A and B nearby (in range, line of sight).",
    "",
    "FOCUS vs TARGET (the key test; focus must differ from target):",
    " a. Target B. Click '1 Set focus'.",
    " b. Target A (use Tab or click A). Log must show target=A focus=B.",
    " c. Click '2 Fear @focus'. Fear must land on B.",
    "    Success line: CAST intended=B actual=B.",
    " d. Repeat in combat with '3 Fear unit=focus'.",
    "MOUSEOVER (keys; do not move or press anything else for 2 sec):",
    " e. Target A. Hover B, press OPTION-F, keep the mouse STILL on B",
    "    and stand still until the cast finishes. Repeat with OPTION-G.",
    "Then /hmflab report, /reload, tell me.",
    "Good = CAST intended=X actual=X, never WRONG or INTERRUPTED.",
}, "\n")

local function Snap()
    return ("target=%s focus=%s mouseover=%s"):format(Lab.Short(UnitGUID("target")), Lab.Short(UnitGUID("focus")),
        Lab.Short(UnitGUID("mouseover")))
end

local function Wire(btn, label, token)
    btn:HookScript("PreClick", function(_, _, down)
        if not down then return end
        Lab.Log("TEST", "%s BEFORE %s", label, Snap())
        if token then
            Lab.Cast.Intend("exp4:" .. label, UnitGUID(token), token)
        elseif token == false then
            Lab.Cast.Intend("exp4:" .. label, UnitGUID("mouseover"), nil)
        end
    end)
    btn:HookScript("PostClick", function(_, _, down)
        if not down then return end
        C_Timer.After(0.4, function() Lab.Log("TEST", "%s AFTER  %s", label, Snap()) end)
    end)
end

local function Secure(parent, name, label, x, y, attrs, token, w)
    local btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    btn:SetSize(w or 100, 22)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetText(label)
    btn:GetFontString():SetFont(STANDARD_TEXT_FONT, 10)
    btn:RegisterForClicks("AnyDown", "AnyUp")
    for k, v in pairs(attrs) do btn:SetAttribute(k, v) end
    Wire(btn, label, token)
    return btn
end

Lab.AddSection("Exp 4: focus and mouseover as cast targets", LINES * 13 + 8 + 2 * 26 + 18, function(parent)
    local help = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetJustifyH("LEFT")
    help:SetText(INSTRUCTIONS)
    local top = LINES * 13 + 8

    Secure(parent, nil, "1 Set focus", 0, -top, { type = "macro", macrotext = "/focus target" }, nil)
    Secure(parent, nil, "2 Fear @focus", 104, -top,
        { type = "macro", macrotext = "/cast [@focus,harm,nodead] Fear" }, "focus")
    Secure(parent, nil, "3 Fear unit=focus", 208, -top,
        { type = "spell", spell = "Fear", unit = "focus" }, "focus")
    Secure(parent, nil, "4 Clear focus", 312, -top, { type = "macro", macrotext = "/clearfocus" }, nil)

    local mo1 = Secure(parent, "HMFLabFearMouseoverMacro", "5 @mouseover", 0, -top - 26,
        { type = "macro", macrotext = "/cast [@mouseover,harm,nodead] Fear" }, false, 150)
    local mo2 = Secure(parent, "HMFLabFearMouseoverUnit", "6 unit=mouseover", 154, -top - 26,
        { type = "spell", spell = "Fear", unit = "mouseover" }, false, 150)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", mo2, "RIGHT", 6, 0)
    label:SetText("Option-F / Option-G")

    -- Override bindings, set once out of combat (build runs at PLAYER_LOGIN).
    SetOverrideBindingClick(parent, true, KEY_MACRO, mo1:GetName(), "LeftButton")
    SetOverrideBindingClick(parent, true, KEY_UNIT, mo2:GetName(), "LeftButton")

    local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 0, -top - 2 * 26 - 4)
    Lab.OnTick(function()
        info:SetText(("target: %s | focus: %s | mouseover: %s"):format(tostring(UnitName("target")),
            tostring(UnitName("focus")), tostring(UnitName("mouseover"))))
    end)
end)
