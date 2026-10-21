--[[
    UI/Shell.lua - the expanded panel's navigation shell:
    Mini (GLANCE) -> Menu (category list) -> Category / All Items / Loot Log.

    The idle HUD is the Mini (MiniHUD + SidecarHUD). Opening it swaps the Mini
    root for ONE expanded panel (PocketsExpandedFrame, native PortraitFrame
    chrome) at the same top-left anchor; content changes in place between
    states (Shell.STATE) rather than opening adjacent windows. Click is the
    only navigation mechanism; hover is reserved for ordinary WoW tooltips.

    Combat: item buttons are protected, so nothing is re-laid-out in combat.
    Opening/closing swap the two top-level frames through secure snippets, and
    a category page per category is pre-built out of combat (Prewarm).

    State transitions never rescan bags - every Render* function reads
    already-computed InventoryState/CapacityEstimator data.
]]

-- luacheck: globals SecureHandlerWrapScript RegisterStateDriver UISpecialFrames

local _, Pockets = ...

Pockets.UI.Shell = Pockets.UI.Shell or {}
local Shell = Pockets.UI.Shell

local Layout = Pockets.UI.Layout
local Constants = Pockets.Constants
local L = Constants.LAYOUT
local PositionStrategy = Pockets.UI.PositionStrategy
local PHUI = Pockets.UI.PHUI

Shell.STATE = {
    GLANCE = "GLANCE",
    MENU = "MENU",
    CATEGORY = "CATEGORY",
    ALL = "ALL",
    -- Loot Log: a peer view reached from Menu/Category chrome
    -- (scroll icon), not an inventory category. Back returns to wherever
    -- it was opened from (context.returnState), so it has no fixed
    -- ESCAPE_PARENT entry.
    LOOT = "LOOT",
}

-- Back (`<`) hierarchy: CATEGORY -> MENU -> GLANCE, ALL -> GLANCE. Escape
-- does NOT use this map - Escape/X
-- dismiss straight to GLANCE from any expanded state; only the Back
-- button walks it stepwise.
local ESCAPE_PARENT = {
    [Shell.STATE.CATEGORY] = Shell.STATE.MENU,
    [Shell.STATE.ALL] = Shell.STATE.GLANCE, -- only ever opened from Glance
    [Shell.STATE.MENU] = Shell.STATE.GLANCE,
}

-- Native (PortraitFrameTemplate) chrome around the expanded panel. Geometry in
-- UI px: the title bar + portrait ring take the top EXP_HEADER; the body sits
-- EXP_SIDE in from the frame sides (so the viewport stays BodyViewportWidth
-- wide: NATIVE_PANEL_WIDTH - 2 * EXP_SIDE); the footer bar sits on
-- the bottom inner border.
local EXP_HEADER = 62
local EXP_SIDE = 16
local EXP_FOOTER_SIDE = 12
local EXP_BOTTOM = 14

-- Fixed viewport height of a native panel (see NATIVE_BODY_ROWS).
local function NativeContentHeight()
    return L.NATIVE_BODY_ROWS * L.LIST_ROW_HEIGHT
end

-- Every view has the same total height: the footer's room is reserved even
-- when a view hides it, so no view changes the panel's height.
local function TotalPanelHeight()
    return EXP_HEADER + NativeContentHeight() + 2 * L.SHELL_PADDING + EXP_BOTTOM + L.SHELL_FOOTER_HEIGHT
end

-- The body viewport's width never varies (fixed panel width), so this is a
-- fixed computation rather than a live frame read.
local function BodyViewportWidth()
    return L.NATIVE_PANEL_WIDTH - 2 * EXP_SIDE
end

-- Fixed viewport in every view; only the scrollbar depends on content.
-- Returns the viewport content height and whether the content overflows.
local function ResolveViewport(contentHeight)
    local fixed = NativeContentHeight()
    return fixed, contentHeight > fixed
end

-- Thin wrapper around the shared UI/ScrollBar.lua component (scrollbar
-- redesign pass): scrollFrame's own rect NEVER changes based on whether
-- the bar is shown - it lives in the panel's existing right-edge padding
-- gutter instead of a reserved column. Callers just hand over the
-- contentHeight/usedContentHeight they already computed for
-- ApplyDimensions - the component itself decides show/hide and thumb
-- size/range from those two numbers; no caller narrows its own
-- rowWidth/usableWidth based on whether a scrollbar ends up showing
-- (that reservation was the old bulky Blizzard scrollbar's whole
-- "changes column count when it appears" problem).
local function SetScrollBarShown(shell, contentHeight, usedContentHeight)
    Pockets.UI.ScrollBar:Update(shell.scrollBar, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- Pure predicates (unit-testable without a live frame)
--------------------------------------------------

-- An Ammo row/stat is shown only when an ammo-specialized bag is actually
-- equipped (ammo.total > 0), never merely because ammo items are being
-- carried in normal bags (TDD §7).
function Shell:ShouldShowAmmoRow(ammoCapacity)
    return (ammoCapacity and ammoCapacity.total or 0) > 0
end

function Shell:GetParentState(state)
    return ESCAPE_PARENT[state]
end

--------------------------------------------------
-- Menu row widget (click-only category navigation - no hover-flyout)
--------------------------------------------------

-- Fixed conceptual columns ICON | LABEL | FLEX | COUNT | CHEVRON (§3,
-- §11) - only the LABEL/FLEX region ever moves when rowWidth changes
-- (SetWidth below), everything else is anchored from a fixed edge so a
-- 3-digit count never shifts the label and the chevron never moves.
local function CreateMenuRow(parent, rowWidth)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(L.LIST_ROW_HEIGHT)
    row:SetWidth(rowWidth)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(L.LIST_ICON_SIZE, L.LIST_ICON_SIZE)
    row.icon:SetPoint("LEFT", row, "LEFT", L.LIST_ROW_PADDING, 0)

    row.count = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.NORMAL)
    row.count:SetPoint("RIGHT", row, "RIGHT", -(L.LIST_ROW_PADDING + L.LIST_ROW_CHEVRON_WIDTH + L.LIST_ROW_GAP), 0)
    row.count:SetWidth(L.LIST_ROW_COUNT_WIDTH)
    row.count:SetJustifyH("RIGHT")

    -- An unmistakable ">" navigation affordance, not the old ambiguous
    -- small guillemet - visually subordinate to the count (muted color)
    -- but sized to actually read as "this row goes deeper" (§2). Not its
    -- own click target - the whole row's OnClick (set per-render below)
    -- is what navigates; this is a label only.
    row.chevron = row:CreateFontString(nil, "OVERLAY")
    row.chevron:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    local mutedColor = PHUI.Colors.TEXT_MUTED
    row.chevron:SetTextColor(mutedColor[1], mutedColor[2], mutedColor[3], mutedColor[4] or 1)
    row.chevron:SetText(">")
    row.chevron:SetWidth(L.LIST_ROW_CHEVRON_WIDTH)
    row.chevron:SetJustifyH("CENTER")
    row.chevron:SetPoint("RIGHT", row, "RIGHT", -L.LIST_ROW_PADDING, 0)

    row.label = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.NORMAL)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", L.LIST_ROW_GAP, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -L.LIST_ROW_GAP, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- Same full-row hover treatment Category List rows get for free from
    -- ItemButtonTemplate (row unification pass §8) - the standard
    -- Blizzard button highlight, not a bespoke PHUI overlay, so both row
    -- types share one hover mechanism instead of two different-looking
    -- ones.
    row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    return row
end

--------------------------------------------------
-- Frame construction
--------------------------------------------------

-- Compact metric-list HUD (Glance redesign pass) - NOT a centered status
-- card, NOT forced square. Structure, top to bottom: header ("pockets" +
-- Search), Bag/Gold/Ammo metric rows (Ammo optional, always last, built
-- via one shared MetricRow component), Recent Items strip. Every frame
-- below gets BOTH width and height set explicitly at creation (via the
-- component opts) - a frame anchored by a single point with only one
-- dimension known can resolve to a fully indeterminate position, which
-- is exactly what silently blanked every earlier version of this HUD.
-- The Mini's dark disc and zoned capacity ring, drawn inside the native
-- frame's portrait hole so the gauge survives the Mini -> native switch.
-- Children of the chrome (hidden with it), at frame levels between the
-- template's portrait container (399) and its border art (499).
function Shell:BuildNativeGauge(root, chrome, onPortraitClick)
    local cx, cy = L.MINI_WIDTH / 2, -L.MINI_PORTRAIT_SIZE / 2
    local discFrame = CreateFrame("Frame", nil, chrome)
    discFrame:SetFrameLevel(380)
    discFrame:SetSize(51, 51) -- the template ring's inner hole
    discFrame:SetPoint("CENTER", root, "TOPLEFT", cx, cy)
    local disc = discFrame:CreateTexture(nil, "BACKGROUND")
    disc:SetAllPoints(discFrame)
    disc:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    local bg = PHUI.Colors.BG_DARK
    disc:SetVertexColor(bg[1], bg[2], bg[3], 1)

    local ring = Pockets.UI.CapacityRing:Create(chrome, {
        diameter = L.MINI_PORTRAIT_SIZE - 2 * L.MINI_RING_INSET,
        thickness = L.MINI_RING_THICKNESS,
    })
    ring:SetPoint("CENTER", root, "TOPLEFT", cx, cy)
    -- Above the template's border art (499; hints at 515): its ring has an
    -- inner shadow that was covering most of our ring's thickness.
    ring:SetFrameLevel(520)
    ring:SetColorFn(function(fraction)
        local c = Pockets.UI.Layout:GetCapacityColor(fraction)
        return c.r, c.g, c.b
    end)
    root.gaugeRing = ring
    if root == self.root then
        self.nativeRing = ring
    end

    -- Clicking the bag runs onPortraitClick (collapse / close). Drags are
    -- forwarded so the frame can still be moved from the portrait.
    local btn = CreateFrame("Button", nil, chrome)
    btn:SetSize(L.MINI_PORTRAIT_SIZE, L.MINI_PORTRAIT_SIZE)
    btn:SetPoint("CENTER", root, "TOPLEFT", cx, cy)
    btn:SetFrameLevel(530)
    btn:RegisterForClicks("AnyUp")
    btn:SetScript("OnClick", onPortraitClick)
    root.portraitButton = btn -- so a combat-safe secure overlay can sit on it
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function()
        local handler = root:GetScript("OnDragStart")
        if handler then handler(root) end
    end)
    btn:SetScript("OnDragStop", function()
        local handler = root:GetScript("OnDragStop")
        if handler then handler(root) end
    end)
