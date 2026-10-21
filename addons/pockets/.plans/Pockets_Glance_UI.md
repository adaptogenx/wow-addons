Implement the next Pockets UI/navigation architecture end-to-end.

This replaces the current multi-window / flyout-oriented interaction model with a single-frame, in-place navigation model.

Do not stop at planning. Inspect the existing ph-pockets code and shared PHUI implementation, reconcile this design with what already works, then implement it.

VISUAL REFERENCE

Use this image as the visual reference:

a_clean_ui_concept_mockup_infographic_style_imag.png

The image communicates:
- four UI states
- one shared frame after Glance
- stable header/footer geometry
- category navigation in place
- category item view in place
- All Items view in place

The written requirements below are authoritative where the image differs.

==================================================
1. PRODUCT / UX DIRECTION
==================================================

Pockets should behave more like a native hierarchical application surface than a web-style collection of flyouts.

Core principle:

ONE OBJECT
ONE ROOT FRAME
CONTENT CHANGES IN PLACE

Do NOT continue the current model:

HUD
→ flyout
→ item flyout
→ separate expanded inventory

Instead implement:

Glance
→ Menu
→ Category
→ All Items

Navigation changes the contents/state of Pockets rather than spawning adjacent windows.

Hover is no longer primary navigation.

Hover remains useful for:
- normal WoW item tooltips
- button hover feedback

Click is the reliable navigation mechanism.

==================================================
2. UI STATES
==================================================

There are four states.

------------------------------
STATE 1 — GLANCE
------------------------------

This is the only state allowed to use unique/minimal geometry.

Concept:

┌──────────────┐
│    [BAG]     │
│    57 / 84   │
│  13m to full │
│              │
│ [AMMO] 12/16 │
└──────────────┘

Goals:
- extremely small
- square-ish
- bag icon is visually dominant
- general bag capacity is immediately readable
- ETA shown when sufficiently trustworthy
- no "~" prefix in ETA
- Ammo appears only if an actual quiver/ammo pouch is equipped

Example:

57 / 84
13m to full

NOT:

~13m to full

If ETA cannot be estimated with reasonable reliability, hide it rather than showing a wildly incorrect value.

Clicking Glance opens Menu.

Glance does NOT need the persistent navigation header used by deeper states.

------------------------------
STATE 2 — MENU
------------------------------

Once leaving Glance, Pockets establishes a stable application shell.

Concept:

┌─────────────────────┐
│ Pockets          [+]│
├─────────────────────┤
│ Recent          6  ›│
│ Equipment      14  ›│
│ Consumables    23  ›│
│ Trade Goods    31  ›│
│ Quest           4  ›│
│ Junk            1  ›│
│ Other          11  ›│
├─────────────────────┤
│ 57/84 · 13m    12/16│
└─────────────────────┘

Menu requirements:
- stable header
- stable footer
- category list in body
- category rows are clicked, not hover-navigated
- category counts right aligned
- subtle `>` affordance
- use existing Pockets category taxonomy
- compact density
- PHUI styling

The `+` button uses the same shared PHUI "+" button treatment as pH.

In Menu:

+ = open All Items state

------------------------------
STATE 3 — CATEGORY
------------------------------

Same root frame.
Same width.
Same header height.
Same footer height.
Same screen position.

Only body/header content changes.

Concept:

┌─────────────────────┐
│ ‹  Consumables   [+]│
├─────────────────────┤
│ [i][i][i][i][i]    │
│ [i][i][i][i][i]    │
│ [i][i]             │
│                     │
├─────────────────────┤
│ 57/84 · 13m    12/16│
└─────────────────────┘

Header layout must use fixed regions:

[back] [title] [right action]

Back button:
- returns to Menu

Title:
- current category name

+:
- switches to All Items

Do not move controls around between states.

Category view:
- renders aggregated item buttons from only the selected category
- body may scroll if necessary
- uses the same item-button implementation as All Items
- never opens another category/item window

------------------------------
STATE 4 — ALL ITEMS
------------------------------

Same application shell again.

Concept:

┌─────────────────────┐
│ ‹  All       [Search]│
├─────────────────────┤
│ Recent              │
│ [i][i][i][i][i]     │
│                     │
│ Equipment           │
│ [i][i][i]           │
│                     │
│ Consumables         │
│ [i][i][i][i][i]     │
│       ↓ scroll      │
├─────────────────────┤
│ 57/84 · 13m    12/16│
└─────────────────────┘

The + button is NOT shown here because the user is already in All Items.

Its right-side header slot becomes Search.

Back:
- returns to Menu

All Items:
- categorized
- compact
- scrollable
- aggregated
- searchable
- no sidebar
- no inspector
- no sorting UI
- no filter toolbar
- no additional windows

==================================================
3. STABLE APPLICATION SHELL
==================================================

This is a hard UI rule.

MENU, CATEGORY, and ALL ITEMS must share:

- exact root-frame position
- exact width
- exact header height
- exact footer height
- consistent body viewport
- consistent left/right action zones

Changing state must NOT make the UI jump around.

Header contracts:

Menu:
[Pockets]                        [+]

Category:
[<] [Category Name]             [+]

