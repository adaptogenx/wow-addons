--[[
    UI/RecentItemStrip.lua - Compact horizontal strip of the most
    recently acquired unique items (Glance's Recent row).

    Reuses UI/ItemButtonPool.lua for the actual item buttons - same real
    secure buttons Category List/Grid/Search use, so tooltip/click/drag/
    split/quantity all work identically here with no second interaction
    implementation (UI_RULES.md #10). Each strip gets its own dedicated
    pool key (a private child frame, not shared with Grid/List/Search's
    own pool anchors) so a strip-sized (smaller) button can never get
    recycled back into a Grid/List render still shaped like a Recent icon
    - the same reasoning already documented for categoryListPoolAnchor/
    searchPoolAnchor in UI/Shell.lua.

    Width/height are required opts and set explicitly at creation (see
    UI/MetricRow.lua's header comment for why - same anchor-resolution
    hardening applies here).
]]

local _, Pockets = ...

Pockets.UI.RecentItemStrip = Pockets.UI.RecentItemStrip or {}
local RecentItemStrip = Pockets.UI.RecentItemStrip
local PHUI = Pockets.UI.PHUI

-- opts: width (required), iconSize (required), gap (default 4),
-- moreButton (optional { tooltipText, onClick, size }): a ">>" button
-- placed in the slot right after the LAST shown icon. It takes one icon
-- slot out of the strip's capacity (never extra width), so the strip -
-- and Glance - never resize for it.
function RecentItemStrip:Create(parent, opts)
    opts = opts or {}
    local iconSize = opts.iconSize or 20
    local gap = opts.gap or 4
    local width = opts.width or iconSize

    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, iconSize)

    strip.poolAnchor = CreateFrame("Frame", nil, strip)
    strip._iconSize = iconSize
    strip._gap = gap
    strip._width = width

    -- Stock ItemButtonTemplate's NormalTexture/PushedTexture (the
    -- decorative slot-frame border) carry a FIXED absolute size baked
    -- into the Blizzard template - they do NOT shrink when the button's
    -- own frame is resized smaller via SetSize. At Category Grid's
    -- native 40px button size that oversized art just barely overhangs
    -- the visible slot; shrunk to Recent's compact iconSize it overhangs
    -- dramatically, reading as an oversized icon that bleeds past its
    -- intended padding (matches the LAYOUT/DENSITY and BAG ICON specs'
    -- "no double frame" intent, and mirrors Shell.lua's
    -- CreateCategoryListRow, which neutralizes the exact same texture
    -- for the same reason on List rows). SetColorTexture(0,0,0,0) is
    -- what actually works on this client - SetTexture(nil)/
    -- SetNormalTexture(nil) both throw. pcall'd so any further
    -- texture-API surprise here can never break a render.
    local function NeutralizeSlotChrome(button)
        pcall(function()
            local normalTexture = button.GetNormalTexture and button:GetNormalTexture()
            if normalTexture then
                normalTexture:SetColorTexture(0, 0, 0, 0)
            end
            local pushedTexture = button.GetPushedTexture and button:GetPushedTexture()
            if pushedTexture then
                pushedTexture:SetColorTexture(0, 0, 0, 0)
            end
        end)
        if button.icon then
            button.icon:ClearAllPoints()
            button.icon:SetAllPoints(button)
        end
        if button.IconBorder then
            button.IconBorder:ClearAllPoints()
            button.IconBorder:SetAllPoints(button)
        end
    end

    -- Recent Item Preview (opt-in toggle, /pockets recentpreview):
    -- HookScript, never SetScript - ItemButtonPool's own OnEnter/OnLeave
    -- (tooltip wiring) must keep firing unchanged. Wired once per pooled
    -- button (same guard pattern as ItemButtonPool.pocketsScriptsWired)
    -- since a recycled button would otherwise stack a duplicate hook
    -- every time the strip re-acquires it. previewRecord is read at hover
    -- time, not click time, so it always reflects this render's item.
    -- The handlers are also stored as plain fields (not just passed to
    -- HookScript) - GetScript() only ever returns a SetScript handler,
    -- never a HookScript one, so tests need a direct reference to invoke
    -- them without simulating a real mouse-enter event.
    local function WirePreviewHooks(button)
        if button.pocketsPreviewHooksWired then
            return
        end
        button.pocketsPreviewHooksWired = true

        function button.previewOnEnter(self)
            if Pockets.SavedSettings.recentItemPreviewEnabled and self.previewRecord then
                Pockets.UI.ItemPreview:Show(self.previewRecord)
            end
        end
        function button.previewOnLeave()
            Pockets.UI.ItemPreview:Hide()
        end

        button:HookScript("OnEnter", button.previewOnEnter)
        button:HookScript("OnLeave", button.previewOnLeave)
    end

    -- items: newest-first, unique-by-itemID records already resolved to
    -- current carried quantity (Pockets.API.GetAggregatedCategoryItems
    -- with Constants.CATEGORY.RECENT - no second bag scan here). Clamps
    -- to however many actually fit at this strip's own width rather than
    -- a hard-coded count (RECENT ITEMS + WIDTH spec) - returns the
    -- number actually shown.
    if opts.moreButton then
        local size = opts.moreButton.size or iconSize
        strip.moreButton = PHUI.CreateNativeIconButton(strip, size, PHUI.Icons.NEXT, {
            pushedTexture = PHUI.Icons.NEXT_PUSHED,
            tooltipText = opts.moreButton.tooltipText,
            onClick = opts.moreButton.onClick,
        })
        strip.moreButton:Hide()
    end

    function strip:SetItems(items)
        local pool = Pockets.UI.ItemButtonPool
        pool:ReleaseAll(self.poolAnchor)
        -- A button about to be recycled/repositioned could be the one
        -- the preview is currently showing (mouse still over it from a
        -- prior render) - clear it preemptively rather than leaving a
        -- stale icon orphaned on screen.
        Pockets.UI.ItemPreview:Hide()

        local slots = math.max(0, math.floor((self._width + self._gap) / (self._iconSize + self._gap)))
        local maxFit = self.moreButton and math.max(slots - 1, 0) or slots
        local count = math.min(#items, maxFit)

        for i = 1, count do
            local button = pool:Acquire(self.poolAnchor)
            if not button then
                return i - 1 -- pool blocked (combat); re-rendered after combat
            end
            button:SetSize(self._iconSize, self._iconSize)
            NeutralizeSlotChrome(button)
            WirePreviewHooks(button)
            button.hideCount = opts.hideCount and true or false
            pool:Configure(button, items[i])
            button.previewRecord = items[i]
            -- Tells ItemButtonPool's shared OnEnter to leave this
            -- button's tooltip anchor alone (per-button ANCHOR_RIGHT)
            -- instead of redirecting it to the HUD's top-right like
            -- every other item surface - Recent items get their own,
            -- more specific anchor via the hover preview above.
            button.isRecentItem = true
            button:ClearAllPoints()
            -- positionFor(i, shown) lets a caller space/align the icons itself
            -- (Mini mode justifies them across the HUD's width).
            local x = self.positionFor and self.positionFor(i, count) or (i - 1) * (self._iconSize + self._gap)
            button:SetPoint("LEFT", self, "LEFT", x, 0)
            button:Show()
        end

        if self.moreButton then
            -- Only meaningful with something to expand; hidden otherwise.
            self.moreButton:ClearAllPoints()
            self.moreButton:SetPoint("LEFT", self, "LEFT", count * (self._iconSize + self._gap), 0)
            self.moreButton:SetShown(count > 0)
        end

        return count
    end

    return strip
end
