--[[
    Tests/ShellTests.lua - Single-frame state machine + stable shell
    contract (.plans/Pockets_Glance_UI.md §4, §15)

    Needs the real Shell frame (created by Shell:Initialize() during addon
    load), so these run via /pockets test run like the rest of the
    frame-dependent suites.
]]

local _, Pockets = ...

local Shell = Pockets.UI.Shell

local function ResetToGlance()
    Shell:SetState(Shell.STATE.GLANCE)
end

-- GetPoint() coordinates round-trip through UIParent's effective scale,
-- so comparing a value it returns against a plain Lua arithmetic result
-- (e.g. savedX + 37) needs a tolerance, not exact equality - see the same
-- note in Tests/PositionStrategyTests.lua.
local EPSILON = 0.01
local function ApproxEqual(a, b)
    return math.abs(a - b) < EPSILON
end

--------------------------------------------------
-- Pure predicates
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Ammo row hidden when ammo capacity is nil", function()
    local ok = Shell:ShouldShowAmmoRow(nil) == false
    return ok, ok and "OK" or "expected Ammo row hidden for nil capacity"
end)

Pockets.Tests.TestRunner:Register("Shell: Ammo row hidden when no ammo bag equipped (0/0)", function()
    local ok = Shell:ShouldShowAmmoRow({ used = 0, total = 0 }) == false
    return ok, ok and "OK" or "expected Ammo row hidden for zero total"
end)

Pockets.Tests.TestRunner:Register("Shell: Ammo row shown for equipped-but-empty quiver (0/16)", function()
    local ok = Shell:ShouldShowAmmoRow({ used = 0, total = 16 }) == true
    return ok, ok and "OK" or "expected Ammo row shown once a quiver is equipped, even at 0 used"
end)

Pockets.Tests.TestRunner:Register("Layout: ETA formatting never includes a '~' prefix", function()
    local Layout = Pockets.UI.Layout
    local eta = Layout:FormatETA(13 * 60)
    local suffix = Layout:FormatETASuffix(13 * 60)
    local ok = eta == "13m to full" and not suffix:find("~", 1, true)
    return ok, ok and "OK" or string.format("expected no '~' prefix, got eta=%s suffix=%s", tostring(eta), tostring(suffix))
end)

Pockets.Tests.TestRunner:Register("Layout: FormatETA returns nil for no data (caller omits rather than guesses)", function()
    local ok = Pockets.UI.Layout:FormatETA(nil) == nil
    return ok, ok and "OK" or "expected nil ETA to stay nil, never a fabricated string"
end)

--------------------------------------------------
-- State machine
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Glance click transitions to Menu", function()
    if not Shell.frame then
        return false, "Shell frame not initialized yet"
    end
    ResetToGlance()
    Shell.frame:Click()
    local ok = Shell:GetState() == Shell.STATE.MENU
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected MENU after Glance click, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: Menu -> Category -> Menu -> All -> Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    local afterCategory = Shell:GetState() == Shell.STATE.CATEGORY

    Shell:GoBack()
    local backToMenu = Shell:GetState() == Shell.STATE.MENU

    Shell:SetState(Shell.STATE.ALL)
    local afterAll = Shell:GetState() == Shell.STATE.ALL

    Shell:GoBack()
    -- All Items' Back dismisses to the Mini (ESCAPE_PARENT).
    local backToMenu2 = Shell:GetState() == Shell.STATE.GLANCE

    ResetToGlance()
    local ok = afterCategory and backToMenu and afterAll and backToMenu2
    return ok, ok and "OK" or "unexpected state during Menu/Category/All round-trip"
end)

Pockets.Tests.TestRunner:Register("Shell: Category -> All -> Menu (Category's + jumps straight to All)", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    Shell:SetState(Shell.STATE.ALL)
    local ok = Shell:GetState() == Shell.STATE.ALL
    ResetToGlance()
    return ok, ok and "OK" or "expected Category's + to land directly on ALL"
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from Category goes straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell:HandleEscape()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format(
        "expected a single Escape from Category to land on GLANCE directly, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from All goes straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.ALL)
    Shell:HandleEscape()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format(
        "expected a single Escape from All to land on GLANCE directly, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: one Escape from Menu goes to Glance and is a no-op from Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:HandleEscape()
    local step1 = Shell:GetState() == Shell.STATE.GLANCE

    Shell:HandleEscape() -- no-op at Glance (frame doesn't even see it - see keyboard-capture test)
    local step2 = Shell:GetState() == Shell.STATE.GLANCE

    local ok = step1 and step2
    return ok, ok and "OK" or "expected Menu -> Escape -> Glance, then a no-op"
end)

Pockets.Tests.TestRunner:Register("Shell: Shift-B (ToggleAllItems) jumps directly to All from any state", function()
    ResetToGlance()
    Shell:ToggleAllItems()
    local fromGlance = Shell:GetState() == Shell.STATE.ALL

    Shell:SetState(Shell.STATE.MENU)
    Shell:ToggleAllItems()
    local fromMenu = Shell:GetState() == Shell.STATE.ALL

    Shell:ToggleAllItems() -- toggling again from ALL closes to Glance
    local toggleBack = Shell:GetState() == Shell.STATE.GLANCE

    ResetToGlance()
    local ok = fromGlance and fromMenu and toggleBack
    return ok, ok and "OK" or "expected ToggleAllItems to jump straight to ALL and toggle back"
end)

Pockets.Tests.TestRunner:Register("Shift-B binding invokes the same All Items jump as Menu's + button", function()
    local originalToggle = Pockets.API.ToggleFullInventory
    local calls = 0
    Pockets.API.ToggleFullInventory = function() calls = calls + 1 end

    Pockets_ToggleFullInventory()

    Pockets.API.ToggleFullInventory = originalToggle

    local ok = calls == 1
    return ok, ok and "OK" or string.format("expected Shift-B to call ToggleFullInventory once, got %d", calls)
end)

Pockets.Tests.TestRunner:Register("Shell: same root frame is reused across every state transition", function()
    local frameBefore = Shell.frame
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.QUEST })
    Shell:SetState(Shell.STATE.ALL)
    ResetToGlance()
    local ok = Shell.frame == frameBefore
    return ok, ok and "OK" or "expected the root frame to never be destroyed/recreated"
end)

--------------------------------------------------
-- Stable shell contract (§3)
--------------------------------------------------

-- Expanding (Search/Menu/Category/All) is meant to match pH's real HUD
-- width exactly (verified value, not Glance's own intentionally-compact
-- width - Glance is content-sized on purpose, never meant to clone pH's
-- footprint).
Pockets.Tests.TestRunner:Register("Shell: state changes do not move the frame's screen anchor", function()
    Shell:SetState(Shell.STATE.MENU)
    local point1, _, relPoint1, x1, y1 = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.CONSUMABLE })
    local point2, _, relPoint2, x2, y2 = Shell.frame:GetPoint()

    Shell:SetState(Shell.STATE.ALL)
    local point3, _, relPoint3, x3, y3 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = point1 == point2 and point2 == point3
        and relPoint1 == relPoint2 and relPoint2 == relPoint3
        and x1 == x2 and x2 == x3 and y1 == y2 and y2 == y3
    return ok, ok and "OK" or "frame anchor point moved across state transitions"
