# Pockets Testing Guide

## Quick Start

1. Install the addon (`./install.sh`) and `/reload` in game.
2. Run the automated test suite: `/pockets test run`
3. Enable verbose debug logging while testing: `/pockets debug verbose on`
4. Inspect live state: `/pockets debug inventory`, `/pockets debug
   categories`, `/pockets debug estimator`, `/pockets debug events`

## Automated Domain Tests

`/pockets test run` executes every test registered with
`Pockets.Tests.TestRunner` (see `pockets/Tests/*.lua`). These are pure/
domain tests per `Pockets_TDD.md` §24.1 - they exercise category mapping,
recent-item queue bounds, and the capacity estimator's state machine
without requiring live bag contents.

Current coverage:

- **CategorizerTests** - precedence ordering (quest > ammo > junk >
  consumable > equipment > trade goods > other).
- **RecentItemsTests** - newest-first ordering, quantity preservation,
  bounded history, rejection of zero/negative deltas.
- **CapacityEstimatorTests** - `warming_up`/`filling`/`freeing`/`full`
  states, ETA omission below confidence threshold, discontinuity discount
  after a large negative sample (e.g. a vendor trip).
- **InventoryStateTests** - capacity result shape, zero-total safety,
  general/ammo pool independence, live bag/slot lookup by itemID.
- **APITests** - Recent category count is entry count (not quantity sum);
  Recent entries resolve to a live bag/slot when still carried and are
  marked non-interactive when not (UI_SPEC §9).

These can also be run outside the game with a plain Lua interpreter (no
WoW client needed) - see `Core/`, `Adapters/ItemAPI.lua`, and `API.lua`
loaded against a small `GetTime`/`GetItemInfo` stub. Useful for CI.

As bag-scan/diff logic and stack consolidation are implemented (TDD Phases
1-5), add corresponding tests here and to this coverage list.

## Test Injection Commands

Injection targets domain services directly so logic can be exercised
without performing every game action manually (`Pockets_TDD.md` §23):

```
/pockets test sample <used> <total> <secondsAgo>   - Feed the capacity estimator a sample
/pockets test category <itemID>                    - Print the category Pockets assigns an item
/pockets test recent <itemID> <quantity>            - Record a Recent Items entry
```

Example - simulate bags trending toward full:

```
/pockets test sample 40 68 180
/pockets test sample 50 68 120
/pockets test sample 60 68 60
/pockets test sample 65 68 0
/pockets debug estimator
```

## Manual Acceptance Matrix

At minimum, test each of the following before calling a phase done
(`Pockets_TDD.md` §24.3):

- [ ] Login/reload
- [ ] Bags empty / partially full / full
- [ ] Loot stackable item into an existing stack
- [ ] Loot an item that creates a new slot
- [ ] Split a stack
- [ ] Move a stack between bags
- [ ] Combine stacks
- [ ] Equip/unequip an item
- [ ] Consume an item
- [ ] Vendor/remove many items at once
- [ ] General bags fill while ammo slots remain free
- [ ] Ammunition stored in a normal bag
- [ ] Quiver/ammo pouch equipped
- [ ] Hover suppression in combat
- [ ] Click access in combat
- [ ] Shift-B in and out of combat
- [ ] Tooltip hook alongside common tooltip addons
- [ ] Automatic consolidation while items are locked (once Phase 5 lands)
- [ ] `/reload` while a flyout/full view is open

### Glance Acceptance Checks (Glance cleanup pass)

- [ ] Glance shows a small, clean bag icon centered horizontally - no
      black slot/border look, no ItemButton-style chrome
- [ ] Capacity, Full/ETA, and Gold read as one centered vertical stack
      directly below the bag icon
- [ ] Gold always shows a value and matches `/run print(GetMoney())`
      converted to gold/silver/copper (copper omitted once you have >= 1g)
- [ ] Search icon stays in the top-right corner and never shifts the
      centered stack, with or without Ammo showing
- [ ] Without an ammo bag/quiver equipped: no Ammo row, no reserved empty
      space below Gold
- [ ] With an ammo bag/quiver equipped: Ammo is the last row, below Gold,
      showing `[icon] used / total`
- [ ] Glance stays a true square in both the Ammo and no-Ammo states

### UI_SPEC Acceptance Checks (Pockets_UI_SPEC.md §16)

- [ ] HUD shows a large, recognizable square bag icon (not text-only)
- [ ] HUD width never changes as used/total digits or ETA appear/disappear
      (watch it while bags fill from empty to full)
- [ ] Category flyout width never changes as counts change (test with a
      1-digit and a 4-digit count, e.g. via `/pockets test recent`)
- [ ] Category counts stay right-aligned across rows
- [ ] HUD hover → category flyout feels immediate (no perceptible delay)
- [ ] Category hover → item panel feels immediate
- [ ] Moving the mouse from the category flyout into the item panel does
      NOT flicker-close either panel
- [ ] Moving the mouse away from the whole HUD+flyout+panel group closes
      it after a short (~150-250ms) grace period, not instantly and not
      instantly-forever
- [ ] Left-click an item button: normal pickup/equip/use behavior
- [ ] Right-click an item button: normal use behavior
- [ ] Shift-click an item button: posts the item link to chat (if a chat
      edit box is focused) like a normal bag slot
- [ ] Drag an item button to another bag slot: moves the item normally
- [ ] Drag a cursor item onto an item button: swaps/stacks normally
- [ ] Hovering an item button shows the normal GameTooltip (durability,
      comparison, etc.)
- [ ] A locked item (e.g. mid-trade) shows the normal locked/desaturated
      visual and doesn't misbehave
- [ ] Recent Items: an entry for an item you no longer carry is NOT
      clickable/draggable (no fake action)
- [ ] Recent Items: an entry for an item you still carry IS interactive and
      resolves to its current bag/slot
- [ ] Category icons are visually distinct per category and load without
      a "missing texture" question-mark
- [ ] Full inventory (Shift-B) item buttons behave identically to the
      flyout's (same click/drag/tooltip)
- [ ] Full inventory scrolls internally instead of growing past its bounds
      when many categories are populated

For each item above, confirm against the relevant PRD success criteria
(`Pockets_PRD.md` §6): how full are my bags, about how long until full,
what did I just pick up, how much of each item type, where is a specific
item, how much ammo am I carrying.

## Definition of Done Gate

Per `Pockets_TDD.md` §25.5, a feature is not complete until, in order:

1. `luacheck pockets/` passes.
2. `./scripts/static-checks.sh` passes.
3. `/pockets test run` passes.
4. Relevant manual/in-game acceptance cases above are documented as tested.
5. `./package-release.sh` succeeds.

## Reporting Issues

When reporting a Pockets issue, include:

1. WoW version (Classic Anniversary or TBC) and Pockets version (`/pockets help`).
2. Steps to reproduce.
3. Console errors, if any (`/pockets debug verbose on` first).
4. Output of the relevant `/pockets debug ...` command.
