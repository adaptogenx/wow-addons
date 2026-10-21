# GoldPH History UI - Next Phases Roadmap

> Note: Metric-card trend/stability indicators in HUD/History summary were removed from the current implementation. Any trend mentions here refer to future roadmap concepts (for example, price-delta indicators), not active summary-card trend UI.

## Current Status: Phases 1-4 Complete ✅

The core framework is fully functional. Users can browse sessions, filter, sort, and view comprehensive summaries.

## Phase 5: Items Tab 🎯 NEXT UP

**Goal:** Display all items looted during a session with values and counts

### Implementation Plan

**File to modify:** `GoldPH/UI_History_Detail.lua` (RenderItemsTab function)

**What to build:**
1. Table/list view of session.items
2. Columns: Item Name, Quality (color-coded), Count, Expected Value, Avg Value Each
3. Bucket filter dropdown (All, Vendor Trash, Rare/Multi, Gathering)
4. Sort by: Name, Value (desc), Count (desc)
5. Scrollable list (use same row pooling pattern as session list)

**Data source:**
```lua
local items = self.currentSession.items
for itemID, itemData in pairs(items) do
  -- itemData.name, itemData.quality, itemData.count, itemData.expectedTotal
  -- itemData.bucket
end
```

**UI Layout:**
```
┌────────────────────────────────────────────┐
│ [Bucket Filter: All ▼]  [Sort: Value ▼]   │
├────────────────────────────────────────────┤
│ Item Name          | Qty | Expected Value  │
├────────────────────────────────────────────┤
│ Buzzard Wing (G)   |  15 |   45g 00s       │
│ Heavy Stone (G)    |   8 |   12g 50s       │
│ Silk Cloth         |  24 |    8g 75s       │
│ ...                                        │
└────────────────────────────────────────────┘
```

**Quality color coding:**
- Gray: `{0.6, 0.6, 0.6}`
- White: `{1, 1, 1}`
- Green: `{0, 1, 0}`
- Blue: `{0, 0.5, 1}`
- Purple: `{0.7, 0, 1}`

**Estimated effort:** 2-3 hours

---

## Phase 6: TSM Integration (Optional) 💎

**Goal:** Show current TSM prices vs snapshot prices with trend indicators

### Prerequisites
- TSM addon installed (check with `TSM_API`)
- Items must have TSM data

### Implementation Plan

**Files to modify:**
- `GoldPH/UI_History_Detail.lua` (Items tab)
- Possibly create `GoldPH/UI_History_TSM.lua` for TSM utilities

**What to build:**
1. Detect TSM installation: `if TSM_API then ...`
2. Lookup current TSM prices for visible items (batch by rows shown)
3. Compare snapshot (expectedEach) vs current (TSM price)
4. Show trend: ↑ (price up), ↓ (price down), → (similar)
5. Show percentage change: +15%, -8%, etc.
6. Cache lookups (60s) to avoid API spam
7. Graceful fallback if TSM not installed

**UI Addition:**
```
Item Name          | Qty | Snapshot | Current | Trend
Buzzard Wing       |  15 |    3g 00s |   3g 50s | ↑ +17%
Heavy Stone        |   8 |    1g 55s |   1g 20s | ↓ -23%
```

**TSM API calls:**
```lua
local price = TSM_API.GetCustomPriceValue("DBMinBuyout", itemLink)
-- or TSM_API.GetCustomPriceValue("DBMarket", itemLink)
```

**Estimated effort:** 3-4 hours

---

## Phase 7: Gathering Tab 🌿

**Goal:** Display gathering node breakdown and efficiency metrics

### Implementation Plan

**File to modify:** `GoldPH/UI_History_Detail.lua` (RenderGatheringTab function)

**What to build:**
1. Check if session has gathering data: `session.gathering.totalNodes > 0`
2. Display total nodes and nodes/hour
3. Table of node types with counts
4. Bar chart (optional) showing node distribution
5. Zone-level insights (if available from Index)

