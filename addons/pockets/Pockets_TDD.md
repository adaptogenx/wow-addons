# Pockets — Technical Design Document (TDD)

**Working name:** Pockets  
**Target:** World of Warcraft Classic TBC  
**Architecture:** standalone addon, Lua 5.1-compatible  
**Design constraint:** future shared state/core with pH, without requiring a pH refactor for v1

## 1. Technical Goals

Pockets must be small, deterministic, event-driven, and easy for a coding agent to extend without collapsing presentation, inventory state, and WoW API handling into one module.

The implementation should optimize for:

- low idle CPU usage;
- bounded memory use;
- minimal frame creation;
- zero continuous inventory polling when events are sufficient;
- graceful handling of asynchronous/temporarily unavailable item metadata;
- combat-safe access;
- stable module interfaces that can later point at shared pH/Pockets implementations;
- compatibility with the same engineering discipline already used by pH.

## 2. Confirmed pH Engineering Baseline

Pockets should begin with the same development baseline already established in pH.

The current pH repository confirms the following conventions:

- Lua 5.1 target.
- `.luacheckrc` checked into the repository and configured for WoW globals.
- `luacheck` as the required Lua static lint tool.
- Pre-commit lint hook.
- Hook setup script (`setup-hooks.sh`).
- Linting of staged Lua files before commit, with commit blocked on lint failure.
- In-game debug mode and diagnostic commands.
- Automated in-game test suite callable by slash command.
- Test-data injection commands so logic can be exercised without performing every game action manually.
- Dedicated testing documentation (`TESTING_GUIDE.md`).
- Dedicated UI rules documentation (`UI_RULES.md`).
- Install and release/package scripts.

Pockets should copy these repository-level conventions at project creation rather than adding them later.

### Required repository baseline

```text
Pockets/
├── .gitignore
├── .luacheckrc
├── README.md
├── CLAUDE.md
├── TESTING_GUIDE.md
├── UI_RULES.md
├── setup-hooks.sh
├── install.sh
├── package-release.sh
└── pockets/
    ├── Pockets.toc
    └── ...Lua/XML/assets...
```

Where practical, the initial versions of these files should be derived from pH and edited for the Pockets namespace and WoW APIs used here.

## 3. Proposed Runtime Architecture

Use four runtime layers:

```text
WoW API Adapters
      ↓
Domain State / Services
      ↓
Public Interfaces + Event Bus
      ↓
UI / Interaction
```

### 3.1 WoW API Adapters

Purpose: isolate direct Blizzard API access so the rest of the addon works against normalized Pockets data.

Candidate modules:

```text
Adapters/BagAPI.lua
Adapters/ItemAPI.lua
Adapters/CombatAPI.lua
Adapters/TooltipAPI.lua
Adapters/BindingsAPI.lua
```

Rules:

- Direct calls to bag/container APIs should be concentrated in `BagAPI`.
- Direct item-info lookups should be concentrated in `ItemAPI`.
- UI modules should not independently rescan bags.
- Adapter functions normalize API return shapes into Pockets-owned tables.
- Client-version-specific compatibility logic belongs here.

### 3.2 Domain Services

Candidate modules:

```text
Core/InventoryState.lua
Core/ItemCategorizer.lua
Core/RecentItems.lua
Core/CapacityEstimator.lua
Core/StackConsolidator.lua
Core/EventBus.lua
```

These modules should not own visible frames.

### 3.3 UI Modules

Candidate modules:

```text
UI/HUD.lua
UI/CategoryFlyout.lua
UI/ItemFlyout.lua
UI/FullInventory.lua
UI/Search.lua
UI/TooltipCounts.lua
UI/ItemButtonPool.lua
UI/Layout.lua
```

UI reads domain state and emits user intents. It should not become the source of truth for inventory.

## 4. Namespace and Dependency Model

Pockets must not require pH to load.

Use one addon namespace and avoid unnecessary globals.

Example:

```lua
local ADDON_NAME, Pockets = ...

Pockets.API = Pockets.API or {}
Pockets.Events = Pockets.Events or {}
Pockets.Services = Pockets.Services or {}
```

Only deliberately exported integration points should be global or reachable externally.