end

-- Search strip geometry (UI px from the panel's top-left): under the title
-- bar, clear of the portrait ring (ends ~60).
local NATIVE_SEARCH_LEFT = 68
local NATIVE_SEARCH_TOP = 36
local NATIVE_SEARCH_HEIGHT = 22

-- The native panel's search field: dark rounded box, magnifier icon, faint
-- "Search" hint. One look for the category list and the All Items view.
local function CreateStyledSearchBox(parent)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetHeight(NATIVE_SEARCH_HEIGHT)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontNormalSmall")
    box:SetTextColor(PHUI.Colors.TEXT_PRIMARY[1], PHUI.Colors.TEXT_PRIMARY[2], PHUI.Colors.TEXT_PRIMARY[3])
    box:SetTextInsets(22, 6, 0, 0)
    box:SetMaxLetters(40)
    PHUI.ApplyBackdrop(box, {
        backdrop = PHUI.Backdrops.ROUNDED_SMALL, -- lightly rounded, thin
        bgColor = PHUI.Colors.BADGE_BG,
        bgAlpha = 0.85,
    })
    box.icon = box:CreateTexture(nil, "OVERLAY")
    box.icon:SetSize(L.SEARCH_ICON_SIZE, L.SEARCH_ICON_SIZE)
    box.icon:SetPoint("LEFT", box, "LEFT", 5, 0)
    box.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    box.hint = PHUI.CreateLabel(box, "muted", "Search", PHUI.Fonts.SMALL)
    box.hint:SetPoint("LEFT", box, "LEFT", 22, 0)
    function box:RefreshHint()
        self.hint:SetShown(self:GetText() == "")
    end
    return box
end

-- The title bar's action buttons: [Loot Log] [+ All Items] just left of the
-- template's X. ONE builder for the opened frame and the expanded panel, so
-- the buttons are the same elements at the same spot in every view.
local function CreateTitleActions(chrome)
    local plus = PHUI.CreateNativeIconButton(chrome, 20, PHUI.Icons.PLUS, {
        tooltipText = "All Items",
        onClick = function() Shell:SetState(Shell.STATE.ALL) end,
    })
    plus:SetFrameLevel(530)
    plus:SetPoint("RIGHT", chrome.CloseButton, "LEFT", -6, 0)
    local log = PHUI.CreateIconButton(chrome, 20, PHUI.Icons.SCROLL, {
        tooltipText = "Loot Log",
        onClick = function() Shell:OpenLootLog() end,
    })
    log:SetFrameLevel(530)
    log:SetPoint("RIGHT", plus, "LEFT", -4, 0)
    return plus, log
end

-- Back arrow on the title bar, ~6px right of the ring. One builder for the
-- opened frame (where it collapses back to the Mini, like a close) and the
-- expanded panels (where it goes up a level).
local function CreateBackButton(parent, frame, onClick)
    local button = PHUI.CreateIconButton(parent, 22, nil, { tooltipText = "Back", onClick = onClick })
    button:SetFrameLevel(530)
    button:SetSize(22, 22)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 66, -8)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(24, 24)
    arrow:SetPoint("CENTER", button, "CENTER", 0, 0)
    arrow:SetTexture(PHUI.Icons.PREV)
    button.arrow = arrow
    return button
end

-- Keeps the native frame's ring in step with the main-bag capacity.
function Shell:RenderNativeRing()
    local capacity = Pockets.Services.InventoryState:GetGeneralCapacity()
    local fraction = Pockets.UI.MiniHUD.GetFraction(capacity)
    for _, frame in ipairs({ self.root, self.expanded }) do
        if frame and frame.gaugeRing then
            frame.gaugeRing:SetFraction(fraction)
        end
    end
end

-- The idle HUD: the round Mini with its gold/ammo pills and Recent strip.
-- Clicking it (or a toggle key) opens the expanded panel.
function Shell:BuildMini()
    local frame = self.root
    frame:SetBackdrop(nil)
    frame:SetSize(L.MINI_WIDTH, L.MINI_HEIGHT)

    self.mini = Pockets.UI.MiniHUD:Build(frame)

    -- Sidecar HUD pieces (children of the root; the root keeps the Mini
    -- footprint so the Mini never moves). Dragging a badge or strip icon
    -- moves the HUD through the root's own drag handlers.
    local function forward(name)
        return function()
            local handler = frame:GetScript(name)
            if handler then
                handler(frame)
            end
        end
    end
    self.sidecar = Pockets.UI.SidecarHUD:Build(frame, {
        openRecent = function()
            Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Constants.CATEGORY.RECENT })
        end,
        openAmmo = function()
            Shell:SetState(Shell.STATE.CATEGORY, { categoryID = Constants.CATEGORY.AMMO })
        end,
        dragStart = forward("OnDragStart"),
        dragStop = forward("OnDragStop"),
    })
end