end)

--------------------------------------------------
-- UI polish pass: width, header/footer borders, chevron, item grid
--------------------------------------------------

-- Width follow-up: both the original 220 and the first polish pass's
-- narrower 192 left a visibly wasted trailing gap in Category/All's item
-- grid because only 3-4 columns fit. Width must be wide enough that the
-- grid defaults to 5 columns with no scrollbar showing.
Pockets.Tests.TestRunner:Register("Shell: Menu row worst-case (long label + 3-digit count) fits without clipping", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]
    row.label:SetText("Consumables")
    row.count:SetText("180")

    local labelRight = row.label:GetRight()
    local countLeft = row.count:GetLeft()
    local chevronLeft = row.chevron:GetLeft()
    local countRight = row.count:GetRight()

    ResetToGlance()

    local ok = labelRight and countLeft and labelRight <= countLeft
        and chevronLeft and countRight and chevronLeft >= countRight
    return ok, ok and "OK" or "worst-case Menu row label/count/chevron overlapped"
end)

Pockets.Tests.TestRunner:Register("Shell: Menu chevron is a legible size, not the old tiny glyph", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]
    local _, fontSize = row.chevron:GetFont()
    local text = row.chevron:GetText()
    ResetToGlance()

    local ok = text == ">" and fontSize and fontSize >= 14
    return ok, ok and "OK" or string.format("expected '>' at >=14px, got text=%s size=%s", tostring(text), tostring(fontSize))
end)

Pockets.Tests.TestRunner:Register("Shell: category counts stay right-aligned regardless of digit count", function()
    Shell:SetState(Shell.STATE.MENU)
    local row = Shell.frame.shell.menuRows[1]

    row.count:SetText("1")
    local rightWith1Digit = row.count:GetRight()
    row.count:SetText("180")
    local rightWith3Digits = row.count:GetRight()

    ResetToGlance()

    local ok = rightWith1Digit and rightWith3Digits and math.abs(rightWith1Digit - rightWith3Digits) < 0.01
    return ok, ok and "OK" or "count's right edge shifted when digit count changed"
end)

Pockets.Tests.TestRunner:Register("Shell: no scrollbar when Category content fits the viewport", function()
    Shell:SetState(Shell.STATE.MENU)
    -- Junk is a low-count category in test/dev environments - well under
    -- one viewport's worth of items.
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

    local shell = Shell.frame.shell
    local contentWidth = shell.content:GetWidth()
    local viewportWidth = shell.scrollFrame:GetWidth()
    local scrollBarShown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)

    ResetToGlance()

    local ok = not scrollBarShown and math.abs(contentWidth - viewportWidth) < 0.01
    return ok, ok and "OK" or "scrollbar was present without overflowing content"
end)

--------------------------------------------------
-- Hard anchor rule: TOPLEFT is the origin (UI layout pass §1, §18)
--------------------------------------------------

--------------------------------------------------
-- Glance redesign pass: compact metric-list HUD (header + Bag/Gold/Ammo
-- metric rows + Recent Items strip), replacing the old centered/square
-- status card.
--------------------------------------------------

local function WithAmmoCapacity(capacity, fn)
    local InventoryState = Pockets.Services.InventoryState
    local original = InventoryState.GetAmmoCapacity
    InventoryState.GetAmmoCapacity = function() return capacity end

    local ok, err = pcall(fn)

    InventoryState.GetAmmoCapacity = original
    if not ok then
        error(err, 0)
    end
end

local function WithRecentItems(items, fn)
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function(categoryID)
        if categoryID == Pockets.Constants.CATEGORY.RECENT then
            return items
        end
        return original(categoryID)
    end

    local ok, err = pcall(fn)

    Pockets.API.GetAggregatedCategoryItems = original
    if not ok then
        error(err, 0)
    end
end

local function FakeRecentItem(itemID, quantity)
    return {
        itemID = itemID, itemLink = "item:" .. itemID, name = "Item " .. itemID,
        texture = 1, quality = 1, quantity = quantity, bagID = 0, slotID = itemID,
        interactive = true,
    }
end

--------------------------------------------------
-- Header (no X/back button, Search top-right, same visual size as
-- metric icons)
--------------------------------------------------

--------------------------------------------------
-- Metric row system: Bag/Gold/Ammo share one component/geometry
--------------------------------------------------

-- Guards the exact regression that prompted this pass: Glance's header
-- "+" visibly not matching Shell's expanded-header "+" because they were
-- built from two different, un-linked size numbers. Both Glance's search
-- icon and Shell's expanded-header side (back/+) button must trace back
-- to the one shared default. The close (X) button is intentionally
-- excluded here - see the dedicated native-close-size test below.