Recommended public integration root:

```lua
_G.Pockets = Pockets
```

If global exposure is undesirable, export only `PocketsAPI`; however, keeping one well-defined addon global is simpler for optional pH integration and mirrors common WoW addon practice.

## 5. Core Interfaces

The point of these interfaces is not object-oriented ceremony. They create a seam that lets copied v1 implementations later be replaced by shared pH/Pockets implementations.

### 5.1 Inventory State

```lua
InventoryState:Refresh(reason)
InventoryState:GetGeneralCapacity()
InventoryState:GetAmmoCapacity()
InventoryState:GetUtilization()
InventoryState:GetItems()
InventoryState:GetItem(itemKey)
InventoryState:GetItemsByCategory(categoryID)
InventoryState:GetCarriedQuantity(itemID)
InventoryState:GetRevision()
```

Suggested capacity return value:

```lua
{
    used = 60,
    total = 68,
    free = 8,
    utilization = 0.8824,
}
```

Ammo capacity uses the same shape but remains a distinct capacity pool.

### 5.2 Item Categorizer

```lua
ItemCategorizer:Categorize(item)
ItemCategorizer:GetDisplayCategory(item)
ItemCategorizer:GetCategoryDefinition(categoryID)
ItemCategorizer:GetCategories()
```

Recommended stable IDs:

```text
recent
equipment
consumable
trade_goods
quest
ammo
junk
other
```

The domain categorizer may record a more specific `internalCategory` or Blizzard item class/subclass while mapping it to one simplified display category.

### 5.3 Recent Items

```lua
RecentItems:Record(delta)
RecentItems:GetRecent(limit)
RecentItems:GetSince(timestamp)
RecentItems:Clear()
RecentItems:GetRevision()
```

A recent delta should represent acquisition, not a raw bag-slot mutation:

```lua
{
    itemID = 21877,
    quantity = 4,
    timestamp = 123456.7,
    itemLink = "...",
}
```

Do not treat stack movement between bags as acquisition.

### 5.4 Capacity Estimator

```lua
CapacityEstimator:AddSample(timestamp, usedSlots, totalSlots)
CapacityEstimator:GetRate()
CapacityEstimator:GetETA()
CapacityEstimator:GetConfidence()
CapacityEstimator:GetState()
CapacityEstimator:Reset(reason)
```

Suggested estimator states:

```text
warming_up
filling
stable
freeing
full
```

`GetETA()` returns seconds or `nil`; UI formatting is separate.

### 5.5 Event Bus

```lua
EventBus:Subscribe(eventName, callback, owner)
EventBus:UnsubscribeOwner(owner)
EventBus:Publish(eventName, payload)
```

Suggested domain events:

```text
POCKETS_INVENTORY_CHANGED
POCKETS_ITEM_ACQUIRED
POCKETS_CATEGORY_CHANGED
POCKETS_CAPACITY_CHANGED
POCKETS_ETA_CHANGED
POCKETS_COMBAT_STATE_CHANGED
```

These should be addon-local events, not WoW events exposed directly to consumers.

## 6. Inventory Data Model

Inventory should be represented independently of visible bag/slot layout.

Suggested normalized item record:

```lua
{
    key = "bag:slot",
    bagID = 0,
    slotID = 5,
    itemID = 21877,
    itemLink = "...",
    name = "Netherweave Cloth",
    texture = 132898,
    quantity = 20,
    quality = 1,
    maxStack = 20,
    classID = 7,
    subclassID = 5,
    isQuestItem = false,
    isLocked = false,
    bagFamily = 0,
    capacityClass = "GENERAL",
    categoryID = "trade_goods",
}
```

Important distinction:

- **Slots** model physical location and capacity.
- **Items** model presentation and quantities.
- **Aggregates** model category and item totals.

The UI should usually render aggregates or normalized records, not re-query a bag slot on every paint.

## 7. Capacity Classes

v1 supports exactly two capacity classes:

```text
GENERAL
AMMO
```

Rules:

- Backpack and unrestricted equipped bags are `GENERAL`.
- Quivers/ammo pouches are `AMMO`.
- `GENERAL` determines the primary HUD capacity and bag-full ETA.
- `AMMO` is reported separately.
- Empty ammo slots never increase general free-slot count.
- An ammo item occupying a general slot still consumes a general slot while also belonging to the Ammo display category.

Do not add generic profession-bag abstractions to UI in v1. The internal enum can be extensible, but only `GENERAL` and `AMMO` should be implemented/tested as product behavior.

## 8. Bag Scan and Diff Algorithm

Pockets needs authoritative inventory snapshots plus deltas that distinguish acquisition from movement.

### 8.1 Trigger model

Listen to the appropriate bag/container update events available in the Classic TBC client. The implementation agent must verify the exact event/API names against the target 2.5.6 client before coding.

The high-level flow:

```text
WoW bag event
  ↓
debounce coalesced updates
  ↓
scan current bags once
  ↓
normalize snapshot
  ↓
diff previous snapshot
  ↓
update InventoryState
  ↓
record true acquisitions
  ↓
update estimator
  ↓
publish domain events
  ↓
refresh only affected UI
```

Bag events can arrive in bursts. Use a short deferred refresh/debounce rather than rescanning every event individually.

### 8.2 Diffing

The diff must avoid recording these as newly acquired items:

- moving an item between bag slots;
- splitting a stack;
- combining stacks;
- automatic consolidation performed by Pockets;
- equipping/unequipping when the resulting bag delta can be reconciled;
- simple slot reordering.

Preferred acquisition calculation:

1. Aggregate old snapshot quantity by item identity.
2. Aggregate new snapshot quantity by item identity.
3. `delta = newTotal - oldTotal`.
4. Record positive deltas as acquisitions.
5. Treat negative deltas as removals; they are useful for state/ETA but not Recent.

If item identity cannot be resolved because item metadata is pending, retain a provisional entry keyed by item ID/link and reconcile when metadata becomes available.

## 9. Item Metadata and Caching

WoW item metadata is not guaranteed to be synchronously available for every newly encountered item.

Requirements:

- Inventory scanning must not fail if `GetItemInfo`-style data is incomplete.
- Cache normalized item metadata by item ID.
- Support a pending metadata state.
- Refresh classification/UI when item data becomes available.
- Do not repeatedly request/resolve the same metadata every frame.

Suggested metadata cache:

```lua
ItemCache[itemID] = {
    status = "ready" | "pending",
    name = ...,
    quality = ...,
    classID = ...,
    subclassID = ...,
    maxStack = ...,
    texture = ...,
}
```

## 10. Categorization Strategy

Pockets should begin by copying the useful pH item-category logic and making it domain-neutral.

Classification precedence matters. Recommended order:

```text
1. Quest override
2. Ammo
3. Junk / poor quality
4. Consumable
5. Equipment
6. Trade Goods
7. Other
```

Why precedence is explicit:

- quest items can belong to normal item classes but should display under Quest;
- ammunition needs a first-class category independent of physical bag location;
- poor-quality equipment should generally display as Junk if the product expectation is “junk first,” unless existing pH semantics strongly argue otherwise.

The coding agent should compare pH's current classification rules before locking the exact precedence and preserve shared semantics where doing so does not damage Pockets UX.

## 11. Bag-Full ETA Algorithm

### 11.1 Input

The estimator observes:

```text
(timestamp, used GENERAL slots, total GENERAL slots)
```

It does not estimate from number of loot messages or total item quantity.

### 11.2 Shared conceptual model with pH

Borrow pH's existing ETA philosophy:

```text
remaining work / smoothed recent progress rate
```

For bags:

```text
freeSlots = totalGeneralSlots - usedGeneralSlots
slotPressure = smoothed positive occupied-slot change / active minute
ETA = freeSlots / slotPressure
```

### 11.3 Sampling

Recommended behavior:

- Add samples when general used-slot count changes.
- Also allow sparse periodic samples while an active trend exists if needed to age history.
- Maintain a bounded rolling window.
- Give recent samples greater influence than old samples if matching pH's current estimator design.
- Detect large negative discontinuities (e.g. vendor trip) and heavily discount/reset stale positive pressure.