function Shell:BuildShell()
    local frame = self.expanded
    -- Native Forever window chrome (portrait/ring/title bar): the shell and
    -- everything in it draw above the template's own pieces (levels
    -- 399-515). The template is required (checked in Initialize).
    local chrome = Pockets.UI.GlanceFrame:CreateChrome(frame, Constants.HUD_ICON, nil, "", {
        size = L.MINI_ICON_SIZE,
        centerX = L.MINI_WIDTH / 2,
        centerY = -L.MINI_PORTRAIT_SIZE / 2,
    })
    frame.chrome = chrome
    frame:SetBackdrop(nil)
    self:BuildNativeGauge(frame, chrome, function() Shell:CloseAll() end)
    -- Blizzard's inset panel behind the body.
    local ok, inset = pcall(CreateFrame, "Frame", nil, chrome, "InsetFrameTemplate")
    if ok and inset then
        inset:SetFrameLevel(505)
        inset:SetPoint("TOPLEFT", frame, "TOPLEFT", EXP_SIDE - 4, -(EXP_HEADER + L.SHELL_PADDING - 4))
        inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(EXP_SIDE - 4),
            EXP_BOTTOM + L.SHELL_FOOTER_HEIGHT + 4)
        inset:EnableMouse(false)
        frame.inset = inset
    end
    local shell = CreateFrame("Frame", nil, frame)
    shell:SetFrameLevel(frame:GetFrameLevel() + 600)
    -- shell fills frame's rect exactly - frame itself is the one thing
    -- Shell:ApplyDimensions ever resizes (§3 "one logical root frame").
    shell:SetAllPoints(frame)
    frame.shell = shell
    self.frame.shell = shell
    shell.menuRows = {}
    shell.categoryListRows = {}
    shell.allListRows = {}

    -- Header: fixed [back][title][right] zones (§3 header contracts) -
    -- the control occupying a zone changes, the zone itself never moves.
    -- Anchored only to the shell's top edge (§8) - never repositioned by
    -- state changes, only its contents are reconfigured. Real PHUI
    -- backdrop+border (§1 of the polish pass) instead of a flat texture -
    -- slightly more opaque than the body so it reads as a distinct,
    -- structurally-bordered chrome band rather than a strip laid over it.
    local header = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    -- A transparent strip over the template's title bar, to the right of the
    -- portrait ring; the template's own title/X are used.
    -- The template's title bar is centred ~19px below the frame's top-left
    -- (its X button sits at the chrome's top-right, -2/+1, 24px tall, and the
    -- chrome is inset 8px), so the 26px header sits at y = 6.
    header:SetPoint("TOPLEFT", shell, "TOPLEFT", 66, -6)
    header:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -8, -6)
    header:SetHeight(L.SHELL_HEADER_HEIGHT)
    shell.header = header

    header.backButton = CreateBackButton(header, shell, function() Shell:GoBack() end)

    -- X is always fixed at the far-right edge of every expanded state
    -- (top-bar/close pass §"TOP BAR") - dismisses Pockets straight to
    -- Glance, never through the Back/Escape hierarchy. Built and anchored
    -- once here, never hidden/recreated per state, so its position can
    -- never shift between Menu/Category/All.
    header.closeButton = chrome.CloseButton -- the template's own X
    header.closeButton:SetScript("OnClick", function() Shell:CloseAll() end)

    -- Contextual action (+ / search) sits immediately LEFT of the
    -- always-present X, never in the far-right slot itself.
    header.plusButton, header.lootButton = CreateTitleActions(chrome)

    -- The search strip under the title bar, right of the portrait ring.
    header.searchBox = CreateStyledSearchBox(header)
    header.searchBox:SetPoint("TOPLEFT", shell, "TOPLEFT", NATIVE_SEARCH_LEFT, -NATIVE_SEARCH_TOP)
    header.searchBox:SetPoint("TOPRIGHT", shell, "TOPRIGHT", -EXP_SIDE, -NATIVE_SEARCH_TOP)
    header.searchBox:SetScript("OnTextChanged", function(box)
        if box.RefreshHint then
            box:RefreshHint()
        end
        if Shell.state == Shell.STATE.MENU then
            -- Typing on the category list searches all items.
            if box:GetText() ~= "" and not Shell:IsCombatBlocked() then
                Shell:SetState(Shell.STATE.ALL)
            end
            return
        end
        Shell:RenderAll(box:GetText())
    end)
    -- This editbox must resolve Escape itself (clear focus, then dismiss)
    -- rather than leaving it to the raw keydown bubbling up.
    header.searchBox:SetScript("OnEscapePressed", function(box)
        box:ClearFocus()
        Shell:HandleEscape()
    end)
    header.searchBox:Hide()

    -- Footer: anchored only to the shell's bottom edge (§8) - never moves
    -- when the body resizes above it. Same real PHUI backdrop+border
    -- treatment as the header (§1) - header/body/footer read as one
    -- connected panel since their left/right/shared edges are coincident
    -- with the root frame's own border, not offset from it.
    shell.footer = CreateFrame("Frame", nil, shell, "BackdropTemplate")
    shell.footer:SetPoint("BOTTOMLEFT", shell, "BOTTOMLEFT", EXP_FOOTER_SIDE, EXP_BOTTOM)
    shell.footer:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -EXP_FOOTER_SIDE, EXP_BOTTOM)
    shell.footer:SetHeight(L.SHELL_FOOTER_HEIGHT)
    PHUI.ApplyBackdrop(shell.footer, { bgAlpha = L.EXPANDED_CHROME_ALPHA })

    -- Footer metrics (Full Inventory redesign): reuse the SAME MetricRow/
    -- MoneyFormat components Glance's Bag/Gold/Ammo rows already use,
    -- rather than duplicated FontString formatting - icon/gap/font sizes
    -- are the same verified pH-sized defaults (GLANCE_METRIC_ICON_SIZE),
    -- just laid out horizontally instead of stacked. width starts at 1
    -- (unknown until text is set) - Shell:ConfigureFooter resizes each to
    -- its own measured content width every render, same pattern
    -- EnsureCategoryHeader/CategoryLabel already used.
    local function BuildFooterMetric(texture, iconOpts, primaryStyle)
        return Pockets.UI.MetricRow:Create(shell.footer, {
            width = 1,
            height = L.GLANCE_METRIC_ROW_HEIGHT,
            iconSize = L.GLANCE_METRIC_ICON_SIZE,
            gap = L.GLANCE_METRIC_ICON_TEXT_GAP,
            texture = texture,
            iconOpts = iconOpts,
            hasSecondary = false,
            primaryStyle = primaryStyle,
        })
    end

    shell.footerBagRow = BuildFooterMetric(Constants.HUD_ICON, { insetTexCoord = false }, "primary")
    shell.footerBagRow:SetPoint("LEFT", shell.footer, "LEFT", L.SHELL_PADDING, 0)

    shell.footerGoldRow = BuildFooterMetric(Constants.GOLD_ICON, { insetTexCoord = false }, "muted")

    -- Ammo is always the far-right metric, independent of Bag/Gold's
    -- measured widths (§ "Ammo disappears completely when irrelevant") -
    -- fixed to the footer's own right edge rather than chained after Gold.
    shell.footerAmmoRow = BuildFooterMetric(Constants.CATEGORY_ICON.ammo, nil, "primary")
    shell.footerAmmoRow:SetPoint("RIGHT", shell.footer, "RIGHT", -L.SHELL_PADDING, 0)
    shell.footerAmmoRow:Hide()

    -- Body: the ONE region whose height actually varies by state - it
    -- fills whatever space is left between header and footer once
    -- Shell:ApplyDimensions resizes the root frame (§8), so nothing here
    -- ever needs to be repositioned by hand per state. One scrolling
    -- viewport reused by Menu/Category/All (§3 "consistent body bounds").
    --
    -- Plain ScrollFrame, no template (scrollbar redesign pass) - Blizzard's
    -- UIPanelScrollFrameTemplate drags in a wide dedicated scrollbar column
    -- with big up/down arrow buttons, which read as a second toolbar next
    -- to the item grid and forced every RenderX function to narrow its own
    -- content width whenever a scrollbar appeared (reflowing the grid).
    -- The scrollFrame's own rect is now fixed - always inset by exactly
    -- SHELL_PADDING, regardless of whether a scrollbar is showing - and
    -- UI/ScrollBar.lua's compact custom Slider lives in that same existing
    -- padding gutter as a sibling, never reserving extra width itself.
    -- Plain wrapper: in combat a ScrollFrame holding protected item buttons
    -- can't be shown/hidden itself, but a parent nothing protected anchors to
    -- can - that is how combat category pages swap (see ShowCombatPage).
    shell.mainHost = CreateFrame("Frame", nil, shell, self.useSecure and "SecureHandlerBaseTemplate" or nil)
    shell.mainHost:SetAllPoints(shell)
    shell.mainHost:SetFrameLevel(shell:GetFrameLevel())
    shell.scrollFrame = CreateFrame("ScrollFrame", "PocketsShellScrollFrame", shell.mainHost)
    shell.scrollFrame:SetPoint("TOPLEFT", shell, "TOPLEFT", EXP_SIDE, -(EXP_HEADER + L.SHELL_PADDING))
    shell.scrollFrame:SetPoint("BOTTOMRIGHT", shell.footer, "TOPRIGHT", -(EXP_SIDE - EXP_FOOTER_SIDE), L.SHELL_PADDING)
    shell.scrollBar = Pockets.UI.ScrollBar:Create(shell.scrollFrame)

    shell.content = CreateFrame("Frame", nil, shell.scrollFrame)
    shell.content:SetWidth(BodyViewportWidth())
    shell.content:SetHeight(1)
    shell.scrollFrame:SetScrollChild(shell.content)

    -- A dedicated ItemButtonPool key (not `shell.content` itself, which
    -- Grid's own pool uses) - List rows are acquired ONCE and reused
    -- indefinitely (unlike Grid's per-render Acquire/ReleaseAll), and
    -- each one is resized/reparented for the row layout. Sharing Grid's
    -- pool key would let a resized List row get recycled back into Grid
    -- mode still shaped like a List row. MUST be parented under
    -- `shell.content` (not a sibling of it) - WoW only clips/scrolls a
    -- ScrollFrame's actual frame DESCENDANTS, not frames merely
    -- SetPoint-anchored relative to its scroll child. A sibling parent
    -- here previously let List rows render entirely unclipped, spilling
    -- past the panel and even the footer once a category had more items
    -- than fit the visible viewport.
    shell.categoryListPoolAnchor = CreateFrame("Frame", nil, shell.content)

    -- Loot Log rows (UI/LootLog.lua) live in the same scroll content, so
    -- they get the shared ScrollBar and clipping like every other body.
    shell.lootView = Pockets.UI.LootLog:Create(shell.content)

end

function Shell:Initialize()
    if self.frame then
        return
    end

    -- The panel is built on the client's PortraitFrameTemplate; without it
    -- there is nothing to draw, so say so instead of erroring.
    local hasTemplate, probe = pcall(CreateFrame, "Frame", nil, UIParent, "PortraitFrameTemplate")
    if not hasTemplate or not probe or not probe.PortraitContainer then
        Pockets.Debug:LogError("This client has no PortraitFrameTemplate; the Pockets HUD is disabled.")
        return
    end
    probe:Hide()

    -- Where item buttons are secure (Forever), both top-level frames are
    -- secure handlers too, so a restricted snippet can show/hide them in
    -- combat. Insecure code may still show/hide them out of combat.
    self.useSecure = Pockets.Adapters.BagAPI:UsesSecureItemAttributes() == true
    local frameTemplate = self.useSecure and "SecureHandlerBaseTemplate,BackdropTemplate" or "BackdropTemplate"
    local frame = CreateFrame("Button", "PocketsShellFrame", UIParent, frameTemplate)
    self.root = frame

    -- The expanded view (Menu/Category/All/Search/Loot) is its OWN top-level
    -- frame, not a child of the Glance root. Item buttons are protected in
    -- combat, and a frame in a protected button's anchor chain cannot be
    -- re-anchored or resized then. Keeping the expanded item buttons under a
    -- separate chain means Glance can still be touched, and the expanded
    -- frame is only ever shown/hidden in combat (never resized/re-anchored).
    local expanded = CreateFrame("Button", "PocketsExpandedFrame", UIParent, frameTemplate)
    expanded:Hide()
    self.expanded = expanded

    -- Legacy single-frame facade: `Shell.frame` forwards methods to whichever
    -- frame is currently on screen (expanded for non-Glance states) and
    -- carries the .glance/.shell fields. Use GetActiveFrame() whenever a real
    -- frame is required (anchoring, parenting).
    self.frame = setmetatable({}, {
        __index = function(_, key)
            return function(_, ...)
                local target = Shell:GetActiveFrame()
                return target[key](target, ...)
            end
        end,
    })

    for _, f in ipairs({ frame, expanded }) do
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        PHUI.ApplyBackdrop(f)

        f:SetScript("OnDragStart", function(self)
            -- StartMoving on a frame in a protected button's anchor chain
            -- is blocked in combat.
            if Pockets.UI.ItemButtonPool:IsStructurallyBlocked() then
                return
            end
            if not Pockets.CharDB.hud.locked then
                Shell.isDragging = true
                self:StartMoving()
            end
        end)
        f:SetScript("OnDragStop", function(self)
            if not Shell.isDragging then
                return
            end
            self:StopMovingOrSizing()
            Shell.isDragging = false
            Shell:SavePosition(self)
            -- Render() no-ops while isDragging is true (see Render's guard),
            -- so any state change requested by the SAME click (WoW fires
            -- OnDragStart/OnDragStop on every click, moving or not - see
            -- OnClick's note below) never got drawn. Flush it now.
            Shell:Render()
        end)
    end
    -- Growing DOWN/RIGHT from a fixed TOPLEFT must never depend on the
    -- frame's SIZE - no OnSizeChanged handler here re-anchors anything.
    -- Position is only ever written by a user drag (SavePosition) and
    -- only ever read/reapplied by Render's RestorePosition call (§1, §2,
    -- §15) - there is no other path that touches the root frame's point.

    -- Click is the only navigation mechanism (§1). Clicking Glance opens
    -- Menu; clicks inside Menu/Category/All are handled by their own
    -- child buttons/rows and never reach this handler.
    --
    -- WoW fires OnDragStart/OnDragStop on every mousedown/mouseup for any
    -- frame registered via RegisterForDrag, even a stationary click with
    -- zero movement - so this OnClick can run while StartMoving()'s
    -- cursor-follow is technically still active for the same click.
    -- SetState below would then resize the frame (Glance -> Menu) WHILE
    -- WoW's drag system is mid-commit, which corrupts the position
    -- StopMovingOrSizing() ends up saving (observed in practice: opening
    -- jumped the frame, closing jumped it again by roughly double).
    -- Render() defers itself while isDragging is true and OnDragStop
    -- flushes it once the drag has fully settled, so no resize can ever
    -- happen mid-move.
    frame:SetScript("OnClick", function()
        if Shell:IsCombatBlocked() then
            return -- the secure overlay handles combat (BuildSecureControls)
        end
        if Shell.state ~= Shell.STATE.GLANCE then
            return
        end
        Shell:SetState(Shell.STATE.MENU)
    end)

    -- Escape dismisses straight to Glance (HandleEscape), never stepping
    -- backward through the hierarchy. Done with the standard WoW mechanism
    -- - a hidden frame registered in UISpecialFrames that is only SHOWN
    -- while an expanded state is open - so Escape closes it (and does not
    -- also open the Game Menu) and Pockets never captures the keyboard.
    -- The old approach (EnableKeyboard + SetPropagateKeyboardInput) kept
    -- Enter/typing from reaching chat on WoW Forever.
    local catcher = CreateFrame("Frame", "PocketsEscapeCatcher", UIParent)
    catcher:Hide()
    catcher:SetScript("OnHide", function(self)
        if not self.suppress then
            Shell:HandleEscape()
        end
    end)
    table.insert(UISpecialFrames, "PocketsEscapeCatcher")
    Shell.escapeCatcher = catcher

    self:BuildMini()
    self:BuildShell()
    self:BuildSecureControls()
    self:RestorePosition()

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.CAPACITY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.ETA_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.INVENTORY_CHANGED, function() self:OnDataChanged() end, self)
    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.LOOT_LOGGED, function() self:RefreshLootLog() end, self)

    Pockets.Services.EventBus:Subscribe(Constants.DOMAIN_EVENT.COMBAT_STATE_CHANGED, function(payload)
        if payload and payload.inCombat == false then
            self:OnCombatEnded()
        elseif payload and payload.inCombat == true then
            self:SetSearchEnabled(false)
        end
    end, self)

    -- Learn (out of combat) whether item buttons are combat-protected.
    Pockets.UI.ItemButtonPool:Probe(UIParent)

    self.state = self.STATE.GLANCE
    self.context = {}
    self:Render()
end

-- Position and size are independent concerns (§2): this is the ONLY place
-- that ever anchors the root frame to UIParent. Every state transition
-- afterward touches SetSize only, so the anchor set here is what pins
-- Glance's TOPLEFT and every expanded state's TOPLEFT to the same point.
function Shell:RestorePosition()
    -- Re-anchoring is blocked in combat for frames in a protected button's
    -- anchor chain; the saved position only changes via a drag anyway.
    if Pockets.UI.ItemButtonPool:IsStructurallyBlocked() then
        return
    end
    local hud = Pockets.CharDB.hud
    PositionStrategy:ApplyRootPosition(self.root, hud)
    -- The Mini sits wherever the player parked it; the (much larger) panel
    -- opens at the same top-left but is shifted just enough to stay on screen.
    local x, y = PositionStrategy.ClampToScreen(hud.x or 0, hud.y or 0,
        L.NATIVE_PANEL_WIDTH, TotalPanelHeight(), UIParent:GetWidth(), UIParent:GetHeight())
    PositionStrategy:ApplyRootPosition(self.expanded, { x = x, y = y })
end

-- The frame currently on screen for the current state (Glance root, or the
-- expanded frame for every other state).
function Shell:GetActiveFrame()
    if self.state == nil or self.state == self.STATE.GLANCE then
        return self.root
    end
    return self.expanded
end

-- OnDragStart/OnDragStop fire on every click (moving or not), so this
-- runs far more often than an actual drag happens. Skip the write
-- entirely when the position hasn't meaningfully changed, so a
-- stationary click can never persist a fresh (and possibly slightly
-- different, e.g. from float rounding) value over a perfectly good one.
local NO_OP_MOVE_THRESHOLD = 0.5
function Shell:SavePosition(source)
    local hud = Pockets.CharDB.hud
    local captured = PositionStrategy:CaptureSavedPosition(source or self:GetActiveFrame())

    if math.abs(captured.x - (hud.x or 0)) < NO_OP_MOVE_THRESHOLD
        and math.abs(captured.y - (hud.y or 0)) < NO_OP_MOVE_THRESHOLD then
        return
    end

    hud.point = captured.point
    hud.relativePoint = captured.relativePoint
    hud.x = captured.x
    hud.y = captured.y
end

--------------------------------------------------
-- State machine (§4)
--------------------------------------------------

function Shell:GetState()
    return self.state
end

-- Cheap: never rescans bags, never recreates the root frame - every
-- Render* function below only reads already-computed domain state (§14).
function Shell:SetState(state, context)
    local previousState = self.state
    -- In combat nothing may be re-laid-out: hand straight to Render, which
    -- opens/closes the already laid-out view (RenderInCombat).
    if self:IsCombatBlocked() then
        self.state = state
        self.context = context or {}
        self:Render()
        return
    end
    if previousState ~= state then
        self.lootRendered = false
    end
    self.state = state
    self.context = context or {}
    self:Render()
end

function Shell:GoBack()
    if self.state == self.STATE.LOOT then
        -- Back to wherever Loot Log was opened from, with its context
        -- (e.g. the category being viewed).
        local returnState = self.context.returnState or self.STATE.GLANCE
        self:SetState(returnState, self.context.returnContext)
        return
    end
    local parent = self:GetParentState(self.state)
    if parent then
        self:SetState(parent)
    end
end

-- Escape = dismiss Pockets, not "navigate up" (top-bar/close pass
-- "Important semantic distinction"): one Escape from ANY expanded state
-- goes straight to Glance, same as clicking X, never stepping backward
-- through Category -> Menu -> Glance the way GoBack/Back does. A no-op
-- from Glance is handled upstream - keyboard capture is only enabled
-- outside GLANCE (see Render), so Pockets never even sees this key there.
-- Shown only while an expanded state is open (see Initialize). Hiding it
-- programmatically must not count as an Escape press.
function Shell:SetEscapeCatcherShown(shown)
    local catcher = self.escapeCatcher
    if not catcher then
        return
    end
    if shown then
        catcher:Show()
    else
        catcher.suppress = true
        catcher:Hide()
        catcher.suppress = false
    end
end

-- Escape (and the X / bag-portrait on an expanded panel) goes ALL the way
-- back to the Mini: out of any panel, and out of the opened frame.
function Shell:CloseAll()
    if self.state ~= self.STATE.GLANCE then
        self:SetState(self.STATE.GLANCE)
    end
end

-- True while something is open that Escape should dismiss.
function Shell:EscapeActive()
    return self.state ~= self.STATE.GLANCE
end

function Shell:HandleEscape()
    self:CloseAll()
end

function Shell:OnDataChanged()
    if self.frame then
        self:Render()
    end
end

-- Resizes the root frame only - never touches its anchor (§1/§2/§15).
-- Since the frame is TOPLEFT-anchored, growing/shrinking always extends
-- right/down from that fixed point.
function Shell:ApplyDimensions()
    self.expanded:SetSize(L.NATIVE_PANEL_WIDTH, TotalPanelHeight())
end

-- Explicit body-clear lifecycle step (§7): hides every kind of body
-- content Shell can render (Menu rows, Category/All item buttons,
-- category labels) and resets scroll/content cursor state, so a state
-- transition never leaves the previous state's widgets visible behind
-- the new one. Called before every RenderMenu/RenderCategory/RenderAll,
-- regardless of whether they were reached via SetState or (RenderAll's
-- case) a direct search-box re-render.
function Shell:ClearBody()
    local shell = self.frame.shell
    for _, row in ipairs(shell.menuRows) do
        row:Hide()
    end
    -- Category List rows are long-lived real item buttons (created once
    -- per index, reconfigured on each render from their own dedicated
    -- pool key) rather than Acquire/ReleaseAll'd per render like Grid's,
    -- so they're hidden explicitly instead of through the pool.
    for _, row in ipairs(shell.categoryListRows) do
        row:Hide()
    end
    for _, row in ipairs(shell.allListRows) do
        row:Hide()
    end
    Pockets.UI.LootLog:Hide(shell.lootView)
    Pockets.UI.ItemButtonPool:ReleaseAll(shell.content)
    Pockets.UI.ScrollBar:ScrollToTop(shell.scrollBar)
    shell.content:SetHeight(1)
end

-- Cheap and idempotent - every Render* function below only reads
-- already-computed domain state (§14), so it's always safe to just call
-- this again rather than trying to patch up a half-drawn state.
-- Combat lockdown + protected item buttons: showing/hiding/anchoring/
-- re-binding them is forbidden, so layout work cannot happen in combat
-- (M2 §11-§17). The expanded view therefore works like a bag in combat:
-- it can be opened and closed (the frame is only shown/hidden) and items
-- can be used, but it shows the LAST laid-out view (kept ready by Prewarm
-- while idle). Navigation/search/layout changes wait for combat to end.
function Shell:IsCombatBlocked()
    return Pockets.UI.ItemButtonPool:IsStructurallyBlocked()
end

-- Guard for every layout function: in combat none of them may run (they
-- hide/anchor/resize frames in the protected buttons' chains). Marks a
-- re-render for combat end and keeps counts/stale flags fresh meanwhile.
-- Returns true when the caller must stop.
function Shell:DeferIfItemsBlocked()
    if not self:IsCombatBlocked() then
        return false
    end
    local pool = Pockets.UI.ItemButtonPool
    self.renderDeferred = true
    pool:ValidateAll()
    pool:RefreshCounts()
    return true
end

-- The search strip needs a re-layout to show results, which combat forbids.
function Shell:SetSearchEnabled(enabled)
    local box = self.frame and self.frame.shell and self.frame.shell.header.searchBox
    if not box then
        return
    end
    if not enabled then
        box:ClearFocus()
    end
    if box.SetEnabled then
        box:SetEnabled(enabled)
    end
    box:SetAlpha(enabled and 1 or 0.5)
end

-- PLAYER_REGEN_ENABLED: repair secure bindings from current state, then
-- paint whatever was deferred.
function Shell:OnCombatEnded()
    self:SetSearchEnabled(true)
    self:UpdateCombatBindings()
    local pool = Pockets.UI.ItemButtonPool
    local hadDeferred = pool:Reconcile()
    if self.renderDeferred or hadDeferred then
        self.renderDeferred = false
        self:Render()
    end
end

-- Shows exactly one of root (Glance) / expanded for the current state.
-- Plain Show/Hide only - allowed in combat.
function Shell:ApplyVisibility()
    local showExpanded = self.state ~= self.STATE.GLANCE
    -- Insecure show/hide of these frames is blocked in combat; there only
    -- the secure controls (BuildSecureControls) change visibility.
    if self:IsCombatBlocked() then
        return
    end
    -- Expanded is hidden BEFORE root: its secure OnHide wrap shows root.
    if self.userHidden then
        self.expanded:Hide()
        self.root:Hide()
        return
    end
    if showExpanded then
        self.expanded:Show()
        self.root:Hide()
    else
        self.expanded:Hide()
        self.root:Show()
    end
end

-- In combat, visibility is changed only by the secure controls; state just
-- follows what is actually on screen.
function Shell:SyncStateFromVisibility()
    if self.expanded:IsShown() then
        -- What is actually laid out in the frame (the prewarmed view if it was
        -- last reset out of combat), not the last view the player navigated to.
        local shown = self.laidOutState
        if not shown or shown == self.STATE.GLANCE then
            shown = self:GetCombatOpenState()
        end
        self.state = shown
        self.context = self.laidOutContext or {}
        self.userHidden = false
        self.expandedVisible = true
    else
        self.state = self.STATE.GLANCE
        self.expandedVisible = false
    end
    self:SetEscapeCatcherShown(self:EscapeActive())
end

function Shell:RenderInCombat()
    local pool = Pockets.UI.ItemButtonPool
    self.renderDeferred = true
    pool:ValidateAll()
    pool:RefreshCounts()
    -- Plain textures/text only: safe to update in combat.
    Pockets.UI.MiniHUD:Render(self.mini)
    Pockets.UI.SidecarHUD:Render(self.sidecar, false)
    self:SyncStateFromVisibility()
end

-- Secure show/hide controls (Forever, protected item buttons). Restricted
-- snippets may show/hide protected frames in combat; insecure code may not.
--   * PocketsSecureToggle: bound to the Toggle Full Inventory key(s) while
--     in combat (state driver below).
--   * "+" on Glance (open) and X on the expanded header (close): secure
--     overlays that exist only in combat, over the normal buttons.
--   * Escape: the expanded frame is in UISpecialFrames, so Blizzard's own
--     secure code hides it.
local TOGGLE_SNIPPET = [[
    local e = self:GetFrameRef("expanded")
    local r = self:GetFrameRef("root")
    local action = self:GetAttribute("pocketsaction") or "toggle"
    local main = self:GetFrameRef("main")
    local n = self:GetAttribute("npages") or 0
    if action == "back" then
        -- Back from a combat category page returns to the category list.
        for i = 1, n do
            local h = self:GetFrameRef("page" .. i)
            if h and h:IsShown() then
                h:Hide()
                if main then main:Show() end
                return
            end
        end
        action = "close"
    end
    local open
    if action == "open" then
        open = true
    elseif action == "close" then
        open = false
    else
        open = not e:IsShown()
    end
    if open then
        e:Show()
        r:Hide()
    else
        e:Hide()
        r:Show()
        -- Next open starts at the category list again.
        for i = 1, n do
            local h = self:GetFrameRef("page" .. i)
            if h then h:Hide() end
        end
        if main then main:Show() end
    end
]]

function Shell:OnSecureToggle()
    self:SyncStateFromVisibility()
    self:Render()
end

local function MakeSecureClicker(name, parent, action)
    local b = CreateFrame("Button", name, parent, "SecureHandlerClickTemplate")
    b:SetFrameRef("expanded", Shell.expanded)
    b:SetFrameRef("root", Shell.root)
    b:SetAttribute("pocketsaction", action)
    b:SetAttribute("_onclick", TOGGLE_SNIPPET)
    b:RegisterForClicks("AnyUp")
    Shell.pageClickers = Shell.pageClickers or {}
    table.insert(Shell.pageClickers, b)
    b:HookScript("PostClick", function()
        Shell:SyncCombatPageUI()
        Shell:OnSecureToggle()
    end)
    return b
end

function Shell:BuildSecureControls()
    if not self.useSecure or not SecureHandlerWrapScript then
        return
    end

    local toggle = MakeSecureClicker("PocketsSecureToggle", UIParent, "toggle")
    toggle:SetSize(1, 1)
    self.secureToggle = toggle

    -- Whenever the expanded frame hides (X, Escape, toggle), Glance returns.
    SecureHandlerWrapScript(self.expanded, "OnHide", toggle,
        [[
            local r = owner:GetFrameRef("root")
            if r then r:Show() end
            local n = owner:GetAttribute("npages") or 0
            for i = 1, n do
                local h = owner:GetFrameRef("page" .. i)
                if h then h:Hide() end
            end
            local m = owner:GetFrameRef("main")
            if m then m:Show() end
        ]])
    self.expanded:HookScript("OnHide", function()
        if Shell:IsCombatBlocked() then
            Shell:Render()
        end
    end)
    table.insert(UISpecialFrames, "PocketsExpandedFrame")

    local function Overlay(target, action)
        if not target then
            return
        end
        local o = MakeSecureClicker(nil, target, action)
        o:SetAllPoints(target)
        o:SetFrameLevel(target:GetFrameLevel() + 10)
        o:Hide()
        RegisterStateDriver(o, "visibility", "[combat] show; hide")
    end
    -- The Mini: in combat a click opens the prewarmed panel. The overlay is a
    -- child of the root (already protected) and covers only the Mini's own
    -- footprint, so the sidecar's item buttons stay clickable and the Mini
    -- itself stays a plain frame that can be shown from Lua.
    local mini = MakeSecureClicker(nil, self.root, "open")
    mini:SetAllPoints(self.root)
    mini:SetFrameLevel(self.root:GetFrameLevel() + 50)
    mini:Hide()
    RegisterStateDriver(mini, "visibility", "[combat] show; hide")
    Overlay(self.frame.shell.header.closeButton, "close")
    -- Clicking the bag portrait also closes the expanded panel, so it needs
    -- the same combat-safe overlay as the X (the normal click is insecure).
    Overlay(self.expanded.portraitButton, "close")
    -- Back would need a re-layout to Menu; in combat it closes instead.
    Overlay(self.frame.shell.header.backButton, "back")

    -- Key binding -> secure toggle, active only in combat; out of combat
    -- the normal binding runs Pockets_ToggleFullInventory (full behavior).
    local driver = CreateFrame("Frame", "PocketsBindingDriver", UIParent, "SecureHandlerStateTemplate")
    driver:SetAttribute("_onstate-pcombat", [[
        if newstate == "combat" then
            for i = 1, 2 do
                local key = self:GetAttribute("key" .. i)
                if key then
                    self:SetBindingClick(true, key, "PocketsSecureToggle", "LeftButton")
                end
            end
        else
            self:ClearBindings()
        end
    ]])
    RegisterStateDriver(driver, "pcombat", "[combat] combat; nocombat")
    self.bindingDriver = driver
    self:UpdateCombatBindings()
end

-- Out of combat only (SetAttribute on a protected frame).
function Shell:UpdateCombatBindings()
    if not self.bindingDriver or Pockets.Adapters.CombatAPI:IsInCombat() then
        return
    end
    local key1, key2 = GetBindingKey("POCKETS_TOGGLE_FULL_INVENTORY")
    self.bindingDriver:SetAttribute("key1", key1)
    self.bindingDriver:SetAttribute("key2", key2)
end

-- The view a combat open shows: it can't be laid out then, so it is built
-- ahead of time. Opening always lands on the category list (Menu), in and
-- out of combat.
function Shell:GetCombatOpenState()
    return self.STATE.MENU
end

-- Out-of-combat only: lay out the combat-open view into the (hidden)
-- expanded frame so it is ready to be shown in combat. Cheap to skip;
-- coalesced by SchedulePrewarm.
function Shell:Prewarm()
    if self.state ~= self.STATE.GLANCE or self:IsCombatBlocked() or self.isDragging then
        return
    end
    local savedState, savedContext = self.state, self.context
    local target = self:GetCombatOpenState()
    self.state, self.context = target, {}
    local ok, err = pcall(function()
        self:RenderExpandedContent(target)
        if target == self.STATE.MENU then
            self:BuildCombatPages()
            self:SyncPageRefs()
        end
    end)
    self.state, self.context = savedState, savedContext
    if ok then
        self.laidOutState, self.laidOutContext = target, {}
    elseif Pockets.Debug then
        Pockets.Debug:LogError("Shell Prewarm failed: " .. tostring(err))
    end
end

function Shell:SchedulePrewarm()
    if self.prewarmPending or not C_Timer then
        return
    end
    self.prewarmPending = true
    C_Timer.After(0.4, function()
        self.prewarmPending = false
        if self.state == self.STATE.GLANCE then
            self:Prewarm()
        end
    end)
end

function Shell:Render()
    -- Fully deferred while a drag is in progress (§1/§2/§15): WoW's
    -- StartMoving() is live-updating the frame's screen position from the
    -- cursor for as long as isDragging is true, and ANY resize while
    -- that's active (not just a stray SetPoint) can corrupt the final
    -- position StopMovingOrSizing() commits - see OnClick's note in
    -- Initialize for how a plain click can trigger this. self.state is
    -- still updated by SetState even when deferred; OnDragStop flushes a
    -- fresh Render() once the drag has fully settled.
    if self.isDragging then
        return
    end
    -- The Escape catcher is a plain (non-protected) frame, so it follows
    -- the state even in combat - Escape keeps working.
    self:SetEscapeCatcherShown(self:EscapeActive())

    if self:IsCombatBlocked() then
        self:RenderInCombat()
        return
    end

    local state = self.state
    self.renderDeferred = false

    -- Single root position ownership (§1/§2): every state - GLANCE
    -- included - reapplies the exact same saved TOPLEFT anchor through
    -- the one PositionStrategy-backed function before anything else runs.
    -- The rest of Render only ever calls SetSize afterward, so a state
    -- transition can resize the frame but can never drift its origin.
    self:RestorePosition()
    self:ApplyVisibility()
    self.expandedVisible = state ~= self.STATE.GLANCE and not self.userHidden

    if state == self.STATE.GLANCE then
        self:SetEscapeCatcherShown(false)
        self:RenderMini()
        self:SchedulePrewarm()
        return
    end

    self:SetEscapeCatcherShown(true)
    self:RenderExpandedContent(state)
    self.displayedState, self.displayedContext = state, self.context
    self.laidOutState, self.laidOutContext = state, self.context
end

-- Lays out one expanded state into the expanded frame. Does not touch
-- visibility; used by Render and Prewarm.
function Shell:RenderExpandedContent(state)
    local frame = self.frame
    self:ResetCombatPages()
    self:ConfigureHeader()

    -- Every branch here computes its own actual content height and calls
    -- ApplyDimensions itself (dynamic height pass) - none of them just
    -- claim a fixed/maximum height regardless of what's actually shown.
    if state == self.STATE.MENU then
        self:RenderMenu()
    elseif state == self.STATE.CATEGORY then
        self:RenderCategory(self.context.categoryID)
    elseif state == self.STATE.ALL then
        self:RenderAll(frame.shell.header.searchBox:GetText())
    elseif state == self.STATE.LOOT then
        self:RenderLoot()
    end

    frame.shell.footer:Show()
    frame.shell.scrollFrame:Show()
    self:ConfigureFooter()
end

--------------------------------------------------
-- GLANCE
--------------------------------------------------

function Shell:RenderMini()
    -- The Mini always has its own fixed footprint (out of combat the root can
    -- be resized, so anything that changed it is healed here).
    self.root:SetSize(L.MINI_WIDTH, L.MINI_HEIGHT)
    self:RenderNativeRing()
    Pockets.UI.MiniHUD:Render(self.mini)
    Pockets.UI.SidecarHUD:Render(self.sidecar)
end

--------------------------------------------------
-- Header (§3 header contracts)
--------------------------------------------------

-- Reconfigures the ONE header (left/title/right zones never move, only
-- what occupies them does - §4, §6). The back button is a single
-- reused widget whose onClick (Shell:GoBack, wired once in BuildShell)
-- already resolves MENU -> GLANCE, CATEGORY -> MENU, and ALL -> MENU via
-- the same ESCAPE_PARENT map GoBack uses. X (close), by contrast, always
-- dismisses straight to Glance (Shell:SetState(GLANCE), wired once in
-- BuildShell) - Back = navigate up, X/Escape = dismiss Pockets.
function Shell:ConfigureHeader()
    local header = self.frame.shell.header
    local state = self.state

    header.backButton:Show()
    header.closeButton:Show()
    local chrome = self.expanded.chrome
    local function SetTitle(text)
        -- The template's own title; lower case to match "pockets" everywhere.
        chrome:SetTitle(text:lower())
    end

    if state == self.STATE.MENU then
        SetTitle("Pockets")
        header.plusButton:Show()
        header.lootButton:Show()
        -- The category list carries the search strip too (typing switches
        -- to All Items with the query); disabled in combat.
        if header.searchBox:GetText() ~= "" then
            header.searchBox:SetText("")
        end
        header.searchBox:Show()
    elseif state == self.STATE.CATEGORY then
        SetTitle(Constants.CATEGORY_LABEL[self.context.categoryID] or "")
        header.plusButton:Show()
        header.lootButton:Show()
        header.searchBox:Hide()
    elseif state == self.STATE.ALL then
        SetTitle("All")
        -- Search lives in its own strip, so every header keeps the same
        -- Loot Log / All buttons.
        header.plusButton:Show()
        header.lootButton:Show()
        header.searchBox:Show()
    elseif state == self.STATE.LOOT then
        -- Just [ < ] Loot Log [ X ] - nothing contextual.
        SetTitle("Loot Log")
        header.plusButton:Hide()
        header.lootButton:Hide()
        header.searchBox:Hide()
    end
end

--------------------------------------------------
-- MENU (§3 STATE 2)
--------------------------------------------------

function Shell:RenderMenu()
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    local shell = self.frame.shell
    local content = shell.content

    -- Zero-count categories are absent, not shown as empty rows (§10) -
    -- Menu's height (and thus, in practice, whether it can ever overflow
    -- at all) is entirely a function of how many categories are actually
    -- visible right now, never the fixed full taxonomy.
    local visible = {}
    for _, entry in ipairs(Pockets.API.GetCategorySummary()) do
        if entry.count > 0 then
            table.insert(visible, entry)
        end
    end

    local rowWidth = BodyViewportWidth()
    local contentHeight = #visible * L.LIST_ROW_HEIGHT
    local usedContentHeight = ResolveViewport(contentHeight)

    self:ApplyDimensions()
    content:SetWidth(rowWidth)

    local y = 0
    for index, entry in ipairs(visible) do
        local row = shell.menuRows[index]
        if not row then
            row = CreateMenuRow(content, rowWidth)
            shell.menuRows[index] = row
        end

        row.categoryID = entry.categoryID
        row.icon:SetTexture(entry.icon)
        row.label:SetText(entry.label)
        row.count:SetText(tostring(entry.count))
        row:SetWidth(rowWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:SetScript("OnClick", function()
            Shell:SetState(Shell.STATE.CATEGORY, { categoryID = entry.categoryID })
        end)
        self:WireMenuRowOverlay(row)
        row:Show()

        y = y + L.LIST_ROW_HEIGHT
    end

    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- CATEGORY (§3 STATE 3) - one navigation state, two body presentations
-- (Category List/Grid view pass). Header/footer/root/navigation/capacity
-- status stay identical between them; only the body renderer differs.
--------------------------------------------------

function Shell:RenderCategory(categoryID)
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    self:RenderCategoryList(categoryID)
end

-- List: one row per aggregate item - [icon] [full name] [total qty] -
-- same compact grammar as Menu rows (§5). The row itself IS the real
-- item button (ItemButtonPool.Configure wires it, same as Grid), just
-- resized/reparented so the whole row - not only the icon - is the
-- interaction target (§8), with name/qty labels anchored onto it.
local function CreateCategoryListRow(poolAnchor)
    local row = Pockets.UI.ItemButtonPool:Acquire(poolAnchor)
    row:SetHeight(L.LIST_ROW_HEIGHT)

    if not row.categoryListInitialized then
        row.categoryListInitialized = true

        -- The button's OWN icon/border regions default to filling the
        -- whole button (fine at Grid's fixed 40x40) - re-anchored to a
        -- small square on the left so widening the row (below) doesn't
        -- stretch the item art across the whole row.
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", L.LIST_ROW_PADDING, 0)
        row.icon:SetSize(L.LIST_ICON_SIZE, L.LIST_ICON_SIZE)
        if row.IconBorder then
            row.IconBorder:ClearAllPoints()
            row.IconBorder:SetAllPoints(row.icon)
        end
        -- ItemButtonTemplate's own slot-border art (NormalTexture) also
        -- defaults to SetAllPoints(button) - left alone, it stretches
        -- into a long repeating slot-frame graphic across the wide row.
        -- List rows use plain Menu-style rows with no button chrome, so
        -- it's just made invisible rather than reanchored to nothing
        -- useful. Both SetNormalTexture(nil) AND Texture:SetTexture(nil)
        -- throw "Usage: self:SetNormalTexture(asset)" on this client -
        -- SetColorTexture(0,0,0,0) (fully transparent, plain numeric
        -- args, no asset-path validation) is what actually works.
        -- pcall'd regardless, so any further texture-API surprise here
        -- can never crash a render/EventBus subscriber again.
        pcall(function()
            local normalTexture = row.GetNormalTexture and row:GetNormalTexture()
            if normalTexture then
                normalTexture:SetColorTexture(0, 0, 0, 0)
            end
            local pushedTexture = row.GetPushedTexture and row:GetPushedTexture()
            if pushedTexture then
                pushedTexture:SetColorTexture(0, 0, 0, 0)
            end
        end)
        -- HighlightTexture is left alone deliberately - it already
        -- covers the full (now row-width) button via SetAllPoints,
        -- giving a whole-row hover glow for free, matching Menu rows'
        -- own hover highlight.

        row.name = PHUI.CreateLabel(row, "primary", nil, PHUI.Fonts.NORMAL)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", L.LIST_ROW_GAP, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        -- Item rows never navigate deeper (§7), so - unlike Menu rows -
        -- they don't reserve a trailing chevron column: that was 20px of
        -- permanently dead space on every row, worse once a scrollbar
        -- narrows the row further (wasted-space pass). qty sits flush
        -- against the row's own right edge instead, reclaiming that
        -- width for the name column.
        row.qty = PHUI.CreateLabel(row, "muted", nil, PHUI.Fonts.NORMAL)
        row.qty:SetPoint("RIGHT", row, "RIGHT", -L.LIST_ROW_PADDING, 0)
        row.qty:SetWidth(L.LIST_ROW_COUNT_WIDTH)
        row.qty:SetJustifyH("RIGHT")

        row.name:SetPoint("RIGHT", row.qty, "LEFT", -L.LIST_ROW_GAP, 0)
    end

    return row
end

-- Fills one list row (item name in its quality colour, right-aligned qty) and
-- binds it to the item's real bag slot. Shared by the category list and the
-- native All Items list.
local function ConfigureListRow(row, item, rowWidth)
    row:SetWidth(rowWidth)
    row.name:SetText(item.name or item.itemLink or ("item:" .. tostring(item.itemID)))
    local qualityColor = item.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[item.quality]
    if qualityColor and item.quality > 1 then
        row.name:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b)
    else
        PHUI.ApplyTextStyle(row.name, "primary")
    end
    row.qty:SetText(tostring(item.quantity))

    row.hideCount = true -- stays hidden when combat's RefreshCounts reruns SetCount
    Pockets.UI.ItemButtonPool:Configure(row, item)
    -- Configure() shows the button's own built-in stack-count badge (meant
    -- for a 40x40 square button) - redundant on a wide row that already has
    -- a right-aligned qty column.
    if row.Count then
        row.Count:Hide()
    end
end

function Shell:RenderCategoryList(categoryID)
    if self:DeferIfItemsBlocked() then
        return
    end
    local shell = self.frame.shell
    local content = shell.content

    local items = Pockets.API.GetAggregatedCategoryItems(categoryID)

    -- Height-management pass: capped by row COUNT
    -- (MAX_VISIBLE_LIST_ROWS, shared with Menu), not the generic
    -- Grid/All pixel budget (SHELL_BODY_MAX_HEIGHT) - whole rows should
    -- be visible before a scrollbar appears, never however many happen
    -- to fit under an unrelated pixel cap. Fixed row height makes this
    -- pure arithmetic, no FlowLayout call needed. Width is a constant
    -- (dynamic height pass - see RenderCategoryGrid's note).
    local rowWidth = BodyViewportWidth()
    local contentHeight = #items * L.LIST_ROW_HEIGHT
    local usedContentHeight = ResolveViewport(contentHeight)

    self:ApplyDimensions()
    content:SetWidth(rowWidth)

    for index, item in ipairs(items) do
        local row = shell.categoryListRows[index]
        if not row then
            row = CreateCategoryListRow(shell.categoryListPoolAnchor)
            shell.categoryListRows[index] = row
        end

        ConfigureListRow(row, item, rowWidth)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * L.LIST_ROW_HEIGHT)
        row:Show()
    end

    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
end

--------------------------------------------------
-- COMBAT CATEGORY PAGES (Mini mode)
-- In combat nothing can be re-laid-out (item buttons are protected), so the
-- category list can't navigate by re-rendering. Instead Prewarm builds one
-- hidden scroll page per category out of combat - real item-button rows,
-- same look as the category list - and in combat a category row only
-- Show()/Hide()s plain parent frames, which combat lockdown allows.
--------------------------------------------------

function Shell:CreateCombatPage(shell)
    local page = {}
    page.host = CreateFrame("Frame", nil, shell, Shell.useSecure and "SecureHandlerBaseTemplate" or nil)
    page.host:SetAllPoints(shell)
    page.host:SetFrameLevel(shell:GetFrameLevel())
    page.scroll = CreateFrame("ScrollFrame", nil, page.host)
    for i = 1, shell.scrollFrame:GetNumPoints() do
        page.scroll:SetPoint(shell.scrollFrame:GetPoint(i))
    end
    page.content = CreateFrame("Frame", nil, page.scroll)
    page.content:SetWidth(BodyViewportWidth())
    page.content:SetHeight(1)
    page.scroll:SetScrollChild(page.content)
    page.bar = Pockets.UI.ScrollBar:Create(page.scroll) -- child of page.host
    page.host:Hide()
    return page
end

-- Out of combat only (called from Prewarm).
function Shell:BuildCombatPages()
    local shell = self.frame.shell
    shell.combatPages = shell.combatPages or {}
    local pool = Pockets.UI.ItemButtonPool
    local rowWidth = BodyViewportWidth()
    local present = {}
    for _, entry in ipairs(Pockets.API.GetCategorySummary()) do
        if entry.count > 0 then
            local categoryID = entry.categoryID
            present[categoryID] = true
            local page = shell.combatPages[categoryID]
            if not page then
                page = self:CreateCombatPage(shell)
                shell.combatPages[categoryID] = page
            end
            pool:ReleaseAll(page.content)
            local items = Pockets.API.GetAggregatedCategoryItems(categoryID)
            for index, item in ipairs(items) do
                local row = CreateCategoryListRow(page.content)
                ConfigureListRow(row, item, rowWidth)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, -(index - 1) * L.LIST_ROW_HEIGHT)
                row:Show()
            end
            local contentHeight = #items * L.LIST_ROW_HEIGHT
            local usedContentHeight = ResolveViewport(contentHeight)
            page.content:SetHeight(math.max(contentHeight, 1))
            Pockets.UI.ScrollBar:Update(page.bar, contentHeight, usedContentHeight)
        end
    end
    -- Categories that emptied out: drop their rows.
    for categoryID, page in pairs(shell.combatPages) do
        if not present[categoryID] then
            pool:ReleaseAll(page.content)
        end
    end
