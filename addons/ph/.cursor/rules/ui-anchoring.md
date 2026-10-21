# UI Anchoring Consistency Rule

## Rule: Always anchor UI elements to the same top-left coordinate

When creating or modifying UI elements that appear in both collapsed and expanded states (or any state changes), **always anchor them to the same reference point** to prevent visual jumping.

### Key Principle

**The microbar tiles and other collapsible UI elements must be anchored to `hudFrame.TOPLEFT` with consistent offsets**, not to intermediate elements like `headerTimer.BOTTOM` or other child frames that may shift when the frame size changes.

### Implementation Guidelines

1. **Use `hudFrame.TOPLEFT` as the primary anchor point** for all elements that should remain stable during state changes.

2. **Calculate offsets explicitly** rather than chaining anchors:
   - ✅ Good: `element:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, -32)`
   - ❌ Bad: `element:SetPoint("TOP", headerTimer, "BOTTOM", 0, -6)`

3. **When collapsing/expanding UI:**
   - Calculate header height: `PADDING + titleHeight + gap`
   - Use this calculation consistently for Y offsets
   - Never rely on relative positioning to elements that may change size or position

4. **Prevent UI jumping:**
   - Frame size changes should not affect element positions
   - Elements anchored to `hudFrame.TOPLEFT` will remain stable regardless of frame dimensions
   - Test collapse/expand transitions to verify no visual jumping occurs

### Example: Microbar Tiles

```lua
-- Calculate header height explicitly
local headerHeight = PADDING + 14 + 6  -- top padding + title height + gap
local headerYOffset = -headerHeight

-- Anchor first tile to hudFrame.TOPLEFT
state.tile:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, headerYOffset)
```

### Verification Checklist

- [ ] Elements use `hudFrame.TOPLEFT` as anchor (or `hudFrame.LEFT`/`hudFrame.TOP` with explicit offsets)
- [ ] No chained anchors through intermediate elements that may change
- [ ] Offsets are calculated explicitly, not hardcoded magic numbers
- [ ] Tested collapse/expand transitions show no visual jumping
- [ ] Frame movement (dragging) maintains element positions correctly
