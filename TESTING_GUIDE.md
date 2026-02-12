# GoldPH History UI Testing Guide

## Quick Start

1. **Reload UI** in game: `/reload`
2. **Open history**: `/ph history` or `/gph history`
3. **Create test sessions** (if none exist):
   ```
   /ph start
   /ph test loot 500000   (50 gold)
   /ph test lootitem 3404 5   (loot 5x Buzzard Wing)
   /ph stop
   ```

## Testing Checklist

### Phase 1: Index (Data Layer)
- [ ] Open history with 0 sessions → Shows "No sessions" message
- [ ] Open history with 1+ sessions → Index builds quickly (<500ms)
- [ ] Check console for build time: Should print "[GoldPH Index] Built index with N sessions in X.XXXs"
- [ ] Enable debug: `/ph debug verbose on`
- [ ] Verify no errors in console

### Phase 2: Main Frame + List
- [ ] `/ph history` opens centered frame (640x480)
- [ ] Frame is draggable (click+drag title area)
- [ ] Sessions display in list (left pane, 240px width)
- [ ] Each row shows: gold/hr, zone, duration, character, badges
- [ ] Scroll through sessions (mouse wheel)
- [ ] Click a session → Highlights selected row
- [ ] Close and reopen → Position persists
- [ ] Close and reopen → Last selected session is remembered

### Phase 3: Filters
- [ ] **Sort dropdown**: Change sort order → List updates immediately
  - [ ] Total g/hr (default)
  - [ ] Cash g/hr
  - [ ] Expected g/hr
  - [ ] Date
- [ ] **Zone dropdown**: Filter by zone → Only matching sessions shown
  - [ ] "All Zones" shows all
  - [ ] Select specific zone → Filters correctly
- [ ] **Character dropdown**: Filter by character
  - [ ] "All Characters" shows all
  - [ ] Select specific char → Filters correctly
- [ ] **Search box**: Type text → Filters by zone/character/item name
  - [ ] Empty search → Shows all
  - [ ] Partial match works (e.g., "Zul" finds "Zul'Farrak")
- [ ] **Gathering checkbox**: Check → Shows only gathering sessions
- [ ] **Pickpocket checkbox**: Check → Shows only pickpocket sessions
- [ ] **Multiple filters**: Combine filters → Works correctly (AND logic)
- [ ] Close and reopen → Filter state persists

### Phase 4: Summary Tab
- [ ] Click a session → Detail pane shows Summary tab
- [ ] **Session Info section** displays:
  - [ ] Session ID, Zone, Start/End dates, Duration
- [ ] **Economic Summary section** displays:
  - [ ] Total Value, Total/hr (gold color)
  - [ ] Cash, Cash/hr (green color)
  - [ ] Expected Inventory, Expected/hr (light blue)
- [ ] **Cash Flow section** displays:
  - [ ] Looted Coin, Quest Rewards, Vendor Sales
  - [ ] Expenses (red): Repairs, Vendor Purchases, Travel
- [ ] **Inventory Expected section** displays:
  - [ ] Vendor Trash, Rare/Multi, Gathering
- [ ] **Pickpocket section** (if applicable):
  - [ ] Only shows if session has pickpocket data
  - [ ] Coin, Items Value, Lockbox stats
- [ ] **Gathering section** (if applicable):
  - [ ] Only shows if session has gathering data
  - [ ] Total Nodes, Nodes/hr
  - [ ] Gathering tab shows per-node-type breakdown with correct counts and percentages
- [ ] Content is scrollable if long
- [ ] Switch between sessions → Detail updates correctly
- [ ] No errors in console

### Tab System
- [ ] Four tabs visible: Summary, Items, Gathering, Compare
- [ ] Click tabs → Switch between tabs
- [ ] Active tab highlighted (blue background)
- [ ] Inactive tabs dimmed (gray background)
- [ ] Items tab shows "Coming in Phase 5" placeholder
- [ ] Gathering tab shows "Coming in Phase 7" placeholder
- [ ] Compare tab shows "Coming in Phase 8" placeholder
- [ ] Close and reopen → Active tab persists