end

-- In combat the hosts (protected, they hold protected item buttons) can only
-- be shown/hidden by secure snippets: category rows and Back carry secure
-- overlays (see BuildSecureControls / WireMenuRowOverlay). Out of combat,
-- plain calls are fine.
function Shell:ResetCombatPages()
    local shell = self.frame and self.frame.shell
    if not shell or self:IsCombatBlocked() then
        return
    end
    for _, page in pairs(shell.combatPages or {}) do
        page.host:Hide()
    end
    shell.mainHost:Show()
end

-- Title follows whichever page (if any) the secure click left showing.
function Shell:SyncCombatPageUI()
    local shell = self.frame and self.frame.shell
    local chrome = self.expanded and self.expanded.chrome
    if not shell or not chrome or not shell.combatPages then
        return
    end
    for categoryID, page in pairs(shell.combatPages) do
        if page.host:IsShown() then
            chrome:SetTitle((Constants.CATEGORY_LABEL[categoryID] or ""):lower())
            return
        end
    end
    chrome:SetTitle("pockets")
end

-- Out of combat only: hand every secure clicker the current main host and
-- page list (its snippets reset pages on close / go Back through them).
function Shell:SyncPageRefs()
    local shell = self.frame.shell
    local hosts = {}
    for _, page in pairs(shell.combatPages or {}) do
        table.insert(hosts, page.host)
    end
    for _, clicker in ipairs(self.pageClickers or {}) do
        clicker:SetFrameRef("main", shell.mainHost)
        for i, host in ipairs(hosts) do
            clicker:SetFrameRef("page" .. i, host)
        end
        clicker:SetAttribute("npages", #hosts)
    end
    -- Menu row overlays: each opens its row's category page.
    for _, row in ipairs(shell.menuRows) do
        local overlay = row.pageOverlay
        if overlay then
            local page = row.categoryID and shell.combatPages and shell.combatPages[row.categoryID]
            overlay:SetFrameRef("main", shell.mainHost)
            if page then
                overlay:SetFrameRef("page", page.host)
            end
            overlay.hasPage = page ~= nil
        end
    end
end

local PAGE_SNIPPET = [[
    local main = self:GetFrameRef("main")
    local page = self:GetFrameRef("page")
    if main and page then
        main:Hide()
        page:Show()
    end
]]

-- A secure overlay on a Menu row (combat only): opens that category's page.
function Shell:WireMenuRowOverlay(row)
    if row.pageOverlay or not self.useSecure then
        return
    end
    local o = CreateFrame("Button", nil, row, "SecureHandlerClickTemplate")
    o:SetAllPoints(row)
    o:SetFrameLevel(row:GetFrameLevel() + 10)
    o:SetAttribute("_onclick", PAGE_SNIPPET)
    o:RegisterForClicks("AnyUp")
    o:HookScript("PostClick", function() Shell:SyncCombatPageUI() end)
    o:Hide()
    RegisterStateDriver(o, "visibility", "[combat] show; hide")
    row.pageOverlay = o
end

--------------------------------------------------
-- ALL ITEMS (§3 STATE 4) - categorized dynamic flow + search, ported
-- from the previous FullInventory window onto Shell's shared body.
--------------------------------------------------

-- Flat, name-matching aggregate list across every category (no
-- per-category grouping) - the "temporarily flatten" search mode (§11).
local function BuildFlatSearchResults(query)
    local Search = Pockets.UI.Search
    local out = {}
    local seen = {}
    for _, categoryID in ipairs(Constants.CATEGORY_ORDER) do
        for _, item in ipairs(Pockets.API.GetAggregatedCategoryItems(categoryID)) do
            if Search:Matches(item, query) and not seen[item.itemID] then
                seen[item.itemID] = true
                table.insert(out, item)
            end
        end
    end
    return out
end

-- EXPERIMENT: All Items as ONE alphabetical vertical list (case-insensitive by
-- name; a search query just filters it). Rows are the same real item buttons
-- the category list uses.
function Shell:RenderAllList(query)
    local shell = self.frame.shell
    local content = shell.content
    local rowWidth = BodyViewportWidth()
    local hasQuery = query ~= nil and query ~= ""

    local items = hasQuery and BuildFlatSearchResults(query) or Pockets.API.GetAllAggregatedItems()
    table.sort(items, function(a, b)
        local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
        if an ~= bn then
            return an < bn
        end
        return (a.itemID or 0) < (b.itemID or 0)
    end)

    for index, item in ipairs(items) do
        local row = shell.allListRows[index]
        if not row then
            row = CreateCategoryListRow(shell.categoryListPoolAnchor)
            shell.allListRows[index] = row
        end
        ConfigureListRow(row, item, rowWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * L.LIST_ROW_HEIGHT)
        row:Show()
    end

    local contentHeight = #items * L.LIST_ROW_HEIGHT
    local usedContentHeight = ResolveViewport(contentHeight)
    self:ApplyDimensions()
    content:SetWidth(rowWidth)
    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
end

function Shell:RenderAll(query)
    if self:DeferIfItemsBlocked() then
        return
    end
    self:ClearBody()
    self:RenderAllList(query)
end

--------------------------------------------------
-- Footer (shared by MENU/CATEGORY/ALL)
--------------------------------------------------

-- Measure-after-set + resize, same pattern established elsewhere
-- (EnsureCategoryHeader/the old EnsureCategoryLabel) - a MetricRow's
-- width isn't known until its text is set, and footer metrics are laid
-- out left-to-right by actual measured width, not a fixed column.
local function ResizeFooterMetric(row)
    row:SetWidth(L.GLANCE_METRIC_ICON_SIZE + L.GLANCE_METRIC_ICON_TEXT_GAP + (row.primaryText:GetStringWidth() or 0))
end

function Shell:ConfigureFooter()
    local shell = self.frame.shell
    self:ConfigureFooterRows({
        bag = shell.footerBagRow,
        gold = shell.footerGoldRow,
        ammo = shell.footerAmmoRow,
    })
end

-- Fills a footer's Bag / Gold / Ammo metric rows (the old panel's footer and
-- the native frame's share this).
function Shell:ConfigureFooterRows(rows)
    local InventoryState = Pockets.Services.InventoryState

    local capacity = InventoryState:GetGeneralCapacity()
    local color = Layout:GetCapacityColor(capacity.utilization)
    rows.bag:SetPrimary(string.format("%d/%d", capacity.used, capacity.total))
    rows.bag:SetPrimaryColor(color.r, color.g, color.b)
    ResizeFooterMetric(rows.bag)

    local money = Pockets.Adapters.MoneyAPI:GetMoney()
    rows.gold:SetTexture(Pockets.UI.MoneyFormat:CoinIcon(money))
    rows.gold:SetPrimary(Pockets.UI.MoneyFormat:Format(money))
    ResizeFooterMetric(rows.gold)
    rows.gold:ClearAllPoints()
    -- Same gap the Gold icon already keeps against ITS OWN text
    -- (GLANCE_METRIC_ICON_TEXT_GAP) - using the smaller ACTION_GAP here
    -- left the coin sitting lopsided: barely any breathing room after
    -- Bag's count, then a bigger gap before Gold's own text.
    rows.gold:SetPoint("LEFT", rows.bag, "RIGHT", L.GLANCE_METRIC_ICON_TEXT_GAP, 0)

    local ammoCapacity = InventoryState:GetAmmoCapacity()
    if self:ShouldShowAmmoRow(ammoCapacity) then
        -- An ammo bag: its slot usage.
        rows.ammo:SetPrimary(string.format("%d/%d", ammoCapacity.used, ammoCapacity.total))
        ResizeFooterMetric(rows.ammo)
        rows.ammo:Show()
    else
        -- No ammo bag, but ammo carried in normal bags (any class can): the
        -- arrow / bullet count, same as the Mini's ammo pill.
        local carried = 0
        for _, item in ipairs(Pockets.API.GetAggregatedCategoryItems(Constants.CATEGORY.AMMO)) do
            carried = carried + (item.quantity or 0)
        end
        if carried > 0 then
            rows.ammo:SetPrimary(tostring(carried))
            ResizeFooterMetric(rows.ammo)
            rows.ammo:Show()
        else
            rows.ammo:Hide()
        end
    end
end

--------------------------------------------------
-- LOOT LOG
--------------------------------------------------

-- Opens Loot Log from the current state, remembering where to return.
-- Opened from Loot Log itself is a no-op (button is hidden there anyway).
function Shell:OpenLootLog()
    if self.state == self.STATE.LOOT then
        return
    end
    self:SetState(self.STATE.LOOT, { returnState = self.state, returnContext = self.context })
end

function Shell:RenderLoot()
    if self:DeferIfItemsBlocked() then
        return
    end
    local shell = self.frame.shell
    local content = shell.content

    -- A re-render while already viewing the log (new event, item cache
    -- resolved) keeps the player's scroll position; opening starts at the
    -- top, i.e. the newest entries. At offset 0 a new entry therefore
    -- stays visible by construction.
    local keepOffset = self.lootRendered and shell.scrollFrame:GetVerticalScroll() or 0

    self:ClearBody()

    local rowWidth = BodyViewportWidth()
    local entries = Pockets.Services.LootLog:GetEntries()
    local contentHeight = Pockets.UI.LootLog:Render(shell.lootView, entries, rowWidth)
    local usedContentHeight = ResolveViewport(contentHeight)

    self:ApplyDimensions()
    content:SetWidth(rowWidth)
    content:SetHeight(math.max(contentHeight, 1))
    SetScrollBarShown(shell, contentHeight, usedContentHeight)
    if keepOffset > 0 then
        Pockets.UI.ScrollBar:SetScroll(shell.scrollBar, keepOffset)
    end
    self.lootRendered = true
end

-- Coalesces bursts (AoE loot, container opens, quest turn-ins) into one
-- re-render shortly after the last event, and does nothing at all while
-- Loot Log isn't the visible state - the log stays lightweight hidden.
local LOOT_REFRESH_DELAY = 0.1
function Shell:RefreshLootLog()
    if not self.frame or self.state ~= self.STATE.LOOT or self.lootRefreshPending then
        return
    end
    self.lootRefreshPending = true
    C_Timer.After(LOOT_REFRESH_DELAY, function()
        self.lootRefreshPending = false
        if self.state == self.STATE.LOOT then
            self:Render()
        end
    end)
end

--------------------------------------------------
-- Visibility (independent of state - /pockets show)
--------------------------------------------------

function Shell:Show()
    if self.frame and not self:IsCombatBlocked() then
        self.userHidden = false
        self:ApplyVisibility()
    end
end

function Shell:Hide()
    if self.frame and not self:IsCombatBlocked() then
        self.userHidden = true
        self:ApplyVisibility()
        self.expandedVisible = false
    end
end

function Shell:Toggle()
    if not self.frame then
        return
    end
    if self.userHidden then
        self:Show()
    else
        self:Hide()
    end
end

-- Shift-B / the old "expand" action jump directly to All Items (§4),
-- closing to Glance if All Items is already open.
function Shell:ToggleAllItems()
    -- In combat there is no re-layout to step back to Menu: toggling closes.
    if self:IsCombatBlocked() and self.state ~= self.STATE.GLANCE then
        self:SetState(self.STATE.GLANCE)
    elseif self.state == self.STATE.ALL then
        self:SetState(self.STATE.GLANCE)
    else
        self:SetState(self.STATE.ALL)
    end
end