Do not hard-code the exact window/weighting until the coding agent has inspected pH's current ETA implementation. The goal is to copy/generalize that implementation rather than invent a parallel algorithm.

### 11.4 State rules

Suggested semantics:

```text
warming_up: not enough observations/time
filling:     statistically useful positive slot pressure
stable:      pressure near zero
freeing:     meaningful negative pressure
full:        no free GENERAL slots
```

UI output:

```text
warming_up -> no ETA
filling    -> ~20m
stable     -> omit ETA or “Stable” in expanded detail only
freeing    -> omit ETA
full       -> Full
```

The compact HUD should prefer omission to noisy text.

### 11.5 Confidence

Confidence can remain internal in v1 but should be available through the interface.

Inputs may include:

- amount of elapsed observation time;
- number of distinct slot-change observations;
- variance of observed rate;
- recency of most recent positive pressure.

The UI should only surface ETA above a minimum confidence threshold.

## 12. Automatic Stack Consolidation

This is the one intentional inventory-management behavior in v1.

### 12.1 Constraints

- Must only use APIs allowed by the target Classic TBC client.
- Must not continuously churn stacks.
- Must not fight the player while they are manually dragging an item.
- Must avoid repeated consolidation loops caused by its own bag-update events.
- Must gracefully skip locked items.
- Must not disable Pockets if consolidation is unavailable in combat or another protected context.

### 12.2 Trigger strategy

Prefer event-driven consolidation after inventory settles rather than on every bag event.

Suggested flow:

```text
inventory change
  ↓
refresh + diff
  ↓
if consolidation eligible and no item currently held
  ↓
schedule one consolidation pass
  ↓
mark consolidation transaction active
  ↓
move compatible partial stacks
  ↓
subsequent bag events refresh state but do not create Recent acquisitions
  ↓
transaction ends
```

### 12.3 Loop protection

Track a consolidation generation/token so bag changes caused by Pockets are recognized as internal mutations.

Even with that token, Recent Items should primarily rely on aggregate quantity diffing so movement never appears as acquisition.

## 13. UI Architecture

### 13.1 HUD

The HUD should be one small frame with minimal child objects.

Recommended elements:

```text
Frame
├── Bag icon / status background
├── Capacity text
└── ETA text (conditionally shown)
```

Avoid creating category/item frames until flyouts are needed.

HUD update triggers:

- capacity change;
- ETA state/value threshold change;
- settings/position change.

Do not update HUD text every frame.

### 13.2 Capacity colors

Use percentage utilization or free-slot thresholds through one centralized function.

Example interface:

```lua
Color:GetCapacityColor(utilization)
```

Exact thresholds should be constants/settings in code, not duplicated across UI modules.

Initial product-default candidate:

```text
Green  < 70% used
Yellow 70–89% used
Red    >= 90% used
```

These are implementation defaults, not a user-facing tuning system in v1.

### 13.3 Category Flyout

Render only non-empty categories except where a category is product-critical.

Each row should be reusable/poolable and contain:

```text
icon?  label  count
```

Prefer no icon if labels alone are clearer and smaller.

### 13.4 Item Flyout

Use item-button pooling rather than creating new buttons on every open.

Display information should prioritize:

- item icon;
- stack/count;
- quality border if visually useful;
- tooltip on hover.

Keep category flyout and item flyout independently closable so click navigation works in combat.

### 13.5 Full Inventory

The full view should use category sections and pooled item buttons.

Do not build one Blizzard-style bag frame per container.

Recommended layout rules:

- fixed maximum width appropriate for small screens;
- categories wrap or collapse vertically;
- no persistent sidebars;
- search row only when full view is open;
- recent section first;
- empty categories hidden;
- frame height bounded to screen with internal scrolling if necessary.

## 14. Hover vs Click Interaction State Machine

Outside combat:

```text
HUD hover/click
  → category flyout
category hover/click
  → item flyout
```

Inside combat:

```text
HUD hover
  → no action
HUD click
  → category flyout
category hover
  → no action
category click
  → item flyout
Shift-B
  → full inventory
```

Do not implement combat behavior by hiding all Pockets frames.

The interaction controller should check combat state at the moment of hover intent, not simply at addon load or frame creation.

