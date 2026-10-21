--[[
    UI/ScrollBar.lua - Compact, native-feeling scrollbar for Pockets'
    scrollable body views.

    Replaces UIPanelScrollFrameTemplate's default scrollbar (a wide
    dedicated column with big up/down arrow buttons - reads as a second
    toolbar next to the item grid) with a thin custom Slider: no arrow
    buttons, no surrounding button frames, no reserved layout column.

    Lives as a SIBLING of the ScrollFrame it drives (anchored to the
    ScrollFrame's own parent, not to the ScrollFrame itself), sitting in
    the panel's EXISTING right-edge padding gutter rather than carving out
    extra width - callers never narrow their content/grid width based on
    whether this is shown (that reservation was the old scrollbar's whole
    "changes column count when it appears" problem). ONE component so
    every scrollable Pockets view (Menu/Category List/Grid/All today,
    Quick Search results if it ever needs one) gets the identical visual
    treatment and behavior by construction, not by convention.

    Callers own layout (content/viewport height are already computed every
    render by Shell's own dynamic-height pass) - this component only ever
    reacts to numbers it's handed via :Update(), never re-measures anything
    itself.
]]

local _, Pockets = ...

Pockets.UI.ScrollBar = Pockets.UI.ScrollBar or {}
local ScrollBar = Pockets.UI.ScrollBar
local PHUI = Pockets.UI.PHUI

local TRACK_WIDTH = 4
local THUMB_WIDTH = 6
local MIN_THUMB_HEIGHT = 20 -- always reliably grabbable, however small the ratio
local WHEEL_STEP = 30 -- pixels per wheel notch, matches the old template's feel
local HIT_PAD = 4 -- extra invisible hit-area on each side of the thin thumb

local TRACK_ALPHA = 0.18
local THUMB_ALPHA = 0.55
local THUMB_ALPHA_HOVER = 0.85

local function SetThumbAlpha(bar, alpha)
    local color = PHUI.Colors.BORDER_BRONZE
    bar.slider.thumb:SetColorTexture(color[1], color[2], color[3], alpha)
end

local function HandleWheel(bar, delta)
    local minVal, maxVal = bar.slider:GetMinMaxValues()
    if maxVal <= minVal then
        return
    end
    local newValue = bar.slider:GetValue() - delta * WHEEL_STEP
    bar.slider:SetValue(math.min(math.max(newValue, minVal), maxVal))
end

-- scrollFrame: the real ScrollFrame this bar drives (plain, no Blizzard
-- scrollbar template - see Shell.lua's own scrollFrame creation). opts.gap:
-- empty space between scrollFrame's own right (clipped-content) edge and
-- the bar's LEFT edge (default 1px) - content is flush to that edge with
-- no margin of its own, so anchoring the bar's right edge with a plain
-- offset here would have let the thumb overlap a few px into the grid;
-- anchoring by "how far clear of the content edge does the bar start"
-- instead makes zero overlap true by construction for any gap >= 0.
function ScrollBar:Create(scrollFrame, opts)
    opts = opts or {}
    local gap = opts.gap or 1
    local rightOffset = gap + THUMB_WIDTH

    local bar = CreateFrame("Frame", nil, scrollFrame:GetParent())
    bar.scrollFrame = scrollFrame
    bar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", rightOffset, 0)
    bar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", rightOffset, 0)
    bar:SetWidth(THUMB_WIDTH)
    bar:Hide()
    bar.shown = false

    -- Subtle always-there track (optional per spec, kept very faint) so
    -- there's a hint of a scroll affordance even before the thumb draws
    -- attention - never the primary visible element.
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.track:SetWidth(TRACK_WIDTH)
    do
        local color = PHUI.Colors.BORDER_BRONZE
        bar.track:SetColorTexture(color[1], color[2], color[3], TRACK_ALPHA)
    end

    -- Bare Slider, no template - a template (even OptionsSliderTemplate)
    -- drags in Blizzard's bigger thumb art and/or text labels. No custom
    -- image asset either: the thumb is a plain color texture (same
    -- technique already used for List rows' own transparent normal/
    -- pushed textures elsewhere in Shell.lua).
    bar.slider = CreateFrame("Slider", nil, bar)
    bar.slider:SetOrientation("VERTICAL")
    bar.slider:SetWidth(THUMB_WIDTH)
    bar.slider:SetPoint("TOP", bar, "TOP", 0, 0)
    bar.slider:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    bar.slider:SetValueStep(1)
    bar.slider:EnableMouse(true)
    bar.slider:EnableMouseWheel(true)
    -- The visible thumb is only THUMB_WIDTH px wide - widen the actual
    -- clickable/draggable hit area well past that so it stays reliably
    -- grabbable (§ INTERACTION "must remain large enough to reliably grab").
    bar.slider:SetHitRectInsets(-HIT_PAD, -HIT_PAD, 0, 0)

    bar.slider.thumb = bar.slider:CreateTexture(nil, "ARTWORK")
    bar.slider.thumb:SetWidth(THUMB_WIDTH)
    bar.slider:SetThumbTexture(bar.slider.thumb)
    SetThumbAlpha(bar, THUMB_ALPHA)

    bar.slider:SetScript("OnEnter", function() SetThumbAlpha(bar, THUMB_ALPHA_HOVER) end)
    bar.slider:SetScript("OnLeave", function() SetThumbAlpha(bar, THUMB_ALPHA) end)
    bar.slider:SetScript("OnValueChanged", function(_, value)
        scrollFrame:SetVerticalScroll(value)
    end)
    bar.slider:SetScript("OnMouseWheel", function(_, delta) HandleWheel(bar, delta) end)

    -- Wheel-to-scroll is the primary interaction (§ INTERACTION) and must
    -- work anywhere over the scrollable body, not just while hovering the
    -- thin bar itself.
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta) HandleWheel(bar, delta) end)

    return bar
