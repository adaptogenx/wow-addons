# Forever Test Results

Build 1.60.1 / 70790 / toc 16001. Tester: user, solo Warlock L8, crowded zone (many players pulling mobs).

## M0 API baseline: PASS
- Expected: correct build, capability inventory, no blocked prompts, unknowns marked. Actual: all met. Build/interface MATCH; no prompts.
- Unverified: Forever UI source and event payload fields (not available locally).

## M1 Enemy identity & discovery: PASS (with gaps)
| Criterion | Result | Notes |
|---|---|---|
| Distinguish identical hostile mobs by readable identity | PASS | Several "Clattering Scorpid" with distinct GUIDs (e.g. ...6E3BA593BF, ...B08F7B6C8C, ...0F029F636F); two simultaneous plates (nameplate1/2) with distinct GUIDs in combat |
| Detect enemy entering/leaving accessible tokens | PASS | NAME_PLATE_UNIT_ADDED/REMOVED fire out and in combat; plates seen up to nameplate4 |
| No secret-value comparison errors | PASS | 0 SECRET/INACCESSIBLE/ERROR results across all probes |
| No incorrect GUID-to-unit associations | PASS | Nameplate tokens re-snapshotted on every add; no nameplate mismatch. Early MISMATCH/STALE lines were a harness bug (target/focus/mouseover legitimately change), fixed |
| Identities readable in combat | PASS | target, focus, mouseover, nameplate GUID+name readable in combat; player cast spellID readable |
- `FOCUS` set/clear works and reads correctly, including in combat.
- `UnitThreatSituation` returned nil everywhere: INCONCLUSIVE (not secret).
- Gaps: `/hmflab m1stats` not run; `/hmflab units` with 2+ simultaneous plates not run (but plate add events show them). Cast-target info: only target/focus/mouseover at cast time; no cast-target in event payload.
- Note: tester said "so many players pulling all the mobs"; combat tests used mobs already in combat.
- **Gate: passed** (independent enemy identity available). GUID-based tracking may continue.

## M2 Fear & debuff tracking: FAIL in combat (RESTRICTED), PASS out of combat
Learned spell IDs: Fear 5782, Corruption 172, Bane of Agony 980, Immolate 348.
| Criterion | Result | Notes |
|---|---|---|
| Fear detected on accessible enemy in combat | FAIL / RESTRICTED | `GetUnitAuraBySpellID` nil in combat; `UNIT_AURA` payload SECRET; enumeration errors while tainted |
| Remaining Fear duration displayed accurately | Unsupported in combat | Readable and accurate only out of combat (Corruption: duration 12.0, expiration readable, HUD swirl matched) |
| Two mobs independent durations | Unsupported in combat | No readable aura data. Out of combat not exercised with two mobs |
| Early break vs expiration | Unsupported | removed IDs secret in combat; REMOVED verdict logic never received readable data |
| DoT/Curse shown without secret-value errors | Partially | No secret errors (classification before use), but data unavailable in combat; swirls vanish when combat starts |
| Recast-threshold calculation | PASS | `tests/test_lab_threshold.lua` offline and `/hmflab thresholdtest` in game (4/4); unknown expiry returns nil, never guessed |
| Native widget showing secret durations without addon math | INCONCLUSIVE | Widget methods exist, but no untainted way found to obtain an aura instance ID/duration object in combat, and no native container constructor found |
- Player `UNIT_SPELLCAST_SUCCEEDED` spellID is READABLE in combat, so cast-time ESTIMATES are possible (logged as ESTIMATE only; not authoritative per gate).
- Not tested: Fear on nameplate tokens in combat (`ShouldAurasBeSecret()` is global, so inferred restricted); Fear natural expiry/early break/death (no readable data).
- **Gate: estimated timers are not promoted to authoritative state.**



## M3 Secure casting & raid markers: PASS (with restrictions)
| Criterion | Result | Notes |
|---|---|---|
| Secure casting works on intended valid unit in combat | PASS | target, focus, mouseover (key-bound) all cast Fear in combat |
| Intended target = actual recipient | PASS for focus/mouseover (observed); name check inconclusive | All test mobs were named "Kul Tiras Sailor"; confirmed by user observation, not by log |
| Different selected target not accidentally affected | PASS (observed) | Focus cast with target cleared; mouseover cast with different target |
| Player-triggered raid marking | PASS | `/tm 5` button, `/tm [@mouseover] 6` key, `/tm [@focus] 7` button; user saw moon and square; works in combat |
| `GetRaidTargetIndex` accessibility | RESTRICTED | returns SECRET for marked units; marks cannot be read back or verified by the addon |
| Fixed marker pool selectable in combat without attribute changes | PASS | Pre-created buttons/keys each carry a fixed marker and a unit token (target/focus/mouseover); nothing changes in combat. Choosing marker N for a specific mob needs one bound key/button per marker |
| No blocked-action dialogs / combat-lockdown errors | PASS | 0 ADDON_ACTION_FORBIDDEN/BLOCKED events |
- `@nameplateN` casting: FAIL (no cast sent).
- Out-of-range cast gives "Out of range." UI error and UNIT_SPELLCAST_FAILED; both readable.
- Production HoldMyFear on Forever throws `Encounter.lua:118: compare a secret number value` because `GetMarker` is secret (confirms the GetRaidTargetIndex finding). Needs fixing before M4.
- Not tested: Clique-style click casting, marker pool > 3 markers, `/tm` on mobs while moving.