All:
[<] [All]                  [Search]

The control occupying a slot may change, but the slot does not move.

Glance is exempt and may be significantly smaller.

==================================================
4. NAVIGATION STATE MACHINE
==================================================

Implement explicit state rather than visibility relationships between multiple windows.

Suggested conceptual states:

GLANCE
MENU
CATEGORY
ALL

and for Category:

selectedCategoryID

Suggested interface:

Pockets.UI:SetState(state, context)
Pockets.UI:GetState()

Transitions:

GLANCE click
→ MENU

MENU category click
→ CATEGORY(categoryID)

MENU +
→ ALL

CATEGORY back
→ MENU

CATEGORY +
→ ALL

ALL back
→ MENU

Shift-B
→ ALL directly

HUD + / expanded action
→ ALL directly where applicable

Escape hierarchy:

CATEGORY → MENU
ALL      → MENU
MENU     → GLANCE
GLANCE   → no-op / normal close behavior as appropriate

Do not destroy/recreate the root frame between transitions.

==================================================
5. ITEM PRESENTATION: AGGREGATION
==================================================

Pockets intentionally hides physical stack fragmentation in normal presentation.

Example physical inventory:

Healing Potion:
5 + 5 + 5 + 2

Pockets displays:

[Healing Potion]
       17

One icon per itemID.

Quantity appears bottom-right using normal WoW stack-count convention.

Conceptual aggregate:

{
    itemID,
    itemLink,
    texture,
    categoryID,
    totalQuantity,

    stacks = {
        { bagID, slotID, quantity },
        ...
    }
}

This aggregation is PRESENTATION ONLY.

Do not force physical WoW stacks to merge.

This allows a player to retain:

5 + 5 + 5 + 2

while Pockets presents:

17

==================================================
6. STANDARD WOW ITEM FUNCTIONALITY MUST REMAIN
==================================================

Pockets may virtualize presentation, but item buttons still represent real inventory.

For items in Category and All Items, preserve normal WoW behavior wherever Classic TBC APIs permit.

Required interaction contract:

HOVER
→ normal GameTooltip

RIGHT CLICK
→ standard WoW right-click action:
   use / equip / open / consume / etc.

LEFT CLICK + DRAG
→ pick up a real physical stack
→ allow normal movement/trade/mail/action behavior

SHIFT + LEFT CLICK
→ standard WoW split-stack behavior for stackable items

SHIFT CLICK WITH CHAT OPEN
→ preserve normal WoW item-link behavior rather than intercepting it

Other modified-click behavior:
→ defer to Blizzard conventions wherever feasible

IMPORTANT:

Do NOT assign Pockets navigation actions to item right-click.

Navigation belongs to Pockets controls.

Item buttons belong to WoW.

==================================================
7. HOW AGGREGATED ITEMS RESOLVE TO PHYSICAL STACKS
==================================================

An aggregate might visually show:

Potion x17

while physical bags contain:

5
5
5
2

Some actions require a real stack.

For v1:

Interactions that require physical item location operate on one real underlying stack.

Do NOT permanently bind the rendered aggregate to a single potentially stale bag/slot.

Resolve the physical stack when the interaction occurs.

Recommended resolver for manipulation:

Use the SMALLEST valid physical stack first.

Example:

20 + 20 + 3 Netherweave

Dragging aggregated Netherweave should preferably pick up the physical stack of 3.

Reason:
- less disruptive
- better for normal stack manipulation
- useful when moving/trading smaller quantities

Right-click/use may use any deterministic valid stack, but using one shared resolver where practical is preferable.

Before executing the action:
- ensure bagID/slotID still contains the expected item
- ensure stack is valid/unlocked as required
- reject stale location
- resolve another valid stack when appropriate

InventoryState changes must refresh aggregate backing data.

==================================================
8. KNOWN V1 TRADE-OFF: PHYSICAL STACK MANAGEMENT
==================================================

We intentionally accept a trade-off in v1.

Pockets makes:

5 + 5 + 5 + 2

look like:

17

This is excellent for compact inventory awareness but less useful for players deliberately maintaining multiple prepared physical stacks.

Example:
a raider may intentionally maintain potion stacks of 2–3 for quick trading.

Do NOT solve this in v1.

Assume players requiring detailed physical-stack management may use a traditional bag addon alongside Pockets.

Future possibility:

Selecting/contextually expanding an aggregate could expose:

Potion x17

[5] [5] [5] [2]

But this is explicitly deferred.

Do not compromise the primary Pockets UI for this edge case now.

==================================================
9. CAPACITY / AMMO
==================================================

GENERAL capacity:

57 / 84

ETA:

13m to full

No "~".

ETA should be visible often enough to be useful, but only when the estimator has enough evidence that the number is not wildly misleading.

If:
- insufficient data
- bag usage flat
- bag usage decreasing
- estimate highly unstable

then omit ETA.

Do not show fake precision.

Ammo capacity:

12 / 16

ONLY render Ammo status if the player has an actual equipped:
- quiver
- ammo pouch

Carrying bullets/arrows in normal bags does NOT create Ammo capacity.

Ammo bag slots remain excluded from GENERAL capacity.

