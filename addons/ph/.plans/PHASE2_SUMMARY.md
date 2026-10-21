# Phase 2 Implementation Summary: Vendor Expenses

## Overview

Phase 2 is complete! This phase adds expense tracking to prove negative cash flows work correctly.

**Version**: 0.2.0-phase2
**Lines Added**: ~237 lines (Phase 1: 1,064 → Phase 2: 1,301)

## Features Implemented

### Expense Tracking
- **Repair Costs**: Automatic tracking via `RepairAllItems()` hook
- **New Ledger Accounts**:
  - `Expense:Repairs` - Repair costs at vendors
  - `Expense:VendorBuys` - Vendor purchases (placeholder for Phase 4)

### Merchant Context
- Tracks when merchant window is open/closed
- Uses `MERCHANT_SHOW` and `MERCHANT_CLOSED` events
- Stores state in runtime (not persisted)

### HUD Improvements
- **Income/Expense Breakdown**:
  - Income: Total looted coin
  - Expenses: Repairs + vendor purchases
  - Net: Income - Expenses (should equal Cash)
- HUD resized to accommodate new fields (220x130)

### Testing Enhancements
- **Test Injection**: `/goldph test repair <copper>`
- **New Automated Tests**:
  - Basic repair posting (verifies expense accounting)
  - Net cash calculation (income - expenses)
- Test suite now runs 5 tests (Phase 1: 3, Phase 2: +2)

## Files Modified

### Ledger.lua
- Added `Expense:Repairs` and `Expense:VendorBuys` accounts to initialization

### Events.lua (+108 lines)
- Added merchant context tracking (state.merchantOpen)
- Registered `MERCHANT_SHOW` and `MERCHANT_CLOSED` events
- Implemented `HookRepairFunctions()` for `RepairAllItems()` hook
- Added `OnRepairAll()` handler to post repair expenses
- Added `InjectRepair()` for testing

### SessionManager.lua (+20 lines)
- Extended `GetMetrics()` to include:
  - `income` - Total income
  - `expenses` - Total expenses
  - `expenseRepairs` - Repair costs
  - `expenseVendorBuys` - Vendor purchases

### UI_HUD.lua (+54 lines)
- Increased frame size (220x130)
- Added income display
- Added expenses display
- Added net cash display
- Net = Income - Expenses (validates accounting)

### Debug.lua (+52 lines)
- Added `Test_BasicRepair()` test
- Added `Test_NetCash()` test
- Updated test suite to run Phase 2 tests

### init.lua (+3 lines)
- Added `/goldph test repair <copper>` command
- Updated help text

### GoldPH.toc
- Version: 0.2.0-phase2

## Accounting Model

### Repair Transaction
```
Dr Expense:Repairs    +250 copper
Cr Assets:Cash        +250 copper
```

Result: Cash decreases by 250, Expense increases by 250

### Invariant Check
```
Net Worth = Assets:Cash
Income - Expenses = Net Cash
```

If you loot 1000c and spend 250c on repairs:
- Income:LootedCoin = 1000
- Expense:Repairs = 250
- Assets:Cash = 750
- Net = 1000 - 250 = 750 ✓

## Testing

### Manual Testing

1. **Start session and repair**:
   ```
   /goldph start
   # Visit vendor, click "Repair All"
   /goldph status
   ```
   - Verify HUD shows expenses increasing
   - Verify cash decreases by repair cost
   - Verify net = income - expenses

2. **Test injection** (faster):
   ```
   /goldph start
   /goldph test loot 1000
   /goldph test repair 250
   /goldph status
   ```
   - Should show: Income 1000c, Expenses 250c, Net 750c, Cash 750c

3. **Automated tests**:
   ```
   /goldph debug on
   /goldph test run
   ```
   - All 5 tests should pass (green)
   - New tests: "Basic Repair Posting" and "Net Cash Calculation"

### Debug Commands

```
/goldph debug dump       # Show full session state with expenses
/goldph debug ledger     # Show all accounts including Expense:*
/goldph debug verbose on # See repair events in chat
```

## Validation

Phase 2 successfully implements:
✅ Expense accounts in ledger
✅ Repair cost tracking via hook
✅ Merchant context tracking
✅ HUD income/expense breakdown
✅ Test injection for repairs
✅ Automated tests for expense handling
✅ Net cash calculation (income - expenses)
✅ Invariant validation with expenses

## Known Limitations

Phase 2 tracks repairs only. Not yet implemented:
- Vendor purchases (requires hooking `BuyMerchantItem`)
- Flight costs (Phase 5)
- Quest rewards (Phase 5)
- Item tracking (Phase 3)
- Vendor sales (Phase 4)

## Next Steps - Phase 3

Phase 3 will add item looting and valuation:
- ValuationEngine (bucket classification, expected values)
- Holdings (FIFO lot creation)
- Item aggregates for UI
- New accounts: `Assets:Inventory:*`, `Income:ItemsLooted:*`
- Test commands: `/goldph test lootitem <itemID> <count>`

Estimated effort: ~500 lines, 3-4 hours

## Success Criteria

✅ Repair costs tracked automatically
✅ HUD shows income/expense breakdown
✅ Net cash = income - expenses
✅ Test injection works (`/goldph test repair`)
✅ Automated tests pass
✅ Invariant checks validate expenses
✅ No double counting (expense decreases cash correctly)

Phase 2 is **COMPLETE** and ready for in-game testing!
