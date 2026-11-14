# Hold My Fear - Design (post-lab)

Based on `LAB_REPORT.md`. HUD tracks and informs; casting is mouseover/focus.

## Casting model
- Secure buttons, created once out of combat, `AnyDown`+`AnyUp`:
  - Mouseover Fear: override binding -> `/cast [@mouseover,harm,nodead] Fear`
  - Focus Fear: `/cast [@focus,harm,nodead] Fear`
  - Set focus: `/focus target`
  - Same for each tracked debuff (Curse of Agony, Corruption, ...).
- Keys come from `Bindings.xml` (user-rebindable), not hardcoded overrides.
- Intended-vs-actual (combat-log `destGUID`) kept as a debug/verification aid.

## HUD (insecure, combat-safe)
- Row per tracked GUID: marker, portrait, debuff icons + timers, Fear timer,
  name/level. Stable marker and row order per encounter.
- Highlight row of current mouseover / focus / target so the player maps
  keypress -> row at a glance. Directional arrow: NOT SUPPORTED on
  Classic Anniversary (tested 2026-11-02, `/hmf arrow`): `UnitPosition("target")`
  is nil for hostile NPCs, and nameplate frames (and frames anchored to them)
  cannot be measured, in or out of combat ("Can't measure restricted regions").
  Retest on Forever when it launches.
- Clicking a row does nothing secure. Optional: row click sets nothing.

## Layers (see CLAUDE.md)
- `Adapters/`: unit/nameplate/combat-log/spell APIs.
- `Core/`: Tracker (GUID <-> marker <-> row), DebuffState, FearState.
- `UI/`: HUD rows; `Casting/` or `UI/SecureButtons`: secure buttons + bindings.

## Milestones
1. Tracker + markers + HUD rows (no casting).
2. Debuff/fear timers from combat log + aura scans.
3. Secure cast buttons + `Bindings.xml`.
4. Row highlighting for mouseover/focus/target; polish, tests, Lab removal.
