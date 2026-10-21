# XP/Rep/Honor Tracking - Test Plan

## Test Environment Setup

1. **Load Addon**: `/reload` in-game to load the updated addon
2. **Start Session**: `/goldph start` to begin tracking
3. **Debug Mode**: Enable verbose logging with `/goldph debug verbose on`

## Test Scenarios

### 1. XP Tracking Tests

#### Test 1.1: Normal XP Gain
**Steps:**
1. Start a session at level < 60 (Classic) or < 70 (TBC)
2. Kill 5-10 mobs that give XP
3. Observe HUD for XP metrics chip

**Expected Results:**
- HUD shows "Metrics: XP X/h" chip (only when expanded)
- Debug log shows: `[GoldPH] XP gained: X (total: Y)`
- `/goldph session` shows xpGained value

**Pass Criteria:** XP accumulates correctly, per-hour rate updates

#### Test 1.2: Level-Up Rollover
**Steps:**
1. Start session near end of level (e.g., 95% to next level)
2. Kill enough mobs to level up
3. Continue killing mobs after level-up

**Expected Results:**
- XP delta correctly calculated across level boundary
- Debug log shows proper delta calculation
- No negative or incorrect XP values

**Pass Criteria:** XP continues to accumulate correctly after level-up

#### Test 1.3: Max Level Character
**Steps:**
1. Start session with max level character (60 in Classic, 70 in TBC)
2. Kill mobs (no XP should be gained)
3. Check HUD and session metrics

**Expected Results:**
- No XP tracking initialized
- No XP chips shown in HUD
- No errors in chat or Lua errors
- Session has `xpEnabled = false`

**Pass Criteria:** Max level characters work without errors, no XP tracking

### 2. Reputation Tracking Tests

#### Test 2.1: Single Faction Gain
**Steps:**
1. Start a session
2. Turn in quest that rewards reputation with one faction
3. Check HUD and debug log

**Expected Results:**
- HUD shows "Metrics: Rep X/h" chip
- Debug log shows: `[GoldPH] Rep gained: FactionName +X`
- Session has `repEnabled = true`, `repGained > 0`

**Pass Criteria:** Reputation tracked correctly, byFaction populated

#### Test 2.2: Multiple Factions
**Steps:**
1. Start session
2. Turn in quests or kill mobs that grant rep with 3+ different factions
3. View session detail pane

**Expected Results:**
- Total repGained is sum of all factions
- Detail pane shows top 3 factions by gain
- Factions listed with individual gain amounts

**Pass Criteria:** Multiple factions tracked correctly, top 3 shown in detail

#### Test 2.3: Faction Index Stability
**Steps:**
1. Start session
2. Collapse/expand faction headers in reputation pane
3. Gain reputation with a faction
4. Check that tracking still works

**Expected Results:**
- Reputation tracking continues to work despite UI changes
- No errors about invalid faction indices
- FactionID-based tracking prevents issues

**Pass Criteria:** Tracking stable regardless of UI state

### 3. Honor Tracking Tests

#### Test 3.1: Honor Gain from BG
**Steps:**
1. Start session
2. Enter a battleground
3. Participate and gain honor
4. Check HUD

**Expected Results:**
- HUD shows "Metrics: Hon X/h" chip
- Debug log shows: `[GoldPH] Honor gained: X (total: Y, HKs: Z)`
- Session has `honorEnabled = true`, `honorGained > 0`

**Pass Criteria:** Honor accumulates from battleground events

#### Test 3.2: Honorable Kills
**Steps:**
1. Start session
2. Get killing blow on enemy player
3. Check honor metrics

**Expected Results:**
- honorKills counter increments
- Detail pane shows "Honorable Kills: X"
- Debug log confirms HK detection

**Pass Criteria:** Honorable kills tracked separately from honor points

#### Test 3.3: No Honor System (PvE Server)
**Steps:**
1. Start session on PvE server without honor system
2. Play normally
3. Check metrics

**Expected Results:**
- No honor tracking occurs
- `honorEnabled` stays false
- No errors or UI issues

**Pass Criteria:** Graceful handling when honor system unavailable

### 4. UI Integration Tests

#### Test 4.1: HUD Metrics Chips
**Steps:**
1. Start session
2. Gain XP, Rep, and Honor
3. Observe HUD in both expanded and minimized states

**Expected Results:**
- **Expanded**: "Metrics: XP Xk/h | Rep Y/h | Hon Z/h" row visible
- **Minimized**: Metrics row hidden
- Only active metrics shown (if only XP: "Metrics: XP Xk/h")
- Compact format, readable

**Pass Criteria:** Chips display correctly, adaptive to available metrics

#### Test 4.2: History List Badges
**Steps:**
1. Complete multiple sessions with different metric combinations:
   - Session A: XP only
   - Session B: XP + Rep
   - Session C: XP + Rep + Honor
   - Session D: None
2. View history list

**Expected Results:**
- Session A: `[XP]` badge (blue)
- Session B: `[XP] [Rep]` badges
- Session C: `[XP] [Rep] [Hon]` badges
- Session D: No XP/Rep/Hon badges (may have `[G]` or `[P]`)

**Pass Criteria:** Badges only shown for sessions with data

#### Test 4.3: History Filters
**Steps:**
1. Check "XP" filter checkbox
2. Verify only sessions with XP data shown
3. Uncheck, check "Rep" filter
4. Verify only sessions with Rep data shown
5. Check multiple filters

