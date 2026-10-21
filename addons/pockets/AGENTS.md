# AGENTS.md

Process rules for agents in this repo. See `CLAUDE.md` for architecture.

## After every change

1. `luacheck pockets` - 0 warnings. Never add a name to `globals` in
   `.luacheckrc` to silence a real leak; namespace it under `Pockets.*`
   instead.
2. `bash scripts/static-checks.sh` - must pass.
3. `git diff | grep -n '_G\.'` - only pre-approved global writes are
   `_G.Pockets` (`Init.lua`) and `PocketsDB`/`PocketsCharDB`. Anything
   else is a leak (see `Shared/PHUI.lua` history: it used to publish
   `_G.PHUI` and collided with pH's own copy, blanking the HUD).
4. Tell the user `/pockets test run` still needs to be run in-game -
   there's no headless runner, so never claim the test suite passed
   without them confirming it.
5. If behavior changed, add/update the matching test in `Tests/*.lua`.
