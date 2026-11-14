# Quest XP Forecast: Forever Capability Report

Tested build: WoW Forever, `## Interface: 16001`, `WOW_PROJECT_ID=18`, Warlock-era low-level character (levels 6–9 quests), 8–9 quest log entries.
Evidence: `QuestXPLabDB` SavedVariables written by `addons/quest-xp-lab` (`/qxplab`), sessions 2026-11-13 22:20–22:37.
Only results actually observed are marked PASS. Everything else is listed under **Testing notes**.

## Recommendation: GO (with the testing notes closed first)

Classification and reward XP are readable, accurate in the one turn-in compared, and cheap to compute. The "classification and rewards reliable" gate is met for the tested scenarios. Build the full feature, but run the testing notes below before release.

## 1. API results (M0)

| API | Result |
|---|---|
| `C_QuestLog.GetNumQuestLogEntries/GetInfo/GetQuestObjectives/IsComplete/ReadyForTurnIn/GetQuestIDForLogIndex/GetSelectedQuest/IsOnQuest/IsRepeatableQuest` | EXIST; all probed values READABLE (no secret values, no errors) |
| `GetQuestLogRewardXP(questID)` | EXISTS; returns a number per questID without selecting the quest (8/8 quests, distinct values) |
| `GetQuestLogRewardXP()` (selected-quest form) | returns 0 with nothing selected, so the questID argument is honored |
| `C_QuestLog.GetQuestLogMajorFactionReputationRewards`, `GetQuestLogRewardMoney`, `GetQuestLogLeaderBoard`, `GetNumQuestLeaderBoards` | EXIST (not used for XP) |
| `GetNumQuestLogEntries`, `GetQuestLogTitle`, `GetQuestLogSelection` (classic globals) | MISSING; use `C_QuestLog` only |
| `UnitXP`, `UnitXPMax`, `UnitLevel` | EXIST, readable |

Objective data: `GetQuestObjectives` returns `{text, type, finished, numFulfilled, numRequired}` per objective, readable without selecting the quest.

## 2. Classification (M1)

Rules (never inferred from titles): ReadyForTurnIn/IsComplete true → READY; any measurable objective with progress or finished → IN_PROGRESS; measurable objectives all at 0 → NOT_STARTED; no numeric objective or unreadable → UNKNOWN.

| Scenario | Observed |
|---|---|
| Kill quest 0/N | NOT_STARTED (q756 0/12, q99108 0/3) PASS |
| Kill quest partial | IN_PROGRESS (q766 3/4; q756 1/12 after a kill) PASS |
| Ready, not turned in | READY (q749, q772, q99079) PASS |
| Turn-in-only / already-complete on accept | READY (q773 accepted as `done`, 850 XP) PASS; likely a talk-to-NPC quest |
| Collection, multi-objective, exploration, no-objective quests | NOT OBSERVED, see testing notes |

No UNKNOWN quests and no duplicate rows appeared in any scan.

## 3. Reward XP (M2)

| Quest | State at turn-in | API predicted | Event XP | Actual XP delta | Match |
|---|---|---|---|---|---|
| 772 | READY | 480 | 480 | 480 | yes |

Reward XP was readable for all three states (READY, IN_PROGRESS, NOT_STARTED) on all 8 quests. Accuracy of NOT_STARTED and IN_PROGRESS predictions is unconfirmed until those quests are turned in. Below-level, repeatable, and item-choice quests were not tested.

## 4. Live updates (M3)

| Event | Observed |
|---|---|
| `QUEST_LOG_UPDATE` | fires on login, accept, turn-in, progress; used as the base rescan trigger |
| `QUEST_WATCH_UPDATE(questID)` | fires on objective progress, payload readable; rescan moved q756 NOT_STARTED to IN_PROGRESS PASS |
| `UNIT_QUEST_LOG_CHANGED(player)` | fires on accept, turn-in, progress, payload readable |
| `QUEST_ACCEPTED(questID)` | fires, payload readable; new quest appeared in the next rescan PASS |
| `QUEST_TURNED_IN(questID, xp, money)` | fires, payload readable; quest removed from forecast, XP matched PASS |
| `QUEST_REMOVED(questID, ...)` | fired on turn-in (`false` flag) |
| `QUEST_POI_UPDATE` | fires; not needed |
| `PLAYER_LEVEL_UP` | registers OK; not yet observed firing |
| Reload | 0 differences across two reloads; one diff matched a real kill made before reload PASS |

Rescans are throttled to one per 0.5 s burst. No stale or duplicated rows seen; forecast XP was never added to earned XP.

## 5. Restrictions and performance (M4)

- Out of combat, 24 scans: avg 0.45 ms, max 1.11 ms (8 quests); event-driven rescans 0.24–4.6 ms.
- 0 Lua errors, 0 `ADDON_ACTION_FORBIDDEN/BLOCKED`, 0 secret-value reads, 0 changes to the selected quest.
- No `SelectQuestLogEntry`, tooltip, combat-log, or protected API was used.

## 6. Known limitations

- A quest with no numeric objective is UNKNOWN by design; the forecast must show an explicit unknown count rather than treating it as Not Started.
- READY includes quests that need only an NPC talk (q773); that is correct for the forecast.
- Reward XP is what the API reports at scan time; it must be refreshed on level-up.

## Testing notes (not yet done)

1. Run `/qxplab m4` in combat. `combatScans` was 0, so combat behavior is unverified.
2. Abandon a quest. Confirm `QUEST_REMOVED` fires and the quest leaves the forecast.
3. Level up. Confirm `PLAYER_LEVEL_UP` fires and rewards and XP-needed refresh.
4. Turn in an IN_PROGRESS-then-READY quest and a NOT_STARTED-then-completed quest. Compare predicted vs actual XP.
5. Find or accept a quest with no numeric objective (explore, talk-to, escort). Confirm it reports UNKNOWN.
6. Test collection and multi-objective quests (M1 table rows).
7. Test below-level quests, repeatables, and quests with item choices for reward XP.
8. Test a 25-quest log for scan time.
9. Confirm no addon-blocked dialog appears during combat play.

## Next step

Write the pH implementation TDD after the testing notes above are closed or accepted as risk.
