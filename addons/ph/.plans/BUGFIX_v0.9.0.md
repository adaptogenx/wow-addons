# GoldPH v0.9.0 - Bug Fixes

## Issues Fixed

### 1. XP Panel Visibility
**Problem:** XP panel was hiding when `xpGained == 0`, but Rep panel was always showing. This broke the middle row layout (XP left, Rep right).

**Fix:** Updated `UpdateXPPanel()` to always show the panel in expanded mode (unless player is at max level), maintaining the middle row layout even when XP is 0.

**Before:**
```lua
if metrics.xpGained == 0 then
    panel:Hide()
    return
end
```

**After:**
```lua
-- Always show in expanded mode to maintain middle row layout
-- Only hide if player is at max level
if UnitLevel("player") >= MAX_PLAYER_LEVEL then
    panel:Hide()
    return
end
```

### 2. HUD Frame Height Calculation
**Problem:** The outer HUD frame was not sizing correctly to fit the rectangular panels. The frame height was using a fixed `FRAME_HEIGHT` constant instead of dynamically calculating based on visible panels.

**Fix:** Added dynamic height calculation in the Update() function that computes total frame height based on:
- Header section: 52px (title + timer + headerContainer)
- Panel container: variable height based on visible panels
- Bottom padding: 12px

**Code Added (line 1527-1532):**
```lua
-- Update HUD frame height to fit panels
-- Header: title (-12) + timer row (14) + gap (4) + headerContainer (14) + gap (8) = 52px
-- Container: containerHeight
-- Bottom padding: 12px
local totalHeight = 52 + containerHeight + 12
hudFrame:SetHeight(totalHeight)
```

### 3. ApplyMinimizeState Height Override
**Problem:** `ApplyMinimizeState()` was setting a fixed height when expanding, which would override the dynamic height calculation from the panel system.

**Fix:** Modified `ApplyMinimizeState()` to only set height for legacy mode (when panels are disabled). When panels are enabled, height is set dynamically in `Update()`.

**Before:**
```lua
else
    hudFrame:SetHeight(FRAME_HEIGHT)
    hudFrame:SetWidth(FRAME_WIDTH_EXPANDED)
end
```

**After:**
```lua
else
    hudFrame:SetWidth(FRAME_WIDTH_EXPANDED)
    -- Height will be set dynamically in Update() based on visible panels
    -- For legacy mode, set fixed height
    if not (cardCfg and cardCfg.enabled ~= false) then
        hudFrame:SetHeight(FRAME_HEIGHT)
    end
end
```

## Expected Frame Heights

With all panels visible:
- Header: 52px
- Gold panel: 140px
- Gap: 6px
- Middle row (XP + Rep): 80px
- Gap: 6px
- Honor panel: 90px
- Bottom padding: 12px
- **Total: 386px**

With no honor:
- Header: 52px
- Gold panel: 140px
- Gap: 6px
- Middle row (XP + Rep): 80px
- Bottom padding: 12px
- **Total: 290px**

Gold only (XP at max level, no honor):
- Header: 52px
- Gold panel: 140px
- Bottom padding: 12px
- **Total: 204px**

## Files Modified

- `GoldPH/UI_HUD.lua` - Fixed XP panel visibility and frame height calculation

## Testing

Test cases to verify:
1. [ ] XP panel shows even when xpGained = 0 (below max level)
2. [ ] XP panel hides at max level
3. [ ] Middle row (XP + Rep) maintains horizontal layout
4. [ ] Frame height adjusts when honor panel appears/disappears
5. [ ] Frame height adjusts when XP panel hides at max level
6. [ ] No visual clipping or overflow of panels
7. [ ] Frame top position stays fixed when toggling expand/collapse
8. [ ] Legacy mode (panels disabled) still uses fixed height

## Version

**GoldPH v0.9.0** - Bug fixes for panel visibility and frame sizing
