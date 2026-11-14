# Targeting Lab Report

Client: Classic Anniversary / Forever, build 20506. Run in-game 2026-10-26/27.
Raw logs: `HoldMyFearDB.labLog` (SavedVariables). Lab code: `holdmyfear/Lab/`.

## Verdict

One-click casting on a **specific GUID from a HUD row is not achievable** in
this client. What is achievable: casting on **`mouseover`** (any mob, any
number) and on **`focus`** (one mob), securely, in and out of combat.

## Results

| Question | Result |
|----------|--------|
| `type=spell unit=nameplateN` casts | **No.** Out of range: "too far away". In range: silent no-op (no SENT, no error). |
| `/cast [@nameplateN] Fear` casts | **No.** Same as above. |
| `type=target`, `/target nameplateN` | **No.** Target unchanged. |
| `type=focus`, `/focus nameplateN` | **No.** Focus unchanged. |
| Insecure `TargetUnit`/`FocusUnit`/`CastSpellByName` | **Blocked** (`ADDON_ACTION_FORBIDDEN`). |
| `unit=target` / `[@target]` | Works. |
| `/focus target` via secure macro | Works, including in combat. |
| `[@focus,harm,nodead]` and `unit=focus` | **Works**, in combat. Cast hit focus while target changed mid-cast. |
| `[@mouseover,harm,nodead]` and `unit=mouseover` via override binding | **Works** with target != mouseover (out of combat); also in combat. |
| Restricted env (secure snippets) unit APIs | Only `UnitExists`. No `UnitGUID`, `UnitName`, `GetRaidTargetIndex`. |
| Insecure detection of new hostiles in combat | **Works** (`NAME_PLATE_UNIT_ADDED` fires in combat). |
| Insecure `SetAttribute` on secure frames in combat | Untested validly (test ran before lockdown). Blocked by design. |
| State-driver snippets mid-combat (C/F) | Untested (snippet did not log). Moot, see below. |
| Intended-vs-actual verification | Works via combat log `destGUID` (SPELL_CAST_SUCCESS / AURA_APPLIED). |

## Consequences

- Secure code cannot identify a mob by GUID or marker, so no secure rebinding
  scheme can map a HUD row to a mob. Nameplate tokens are the only per-mob
  tokens and they are rejected as spell/target/focus units.
- GUID tracking, marker assignment and HUD state are insecure and fully
  available in combat.
- Casting is limited to `target`, `focus`, `mouseover` (fixed tokens that
  never need rebinding).
- Nameplate indices shift as mobs enter/leave; any design keyed on them is
  unreliable regardless.

## Forever-specific notes

- `ActionButtonUseKeyDown=1`: secure buttons must register
  `("AnyDown", "AnyUp")` or key-down clicks do nothing.
- `SpellCanTargetUnit` returns false even for valid targets; do not use.
- Macro/Lua `FocusUnit`, `TargetUnit`, `CastSpellByName` are forbidden to
  addon code at all times; only secure templates may act.
- Moving cancels the Fear cast (`FAILED` with player speed > 0).
- SavedVariables only flush on `/reload` or logout; a second reload
  overwrites the first session's log.