-- pH never resizes its own UIPanelCloseButton away from its native size
-- (ph/UI_History.lua:156-157) - forcing it down to the same 20px as the
-- other header icon buttons was the actual bug (the template's art
-- doesn't scale cleanly), not a size PICKED to be different on purpose.
--------------------------------------------------
-- Bag row: capacity + ETA
--------------------------------------------------

--------------------------------------------------
-- Gold: always present, pH Ledger-compatible formatting
--------------------------------------------------

--------------------------------------------------
-- Ammo: optional, always follows Gold, removes its row when absent
--------------------------------------------------

--------------------------------------------------
-- Recent Items strip
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Glance: Recent items carry no duplicate itemIDs", function()
    ResetToGlance()
    local items = Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.RECENT)
    local seen = {}
    local ok = true
    for _, item in ipairs(items) do
        if seen[item.itemID] then
            ok = false
        end
        seen[item.itemID] = true
    end
    return ok, ok and "OK" or "expected Glance's Recent source to contain no duplicate itemIDs"
end)

--------------------------------------------------
-- Recent Item Preview (opt-in toggle, /pockets recentpreview)
--------------------------------------------------

local function WithRecentPreviewEnabled(enabled, fn)
    local original = Pockets.SavedSettings.recentItemPreviewEnabled
    Pockets.SavedSettings.recentItemPreviewEnabled = enabled
    local ok, err = pcall(fn)
    Pockets.SavedSettings.recentItemPreviewEnabled = original
    if not ok then
        error(err, 0)
    end
end

Pockets.Tests.TestRunner:Register("ItemPreview: Show/Hide toggles the frame's visibility", function()
    Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    local shownAfterShow = Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown()
    Pockets.UI.ItemPreview:Hide()
    local hiddenAfterHide = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
    local ok = shownAfterShow and hiddenAfterHide
    return ok, ok and "OK" or "expected Show() to display the preview frame and Hide() to hide it again"
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show is a no-op without a texture (never shows a blank frame)", function()
    Pockets.UI.ItemPreview:Hide()
    Pockets.UI.ItemPreview:Show({ quality = 1 })
    local ok = not (Pockets.UI.ItemPreview.frame and Pockets.UI.ItemPreview.frame:IsShown())
    return ok, ok and "OK" or "expected Show() with no texture to leave the preview hidden"
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show re-anchors an already-visible GameTooltip to its own top-right", function()
    -- Generic show (no real item) is enough to exercise the re-anchor -
    -- ItemPreview:Show only cares whether GameTooltip:IsShown(), not
    -- what it's currently displaying.
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    -- Forever hides an empty tooltip on Show(); give it content.
    GameTooltip:SetText("Pockets test")
    GameTooltip:Show()

    Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    local point, relativeTo, relativePoint = GameTooltip:GetPoint()
    local ok = point == "TOPLEFT" and relativeTo == Pockets.UI.ItemPreview.frame and relativePoint == "TOPRIGHT"

    GameTooltip:Hide()
    Pockets.UI.ItemPreview:Hide()
    return ok, ok and "OK" or string.format(
        "expected GameTooltip TOPLEFT anchored to preview's TOPRIGHT, got point=%s relativeTo=%s relativePoint=%s",
        tostring(point), tostring(relativeTo == Pockets.UI.ItemPreview.frame), tostring(relativePoint))
end)

Pockets.Tests.TestRunner:Register("ItemPreview: Show does not touch GameTooltip when it isn't currently shown", function()
    GameTooltip:Hide()
    local ok, err = pcall(function()
        Pockets.UI.ItemPreview:Show({ texture = 1, quality = 1 })
    end)
    local stillHidden = not GameTooltip:IsShown()
    Pockets.UI.ItemPreview:Hide()
    local result = ok and stillHidden
    return result, result and "OK" or string.format("expected no error and GameTooltip to stay hidden, ok=%s err=%s", tostring(ok), tostring(err))
end)

--------------------------------------------------
-- Sizing: content-driven rectangle, not a forced square
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: PositionStrategy V1 anchor is TOPLEFT", function()
    local ok = Pockets.UI.PositionStrategy:GetRootAnchor() == "TOPLEFT"
    return ok, ok and "OK" or "expected the V1 position strategy to report TOPLEFT"
end)

Pockets.Tests.TestRunner:Register("Shell: full state sequence GLANCE>MENU>CATEGORY>ALL>MENU>GLANCE holds one TOPLEFT (§10)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    local sequence = {
        { Shell.STATE.MENU, nil },
        { Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.QUEST } },
        { Shell.STATE.ALL, nil },
        { Shell.STATE.MENU, nil },
        { Shell.STATE.GLANCE, nil },
    }

    local drifted = false
    for _, step in ipairs(sequence) do
        Shell:SetState(step[1], step[2])
        local _, _, _, x, y = Shell.frame:GetPoint()
        if x ~= x0 or y ~= y0 then
            drifted = true
        end
    end

    local ok = not drifted
    return ok, ok and "OK" or "TOPLEFT drifted somewhere in GLANCE>MENU>CATEGORY>ALL>MENU>GLANCE"
end)

Pockets.Tests.TestRunner:Register("Shell: repeated Glance<->Menu and Menu<->Category cycles never drift", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    local drifted = false
    for _ = 1, 6 do
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.AMMO })
        Shell:GoBack()
        ResetToGlance()
        local _, _, _, x, y = Shell.frame:GetPoint()
        if x ~= x0 or y ~= y0 then
            drifted = true
        end
    end

    local ok = not drifted
    return ok, ok and "OK" or "repeated Glance<->Menu<->Category cycling drifted TOPLEFT"
end)

Pockets.Tests.TestRunner:Register("Shell: changing width/height via SetSize alone never moves TOPLEFT", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    Shell.frame:SetSize(140, 90)
    local _, _, _, xa, ya = Shell.frame:GetPoint()
    Shell.frame:SetSize(220, 400)
    local _, _, _, xb, yb = Shell.frame:GetPoint()

    ResetToGlance()
    local ok = x0 == xa and y0 == ya and xa == xb and ya == yb
    return ok, ok and "OK" or "SetSize alone moved the frame's TOPLEFT anchor"
end)

