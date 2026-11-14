# Hold My Fear

A Warlock addon for WoW Classic Anniversary and Forever that tracks multiple feared enemies and their debuffs, and lets you recast on the one you choose. *In development, not yet released.*

## What it does

- Tracks each enemy and gives it a raid marker and a fixed HUD row for the whole fight.
- One compact row per enemy: marker, portrait, DoT and curse icons with countdowns, a Fear timer (Normal, Recast, Critical, Broken, Expired), and the mob's name.
- Click an icon to recast that spell. It casts on your **focus**, or your **target** if you have no focus, so a row accepts the click only when it is that unit.

## On Forever

Forever hides the combat log and enemy auras from addons in combat. Timers there are **estimates** from your own casts and known spell durations. A resist, early break or dispel can't be seen, so the estimate keeps running. Raid markers can't be assigned by the addon. On Anniversary, timers are read from the combat log and auras.

## Getting started

`/hmf unlock` to move the HUD, `/hmf lock` when done. `/hmf bind <KEY>` binds a key to the focus button; `/hmf macro` creates an "HMF Focus" macro.

---

## Development

Everything above this line is the player-facing text, ready to paste into a CurseForge description once the addon is released. No CurseForge project exists yet.

**Version** 0.1.0 (in development) · **Interface** 11509, 20504, 16001 · **SavedVariables** `HoldMyFearDB`

**Install from source (macOS):** `./install.sh` installs `holdmyfear/` as HoldMyFear to every detected client. `./install-lab.sh` installs the targeting lab (`hmf-api-lab`), dev only. There is no release zip, and the addon is not in the CI release table.

Forever details: [docs/forever-feasibility.md](docs/forever-feasibility.md), [docs/forever-api-matrix.md](docs/forever-api-matrix.md), [docs/forever-test-results.md](docs/forever-test-results.md), [.plans/FOREVER.md](.plans/FOREVER.md). Casting is mouseover/focus only because nameplate tokens do not work as cast targets ([.plans/LAB_REPORT.md](.plans/LAB_REPORT.md)). Secure-casting rules are in [AGENTS.md](AGENTS.md).

### Commands

`/hmf <command>`:

| Command | What it does |
|---------|--------------|
| `unlock` / `lock` | Unlock the HUD to drag it, or lock it |
| `resetpos` | Reset the HUD position |
| `scale <n>` / `width <px>` | HUD scale and width (240 to 380) |
| `reset` | Clear all tracking now |
| `focus` | Focus button diagnostics (button, clicks, bindings, macro, current focus) |
| `macro` | Create the "HMF Focus" macro |
| `bind [KEY]` | Bind a key to the focus button |
| `arrow`, `dots`, `health`, `trace` | Diagnostics |
| `demo` | Track your current target as a row |
| `test run` | In-game test suite |
| `skip hud\|focus\|events` | Bisect switch, then `/reload` |

### Checks

```bash
luacheck holdmyfear                 # 0 warnings
bash scripts/static-checks.sh
lua tests/test_tracker.lua          # offline Core tests (also test_encounter, test_focus, test_casts, test_lab_threshold)
./install.sh                        # then verify in game
```

Optional headless UI tests (macOS, dev-only) from the repo root: `scripts/sim-install.sh`, then `scripts/sim-test.sh hmf`. They check the addon never attempts protected work in combat; the simulator does not enforce lockdown, so `/hmf test run` and real secure casting still need in-game confirmation.

Lua 5.1 only. Layout: `Adapters/` (only place for Blizzard unit/spell/combat APIs), `Core/` (no frames, no `OnUpdate`), `UI/`, `Events.lua`, `Debug.lua`, `Tests/`. See [CLAUDE.md](CLAUDE.md), [TODO.md](TODO.md), [TDD.md](TDD.md), [UI-GUIDLINES.md](UI-GUIDLINES.md), [.plans/DESIGN.md](.plans/DESIGN.md).
