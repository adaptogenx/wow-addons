# Quest XP Forecast: Technical Design

Status: draft. Based on `addons/quest-xp-lab/docs/capability-report.md` (recommendation: GO, nine testing notes open).

## 1. Goal

Show, for the active character, how much XP is sitting in the quest log and whether it can level the character:

- Ready XP: quests ready to turn in.
- In-progress XP: quests with measurable progress.
- Excluded XP: quests not started (not counted toward the forecast).
- Unknown count: quests whose progress cannot be measured (never treated as not started).
- Ready to level / Potential to level, against XP needed (`UnitXPMax - UnitXP`).

Non-goals: tooltip modification of quest items, quest recommendations, per-zone planning, persisting the forecast, counting forecast XP as earned XP, XP-per-hour changes, and any quest-title or database inference.

## 2. Validated platform facts (from the lab)

- Forever exposes readable `C_QuestLog.GetNumQuestLogEntries/GetInfo/GetQuestObjectives/IsComplete/ReadyForTurnIn`; no secret values observed.
- `GetQuestLogRewardXP(questID)` returns the reward without selecting the quest. One predicted vs actual turn-in matched exactly (480/480).
- Classic globals (`GetQuestLogTitle`, `GetNumQuestLogEntries`) are absent on Forever. Anniversary (11504) is untested and needs a separate check.
- Events observed: `QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE(questID)`, `UNIT_QUEST_LOG_CHANGED(player)`, `QUEST_ACCEPTED(questID)`, `QUEST_TURNED_IN(questID, xp, money)`, `QUEST_REMOVED(questID)`.
- A scan of 8 quests costs 0.2–4.6 ms.

## 3. Architecture

New module `ph/QuestForecast.lua`, loaded after `Insights.lua` in `ph.toc`.

| Part | Responsibility |
|---|---|
| `pH_API` additions | `GetQuestLogEntryCount()`, `GetQuestLogEntry(i)`, `GetQuestObjectives(id)`, `IsQuestReady(id)`, `GetQuestRewardXP(id)`. Each wraps `C_QuestLog` with `SafeNumber` / `IsSecret` guards and returns nil on failure. Anniversary fallbacks only after the Anniversary check. |
| `pH_QuestForecast:Classify(entry, objectives, ready)` | Pure function: `READY / IN_PROGRESS / NOT_STARTED / UNKNOWN`. Rules below. |
| `pH_QuestForecast:Scan()` | Walks the log, returns `{rows, totals}`; no globals mutated. |
| `pH_QuestForecast:Summarize(rows, xp, xpMax)` | Pure function: ready/progress/excluded XP, unknown count, `readyToLevel`, `potentialToLevel`. |
| Event router | Registers the events above on the pH frame (`Events.lua` pattern), debounces rescans (0.5 s, one timer, never per frame). |
| UI | XP tooltip lines in `UI_HUD.lua` and a "Quest XP" block in the session detail window. |

Forecast data is runtime-only. It is not written to `pH_DB`, to sessions, or to the ledger. This preserves the pH rule that forecasts are never earned values.

## 4. Classification rules

1. `ReadyForTurnIn(questID)` (fallback `IsComplete`) true: READY.
2. Otherwise read objectives. If any objective has `numRequired > 0`:
   - any `numFulfilled > 0` or `finished`: IN_PROGRESS;
   - all at 0: NOT_STARTED.
3. No numeric objective, objectives unreadable, or any API result secret/nil: UNKNOWN.
4. A quest with no measurable progress is never NOT_STARTED. Exploration, talk-to, and hidden objectives stay UNKNOWN unless the client says finished.
5. Headers, tasks, and hidden entries are skipped. Repeatable quests: counted but marked (see open questions).

Reward lookup failure: reward = nil, quest still classified, counted in `rewardFail` and excluded from XP sums. The UI shows the XP total as a lower bound whenever `rewardFail > 0` or `unknown > 0`.

## 5. Level math

- `need = xpMax - xp` for the current level only.
- `readyToLevel = readyXP >= need`; `potentialToLevel = readyXP + progressXP >= need`.
- Rewards are computed for the current level. On `PLAYER_LEVEL_UP`, clear and rescan (rewards and `xpMax` change). The forecast does not project across multiple levels.
- At max level (`pH_API:GetMaxPlayerLevel`) the forecast is disabled.

