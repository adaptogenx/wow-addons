# Pockets UI Rules

Modeled after pH's UI discipline, adapted for Pockets' progressive-
disclosure bag HUD (`Pockets_PRD.md` §2, `Pockets_TDD.md` §13, §26,
`Pockets_UI_SPEC.md`). **`Pockets_UI_SPEC.md` is authoritative for exact
pixel geometry, icon sourcing, and hover behavior** - this file states the
rules; the spec states the numbers.

## Core Rules

1. **Compact HUD first.** The default, always-visible state is one small
   fixed-size frame (`UI/HUD.lua`): a square verified-Blizzard bag icon
   plus capacity/ETA text. No feature may require permanent extra screen
   space without explicit product approval.
2. **Progressive disclosure only.** HUD → category flyout → item flyout →
   full inventory. Don't skip a level, and don't add a persistent
   always-visible layer beyond the HUD itself.
3. **Frames stay on-screen.** After dragging or scaling, a frame must
   remain fully within the screen bounds. The item flyout flips from the
   right side to the left when it would overflow (UI_SPEC §7, §13).
4. **Fixed geometry lives in one place.** Every pixel width/height/column
   count comes from `Constants.LAYOUT` (`HUD_WIDTH`, `FLYOUT_WIDTH`,
   `ITEM_PANEL_COLUMNS`, etc.) - never hard-coded per module, never derived
   from content length. Fonts/padding/capacity-color come from
   `UI/Layout.lua`. **No panel may resize because counts, digit count, or
   item names changed** (UI_SPEC §16.1-4).
5. **No UI module owns authoritative inventory state.** Every UI module
   reads from `Core/InventoryState.lua` / `Pockets.API` (via
   `API.GetCategoryItems`, which also resolves Recent) and never rescans
   bags, categorizes, or does other inventory work itself - including on
   hover (UI_SPEC §6).
6. **Never block the full Pockets UI in combat.** Only hover-triggered
   expansion is suppressed in combat (`Pockets_TDD.md` §14, UI_SPEC §12).
   Clicking the HUD, clicking a category, and Shift-B must keep working.
   Individual protected/restricted actions degrade independently rather
   than hiding the whole addon.
7. **Hover is convenience; click is the reliable path.** Every hover-driven
   reveal (category flyout, item flyout) must have an equivalent click
   path that also works in combat. Opening on hover must be immediate (no
   timer); only closing goes through `UI/HoverGroup.lua`'s shared grace
   timer, so crossing the gap between two connected panels never
   flicker-closes them (UI_SPEC §5).
8. **Pool, don't recreate.** Repeated rows/buttons (category rows, item
   buttons) come from `UI/ItemButtonPool.lua` or an equivalent per-frame
   pool. Flyouts and the full inventory view must not create new frames on
   every open.
9. **Render only non-empty categories.** Empty categories are hidden in
   both the category flyout and the full inventory view.
10. **Item icons are real item buttons, never decorative textures.** Every
    rendered item icon (category flyout, item flyout, full inventory) must
    go through `ItemButtonPool:Configure(button, record)`, which binds the
    button to `record.bagID`/`record.slotID` via `Adapters/BagAPI.lua` so
    click/right-click/shift-click/drag/tooltip work normally (UI_SPEC §8).
    Re-`Configure` on every render - never let a pooled button keep acting
    on a bag/slot from a previous render (stale-location safety).
11. **Category icons are verified Blizzard textures only.** Sourced from
    `Constants.CATEGORY_ICON` / `Constants.HUD_ICON` - see the provenance
    comment above that table in `Constants.lua` for how each was verified.
    Never bundle custom icon art; never guess a texture path/fileID without
    confirming it's already used by a real, shipped addon or documented
    Blizzard constant.
12. **Tooltip content stays terse.** `UI/TooltipCounts.lua` adds exactly
    one line (`In your pockets: <count>`) and never duplicates it on tooltip
    refresh.
13. **Flyouts stay independently closable.** `CategoryFlyout` and
    `ItemFlyout` each manage their own show/hide so click navigation keeps
    working even if a parent flyout later closes.

## Capacity Colors

Use `Layout:GetCapacityColor(utilization)` - never re-implement the
green/yellow/red thresholds in a UI module. Current implementation
defaults (`Constants.CAPACITY_COLOR_THRESHOLDS`), not a user-facing tuning
system in v1:

```
Green  < 70% used
Yellow 70-89% used
Red    >= 90% used
```

## Full Inventory Layout

- Fixed width/height (`Constants.LAYOUT.FULL_INVENTORY_WIDTH/HEIGHT`)
  appropriate for small screens, with internal scrolling for overflow
  rather than growing the frame (UI_SPEC §10).
- Category sections stack vertically; no persistent sidebars.
- Search row only exists while the full view is open (`PRD §3.7`) - never
  a persistent search box in the HUD or category flyout.
- Recent items render first, always unfiltered by search.
- One frame with pooled real item buttons (shared `ItemButtonPool` with the
  item flyout) - never one panel per physical bag.

## When Adding a New UI Module

1. Read state through `Pockets.Services.*` or `Pockets.API.*` - don't
   introduce a second source of truth.
2. Subscribe to `Core/EventBus.lua` domain events rather than polling.
3. Pull geometry from `Constants.LAYOUT`, fonts/padding/color from
   `UI/Layout.lua`.
4. Confirm the combat behavior matches `Pockets_TDD.md` §14 / UI_SPEC §12's
   hover/click state machine before shipping.
5. If it renders items, use `ItemButtonPool:Configure` rather than a new
   icon-rendering path.
6. Add the corresponding manual acceptance case to
   [TESTING_GUIDE.md](TESTING_GUIDE.md).
