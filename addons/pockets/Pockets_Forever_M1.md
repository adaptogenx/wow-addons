# Pockets on WoW Forever — M1 status (read-only inventory)

Branch: `feature/forever-m1`. One shared codebase; all client differences live in `Adapters/`.

## What M1 changed
- `Adapters/ClientAPI.lua` (new): interface-number client detection (16000–16999 = Forever, 11xxx/20xxx = Classic, else unknown), `IsSecret`, `GetAddonMetadata` (C_AddOns → legacy).
- `Pockets.toc`: `## Interface: 11509, 20504, 16001` (single multi-interface TOC; **unverified in the Forever client** — if it refuses, split manifests, sharing the same Lua).
- `ItemAPI`: `RawGetItemInfo` (C_Item → legacy), `GetItemFamily` (C_Item → legacy), `RequestItemData` (C_Item.RequestLoadItemDataByID). Pending items request a load; GET_ITEM_INFO_RECEIVED + existing debounced refresh resolves them.
- `BagAPI`: ammo family via ItemAPI; Secret slot counts → 0 (existing cached-size / incomplete-scan protection takes over); Secret slot contents → slot skipped.
- `TooltipAPI`: legacy `OnTooltipSetItem` hook only when the tooltip still has that script; otherwise skipped (`TooltipAPI.supported = false`). **Carried-count tooltip line is unavailable on Forever until M3.**
- `Events.lua` / `Debug.lua`: no direct legacy item/addon globals.
- Tests: `Tests/ClientAPITests.lua` (modern + legacy mocks, Secret Values, pending→ready, ammo families, tooltip detection).

## Deliberately untouched (M2)
`UI/ItemButtonPool.lua` secure buttons (`type2="item"`, `item2="bag slot"`), pickup/drag/use/split/modified-click via `BagAPI:PickupItem/UseItem/SplitStack/HandleModifiedItemClick`, `SetTooltipToBagItem`, stale-slot protection, combat behavior. Unknown on Forever: whether secure item attributes + `C_Container.UseContainerItem` still work from addon code; whether `HandleModifiedItemClick` is still global.

## Deferred to M3
- Modern tooltips (`TooltipDataProcessor`) for the carried-count line.
- Bindings (`BindingsAPI`) validation, SavedVariables reload checks, combat hardening, full Secret Value audit in-game, packaging.

## Known gaps / assumptions to verify in the Forever client
- Interface number 16001 is the detection signal (not `WOW_PROJECT_ID`).
- Reagent bag (container 5) is not scanned (bags 0–4 only), same as before.
- `GetInventoryItemLink`, `GetBuildInfo`, `issecretvalue` assumed present/absent as on Mainline; all guarded.
- Events in `Events.lua` (BAG_UPDATE, BAG_UPDATE_DELAYED, ITEM_LOCK_CHANGED, PLAYER_MONEY, GET_ITEM_INFO_RECEIVED, MAIL_CLOSED, AUCTION_HOUSE_CLOSED, PLAYER_REGEN_*) must all exist; RegisterEvent on an unknown event errors on modern clients.

## Runtime checklist (not yet run)
Install → login → open Pockets → `/reload` → `/pockets test run` → verify capacity, ammo pool, items, categories, Recent, ETA, search, HUD position; then repeat on Anniversary/TBC.
