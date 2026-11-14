# Hold My Fear Feature Log

Player-facing changes, newest first. Written to paste into release notes.

## 0.1.0

First test release (Warlock only).

### What it does
- Tracks every enemy you Fear (or that fights you) in a compact list: one row per mob with its portrait, your DoTs and curses, a Fear countdown, and its name.
- Each mob keeps the same row and raid marker for the whole fight, so rows never jump around.
- DoT and curse icons drain from right to left as they run out. Expired ones stay (greyed, red frame) so you can see what to recast.
- Fear icon sits at the right of every row with whole-second countdown. The border changes for Normal, Recast soon, Critical, Broken and Expired.
- Focus helper: the row of the mob you should focus shows `SET FOCUS`. It stays put while that mob's Fear runs and moves on when it dies.
  - `/hmf macro` creates an "HMF Focus" macro for your action bar. Target or hover a mob and click it to set focus.
  - `/hmf bind <KEY>` binds a key to it instead.

### Commands
`/hmf` shows them all. Useful ones: `unlock` / `lock` (move the list), `scale 0.5-1.5`, `width 240-340`, `demo` (track your target), `reset`.

### Known limits
- Developed on WoW Classic Anniversary. Forever hides the combat log and enemy auras from addons, so there tracking is driven by your own casts: timers are estimates, and a resist, early break or dispel can't be seen.
- Forever also blocks addons from placing raid markers on mobs, so markers show on the list only.
- No direction arrow: the game does not give addons enemy positions.
- Casting is not done by the addon. It only tracks and helps you focus.
