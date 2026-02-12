# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pH is a World of Warcraft addon (Classic Anniversary) that tracks gold-per-hour earnings using a session-based, **double-ledger accounting model**. It tracks both actual cash (gold gained/spent) and expected inventory value (conservative liquidation value of items acquired during a session).

**Key Design Philosophy:**
- **Conservative valuation**: Avoid inflated market pricing
- **No double counting**: Use holdings and ledger to prevent counting items twice (once when looted, again when vendored)
- **Snapshot pricing**: Store per-session prices at acquisition time
- **Minimal dependencies**: Optionally use TSM prices if present, but never require them

## UI Design
Follow the guidelines in: PH_UI_DESIGN_BRIEF_AND_RULES.md when creating any component or interface

## Architecture

### Component Structure

The addon follows a modular design (see pH_TDD.md §4.1 for full details):

1. **SessionManager** - Start/stop/persist sessions, compute derived metrics
2. **Ledger** - Account balances using double-entry bookkeeping principles
3. **Holdings** - Per-item FIFO lots storing expected values at acquisition time
4. **ValuationEngine** - Classify items into buckets and compute conservative expected values
5. **EventRouter** - Subscribe to WoW events and dispatch to accounting actions
6. **UI** - Minimal HUD + session summary panel

### Core Data Model

**All currency values are stored in copper (integers).**

The saved variables structure (`pH_DB`) includes:
- `meta`: Version, realm, faction, character, lastSessionId
- `settings`: User preferences
- `priceOverrides`: Manual item price overrides
- `activeSession`: Current session object (or nil)
- `sessions`: Historical sessions by ID

Each **Session** contains:
- Ledger balances (chart of accounts using double-entry model)
- Per-item aggregates (for UI breakdown)
- FIFO holdings lots (for reversal of expected value on sale)
- Gathering node counts
- Pickpocket statistics

See pH_TDD.md §5 for complete data structures.

## Double-Ledger Accounting System

### Core Invariant
```
Net Worth Change = ΔCash + ΔInventoryExpected
```

### Chart of Accounts
- **Assets**: `Assets:Cash`, `Assets:Inventory:TrashVendor`, `Assets:Inventory:RareMulti`, `Assets:Inventory:Gathering`, `Assets:Inventory:Containers:Lockbox`
- **Income**: `Income:LootedCoin`, `Income:Quest`, `Income:VendorSales`, `Income:ItemsLooted:<bucket>`, `Income:Pickpocket:*`
- **Expenses**: `Expense:Repairs`, `Expense:VendorBuys`, `Expense:Travel`
- **Equity**: `Equity:InventoryRealization` (offset when removing inventory expected value on sale)

This structure prevents double counting and maintains accounting invariants.

## Valuation Model

### Item Buckets
- `trash_vendor`: Gray items and most whites valued at vendor price
- `rare_multi`: Greens/blues/purples using multi-path expected value formula
- `gathering`: Mats (ore, herbs, leather, cloth)
- `container_lockbox`: Lockboxes have **expected value = 0 until opened**

### Rare Multi EV Formula (Fixed, Conservative)
```
EV = 0.50 * V_vendor + 0.35 * V_DE + 0.15 * V_AH
Final = min(EV, 1.25 * max(V_vendor, V_DE))
```

### AH Price Sources (Priority Order)
1. Manual override in `pH_DB.priceOverrides[itemID]`
2. TSM (if installed): use low-biased figure
3. Otherwise 0 (better to undercount than guess)

Apply friction multiplier (0.85) to AH values to reflect sale risk and fees.

## Holdings & FIFO Lots (Critical for No Double Counting)

When an item is looted:
1. Compute `expectedEach` value using ValuationEngine
2. Create FIFO lot: `{count, expectedEach, bucket}`
3. Post inventory acquisition to ledger
4. Store lot in `session.holdings[itemID].lots`

When the item is sold to vendor:
1. Consume lots FIFO to compute `heldExpectedValue`
2. Post cash proceeds: Dr `Assets:Cash`, Cr `Income:VendorSales`
3. Post inventory reduction: Cr `Assets:Inventory:<bucket>`, Dr `Equity:InventoryRealization`

This ensures pricing snapshots remain stable and removals match what was originally booked.

## Event Handling & Attribution

### Runtime State (Not Persisted)
- `moneyLast`: Last known player money for delta calculation
- `merchantOpen`, `taxiOpen`: Context flags
- `pickpocketActiveUntil`: Attribution window for pickpocket events
- `openingLockboxUntil`, `openingLockboxItemID`: Attribution for lockbox contents

### Key Event Mappings
- **CHAT_MSG_MONEY**: Looted coin (includes pickpocket coin if within attribution window)
- **CHAT_MSG_LOOT**: Looted items (normal, pickpocket, or from lockbox)
- **MERCHANT_SHOW/CLOSED**: Track merchant context
- **UNIT_SPELLCAST_SUCCEEDED**: Detect pickpocket and gathering spells
- **UseContainerItem hook**: Detect vendor sales and lockbox opening

