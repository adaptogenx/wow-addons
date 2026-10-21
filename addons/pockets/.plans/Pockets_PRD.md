# Pockets — Product Requirements Document (PRD)

**Working name:** Pockets  
**Product family:** pH  
**Target game:** World of Warcraft Classic TBC  
**Status:** v1 planning

## 1. Product Summary

Pockets is a minimal, opinionated bag HUD for World of Warcraft. Its primary purpose is to let a player understand and interact with their carried inventory without opening a large traditional bag window.

The product is intentionally not a full Bagnon/Baganator replacement. It focuses on visibility, categorization, compact interaction, and capacity awareness while avoiding broad inventory-management scope.

The central product question is:

> Can the player understand what they are carrying, how much room remains, and whether they need to stop farming, without opening a large inventory window?

## 2. Product Principles

- **Minimal screen footprint.** The normal state is a tiny persistent HUD.
- **Progressive disclosure.** HUD → categories → items → full inventory.
- **Opinionated defaults.** Useful categorization without a category editor or configuration burden.
- **Inventory visibility, not inventory automation.** Pockets presents and organizes inventory; it does not become a vendor, bank, auction, or mail addon.
- **Combat-safe, not combat-disabled.** The interface remains accessible in combat; only hover-triggered expansion is suppressed.
- **Standalone from pH.** Pockets ships independently, but its internal interfaces are deliberately designed so pH and Pockets can share state and implementation later.
- **Small-screen first.** Every feature must justify its screen cost.

## 3. Core Features

### 3.1 Compact Bag HUD

The default Pockets experience is a single compact bag indicator.

Example:

```text
[bag] 55 / 70   ~20m
```

Requirements:

- Shows used / total **general-purpose bag slots**.
- The player backpack and normal equipped bags form one capacity pool named **Bags**.
- Color state transitions from green → yellow → red as free capacity falls.
- Shows bag-full ETA when the estimator has sufficient confidence.
- Is movable.
- Requires effectively no initial configuration.

### 3.2 Time Until Bags Full

Pockets estimates when general-purpose bags will become full using a generalized form of pH's progress/ETA logic.

Requirements:

- Measure **occupied-slot pressure over time**, not raw item pickup rate.
- Use a rolling/smoothed rate to avoid reacting excessively to short spikes.
- Ignore specialized ammo capacity when calculating general bag ETA.
- Correctly handle decreasing utilization after selling, destroying, mailing, consuming, or otherwise removing items.
- Show no estimate when insufficient history exists.
- Show an appropriate stable/no-pressure state when the player is not trending toward full bags.
- Never fabricate a precise-looking ETA from weak data.

### 3.3 Recent Items

Recent items are a first-class view, not just another category.

Requirements:

- Track newly acquired items.
- Display newest first.
- Preserve quantity acquired.
- Maintain a bounded recent-item history queue.
- Allow later evolution toward session-aware history shared with pH.

### 3.4 Automatic Categories

Pockets automatically categorizes carried items into a deliberately small taxonomy.

Initial categories:

- Recent
- Equipment
- Consumables
- Trade Goods
- Quest
- Ammo
- Junk
- Other

Requirements:

- Categorization is automatic.
- No category editor in v1.
- The internal categorization model should be generalized from the existing pH item categorization wherever practical.
- The core categorizer may support richer internal metadata than the UI exposes, allowing pH and Pockets to present different category groupings later.

### 3.5 Progressive Flyout UI

Primary interaction model:

```text
HUD → Categories → Items
```

Requirements:

- Click or hover the HUD outside combat to reveal category summary.
- Category summary shows category name and useful count/quantity.
- Hovering or clicking a category outside combat reveals its contained items.
- Clicking remains available in combat.
- Hover-triggered expansion is disabled in combat.
- Flyouts must remain compact and avoid covering large areas of the screen.

Example:

```text
Recent          7
Consumables    12
Equipment       5
Trade Goods    23
Quest           3
Ammo          614
Junk            4
Other           2
```

