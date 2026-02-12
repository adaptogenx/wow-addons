# pH UI Design Brief (Theme A — Alchemical Readout)
**Goal:** A WoW Classic–native “instrument” UI that measures **per hour** metrics.  
**Principles:** Calm, readable, accurate, consistent. No hype. No clutter.

> **Revision note:** Text colors have been darkened for improved readability against dark Classic UI backgrounds.

---

## 1) Visual Style
- Serif headers, darker parchment text, bronze borders
- High contrast for dungeon/raid lighting
- Literal, calm labeling throughout

---

## 2) Design Tokens

### Color Tokens (Classic-safe RGB 0–1)

```lua
-- Text (improved contrast)
PH_TEXT_PRIMARY   = { r=0.92, g=0.89, b=0.80 }
PH_TEXT_MUTED     = { r=0.72, g=0.68, b=0.60 }

-- Accents
PH_ACCENT_GOOD    = { r=0.30, g=0.85, b=0.48 }
PH_ACCENT_NEUTRAL = { r=0.60, g=0.76, b=0.60 }
PH_ACCENT_BAD     = { r=0.85, g=0.38, b=0.32 }

-- Backgrounds
PH_BG_DARK        = { r=0.06, g=0.05, b=0.04 }
PH_BG_PARCHMENT   = { r=0.16, g=0.14, b=0.11 }

-- Borders
PH_BORDER_BRONZE  = { r=0.55, g=0.45, b=0.30 }
PH_DIVIDER_DARK   = { r=0.18, g=0.16, b=0.14 }
```

---

## 3) Focus Panel Spacing Rules (Required)

These rules apply to expanded metric focus/detail panels, especially gold breakdown layouts.

### Vertical Rhythm
- Sparkline to breakdown summary text: **8px**
- Breakdown summary text to breakdown header row: **12px**
- Breakdown header row to divider: **8px**
- Divider to first breakdown row: **8px**
- Breakdown row step (baseline to baseline): **14px**
- Minimum clearance below last breakdown row: **34px**

### Non-Overlap Requirements
- Header text, divider, and rows must never overlap panel borders.
- Breakdown content must never overlap interactive controls (for example `Back` button regions).
- Dynamic row counts must expand panel height; content should never be clipped.
- If available height is insufficient, increase panel height instead of reducing readability.

### Consistency Requirement
- Use the same spacing constants across HUD expanded gold breakdowns and summary/detail focus panels unless a documented exception is approved.

---

## 4) Typography, Components, and Interaction Rules
- Keep labels literal and calm; avoid flashy or promotional language.
- Preserve high contrast in dark environments and dungeon lighting.
- Prioritize clear scan order: title -> primary rate -> sparkline -> breakdown rows.

### pH Logo Consistency (Required)
The pH logo/title must be visually identical across all UI states to maintain brand consistency:

- **Font**: Friz Quadrata (`Fonts\\FRIZQT__.TTF`)
- **Size**: 12px (always)
- **Position**: `TOPLEFT` with offsets `(PADDING, -PADDING)` = `(12, -12)`
- **Color**: `PH_TEXT_PRIMARY` = `{0.92, 0.89, 0.80}`
- **Text**: "pH" (lowercase p, uppercase H)

**Apply to:**
- Active HUD title (when session running)
- Start screen logo (when no session active)
- Any future states or panels

**Implementation:**
```lua
logo:SetPoint("TOPLEFT", parent, "TOPLEFT", PADDING, -PADDING)
logo:SetText("pH")
logo:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
logo:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
```
