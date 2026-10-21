# GoldPH Addon — Technical Design Document (TDD)
*(WoW Classic Anniversary)*

## 0. Summary
GoldPH is a session-based gold-per-hour addon that tracks:
- **Actual cash** (gold/coin gained and spent)
- **Expected inventory value** (conservative liquidation value of items acquired during a session)

It uses a **double-ledger model** to prevent double counting (e.g., grays counted when looted and again when vendored) and to correctly handle **Rogue pickpocketing** and **lockboxes** (0 value until opened).

---

## 1. Goals (MVP)
1. Track per-session:
   - Cash gains (looted coin, quest gold, vendor sales)
   - Cash spends (repairs, vendor purchases, travel/flight)
   - Expected inventory value gained (trash/vendor, rare items, gathering mats)
   - Expected inventory value removed (e.g., when vendored)
   - Nodes gathered: total + by node type name (e.g., “Rich Thorium Vein”)
   - Pickpocket totals: cash + expected value from pickpocket *excluding unopened lockboxes*
2. Display:
   - **Raw cash/hour**, **expected value/hour**, **total economic/hour**
   - Category breakdowns and top item contributors
   - Nodes summary and pickpocket summary
3. Ensure **no double counting** across item value vs vendor sales.
4. Persist sessions across reloads.

---

## 2. Non-Goals (MVP)
- No tooltip modifications
- No automatic activity detection
- No CSV export
- No AH sale realization (tracking sold auctions vs listed)
- No configurable valuation weights (fixed conservative model)
- No advanced disenchant table (DE value can be 0 until implemented)
- No location tracking for nodes

---

## 3. Key Design Principles
- **Conservative** valuation (avoid inflated market pricing)
- **Ledger invariants**: economic changes are explainable and consistent
- **Snapshot pricing**: store the per-session price used at acquisition time
- **Minimal dependencies**: use TSM prices if present, but never require TSM

---

## 4. Architecture Overview
### 4.1 Components
- **SessionManager**
  - Start/stop session
  - Persist active session
  - Compute derived metrics
- **Ledger**
  - Account balances (and optional posting log)
  - Posting helpers
- **Holdings**
  - Per-item FIFO lots storing expected values booked at acquisition time
  - Supports reversals on vendor sale (removing previously-booked expected value)
- **ValuationEngine**
  - Classify items into buckets
  - Compute conservative expected value per item
- **EventRouter**
  - Subscribes to WoW events and dispatches to accounting actions
- **UI**
  - Minimal HUD + session summary panel

---

## 5. Data Model & SavedVariables

### 5.1 SavedVariables Root
```lua
GoldPH_DB = {
  meta = {
    version = 1,
    realm = "Dreamscythe",
    faction = "Horde",
    character = "Adaptogen",
    lastSessionId = 0,
  },

  settings = {
    trackZone = true,
  },

  priceOverrides = {
    -- [itemID] = copperValuePerItem
  },

  activeSession = nil,

  sessions = {
    -- [sessionId] = Session
  },
}
```

