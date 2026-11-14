# pH: Per Hour Metrics

Measure your gold, XP, honor and reputation per hour and track progress toward your next milestone. Works on WoW Classic Anniversary and Forever.

## Getting started

- `/ph start`: begin a session
- `/ph stop`: stop and save it
- `/ph pause` / `/ph resume`: pause or resume
- `/ph history`: open session history
- `/ph help`: list all commands

You can also control sessions from the HUD. `/ph show` shows or hides it.

## What it tracks

- **Gold per hour**: income and expenses (loot, vendor sales, repairs, quests, travel), estimated item value, gathering, pickpocketing and lockboxes. Cash and inventory are accounted separately, so nothing is counted twice, and item values are conservative.
- **XP per hour**: rate, sources and time to next level.
- **Reputation per hour**: rep and rate by faction, time to next standing, potential rep from turn-in items, and turn-in progress messages (`/ph repnotify`).
- **Honor per hour**: honor earned, rate and honorable kills.

## HUD

A collapsed mode with minimal metric bars and an expanded mode with detailed cards. Live pace indicators, sparklines, tooltips, and a movable Classic-style frame.

## Session automation

Pick a profile: Manual, Balanced or Hands-Free (`/ph auto profile <name>`). Each trigger can start a session, prompt you, or do nothing (`/ph auto ui`). Sessions survive reloads and logouts, and paused time is not counted.

## History

Browse, filter and sort sessions across characters, with Summary, Items, Gathering and Compare views. Archive, merge and delete sessions; `/ph history undo` reverses the last action for 30 seconds.

## Optional pricing

TradeSkillMaster prices are used for item valuation if installed. pH works without it.

## Troubleshooting

- HUD not showing: `/ph show`.
- Session missing after reload: check SavedVariables are enabled.
- Something looks off: `/ph debug verbose on`, then `/ph debug dump`.

---

## Development

Everything above this line is the player-facing text, kept in sync with the [CurseForge page](https://www.curseforge.com/wow/addons/ph-per-hour-metrics). Update both on user-visible changes.

**Version** 1.7.1 · **Interface** 11504, 16001 · **SavedVariables** `pH_DB_Account` (account), `pH_Settings` (per character)

**Install from source (macOS):** `./install.sh` installs to every detected client; `./install.sh <path>` to one AddOns folder. It syncs shared code first and writes `.install_info`.

Run from the repo root (see the top-level [README](../../README.md)):

```bash
scripts/lint.sh          # luacheck (ph uses a warning-count ratchet) + shared checks
scripts/test.sh          # offline tests incl. addons/ph/tests/*.lua
scripts/build.sh ph      # dist/ph.zip
```

In-game: `/ph debug on`, then `/ph test run`. Inject data without playing: `/ph start`, `/ph test loot 1000`, `/ph test repair 250`, `/ph status`. In-game suites are not covered by CI.

Pre-commit luacheck hook: `./setup-hooks.sh`.

Lua 5.1 syntax only. The shared UI in `ph/Shared/UI/` is generated from `shared/ui/`; never edit it here.

## Documentation

- [CLAUDE.md](CLAUDE.md): architecture and module guidance
- [TESTING_GUIDE.md](TESTING_GUIDE.md), [UI_RULES.md](UI_RULES.md), [TODO.md](TODO.md)
- [.plans/GoldPH_TDD.md](.plans/GoldPH_TDD.md): technical design
- [FOREVER_M1.md](FOREVER_M1.md), [FOREVER_M2.md](FOREVER_M2.md), [FOREVER_M3.md](FOREVER_M3.md): Forever client findings
