Add a Category View preference to Pockets so users can choose between:

1. Grid view — preserve the current implementation exactly
2. List view — new compact item-list presentation

Do NOT delete or replace the existing grid code.

==================================================
1. PREFERENCE
==================================================

Add a persisted user preference:

Category View:
- Grid
- List

Default:
List

Reason:
The current grid is already functional and useful for fast visual scanning. The new list mode is better for readable item names and dense category browsing. Both should remain supported.

Store the preference in the existing Pockets SavedVariables/settings system.

Conceptually:

settings.categoryViewMode = "GRID" | "LIST"

Do not create a parallel settings framework.

==================================================
2. SETTINGS UI
==================================================

Expose the preference through the existing Pockets configuration/preferences UI.

Label:

Category View

Options:

Grid
List

Keep the control compact and consistent with existing PHUI/settings components.

Changing the preference should immediately re-render the currently open Category state if one is visible.

No reload should be required.

==================================================
3. CATEGORY RENDERER DISPATCH
==================================================

Category state remains one navigation state.

Do NOT create separate navigation states like:

CATEGORY_GRID
CATEGORY_LIST

Instead:

CATEGORY
  -> choose renderer from preference

Conceptually:

RenderCategory(categoryID)

if categoryViewMode == "LIST":
    RenderCategoryList(categoryID)
else:
    RenderCategoryGrid(categoryID)

Header, footer, root frame, navigation, capacity status, and state-machine behavior remain identical between both modes.

Only the body renderer changes.

==================================================
4. PRESERVE GRID VIEW
==================================================

Do not rewrite the current grid unless small extraction work is required to make renderer selection clean.

Grid continues to provide:

- current item-button size
- aggregated identical items
- bottom-right aggregate quantity
- scrolling when needed
- real WoW item interactions
- current pooling
- current spacing/layout behavior

If refactoring is required, preserve behavior exactly.

Grid should remain the default until we deliberately change the product default later.

==================================================
5. NEW LIST VIEW
==================================================

List view uses the same compact visual grammar as the Menu.

Target:

[icon] Super Healing Potion                       19
[icon] Bottled Nethergon Energy                    5
[icon] Blackened Sporefish                         3
[icon] Warp Burger                                 6
[icon] Flask of Relentless Assault                 2

Each aggregate item is one row.

Row contract:

[ICON] [FULL ITEM NAME]                    [TOTAL QUANTITY]

Recommended starting dimensions:

- icon: ~22–24px
- row height: ~28–32px
- compact vertical padding
- same left/right content padding as Menu
- fixed right-aligned quantity region

Do not add a chevron to item rows.

==================================================
6. ITEM NAME
==================================================

Display the actual item name.

Use WoW item-quality coloring when quality metadata exists.

Examples:

poor -> gray
common -> white
uncommon -> green
rare -> blue
epic -> purple

Use the same quality-color source already used elsewhere in Pockets/WoW rather than duplicating constants.

If a name cannot fit:

- truncate with ellipsis
- do not shrink font
- normal GameTooltip still exposes the full name/details

==================================================
7. AGGREGATION IS IDENTICAL IN BOTH MODES
==================================================

Grid and List are two views over the same aggregate data.

Example physical stacks:

5 + 5 + 5 + 2

Both render one logical item:

Grid:
[Healing Potion icon]
              17

List:
[icon] Healing Potion                              17

Do not maintain separate aggregate logic for each renderer.

Both consume the same InventoryState/aggregate records.

==================================================
8. ITEM INTERACTIONS MUST MATCH
==================================================

Grid and List must expose the same underlying item interaction behavior.

For List, make the whole row the interaction target where practical.

Preserve:

Hover:
-> normal GameTooltip

Right click:
-> standard WoW use/equip/open/consume

Left click + drag:
-> resolve and pick up a real underlying physical stack

Shift-click:
-> split stack / chat link according to normal WoW context

Locked state:
-> preserve current behavior

Do not create different semantics between Grid and List.

==================================================
9. PHYSICAL STACK RESOLUTION
==================================================

Both views use the same existing aggregate-to-physical-stack resolver.

Do not duplicate resolver logic.

If current behavior resolves the smallest valid stack for manipulation, preserve that.

Stale bag/slot protection must remain identical.

==================================================
10. SCROLLING
==================================================

List mode:

If rows fit:
- no scrollbar
- no scrollbar track
- no scrollbar gutter

If rows overflow:
- use the existing Category body scroll behavior
- scrollbar appears conditionally
- row width adjusts accordingly

Grid mode keeps its current conditional scrolling behavior.

Switching view modes should reset/recompute the body layout correctly.

==================================================
11. STATE/ANCHOR BEHAVIOR
==================================================

Do not alter the current navigation model.

Category remains:

[<] Category Name                              [+]

Back:
CATEGORY -> MENU

+:
CATEGORY -> ALL

Switching Grid/List must NOT:

- move root TOPLEFT
- resize/reposition Header independently
- modify Footer anchors
- create another frame
- change navigation state

Only the Category body presentation changes.

==================================================
12. RENDER LIFECYCLE
==================================================

Make renderer switching explicit and clean.

When switching from Grid -> List:

- hide/release grid item buttons
- clear/reset Category body layout
- render list rows

When switching List -> Grid:

- hide/release list rows
- clear/reset Category body layout
- render grid buttons

No ghost rows/buttons.

No duplicate frames accumulating.

Use pools for list rows if appropriate.

==================================================
13. CODE ORGANIZATION
==================================================

Prefer a structure like:

CategoryView.lua
    Render(categoryID)
    SetMode(mode)

CategoryGridRenderer.lua
CategoryListRenderer.lua

or equivalent using the current project organization.

Do not over-engineer this if existing UI modules already have a better seam.

The important boundary is:

Category state/navigation
!=
Category presentation renderer

==================================================
14. TESTS
==================================================

Add/update tests for:

Preference:
- default is GRID
- setting LIST persists
- setting GRID persists
- invalid value falls back safely

Renderer selection:
- GRID invokes grid renderer
- LIST invokes list renderer

Runtime switching:
- Grid -> List updates visible Category immediately
- List -> Grid updates immediately
- no state transition occurs
- root TOPLEFT does not change
- Header/Footer do not move

Cleanup:
- no grid buttons visible in List mode
- no list rows visible in Grid mode
- repeated toggles do not accumulate frames

Aggregation:
- same aggregate totals in Grid and List

Interaction:
- right click works in both
- drag works in both
- split/link works in both
- stale stack handling is shared

Scrolling:
- list no-overflow -> no scrollbar
- list overflow -> scrollbar
- grid behavior unchanged

==================================================
15. COMPLETION
==================================================

Inspect the existing Category grid implementation first.

Then:

- preserve it
- extract a clean renderer boundary if necessary
- add persisted Grid/List preference
- add settings control
- implement List renderer
- support immediate mode switching
- preserve shared aggregate and interaction logic
- run luacheck
- run tests/static checks
- reinstall Pockets

At completion, summarize:

1. files changed
2. where the preference is stored
3. default mode
4. how Category chooses renderer
5. whether grid code changed at all
6. how shared item interactions are reused
7. manual /reload checks I should perform

Do not delete the grid implementation.
Do not turn this into separate Category navigation states.
Implement this as a presentation preference.
