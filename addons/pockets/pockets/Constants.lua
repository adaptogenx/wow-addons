--[[
    Constants.lua - Shared constants for Pockets

    Centralizes capacity classes, category IDs, colors, and other values
    that must not be duplicated across modules (TDD §7, §10, §13.2).
]]

local _, Pockets = ...

Pockets.Constants = Pockets.Constants or {}
local Constants = Pockets.Constants

-- Capacity classes (TDD §7)
Constants.CAPACITY_CLASS = {
    GENERAL = "GENERAL",
    AMMO = "AMMO",
}

-- Stable category IDs (TDD §5.2)
Constants.CATEGORY = {
    RECENT = "recent",
    EQUIPMENT = "equipment",
    CONSUMABLE = "consumable",
    TRADE_GOODS = "trade_goods",
    QUEST = "quest",
    AMMO = "ammo",
    JUNK = "junk",
    OTHER = "other",
}

-- Display order for category flyout / full inventory (PRD §3.4)
Constants.CATEGORY_ORDER = {
    Constants.CATEGORY.RECENT,
    Constants.CATEGORY.EQUIPMENT,
    Constants.CATEGORY.CONSUMABLE,
    Constants.CATEGORY.TRADE_GOODS,
    Constants.CATEGORY.QUEST,
    Constants.CATEGORY.AMMO,
    Constants.CATEGORY.JUNK,
    Constants.CATEGORY.OTHER,
}

Constants.CATEGORY_LABEL = {
    [Constants.CATEGORY.RECENT] = "Recent",
    [Constants.CATEGORY.EQUIPMENT] = "Equipment",
    [Constants.CATEGORY.CONSUMABLE] = "Consumables",
    [Constants.CATEGORY.TRADE_GOODS] = "Trade Goods",
    [Constants.CATEGORY.QUEST] = "Quest",
    [Constants.CATEGORY.AMMO] = "Ammo",
    [Constants.CATEGORY.JUNK] = "Junk",
    [Constants.CATEGORY.OTHER] = "Other",
}

-- Capacity color thresholds (TDD §13.2). Implementation defaults, not user-tunable in v1.
Constants.CAPACITY_COLOR_THRESHOLDS = {
    YELLOW_AT = 0.70,
    RED_AT = 0.90,
}

-- Estimator states (TDD §5.4, §11.4)
Constants.ESTIMATOR_STATE = {
    WARMING_UP = "warming_up",
    FILLING = "filling",
    STABLE = "stable",
    FREEING = "freeing",
    FULL = "full",
}

-- Bounded history/window sizes (TDD §21 performance requirements)
Constants.RECENT_ITEMS_MAX = 50
Constants.RECENT_DISPLAY_LIMIT = 20
Constants.ESTIMATOR_SAMPLE_WINDOW_MAX = 60
-- Loot Log (recent activity feed, NOT a durable history - pH owns that).
-- Per-character, persisted in PocketsCharDB.lootLog; oldest entries drop
-- first once the bound is hit.
Constants.LOOT_LOG_MAX = 100
-- Seconds after the loot window closes during which new bag items still
-- count as loot (bag scans are debounced and trail the window).
Constants.LOOT_CONTEXT_GRACE_SECONDS = 5

