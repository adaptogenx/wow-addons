--[[
    Tests/TestRunner.lua - Minimal in-addon test runner (TDD §24.2)

    Each test module registers itself with :Register(name, fn). fn returns
    (passed: boolean, message: string). Matches pH's `/pockets test run`
    pattern for tests that need addon runtime behavior.
]]

local _, Pockets = ...

Pockets.Tests.TestRunner = Pockets.Tests.TestRunner or { tests = {} }
local TestRunner = Pockets.Tests.TestRunner

local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_RESET = "|r"

function TestRunner:Register(name, fn)
    table.insert(self.tests, { name = name, fn = fn })
end

-- Prints every PASS/FAIL as it runs (unchanged), then a second,
-- clearly-bordered FAILURES-ONLY recap at the very end listing just the
-- failing test names + messages. Screenshotting/copy-pasting a WoW chat
-- frame with 250+ interleaved PASS lines to find the handful of FAILs
-- buried in it is painful (chat has no scroll-to-failure/export) - the
-- recap is the LAST thing printed, so it's what's on screen without any
-- scrolling once the run finishes.
-- Texture equality that works on both clients: Classic reports the path
-- string, Forever a numeric file ID. Compares against what the client
-- itself reports for `path`.
function Pockets.Tests.TextureEquals(actual, path)
    if actual == path then
        return true
    end
    local probe = UIParent:CreateTexture()
    probe:SetTexture(path)
    local expected = probe:GetTexture()
    return actual ~= nil and actual == expected
end

-- Layout getters on Forever return float32 noise (19.999988 for 20,
-- 243.99996 for 244). Tests compare exact pixel values, so while tests run
-- the size/position getters report values rounded to 0.01px. Restored
-- afterwards; production code never sees this.
local ROUNDED_GETTERS = { "GetWidth", "GetHeight", "GetSize", "GetLeft", "GetRight", "GetTop", "GetBottom", "GetPoint" }
local function Round(v)
    if type(v) == "number" then
        return math.floor(v * 100 + 0.5) / 100
    end
    return v
end

local function InstallRoundedGetters()
    local saved = {}
    local seen = {}
    local function Wrap(widgetType, create)
        local ok, obj = pcall(create)
        if not ok or not obj then return end
        local mt = getmetatable(obj)
        local index = mt and mt.__index
        if type(index) ~= "table" or seen[index] then return end
        seen[index] = true
        for _, name in ipairs(ROUNDED_GETTERS) do
            local original = rawget(index, name)
            if type(original) == "function" then
                saved[#saved + 1] = { index, name, original }
                index[name] = function(...)
                    local a, b, c, d, e = original(...)
                    return Round(a), Round(b), Round(c), Round(d), Round(e)
                end
            end
        end
    end
    Wrap("Frame", function() return CreateFrame("Frame") end)
    Wrap("Button", function() return CreateFrame("Button") end)
    Wrap("EditBox", function() return CreateFrame("EditBox") end)
    Wrap("ScrollFrame", function() return CreateFrame("ScrollFrame") end)
    Wrap("Texture", function() return UIParent:CreateTexture() end)
    Wrap("FontString", function() return UIParent:CreateFontString() end)
    return saved
end

local function RemoveRoundedGetters(saved)
    for _, entry in ipairs(saved or {}) do
        entry[1][entry[2]] = entry[3]
    end
end

function TestRunner:RunAll()
    local roundedSaved = InstallRoundedGetters()
    local passed, failed = 0, 0
    local failures = {}
    for _, test in ipairs(self.tests) do
        local ok, resultOrErr, message = pcall(test.fn)
        local testPassed = ok and resultOrErr
        local testMessage = ok and (message or "OK") or ("ERROR: " .. tostring(resultOrErr))

        if testPassed then
            passed = passed + 1
        else
            failed = failed + 1
            table.insert(failures, { name = test.name, message = testMessage })
        end

        local color = testPassed and COLOR_GREEN or COLOR_RED
        local status = testPassed and "PASS" or "FAIL"
        print(string.format("%s[Test: %s] %s: %s%s", color, test.name, status, testMessage, COLOR_RESET))
    end

    if #failures > 0 then
        print(COLOR_RED .. string.format("======== %d FAILED TEST(S) ========", #failures) .. COLOR_RESET)
        for i, failure in ipairs(failures) do
            print(string.format("%s%d. %s%s", COLOR_RED, i, failure.name, COLOR_RESET))
            print("   " .. failure.message)
        end
        print(COLOR_RED .. "===================================" .. COLOR_RESET)
    end

    RemoveRoundedGetters(roundedSaved)

    -- Persist the outcome so it can be read from the SavedVariables file
    -- (WTF/.../SavedVariables/Pockets.lua) after /reload, instead of
    -- screenshotting chat.
    if _G.PocketsDB then
        _G.PocketsDB.lastTestRun = { passed = passed, failed = failed, failures = failures }
    end

    return passed, failed
end
