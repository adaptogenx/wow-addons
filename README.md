# pH - Gold Per Hour Tracker for WoW Classic Anniversary

A session-based gold tracking addon for World of Warcraft Classic Anniversary using double-ledger accounting to prevent double counting.

**Current Version**: 0.6.0 (Phase 6: Rogue Pickpocketing & Lockboxes)

## Features (Phase 1 & 2)

- ✅ Session-based tracking (start/stop sessions)
- ✅ Looted gold tracking
- ✅ **Repair expense tracking** (Phase 2)
- ✅ **Income/Expense breakdown in HUD** (Phase 2)
- ✅ Real-time cash per hour calculation
- ✅ Persistent sessions (survives `/reload`)
- ✅ Draggable HUD display
- ✅ Comprehensive debug/testing system

## Installation

### macOS (Automated)

```bash
./install.sh
```

The script will:
- Auto-detect your WoW Classic installation
- Backup existing installation if present
- Copy addon files to the correct location

### Manual Installation (macOS & Windows)

1. Copy the `ph/` directory to your WoW AddOns folder:
   - **Windows**: `World of Warcraft/_anniversary_/Interface/AddOns/`
   - **Mac**: `/Applications/World of Warcraft/_anniversary_/Interface/AddOns/`


2. Restart WoW or type `/reload` if already in-game

3. You should see: `[pH] Version 0.1.0-phase1 loaded`

## Quick Start

```
/ph start          # Start tracking session
                       # Go farm gold!
/ph stop           # Stop and save session
```

The HUD will display:
- Session number
- Time elapsed
- Total cash (net)
- Cash per hour
- Income (looted gold)
- Expenses (repairs)
- Net (income - expenses)

## Commands

### Session Commands
- `/ph start` - Start a new session
- `/ph stop` - Stop the active session
- `/ph show` - Show/hide the HUD
- `/ph status` - Show current session status
- `/ph help` - Show all commands

### Debug Commands
- `/ph debug on|off` - Enable/disable debug mode (auto-run invariants)
- `/ph debug verbose on|off` - Enable/disable verbose logging
- `/ph debug dump` - Dump current session state
- `/ph debug ledger` - Show ledger balances
- `/ph debug holdings` - Show holdings (Phase 3+)

### Test Commands
- `/ph test run` - Run automated test suite
- `/ph test loot <copper>` - Inject test gold (e.g., `/ph test loot 500`)
- `/ph test repair <copper>` - Inject test repair cost (e.g., `/ph test repair 250`)

## Architecture

pH uses **double-ledger accounting** to ensure accurate tracking without double counting. When you loot gold:

```
Dr Assets:Cash         +500 copper
Cr Income:LootedCoin   +500 copper
```

This ensures that when items are later sold (Phase 4), we can properly remove their expected value from inventory to avoid counting the same value twice.

See [CLAUDE.md](CLAUDE.md) for architecture details and [GoldPH_TDD.md](GoldPH_TDD.md) for technical specification.

## Known Issues

See [TODO.md](TODO.md) for a complete list of improvements and known issues.

**Critical bugs to fix before Phase 3**:
1. HUD visibility after relog (must manually `/ph show`)
2. Session time continues counting when logged out

## Development Phases

This addon is being developed in 7 incremental phases:

- **Phase 1** (✅ Complete): Looted gold tracking + debug system
- **Phase 2** (✅ Complete): Vendor expenses (repairs, purchases)
- **Phase 3** (✅ Complete): Item looting & valuation
- **Phase 4** (✅ Complete): Vendor sales with FIFO reversals (prevents double counting)
- **Phase 5** (✅ Complete): Quest rewards & travel expenses
- **Phase 6** (✅ Complete): Rogue pickpocketing & lockboxes
- **Phase 7** (Planned): Gathering nodes & UI polish

Each phase is implemented as a separate PR for review. See the [multi-phase plan](.claude/plans/sprightly-gliding-thunder.md) for details.

## Testing

### Manual Testing
1. Start a session: `/ph start`
2. Loot gold from mobs
3. Check HUD updates in real-time
4. Reload UI: `/reload`
5. Verify session continues
6. Stop session: `/ph stop`

### Automated Testing
```
/ph debug on
/ph test run
```

All tests should pass (green). The test suite includes:
- Basic loot posting
- Multiple loot events
- Zero amount handling
- Invariant validation

### Test Injection (No In-Game Actions Required)
```
/ph start
/ph test loot 1000   # Inject 1000 copper
/ph test loot 500    # Inject 500 copper
/ph status           # Should show 1500 copper total
```

## Files Structure

```
ph/
├── ph.toc          - Addon manifest
├── init.lua            - Entry point, slash commands
├── Ledger.lua          - Double-entry bookkeeping
├── SessionManager.lua  - Session lifecycle
├── Events.lua          - Event handling (CHAT_MSG_MONEY)
├── Debug.lua           - Debug/testing infrastructure
└── UI_HUD.lua          - Heads-up display
```

## Technical Details

- **Currency Format**: All values stored in copper (integers)
- **Persistence**: Uses SavedVariables (`pH_DB`)
- **WoW Version**: Classic Anniversary (Interface 11504)
- **Lua Version**: 5.1

## Troubleshooting

**HUD not showing?**
- Ensure session is active: `/ph start`
- Try: `/ph show`

**Session not persisting after reload?**
- Check SavedVariables are enabled in WoW settings
- Verify `pH_DB` exists: `/dump pH_DB`

**Want to test without looting?**
- Use test injection: `/ph test loot 500`

**Debug an issue?**
- Enable verbose mode: `/ph debug verbose on`
- Check session state: `/ph debug dump`

## Development

### Linting

This project uses [luacheck](https://github.com/lunarmodules/luacheck) for code quality. A pre-commit hook automatically runs luacheck before each commit.

**Install luacheck:**
```bash
# Using pip
pip install luacheck

# Using homebrew (macOS)
brew install luacheck
```

**Run linting manually:**
```bash
luacheck ph/
```

The `.luacheckrc` configuration file is configured for WoW Classic Anniversary's Lua 5.1 environment and includes common WoW API globals.

**Pre-commit hook:**
- Automatically runs on `git commit`
- Only checks staged `.lua` files
- Blocks commit if linting fails
- Can be bypassed with `git commit --no-verify` (not recommended)

**Setup hooks:**
```bash
./setup-hooks.sh
```

This installs the pre-commit hook that runs luacheck automatically.

## Contributing

This addon is developed incrementally following a multi-phase plan. Each phase builds on the previous:
1. Foundation (Phase 1) ✅
2. Expenses (Phase 2) ✅
3. Item valuation (Phase 3) ✅
4. Vendor sales with FIFO (Phase 4) ✅ - **Critical for no double counting**
5. Quest/Travel (Phase 5) ✅
6. Pickpocketing (Phase 6)
7. Gathering & UI polish (Phase 7)

See implementation summaries:
- [PHASE1_SUMMARY.md](PHASE1_SUMMARY.md) - Foundation with looted gold tracking
- [PHASE2_SUMMARY.md](PHASE2_SUMMARY.md) - Vendor expense tracking

## License

This addon is provided as-is for personal use. See technical documentation for implementation details.

## Credits

- **Architecture**: Double-ledger accounting system
- **Implementation**: Multi-phase incremental approach
- **Testing**: Comprehensive debug/test infrastructure

For full technical specification, see [GoldPH_TDD.md](GoldPH_TDD.md).
