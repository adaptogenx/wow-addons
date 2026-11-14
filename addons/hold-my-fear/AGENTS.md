# AGENTS.md

Process rules for agents in this repo. See `CLAUDE.md` for architecture.

## After every change

1. `luacheck holdmyfear` - 0 warnings. Never add a name to `globals` in
   `.luacheckrc` to silence a real leak; namespace it under `HoldMyFear.*`
   instead.
2. `bash scripts/static-checks.sh` - must pass.
   `lua tests/test_tracker.lua` - offline Core tests, must print PASS.
3. `git diff | grep -n '_G\.'` - only pre-approved global writes are
   `_G.HoldMyFear` (`Init.lua`) and `HoldMyFearDB`. Anything else is a leak.
4. Run `./install.sh` so the in-game copy matches.
5. Tell the user `/hmf test run` and any secure-casting behavior still need
   in-game verification - there is no headless runner, so never claim they
   passed without the user confirming.
6. If behavior changed, add/update the matching test in `Tests/*.lua`.

## Secure-casting rules

- Never change secure attributes, create secure frames, or show/hide them
  during combat (`InCombatLockdown()` checked at the moment of action).
- Pre-create secure buttons out of combat; queue attribute changes until
  `PLAYER_REGEN_ENABLED`.