See pH_TDD.md §10 for complete event-to-accounting mapping.

## Special Cases

### Rogue Pickpocketing
- Use `pickpocketActiveUntil` attribution window (2 seconds)
- Separate tracking for pickpocket coin and items
- Lockboxes from pickpocket have value = 0 until opened
- When lockbox opened, contents attributed to `fromLockbox` totals

### Vendor Sales (No Double Counting)
1. Hook `UseContainerItem` when merchant open
2. Read item's vendor price and holdings
3. Post cash proceeds
4. **Consume FIFO lots** to get held expected value
5. Reverse inventory value by bucket using `Holdings_ConsumeFIFO_ByBucket`
6. If item not in holdings (pre-session): only record cash proceeds

### Gathering Nodes
- Track via `UNIT_SPELLCAST_SENT` (capture target name)
- Confirm via `UNIT_SPELLCAST_SUCCEEDED` (increment counts)
- Store total nodes + per-node-type breakdown

## Development Guidelines

### Data Integrity Rules
1. **Always store values in copper** (integers only)
2. **Balances are source of truth** - postings list is optional for debugging
3. **Snapshot expected values at acquisition time** - never recompute on sale
4. **Pickpocket income = reporting counters only** - do not double-post to Assets:Cash
5. Implement `Holdings_ConsumeFIFO_ByBucket` to correctly decrement the right inventory accounts

### Item Information Handling
- `GetItemInfo()` may return nil initially (cache delay)
- Implement retry logic for item lookups
- Store itemID, name, quality in aggregates for UI display

### Edge Cases (MVP Scope)
- **Pre-session inventory sold**: heldExpected = 0, only record cash proceeds
- **Mailing items**: Out of scope (future: treat as inventory out)
- **Destroying items**: Out of scope (future: inventory out)
- **Skinning nodes**: Can be generic "Skinning" bucket

## WoW Addon Development Context

### Lua Environment
- This is a WoW addon written in Lua 5.1 (WoW Classic Anniversary)
- Uses WoW API functions like `GetMoney()`, `GetItemInfo()`, `GetTime()`
- Hooks standard WoW functions (e.g., `UseContainerItem`, `RepairAllItems`)
- Events registered via `frame:RegisterEvent()` pattern

### Addon Structure
Typical structure:
```
ph/
  ph.toc          -- Addon manifest
  init.lua            -- Entry point
  SessionManager.lua  -- Session lifecycle
  Ledger.lua          -- Double-entry accounting
  Holdings.lua        -- FIFO lot management
  Valuation.lua       -- Item valuation engine
  Events.lua          -- Event router
  UI_HUD.lua          -- HUD frame
  UI_Summary.lua      -- Session summary panel
```

### SavedVariables
- Declared in `.toc` file
- Persisted across game sessions/reloads
- Root variable: `pH_DB`

## Testing Approach

### Manual Testing Scenarios (See pH_TDD.md §14)
1. Gray loot → vendor (verify no double count)
2. Loot green, no sale (inventory expected increases only)
3. Sell pre-session item (cash only, no inventory reversal)
4. Pickpocket coin (cash + pickpocket.gold)
5. Pickpocket lockbox (count increments, no value)
6. Open lockbox (contents attributed to fromLockbox)
7. Gathering nodes (mine/herb cast events increment by type)

### Invariant Checks
- `Assets:Inventory:*` should equal sum of expected values in holdings
- Per-item aggregates should match holdings totals
- NetWorthChange = balance("Assets:Cash") + sum(balance("Assets:Inventory:*"))

## Key Technical Decisions

### Why Double-Entry Ledger?
Prevents double counting and maintains clear invariants. Every economic change is explainable through debits/credits.

### Why FIFO Lots?
- Preserves pricing snapshots even if market changes
- Ensures exact reversal of booked expected value on sale
- Handles partial sales correctly

### Why Conservative Valuation?
Better to undercount than overestimate. Fixed formula avoids user confusion and prevents gaming the system.

### Why Zero Value for Lockboxes?
Prevents attributing value to containers that may never be opened. Only count contents when realized.

## Non-Goals (MVP)
- No tooltip modifications
- No automatic activity detection
- No CSV export
- No AH sale realization tracking
- No configurable valuation weights
- No advanced disenchant tables (DE value = 0 until implemented)
- No location tracking for nodes

## Reference Document

For complete technical specifications, see `pH_TDD.md` which contains:
- Detailed data structures (§5)
- Complete chart of accounts (§6)
- Valuation formulas (§7)
- Complete event-to-accounting mapping (§10)
- All edge cases and rules (§15)
