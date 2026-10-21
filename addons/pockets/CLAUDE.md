# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Pockets is a World of Warcraft Classic addon (Anniversary is the primary
target; also loads on TBC via a second declared Interface version): a
minimal, opinionated bag
HUD. It shows used/total general-purpose bag slots, an ammo pool tracked
separately, a bag-full ETA, automatic item categorization, and a progressive
disclosure UI (HUD → categories → items → full inventory). It is not a
Bagnon/Baganator replacement - see `Pockets_PRD.md` §4 for explicit non-goals.

Pockets is a standalone addon and does not require pH to load, but is
architected so pH and Pockets can share core implementations later
(`Pockets_TDD.md` §4, §30).

**Source of truth for scope/behavior**: `Pockets_PRD.md` (product),
`Pockets_TDD.md` (technical design), and `Pockets_UI_SPEC.md` (exact UI
geometry/icons/hover behavior). When in doubt about a requirement, re-read the relevant
section number referenced in code comments before guessing.

## UI Design

Follow the guidelines in [UI_RULES.md](UI_RULES.md) when creating or
modifying any UI component.

## Architecture

Four runtime layers (`Pockets_TDD.md` §3):

1. **Adapters/** - the only place allowed to call Blizzard bag/item/combat/
   tooltip/binding APIs directly. Everything else consumes normalized
   Pockets-owned tables. `scripts/static-checks.sh` enforces that bag API
   calls stay inside `Adapters/BagAPI.lua`.
2. **Core/** - domain services with no visible frames: `EventBus`,
   `InventoryState`, `ItemCategorizer`, `RecentItems`, `CapacityEstimator`,
   `StackConsolidator`.
3. **API.lua / Core/EventBus.lua** - the public interface. `Pockets.API.*`
   is the intentionally small external surface (`Pockets_TDD.md` §18);
   domain events (`POCKETS_*`) are addon-local, not raw WoW events.
4. **UI/** - reads domain state and emits user intents; never becomes the
   source of truth for inventory. Frames/buttons are pooled
   (`UI/ItemButtonPool.lua`), not recreated per open.

### Namespace

Everything hangs off one addon-local table, `Pockets` (from `local
ADDON_NAME, Pockets = ...`), also exposed as `_G.Pockets` for optional
future pH integration (`Pockets_TDD.md` §4). Sub-tables: `Pockets.API`,
`Pockets.Services`, `Pockets.Adapters`, `Pockets.UI`, `Pockets.Tests`,
`Pockets.Constants`, `Pockets.Debug`.

### Capacity model

General capacity is plain bags only (`Constants.CAPACITY_CLASS.GENERAL`).
Every specialized bag class is its own separate pool, detected from the
equipped bag item itself (`BagAPI:GetBagClass`): `ammo`, `reagents` (the
dedicated reagent slot, `Enum.BagIndex.ReagentBag`, feature-detected),
and profession bags (herbs, mining, skinning, ...). They are shown as
Glance tabs and never counted in the main bag count or ETA. An ammo item in
a normal bag still occupies a general slot but displays under the Ammo
category - capacity class and display category are tracked independently.

### Categorization precedence (`Pockets_TDD.md` §10)

1. Quest override
2. Ammo
3. Junk / poor quality
4. Consumable
5. Equipment
6. Trade Goods
7. Other

"Recent" is a first-class view (`RecentItems`), not a category the
categorizer assigns.

### Acquisition vs. movement (`Pockets_TDD.md` §8.2)

`InventoryState:Refresh()` diffs aggregate per-itemID totals between scans,
not raw slot contents. Only positive total deltas become `RecentItems`
entries - this is what prevents stack splits/combines/bag moves from
appearing as loot.

### Bag-full ETA (`Pockets_TDD.md` §11)

`CapacityEstimator` observes `(timestamp, usedGeneralSlots, totalGeneralSlots)`
samples only - never loot-message counts or item quantities. States:
`warming_up`, `filling`, `stable`, `freeing`, `full`. The HUD only shows an
ETA in the `filling` state above a confidence threshold; it prefers
omission to a noisy/fabricated number.

## Development Guidelines

### WoW Addon Development Context

- Lua 5.1. `Pockets.toc` declares `## Interface: 11509, 20504` - Anniversary
  (11509) first since it's the primary target, TBC (20504) second for
  compatibility. Update the Anniversary number when the client patches.
- `GetItemInfo`-style lookups are not guaranteed synchronous; always go
  through `Adapters/ItemAPI.lua`'s cache, which tracks a `pending` state.
- Combat state (`InCombatLockdown()`) must be checked at the moment of
  interaction, not cached at load/frame-creation time
  (`Pockets_TDD.md` §14). Never hide the whole UI just because combat is
  active - only hover-triggered expansion is suppressed.
- No `OnUpdate` polling for inventory/estimator work; bag events are
  debounced into one coalesced `InventoryState:Refresh()` (see
  `Events.lua`). `scripts/static-checks.sh` fails the build if an
  `OnUpdate` handler appears under `Core/`.

### Data Integrity Rules

1. Slots model physical location/capacity; items model presentation/
   quantity; aggregates model category/item totals. UI should render
   aggregates, not re-query a bag slot on every paint.
2. `InventoryState` is the single source of truth other modules read from;
   UI modules must not rescan bags themselves.
3. Keep `RecentItems` and `CapacityEstimator` sample history bounded
   (`Constants.RECENT_ITEMS_MAX`, `Constants.ESTIMATOR_SAMPLE_WINDOW_MAX`).

### Edge Cases (v1 scope)

- General bag full while ammo bag has free slots: reported independently,
  not blended into one number.
- Large negative discontinuity (vendor trip): `CapacityEstimator` discounts/
  resets stale positive pressure rather than showing a stale ETA.
- Locked items: skipped by `StackConsolidator`, never block the rest of the
  UI.
- Missing item metadata: categorize conservatively (falls through
  precedence to `other`) and recategorize once `ItemAPI` resolves it.

## Non-Goals (v1)

See `Pockets_PRD.md` §4: bank/guild bank, cross-character inventory, mail,
auction house, auto-sell junk, custom categories/category editor,
user-defined sorting, advanced search syntax, non-ammo specialized bags,
skins/themes, plugin ecosystem, large configuration UI.

## Reference Documents

- `Pockets_PRD.md` - product requirements, success criteria
- `Pockets_UI_SPEC.md` - UI implementation spec; authoritative for pixel
  geometry, verified icon sourcing, and hover/combat behavior
- `Pockets_TDD.md` - full technical design, phased implementation plan (§29),
  definition of done (§32)