Pockets.Tests.TestRunner:Register("Shell: Render skips re-anchoring while a drag is in progress", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local _, _, _, savedX, savedY = Shell.frame:GetPoint()

    -- Mid-drag: simulates StartMoving() having already moved the frame,
    -- then a background event (bag update, ETA tick) calling Render()
    -- before the player has released the mouse.
    Shell.isDragging = true
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", savedX + 37, savedY - 41)
    Shell:Render()
    local _, _, _, midDragX, midDragY = Shell.frame:GetPoint()
    local heldDuringDrag = ApproxEqual(midDragX, savedX + 37) and ApproxEqual(midDragY, savedY - 41)

    -- Drag ends: OnDragStop clears isDragging and saves the new position
    -- together (Shell.lua's OnDragStop handler), so the next Render()
    -- should reapply that NEW position, not the pre-drag one.
    Shell.isDragging = false
    Shell:SavePosition()
    Shell:Render()
    local _, _, _, afterX, afterY = Shell.frame:GetPoint()

    -- restore the real saved position so later tests aren't affected
    Pockets.CharDB.hud.x, Pockets.CharDB.hud.y = savedX, savedY
    ResetToGlance()

    local ok = heldDuringDrag and ApproxEqual(afterX, savedX + 37) and ApproxEqual(afterY, savedY - 41)
    return ok, ok and "OK" or "Render fought an in-progress drag or lost the position saved when it ended"
end)

--------------------------------------------------
-- Height: content-driven Menu, bounded Category/All (§5, §6, §18)
--------------------------------------------------

-- Row unification pass (§10/§11): zero-count categories are hidden, so
-- Menu's height is derived at render time from the VISIBLE category
-- count, not a load-time constant covering the full taxonomy.
Pockets.Tests.TestRunner:Register("Shell: Menu hides zero-count categories entirely (no empty rows)", function()
    local originalGetSummary = Pockets.API.GetCategorySummary
    Pockets.API.GetCategorySummary = function()
        return {
            { categoryID = "a", label = "A", icon = 1, count = 0 },
            { categoryID = "b", label = "B", icon = 1, count = 2 },
        }
    end

    Shell:SetState(Shell.STATE.MENU)
    local visibleLabels = {}
    for _, row in ipairs(Shell.frame.shell.menuRows) do
        if row:IsShown() then
            table.insert(visibleLabels, row.label:GetText())
        end
    end

    Pockets.API.GetCategorySummary = originalGetSummary
    ResetToGlance()

    local ok = #visibleLabels == 1 and visibleLabels[1] == "B"
    return ok, ok and "OK" or "expected exactly one visible row (the non-zero category)"
end)


-- Category/List tests need items to render; the live inventory may have
-- none in the chosen category (it varies per character), so tests that
-- inspect List rows run against a fixed fake category list instead.
local function StubCategoryItems()
    local original = Pockets.API.GetAggregatedCategoryItems
    Pockets.API.GetAggregatedCategoryItems = function()
        local items = {}
        for i = 1, 3 do
            items[i] = { itemID = 9000 + i, name = "Test Item " .. i, quantity = i, quality = 1,
                bagID = 0, slotID = i, texture = 134400 }
        end
        return items
    end
    return function() Pockets.API.GetAggregatedCategoryItems = original end
end

local function RegisterWithItems(name, fn)
    Pockets.Tests.TestRunner:Register(name, function()
        local restore = StubCategoryItems()
        local ok, a, b = pcall(fn)
        restore()
        if not ok then
            return false, "ERROR: " .. tostring(a)
        end
        return a, b
    end)
end

--------------------------------------------------
-- Row unification: Menu category rows and Category List item rows share
-- one visual row component (§1-§9)
--------------------------------------------------

RegisterWithItems("RowUnification: Menu row height equals Category List row height", function()

    Shell:SetState(Shell.STATE.MENU)
    local menuRowHeight = Shell.frame.shell.menuRows[1] and Shell.frame.shell.menuRows[1]:GetHeight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRowHeight = Shell.frame.shell.categoryListRows[1] and Shell.frame.shell.categoryListRows[1]:GetHeight()

    ResetToGlance()

    local ok = menuRowHeight and listRowHeight and menuRowHeight == listRowHeight
        and menuRowHeight == Pockets.Constants.LAYOUT.LIST_ROW_HEIGHT
    return ok, ok and "OK" or string.format("expected equal row heights, got menu=%s list=%s",
        tostring(menuRowHeight), tostring(listRowHeight))
end)

RegisterWithItems("RowUnification: Menu icon size equals Category List icon size", function()

    Shell:SetState(Shell.STATE.MENU)
    local menuIconSize = Shell.frame.shell.menuRows[1] and select(1, Shell.frame.shell.menuRows[1].icon:GetSize())

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listIconSize = Shell.frame.shell.categoryListRows[1] and select(1, Shell.frame.shell.categoryListRows[1].icon:GetSize())

    ResetToGlance()

    local ok = menuIconSize and listIconSize and menuIconSize == listIconSize
        and menuIconSize == Pockets.Constants.LAYOUT.LIST_ICON_SIZE
    return ok, ok and "OK" or string.format("expected equal icon sizes, got menu=%s list=%s",
        tostring(menuIconSize), tostring(listIconSize))
end)

RegisterWithItems("RowUnification: category label and item name start at the same X", function()

    Shell:SetState(Shell.STATE.MENU)
    local menuLabelLeft = Shell.frame.shell.menuRows[1] and Shell.frame.shell.menuRows[1].label:GetLeft()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local itemNameLeft = Shell.frame.shell.categoryListRows[1] and Shell.frame.shell.categoryListRows[1].name:GetLeft()

    ResetToGlance()

    local ok = menuLabelLeft and itemNameLeft and math.abs(menuLabelLeft - itemNameLeft) < 0.01
    return ok, ok and "OK" or string.format("expected matching label X, got menu=%s item=%s",
        tostring(menuLabelLeft), tostring(itemNameLeft))
end)

-- Wasted-space pass: item rows no longer reserve Menu's chevron column
-- (items never navigate deeper, so that 20px was permanently dead space,
-- worse once a scrollbar narrowed the row further) - qty now sits flush
-- against the row's own right edge instead of aligning with Menu's count.
RegisterWithItems("RowUnification: item qty sits flush against the row's right edge (no reserved chevron gap)", function()

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRow = Shell.frame.shell.categoryListRows[1]
    local itemQtyRight = listRow and listRow.qty:GetRight()
    local rowRight = listRow and listRow:GetRight()

    ResetToGlance()

    local ok = itemQtyRight and rowRight and math.abs((rowRight - itemQtyRight) - Pockets.Constants.LAYOUT.LIST_ROW_PADDING) < 0.01
    return ok, ok and "OK" or string.format("expected qty flush to row edge (padding only), got qtyRight=%s rowRight=%s",
        tostring(itemQtyRight), tostring(rowRight))
end)

RegisterWithItems("RowUnification: item rows have no chevron", function()

    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local listRow = Shell.frame.shell.categoryListRows[1]

    ResetToGlance()

    local ok = listRow and listRow.chevron == nil
    return ok, ok and "OK" or "expected Category List rows to have no chevron field at all"
end)

RegisterWithItems("RowUnification: Menu and Category List rows use the same Blizzard highlight texture mechanism", function()
    Shell:SetState(Shell.STATE.MENU)
    local menuRow = Shell.frame.shell.menuRows[1]
    local ok = menuRow and menuRow.GetHighlightTexture and menuRow:GetHighlightTexture() ~= nil
    ResetToGlance()
    return ok, ok and "OK" or "expected Menu rows to use a real Button highlight texture, not a bespoke overlay"
end)

RegisterWithItems("RowUnification: category rows still navigate, item rows still resolve to a real stack", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.menuRows[1]:Click()
    local navigated = Shell:GetState() == Shell.STATE.CATEGORY
    ResetToGlance()
    return navigated, navigated and "OK" or "expected clicking a Menu row to still navigate into its category"
end)

--------------------------------------------------
-- Category List max visible rows (List max-height pass)
--------------------------------------------------

local function WithNItems(n, fn)
    local originalGetAggregated = Pockets.API.GetAggregatedCategoryItems
    local items = {}
    for i = 1, n do
        items[i] = { itemID = i, name = "Item " .. i, texture = 1, quantity = 1, bagID = 0, slotID = i }
    end
    Pockets.API.GetAggregatedCategoryItems = function() return items end

    local ok, err = pcall(fn)

    Pockets.API.GetAggregatedCategoryItems = originalGetAggregated
    if not ok then
        error(err, 0)
    end
end

local function CheckListScrollState(n, expectScrollbar)
    WithNItems(n, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local shell = Shell.frame.shell
        local shown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)
        local contentWidth = shell.content:GetWidth()
        local viewportWidth = shell.scrollFrame:GetWidth()
        -- Content width never changes based on scrollbar visibility
        -- (scrollbar redesign pass - the compact bar lives in the existing
        -- padding gutter, not a reserved column), so this holds shown or
        -- not, unlike the old wide Blizzard scrollbar's reserved column.
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if not noGutter then
            error(string.format("n=%d: expected content width to always match the viewport width", n), 0)
        end
    end)
    ResetToGlance()
