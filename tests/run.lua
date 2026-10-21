-- Offline tests for shared/ui and its per-addon staged copies.
-- Run from the repo root: lua tests/run.lua   (scripts/test.sh does this
-- after syncing). Loads the STAGED files each addon actually ships.
package.path = "tests/?.lua;" .. package.path
local stub = require("wow_stub")
local golden = dofile("tests/golden/phui_tokens.lua")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n     " .. tostring(err))
    end
end
local function eq(a, b, msg)
    if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end
local function deepEq(a, b, path)
    path = path or "root"
    if type(a) ~= type(b) then error(path .. ": type " .. type(a) .. " vs " .. type(b), 2) end
    if type(a) ~= "table" then
        if a ~= b then error(path .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
        return
    end
    for k, v in pairs(b) do deepEq(a[k], v, path .. "." .. tostring(k)) end
    for k in pairs(a) do if b[k] == nil then error(path .. "." .. tostring(k) .. " unexpected", 2) end end
end

local ADDONS = {
    ph = { dir = "addons/ph/ph", toc = "addons/ph/ph/ph.toc", name = "ph" },
    pockets = { dir = "addons/pockets/pockets", toc = "addons/pockets/pockets/Pockets.toc", name = "Pockets" },
}

-- Shared/UI files in TOC order, exactly as WoW would load them.
local function sharedFiles(addon)
    local files = {}
    for line in io.lines(addon.toc) do
        line = line:gsub("\r", ""):match("^%s*(.-)%s*$")
        if line:match("^Shared/UI/.+%.lua$") then files[#files + 1] = line end
    end
    return files
end

-- Load one addon's shared files; returns its namespace table.
local function loadAddon(env, addon, ns)
    ns = ns or {}
    for _, f in ipairs(sharedFiles(addon)) do
        stub.loadAddonFile(env, addon.dir .. "/" .. f, addon.name, ns)
    end
    return ns
end

local function snapshot(PHUI)
    local out = {}
    for _, k in ipairs({ "Colors", "Fonts", "Spacing", "Backdrops", "Icons" }) do out[k] = PHUI[k] end
    return out
end
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

--------------------------------------------------------------------
-- Namespace isolation
--------------------------------------------------------------------
test("TOCs list shared files and PHUI loads first", function()
    for id, a in pairs(ADDONS) do
        local files = sharedFiles(a)
        assert(#files > 0, id .. " lists no Shared/UI files")
        eq(files[1], "Shared/UI/PHUI.lua", id .. " first shared file")
    end
end)

test("pH loads independently", function()
    local env = stub.newEnv()
    local ns = loadAddon(env, ADDONS.ph)
    assert(ns.UI and ns.UI.PHUI, "ns.UI.PHUI missing")
    eq(#env.writes, 0, "global writes: " .. table.concat(env.writes, ","))
    eq(env.G.PHUI, nil, "_G.PHUI")
end)

test("Pockets loads independently", function()
    local env = stub.newEnv()
    local ns = loadAddon(env, ADDONS.pockets)
    for _, k in ipairs({ "PHUI", "MetricRow", "ScrollBar", "GlanceFrame", "PositionStrategy" }) do
        assert(ns.UI[k], "ns.UI." .. k .. " missing")
    end
    eq(#env.writes, 0, "global writes: " .. table.concat(env.writes, ","))
    eq(env.G.PHUI, nil, "_G.PHUI")
end)

test("every shared file loads cleanly into pH's namespace too (no Pockets needed)", function()
    local env = stub.newEnv()
    local ns = {}
    for _, f in ipairs({ "PHUI", "MetricRow", "ScrollBar", "GlanceFrame", "PositionStrategy" }) do
        stub.loadAddonFile(env, "addons/ph/ph/Shared/UI/" .. f .. ".lua", "ph", ns)
    end
    eq(#env.writes, 0)
end)

for _, order in ipairs({ { "ph", "pockets" }, { "pockets", "ph" } }) do
    test("both addons load together, order " .. order[1] .. " -> " .. order[2], function()
        local env = stub.newEnv() -- one shared global env, like WoW
        local ns = {}
        for _, id in ipairs(order) do ns[id] = loadAddon(env, ADDONS[id]) end
        assert(ns.ph.UI.PHUI ~= ns.pockets.UI.PHUI, "PHUI instances are shared")
        eq(env.G.PHUI, nil, "_G.PHUI")
        eq(#env.writes, 0, "global writes")
        deepEq(snapshot(ns.ph.UI.PHUI), snapshot(ns.pockets.UI.PHUI))
    end)
end

test("no cross-addon mutable state", function()
    local env = stub.newEnv()
    local a = loadAddon(env, ADDONS.ph)
    local b = loadAddon(env, ADDONS.pockets)
    local before = copy(snapshot(b.UI.PHUI))
    a.UI.PHUI.Colors.TEXT_PRIMARY[1] = 0
    a.UI.PHUI.Colors.NEW_TOKEN = { 1, 1, 1 }
    a.UI.PHUI.Spacing.PADDING = 99
    a.UI.PHUI.IsForever = function() return true end
    a.UI.PHUI.SetForeverDetector(function() return true end)
    deepEq(snapshot(b.UI.PHUI), before)
    eq(b.UI.PHUI.IsForever(), false, "pockets detector leaked from pH")
end)

--------------------------------------------------------------------
-- PHUI API / tokens (golden = original Pockets Shared/PHUI.lua)
--------------------------------------------------------------------
local function freshPHUI(opts, id)
    local env = stub.newEnv(opts)
    local ns = loadAddon(env, ADDONS[id or "pockets"])
    return ns.UI.PHUI, ns, env
end

for _, id in ipairs({ "ph", "pockets" }) do
    test("[" .. id .. "] tokens unchanged vs original PHUI", function()
        local PHUI = freshPHUI(nil, id)
        for _, k in ipairs({ "Colors", "Fonts", "Spacing", "Backdrops", "Icons" }) do
            deepEq(PHUI[k], golden[k], k)
        end
        for k, v in pairs(golden.constants) do eq(PHUI[k], v, k) end
    end)

    test("[" .. id .. "] public helpers preserved, PH_HUD_WIDTH removed", function()
        local PHUI = freshPHUI(nil, id)
        for _, fn in ipairs(golden.functions) do eq(type(PHUI[fn]), "function", fn) end
        for _, k in ipairs(golden.removed) do eq(PHUI[k], nil, k) end
    end)
end

test("shared files hold no Pockets/pH-specific identifiers", function()
    for _, f in ipairs({ "PHUI", "MetricRow", "ScrollBar", "GlanceFrame", "PositionStrategy" }) do
        local src = io.open("shared/ui/" .. f .. ".lua"):read("*a")
        for _, bad in ipairs({ "Pockets", "pH_", "GoldPH", "Adapters", "ClientAPI", "PH_HUD_WIDTH", "_G%.PHUI" }) do
            assert(not src:find(bad), f .. " references " .. bad)
        end
    end
end)

--------------------------------------------------------------------
-- PHUI behavior
--------------------------------------------------------------------
test("CreateCloseButton: Classic keeps native 32", function()
    local PHUI, _, env = freshPHUI({ interface = 11504 })
    local b = PHUI.CreateCloseButton(env.G.UIParent)
    eq(b.w, 32); eq(b.h, 32)
    eq(b.template, "UIPanelCloseButton")
end)

test("CreateCloseButton: Forever shrinks to 24 (default detector)", function()
    local PHUI, _, env = freshPHUI({ interface = 16001 })
    local b = PHUI.CreateCloseButton(env.G.UIParent)
    eq(b.w, 24)
end)

test("CreateCloseButton: injected detector wins; opts.size honored on Classic", function()
    local PHUI, _, env = freshPHUI({ interface = 11504 })
    PHUI.SetForeverDetector(function() return true end)
    eq(PHUI.CreateCloseButton(env.G.UIParent).w, 24)
    PHUI.SetForeverDetector(nil) -- back to default
    eq(PHUI.CreateCloseButton(env.G.UIParent, { size = 18 }).w, 18)
end)

test("CreateIconButton: hover border + tooltip + click gating", function()
    local PHUI, _, env = freshPHUI()
    local clicks = 0
    local b = PHUI.CreateIconButton(env.G.UIParent, 20, "tex", { tooltipText = "Tip", onClick = function() clicks = clicks + 1 end })
    eq(b.template, "BackdropTemplate")
    deepEq(b.backdrop, golden.Backdrops.ICON_BUTTON)
    deepEq(b.borderColor, { 0.596, 0.451, 0.263, 1 })
    b.__scripts.OnEnter(b)
    deepEq(b.borderColor, { 1.00, 0.82, 0.00, 1.0 })
    eq(env.G.GameTooltip.text, "Tip"); eq(env.G.GameTooltip.shown, true)
    b.__scripts.OnLeave(b)
    deepEq(b.borderColor, { 0.596, 0.451, 0.263, 1.0 })
    eq(env.G.GameTooltip.shown, false)
    b.__scripts.OnClick(b); eq(clicks, 1)
    b.isActionDisabled = true
    b.__scripts.OnClick(b); eq(clicks, 1, "disabled click fired")
end)

test("CreateIconButton: no tooltip when tooltipText omitted", function()
    local PHUI, _, env = freshPHUI()
    local b = PHUI.CreateIconButton(env.G.UIParent, 20, "tex")
    b.__scripts.OnEnter(b)
    eq(env.G.GameTooltip.shown, false)
end)

test("CreateNativeIconButton: textures, tooltip, click", function()
    local PHUI, _, env = freshPHUI()
    local n = 0
    local b = PHUI.CreateNativeIconButton(env.G.UIParent, 16, "a", { pushedTexture = "b", tooltipText = "T", onClick = function() n = n + 1 end })
    eq(b.normalTexture, "a"); eq(b.pushedTexture, "b")
    b.__scripts.OnEnter(b); eq(env.G.GameTooltip.text, "T")
    b.__scripts.OnLeave(b); eq(env.G.GameTooltip.shown, false)
    b.__scripts.OnClick(b); eq(n, 1)
end)

test("CreateLabel / ApplyTextStyle: template vs role-token fonts, colors", function()
    local PHUI, _, env = freshPHUI()
    local l = PHUI.CreateLabel(env.G.UIParent, "muted", "hi")
    eq(l.template, "GameFontNormalSmall"); eq(l.text, "hi")
    deepEq({ l.textColor[1], l.textColor[2], l.textColor[3] }, golden.Colors.TEXT_MUTED)
    local t = PHUI.CreateLabel(env.G.UIParent, "gold", nil, PHUI.Fonts.TITLE)
    deepEq(t.font, golden.Fonts.TITLE)
    deepEq({ t.textColor[1], t.textColor[2], t.textColor[3] }, golden.Colors.ACCENT_GOLD)
end)

test("ApplyBackdrop: defaults and overrides", function()
    local PHUI, _, env = freshPHUI()
    local f = env.G.CreateFrame("Frame", nil, nil, "BackdropTemplate")
    PHUI.ApplyBackdrop(f)
    deepEq(f.backdrop, golden.Backdrops.PANEL)
    deepEq(f.backdropColor, { 0.082, 0.094, 0.090, 0.92 })
    PHUI.ApplyBackdrop(f, { backdrop = PHUI.Backdrops.BADGE, bgAlpha = 0.5 })
    eq(f.backdropColor[4], 0.5)
end)

test("CreateNativeIcon: size, texture, texcoord inset", function()
    local PHUI, _, env = freshPHUI()
    local i = PHUI.CreateNativeIcon(env.G.UIParent, 12, "t")
    eq(i.w, 12); eq(i.texture, "t"); eq(i.texCoord[1], 0.08); eq(i.texCoord[2], 0.92)
    eq(PHUI.CreateNativeIcon(env.G.UIParent, 12, "t", { insetTexCoord = false }).texCoord, nil)
end)

--------------------------------------------------------------------
-- Shared components
--------------------------------------------------------------------
test("MetricRow: layout and setters unchanged", function()
    local _, ns, env = freshPHUI()
    local row = ns.UI.MetricRow:Create(env.G.UIParent, { width = 200, height = 16, iconSize = 12, texture = "x", hasSecondary = true })
    eq(row.w, 200); eq(row.h, 16); eq(row.icon.w, 12)
    local function point(frame, ...)
        local p, want = frame.__points[1], { ... }
        for i = 1, 5 do eq(p[i], want[i], "point arg " .. i) end
    end
    point(row.icon, "LEFT", row, "LEFT", 0, 0)
    point(row.primaryText, "LEFT", row.icon, "RIGHT", 6, 0)
    point(row.secondaryText, "RIGHT", row, "RIGHT", 0, 0)
    row:SetPrimary("a"); row:SetSecondary("b"); row:SetTexture("y"); row:SetPrimaryColor(1, 0, 0, 1)
    eq(row.primaryText.text, "a"); eq(row.secondaryText.text, "b"); eq(row.icon.texture, "y")
    local bare = ns.UI.MetricRow:Create(env.G.UIParent, { width = 1, height = 1, iconSize = 1 })
    bare:SetSecondary("ignored") -- must not error
    eq(bare.secondaryText, nil)
end)

test("ScrollBar: visibility, range, wheel, scroll restore", function()
    local _, ns, env = freshPHUI()
    local SB = ns.UI.ScrollBar
    local parent = env.G.CreateFrame("Frame")
    local sf = env.G.CreateFrame("ScrollFrame", nil, parent)
    local bar = SB:Create(sf)
    eq(SB:IsShown(bar), false)
    SB:Update(bar, 100, 200)
    eq(SB:IsShown(bar), false, "short content must hide bar")
    SB:Update(bar, 500, 200)
    eq(SB:IsShown(bar), true)
    local mn, mx = bar.slider:GetMinMaxValues(); eq(mn, 0); eq(mx, 300)
    eq(bar.slider.thumb.h, 80, "thumb height") -- 200*200/500
    sf.__scripts.OnMouseWheel(sf, -1)          -- wheel down = +30
    eq(sf:GetVerticalScroll(), 30)
    SB:SetScroll(bar, 9999); eq(bar.slider:GetValue(), 300)
    SB:ScrollToTop(bar); eq(sf:GetVerticalScroll(), 0)
end)

test("PositionStrategy: anchor, clamp, apply, capture fallback", function()
    local _, ns, env = freshPHUI()
    local PS = ns.UI.PositionStrategy
    eq(PS:GetRootAnchor(), "TOPLEFT")
    local x, y = PS.ClampToScreen(500, -500, 3000, 2000, 1920, 1080)
    eq(x, 0); eq(y, 0)
    x, y = PS.ClampToScreen(1900, -1000, 100, 100, 1920, 1080)
    eq(x, 1820); eq(y, -980)
    local f = env.G.CreateFrame("Frame")
    PS:ApplyRootPosition(f, { x = 42, y = -17 })
    local p = f.__points[1]
    eq(p[1], "TOPLEFT"); eq(p[2], env.G.UIParent); eq(p[3], "TOPLEFT"); eq(p[4], 42); eq(p[5], -17)
    local cap = PS:CaptureSavedPosition(f)
    eq(cap.point, "TOPLEFT"); eq(cap.x, 42); eq(cap.y, -17)
end)

test("GlanceFrame: nil without template; chrome with it", function()
    local _, ns, env = freshPHUI({ noPortraitTemplate = true })
    eq(ns.UI.GlanceFrame:CreateChrome(env.G.CreateFrame("Frame"), "p", nil, "T"), nil)
    local _, ns2, env2 = freshPHUI()
    local chrome = ns2.UI.GlanceFrame:CreateChrome(env2.G.CreateFrame("Frame"), "p", nil, "Title")
    assert(chrome, "no chrome")
    eq(chrome.title, "Title")
    eq(chrome.CloseButton.shown, false)
end)

--------------------------------------------------------------------
-- pH adoption (Phase B): tokens used by pH UI resolve to PHUI
--------------------------------------------------------------------
test("pH UI files only reference PHUI backdrops/colors that exist", function()
    local PHUI = freshPHUI(nil, "ph")
    for _, f in ipairs({ "UI_HUD", "UI_History", "UI_History_Detail", "UI_History_Filters", "UI_History_List" }) do
        local src = io.open("addons/ph/ph/" .. f .. ".lua"):read("*a")
        for kind, name in src:gmatch("PHUI%.(%a+)%.([%w_]+)") do
            assert(PHUI[kind] and PHUI[kind][name] ~= nil, f .. ": PHUI." .. kind .. "." .. name .. " missing")
        end
        if src:find("PHUI%.") then
            assert(src:find("local PHUI = addon%.UI%.PHUI"), f .. " uses PHUI without binding it")
        end
    end
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
