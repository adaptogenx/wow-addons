# GoldPH - Todo List & Improvements

## Critical Bugs

None currently. All known critical issues from earlier versions have been addressed as of v0.11.0.

---

## UI/UX Improvements

### 1. HUD Position Persistence
**Issue**: HUD position resets to default after `/reload`

**Solution**: Save HUD position to SavedVariables

**Files**: `UI_HUD.lua`, SavedVariables

**Priority**: MEDIUM

---

### 2. HUD Scaling/Font Size Options
**Issue**: HUD might be too small/large for some users

**Solution**: Add `/ph hud scale <0.5-2.0>` command to adjust HUD size

**Files**: `UI_HUD.lua`, `init.lua`

**Priority**: LOW

---

## Quality of Life

### 3. Auto-Start Session on Login (Optional)
**Issue**: User must remember to `/ph start` every time

**Solution**:
- Add setting: `pH_DB.settings.autoStart = true/false`
- Add command: `/ph autostart on|off`
- If enabled, automatically start session on PLAYER_ENTERING_WORLD (only if no active session)

**Files**: `init.lua`, SavedVariables

**Priority**: LOW

---

### 4. Session Notes/Tags
**Issue**: Hard to remember what each session was for

**Solution**:
- Add `/ph note <text>` to add note to current session
- Add `/ph tag <tag>` to tag session (e.g., "farming", "dungeons", "questing")
- Show in session history

**Files**: `SessionManager.lua`, `init.lua`

**Priority**: LOW

---

## Data Validation & Safety

### 5. Negative Cash Detection
**Issue**: If cash goes negative due to bugs, no warning

**Solution**: Add invariant check for negative Assets:Cash, warn user

**Files**: `Debug.lua`

**Priority**: MEDIUM

---

### 6. Session Data Backup
**Issue**: If SavedVariables corrupts, all history is lost

**Solution**:
- On session stop, create backup entry
- Keep last N sessions in backup
- Add `/ph restore` command

**Files**: `SessionManager.lua`, `init.lua`

**Priority**: LOW

---

## Performance

### 7. Ledger Balance Caching
**Issue**: `GetBalance()` iterates through balances table on every call

**Solution**: Cache frequently accessed balances (Assets:Cash, etc.)

**Files**: `Ledger.lua`

**Priority**: LOW

---

## Future Improvements

### 8. Item Cache Retry Logic
**Issue**: `GetItemInfo()` returns nil on first call, needs retry

**Solution**:
- Implement item cache with retry queue
- Process pending items on timer
- Add warning if item never resolves

**Files**: New `ItemCache.lua`

**Priority**: LOW

---

### 9. In-Game Help Improvements
**Issue**: `/ph help` is long, hard to read

**Solution**:
- Add categories: `/ph help session`, `/ph help debug`, `/ph help test`
- Add examples for each command
- Colorize output

**Files**: `init.lua`

**Priority**: LOW

---

## Known Issues (Won't Fix / Out of Scope)

### 10. Mail Items
**Issue**: Mailing items removes them from inventory but doesn't track it

**Status**: Out of scope for now (future phase)

---

### 11. Destroying Items
**Issue**: Destroying items removes expected value but doesn't track it

**Status**: Out of scope for now (future phase)

---

### 12. Trading Items
**Issue**: Trading items to another player doesn't track the value change

**Status**: Out of scope for now (future phase)

---

## Implementation Priority

**Recommended Next Improvements**:
- 1. HUD Position Persistence (MEDIUM)
- 5. Negative Cash Detection (MEDIUM)
- 6. Session Data Backup (LOW)
- 7. Ledger Balance Caching (LOW)
- 8. Item Cache Retry Logic (LOW)
- 9. In-Game Help Improvements (LOW)

**Optional QoL Enhancements**:
- 2. HUD Scaling/Font Size Options (LOW)
- 3. Auto-Start Session on Login (Optional) (LOW)
- 4. Session Notes/Tags (LOW)

**Known Out-of-Scope Limitations**:
- 10. Mail Items
- 11. Destroying Items
- 12. Trading Items

---

## Notes

- **Current Version**: v0.11.0
- **Phase Status**: Phases 1–6 complete; Phase 7 (Gathering Nodes & UI Polish) planned next.
- **Completed Phases**:
  - Phase 1: Foundation - Looted Gold Only (v0.1.0)
  - Phase 2: Vendor Expenses (v0.2.0)
  - Phase 3: Item Looting & Valuation (v0.3.1)
  - Phase 4: Vendor Sales & FIFO Reversals (v0.4.1)
  - Phase 5: Quest Rewards & Travel Expenses (v0.5.0)
  - Phase 6: Rogue Pickpocketing & Lockboxes (v0.6.0)
- **Architectural fixes completed**:
  - HUD visibility after relog fixed in v0.2.1-bugfix1
  - Character-scoped sessions fixed in v0.3.2
- Many LOW and MEDIUM priority items can be community contributions.
- Focus on core functionality and data integrity first, polish later.