### 3.6 Full Inventory View

A compact full inventory remains available as an escape hatch.

Requirements:

- Default key binding: **Shift-B**.
- Binding is user-assignable.
- Displays all carried inventory grouped by Pockets categories rather than physical bag layout.
- Keeps Recent prominently available.
- Uses normal WoW item interactions and tooltips wherever permitted by the client.
- Optimized for information density and small screens.
- Does not recreate one panel per physical bag.

### 3.7 Search

Search exists only in the full inventory view.

Requirements:

- Simple item-name matching.
- Filters current carried inventory.
- No advanced Boolean/query language in v1.
- No persistent search box in the compact HUD or category flyout.

### 3.8 Automatic Stack Consolidation

Pockets automatically consolidates partial stacks where the WoW API safely permits it.

Requirements:

- No user-facing sort system.
- No configurable sort order.
- Consolidate compatible partial stacks automatically.
- Respect locked/protected items and client restrictions.
- Never block or disable the rest of the UI when consolidation cannot run.
- Physical slot ordering remains an implementation detail because the presentation layer is category-based.

### 3.9 Ammo Bag Support

Ammo is the only specialized bag type supported in v1.

Conceptual capacity model:

```text
Bags    60 / 68    ~14m
Ammo    12 / 16
```

Requirements:

- Backpack + normal bags contribute to **Bags**.
- Quivers/ammo pouches contribute to **Ammo** only.
- Free ammo slots do not count as free general-purpose bag capacity.
- Ammo items are categorized as Ammo regardless of whether they are physically stored in an ammo bag or a normal bag.
- Herb, enchanting, mining, soul, and other specialized bags are deferred.

### 3.10 Tooltip Inventory Counts

Pockets adds a compact carried-count line to item tooltips.

Example:

```text
Netherweave Cloth
...
Pockets: 63
```

Requirements:

- Count only currently carried inventory in v1.
- Do not introduce a cross-character inventory database.
- Keep tooltip augmentation minimal.

### 3.11 Combat Behavior

Pockets remains accessible during combat.

Requirements:

- HUD remains visible and updates.
- Clicking the HUD works.
- Clicking categories works where permitted.
- Shift-B remains usable.
- Full inventory remains accessible.
- Hover-triggered expansion is disabled during combat.
- Individual protected/restricted actions degrade independently.
- Do not hide or disable the whole addon merely because `InCombatLockdown()` is true.

### 3.12 pH-Compatible Architecture

Pockets is a separate addon and does not require pH.

For v1:

- Copy relevant pH estimator and item-classification concepts into Pockets.
- Generalize them inside Pockets rather than refactoring pH first.
- Hide implementations behind stable interfaces.
- Expose a small Pockets API/event surface suitable for future pH integration.

Future target:

```text
pH ───────┐
          ├── shared core/state
Pockets ──┘
```

The later shared-core migration should not require major changes to Pockets UI consumers.

## 4. Explicitly Out of Scope for v1

- Bank replacement
- Guild bank
- Cross-character inventory
- Mail integration
- Auction-house integration
- Auto-sell junk
- Custom categories
- Category editor
- User-defined sorting rules
- Advanced search syntax
- Profession/specialized bags other than ammo bags
- Skins/themes system
- Plugin ecosystem
- Large configuration UI

## 5. Future Roadmap Note

### Ammo Depletion ETA

A separate future feature may estimate approximately how long until the player runs out of ammunition based on recent ammunition consumption rate.

This is explicitly **not** part of the v1 bag-capacity/time-to-full estimator.

## 6. Success Criteria

Pockets v1 succeeds if a player on a small screen can spend most of a farming/leveling session with only the compact HUD visible and can answer the following without opening a traditional bag layout:

- How full are my bags?
- About how long until they are full?
- What did I just pick up?
- How much of each major item type am I carrying?
- Where is a specific carried item?
- How much ammo am I carrying?

The product should feel faster and quieter than a traditional all-in-one bag addon, not more configurable.
