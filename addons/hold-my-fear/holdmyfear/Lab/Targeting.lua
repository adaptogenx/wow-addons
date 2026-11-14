--[[
    Lab/Targeting.lua - Experiment 1: which mechanisms can act on a
    nameplate unit token?

    Run 1/2 findings: `unit="target"` casts; `unit="nameplateN"` (spell
    attribute) and `/cast [@nameplateN] Fear` (macro) produce no SENT and
    no error, even in range and in combat. This matrix isolates whether the
    token itself is rejected (targeting/focus actions) or only as a spell
    target, and whether insecure Lua works out of combat.

    All tests aim at nameplate1. Secure buttons never have attributes
    changed after build.
]]

local _, HMF = ...
local Lab = HMF.Lab

local TOKEN = "nameplate1"
local LINES = 9

local INSTRUCTIONS = table.concat({
    "OUT OF COMBAT, enemies within ~15 yds, in line of sight.",
    "1. Target mob A. Check the 'np1' line: that mob (B) is the test unit.",
    "   If np1 is A, step to see another mob so np1 is not your target.",
    "2. Click ONE button at a time, in order 1 to 12. Read the log.",
    "   Each prints TEST lines: target/focus/np1 before and after.",
    "3. Tests 5,6,11 change target; 7,8,12 set focus. Re-target A after,",
    "   and /clearfocus. Test 9 (@focus) needs focus set first (7 or 8).",
    "4. Tests 1,2,3,4,9,10 cast Fear (~1.5s, needs mana).",
    "5. Type /hmflab report, then /reload, and tell me.",
}, "\n")

local function Snap()
    return ("target=%s focus=%s np1=%s"):format(Lab.Short(UnitGUID("target")), Lab.Short(UnitGUID("focus")),
        Lab.Short(UnitGUID(TOKEN)))
end

local function Before(name, cast)
    Lab.Log("TEST", "%s BEFORE %s", name, Snap())
    if cast then Lab.Cast.Intend("exp1:" .. name, UnitGUID(TOKEN), TOKEN) end
end

local function After(name)
    C_Timer.After(0.4, function()
        Lab.Log("TEST", "%s AFTER  %s blocked=%s", name, Snap(), tostring(Lab.blocked or 0))
    end)
end

-- Secure variants: attrs = table of attribute -> value.
local SECURE = {
    { "unit-spell", true, { type = "spell", spell = "Fear", unit = TOKEN } },
    { "@np1 macro", true, { type = "macro", macrotext = "/cast [@nameplate1] Fear" } },
    { "@np1,harm", true, { type = "macro", macrotext = "/cast [@nameplate1,harm] Fear" } },
    { "@target", true, { type = "macro", macrotext = "/cast [@target] Fear" } },
    { "type=target", false, { type = "target", unit = TOKEN } },
    { "/target np1", false, { type = "macro", macrotext = "/target nameplate1" } },
    { "type=focus", false, { type = "focus", unit = TOKEN } },
    { "/focus np1", false, { type = "macro", macrotext = "/focus nameplate1" } },
    { "@focus", true, { type = "macro", macrotext = "/cast [@focus] Fear" } },
}

-- Insecure Lua variants (out of combat only; blocked in combat by design).
local INSECURE = {
    { "Lua Cast", true, function() CastSpellByName("Fear", TOKEN) end },
    { "Lua Target", false, function() TargetUnit(TOKEN) end },
    { "Lua Focus", false, function() FocusUnit(TOKEN) end },
}

Lab.AddSection("Exp 1: what can act on nameplate1?", LINES * 13 + 8 + 3 * 26 + 18, function(parent)
    local help = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, 0)
    help:SetJustifyH("LEFT")
    help:SetText(INSTRUCTIONS)
    local top = LINES * 13 + 8

    local n = 0
    local function Slot()
        n = n + 1
        return ((n - 1) % 4) * 104, -top - math.floor((n - 1) / 4) * 26
    end

    for _, t in ipairs(SECURE) do
        local x, y = Slot()
        local name, cast, attrs = t[1], t[2], t[3]
        local label = ("%d %s"):format(n, name)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate,SecureActionButtonTemplate")
        btn:SetSize(100, 22)
        btn:SetPoint("TOPLEFT", x, y)
        btn:SetText(label)
        btn:GetFontString():SetFont(STANDARD_TEXT_FONT, 10)
        btn:RegisterForClicks("AnyDown", "AnyUp")
        for k, v in pairs(attrs) do btn:SetAttribute(k, v) end
        btn:HookScript("PreClick", function(_, _, down)
            if down then Before(label, cast) end
        end)
        btn:HookScript("PostClick", function(_, _, down)
            if down then After(label) end
        end)
    end

    for _, t in ipairs(INSECURE) do
        local x, y = Slot()
        local name, cast, fn = t[1], t[2], t[3]
        local label = ("%d %s"):format(n, name)
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(100, 22)
        btn:SetPoint("TOPLEFT", x, y)
        btn:SetText(label)
        btn:GetFontString():SetFont(STANDARD_TEXT_FONT, 10)
        btn:SetScript("OnClick", function()
            Before(label, cast)
            local ok, err = pcall(fn)
            Lab.Log("TEST", "%s pcall ok=%s err=%s", label, tostring(ok), tostring(err))
            After(label)
        end)
    end

    local info = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", 0, -top - 3 * 26 - 4)
    Lab.OnTick(function()
        local inRange = C_Spell and C_Spell.IsSpellInRange and C_Spell.IsSpellInRange("Fear", TOKEN)
        local color = inRange and "|cff40ff40IN RANGE|r" or "|cffff4040TOO FAR / no unit|r"
        info:SetText(("np1: %s %s  %s   target: %s"):format(Lab.Short(UnitGUID(TOKEN)),
            tostring(UnitName(TOKEN)), color, tostring(UnitName("target"))))
    end)
end)