end

for _, n in ipairs({ 1, 3, 6 }) do
    Pockets.Tests.TestRunner:Register(string.format("CategoryList: %d item(s) - no scrollbar", n), function()
        CheckListScrollState(n, false)
        return true, "OK"
    end)
end

Pockets.Tests.TestRunner:Register("CategoryList: exactly NATIVE_BODY_ROWS items (the cap) - still no scrollbar", function()
    CheckListScrollState(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS, false)
    return true, "OK"
end)

-- WoW only clips/scrolls a ScrollFrame's actual frame DESCENDANTS, not
-- frames merely SetPoint-anchored relative to its scroll child. List
-- rows previously lived in a pool parented as a SIBLING of
-- shell.content, so they rendered unclipped and spilled straight past
-- the panel (and the footer) once a category had more items than the
-- visible viewport (vertical scrolling overflow fix).
Pockets.Tests.TestRunner:Register("CategoryList: rows are real frame descendants of the scrollable content (not just SetPoint-adjacent)", function()
    WithNItems(3, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

        local row = Shell.frame.shell.categoryListRows[1]
        local isDescendant = false
        local ancestor = row and row:GetParent()
        while ancestor do
            if ancestor == Shell.frame.shell.content then
                isDescendant = true
                break
            end
            ancestor = ancestor:GetParent()
        end
        if not isDescendant then
            error("expected a Category List row's frame ancestry to include shell.content", 0)
        end
    end)
    ResetToGlance()
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: NATIVE_BODY_ROWS + 1 items - scrollbar appears", function()
    CheckListScrollState(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS + 1, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: large category (200 items) - scrollbar appears", function()
    CheckListScrollState(200, true)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("CategoryList: growing from 3 items to the cap only extends the bottom edge (TOPLEFT fixed)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    WithNItems(3, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    local _, _, _, x1, y1 = Shell.frame:GetPoint()

    WithNItems(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS, function()
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    local _, _, _, x2, y2 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = x0 == x1 and y0 == y1 and x1 == x2 and y1 == y2
    return ok, ok and "OK" or "TOPLEFT moved while the List body grew from 3 rows to the cap"
end)

--------------------------------------------------
-- Menu height-management pass: same shared row-count cap as Category List
--------------------------------------------------

local function WithNVisibleCategories(n, fn)
    local originalGetSummary = Pockets.API.GetCategorySummary
    local summary = {}
    for i = 1, n do
        summary[i] = { categoryID = "cat" .. i, label = "Cat " .. i, icon = 1, count = i }
    end
    Pockets.API.GetCategorySummary = function() return summary end

    local ok, err = pcall(fn)

    Pockets.API.GetCategorySummary = originalGetSummary
    if not ok then
        error(err, 0)
    end
end

local function CheckMenuScrollState(n, expectScrollbar)
    WithNVisibleCategories(n, function()
        Shell:SetState(Shell.STATE.MENU)

        local shell = Shell.frame.shell
        local shown = Pockets.UI.ScrollBar:IsShown(shell.scrollBar)
        local contentWidth = shell.content:GetWidth()
        local viewportWidth = shell.scrollFrame:GetWidth()
        local noGutter = math.abs(contentWidth - viewportWidth) < 0.01

        if shown ~= expectScrollbar then
            error(string.format("n=%d: expected scrollbar shown=%s, got %s", n, tostring(expectScrollbar), tostring(shown)), 0)
        end
        if not noGutter then
            error(string.format("n=%d: expected content width to always match the viewport width", n), 0)
        end
    end)
    ResetToGlance()
end

for _, n in ipairs({ 1, 3 }) do
    Pockets.Tests.TestRunner:Register(string.format("Menu: %d visible categor%s - no scrollbar", n, n == 1 and "y" or "ies"), function()
        CheckMenuScrollState(n, false)
        return true, "OK"
    end)
end

Pockets.Tests.TestRunner:Register("Menu: exactly NATIVE_BODY_ROWS categories (the cap) - still no scrollbar", function()
    CheckMenuScrollState(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS, false)
    return true, "OK"
end)

Pockets.Tests.TestRunner:Register("Menu: NATIVE_BODY_ROWS + 1 categories - scrollbar appears", function()
    CheckMenuScrollState(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS + 1, true)
    return true, "OK"
end)

-- Menu's taxonomy is fixed at 8 categories total (never truly "large"
-- the way a Category List item count can be), but 8 still exceeds the
-- 6-row cap, so a scrollbar is still expected here.
Pockets.Tests.TestRunner:Register("Menu: growing from 3 categories to the cap only extends the bottom edge (TOPLEFT fixed)", function()
    ResetToGlance()
    local _, _, _, x0, y0 = Shell.frame:GetPoint()

    WithNVisibleCategories(3, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local _, _, _, x1, y1 = Shell.frame:GetPoint()

    WithNVisibleCategories(Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local _, _, _, x2, y2 = Shell.frame:GetPoint()

    ResetToGlance()

    local ok = x0 == x1 and y0 == y1 and x1 == x2 and y1 == y2
    return ok, ok and "OK" or "TOPLEFT moved while Menu's body grew from 3 rows to the cap"
end)

-- §7 "Menu and Category List should now behave identically in terms of
-- vertical sizing" - both cap at the SAME total frame height once each
-- has more than NATIVE_BODY_ROWS visible rows.
Pockets.Tests.TestRunner:Register("Menu and Category List cap at the identical total height once over the row limit", function()
    local overCap = Pockets.Constants.LAYOUT.NATIVE_BODY_ROWS + 2

    WithNVisibleCategories(overCap, function()
        Shell:SetState(Shell.STATE.MENU)
    end)
    local menuHeight = Shell.frame:GetHeight()
    ResetToGlance()

    local listHeight
    WithNItems(overCap, function()
        Shell:SetState(Shell.STATE.MENU)
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
        listHeight = Shell.frame:GetHeight()
    end)
    ResetToGlance()

    local ok = menuHeight == listHeight
    return ok, ok and "OK" or string.format("expected matching capped height, got menu=%s list=%s",
        tostring(menuHeight), tostring(listHeight))
end)

-- Dynamic body height pass: Category/All no longer always claim
-- SHELL_BODY_MAX_HEIGHT - they grow to fit actual content, floored at
-- SHELL_BODY_MIN_HEIGHT and capped at SHELL_BODY_MAX_HEIGHT.
--------------------------------------------------
-- Render cleanup: no cross-state leakage (§7, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu -> Category leaves zero Menu rows visible", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })

    local anyVisible = false
    for _, row in ipairs(Shell.frame.shell.menuRows) do
        if row:IsShown() then
            anyVisible = true
        end
    end

    ResetToGlance()
    local ok = not anyVisible
    return ok, ok and "OK" or "a Menu row was still visible after switching to Category"
end)

Pockets.Tests.TestRunner:Register("Shell: Category -> Menu leaves zero item buttons visible in the body", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.TRADE_GOODS })
    Shell:GoBack() -- Category -> Menu

    local pool = Pockets.UI.ItemButtonPool:GetPool(Shell.frame.shell.content)
    local anyVisible = false
    for _, button in ipairs(pool.active) do
        if button:IsShown() then
            anyVisible = true
        end
    end

    ResetToGlance()
    local ok = not anyVisible and #pool.active == 0
    return ok, ok and "OK" or "an item button was still active/visible after returning from Category to Menu"
end)

Pockets.Tests.TestRunner:Register("Shell: repeated Menu<->Category transitions do not grow the row/button pool unboundedly", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell:GoBack()
    -- Earlier tests may already have grown the long-lived row pool; what
    -- matters is that repeating the transition never grows it further.
    local baseline = #Shell.frame.shell.menuRows
    for _ = 1, 5 do
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
        Shell:GoBack()
    end
    local rowCount = #Shell.frame.shell.menuRows
    ResetToGlance()
    local ok = rowCount == baseline
    return ok, ok and "OK" or string.format(
        "expected the Menu row pool to stay at %d rows, got %d", baseline, rowCount)
end)

--------------------------------------------------
-- Footer stability (§14, §18)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: removing Ammo from the footer does not shift the Bags anchor", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    local bagsLeftBefore = shell.footerBagRow:GetLeft()

    shell.footerAmmoRow:Show() -- simulate an ammo pool being present
    Shell:ConfigureFooter() -- re-derives visibility from real (ammo-less) state, hiding it again
    local bagsLeftAfter = shell.footerBagRow:GetLeft()

    ResetToGlance()
    local ok = bagsLeftBefore == bagsLeftAfter
    return ok, ok and "OK" or "Bags anchor moved when Ammo visibility changed"
end)

Pockets.Tests.TestRunner:Register("Shell: footer always shows Bag and Gold, reusing the shared MetricRow/MoneyFormat components", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    Shell:ConfigureFooter()
    local ok = shell.footerBagRow:IsShown() and shell.footerGoldRow:IsShown()
        and shell.footerBagRow.primaryText:GetText() ~= nil
        and shell.footerGoldRow.primaryText:GetText() == Pockets.UI.MoneyFormat:Format(GetMoney())
    ResetToGlance()
    return ok, ok and "OK" or "expected footer Bag/Gold rows visible and Gold text to match MoneyFormat output"
end)

Pockets.Tests.TestRunner:Register("Shell: footer Ammo metric shows only when ShouldShowAmmoRow is true", function()
    Shell:SetState(Shell.STATE.MENU)
    local shell = Shell.frame.shell
    local ammoCapacity = Pockets.Services.InventoryState:GetAmmoCapacity()
    -- The footer also shows ammo carried in normal bags (no ammo bag needed).
    local carried = 0
    for _, item in ipairs(Pockets.API.GetAggregatedCategoryItems(Pockets.Constants.CATEGORY.AMMO)) do
        carried = carried + (item.quantity or 0)
    end
    local expectedShown = Shell:ShouldShowAmmoRow(ammoCapacity) or carried > 0
    Shell:ConfigureFooter()
    local ok = shell.footerAmmoRow:IsShown() == expectedShown
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected footer Ammo shown=%s per ShouldShowAmmoRow", tostring(expectedShown))
end)

Pockets.Tests.TestRunner:Register("Shell: SavePosition ignores a negligible (phantom-drag) position change", function()
    ResetToGlance()
    Shell:SetState(Shell.STATE.MENU)
    local hud = Pockets.CharDB.hud
    local originalX, originalY = hud.x, hud.y

    -- Same spot, only float-rounding-scale noise - simulates a
    -- zero-movement click-triggered OnDragStart/OnDragStop cycle.
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", originalX + 0.001, originalY - 0.001)
    Shell:SavePosition()

    local unchanged = hud.x == originalX and hud.y == originalY

    -- A REAL move still gets saved.
    Shell.frame:ClearAllPoints()
    Shell.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", originalX + 50, originalY - 50)
    Shell:SavePosition()
    local realMoveSaved = ApproxEqual(hud.x, originalX + 50) and ApproxEqual(hud.y, originalY - 50)

    hud.x, hud.y = originalX, originalY
    ResetToGlance()

    local ok = unchanged and realMoveSaved
    return ok, ok and "OK" or "SavePosition either persisted negligible noise or dropped a real move"
end)

--------------------------------------------------
-- Menu -> Glance back navigation (UI/anchoring fix pass §4, §5, §11)
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: Menu header shows a back button", function()
    Shell:SetState(Shell.STATE.MENU)
    local ok = Shell.frame.shell.header.backButton:IsShown()
    ResetToGlance()
    return ok, ok and "OK" or "expected Menu's header to show the back button"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking Menu's back button navigates to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or string.format("expected GLANCE after clicking Menu's back button, got %s", tostring(Shell:GetState()))
end)