**Expected Results:**
- Filters work independently
- Can combine multiple filters (AND logic)
- List updates immediately

**Pass Criteria:** Filters correctly show/hide sessions based on metrics

#### Test 4.4: Sort by Metrics
**Steps:**
1. Click Sort dropdown
2. Select "XP/Hour"
3. Verify sessions sorted by XP/hr descending
4. Repeat for "Rep/Hour" and "Honor/Hour"

**Expected Results:**
- Sessions sorted correctly by selected metric
- Highest per-hour rate at top
- Sessions without metric appear at bottom (0 value)

**Pass Criteria:** Sorting works for all 3 new metrics

#### Test 4.5: Detail Pane Sections
**Steps:**
1. Select session with XP/Rep/Honor data
2. View Summary tab in detail pane

**Expected Results:**
- **Experience section**: Shows XP gained, XP/hr (blue)
- **Reputation section**: Shows Rep gained, Rep/hr, top 3 factions list
- **Honor section**: Shows Honor gained, Honor/hr, HKs (if > 0)
- Sections only appear if metric enabled

**Pass Criteria:** Detail sections display correctly with proper formatting

### 5. Performance Tests

#### Test 5.1: Event Handler Performance
**Steps:**
1. Start session
2. Monitor FPS during:
   - Rapid mob killing (XP events)
   - Mass rep gains (quest turn-in spam)
   - Honor gains in large BG fight
3. Check for FPS drops

**Expected Results:**
- No noticeable FPS impact
- Event handlers process quickly (< 1ms)
- No lag spikes

**Pass Criteria:** No performance degradation from new tracking

#### Test 5.2: Index Build Performance
**Steps:**
1. Create 50+ sessions with mixed XP/Rep/Honor data
2. Rebuild index: `/goldph index rebuild`
3. Measure build time

**Expected Results:**
- Build completes in < 1 second
- Debug log shows: `[GoldPH Index] Built index with X sessions in 0.XXXs`
- No UI freeze

**Pass Criteria:** Index build remains fast with new metrics

### 6. Backward Compatibility Tests

#### Test 6.1: Old Sessions
**Steps:**
1. Load addon with existing sessions (created before this update)
2. View history list and detail pane

**Expected Results:**
- Old sessions display without errors
- XP/Rep/Honor fields default to 0 or false
- No badges shown for old sessions
- No Lua errors

**Pass Criteria:** Old sessions work correctly, no migration errors

#### Test 6.2: Mixed Session Types
**Steps:**
1. Create new sessions with XP/Rep/Honor
2. View history list with both old and new sessions
3. Apply filters

**Expected Results:**
- Old and new sessions coexist
- Filters work correctly (old sessions filtered out by XP/Rep/Hon filters)
- Sorting works (old sessions at bottom for metric sorts)

**Pass Criteria:** Mixed session types handled correctly

### 7. Edge Cases

#### Test 7.1: Rapid Event Spam
**Steps:**
1. Start session
2. Use AoE abilities to tag many mobs simultaneously
3. Gain XP from all at once

**Expected Results:**
- All XP gains tracked correctly
- No events missed
- No Lua errors from event flooding

**Pass Criteria:** Event spam handled gracefully

#### Test 7.2: Session Across Multiple Logins
**Steps:**
1. Start session
2. Gain XP/Rep
3. Log out (session remains active)
4. Log back in
5. Gain more XP/Rep
6. Stop session

**Expected Results:**
- Metrics accumulate correctly across logins
- Runtime state re-initialized on login
- Final totals correct

**Pass Criteria:** Multi-login sessions work correctly

#### Test 7.3: Empty Sessions
**Steps:**
1. Start session
2. Stop immediately without gaining any metrics
3. View in history

**Expected Results:**
- Session appears in history with 0 values
- No errors
- No badges shown

**Pass Criteria:** Empty sessions handled gracefully

## Test Report Template

```
Test: [Test ID and Name]
Date: [Date]
Tester: [Name]
WoW Version: [Classic/TBC/Wrath/etc.]
Character: [Name-Server-Faction]
Level: [X]

Result: [PASS/FAIL]

Notes:
- [Any observations]
- [Issues encountered]
- [Performance notes]

Screenshots: [Links if applicable]
```

## Critical Success Criteria

- ✓ No Lua errors during any test
- ✓ All metrics track correctly
- ✓ UI displays properly in all states
- ✓ Filters and sorting work
- ✓ No performance impact
- ✓ Backward compatibility maintained
- ✓ Max level characters work without errors

## Regression Testing

After any bug fixes, re-run:
1. Test 1.1 (Normal XP Gain)
2. Test 2.1 (Single Faction Gain)
3. Test 3.1 (Honor Gain from BG)
4. Test 4.1 (HUD Metrics Chips)
5. Test 6.1 (Old Sessions)

## Known Issues to Watch For

1. **Faction index drift**: If rep tracking stops working after UI changes → factionID caching issue
2. **XP rollover bugs**: Negative XP or huge spikes after level-up → rollover detection issue
3. **Honor parsing failures**: Some honor messages not parsed → pattern matching issue
4. **UI clipping**: Metric chips too long, text overlaps → formatting issue
5. **Performance**: FPS drops during event spam → event handler optimization needed

## Testing Tools

- `/goldph debug verbose on` - Enable detailed logging
- `/goldph session` - View current session metrics
- `/goldph index rebuild` - Force index rebuild
- `/console scriptErrors 1` - Show Lua errors in-game
- `/framestack` - Debug UI frame layering (if available)
