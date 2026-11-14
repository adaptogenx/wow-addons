# sim-tests (DEV ONLY)

Optional tests run in [wow-ui-sim](https://github.com/Osso/wow-ui-sim) (GPL-3.0, Rust).
Never shipped: lives outside `addons/*/<addon>/`, binary installed to `~/tools/wow-ui-sim`.
Not part of `lint.sh` / `test.sh` / `build.sh` / release workflows.
`tests/test_packaging.sh` fails if a zip contains sim artifacts.

    scripts/sim-install.sh        # once; pinned v0.1.40 forever build, sha256-checked
    scripts/sim-test.sh [ph|pockets|hmf]

Needs a local WoW install (Blizzard UI via CASC). Override with `WOW_INSTALL_PATH`.
Blizzard_* Lua errors in the output are sim noise; only the test summary matters.
Sim passing does NOT replace in-game `/pockets test run`.

## Notes
- `hmf` (Hold My Fear) is handled inside `sim-test.sh`, not `scripts/lib.sh`, so it stays out of build/lint/release.
- The sim does NOT enforce combat lockdown (protected calls in combat succeed). HMF tests use
  `A_Admin.SetInCombat` and assert the addon never *attempts* protected work in combat.
- Test files can reload an addon source file (`io.open` + `loadstring`) to get a fresh module, and spy on `CreateFrame`.
- `assertMatches(value, pattern)`.