--[[
    Verified Blizzard icon assets (UI_SPEC §3, §16.11-12).

    Every value below was confirmed present by grepping shipped, working
    addons on this machine's live Anniversary client (Baganator/BagBrother/
    Attune/Inscription-adjacent code) for the exact fileID or texture path
    already in production use - not guessed. Numeric values are texture
    FileDataIDs (usable directly with :SetTexture(number)); string values
    are "Interface\Icons\<name>" paths.

    Provenance, for future maintainers who want to swap any of these:
      HUD        = "Interface\Buttons\Button-Backpack-Up" (stock Blizzard
                   backpack-slot icon art - a clean backpack drawing on a
                   transparent background, not an item-icon square with
                   black corner padding, so it reads well at Glance's
                   small icon size with no texcoord cropping needed)
      other      = 133628  (BagBrother "Normal Bags" rule icon - generic bag look)
      recent     = "Interface\Icons\INV_Scroll_02" (Inscription/Attune scroll icon, distinct from quest)
      equipment  = 133126  (BagBrother item-class icon: Armor/Weapon/Gem)
      consumable = 134756  (BagBrother item-class icon: Consumable)
      trade_goods= 132894  (BagBrother item-class icon: Tradegoods/Profession/Reagent/Recipe)
      quest      = "Interface\Icons\INV_Scroll_03" (Attune/Inscription scroll icon)
      ammo       = 133581  (BagBrother's default-ammo-icon fallback)
      junk       = 134414  (BagBrother item-class icon: Miscellaneous)
      gold       = "Interface\MoneyFrame\UI-GoldIcon" (stock Blizzard money-
                   frame coin icon - same asset pH's own Ledger/HUD money
                   display uses, already clean/inline at small sizes)
]]
Constants.HUD_ICON = "Interface\\Buttons\\Button-Backpack-Up"
Constants.GOLD_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
Constants.SILVER_ICON = "Interface\\MoneyFrame\\UI-SilverIcon"
Constants.COPPER_ICON = "Interface\\MoneyFrame\\UI-CopperIcon"

Constants.CATEGORY_ICON = {
    recent = "Interface\\Icons\\INV_Scroll_02",
    equipment = 133126,
    consumable = 134756,
    trade_goods = 132894,
    quest = "Interface\\Icons\\INV_Scroll_03",
    ammo = 133581,
    junk = 134414,
    other = 133628,
}

-- Fixed UI geometry: the Mini HUD (+ sidecar) and the expanded native panel
-- (category list, category pages, All Items, Loot Log).
Constants.LAYOUT = {
    -- Metric rows (footer Bag/Gold/Ammo, via UI/MetricRow.lua). Icon size
    -- matches PHUI.Spacing.ICON_SIZE (pH-verified plain-icon size); the row is
    -- taller than the icon for a comfortable hover target and the text.
    -- (GLANCE_ prefix is historical.)
    GLANCE_METRIC_ICON_SIZE = 12,
    GLANCE_METRIC_ROW_HEIGHT = 18,
    GLANCE_METRIC_ICON_TEXT_GAP = 6,

    -- Loot Log rows: `timestamp | loot`, dense, no cards. LOOT_TIME_WIDTH
    -- fits "00:00" in GameFontNormalSmall with slack so the timestamp can
    -- never wrap or push the loot column around.
    LOOT_TIME_WIDTH = 34,
    LOOT_ROW_PAD_Y = 3,
    LOOT_COLUMN_GAP = 6,

    -- Expanded native panel. ONE outer width for every view; the body
    -- viewport, rows, search strip and footer all derive from it. ONE fixed
    -- height too: NATIVE_BODY_ROWS list rows visible (longer content
    -- scrolls, shorter leaves space), so switching views never resizes it.
    NATIVE_PANEL_WIDTH = 300,
    NATIVE_BODY_ROWS = 8,
    -- Matches PHUI.Spacing.PANEL_PADDING (Shared/PHUI.lua).
    SHELL_PADDING = 8,
    SHELL_HEADER_HEIGHT = 26,
    SHELL_FOOTER_HEIGHT = 22,
    -- Title-bar icon-button zone; matches PHUI.Spacing.ICON_BUTTON_SIZE.
    SHELL_HEADER_SIDE_WIDTH = 20,
    EXPANDED_CHROME_ALPHA = 0.96,

    -- Shared list-row geometry: category rows and item rows are the SAME row
    -- component (height, icon size, padding, gap, count column, hover), only
    -- their semantics differ. Item rows reserve the same trailing chevron
    -- column (left empty) so their count lines up with category rows'.
    LIST_ROW_HEIGHT = 36,
    LIST_ICON_SIZE = 30,
    LIST_ROW_PADDING = 6,
    LIST_ROW_GAP = 8,
    LIST_ROW_COUNT_WIDTH = 40,
    LIST_ROW_CHEVRON_WIDTH = 16,

    -- Item button size (ItemButtonPool).
    ITEM_BUTTON_SIZE = 40,

    -- Search strip magnifier icon.
    SEARCH_ICON_SIZE = 14,

    -- Mini HUD: round portrait + ring + count badge. Footprint is exactly
    -- portrait + badge minus their overlap (height = portrait - overlap +
    -- badge).
    MINI_WIDTH = 62, -- = widest piece (badge); the root must match so centre maths is exact
    MINI_HEIGHT = 79,
    MINI_PORTRAIT_SIZE = 60,
    -- Breathing room: rim r30 | 2px gap | ring r26-22 | 4px gap | bag r18.
    MINI_ICON_SIZE = 36,
    MINI_RING_THICKNESS = 4,
    MINI_RING_INSET = 4, -- ring sits this far inside the portrait rim, per side
    MINI_BADGE_WIDTH = 62,
    MINI_BADGE_HEIGHT = 24, -- room for ~5px of padding above/below the 14px count
    MINI_BADGE_OVERLAP = 5,

    -- Sidecar HUD: gold/ammo badges right of the Mini, compact recent strip
    -- 4px beneath it. No labels, no frames beyond 1px bronze edges.
    SIDECAR_BADGE_WIDTH = 56, -- minimum column width (62 Mini + 4 gap + 56 = 122); grows with text
    SIDECAR_BADGE_HEIGHT = 24, -- text/icon padded inside the pill
    SIDECAR_BADGE_GAP = 3, -- between the stacked badges
    SIDECAR_MINI_GAP = 4, -- Mini -> badges
    SIDECAR_BADGE_ICON = 16,
    SIDECAR_BADGE_PAD = 7, -- inside the pill, left and right
    SIDECAR_BADGE_GAP_ICON = 5,
    SIDECAR_STRIP_ICONS = 5,
    -- Recent strip spans exactly the Mini + gold/ammo width (118px at the
    -- minimum): 5 icons of 22px, 2px apart, no padding, no outer frame.
    SIDECAR_STRIP_ICON = 22,
    SIDECAR_STRIP_GAP = 2, -- minimum; widens only if the column grows
    SIDECAR_STRIP_PAD_X = 0,
    SIDECAR_STRIP_HEIGHT = 22,
    SIDECAR_STRIP_BELOW = 4, -- gap under the Mini

    -- Recent Item Preview (opt-in toggle, off by default) - a large
    -- floating icon shown near top-center of the screen while hovering a
    -- Recent Items strip button, independent of the HUD's own footprint so
    -- it never gets clipped.
    RECENT_PREVIEW_ICON_SIZE = 96,
    RECENT_PREVIEW_PADDING = 8,
    RECENT_PREVIEW_TOP_OFFSET = 60,
}