### 5.2 Session Object
All currency values are in **copper**.
```lua
Session = {
  id = 1,

  startedAt = 1700000000,
  endedAt   = 1700003600,
  durationSec = 3600,

  zone = "Zul'Farrak",

  -- Ledger balances by account (source of truth)
  ledger = {
    balances = {
      ["Assets:Cash"] = 0,
      ["Assets:Inventory:TrashVendor"] = 0,
      ["Assets:Inventory:RareMulti"] = 0,
      ["Assets:Inventory:Gathering"] = 0,
      ["Assets:Inventory:Containers:Lockbox"] = 0,

      ["Income:LootedCoin"] = 0,
      ["Income:Quest"] = 0,
      ["Income:VendorSales"] = 0,
      ["Income:ItemsLooted:TrashVendor"] = 0,
      ["Income:ItemsLooted:RareMulti"] = 0,
      ["Income:ItemsLooted:Gathering"] = 0,

      ["Income:Pickpocket:Coin"] = 0,
      ["Income:Pickpocket:Items"] = 0,
      ["Income:Pickpocket:FromLockbox:Coin"] = 0,
      ["Income:Pickpocket:FromLockbox:Items"] = 0,

      ["Expense:Repairs"] = 0,
      ["Expense:VendorBuys"] = 0,
      ["Expense:Travel"] = 0,

      -- Adjustment for removing previously booked inventory value
      ["Equity:InventoryRealization"] = 0,
    },

    -- Optional for debugging; not required MVP:
    -- postings = { Posting, ... }
  },

  -- Per-item aggregates (for UI breakdown)
  items = {
    -- [itemID] = ItemAgg
  },

  -- Per-item FIFO lots used to reverse expected value when items leave inventory
  holdings = {
    -- [itemID] = { count = 0, lots = { Lot, ... } }
  },

  gathering = {
    totalNodes = 0,
    nodesByType = {
      -- ["Rich Thorium Vein"] = 12
    },
  },

  pickpocket = {
    gold = 0,
    value = 0,
    lockboxesLooted = 0,
    lockboxesOpened = 0,
    fromLockbox = { gold = 0, value = 0 },
  },

  -- Precomputed summaries (optional): can also compute at runtime
  summary = {
    -- cached derived metrics for fast UI
  },
}
```

### 5.3 Item Aggregation
```lua
ItemAgg = {
  itemID = 13465,
  name = "Mountain Silversage",
  quality = 1,

  bucket = "gathering", -- "trash_vendor" | "rare_multi" | "gathering" | "container_lockbox" | "other"
  count = 12,

  -- Pricing snapshot used at acquisition time (per 1 item)
  priceEach = { vendor = 250, ah = 1800, de = 0 },

  -- Conservative tracked expected value used for inventory postings
  trackedValueEach = 1800,
  trackedValueTotal = 21600,
}
```

### 5.4 FIFO Lot
```lua
Lot = {
  count = 3,
  expectedEach = 1200,
  bucket = "trash_vendor",
}
```

---

## 6. Double-Ledger System

### 6.1 Core Invariant
Per session:
> **Net Worth Change = ΔCash + ΔInventoryExpected**

- ΔCash is posted to `Assets:Cash`
- ΔInventoryExpected is posted to `Assets:Inventory:*`

### 6.2 Chart of Accounts (MVP)
**Assets**
- `Assets:Cash`
- `Assets:Inventory:TrashVendor`
- `Assets:Inventory:RareMulti`
- `Assets:Inventory:Gathering`
- `Assets:Inventory:Containers:Lockbox` *(expected value 0)*

**Income**
- `Income:LootedCoin`
- `Income:Quest`
- `Income:VendorSales`
- `Income:ItemsLooted:<bucket>`
- `Income:Pickpocket:*`

**Expenses**
- `Expense:Repairs`
- `Expense:VendorBuys`
- `Expense:Travel`

**Equity**
- `Equity:InventoryRealization` *(offset entry when removing inventory expected value on sale)*

> Note: This is a pragmatic structure to support reporting and invariants; it’s not intended to match GAAP.

---

## 7. Valuation Model (Conservative)

### 7.1 Buckets
- `trash_vendor`: grays + most whites valued at vendor
- `rare_multi`: greens/blues/purples using multi-path expected value
- `gathering`: mats (ore, herbs, leather, cloth, etc.)
- `container_lockbox`: lockboxes; **expected = 0** until opened

### 7.2 Conservative Candidate Prices (per item)
- `V_vendor`: vendor sell price
- `V_AH`: conservative AH value (prefer low-biased source + friction)
- `V_DE`: expected DE mat value (0 in MVP unless implemented)

### 7.3 Rare Multi (greens/blues/purples) EV formula (fixed)
```
EV = 0.50 * V_vendor + 0.35 * V_DE + 0.15 * V_AH
Final = min(EV, 1.25 * max(V_vendor, V_DE))
```
If `V_DE` or `V_AH` unavailable, treat as 0.