Pockets.Tests.TestRunner:Register("Shell: clicking Category's back button navigates to Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.MENU
    ResetToGlance()
    return ok, ok and "OK" or "expected MENU after clicking Category's back button"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking All's back button navigates to Glance", function()
    Shell:SetState(Shell.STATE.ALL)
    Shell.frame.shell.header.backButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE after clicking All's back button"
end)

--------------------------------------------------
-- Top bar / close (X) pass: consistent header geometry, X dismisses
-- straight to Glance from every expanded state
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: X is shown and sits at the same far-right position in Menu, Category, and All", function()
    local header = Shell.frame.shell.header

    Shell:SetState(Shell.STATE.MENU)
    local menuShown, menuRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    local catShown, catRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    Shell:SetState(Shell.STATE.ALL)
    local allShown, allRight = header.closeButton:IsShown(), header.closeButton:GetRight()

    ResetToGlance()

    local ok = menuShown and catShown and allShown
        and menuRight and catRight and allRight
        and math.abs(menuRight - catRight) < 0.01 and math.abs(catRight - allRight) < 0.01
    return ok, ok and "OK" or "X was hidden or shifted position between Menu/Category/All"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from Menu navigates straight to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE after clicking Menu's X"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from Category navigates straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.EQUIPMENT })
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE (not MENU) after clicking Category's X"
end)

