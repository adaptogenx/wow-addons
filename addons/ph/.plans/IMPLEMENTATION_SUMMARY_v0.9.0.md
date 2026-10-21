# GoldPH v0.9.0 - Expanded Rectangular Metric Panels Implementation

## Overview

This update replaces the previous 2×2 square card grid (v0.8.1) with rectangular panels stacked vertically, matching the PRD specification for expanded metric cards.

## What Changed

### Visual Layout

**Before (v0.8.1):**
- 2×2 grid of square cards (117px × 100px)
- Frame width: 266px (same for both collapsed and expanded)
- Cards showed: icon, label, rate, trend, peak, stability, sparkline, focus button

**After (v0.9.0):**
- Rectangular panels stacked vertically
- Frame width: 266px collapsed, **340px expanded**
- Panels show detailed breakdowns with per-hour rates, totals, and percentages

### Panel Structure

1. **Gold Panel** (full width, 140px height)
   - Always visible
   - Shows 5 breakdown categories:
     - Raw Gold (looted coin)
     - Vendor Trash
     - AH / Rare Items
     - Gathering
     - Pickpocketing (includes lockbox contents)
   - Each row shows: Label | Per-hour rate | Total | Percentage

2. **XP Panel** (left half, 80px height)
   - Conditional: hidden at max level or when no XP gained
   - Shows total XP and per-hour rate
   - Future: will show Quest XP vs Mob XP breakdown

3. **Rep Panel** (right half, 80px height)
   - Always visible when expanded
   - Shows top 2 factions with gains
   - "+X more..." text if more than 2 factions

4. **Honor Panel** (full width, 90px height)
   - Conditional: hidden when no honor gained
   - Positioned dynamically below XP (if shown) or below Gold
   - Future: will show BG/Bonus Honor vs Kills breakdown

### Key Dimensions

```
Collapsed:  266px wide (micro-bars)
Expanded:   340px wide (panels)

Panel widths:
- Full width: 316px (340 - 2×12 padding)
- Half width: 155px ((316 - 6 gap) / 2)
- Gap: 6px
- Internal padding: 8px
```

## Technical Implementation

### New Constants (lines 33-38)

Replaced old grid constants with panel layout constants:
- `FRAME_WIDTH_EXPANDED = 340`
- `PANEL_FULL_WIDTH = 316`
- `PANEL_HALF_WIDTH = 155`
- `PANEL_GAP = 6`
- `PANEL_PADDING = 8`
- `MAX_PLAYER_LEVEL = 60` (Classic; update to 70 for TBC)

### New Helper Functions

1. **`CreateMetricPanel(parent, width, height)`** (line ~835)
   - Creates a rectangular panel frame with backdrop
   - Sets up icon, label, totalValue, rateText, rawTotal
   - Initializes empty breakdownRows array

2. **`AddBreakdownRow(panel, yOffset, label, perHourValue, totalValue, pctValue)`** (line ~880)
   - Adds a breakdown row to a panel at specified Y offset
   - Shows: Label (left) | Per-hour (120px) | Total (190px) | Percentage (right)

3. **`UpdateGoldPanel(panel, metrics, session)`** (line ~905)
   - Reads ledger accounts for all 5 gold categories
   - Clears old breakdown rows
   - Adds new rows only for non-zero values
   - Calculates percentages relative to total gold

4. **`UpdateXPPanel(panel, metrics)`** (line ~970)
   - Hides panel if max level or no XP gains
   - Shows total and per-hour rate
   - Placeholder for future Quest/Mob XP breakdown

5. **`UpdateRepPanel(panel, metrics)`** (line ~985)
   - Shows top 2 factions from `metrics.repTopFactions`
   - Adds "+X more..." text if more than 2 factions
   - Calculates per-hour rates for each faction

6. **`UpdateHonorPanel(panel, metrics)`** (line ~1015)
   - Hides panel if no honor gains
   - Dynamically repositions based on XP panel visibility
   - Placeholder for future BG vs Kills breakdown

7. **`FormatNumber(num)`** (line ~1030)
   - Formats large numbers for XP display (1.2M, 5.4k, etc.)

### Update Logic Changes (line ~1447)