### 7.4 Gathering valuation
- Use conservative AH value (with friction).

### 7.5 AH price source priority
1. Manual override `GoldPH_DB.priceOverrides[itemID]`
2. TSM (if installed): pick a low-biased figure (implementation-defined)
3. Otherwise 0 (MVP should undercount rather than guess)

### 7.6 Friction
Apply a fixed multiplier to AH values to reflect sale risk and fees (e.g., `0.85`). (Hardcoded in MVP.)

---

## 8. Holdings & Reversals (No Double Counting)

### 8.1 Why Holdings
If you record expected value when an item is looted, then later get cash when it’s sold to a vendor, you must **remove** the expected value from inventory to avoid double counting.

### 8.2 FIFO Lots
On item acquisition:
- Create a lot with `{count, expectedEach, bucket}`
- Append to `session.holdings[itemID].lots`

On item leaving inventory via vendor sale:
- Consume lots FIFO to compute `heldExpectedValue`
- Post inventory reduction using that exact value

This ensures:
- Pricing snapshots remain stable even if market changes later
- Removal matches what was booked

---

## 9. Posting API (Internal)

### 9.1 Posting Representation (optional)
```lua
Posting = {
  ts = time(),
  dr = { account = "Assets:Cash", amount = 1200 },
  cr = { account = "Income:LootedCoin", amount = 1200 },
  tags = { "pickpocket" },
  meta = { itemID=..., spell=..., zone=... },
}
```

### 9.2 Helper functions
- `Ledger_Post(session, debitAccount, creditAccount, amountCopper, tags?, meta?)`
- `Ledger_AddBalance(session, account, deltaCopper)`
- `Holdings_AddLot(session, itemID, lot)`
- `Holdings_ConsumeFIFO(session, itemID, countToRemove) -> heldExpectedValueCopper`

> MVP can skip storing the postings list; balances are sufficient.

---

## 10. Event → Accounting Mapping (MVP)

### 10.1 Runtime State (not persisted)
```lua
state = {
  moneyLast = nil,

  merchantOpen = false,
  taxiOpen = false,

  -- pickpocket attribution windows
  pickpocketActiveUntil = 0,

  -- lockbox opening attribution windows
  openingLockboxUntil = 0,
  openingLockboxItemID = nil,

  -- gathering node attribution
  lastGatherTarget = nil,
  lastGatherTime = 0,
}
```

---

### 10.2 Session Start/Stop
**Start**
- Initialize session object
- `state.moneyLast = GetMoney()`

**Stop**
- set endedAt/duration
- persist to `GoldPH_DB.sessions[id]`
- clear runtime state

---

### 10.3 Money delta base event
**Event:** `PLAYER_MONEY`
- Update `state.moneyLast = GetMoney()`
- Do not post ledger entries here directly (avoid ambiguous attribution).
- Attribution should come from specific events/hooks below.

---

### 10.4 Looted coin (includes pickpocket coin + lockbox coin)
**Event:** `CHAT_MSG_MONEY`
- Parse copper `X`
- Post:
  - Dr `Assets:Cash` +X
  - Cr `Income:LootedCoin` +X
- If `time() <= state.pickpocketActiveUntil`:
  - `session.pickpocket.gold += X`
  - `session.ledger.balances["Income:Pickpocket:Coin"] += X` *(reporting only; do not touch Assets again)*
- If `time() <= state.openingLockboxUntil`:
  - `session.pickpocket.fromLockbox.gold += X`
  - `session.ledger.balances["Income:Pickpocket:FromLockbox:Coin"] += X` *(reporting only)*

---

### 10.5 Looted items (normal + pickpocket + lockbox)
**Event:** `CHAT_MSG_LOOT`
- Extract `(itemID, itemLink, count)`
- Resolve `name, quality, class/subclass`
- Determine context flags:
  - `isPickpocket = (time() <= state.pickpocketActiveUntil)`
  - `isFromLockbox = (time() <= state.openingLockboxUntil)`

**If lockbox item:**
- If `isPickpocket`:
  - `session.pickpocket.lockboxesLooted += count`