**Data source:**
```lua
local gathering = self.currentSession.gathering
-- gathering.totalNodes
-- gathering.nodesByType = {["Copper Vein"] = 12, ["Silverleaf"] = 8, ...}
```

**UI Layout:**
```
┌────────────────────────────────────────────┐
│ Total Nodes: 45            Nodes/hr: 27.3  │
├────────────────────────────────────────────┤
│ Node Type             | Count | % of Total │
├────────────────────────────────────────────┤
│ Copper Vein           |   15  |    33%     │
│ Silverleaf            |   12  |    27%     │
│ Tin Vein              |    8  |    18%     │
│ Peacebloom            |    6  |    13%     │
│ Earthroot             |    4  |     9%     │
└────────────────────────────────────────────┘
```

**No gathering data:**
```
┌────────────────────────────────────────────┐
│                                            │
│     No gathering data for this session     │
│                                            │
└────────────────────────────────────────────┘
```

**Estimated effort:** 2 hours

---

## Phase 8: Compare Tab 📊

**Goal:** Compare session against zone average, character average, or specific session

### Implementation Plan

**File to modify:** `GoldPH/UI_History_Detail.lua` (RenderCompareTab function)

**What to build:**
1. Dropdown: Compare against (Zone Average, Character Average, Best Session)
2. Comparison table showing side-by-side metrics
3. Insights: "This session is 15% above zone average"
4. Visual indicators (better/worse)

**Data source:**
```lua
local zoneAgg = GoldPH_Index:GetZoneAggregates()
local thisZone = self.currentSession.zone
local zoneStats = zoneAgg[thisZone]
-- zoneStats.avgTotalPerHour, zoneStats.bestTotalPerHour, etc.
```

**UI Layout:**
```
┌────────────────────────────────────────────┐
│ Compare against: [Zone Average ▼]         │
├────────────────────────────────────────────┤
│ Metric              | This  | Zone Avg | Δ │
├────────────────────────────────────────────┤
│ Total g/hr          | 170g  | 145g     |↑17%│
│ Cash g/hr           | 120g  | 105g     |↑14%│
│ Expected g/hr       |  50g  |  40g     |↑25%│
│ Nodes/hr            |  28   |  22      |↑27%│
├────────────────────────────────────────────┤
│ 💡 This session is 17% above zone average  │
│ 💡 Rank: #3 of 12 sessions in this zone   │
└────────────────────────────────────────────┘
```

**Estimated effort:** 3-4 hours

---

## Phase 9: Polish & Enhancements ✨

**Goal:** Final touches for production quality

### Implementation Checklist

1. **Loading Indicator**
   - Show spinner during index build
   - "Building index... (N sessions)" message
   - Progress bar (optional)

2. **Keyboard Navigation**
   - Arrow keys to navigate sessions
   - Enter to select
   - Escape to close
   - Tab to cycle through filters

3. **Tooltips**
   - Hover over badges → Explain [G] = Gathering, [P] = Pickpocket
   - Hover over metrics → Show calculation details
   - Hover over filter controls → Usage hints

4. **Empty State Improvements**
   - Better messaging when no sessions
   - Suggest starting a session
   - Link to help

5. **Export Functionality (Future)**
   - CSV export of sessions
   - Copy to clipboard
   - Integration with other addons

6. **Settings Integration**
   - Add history preferences to settings menu
   - Default sort order
   - Default filters
   - Rows per page

7. **Performance Optimizations**
   - Debounce search input (wait 200ms after typing)
   - Lazy load item icons
   - Pagination for very large session counts (1000+)

8. **Error Handling**
   - Graceful degradation if index fails
   - Retry mechanism for corrupt data
   - Error reporting to console with helpful messages

**Estimated effort:** 4-6 hours

---

## Implementation Priority

### Must Have (MVP Complete) ✅
- ✅ Phase 1: Index
- ✅ Phase 2: Main Frame + List
- ✅ Phase 3: Filters
- ✅ Phase 4: Summary Tab

### Should Have (Next Sprint)
- 🎯 Phase 5: Items Tab (NEXT)
- 🌿 Phase 7: Gathering Tab