Main `Update()` function now:
1. Checks if rectangular panels are enabled (`useRectangularPanels`)
2. Hides all legacy rows when panels are active
3. Hides old metric cards from previous grid system
4. Calls panel update functions
5. Dynamically calculates container height based on visible panels
6. Shows the panel container

### Frame Sizing (ApplyMinimizeState, line ~1650)

- Collapsed: 266px width (micro-bars)
- Expanded: 340px width (rectangular panels)
- Removed old grid/vertical layout logic

## Data Sources

### Gold Breakdown
All values read from ledger accounts:
- `Income:LootedCoin` → Raw Gold
- `Income:ItemsLooted:TrashVendor` → Vendor Trash
- `Income:ItemsLooted:RareMulti` → AH / Rare Items
- `Income:ItemsLooted:Gathering` → Gathering
- `Income:Pickpocket:Coin/Items/FromLockbox:Coin/Items` → Pickpocketing (sum of 4 accounts)

### XP, Rep, Honor
Sourced from `metrics` object returned by `SessionManager:GetMetrics()`:
- `metrics.xpGained`, `metrics.xpPerHour`, `metrics.xpEnabled`
- `metrics.repGained`, `metrics.repPerHour`, `metrics.repTopFactions`
- `metrics.honorGained`, `metrics.honorPerHour`, `metrics.honorEnabled`

## Known Limitations (Data Gaps)

1. **XP Sources:** Quest XP vs Mob XP breakdown not yet tracked in SessionManager
2. **Honor Sources:** BG/Bonus Honor vs Kills breakdown not yet tracked in SessionManager

Without these, XP and Honor panels show totals only (no source breakdowns).

## Removed Code

The following old grid card functions are no longer used:
- `CalculateCardPositions()` (line ~1232) - kept for reference but unused
- `EnsureCard()` - removed from Update() flow
- `UpdateCard()` - removed from Update() flow
- Grid layout logic (lines 1515-1693) - completely removed

Focus panel code (lines 710-773) is still present but not used in PRD specification.

## Backward Compatibility

- Legacy vertical row display still exists as fallback
- If `GoldPH_Settings.metricCards.enabled = false`, reverts to old row layout
- Collapsed micro-bar display unchanged
- All data structures remain the same (no breaking changes)

## Testing Checklist

### Visual Tests
- [ ] Frame width: 266px collapsed, 340px expanded
- [ ] Gold panel shows 5 categories with correct values
- [ ] Zero-value categories are hidden
- [ ] XP panel hides at max level
- [ ] Rep panel shows top 2 factions + "+X more..." text
- [ ] Honor panel hides when no honor gains
- [ ] Honor panel positions correctly when XP shown/hidden
- [ ] All text readable at 0.85 UI scale
- [ ] Bronze borders and dark backgrounds match pH design

### Data Accuracy Tests
- [ ] Gold category totals sum to total gold value
- [ ] Percentages sum to ~100% (within rounding)
- [ ] Pickpocket total includes all 4 sources
- [ ] Per-hour rates scale correctly for short sessions (<10 min)
- [ ] Rep factions sorted by total gain (top 2 shown)

### Edge Cases
- [ ] Very short session (<1 min): no divide-by-zero errors
- [ ] No gains in category: row correctly hidden
- [ ] Single faction rep gain: no "+X more..." text
- [ ] Container height adjusts dynamically when toggling panels

## Files Changed

- `GoldPH/UI_HUD.lua` - Complete panel system implementation
- `GoldPH/GoldPH.toc` - Version bumped to 0.9.0

## Next Steps (Future Enhancements)

1. Add XP source tracking to Events.lua (`PLAYER_XP_UPDATE` handler)
2. Add Honor source tracking to Events.lua (`CHAT_MSG_COMBAT_HONOR_GAIN` parser)
3. Consider adding sparklines to panels (optional enhancement)
4. Remove unused focus panel code if not needed
5. Clean up old grid card helper functions if confirmed unused

## Migration Notes

Users upgrading from v0.8.1 will see:
- Wider HUD when expanded (340px vs 266px)
- New rectangular panel layout with detailed breakdowns
- No change to collapsed micro-bar display
- No settings migration required (backward compatible)

## Version

**GoldPH v0.9.0** - Expanded Rectangular Metric Panels

## Post-v0.9 Note

- Trend and stability indicators in metric cards/focus were later removed.
- Current UI now shows rate, total, peak, and sparkline only for those surfaces.
