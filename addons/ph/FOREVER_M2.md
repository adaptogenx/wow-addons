# WoW Forever Port — M2 Status (economic tracking)

## Done (code, mock-tested only)
- `pH_API`: `GetItemInfo`/`GetItemCount` (C_Item first), `RequestItemData`, `IsSecret`, `GetLastBagIndex` (includes reagent bag), `HookUseContainerItem` (C_Container on Forever).
- Loot cache miss: item data requested, loot message queued, replayed on `GET_ITEM_INFO_RECEIVED` or after 3s. Each message processed once. Classic unchanged when `C_Item.RequestLoadItemDataByID` is absent.
- Bag scans now cover the reagent bag.
- `RepairAllItems` hook guarded; lockbox `UseContainerItem` hook works on `C_Container`.
- Secret spell IDs ignored in `UNIT_SPELLCAST_SUCCEEDED`.
- Tests: `lua tests/test_loot_defer.lua`.

## Not done / needs Forever runtime
Vendor, quest, gather, pickpocket, disenchant, repair, buyback, reload, and Classic regression: logic untouched, unverified on Forever.
Open concerns: vendor-sale cache miss still returns early (sale not booked); `CHAT_MSG_LOOT` format and bag-delta-authoritative loot not implemented (loot still chat-driven); disenchant spell ID path unverified.