-- Domain events published on Pockets' internal EventBus (TDD §5.5)
Constants.DOMAIN_EVENT = {
    INVENTORY_CHANGED = "POCKETS_INVENTORY_CHANGED",
    ITEM_ACQUIRED = "POCKETS_ITEM_ACQUIRED",
    CATEGORY_CHANGED = "POCKETS_CATEGORY_CHANGED",
    CAPACITY_CHANGED = "POCKETS_CAPACITY_CHANGED",
    ETA_CHANGED = "POCKETS_ETA_CHANGED",
    COMBAT_STATE_CHANGED = "POCKETS_COMBAT_STATE_CHANGED",
    LOOT_LOGGED = "POCKETS_LOOT_LOGGED",
    READY = "POCKETS_READY",
}

-- Default SavedVariables shape (TDD §19). TOPLEFT is Pockets' one V1
-- positional anchor (UI layout pass §1/§2) - Glance and every expanded
-- state share this same screen-space origin; only TOPLEFT-anchored
-- positions are ever saved/restored (see UI/PositionStrategy.lua).
Constants.DEFAULT_SETTINGS = {
    hud = {
        point = "TOPLEFT",
        relativePoint = "TOPLEFT",
        x = 100,
        y = -100,
        locked = false,
    },
    -- Opt-in (v1 stays minimal/opinionated by default - PRD §4 non-goals
    -- warn against a large configuration surface, so new visual extras
    -- default OFF rather than always-on).
    recentItemPreviewEnabled = false,
}
