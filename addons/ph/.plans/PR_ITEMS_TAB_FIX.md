# Pull Request: fix: History Items tab shows all items looted (including vendored)

**Create PR here:** https://github.com/TheRightChoyce/wow-gold-per-hour-addon/pull/new/fix/items-tab-full-loot-history

**Base branch:** `feature/expanded-metric-cards`  
**Compare branch:** `fix/items-tab-full-loot-history`

---

## Title
```
fix: History Items tab shows all items looted (including vendored)
```

## Body
```markdown
## Problem
The Items tab in History → Session Detail only showed items still in bags. Any item sold to a vendor during the session was removed from `session.items`, so it disappeared from the history.

## Solution
- **`countLooted`** – New field on each item aggregate: total quantity ever looted (never decremented).
- **No deletion on vendor sale** – `ProcessVendorSale()` only decrements `count` (current held) and clamps at 0; the item entry stays in `session.items`.
- **Items tab** – Displays `countLooted` (with fallback to `count` for older saved sessions) for quantity and footer total.
- **Index aggregation** – Cross-session item stats use `countLooted` so totals reflect items looted, not just held at session end.

## Files changed
- `GoldPH/SessionManager.lua` – Add `countLooted` in `AddItem()`
- `GoldPH/Events.lua` – Stop deleting items in `ProcessVendorSale()`
- `GoldPH/UI_History_Detail.lua` – Use `countLooted` in Items tab
- `GoldPH/Index.lua` – Use `countLooted` in item aggregation
```