end

-- Recomputes thumb size/range/visibility and hides the bar entirely when
-- content doesn't overflow the viewport (§ VISIBILITY - never an empty
-- track/reserved column for short content). Call after content/scrollFrame
-- both have their final size for this render.
function ScrollBar:Update(bar, contentHeight, viewportHeight)
    local maxScroll = math.max(contentHeight - viewportHeight, 0)
    local needsScrollbar = maxScroll > 0.5

    bar.shown = needsScrollbar
    bar:SetShown(needsScrollbar)

    if not needsScrollbar then
        bar.slider:SetMinMaxValues(0, 0)
        bar.slider:SetValue(0)
        bar.scrollFrame:SetVerticalScroll(0)
        return
    end

    local thumbHeight = math.min(viewportHeight,
        math.max(MIN_THUMB_HEIGHT, viewportHeight * viewportHeight / contentHeight))
    bar.slider.thumb:SetHeight(thumbHeight)

    bar.slider:SetMinMaxValues(0, maxScroll)
    local value = math.min(bar.scrollFrame:GetVerticalScroll(), maxScroll)
    bar.slider:SetValue(value)
    bar.scrollFrame:SetVerticalScroll(value)
end

-- Explicit reset (e.g. ClearBody switching views) - keeps the Slider's own
-- value in sync rather than letting the ScrollFrame's offset and the
-- Slider's value drift apart.
function ScrollBar:ScrollToTop(bar)
    bar.slider:SetValue(0)
    bar.scrollFrame:SetVerticalScroll(0)
end

-- Restores a previous offset after a re-render (clamped to the current
-- range; no-op when nothing scrolls).
function ScrollBar:SetScroll(bar, offset)
    local minVal, maxVal = bar.slider:GetMinMaxValues()
    if maxVal <= minVal then
        return
    end
    bar.slider:SetValue(math.min(math.max(offset, minVal), maxVal))
end

function ScrollBar:IsShown(bar)
    return bar.shown
end
