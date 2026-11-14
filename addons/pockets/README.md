# Pockets: Minimal Bag HUD

A compact bag HUD for WoW Classic with inventory categories, recent loot, gold, and bag-full estimates. Expand it when you need your inventory, collapse it when you don't.

## At a glance

- **Bag capacity**: used and free slots with a color-coded indicator.
- **Time until full**: estimated from your recent activity.
- **Recent items**: your most recently acquired items.
- **Gold, ammo and supplies**: gold, ammo (quivers and pouches tracked separately), soul shards, water, and optionally food.
- **Movable HUD**: small, and stays out of your way.

## Inventory

- **Categories**: Recent, Equipment, Consumables, Trade Goods, Quest Items, Ammunition, Junk, Other. View one grid or a category list.
- **Search** your bags by item name as you type.
- **Loot history**: timestamped log of items and money acquired.
- **Normal item actions**: right-click to use, drag to move, Shift-click to split. Standard tooltips, plus how many of the item you carry.
- **Discard First**: at 90% full, suggests the lowest-value stacks to throw away. Click one, then "Discard". It never suggests quest items, ammo, your Hearthstone, tools, recipes or items with unknown value.
- **Vendors and mail**: sell cursor at vendors; right-click sells weapons and armor; right-click with a mail composer open attaches every stack.
- **Combat-aware**: the bag window scrolls in combat. On Forever it pages by default, to avoid blocked-action errors.
- **Resizable bag window**, movable apart from the HUD. Size is remembered per character.

Supported: Classic Anniversary, TBC Classic, and Forever.

## Controls

- **Shift-B** opens or closes the full inventory. It is bound only if free; change it in Key Bindings.
- **Click the HUD** to expand. **Hover a category** to browse its items outside combat.

## Commands

`/pockets` (or `/pk`):

- `show`: show or hide the HUD
- `view [grid|list]`: grid (default) or category list
- `bags [on|off]`: clicking the HUD opens your regular bags instead (default off)
- `panel [separate|attached|reset]`: drag the panel apart from the HUD (default), keep it attached, or reset position and size
- `combatscroll [pages|smooth]`: Forever only, how the grid moves in combat
- `food [on|off]`: food count (default off)
- `supplies [on|off]`: soul shard and water counts
- `recentpreview [on|off]`: large preview when hovering Recent items (default off)
- `help`: list commands

Use `/pockets bags on` to run Pockets as a HUD alongside your usual bag addon.

## Part of the pH family

Pockets shares a design with [pH: Per Hour Metrics](https://www.curseforge.com/wow/addons/ph-per-hour-metrics). Each works on its own.

---

## Development

Everything above this line is the player-facing text, kept in sync with the [CurseForge page](https://www.curseforge.com/wow/addons/pockets-minimal-bag-hud). Update both on user-visible changes. Release notes live in [FEATURES.md](FEATURES.md).

**Version** 1.3.0 · **Interface** 11509, 20504, 16001 · **SavedVariables** `PocketsDB`, `PocketsCharDB`

**Install from source (macOS):** `./install.sh` installs to every detected client (`_anniversary_`, `_forever_`, `_classic_beta_`); `./install.sh <path>` to one AddOns folder.

### Architecture

Four runtime layers:

```
WoW API Adapters (Adapters/)
      v
Domain State / Services (Core/)
      v
Public interface + Event Bus (API.lua, Core/EventBus.lua)
      v
UI / Interaction (UI/)
```

```
pockets/
├── Pockets.toc    Init.lua  Constants.lua  Events.lua  API.lua  Debug.lua
├── Bindings.xml   Shift-B (not listed in the TOC)
├── Adapters/      isolated WoW API access (bags, items, mail, money, combat, tooltip, bindings)
├── Core/          domain services, no frames
├── UI/            HUD, shell, search, loot log, item buttons, tooltip counts
├── Shared/UI/     generated from shared/ui; never edit here
└── Tests/         in-addon test runner and domain tests
```

Only `Adapters/BagAPI.lua` may call bag APIs directly. Only `_G.Pockets`, `PocketsDB` and `PocketsCharDB` may be written as globals.

### Commands for development

From the repo root (see the top-level [README](../../README.md)):

```bash
scripts/lint.sh           # luacheck (0 warnings) + static checks
scripts/test.sh           # offline + packaging tests
scripts/build.sh pockets  # dist/pockets.zip
```

Also: `./scripts/static-checks.sh` (architecture rules luacheck cannot express) and `./setup-hooks.sh` (pre-commit hook). In-game tests: `/pockets test run` (not covered by CI). See [TESTING_GUIDE.md](TESTING_GUIDE.md).

Releases: push a `pockets-v<version>` tag. The version must match the TOC and the `## <version>` section of FEATURES.md becomes the release notes.

## Reference documents

[CLAUDE.md](CLAUDE.md) · [AGENTS.md](AGENTS.md) · [UI_RULES.md](UI_RULES.md) · [Pockets_PRD.md](Pockets_PRD.md) · [Pockets_TDD.md](Pockets_TDD.md) · [Pockets_UI_SPEC.md](Pockets_UI_SPEC.md) · [Pockets_Forever_M1.md](Pockets_Forever_M1.md) · [Pockets_Forever_M2.md](Pockets_Forever_M2.md)

Non-goals: bank, guild bank, auction house, auto-sell, custom categories, advanced search, skins, plugin ecosystem. See PRD §4.