- Record in `items` with bucket `container_lockbox`, expected value = 0
- Do **not** post inventory value

**Else:**
- Compute `expectedEach` (valuation engine)
- expectedTotal = expectedEach * count
- Post inventory acquisition:
  - Dr `Assets:Inventory:<bucketAccount>` +expectedTotal
  - Cr `Income:ItemsLooted:<bucket>` +expectedTotal
- Update holdings FIFO:
  - Add lot `{count, expectedEach, bucket}`
- Update item aggregates:
  - increment counts and tracked totals using expectedEach
- If `isPickpocket`:
  - `session.pickpocket.value += expectedTotal`
  - `session.ledger.balances["Income:Pickpocket:Items"] += expectedTotal` *(reporting only)*
- If `isFromLockbox`:
  - `session.pickpocket.fromLockbox.value += expectedTotal`
  - `session.ledger.balances["Income:Pickpocket:FromLockbox:Items"] += expectedTotal` *(reporting only)*

---

### 10.6 Vendor sales (prevent double counting)
**Hook:** `UseContainerItem(bag, slot)`
When `state.merchantOpen == true`, treat as **selling to vendor**.

Before calling original function:
- Read item in bag/slot:
  - `itemID, count, vendorSellEach`
- saleProceeds = vendorSellEach * count

After the sale happens, post:

**A) Cash proceeds**
- Dr `Assets:Cash` +saleProceeds
- Cr `Income:VendorSales` +saleProceeds

**B) Remove expected value from inventory (reverse holdings)**
- `bucketTotals = Holdings_ConsumeFIFO_ByBucket(session, itemID, count)`
  - returns map: `{ bucketName -> heldExpectedValueCopper }`
- For each (bucketName, heldExpectedValue):
  - Cr `Assets:Inventory:<bucketAccount>` −heldExpectedValue
  - Dr `Equity:InventoryRealization` +heldExpectedValue

Also update `session.items[itemID]` aggregate:
- decrement count
- decrement trackedValueTotal by the same expected values removed
- remove entry if count hits 0

**If item not present in holdings (pre-session item):**
- No inventory reversal; only cash proceeds.

---

### 10.7 Merchant purchases + repairs
**Event:** `MERCHANT_SHOW`
- `state.merchantOpen = true`

**Event:** `MERCHANT_CLOSED`
- `state.merchantOpen = false`

**Hook:** `RepairAllItems()` (recommended)
- cost = `GetRepairAllCost()`
- If cost > 0 and player can repair:
  - Cr `Assets:Cash` −cost
  - Dr `Expense:Repairs` +cost

**Vendor buys**
- If implementing purchase hooks:
  - On purchase cost `C`:
    - Cr `Assets:Cash` −C
    - Dr `Expense:VendorBuys` +C
- If not: defer buy attribution in MVP.

---

### 10.8 Travel (flight path)
**Event:** `TAXIMAP_OPENED`
- `state.taxiOpen = true`

**Event:** `TAXIMAP_CLOSED`
- `state.taxiOpen = false`

If flight purchase cost `C` is captured (via hook or delta):
- Cr `Assets:Cash` −C
- Dr `Expense:Travel` +C

---

### 10.9 Quest gold
**Event:** `QUEST_TURNED_IN` (if reward copper available)
- reward = rewardCopper
- Dr `Assets:Cash` +reward
- Cr `Income:Quest` +reward

---

### 10.10 Gathering nodes (counts)
**Event:** `UNIT_SPELLCAST_SENT` (player)
- If spell is Mining/Herbalism gather:
  - `state.lastGatherTarget = targetName`
  - `state.lastGatherTime = time()`

**Event:** `UNIT_SPELLCAST_SUCCEEDED` (player)
- If gather spell and `time() - lastGatherTime <= 3`:
  - `session.gathering.totalNodes += 1`
  - `session.gathering.nodesByType[lastGatherTarget] += 1`
  - clear lastGatherTarget

---

