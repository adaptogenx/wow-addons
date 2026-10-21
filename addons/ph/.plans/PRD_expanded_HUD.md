# PRD — Expanded Realtime Metrics Dashboard (UI-Only)

## Scope

**UI / UX only**

This document defines layout, visibility rules, hierarchy, and real-time presentation for the expanded dashboard.  
All metrics are assumed to be **pre-computed** and provided to the UI.

**Explicitly out of scope**
- Event tracking
- Attribution logic
- Valuation logic
- Session math

---

## 1. Problem

The expanded view must communicate detailed, real-time per-hour performance across Gold, XP, Reputation, and Honor without compressing information into unreadable tiles or cards.

---

## 2. Design Principles

1. Rectangular panels over square cards  
2. Gold is the primary metric and visual anchor  
3. Every visible metric shows **per-hour rate + raw total**  
4. No trend or stability indicators; numbers and sparklines only  
5. Readable at Classic / TBC UI scale (≈0.85–1.0)

---

## 3. High-Level Layout

Vertical order (top → bottom):

1. Header bar (session context + controls)
2. Gold panel (full width, tallest)
3. Middle row:
   - XP panel (left, conditional)
   - Reputation panel (right)
4. Honor panel (full width, optional)
5. Optional session composition bar

All panels render **inside the HUD wrapper**.

---

## 4. Wireframe (Reference)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Session: <Name>                         Time: 32m 45s        [Close X]     │
│ [Pin] [Opacity ▾] [Preset ▾]                                              │
├─────────────────────────────────────────────────────────────────────────────┤

┌─────────────────────────────────────────────────────────────────────────────┐
│ [ICON] GOLD                                                     Total: 5,420g│
├─────────────────────────────────────────────────────────────────────────────┤
│ 1,620g/hr                               Sparkline (optional)               │
│ 5,420g (raw)                                                                │
│                                                                             │
│ Breakdown (per hour | total | %)                                           │
│ - Raw Gold        | 300g/hr |   980g | 18%                                  │
│ - Vendor Trash    | 570g/hr | 1,850g | 34%                                  │
│ - AH / Rare Items | 200g/hr | 1,270g | 24%                                  │
│ - Gathering       | 400g/hr | 1,010g | 19%                                  │
│ - Pickpocketing   | 150g/hr |   310g |  5%                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────┐   ┌─────────────────────────┐
│ [ICON] XP                         Total: 3.45m │   │ [ICON] REPUTATION       │
├───────────────────────────────────────────────┤   ├─────────────────────────┤
│ 65k/hr                               Sparkline │   │ +450/hr     Total: +2,775│
│ 3.45m XP (raw)                                │   ├─────────────────────────┤
│ XP Sources (raw | %)                         │   │ Faction Gains (per hr | total)│
│ - Quests:   915k (26%)                       │   │ - Argent Dawn     +250/hr | +1,500│
│ - Mobs:   2.54m (74%)                        │   │ - Stormpike Guard +120/hr |   +775│
│                                              │   │ +3 more…                  │
└───────────────────────────────────────────────┘   └─────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ [ICON] HONOR                                                     Total: 7,550│
├─────────────────────────────────────────────────────────────────────────────┤
│ 1,400/hr                              Sparkline                              │
│ 7,550 honor (raw)                                                         │
│                                                                             │
│ Breakdown (raw | %)                                                        │
│ - Battleground / Bonus Honor: 5,450 | 72%                                  │
│ - Honor from Kills:           2,100 | 28%                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Panel Requirements

### 5.1 Shared Panel Anatomy

All panels include:
- Header row (icon, label, right-aligned raw total)
- Primary stat: per-hour rate (largest text)
- Secondary stat: raw total
- Optional sparkline
- Optional breakdown rows

---

## 6. Gold Panel

**Always visible.**

Breakdown rows (fixed order):
1. Raw Gold  
2. Vendor Trash  
3. AH / Rare Items  
4. Gathering  
5. Pickpocketing  

Each row displays:
- Per-hour value
- Total value
- Percentage of total gold

Zero-value rows are hidden by default.

---

## 7. XP Panel

### Visibility
- **Shown** when player is below max level
- **Hidden** at max level (TBC: level 70)
- When hidden, layout collapses with no placeholder

### Content
- XP/hr
- Raw XP total
- Two breakdown rows:
  - Quest XP (raw + %)
  - Mob XP (raw + %)

---

## 8. Reputation Panel

### Space Constraint
- Maximum visible factions: **2**
- Sorted by total reputation gained (desc)

If more than 2 factions have gains:
- Show 2 rows
- Add a third text-only row:

```
+X more…
```

No scrolling or expansion in v1.

### Row Content
- Faction name
- Rep/hr
- Total rep gained

---

## 9. Honor Panel

### Visibility
- **Hidden** when no honor gains exist
- **Shown automatically** once honor > 0

### Content
- Honor/hr
- Raw honor total
- Two breakdown rows (fixed order):
  1. Battleground / Bonus Honor
  2. Honor from Kills

Each row shows raw value + percentage of total honor.

---

## 10. Interaction Rules

- Expanded view toggled from collapsed HUD or button
- Pin keeps expanded view visible
- Opacity applies to entire expanded frame
- Presets affect **layout emphasis only** (never calculations)

---

## 11. Layout Constraint (Global)

- All panels must render **inside the HUD wrapper**
- No overflow, detached frames, or free-floating panels
- Layout collapses vertically when optional panels are hidden
- Text rows and headers must never overlap panel borders, controls, or each other

### 11.1 Line Spacing and Vertical Rhythm (Required)

Use consistent vertical spacing for sparkline + breakdown content blocks:
- Sparkline to breakdown summary text: **8px**
- Breakdown summary text to breakdown header row: **12px**
- Breakdown header row to divider: **8px**
- Divider to first breakdown row: **8px**
- Breakdown row step (baseline-to-baseline): **14px**
- Minimum bottom clearance below last breakdown row: **34px** (reserves border + button/control area)

Layout engines must compute panel height from content depth and required bottom clearance, rather than relying only on fixed constants.

### 11.2 Non-Overlap Guardrails (Required)

- Do not allow any breakdown header or row text to render into the bottom border region.
- Do not allow breakdown content to render under interactive controls (e.g., Back button).
- If dynamic row count increases, panel height must expand so all visible rows stay fully readable.
- If content cannot fit at minimum panel size, increase panel size; never clip text.

---

## 12. Acceptance Criteria

- All UI design rules are followed
- Gold panel is the dominant visual element
- Every visible panel shows per-hour + raw totals
- Gold shows exactly five breakdown rows
- Reputation shows at most two factions plus “+X more…”
- XP panel hides at max level (70 for TBC)
- Honor panel hides when no honor is gained
- Honor breakdown shows:
  - Battleground / Bonus Honor
  - Honor from Kills
- All panels fit within the HUD wrapper
- Breakdown headers and rows never overlap borders or controls
- Breakdown spacing follows the required vertical rhythm values
- UI remains readable at Classic/TBC scale
