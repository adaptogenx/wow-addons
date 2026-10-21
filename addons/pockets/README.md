# Pockets

A minimal, opinionated bag HUD for World of Warcraft Classic (Anniversary
focus, TBC-compatible). Pockets
answers "how full are my bags, how long until they're full, and what did I
just pick up" without opening a traditional bag window.

**Current status**: Phase 0 (repository/foundation) complete. See
`Pockets_TDD.md` §29 for the phased implementation plan.

## Supported Clients

One addon, one TOC (`## Interface: 11509, 20504, 16001`):

- WoW Classic Anniversary (11509) - primary
- WoW TBC Classic (20504)
- WoW Forever beta (16001)

## Installation

### macOS (Automated)

```bash
./install.sh
```

Installs to every detected Anniversary (`_anniversary_`) and Forever beta
(`_classic_beta_`) AddOns folder. Pass a path to install to just one.

### Manual Installation (macOS & Windows)

1. Copy the `pockets/` directory to your WoW AddOns folder:
   - **Windows**: `World of Warcraft/_anniversary_/Interface/AddOns/` (`_classic_` for TBC, `_classic_beta_` for Forever)
   - **Mac**: `/Applications/World of Warcraft/_anniversary_/Interface/AddOns/` (`_classic_` for TBC, `_classic_beta_` for Forever)
2. Restart WoW or `/reload` if already in-game.
3. Type `/pockets help`.

## Quick Start

```
/pockets show     - Show/hide the compact HUD
Shift-B           - Toggle the full categorized inventory view
/pockets help     - List commands
```

Shift-B is bound on first login only if unbound; reassign it under
Key Bindings > AddOns > Pockets. Known client limitations:
[FOREVER_LIMITATIONS.md](FOREVER_LIMITATIONS.md).

Hover or click the HUD outside combat to see the category summary; click
works in combat too. Hovering or clicking a category reveals its items.

## Commands

- `/pockets show` - Show/hide the HUD
- `/pockets help` - Show user commands
- `/pockets help dev` - Show debug/testing commands

### Debug Commands

- `/pockets debug on|off` - Enable/disable debug mode
- `/pockets debug verbose on|off` - Enable/disable verbose logging
- `/pockets debug inventory` - Dump current inventory state
- `/pockets debug categories` - Dump category summary
- `/pockets debug estimator` - Dump capacity estimator state
- `/pockets debug events` - Dump EventBus subscriber counts

### Test Commands

- `/pockets test run` - Run the automated test suite
- `/pockets test sample <used> <total> <secondsAgo>` - Inject a capacity sample
- `/pockets test category <itemID>` - Print the category Pockets would assign an item
- `/pockets test recent <itemID> <quantity>` - Inject a Recent Items entry

## Architecture

Pockets uses four runtime layers (see `Pockets_TDD.md` §3):

```
WoW API Adapters (Adapters/)
      v
Domain State / Services (Core/)
      v
Public Interfaces + Event Bus (API.lua, Core/EventBus.lua)
      v
UI / Interaction (UI/)
```

See [CLAUDE.md](CLAUDE.md) for module-by-module guidance and
[UI_RULES.md](UI_RULES.md) for the compact-HUD-first interaction rules.

## Development

### Linting

This project uses [luacheck](https://github.com/lunarmodules/luacheck) for
static analysis, plus a repository-level static-check script for
architectural rules that luacheck can't express.

**Install luacheck:**
```bash
brew install luacheck
```

**Run linting/checks manually:**
```bash
luacheck pockets/
./scripts/static-checks.sh
```

**Setup hooks:**
```bash
./setup-hooks.sh
```

This installs a pre-commit hook that runs luacheck and the static checks on
staged `.lua` files. Blocks commit on failure; bypass with `git commit
--no-verify` (not recommended).

### Testing

See [TESTING_GUIDE.md](TESTING_GUIDE.md).

### Packaging a release

```bash
./package-release.sh
```

Runs luacheck and static checks first, then produces
`releases/pockets-<version>.zip`.

## Files Structure

```
pockets/
├── Pockets.toc          - Addon manifest
├── Bindings.xml         - Shift-B keybinding
├── Init.lua             - Namespace bootstrap
├── Constants.lua        - Shared constants (categories, colors, events)
├── Events.lua           - WoW event wiring, startup sequence, slash commands
├── API.lua              - Small public integration surface
├── Debug.lua            - Debug/diagnostic commands
├── Adapters/            - Isolated WoW API access (bags, items, combat, tooltip, bindings)
├── Core/                - Domain services (no visible frames)
├── UI/                  - HUD, flyouts, full inventory, search, tooltip counts
└── Tests/                - In-addon test runner + domain tests
```

## Non-Goals (v1)

See `Pockets_PRD.md` §4 for the full list (bank, guild bank, auction house,
mail, auto-sell, custom categories, advanced search, non-ammo specialized
bags, skins/themes, plugin ecosystem, large config UI).

## Reference Documents

- [Pockets_PRD.md](Pockets_PRD.md) - Product requirements
- [Pockets_TDD.md](Pockets_TDD.md) - Technical design
- [Pockets_UI_SPEC.md](Pockets_UI_SPEC.md) - UI implementation spec (fixed
  geometry, icon sourcing, hover behavior, real item buttons)
