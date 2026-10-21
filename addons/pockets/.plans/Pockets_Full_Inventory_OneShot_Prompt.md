# Claude Code Prompt — Implement Pockets Full Inventory View

Implement the expanded/full inventory view for Pockets in one focused pass.

Use the existing Pockets codebase, shared PHUI layer, PRD/TDD, and the attached `Pockets_Full_Inventory_Mockup.png` as visual direction.

IMPORTANT: the mockup is visual guidance only. Preserve the approved Pockets product scope below. Do not add generic bag-addon features just because they appear in the mockup.

## Goal

Create a polished expanded inventory surface that feels like the same product as pH/Pockets:

- compact relative to traditional bag addons
- category-driven
- aggregated by item
- fully interactive
- searchable
- GENERAL and Ammo capacity shown separately
- built from shared PHUI primitives
- opens from Shift-B and the HUD expand button

## Overall layout

Use a single fixed/bounded PHUI window.

Recommended structure:

```text
┌────────────────────────────────────────────────────────────┐
│ Pockets                                      [close]        │
├───────────────┬────────────────────────────────────────────┤
│ Search        │ Current category / All Items               │
│               │                                            │
│ Recent     6  │ [item][item][item][item][item]             │
│ Equipment 14  │ [item][item][item][item][item]             │
│ Consum.  110  │ [item][item][item][item][item]             │
│ Trade     119  │ ...                                        │
│ Quest      42  │                                            │
│ Ammo      ...  │                                            │
│ Junk        1  │                                            │
│ Other     144  │                                            │
├───────────────┴────────────────────────────────────────────┤
│ Bags 59 / 76   ~13m to full      Ammo 12 / 16             │
└────────────────────────────────────────────────────────────┘
```

The actual dimensions should fit a small screen and use existing PHUI spacing/constants. Do not blindly reproduce the larger mockup dimensions.

## Header

- Use shared PHUI panel/header styling.
- Title: `Pockets`
- Close button on the far right using the existing PHUI close-button primitive.
- The window should not resize based on item counts, search results, or category contents.
- Preserve a stable fixed/bounded width and height.
- Clamp to screen bounds.

## Left category navigation

Use the existing Pockets category taxonomy only:

- Recent
- Equipment
- Consumables
- Trade Goods
- Quest
- Ammo
- Junk
- Other

Do not add Weapon, Armor, Recipe, Gem, Miscellaneous, custom categories, or category editing.

Each row:

```text
[Blizzard category icon] Category Name       Count
```

Requirements:

- fixed sidebar width
- fixed icon region
- fixed right-aligned count region
- selected category has a subtle PHUI highlight
- category rows are clickable
- category switching should be immediate
- do not rescan/reclassify bags on click
- read precomputed InventoryState/category aggregates

`All Items` may be implemented as the default full-inventory view if useful, but do not expand the category taxonomy.

## Search

Place a simple search field at the top of the category/sidebar area or top of the item area, whichever fits PHUI best.

Requirements:

- case-insensitive substring match on item name
- immediate filtering from cached inventory state
- no advanced query language
- clear button when text exists
- search does not trigger bag scans
- clearing restores the selected category/all-items view

## Item grid

Render a dense fixed-column grid of actual carried items.

Use the existing pooled real-item-button component rather than creating a separate fake icon implementation.

### Aggregate identical items

The UI must render one icon per `itemID`, even if the item is physically spread across many bag slots.

Example:

```text
Netherweave:
20 + 20 + 20 + 3
```

renders once with:

```text
63
```

in the **bottom-right**, matching WoW's normal stack-count convention.

The aggregate retains all physical stack locations underneath:

```lua
{
    itemID = ...,
    itemLink = ...,
    texture = ...,
    totalQuantity = 63,
    categoryID = ...,
    stacks = {
        { bagID = ..., slotID = ..., quantity = ... },
        ...
    }
}
```

Use `totalQuantity` for the visible count.

Hide count only for quantity 1.

## Item interaction

Rendered icons must be actual interactive WoW inventory buttons backed by current physical inventory.

Preserve, wherever Classic TBC APIs permit:

- left click: normal use/equip/open
- right click: normal item behavior
- shift-click: normal link/split-stack behavior
- drag: normal pickup/movement
- hover: normal GameTooltip
- locked-state behavior

For an aggregate item, resolve a current valid physical stack at action time.

Do not permanently trust a stale bag/slot reference.

If inventory revision changes, update the aggregate/button backing data before interaction.

## Recent

Recent remains first-class.

For Recent:
- visually aggregate repeated acquisitions by item where consistent with the current Recent model
- show the aggregate/current total presentation cleanly
- only expose a clickable physical-item action when a valid carried stack currently exists
- do not invent a bag/slot action for historical items no longer carried