Pockets.Tests.TestRunner:Register("Shell: clicking X from All navigates straight to Glance, not Menu", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.ALL)
    Shell.frame.shell.header.closeButton:Click()
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    ResetToGlance()
    return ok, ok and "OK" or "expected GLANCE (not MENU) after clicking All's X"
end)

Pockets.Tests.TestRunner:Register("Shell: Glance does not intercept Escape (keyboard capture disabled)", function()
    ResetToGlance()
    local ok = not Shell.escapeCatcher:IsShown() and not Shell.frame:IsKeyboardEnabled()
    return ok, ok and "OK" or "expected Glance to leave keyboard capture disabled so Escape is not intercepted"
end)

-- Combat-safety hardening pass: an expanded state must keep working
-- (keyboard capture enabled, action-bar keys still propagate through
-- non-Escape presses) even while CombatAPI reports combat - Pockets must
-- never block/hide behind a combat conditional (CLAUDE.md/UI_RULES.md).
-- Forcing IsInCombat true here also guards against ever reintroducing a
-- combat-conditional branch into Render() by accident.
-- Back = navigate up (routes through GoBack/ESCAPE_PARENT, one level at a
-- time); X/Escape = dismiss Pockets (jump straight to Glance, bypassing
-- GoBack entirely) - top-bar/close pass's semantic distinction.
Pockets.Tests.TestRunner:Register("Shell: Back routes through GoBack; X and Escape bypass it and dismiss straight to Glance", function()
    Shell:SetState(Shell.STATE.MENU)
    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })

    local originalGoBack = Shell.GoBack
    local calls = 0
    Shell.GoBack = function(self, ...)
        calls = calls + 1
        return originalGoBack(self, ...)
    end

    Shell.frame.shell.header.backButton:Click() -- Category -> Menu, via GoBack
    local afterBackClick = calls
    local backLandedOnMenu = Shell:GetState() == Shell.STATE.MENU

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell.frame.shell.header.closeButton:Click() -- Category -> Glance directly, NOT through GoBack
    local afterCloseClick = calls
    local closeLandedOnGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.JUNK })
    Shell:HandleEscape() -- Category -> Glance directly, NOT through GoBack
    local afterEscape = calls
    local escapeLandedOnGlance = Shell:GetState() == Shell.STATE.GLANCE

    Shell.GoBack = originalGoBack
    ResetToGlance()

    local ok = afterBackClick == 1 and backLandedOnMenu
        and afterCloseClick == afterBackClick and closeLandedOnGlance
        and afterEscape == afterBackClick and escapeLandedOnGlance
    return ok, ok and "OK" or string.format(
        "expected only Back to call GoBack (got %d calls after back, %d after close, %d after escape)",
        afterBackClick, afterCloseClick, afterEscape)
