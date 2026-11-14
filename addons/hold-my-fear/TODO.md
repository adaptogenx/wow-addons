# Hold My Fear - TODO

Source: `.plans/DESIGN.md` milestones. Status checked 2026-11-01 by code review,
`lua tests/test_tracker.lua` (PASS) and `scripts/static-checks.sh` (pass).
Not run in game: "done" means the code exists and offline tests pass.
Offline: `lua tests/test_tracker.lua` and `lua tests/test_encounter.lua` both PASS.

## M1: Tracker + markers + HUD rows (no casting) - DONE (code)
- [x] 1.1 GUID-keyed Tracker, stable row order (`Core/Tracker.lua`)
- [x] 1.2 Cycling marker assignment, nil when all 8 are used
- [x] 1.3 Subscribe/emit events for the UI
- [x] 1.4 Untrack and reset on death or combat end (`Core/Encounter.lua`)
- [x] 1.5 HUD frame with draggable lock/unlock, saved position (`UI/HUD.lua`)
- [x] 1.6 Row layout: marker, portrait, name (level removed per TDD)
- [x] 1.7 Offline tracker tests pass
- [x] 1.8 Offline tests for Encounter (`tests/test_encounter.lua`)

## M2: Debuff/fear timers - DONE
- [x] 2.1 Combat-log adapter (`Adapters/CombatLogAPI.lua`)
- [x] 2.2 Fear applied, refreshed and removed from the combat log
- [x] 2.3 Aura-scan adapter for the player's debuffs (`Adapters/AuraAPI.lua`)
- [x] 2.4 Estimated durations replaced by real ones once an aura scan reads
- [x] 2.5 DoT/curse icons on each row, horizontal depletion, expired kept, `+N` overflow (TDD)
- [x] 2.6 Fear icon with whole-second timer; Normal/Recast/Critical/Broken/Expired states (TDD)
- [x] 2.7 Engaged-mob scanning from threat, nameplates and the combat log
- [x] 2.8 In-game verification of the timers (user confirmed 2026-11-02)
- [x] 2.9 Offline tests for the Encounter/combat-log paths (`tests/test_tracker.lua`, `tests/test_encounter.lua`)

## TDD: Combat Minimal HUD redesign (`TDD.md`) - DONE (code), not verified in game
- [x] T.1 Layout: 292px (240-340 via `/hmf width`), 68px rows, 28px icons, name under portrait
- [x] T.2 DoT depletion, expired icons kept, `+N` overflow
- [x] T.3 Fear control: fixed 28px, integer seconds, 5 states, real cast time + 0.3s buffer
- [x] T.4 Broken Fear only on confirmed duration (`Core/Encounter.lua`); offline tests added
- [x] T.5 In-game check (user confirmed 2026-11-02): 1-5 mobs, all Fear states, `+N` at 240px, cast-time lookup, `/hmf test run`
- [ ] T.6 Click-to-recast on icons (needs M3 secure buttons)
- [-] T.7 Direction arrow: UNSUPPORTED on Anniversary (no mob position; nameplates unmeasurable, tested 2026-11-02). Code kept, hidden when no bearing. Retest on Forever with `/hmf arrow` (see 4.2)
- [x] T.8 Broken-chain art: ReadyCheck X accepted for now (user, 2026-11-02)
- [ ] T.9 Make Broken / Expired Fear more visible, e.g. floating-combat-text-style pop on the row ("BROKEN" / "EXPIRED"), possibly with the mob name or marker. Visual only, no audio (audio is out of scope per TDD)

## Forever (see `.plans/FOREVER.md`)
- [x] F.1 Stop the load-time "blocked action" prompt (combat log registration and `SetRaidTarget` skipped on Forever)
- [~] F.2 Forever tracking from player casts (`Core/Casts.lua`) + Blizzard aura-engine bars on each icon (`Adapters/ForeverAPI.lua`, learned from Warlock Tools Forever). Code + offline tests (`tests/test_casts.lua`) done; NOT verified in game. Raid markers HUD-only.

## M3: Secure cast buttons + `Bindings.xml` - NOT STARTED
Only the Lab has secure code. `Lab/FocusMouseover.lua` is loaded;
`Lab/Combat.lua` and `Lab/GuidCast.lua` are disabled.
- [ ] 3.1 Create the secure buttons out of combat, `AnyDown`+`AnyUp`
- [ ] 3.2 Mouseover Fear: `/cast [@mouseover,harm,nodead] Fear`
- [ ] 3.3 Focus Fear: `/cast [@focus,harm,nodead] Fear`
- [~] 3.4 Set focus: `/focus [@mouseover] mouseover; target` secure button + Key Bindings entry + suggested-focus logic (`Core/Focus.lua`, HUD tag). Code + offline tests done; in-game check pending
- [ ] 3.5 Per-debuff mouseover and focus buttons (Corruption, Curse of Agony, ...)
- [~] 3.6 `Bindings.xml` + binding names exist for Set focus only (auto-loaded, not listed in `.toc`); Fear/debuff buttons still to add
- [ ] 3.7 Combat-lockdown guard: never create or change buttons in combat
- [ ] 3.8 Intended-vs-actual `destGUID` debug check
- [ ] 3.9 In-game test of the bindings

## M4: Row highlighting, polish, tests, Lab removal - NOT STARTED
- [ ] 4.1 Highlight the row for mouseover, focus and target
- [-] 4.2 Directional arrow: unsupported on Anniversary; retest on Forever (see T.7)
- [ ] 4.3 Polish: settings, empty state, row sizing
  - Scale 0.8 (`/hmf scale`) was hard to read on a small laptop; TDD sizes (28px icons, 14px Fear number) should help, recheck in game
  - Prune safety net (`Encounter.Prune`) added; confirm in game that dead mobs leave the HUD
- [ ] 4.4 Wire in-game tests into `Tests/TestRunner.lua` (runner exists, 0 cases registered)
- [ ] 4.5 Remove `Lab/`, its `.toc` entries and the `/hmflab` command
- [ ] 4.6 Update README and `DESIGN.md` status

## Next
M3.1 - M3.6.
