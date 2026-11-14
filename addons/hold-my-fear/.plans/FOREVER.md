# Forever client differences (tested 2026-11-04, build 16001)

Forever is a retail-based engine with "secret values" restrictions. Tested against the Anniversary build, where all of this works.

| Area | Anniversary | Forever |
|---|---|---|
| `RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` | works | **Blocked** ("blocked from an action only available to the Blizzard UI" prompt at load, no Lua error, no taint log entry, event reports `func=UNKNOWN()`). Confirmed: prompt stops when the registration is skipped. |
| `SetRaidTarget` | works | **Blocked** (same prompt, even under `pcall`). Skipped on Forever. |
| `C_UnitAuras.GetAuraDataByIndex` on enemy units | works | Errors "Auras cannot be accessed when secret while tainted". Wrapped in `pcall`; treated as unreadable. |
| Nameplate `GetCenter()` / frames anchored to a nameplate | error ("restricted regions") | Same, plus anchoring to a plate raised the blocked-action prompt. |
| `UnitPosition` on hostile NPCs | nil | not retested |
| Key Bindings `Bindings.xml` with custom category | n/a | not the cause of the prompt; removed anyway (empty `Bindings.xml` kept so the client's stale file lookup succeeds). |

Consequence: on Forever the addon currently has no event source for Fear/DoT tracking. Needs a different design (player cast events, UNIT_AURA, target GUID) before it does anything there.

How it was found: the addon saved/printed `ADDON_ACTION_FORBIDDEN`, then bisected by removing candidates one at a time.