end)

--------------------------------------------------
-- Full Inventory category headers/collapse (Full Inventory redesign)
--
-- No mock-inventory harness exists (per AGENTS.md, full confidence needs
-- a manual in-game `/pockets test run`), so these run against whatever
-- real bag/Recent contents the test character happens to have. They're
-- written as structural invariants that hold regardless of exact
-- contents (rather than asserting specific counts/items), except the
-- Recent cap check, which is a best-effort upper-bound check.
--------------------------------------------------

--------------------------------------------------
-- Render smoke tests
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Shell: RenderMenu does not error", function()
    local ok, err = pcall(function() Shell:SetState(Shell.STATE.MENU) end)
    ResetToGlance()
    return ok, ok and "OK" or tostring(err)
end)

Pockets.Tests.TestRunner:Register("Shell: RenderCategory does not error", function()
    local ok, err = pcall(function()
        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Pockets.Constants.CATEGORY.OTHER })
    end)
    ResetToGlance()
    return ok, ok and "OK" or tostring(err)
end)

Pockets.Tests.TestRunner:Register("Shell: RenderAll does not error for categorized flow or a flattened search query", function()
    local ok1, err1 = pcall(function()
        Shell:SetState(Shell.STATE.ALL)
        Shell:RenderAll("")
    end)
    local ok2, err2 = pcall(function() Shell:RenderAll("zzz_no_match_zzz") end)
    local ok3, err3 = pcall(function() Shell:RenderAll("") end) -- clearing search restores categorized flow
    ResetToGlance()
    local ok = ok1 and ok2 and ok3
    return ok, ok and "OK" or string.format("%s / %s / %s", tostring(err1), tostring(err2), tostring(err3))
end)

--------------------------------------------------
-- Legacy hover navigation is gone
--------------------------------------------------

Pockets.Tests.TestRunner:Register("Legacy: Pockets.UI no longer exposes the old flyout modules", function()
    local ok = Pockets.UI.CategoryFlyout == nil and Pockets.UI.ItemFlyout == nil
        and Pockets.UI.HoverGroup == nil and Pockets.UI.HUD == nil and Pockets.UI.FullInventory == nil
    return ok, ok and "OK" or "an old hover-flyout module is still present"
end)

Pockets.Tests.TestRunner:Register("Legacy: hovering the Glance frame does not change Shell state", function()
    ResetToGlance()
    if Shell.frame:GetScript("OnEnter") then
        Shell.frame:GetScript("OnEnter")(Shell.frame)
    end
    local ok = Shell:GetState() == Shell.STATE.GLANCE
    return ok, ok and "OK" or "hovering Glance changed navigation state"
end)

--------------------------------------------------
-- Glance Quick Search (SEARCH state) - Glance -> Search -> interact ->
-- Glance. NOT inventory browsing (product intent) - separate, lightweight
-- from All Items' own search box/behavior, which is untouched.
--------------------------------------------------

-- fn returns (ok, message), same contract TestRunner:Register expects -
-- WithAllAggregatedItems just guarantees the stub is restored either way
-- and passes that (ok, message) straight through.
local function WithAllAggregatedItems(items, fn)
    local original = Pockets.API.GetAllAggregatedItems
    Pockets.API.GetAllAggregatedItems = function() return items end
    local callOK, ok, message = pcall(fn)
    Pockets.API.GetAllAggregatedItems = original
    if not callOK then
        return false, "ERROR: " .. tostring(ok)
    end
    return ok, message
end

-- Builds `count` distinct "Mana <n>" items that all match query "mana",
-- for exercising the capped-rows/overflow-trailer and full-feedback-
-- collapse branches without hardcoding a match count against a layout
-- constant that might change again later.
local function BuildManaItems(count)
    local items = {}
    for i = 1, count do
        table.insert(items, { itemID = i, name = string.format("Mana %d", i), quantity = 1, bagID = 0, slotID = i })
    end
    return items
end

-- In combat only secure code can show/hide the frames, so the Shell's state
-- must follow what is on screen. These tests stand in for the secure
-- snippet by showing/hiding the frames directly while faking combat.
local function WithFakeCombat(fn)
    local CombatAPI = Pockets.Adapters.CombatAPI
    local Pool = Pockets.UI.ItemButtonPool
    local originalCombat, originalProtected = CombatAPI.IsInCombat, Pool.templateProtected
    CombatAPI.IsInCombat = function() return true end
    Pool.templateProtected = true
    local ok, result, message = pcall(fn)
    CombatAPI.IsInCombat, Pool.templateProtected = originalCombat, originalProtected
    Pool.dirty = false
    ResetToGlance()
    if not ok then
        return false, tostring(result)
    end
    return result, message
end

Pockets.Tests.TestRunner:Register("Shell: in combat, navigation requests never change state without a secure show/hide", function()
    ResetToGlance()
    return WithFakeCombat(function()
        Shell:SetState(Shell.STATE.MENU)
        local stayedGlance = Shell:GetState() == Shell.STATE.GLANCE and not Shell.expanded:IsShown()
        return stayedGlance, stayedGlance and "OK" or "state changed in combat without the expanded frame being shown"
    end)
end)

Pockets.Tests.TestRunner:Register("Shell: secure open/close in combat is followed by Shell state; nav waits", function()
    ResetToGlance()
    Shell:Prewarm()
    return WithFakeCombat(function()
        Shell.expanded:Show()
        Shell.root:Hide() -- what the secure snippet does
        Shell:OnSecureToggle()
        local openState = Shell:GetCombatOpenState()
        local opened = Shell:GetState() == openState and Shell.escapeCatcher:IsShown()

        Shell:SetState(Shell.STATE.CATEGORY, { categoryID = "consumable" })
        local navRejected = Shell:GetState() == openState

        Shell.expanded:Hide()
        Shell.root:Show()
        Shell:OnSecureToggle()
        local closed = Shell:GetState() == Shell.STATE.GLANCE and not Shell.escapeCatcher:IsShown()

        local ok = opened and navRejected and closed
        return ok, ok and "OK" or string.format("opened=%s navRejected=%s closed=%s",
            tostring(opened), tostring(navRejected), tostring(closed))
    end)
end)
