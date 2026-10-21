# Pocket — Expanded Bag One-Shot Claude Prompt

Implement the expanded/full inventory view for Pocket end-to-end. Inspect the existing ph-pockets code and shared PHUI implementation first, then implement it. Do not stop at planning.

## Product intent
Pocket is not Bagnon/Baganator. Preserve: minimal screen footprint, opinionated category organization, high information density, little UI chrome, aggregated identical items, normal WoW interactions, and small-screen usability. Think: "Show me everything in my Pocket."

## Entry points
Shift-B and the Pocket HUD expand button must toggle the exact same expanded frame. The close button closes it.

## Shared UI
Use existing PHUI backdrop, borders, fonts, colors, icon buttons, spacing, padding, hover states, and close-button treatment. Do not create another Pocket theme or redesign pH/PHUI.

## Window
Fixed/bounded frame:

POCKET                         [Search...] [X]
------------------------------------------------
          scrollable inventory flow
------------------------------------------------
Bags 59/76 · ~13m to full        Ammo 12/16

Title is `Pocket`, singular. Header/footer stay fixed; only body scrolls. Window dimensions never change with inventory/search. Clamp to screen and optimize for small screens. No sidebar, inspector, or sort/filter toolbar.

## Categories
Use the existing Pocket taxonomy/categorizer: Recent, Equipment, Consumables, Trade Goods, Quest, Ammo where applicable as an item category, Junk, Other. Do not invent categories or category configuration.

## Dynamic item flow
This is NOT independent fixed-height category sections. Items flow left-to-right with consistent size/gap and may span any number of rows. Never reserve unused rows or fixed category heights.

### Category packing heuristic
Avoid both extremes: always starting categories on fresh rows wastes space; fully continuous category flow mangles visual structure.

Categories normally start on a fresh row. When a category ends, inspect actual pixel width used by its FINAL item row.

If final-row used width is LESS THAN 50% of available row width, the next category MAY begin in the remaining space on that same row.

If used width is 50% OR MORE, next category starts on a fresh row.

Example allowed:

Category A
[i][i][i][i][i][i][i][i]
[i]   Category B [i][i][i][i]

Example not inlined:

Category A
[i][i][i][i][i]

Category B
[i][i][i]

Use actual widths, not item counts:

remainingWidth = rowWidth - usedWidth

canInlineNext =
    usedWidth < (rowWidth * 0.5)
    and remainingWidth >= (nextCategoryLabelWidth + gap + itemWidth)

Inline only if:
1. prior final row is <50% used;
2. complete next category label fits;
3. at least one item from the new category fits after the label.

Otherwise wrap. Never split a category label. Once inline, its items flow naturally and wrap. Keep the packing strategy modular so a smarter dynamic layout can replace it later.

## Category labels
Compact `[small icon] Category Name` labels. No large full-width headers or decorative rules. Boundaries must remain visually obvious when two categories share a row. Use PHUI typography/colors.

## Scrolling
One vertical scroll region for the entire category/item flow. No per-category scrolling, pagination, multiple scrollbars, or growing the outer window.

## Item aggregation
Aggregate identical items by itemID for presentation.

Physical Netherweave stacks `20 + 20 + 20 + 3` render as ONE icon with `63` bottom-right using WoW's stack-count convention. Quantity 1 may omit count.

Retain physical locations underneath:
{
  itemID,
  itemLink,
  texture,
  totalQuantity,
  categoryID,
  stacks = {
    {bagID, slotID, quantity},
    ...
  }
}

This is visual aggregation, NOT physical stack consolidation.

## Item interaction
Aggregated icons remain real usable inventory items. Preserve tooltip, use/equip, right-click, shift-click, drag/pickup, and locked behavior wherever Classic TBC permits.

Never permanently bind an aggregate to a stale slot. At action time resolve a current valid physical stack (deterministically: first valid or largest valid). Refresh backing aggregate data after InventoryState changes. Reuse existing real-item-button/pooling infrastructure.

## Recent
Recent remains first and uses existing Pocket recent semantics. It participates in the same flow. Avoid duplicate identical recent entries where appropriate. Never fabricate an interactive slot for a historical item no longer carried.

## Search
Compact header search. Case-insensitive item-name matching against cached aggregates, immediate updates, clear action. Search must not trigger bag scans, categorization passes, or metadata loops. Search may temporarily flatten categories into dense matching aggregated items; clearing restores categorized flow.

## Capacity footer
GENERAL: `Bags 59 / 76   ~13m to full`. ETA uses GENERAL capacity only.

Show `Ammo 12 / 16` ONLY with an actually equipped quiver/ammo pouch. Carrying ammo in normal bags does not create Ammo capacity and never show `Ammo 0 / 0`. Specialized ammo slots are excluded from GENERAL capacity.

Ammo item category = ammunition carried anywhere.
Ammo capacity = utilization of equipped specialized ammo storage.

## Combat
Full view remains accessible through Shift-B/HUD button in combat. Individual protected actions obey WoW restrictions; do not hide the entire UI.

## Performance
Opening, scrolling, searching, and layout should render cached state. Do not synchronously perform full scans, categorization, metadata discovery, ETA reconstruction, or stack consolidation. Pool/reuse item buttons.

## Non-goals
No physical bag representations, sidebar, manual sorting, sort controls, configurable filters, inspector/details pane, custom categories, bank/guild bank, cross-character inventory, junk selling, advanced search, profession bags beyond approved Ammo behavior, pagination, per-category scrolling, or large decorative category sections.

## Tests

Layout:
- empty categories
- one-row and multi-row categories
- exactly one overflow item
- final row <50% permits inline
- ==50% does NOT inline
- >50% does NOT inline
- label fits but label + one item does not -> wrap
- label never splits
- inline category wraps correctly
- inventory changes reflow
- scroll height matches content

Aggregation:
- one/multiple stacks
- full + partial stacks
- merge/split
- quantity changes/zero removal
- correct total and bottom-right count
- valid physical interaction
- stale slots rejected

Search:
- case-insensitive match
- clear restores flow
- no bag scan

Capacity:
- normal bags
- ammo in normal bags
- empty/partial/full quiver
- Ammo footer visibility
- GENERAL excludes ammo bag
- ETA GENERAL-only

Entry points:
- Shift-B toggles expanded Pocket
- HUD expand invokes same toggle
- close closes same frame

## Completion
Run luacheck, all tests, and repository/static checks; fix failures. Verify TOC/load order and no duplicated PHUI theme code. Install/update addon for in-game testing. Summarize files changed, dynamic layout implementation, aggregate interaction strategy, Classic TBC API limitations, and manual `/reload` checks.

Do not stop at architecture. Implement end-to-end.
