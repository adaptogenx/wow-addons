# WoW Forever Port — M3 (Production Compatibility)

## API audit (client-specific calls)
| Call | Status |
|---|---|
| GetAddOnMetadata, GetSpellInfo, GetItemInfo, GetItemCount, GetNumFactions/GetFactionInfo, GetMoney, UnitXP/UnitXPMax/UnitLevel/GetMaxPlayerLevel, UseContainerItem hook | Wrapped in `pH_API` |
| C_Container bag/slot calls | Already wrapped in Events.lua (`GetBagNumSlots`/`GetBagItemInfo`); bag range via `pH_API:GetLastBagIndex()` |
| RepairAllItems, TakeTaxiNode hooks | Guarded (`if fn then`) |
| SetBackdrop | All 20 frames use `BackdropTemplate` (audited) |
| UIDropDownMenu_*, StaticPopup, IsInInstance, UnitName/GetRealmName/UnitFactionGroup, GetZoneText | Shared, unchanged; **verify on Forever** |
| OnUpdate handlers | 3 small (10s timer, 20s prompt, 30s toast); no per-frame scans |

## M3 code changes
- `CHAT_MSG_*` events with Secret Value payloads are ignored.
- `EnsureAccountDB` repairs missing/invalid `sessions`, `activeSessions`, `priceOverrides`, `debug`, `lastSessionId` field-by-field (never resets history; `lastSessionId` recovers from max existing ID).
- No schema migration, no SavedVariables rename. Same TOC/package for both clients (`## Interface: 11504, 16001`); `package-release.sh` already includes `pH_API.lua`.
- Pending state is bounded: loot deferral queue expires after 3s.

## Automated tests
`lua tests/test_api.lua` and `lua tests/test_loot_defer.lua`. Not covered: history UI, persistence round-trips, vendor/quest/DE flows.

## Forever runtime report (fill in per build)
Forever build: ____   pH version: 1.6.0

| Area | Test | Result | Limitation |
|---|---|---|---|
| Load | Fresh login / reload / relog | | |
| Session | Start/Pause/Resume/Stop | | |
| AutoSession | Gold / XP / Rep / Honor | | |
| Gold | Gain / expense | | |
| XP | Mob / quest / level rollover | | |
| Rep | Gain / standing rollover | | |
| Honor | Gain (chat-parsed) | | |
| Loot | Item | | |
| Vendor | Buy / sell / repair / buyback | | |
| Quest | Economic rewards | | |
| Gathering / Pickpocket / Disenchant | | | |
| History | List / detail / filters / empty / large | | |
| Persistence | Reload / relog / character switch | | |
| Upgrade | Classic SavedVariables on new build | | |
| UI | Combat / non-combat | | |
| Instance | Dungeon / PvP / re-entry | | |

Classify failures: port regression / existing pH bug / Forever beta limitation.

## Known Forever limitations / open items
| Feature | Forever behavior | pH behavior | Fixable? |
|---|---|---|---|
| Honor | Chat-message parsing unverified | Unchanged from Classic | Possibly, via honor currency delta |
| Loot | Chat-driven, not bag-delta authoritative | Same as Classic | Yes (future work) |
| Vendor sale, item uncached | Sale skipped | Not booked | Yes (defer like loot) |
| Reputation | Paragon/friendship/major factions not handled | Standard factions only | Yes |
| Chat payloads | May be secret in restricted contexts | Event ignored | No (by design) |