### Edge Cases
- [ ] **No sessions**: Shows appropriate message
- [ ] **Active session**: Excluded from history (not shown in list)
- [ ] **Session without zone**: Displays as "Unknown"
- [ ] **Session without items**: Summary still works
- [ ] **Session without gathering**: No gathering section
- [ ] **Session without pickpocket**: No pickpocket section
- [ ] **Very long zone name**: Truncates with "..." in list
- [ ] **Many sessions (50+)**: Scrolling is smooth, no lag
- [ ] **Empty search**: Clears filter correctly

### Performance
- [ ] Index build completes in <500ms for 100 sessions
- [ ] Scrolling is smooth (no frame drops)
- [ ] Filter changes are instant (<100ms)
- [ ] Tab switching is instant (<50ms)
- [ ] No memory leaks (play for extended time, check with `/run print(collectgarbage("count"))`)

### Integration
- [ ] Stop active session → Index marked stale
- [ ] Reopen history → Index rebuilds automatically
- [ ] New session appears in list after stop
- [ ] Metrics match `/ph status` output
- [ ] Metrics match HUD display
- [ ] Close history → HUD still works
- [ ] Open history while HUD visible → Both work together

### UI Polish
- [ ] All text is readable (proper font sizes)
- [ ] Colors are consistent with WoW UI
- [ ] Buttons respond to mouse hover
- [ ] Dropdowns close properly
- [ ] No UI elements overlap
- [ ] Frame stays within screen bounds
- [ ] Close button (X) works

## Common Issues & Solutions

### Issue: "No sessions" message when sessions exist
**Solution:** Check if active session is being excluded. Stop the active session first.

### Issue: Index builds slowly
**Solution:** Check session count. 100+ sessions should still be <500ms. If slower, check for nil references.

### Issue: Filters don't work
**Solution:** Check console for errors. Verify pH_Index is not nil.

### Issue: Frame position not persisting
**Solution:** Check pH_DB.settings.historyPosition is being saved on close.

### Issue: Summary tab shows wrong data
**Solution:** Verify SessionManager:GetMetrics is being called correctly. Check session ID matches.

### Issue: Dropdowns don't populate
**Solution:** Check pH_Index:GetZones() and GetCharacters() return valid arrays.

## Debug Commands

Enable verbose logging to see detailed output:
```
/ph debug verbose on
/ph history
```

Check index state:
```
/dump pH_Index.stale
/dump pH_Index.sessions
/dump pH_Index.summaries[1]
```

Check filter state:
```
/dump GoldPH_History.filterState
```

## Performance Benchmarks

Expected performance on a typical system:

- **Index build (10 sessions)**: <50ms
- **Index build (100 sessions)**: <500ms
- **Index build (500 sessions)**: <2s
- **Query (no filters)**: <5ms
- **Query (with filters)**: <10ms
- **Scroll event**: <5ms
- **Filter change**: <20ms
- **Tab switch**: <10ms

## Test Data Generation

Generate test sessions for performance testing:

```lua
-- In-game Lua
for i = 1, 50 do
  pH_SessionManager:StartSession()
  GoldPH_Events:InjectLootedCoin(math.random(100000, 500000))
  GoldPH_Events:InjectLootItem(3404, math.random(1, 10))  -- Buzzard Wing
  C_Timer.After(1, function()
    pH_SessionManager:StopSession()
  end)
end
```

## Reporting Issues

When reporting issues, include:
1. WoW version (Classic Anniversary)
2. Addon version (`/ph` shows v0.7.0)
3. Steps to reproduce
4. Console errors (if any)
5. Number of sessions in history
6. Filter state when issue occurred

## Next Steps After Testing

If testing is successful:
1. ✅ Mark Phase 1-4 as complete
2. 🚀 Begin Phase 5: Items Tab
3. 🚀 Begin Phase 6: TSM Integration (optional)
4. 🚀 Begin Phase 7: Gathering Tab
5. 🚀 Begin Phase 8: Compare Tab
6. 🚀 Begin Phase 9: Polish & Enhancements

## Success Criteria

✅ All checkboxes above are checked
✅ No errors in console
✅ Performance meets benchmarks
✅ Users can browse and analyze historical sessions efficiently
✅ Filtering and sorting work intuitively
✅ Detail view provides comprehensive session insights