## 15. Search

Search operates over the current `InventoryState` aggregate and should not rescan bags.

Behavior:

- case-insensitive item name substring match;
- debounced input if necessary;
- empty search restores category presentation;
- no fuzzy matcher or query parser in v1.

## 16. Tooltip Counts

Hook item tooltips conservatively.

Requirements:

- resolve the hovered item ID/link;
- read carried quantity from `InventoryState`;
- add exactly one Pockets line when quantity > 0;
- avoid duplicate lines on repeated tooltip refresh;
- do not trigger bag scans from tooltip rendering.

The tooltip module is a read-only consumer of inventory state.

## 17. Key Bindings

Ship a binding entry for the full inventory action.

Default desired behavior: Shift-B.

The coding agent must implement the binding using the target Classic TBC binding conventions and verify that the chosen default does not break expected Blizzard bindings or fail to save.

The action should call a Pockets method such as:

```lua
Pockets.API.ToggleFullInventory()
```

so the binding is not coupled directly to a frame instance.

## 18. Public API

Keep the external API intentionally small.

Proposed v1 surface:

```lua
Pockets.API.GetBagStatus()
Pockets.API.GetAmmoStatus()
Pockets.API.GetBagETA()
Pockets.API.GetRecentItems(limit)
Pockets.API.GetCategorySummary()
Pockets.API.GetCarriedQuantity(itemID)
Pockets.API.Open()
Pockets.API.Close()
Pockets.API.Toggle()
Pockets.API.Subscribe(eventName, callback, owner)
```

Example bag status:

```lua
{
    used = 60,
    total = 68,
    free = 8,
    utilization = 0.8824,
}
```

Example ETA:

```lua
{
    state = "filling",
    seconds = 840,
    confidence = 0.82,
}
```

Do not expose internal bag-slot tables as API contracts unless a real integration requires them.

## 19. SavedVariables

Persist only data that survives reload/logout usefully.

Likely account/character settings:

```lua
PocketsDB = {
    version = 1,
    settings = {
        hud = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
            locked = false,
        },
    },
}
```

Potentially persist a small amount of estimator history if pH's implementation already has safe session-resume semantics. Otherwise reset estimator samples on login/reload and rebuild quickly.

Do not persist the full inventory as an offline database in v1.

## 20. Initialization and Event Flow

Suggested startup sequence:

```text
ADDON_LOADED
  ↓
load/migrate SavedVariables
  ↓
construct services
  ↓
register WoW events
  ↓
create compact HUD
  ↓
initial inventory refresh
  ↓
initialize categories/capacity
  ↓
initialize tooltip + bindings
  ↓
publish POCKETS_READY
```

Avoid doing expensive bag scans before the game has valid container state.

## 21. Performance Requirements

Pockets is a HUD addon; idle overhead should be negligible.

Requirements:

- No `OnUpdate` inventory scanning.
- No per-frame ETA calculation.
- No per-frame tooltip/accounting work.
- Coalesce bursty bag events into one refresh.
- Cache item metadata.
- Pool/reuse item buttons and flyout rows.
- Refresh only views currently visible or invalidate them for next open.
- Keep Recent bounded.
- Keep estimator samples bounded.
- Avoid deep SavedVariables writes on every bag event.

Recommended profiling acceptance target: no visible FPS impact during normal play and no recurring CPU hotspots from Pockets while bags are unchanged.

## 22. Error Handling

Pockets should fail locally.

Examples:

- Item metadata unavailable → show icon/link if possible, category temporarily Other, then recategorize later.
- Item locked → skip consolidation for that item.
- Protected action blocked → skip that action and keep UI usable.
- Tooltip hook conflict → fail tooltip augmentation without breaking inventory state.
- Unknown bag family → treat conservatively as non-general until verified, log in debug mode.

Never hide the whole UI in response to one unavailable feature.

## 23. Debug and Diagnostics

Copy pH's philosophy of built-in diagnostics.

Proposed commands:

```text
/pockets debug on|off
/pockets debug verbose on|off
/pockets debug inventory
/pockets debug categories
/pockets debug estimator
/pockets debug events
/pockets test run
```

