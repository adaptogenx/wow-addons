--[[
    Tests/ScrollBarTests.lua - UI/ScrollBar.lua's compact custom scrollbar
    (scrollbar redesign pass): no Blizzard template arrow buttons, correct
    show/hide purely from overflow, thumb range/value tracking, wheel
    scrolling, thumb-drag equivalent (SetValue), and reuse across
    independent ScrollFrame/parent pairs (not Full-Inventory-specific).

    Uses throwaway UIParent-child frames rather than Shell's real ones -
    Shell's own scrollFrame/scrollbar wiring is covered separately in
    ShellTests.lua (content width/column-count invariants there depend on
    Shell's actual layout constants).
]]

local _, Pockets = ...
local ScrollBar = Pockets.UI.ScrollBar

local function CreateTestScrollFrame()
    local parent = CreateFrame("Frame", nil, UIParent)
    parent:SetSize(200, 100)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent)
    scrollFrame:SetSize(200, 100)
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(200, 1)
    scrollFrame:SetScrollChild(content)
    return parent, scrollFrame, content
end

Pockets.Tests.TestRunner:Register("ScrollBar: unnamed bar/slider - no template-driven arrow buttons", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    -- Blizzard's scrollbar templates always name their arrow buttons off
    -- the parent's own name ($parentScrollUpButton etc.) - an unnamed
    -- bar/slider means nothing could have been created that way.
    local ok = bar:GetName() == nil and bar.slider:GetName() == nil
    return ok, ok and "OK" or "expected an unnamed bar/slider, not a template with arrow-button children"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: hidden when content fits the viewport", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 80, 100) -- content shorter than the viewport
    local ok = not ScrollBar:IsShown(bar) and not bar:IsShown()
    return ok, ok and "OK" or "expected the bar hidden when content does not overflow"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: shown when content overflows the viewport", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 400, 100)
    local ok = ScrollBar:IsShown(bar) and bar:IsShown()
    return ok, ok and "OK" or "expected the bar shown when content overflows"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: never resizes its own ScrollFrame (no reserved column)", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    local widthBefore, heightBefore = scrollFrame:GetWidth(), scrollFrame:GetHeight()
    ScrollBar:Update(bar, 400, 100)
    local widthAfter, heightAfter = scrollFrame:GetWidth(), scrollFrame:GetHeight()
    local ok = widthBefore == widthAfter and heightBefore == heightAfter
    return ok, ok and "OK" or "expected scrollFrame's own size to be unaffected by scrollbar visibility"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: thumb range tracks content/viewport height", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    scrollFrame:SetVerticalScroll(0)
    ScrollBar:Update(bar, 300, 100) -- maxScroll = 200
    local minVal, maxVal = bar.slider:GetMinMaxValues()
    local ok = minVal == 0 and maxVal == 200 and bar.slider:GetValue() == 0
    return ok, ok and "OK" or string.format("expected range [0,200] value 0, got [%s,%s] value %s",
        tostring(minVal), tostring(maxVal), tostring(bar.slider:GetValue()))
end)

Pockets.Tests.TestRunner:Register("ScrollBar: moving the thumb (drag equivalent) scrolls the ScrollFrame", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 300, 100)
    bar.slider:SetValue(150) -- what an in-progress drag drives via OnValueChanged
    local ok = scrollFrame:GetVerticalScroll() == 150
    return ok, ok and "OK" or string.format("expected scroll offset 150, got %s", tostring(scrollFrame:GetVerticalScroll()))
end)

Pockets.Tests.TestRunner:Register("ScrollBar: mouse wheel over the ScrollFrame moves the scroll offset", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 300, 100)
    local handler = scrollFrame:GetScript("OnMouseWheel")
    handler(scrollFrame, -1) -- one notch down
    local ok = scrollFrame:GetVerticalScroll() > 0
    return ok, ok and "OK" or "expected mouse wheel to move the scroll offset forward"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: mouse wheel is a no-op with nothing to scroll", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 80, 100) -- no overflow
    local handler = scrollFrame:GetScript("OnMouseWheel")
    handler(scrollFrame, -1)
    local ok = scrollFrame:GetVerticalScroll() == 0
    return ok, ok and "OK" or "expected mouse wheel to do nothing when content does not overflow"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: ScrollToTop resets both the ScrollFrame and the thumb", function()
    local _, scrollFrame = CreateTestScrollFrame()
    local bar = ScrollBar:Create(scrollFrame)
    ScrollBar:Update(bar, 300, 100)
    bar.slider:SetValue(150)
    ScrollBar:ScrollToTop(bar)
    local ok = scrollFrame:GetVerticalScroll() == 0 and bar.slider:GetValue() == 0
    return ok, ok and "OK" or "expected ScrollToTop to zero both the scroll offset and the thumb value"
end)

Pockets.Tests.TestRunner:Register("ScrollBar: reusable across independent ScrollFrame/parent pairs", function()
    local _, scrollFrameA = CreateTestScrollFrame()
    local _, scrollFrameB = CreateTestScrollFrame()
    local barA = ScrollBar:Create(scrollFrameA)
    local barB = ScrollBar:Create(scrollFrameB)
    ScrollBar:Update(barA, 400, 100)
    ScrollBar:Update(barB, 50, 100)
    local ok = ScrollBar:IsShown(barA) and not ScrollBar:IsShown(barB) and barA ~= barB
    return ok, ok and "OK" or "expected two independently created bars to track their own ScrollFrame's state"
end)
