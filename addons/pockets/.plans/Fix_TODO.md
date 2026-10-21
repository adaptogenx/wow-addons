Fix list for the current Glance/Menu/Category/All shell.

Do not mix Adaptive Screen Sizing into this pass (see `.plans/Adaptive_Screen_sizing.md`).

==================================================
1. Alphabetical ordering of items
==================================================

Status: fixed. Category/All item lists now sort A-Z at `API.GetAggregatedCategoryItems`.

Fix:
- Sort aggregated items A–Z by item name (case-insensitive) in Category List, Category Grid, and All Items grouped sections.
- Keep Menu category order as `CATEGORY_ORDER` (taxonomy, not alpha).
- Keep Recent newest-first. Recency is the point of that view.
- Missing names sort last (`item:<id>` fallback), not as empty strings.

Touch:
- `pockets/Core/InventoryState.lua` (`GetItemsByCategory` / `AggregateRecords`) or a single sort at `API.GetAggregatedCategoryItems`
- Tests for A–Z order and Recent remaining unsorted by name

==================================================
2. Unique recent items
==================================================

Status: fixed. `RecentItems:Record` now dedupes by `itemID` at insertion, bumping the existing entry to newest instead of adding a second row.

Effect: fishing 20 of the same fish fills `RECENT_ITEMS_MAX` with that one id, then the other unique recents fall off the queue. After display-time dedupe the Recent category is just that fish.

Fix:
- Treat Recent as unique-by-itemID, not a raw event log.
- Re-acquiring an already-recent item: bump it to newest, do not add a second row, do not evict other unique items.
- Bound unique itemIDs (`RECENT_ITEMS_MAX` / `RECENT_DISPLAY_LIMIT`), not duplicate pickup events.
- Displayed quantity stays current carried total (existing resolver behavior).

Touch:
- `pockets/Core/RecentItems.lua`
- `pockets/Tests/RecentItemsTests.lua`
- `pockets/Tests/APITests.lua` (dedupe-at-source, not only at resolve)

==================================================
3. Glance is not a square
==================================================

Status: fixed. Glance is now a true square: bag icon top-left, search icon top-right, capacity/ETA text column centered below. `GLANCE_SIZE` (74 with current values) is derived as the max of the icon+search row width, the text column width, and the full vertical stack height - replaces the old separate `GLANCE_WIDTH`/`GLANCE_HEIGHT`.

The compactness pass optimized for a horizontal `[icon][capacity/ETA]` row. The Glance plan asked for a small square surface.

Fix:
- Glance frame width == height (true square, not “square-ish”).
- Bag icon stays the dominant visual.
- Capacity (`57 / 84`) and compact ETA still readable inside the square.
- Adding the search control (#4) must not stretch Glance back into a rectangle.
- Existing tests that lock the derived 108-wide layout need to change with the geometry.

Touch:
- `pockets/Constants.lua` (`LAYOUT.GLANCE_*`)
- `pockets/UI/Shell.lua` (`BuildGlance` / `RenderGlance`)
- `pockets/Tests/ShellTests.lua` (Glance size tests)

==================================================
4. Search icon / easy search on Glance
==================================================

Status: fixed, enabled. Implemented as Glance Quick Search (dedicated `Shell.STATE.SEARCH`) instead of "jump to All Items search" - Glance's search icon replaces Glance in place with a compact, non-browsing search surface (0/1-2/3+ result thresholds, ranked exact/prefix/substring matching, max 2 rows, no footer/scrollbar). Reuses `CreateCategoryListRow`/`ItemButtonPool` for real secure item rows. Back/X/Escape all return to Glance.

Shipped together with the square-Glance pass (#3) rather than as a separate follow-up: the icon+search row (top of the square) fits inside the width the text column below it already demands, so re-enabling the button cost no extra size. `glance.searchButton` is shown again in `Shell:BuildGlance`, anchored top-right; `GLANCE_SIZE`'s derivation includes the icon+search row as one of its width candidates.

Touch:
- `pockets/UI/Shell.lua`, `pockets/UI/Search.lua`, `pockets/API.lua`, `pockets/Constants.lua`
- `pockets/Tests/ShellTests.lua`, `pockets/Tests/SearchTests.lua`, `pockets/Tests/APITests.lua`

==================================================
5. Close (X) on list views → Glance
==================================================

Status: fixed. Header now has a fixed [< ][Title][context][X] geometry across Menu/Category/All. X (`PHUI.CreateCloseButton`) always dismisses straight to Glance; Back stays hierarchical; Escape now dismisses straight to Glance in one step instead of walking the hierarchy.

Fix:
- Show an X/close control on Menu, Category, and All Items (every expanded list view).
- Clicking it always returns to Glance, skipping Menu when the current state is Category or All.
- Leave `<` and Escape as one-level Back. X is “dismiss Pockets,” Back is “up one level.”
- Keep X on Glance hidden; Glance is already the collapsed HUD.
- Do not steal All Items’ search slot. Park X on the far right; `+` / search sit just left of it.
- Use the existing PHUI close-button treatment rather than a one-off glyph.

Touch:
- `pockets/UI/Shell.lua` (`BuildShell`, `ConfigureHeader`, new `CloseToGlance` or `SetState(GLANCE)`)
- `pockets/Constants.lua` if the header right zone needs room for close + plus/search
- `pockets/Tests/ShellTests.lua` (X on every expanded state; Category/All X lands on Glance, not Menu)

==================================================
6. Items from the mail do not count as Recent
==================================================

Status: not started. Bug, not a policy - mail pickups should hit Recent
the same as any other positive-total-delta acquisition.

Effect: taking an item out of the mailbox does not add it to Recent.
Suspect something about how mail delivers items to bags doesn't trigger
(or survive) `InventoryState:Refresh()`'s diff, so the positive delta
`RecentItems:Record` relies on never fires for mail.

Fix:
- Repro: send/receive an item via mail, open bags, confirm it's missing
  from Recent.
- Find why the mail acquisition path doesn't produce the same
  aggregate-total delta a loot/vendor/trade acquisition does (event not
  firing/registered, refresh timing vs. mail window, etc.).
- Make mail acquisitions flow through the normal `RecentItems:Record`
  path - no mail-specific special-casing in `RecentItems` itself.

Touch:
- `pockets/Core/InventoryState.lua` (event registration / refresh timing)
- `pockets/Core/RecentItems.lua`
- `pockets/Tests/RecentItemsTests.lua`

==================================================
7. Suggested implementation order
==================================================

1. Unique recents (core, no layout risk)
2. Alphabetical item order (core/API, tests)
3. Square Glance (layout + tests)
4. Glance search icon (depends on square Glance so the control fits)
5. Close X on list views (header chrome; independent of Glance square except shared header-zone math)

==================================================
8. Out of scope
==================================================

- Adaptive viewport / growth direction
- User-facing sort UI or configurable sort order
- Persistent search box on Glance or Menu
- Changing category taxonomy order