Potential test injection:

```text
/pockets test sample <used> <total> <secondsAgo>
/pockets test category <itemID>
/pockets test recent <itemID> <quantity>
```

Injection should target domain services directly where practical so tests do not require actual bag mutation.

## 24. Testing Strategy

### 24.1 Pure/domain tests

High-value tests:

- category mapping;
- category precedence;
- aggregate inventory diffing;
- acquisition vs movement detection;
- partial-stack movement not counted as Recent;
- capacity calculation with normal + ammo bags;
- ammo in normal bags;
- general bag full while ammo bag has free slots;
- ETA warming-up/filling/stable/freeing/full states;
- estimator reset/discount after large bag-emptying event;
- search filtering;
- tooltip quantity lookup.

### 24.2 In-game automated tests

Match pH's `/test run` pattern for tests requiring addon runtime/WoW object behavior.

### 24.3 Manual acceptance matrix

At minimum test:

- login/reload;
- bags empty/partially full/full;
- loot stackable item into existing stack;
- loot item that creates new slot;
- split stack;
- move stack between bags;
- combine stacks;
- equip/unequip item;
- consume item;
- vendor/remove many items;
- fill general bags while ammo slots remain free;
- ammunition stored in normal bag;
- quiver/ammo pouch equipped;
- combat hover suppression;
- combat click access;
- Shift-B in and out of combat;
- tooltip hook alongside common tooltip addons;
- automatic consolidation while items are locked;
- `/reload` while flyout/full view is open.

## 25. Linting and Code Analysis Baseline

This section is mandatory for the coding agent.

### 25.1 Luacheck

Pockets must include a checked-in `.luacheckrc` derived from pH's configuration.

Requirements:

- Lua 5.1 semantics.
- Known WoW Classic TBC globals declared/read appropriately.
- Pockets globals explicitly allowed rather than disabling undefined-global checking broadly.
- Third-party/global exceptions added narrowly.
- `luacheck pockets/` must pass before release.

### 25.2 Pre-commit hook

Copy pH's hook pattern:

- installed via `setup-hooks.sh`;
- runs automatically on `git commit`;
- evaluates staged `.lua` files;
- blocks commit on lint errors;
- no blanket bypass in normal workflow.

### 25.3 Syntax/load-order validation

Add a lightweight repository check that validates:

- every Lua file referenced by `Pockets.toc` exists;
- no duplicate file entries;
- required bootstrap files load before consumers;
- no accidental pH namespace/global references remain after copied code is generalized.

This can be a shell or Python script if pH does not already contain an equivalent check.

### 25.4 Static grep checks

Add repository checks for high-risk mistakes:

- `GoldPH_` / stale `pH_` copied implementation names;
- direct bag API access outside adapter modules;
- `OnUpdate` handlers in inventory/state modules;
- unexpected global assignments;
- debug `print()` left outside the debug/logging module;
- TODO/FIXME optionally reported during release packaging.

These checks should be simple enough for a coding agent to understand and maintain.

### 25.5 Agent completion gate

A coding agent must not declare a feature complete until:

```text
1. luacheck passes
2. repository/static checks pass
3. automated Pockets tests pass
4. relevant manual/in-game acceptance cases are documented as tested
5. package script succeeds
```

The same standard should apply to future pH/Pockets shared-core work.

## 26. UI Rules Baseline

Create `UI_RULES.md` on day one, modeled after pH.

Minimum rules:

- compact HUD first;
- no feature may require permanent extra screen space without explicit product approval;
- frames must remain on-screen after scaling/dragging;
- category/item presentation uses shared spacing/font/button constants;
- no UI module owns authoritative inventory state;
- no blocking of the full Pockets UI in combat;
- hover is optional convenience, click is the reliable interaction path;
- reuse/pool repeated rows and buttons;
- tooltip content remains terse.

## 27. Release/Packaging Baseline

Copy pH's install/package discipline.

Expected scripts:

```text
install.sh
setup-hooks.sh
package-release.sh
```

`package-release.sh` should:

- run lint/tests/static checks first;
- create a clean `Pockets/` addon directory/zip;
- exclude repository-only files;
- include the TOC, Lua files, XML/assets, binding file, and required docs/licenses;
- fail if validation fails.

