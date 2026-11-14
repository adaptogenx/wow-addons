# WoW Addons

Small, focused addons for **World of Warcraft Classic Anniversary** (TBC-compatible) and the **Forever** client. Each addon is independently installable, versioned and released. No addon depends on another.

## Addons

| Addon | What it does | Version | Client interface |
|-------|--------------|---------|------------------|
| [**pH**](addons/ph/) | Session-based gold-per-hour tracker. Double-ledger accounting (no double counting), real-time metrics, minimizable HUD, conservative item valuation. | 1.7.1 | 11504, 16001 |
| [**Pockets**](addons/pockets/) | Minimal bag HUD: how full are my bags, how long until they're full, what did I just pick up. Auto-categorization, Discard First, loot log. | 1.3.0 | 11509, 20504, 16001 |
| [**Hold My Fear**](addons/hold-my-fear/) | Warlock helper that tracks multiple feared enemies and their debuffs, with one-click recasting via focus/target. *In development, not yet released.* | 0.1.0 | 11509, 20504, 16001 |

## Install

**Releases:** download the zip for an addon from [GitHub Releases](../../releases) (tags `ph-v*`, `pockets-v*`) and extract it into `World of Warcraft/<client>/Interface/AddOns/`.

**From source (macOS):** run `./install.sh` inside an addon folder (for example `addons/pockets/`). It syncs shared code and copies the addon into every detected client's `AddOns` directory. Pass a path to install to one place only.

## Repository layout

```
addons/
  ph/              pH addon (source in addons/ph/ph/)
  pockets/         Pockets addon (source in addons/pockets/pockets/)
  hold-my-fear/    Hold My Fear addon (source in addons/hold-my-fear/holdmyfear/)
shared/ui/         Canonical shared UI library (PHUI). Copied into each addon; never edit the copies.
scripts/           lint, test, build, sync-shared
tests/             shared-code and packaging tests
sim-tests/         optional dev-only headless tests (see below)
```

## Development

Requirements: `lua` 5.4, `luacheck`, `zip`. All addon code is Lua 5.1 syntax.

```bash
scripts/sync-shared.sh   # copy shared/ui into each addon (CI fails on stale copies)
scripts/lint.sh          # luacheck + shared-code boundary checks
scripts/test.sh          # offline tests + packaging checks
scripts/build.sh pockets # build dist/pockets.zip (or: ph)
```

Rules for contributors and agents are in [AGENTS.md](AGENTS.md). In-game suites (`/pockets test run`, `/ph test run`) are not covered by CI and need manual verification in a client.

### Optional: headless UI tests

`scripts/sim-install.sh` then `scripts/sim-test.sh [ph|pockets|hmf]` runs tests in [wow-ui-sim](https://github.com/Osso/wow-ui-sim) on macOS (Apple Silicon, needs a local WoW install). It is dev-only: not part of lint/test/build, never shipped, and packaging tests fail if it leaks into a release zip. See [sim-tests/README.md](sim-tests/README.md).

## Releases

Pushing a tag `ph-v<version>` or `pockets-v<version>` validates that addon, builds its zip, publishes a GitHub Release, and uploads to CurseForge when configured. The tag version must match the TOC `## Version`.
