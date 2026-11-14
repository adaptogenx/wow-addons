-- Secure-casting discipline for UI/CastButtons.lua (AGENTS.md "Secure-casting rules").
-- The sim does not enforce combat lockdown itself, so these tests check that the addon
-- never *attempts* protected work in combat. Tests below share state and run in order.
local HMF = _G.HoldMyFear
local realModule, realCastName, realKnows = HMF.UI.CastButtons, HMF.Adapters.Unit.CastName, HMF.Adapters.Unit.Knows
local realCreateFrame = _G.CreateFrame

local function addonDir()
    local src = debug.getinfo(1, "S").source:gsub("^@", "")
    return (src:gsub("tests/[^/]*$", ""))
end

local fh = assert(io.open(addonDir() .. "UI/CastButtons.lua", "r"))
local text = fh:read("*a"); fh:close()

-- Fresh copy of the module (own locals), with CreateFrame spied to collect the secure buttons.
local secure, hud = {}, nil
_G.CreateFrame = function(kind, name, parent, template)
    local f = realCreateFrame(kind, name, parent, template)
    if template and template:find("SecureActionButtonTemplate", 1, true) then secure[#secure + 1] = f end
    return f
end
HMF.Adapters.Unit.CastName = function(n) return n end
HMF.Adapters.Unit.Knows = function(n) return n == "Corruption" end
assert(loadstring(text, "@CastButtons.lua"))("HoldMyFear", HMF)
local CB = HMF.UI.CastButtons

local ROWS = 2
local function slotX(i) return 10 + i * 24 end
local function slotY() return -20 end

local function leaveCombat()
    A_Admin.SetInCombat(false)
    A_Admin.FireEvent("PLAYER_REGEN_ENABLED")
end

test("Build in combat is deferred until combat ends", function()
    hud = CreateFrame("Frame", nil, UIParent)
    hud:SetSize(300, 300)
    A_Admin.SetInCombat(true)
    CB.Build(hud, ROWS, slotX, slotY)
    assertEquals(0, #secure)          -- no secure frames created in combat
    leaveCombat()
    assertEquals(ROWS * (1 + #HMF.Constants.PLACEHOLDER_DOTS), #secure)
end)

test("secure buttons are never parented or anchored to a row", function()
    local layer = secure[1]:GetParent()
    assertEquals(hud, layer:GetParent())          -- layer is a child of the HUD frame only
    for _, b in ipairs(secure) do
        assertEquals(layer, b:GetParent())
        local _, rel = b:GetPoint(1)
        assertEquals(layer, rel)
    end
end)

test("attributes are applied out of combat", function()
    assertEquals("macro", secure[1]:GetAttribute("type1"))
    assertMatches(secure[1]:GetAttribute("macrotext1"), "/cast %[@focus,exists,harm,nodead%] Fear")
end)

test("Refresh in combat leaves attributes alone, applies them after combat", function()
    local before = secure[1]:GetAttribute("macrotext1")
    HMF.Adapters.Unit.CastName = function(n) return n .. "2" end
    A_Admin.SetInCombat(true)
    CB.Refresh()
    assertEquals(before, secure[1]:GetAttribute("macrotext1"))   -- untouched in combat
    leaveCombat()
    assertMatches(secure[1]:GetAttribute("macrotext1"), "Fear2")  -- queued change applied
end)

-- Restore the real module and adapters so other test files see the live addon.
test("cleanup", function()
    _G.CreateFrame = realCreateFrame
    HMF.Adapters.Unit.CastName, HMF.Adapters.Unit.Knows = realCastName, realKnows
    HMF.UI.CastButtons = realModule
    A_Admin.SetInCombat(false)
    assertEquals(realModule, HMF.UI.CastButtons)
end)