## 6. Events and refresh

| Event | Action |
|---|---|
| `QUEST_LOG_UPDATE`, `QUEST_WATCH_UPDATE`, `UNIT_QUEST_LOG_CHANGED` (player), `QUEST_ACCEPTED`, `QUEST_REMOVED` | Debounced rescan |
| `QUEST_TURNED_IN` | Debounced rescan; the existing `pH_Events` quest-XP path still records earned XP (the forecast does not touch it) |
| `PLAYER_LEVEL_UP`, `PLAYER_XP_UPDATE` | Rescan (new `xpMax` / baseline) |
| `PLAYER_ENTERING_WORLD` | Rescan after a short delay (quest log may not be populated) |

Unlike gold events, quest rescans continue while a session is paused, since the forecast describes the log, not session earnings. If there is no active session the forecast still works.

## 7. UI

- HUD XP tooltip (`UI_HUD.lua`): Ready XP (count), In-progress XP (count), quest log total, a level-up note, and an unmeasured-quests note. Hidden when the forecast is empty or max level.
- HUD XP tile: `*` suffix and green text as in section 11. No Excluded/not-started figure anywhere.
- Session detail window block: deferred, not part of the first cut.
- Never label forecast numbers as "earned" or add them to XP gained or XP/hr.

## 8. Forever and compatibility guards

- Every quest API result passes `issecretvalue` before comparison; a secret result means UNKNOWN or reward nil.
- No `SelectQuestLogEntry`, tooltip scanning, combat-log events, or protected calls.
- Scans are event-driven and debounced; no OnUpdate scanning.
- Anniversary must be verified (see section 10) before shipping there, or the feature is gated off with `IsForever()`.

## 9. Tests

Automated (plain Lua, `tests/test_quest_forecast.lua`, same style as `test_insights.lua`):
- `Classify`: each row of the M1 table plus secret/nil inputs to UNKNOWN.
- `Summarize`: totals, unknown handling, level threshold edges (exact match, off by one, `xpMax - xp == 0`).
- Debounce: many events produce one scan.
- Scan with fake `pH_API`: headers skipped, reward failure counted, no mutation of session or ledger.

Manual on Forever and Anniversary (see section 10): accept, progress, finish, turn in, abandon, level up, reload, in-combat scan.

Invariant check (add to `Debug.lua` validation): forecast XP is not added to `metrics.xp.gained` or `bySource`.

## 10. Open items to close before release (testing notes from the lab)

1. Combat: scan in combat; confirm no secret or blocked-action errors.
2. Abandon: `QUEST_REMOVED` fires and the quest leaves the forecast.
3. Level-up: `PLAYER_LEVEL_UP` fires and the forecast refreshes.
4. Predicted vs actual XP for quests that were NOT_STARTED and IN_PROGRESS when scanned.
5. A quest with no numeric objective reports UNKNOWN.
6. Collection and multi-objective quests.
7. Below-level quests, repeatables, quests with item choices.
8. 25-quest log scan time.
9. No addon-blocked dialog during play.
10. Anniversary client: API availability and results (the lab has only run on Forever).

## 11. Decisions (owner)

- Not-started XP is never shown or counted (not in totals, not in the UI).
- Repeatable quests are not counted.
- A quest that can give XP and is Ready is counted, including turn-in-only quests.
- Surface in both the HUD tile and the XP tooltip. The tooltip is reorganised: pace, level (to level, quest log), then earned this session.
- Ship Ready + In-progress together.
- HUD tile: XP rate gets a `*` suffix when quest-log XP is waiting (same convention as rep's projected `*`); the rate turns green when Ready quests alone would level the character.
- Unmeasured quests (UNKNOWN) are noted in the tooltip as not counted, never counted as XP.

## 12. Rollout

1. Resolve section 10 items (lab addon is installed; run the scenarios).
2. Implement `pH_API` wrappers, `QuestForecast.lua`, tests, tooltip lines.
3. Add the detail-window block.
4. Run `install.sh`, test on Forever and Anniversary, then bump the pH version.
