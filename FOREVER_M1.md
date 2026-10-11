# WoW Forever Port — M1 Status

## Done (code)
- `ph/pH_API.lua`: client detection (TOC build number >= 160000 = Forever), money/XP/level wrappers (secret-safe, degrade to 0), `GetAddonMetadata` (C_AddOns first), normalized `GetReputations()` (legacy `GetFactionInfo` first, `C_Reputation` fallback).
- Consumers migrated: Events, AutoSession, SessionManager, UI_HUD, init. No direct `GetNumFactions/GetFactionInfo/UnitXP/GetMoney` left outside pH_API.
- HUD max-level now uses `GetMaxPlayerLevel()` (fallback 70) instead of hardcoded 70.
- TOC: single file, `## Interface: 11504, 16001`. Verify both clients accept the comma list; else split TOCs.
- Tests: `lua tests/test_api.lua` (mock Classic + Forever adapters).

## Honor decision
Kept `CHAT_MSG_COMBAT_HONOR_GAIN` parsing (unchanged). Not verified on Forever. If chat is unreliable, switch to honor currency delta via `C_CurrencyInfo` (add `pH_API:GetHonor()`). Needs runtime check.

## Runtime checklist (needs Forever client — NOT yet run)
- [ ] Login, /reload, relog: 0 Lua errors, HUD renders
- [ ] Gold delta, gold/hr, pause/resume
- [ ] XP: mob, quest, level-up rollover, max level hides XP
- [ ] Rep: 2 sources, standing boundary, no double count
- [ ] Honor: gain counted once
- [ ] AutoSession triggers: XP, gold, rep, honor
- [ ] Classic Anniversary regression

## Deferred to M2
`GetItemInfo` -> `C_Item`, container API validation, spell/gather events, `GetSpellInfo`, `GetItemCount`.
Unverified: `C_Reputation.GetFactionDataByIndex` field names, paragon/friendship/major factions handling.