## Capacity footer

Show capacity in a compact footer using the same semantics as the HUD.

Primary:

```text
Bags 59 / 76   ~13m to full
```

This is GENERAL capacity only.

If and only if an actual ammo-specialized bag/quiver is equipped:

```text
Ammo 12 / 16
```

Requirements:

- ammo slots excluded from GENERAL capacity
- ammo capacity row hidden entirely when there is no ammo bag/quiver
- carrying arrows/bullets in normal bags does NOT create Ammo capacity
- GENERAL capacity alone drives bag-full ETA

## Ammo category vs Ammo capacity

Keep these concepts separate:

- Ammo category = ammo items carried anywhere
- Ammo capacity = used/total slots in an equipped ammo-specialized bag

The Ammo item category may exist when carrying ammunition in normal bags even if no Ammo capacity is displayed.

## Visual language

Use the existing shared PHUI interface as the source of truth.

Do not create a separate Pockets theme.

Reuse actual pH/Pockets shared:

- backdrop
- border
- fonts
- text colors
- button styles
- icon-button treatment
- spacing/padding
- selected/hover states

Use Blizzard-provided icons/item textures. Do not bundle custom inventory/category art.

The final surface should look like a larger pH panel, not like Bagnon or Baganator pasted into the addon.

## Small-screen behavior

The full view must stay useful on a small display.

- fixed/bounded outer dimensions
- grid uses available internal space
- if items exceed available visible rows, use internal scrolling
- do not grow the window off-screen
- avoid large decorative headers or empty whitespace
- no inspector/details pane in v1
- no permanent filter/sort toolbars
- category sidebar should remain narrow

## Explicit non-goals

Do NOT implement:

- sort controls
- configurable sorting
- filter system
- item details/inspector pane
- bank
- guild bank
- cross-character inventory
- auto-sell junk
- custom categories
- category editor
- advanced search
- profession bag support beyond current Ammo handling
- pagination unless scrolling is technically impractical
- additional category taxonomy from the visual mockup

The generated mockup contains some of these concepts for visual composition; they are NOT approved product scope.

## Open/close behavior

The same full-inventory frame must be used by:

- Shift-B
- HUD expand/open button

Both invoke the same toggle method.

Do not create separate implementations.

Close button closes this same window.

Opening/closing must not reset inventory state unnecessarily.

## Combat

Preserve the existing Pockets combat philosophy:

- full inventory remains accessible via click/Shift-B in combat
- do not hide the entire UI
- item operations work wherever WoW permits them
- if a specific protected action fails, fail that action only

## Performance

Opening the full inventory should be a render operation against cached state.

Do not synchronously perform on open/category click/search input:

- full bag scans
- categorization passes
- metadata discovery for all items
- stack consolidation
- ETA recomputation loops

Use InventoryState aggregates and existing caches.

Pool/reuse all repeated item buttons and category rows.

## Likely implementation shape

Prefer reusing/extending existing modules rather than parallel systems:

- `UI/FullInventory.lua`
- existing item-button pool/component
- existing category row component where practical
- existing Search module
- `InventoryState` aggregate API
- PHUI shared primitives

If a needed shared primitive does not exist, add the smallest generic PHUI primitive necessary rather than Pockets-only theme duplication.

## Acceptance criteria

The implementation is complete when:

1. Shift-B opens one polished full Pockets inventory window.
2. HUD expand button opens the exact same window.
3. Full view uses shared PHUI styling and looks consistent with pH.
4. Sidebar contains only approved Pockets categories.
5. Category switching is immediate.
6. Search filters cached items by name.
7. Identical item stacks render exactly once per itemID.
8. Aggregate quantity appears bottom-right using WoW convention.
9. Aggregate buttons remain correctly interactive with real physical stacks.
10. No stale bag/slot action can occur after inventory changes.
11. GENERAL Bags capacity is correct.
12. Ammo capacity appears only with a real equipped quiver/ammo pouch.
13. Ammo capacity is excluded from Bags capacity and ETA.
14. Large inventories scroll internally rather than resizing off-screen.
15. Window width/height remain stable across categories/search results.
16. No sorting/filter/details/bank scope is accidentally introduced.
17. Hover/click/combat behavior elsewhere in Pockets is not regressed.
18. No bag scan/categorization pass runs merely because the full window opened.

## Completion

Before declaring done:

- run luacheck
- run existing automated tests
- add/update tests for full inventory rendering, aggregated items, search, capacity footer, and ammo visibility
- run static/repository checks
- verify TOC/load order if new files were added
- reinstall the addon
- summarize changed files and any manual `/reload` checks I should perform

Do not stop at a plan. Implement the full view end-to-end.