## 28. Suggested File Structure

```text
pockets/
├── Pockets.toc
├── Bindings.xml
├── Init.lua
├── Constants.lua
├── Debug.lua
├── Events.lua
├── API.lua
│
├── Adapters/
│   ├── BagAPI.lua
│   ├── ItemAPI.lua
│   ├── CombatAPI.lua
│   └── TooltipAPI.lua
│
├── Core/
│   ├── InventoryState.lua
│   ├── ItemCategorizer.lua
│   ├── RecentItems.lua
│   ├── CapacityEstimator.lua
│   ├── StackConsolidator.lua
│   └── EventBus.lua
│
├── UI/
│   ├── Layout.lua
│   ├── HUD.lua
│   ├── CategoryFlyout.lua
│   ├── ItemFlyout.lua
│   ├── FullInventory.lua
│   ├── Search.lua
│   ├── TooltipCounts.lua
│   └── ItemButtonPool.lua
│
└── Tests/
    ├── TestRunner.lua
    ├── InventoryStateTests.lua
    ├── CategorizerTests.lua
    ├── RecentItemsTests.lua
    └── CapacityEstimatorTests.lua
```

Do not create modules purely to satisfy this tree. Merge modules when they are trivial; preserve the architectural boundaries.

## 29. Implementation Phases

### Phase 0 — Repository/Foundation

- Initialize standalone Pockets repo/addon.
- Copy/generalize pH lint, hook, debug, test, install, packaging, and UI-rule baseline.
- Establish namespace, TOC, SavedVariables, event bus, API shell.

### Phase 1 — Inventory Model

- Bag adapter.
- General/ammo capacity detection.
- Inventory snapshot + aggregate diff.
- Item metadata cache.
- Basic categorizer.
- Debug dumps and tests.

### Phase 2 — HUD + ETA

- Compact HUD.
- Capacity colors.
- Generalize/copy pH ETA implementation.
- Add estimator tests and debug view.

### Phase 3 — Recent + Flyouts

- Recent acquisition queue.
- Category summary flyout.
- Item flyout.
- Combat hover/click behavior.
- Frame/button pooling.

### Phase 4 — Full Inventory + Search

- Shift-B binding.
- Full categorized inventory.
- Simple search.
- Tooltip carried counts.

### Phase 5 — Auto Stack + Hardening

- Safe stack consolidation.
- Internal-mutation loop protection.
- Combat/locked-item edge cases.
- Performance profiling.
- Common-addon compatibility testing.
- Release packaging.

## 30. Future Shared-Core Migration

When ready to refactor pH and Pockets into shared state, preserve the interfaces defined here.

Likely shared candidates:

```text
Time/Rate Estimator
Item Metadata Cache
Item Categorizer
Recent Item / Item Delta model
Event primitives
Common compact UI primitives (later, only where truly shared)
```

Migration pattern:

```text
Pockets UI → existing interface → shared implementation
pH UI      → compatible interface → shared implementation
```

Do not make either addon require the other. If a shared library is introduced, both addons depend on the library independently.

## 31. Deferred Technical Feature: Ammo Depletion ETA

Ammo depletion ETA is deliberately separate from bag-full ETA.

Future model:

```text
remaining ammunition / smoothed ammunition-consumption rate
```

It may reuse the generic estimator interface after the shared-core work, but v1 should only ensure the architecture does not prevent that feature later.

## 32. Definition of Done for v1

Pockets v1 is ready when:

- general and ammo capacity are correctly separated;
- compact HUD accurately shows general bag utilization;
- ETA is stable enough to be useful during farming and hides itself when confidence is weak;
- Recent reports true acquisitions without treating stack moves as loot;
- categories remain simple and correct;
- flyouts are usable by hover outside combat and click during combat;
- Shift-B full inventory works in and out of combat where the client permits;
- search and tooltip counts operate from cached inventory state;
- auto-stack cannot loop or corrupt Recent history;
- idle performance is effectively negligible;
- luacheck, hooks, automated tests, static checks, and release packaging are all part of the repository from the beginning.