### Nice to Have (Future Releases)
- 💎 Phase 6: TSM Integration
- 📊 Phase 8: Compare Tab
- ✨ Phase 9: Polish

### Optional (Based on User Feedback)
- Advanced filters (date range, min duration)
- Favorite sessions
- Session notes/tags
- Multi-character view
- Export/import sessions

---

## Development Tips

### Reusing Existing Patterns

1. **Metric Display**
   - Use `GoldPH_Ledger:FormatMoney(copper)` for full precision
   - Use `GoldPH_Ledger:FormatMoneyShort(copper)` for compact display
   - Always use `SessionManager:GetMetrics(session)` for calculations

2. **Scrolling Lists**
   - See `UI_History_List.lua` for row pooling pattern
   - Create fixed pool of visible rows
   - Update row content on scroll
   - Use `SetPoint` to position rows vertically

3. **Dropdowns**
   - See `UI_History_Filters.lua` for dropdown pattern
   - Use `UIDropDownMenu_*` functions
   - Cache menu state for performance

4. **Color Coding**
   - Gold: `{1, 0.82, 0}`
   - Green: `{0, 1, 0}`
   - Red: `{1, 0.3, 0.3}`
   - Blue: `{0.5, 0.8, 1}`
   - Gray: `{0.5, 0.5, 0.5}`

5. **Layout Helpers**
   - Use `CreateFontString` for text
   - Use `CreateFrame("Button", ...)` for clickable elements
   - Use `SetBackdrop` for borders and backgrounds
   - Use `SetPoint` for relative positioning

### Testing Strategy

For each new phase:
1. Test with 0 items/nodes (empty state)
2. Test with 1 item/node (minimal case)
3. Test with 50+ items/nodes (performance)
4. Test with missing data (graceful degradation)
5. Test with active session (ensure exclusion)

### Code Quality

- Run `luacheck` after each change
- Keep functions under 100 lines
- Comment complex logic
- Use descriptive variable names
- Follow existing naming conventions

---

## Success Metrics

For each phase to be considered complete:

✅ **Functionality**
- Feature works as designed
- No console errors
- Handles edge cases gracefully

✅ **Performance**
- No frame drops during usage
- Operations complete in <100ms
- Memory usage is reasonable

✅ **UX**
- Intuitive to use
- Consistent with existing UI
- Provides clear feedback

✅ **Code Quality**
- Passes luacheck with no warnings
- Well-documented
- Reuses existing patterns

---

## Resources

### WoW API References
- [Item API](https://wowpedia.fandom.com/wiki/Category:API_functions/Item_functions)
- [Frame API](https://wowpedia.fandom.com/wiki/UIOBJECT_Frame)
- [Font Strings](https://wowpedia.fandom.com/wiki/UIOBJECT_FontString)

### TSM API
- [TSM API Documentation](https://www.tradeskillmaster.com/addon/api)
- Check `TSM_API.GetCustomPriceValue` for price lookups

### Testing
- Use `/goldph test hud` for sample data
- Use `/goldph debug verbose on` for detailed logging
- Use `/reload` to reload UI after changes

---

## Questions for User

Before starting Phase 5, consider:
1. Should Items tab show item icons? (requires icon handling)
2. Should Items tab be paginated or fully scrollable?
3. Priority on TSM integration vs gathering/compare tabs?
4. Any specific comparison modes for Compare tab?

---

## Estimated Timeline

Assuming ~2-4 hours per phase:

- **Phase 5 (Items)**: 1 session
- **Phase 7 (Gathering)**: 1 session
- **Phase 8 (Compare)**: 1-2 sessions
- **Phase 6 (TSM)**: 1-2 sessions (optional)
- **Phase 9 (Polish)**: 2-3 sessions

**Total remaining:** 6-12 hours of development

---

## Final Notes

The foundation is solid. Each remaining phase builds on the existing framework without major architectural changes. The modular design makes it easy to add features incrementally.

Focus on **Phase 5 (Items Tab)** next, as it's the most commonly requested feature and provides immediate value to users analyzing their farming sessions.