Keep distinct:

Ammo category
= ammo items carried anywhere

Ammo capacity
= occupancy of an actual specialized ammo bag

==================================================
10. CATEGORY AND ALL-ITEM LAYOUT
==================================================

CATEGORY view can use a straightforward responsive item grid.

ALL ITEMS retains the more advanced categorized layout.

Use the existing dynamic packing strategy where already implemented/appropriate.

Current packing rule:

Categories normally begin on a fresh row.

If a category's final row uses LESS THAN 50% of available width, the next category may begin in the remaining space IF:

- complete next-category label fits
- category label + at least one item fit

Conceptually:

remainingWidth = rowWidth - usedWidth

canInlineNext =
    usedWidth < (rowWidth * 0.5)
    and remainingWidth >= (
        nextCategoryLabelWidth
        + gap
        + itemWidth
    )

If used width is >= 50%:
→ next category starts fresh.

Never split a category label.

This layout logic should remain modular because we expect to iterate on the packing algorithm.

==================================================
11. SEARCH
==================================================

Search exists in ALL ITEMS.

- case-insensitive item-name match
- operates on cached aggregate state
- immediate
- clear/reset action
- no bag scan because a character was typed
- no metadata refresh loop
- no recategorization pass

While searching, flattening the results into a dense aggregate grid is acceptable.

Clear search:
→ restore categorized All Items layout

==================================================
12. PHUI / VISUAL SYSTEM
==================================================

Do not independently style Pockets.

Use the shared PHUI implementation already consumed by pH and Pockets.

Reuse:
- frame/backdrop
- borders
- fonts
- colors
- padding
- spacing
- buttons
- + button
- back button treatment
- hover/pressed states
- icon-button treatment

Use actual Blizzard item icons.

The design relationship should be:

pH:
horizontal status/control surface whose geometry changes with mode

Pockets:
small square Glance surface that expands into a stable vertical navigation surface

Same design system.
Different geometry appropriate to each product.

==================================================
13. REMOVE / DEPRECATE OLD NAVIGATION MODEL
==================================================

As part of implementation, identify code belonging to the previous:

HUD → hover flyout → category item flyout

model.

Do not leave two competing navigation systems active.

Remove or retire:
- hover-triggered navigation between Pockets views
- adjacent item flyout behavior
- category-panel/item-panel mouse bridge hacks
- navigation timers used solely for hover flyouts
- multiple-window positioning logic no longer required

Preserve hover only for:
- tooltips
- ordinary visual button feedback

Do not remove reusable:
- InventoryState
- category model
- item buttons
- item pooling
- aggregate model
- search
- estimator
- PHUI primitives

==================================================
14. PERFORMANCE
==================================================

State changes should be cheap.

MENU → CATEGORY should not rescan bags.

CATEGORY → ALL should not rescan bags.

Back navigation should not rescan bags.

All views consume existing:
- InventoryState
- category aggregates
- item aggregates
- capacity state
- ETA state

No OnUpdate inventory polling.

Pool/reuse item buttons.

Do not recreate root UI on state changes.

==================================================
15. TESTING
==================================================

Add/update tests for:

STATE MACHINE
- Glance → Menu
- Menu → Category
- Menu → All
- Category → Menu
- Category → All
- All → Menu
- Escape hierarchy
- Shift-B → All
- same root frame reused

STABLE SHELL
- Menu/Category/All same width
- same header height
- same footer height
- action zones remain fixed
- no screen-position change across states

AGGREGATED ITEM INTERACTION
- normal tooltip
- right-click resolves valid physical stack
- drag resolves valid physical stack
- shift split resolves physical stack
- stale bag/slot is rejected
- resolver can choose another current stack
- smallest-stack manipulation behavior

AGGREGATION
- one stack
- multiple stacks
- split/merge
- aggregate quantity
- quantity 1 count hidden
- aggregate removed at zero

AMMO
- no quiver → no Ammo status
- ammo in normal bags → no Ammo capacity
- quiver equipped → Ammo capacity visible
- GENERAL excludes specialized ammo slots

ETA
- valid filling trend → ETA visible
- unstable/insufficient → hidden
- stable/decreasing → hidden
- no "~" formatting

SEARCH
- All-state search
- case insensitive
- clearing restores layout
- no inventory scan from search input

LEGACY NAVIGATION
- hover no longer changes Pockets state
- old adjacent flyout frames are not shown
- item hover still shows tooltip

==================================================
16. DEFINITION OF DONE
==================================================

Before declaring complete:

1. Inspect current implementation first.
2. Reuse what works instead of rebuilding unrelated systems.
3. Implement the single-root state architecture.
4. Remove/disable obsolete hover navigation.
5. Preserve standard item interactions.
6. Run luacheck.
7. Run all automated tests.
8. Run static/repository checks.
9. Verify TOC/load order.
10. Install addon for /reload testing.
11. Summarize:
    - files changed
    - old UI pieces removed
    - state-machine implementation
    - physical-stack resolver behavior
    - any Classic TBC API constraints
    - manual in-game tests I should perform

Do not stop at a design proposal.

Implement this architecture end-to-end.