### 10.11 Pickpocket context
**Event:** `UNIT_SPELLCAST_SUCCEEDED` (player)
- If spell == "Pick Pocket":
  - `state.pickpocketActiveUntil = GetTime() + 2.0`

### 10.12 Lockbox opening context
**Hook:** `UseContainerItem(bag, slot)`
- If item is lockbox and is being opened:
  - `state.openingLockboxUntil = GetTime() + 3.0`
  - `state.openingLockboxItemID = itemID`
  - `session.pickpocket.lockboxesOpened += 1`

---

## 11. Derived Metrics (UI)
Compute at render time:

- `netCash = balance("Assets:Cash")`
- `invExpected = balance("Assets:Inventory:TrashVendor") + balance("Assets:Inventory:RareMulti") + balance("Assets:Inventory:Gathering")`
- `netWorthChange = netCash + invExpected`

Per-hour:
- `cashPerHour = netCash / hours`
- `expectedPerHour = invExpected / hours`
- `totalPerHour = netWorthChange / hours`

Also show:
- Expected inventory gained by bucket (use Income:ItemsLooted:* balances)
- Pickpocket totals (session.pickpocket.*)
- Nodes totals (session.gathering.*)
- Top items by expected value contributed (session.items)

---

## 12. UI (MVP)
### 12.1 HUD
- Time elapsed
- Cash/hour
- Expected value/hour
- Total/hour
- Nodes gathered (total)

### 12.2 Session Summary Panel
For each session:
- Duration
- Cash in/out totals
- Expected inventory totals by bucket
- Total economic value and per-hour
- Pickpocket: gold/value + lockboxes looted/opened
- Nodes: total + top node types
- Top items by expected value contributed

(No tooltip integration.)

---

## 13. Addon File/Module Layout (suggested)
```
GoldPH/
  GoldPH.toc
  init.lua
  SessionManager.lua
  Ledger.lua
  Holdings.lua
  Valuation.lua
  Events.lua
  UI_HUD.lua
  UI_Summary.lua
```

---

## 14. Testing Plan (MVP)

### 14.1 Holdings + ledger tests (via slash command harness)
1. **Gray loot then vendor**
   - Loot gray: inventory +V
   - Vendor it: cash +vendor, inventory −V
   - NetWorthChange equals cash + remaining inventory (no double count)
2. **Loot green, no sale**
   - Inventory expected increases only
3. **Sell pre-session item**
   - Vendor sale adds cash but removes no inventory (heldExpectedValue=0)
4. **Pickpocket coin**
   - Coin increases cash and pickpocket.gold
5. **Pickpocket lockbox**
   - Lockbox count increments, no value
6. **Open lockbox**
   - Contents generate cash/items and are attributed to fromLockbox totals
7. **Gathering nodes**
   - Mining/herb cast events increment nodes by type

### 14.2 Invariants
- `Assets:Inventory:*` should equal sum of expected values remaining in `holdings` (within rounding)
- All per-item aggregates should match holdings total for that item

---

## 15. Edge Cases & Rules
- **Pre-session inventory** sold to vendor should not reduce expected inventory (heldExpected=0)
- **Mailing items**: Needs to be treated as inventory out -- use expected value
- **Destroying items**: Needs to remove this item from the ledger and zero out its expected value
- **Skinning nodes**: optional; can be generic “Skinning” bucket
- **Item cache delay**: `GetItemInfo` may return nil; handle retry

---

## 16. Implementation Notes for Claude Code
- Store all values in copper (integers).
- Keep balances as the source of truth; postings list optional.
- Pickpocket “income” should be tracked as counters or reporting balances only (do not double-post Cash).
- Implement `Holdings_ConsumeFIFO_ByBucket` so reversals correctly decrement the right inventory accounts.
- Snapshot expected value at acquisition time and store in lots; never recompute on sale.

---

## 17. Open Questions (defer safely)
- Exact TSM price keys to use (varies by TSM version)
- DE expected value table for Classic Anniversary
- Vendor buy attribution without hooks (can be added later)
