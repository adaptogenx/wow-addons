-- Combat paging for the grid: pure page planner + secure pager snippets.
local Shell = Pockets.UI.Shell

local function section(categoryID, n)
    local items = {}
    for i = 1, n do items[i] = { itemID = categoryID * 1000 + i } end
    return { categoryID = categoryID, items = items }
end

local function countItems(page)
    local c = 0
    for _, e in ipairs(page.entries) do if e.kind == "item" then c = c + 1 end end
    return c
end

test("planner: everything fits on one page", function()
    local pages, cat = Shell.PlanGridPages({ section(1, 3), section(2, 2) }, 6, 400, 40, 4, 18)
    assertEquals(#pages, 1)
    assertEquals(cat[1], 1)
    assertEquals(cat[2], 1)
    assertEquals(countItems(pages[1]), 5)
end)

test("planner: spills onto more pages, headers repeat, nothing lost or past the viewport", function()
    local sections = { section(1, 20), section(2, 30), section(3, 5) }
    local viewport, size, gap, hdr = 108, 40, 4, 18
    local pages, cat = Shell.PlanGridPages(sections, 6, viewport, size, gap, hdr)
    assertTrue(#pages > 1, "expected several pages")
    local total = 0
    for i, page in ipairs(pages) do
        total = total + countItems(page)
        assertEquals(page.entries[1].kind, "header", "page " .. i .. " starts with a header")
        for _, e in ipairs(page.entries) do
            if e.kind == "item" then
                assertTrue(e.y + size <= viewport, "item inside viewport on page " .. i)
            end
        end
    end
    assertEquals(total, 55)
    assertEquals(cat[1], 1)
    assertTrue(cat[2] >= 1 and cat[3] >= cat[2], "category pages are ordered")
end)

test("planner: a header never ends a page alone", function()
    -- viewport fits exactly one header + one row
    local pages = Shell.PlanGridPages({ section(1, 6), section(2, 6) }, 6, 18 + 40, 40, 4, 18)
    for _, page in ipairs(pages) do
        assertTrue(countItems(page) > 0, "every page has items")
    end
end)

test("planner: empty input gives one empty page", function()
    local pages = Shell.PlanGridPages({}, 6, 200, 40, 4, 18)
    assertEquals(#pages, 1)
    assertEquals(#pages[1].entries, 0)
end)

test("pager snippets: goto clamps and swaps pages; combat shows page 1, leaving restores main", function()
    local pager = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local main = CreateFrame("Frame", nil, UIParent)
    local pages = {}
    pager:SetFrameRef("main", main)
    for i = 1, 3 do
        pages[i] = CreateFrame("Frame", nil, UIParent)
        pages[i]:Hide()
        pager:SetFrameRef("pg" .. i, pages[i])
    end
    pager:SetAttribute("npages", 3)
    pager:SetAttribute("curpage", 1)
    pages[1]:Show()
    -- the same body the addon installs, driven through Execute
    local gotoSrc = Shell.PAGER_GOTO_SNIPPET
    assertNotNil(gotoSrc, "snippet exposed for tests")
    pager:SetAttribute("gotopage", gotoSrc)
    pager:Execute([[ self:RunAttribute("gotopage", 2) ]])
    assertTrue(pages[2]:IsShown() and not pages[1]:IsShown(), "moved to page 2")
    pager:Execute([[ self:RunAttribute("gotopage", 99) ]])
    assertTrue(pages[3]:IsShown() and not pages[2]:IsShown(), "clamped to last page")
    pager:Execute([[ self:RunAttribute("gotopage", -5) ]])
    assertTrue(pages[1]:IsShown() and not pages[3]:IsShown(), "clamped to first page")
end)

-- Not covered here: Shell:BuildGridPages itself. The sim cannot create the Shell
-- (no PortraitFrameTemplate), so the frame wiring is only exercised in-game.

test("smooth snippet: repositions visible rows, hides the rest, clamps to the last full screen", function()
    local pager = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local content = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    pager:SetFrameRef("pg1content", content)
    -- rows at y = 0, 44, 88, 132, 176 (height 40); viewport shows 2 rows (84px)
    local kids = {}
    for i = 0, 4 do
        local k = CreateFrame("Frame", nil, content, "SecureHandlerBaseTemplate")
        k:SetAttribute("gx", 0); k:SetAttribute("gy", i * 44); k:SetAttribute("gh", 40)
        kids[i + 1] = k
        pager:SetAttribute("rowy" .. (i + 1), i * 44)
    end
    pager:SetAttribute("viewh", 84)
    pager:SetAttribute("maxidx", 4) -- total 216: from row 4 (132) the end is within 84
    pager:SetAttribute("gotopage", Shell.PAGER_GOTO_SMOOTH_SNIPPET)
    local function shown() local t = {} for i, k in ipairs(kids) do t[i] = k:IsShown() and 1 or 0 end return table.concat(t) end
    pager:Execute([[ self:RunAttribute("gotopage", 1) ]])
    assertEquals(shown(), "11000", "top")
    pager:Execute([[ self:RunAttribute("gotopage", 3) ]])
    assertEquals(shown(), "00110", "middle")
    pager:Execute([[ self:RunAttribute("gotopage", 99) ]])
    assertEquals(pager:GetAttribute("curpage"), 4, "clamped to maxidx")
    assertEquals(shown(), "00011", "bottom shows the last rows")
end)

test("wheel step snippet: up goes back, down goes forward, missing delta does nothing", function()
    local pager = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    local pages = {}
    for i = 1, 3 do
        pages[i] = CreateFrame("Frame", nil, UIParent)
        pages[i]:Hide()
        pager:SetFrameRef("pg" .. i, pages[i])
    end
    pages[1]:Show()
    pager:SetAttribute("npages", 3)
    pager:SetAttribute("curpage", 1)
    pager:SetAttribute("gotopage", Shell.PAGER_GOTO_SNIPPET)
    pager:SetAttribute("wheel", Shell.PAGER_WHEEL_STEP_SNIPPET)
    pager:Execute([[ self:RunAttribute("wheel", -1) ]])
    assertEquals(pager:GetAttribute("curpage"), 2, "down")
    pager:Execute([[ self:RunAttribute("wheel", -1) ]])
    assertEquals(pager:GetAttribute("curpage"), 3, "down again")
    pager:Execute([[ self:RunAttribute("wheel", 1) ]])
    assertEquals(pager:GetAttribute("curpage"), 2, "up")
    pager:Execute([[ self:RunAttribute("wheel") ]])
    assertEquals(pager:GetAttribute("curpage"), 2, "no delta: unchanged, no error")
end)

-- Not covered by the sim: SecureHandlerWrapScript itself (the sim does not mark
-- frames protected, so Blizzard's wrapper rejects the header). In-game, the
-- wrapped OnMouseWheel body must read the wheel value as `offset` (Blizzard's
-- SecureHandlers.lua: Wrapped_MouseWheel = "self,offset"); `delta` and `...` do not exist there.
