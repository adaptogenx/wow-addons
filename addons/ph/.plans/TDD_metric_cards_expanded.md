# Wireframe + TDD — Expanded View Metric Cards

## Wireframe (Expanded View: Metric Cards Grid)

```
┌──────────────────────────────────────────────────────────────────┐
│ Session: Stratholme Live  |  18m 24s  |  Preset: Gold+Rep         │
│ Filters: [All] [Last 30m] [Dungeon] [BG]        Sort: [Gold/hr ▼] │
├──────────────────────────────────────────────────────────────────┤
│  ┌───────────────────────────────┐   ┌──────────────────────────┐ │
│  │ [ICON] GOLD / HOUR            │   │ [ICON] XP / HOUR          │ │
│  │ 124g/hr                      │   │ 42k/hr                     │ │
│  │ Total: 1,560g  Peak: 185g/hr  │   │ Total: 320k  Peak: 52k/hr │ │
│  │                               │   │                           │ │
│  │ ▁▂▃▄▅▆▇▆▅▄▃▂▁  (last 10–15m)   │   │ ▂▃▂▄▆▅▇▅▄▃▅▆▃▂▁          │ │
│  │ [ Focus ]                     │   │ [ Focus ]                │ │
│  └───────────────────────────────┘   └──────────────────────────┘ │
│  ┌───────────────────────────────┐   ┌──────────────────────────┐ │
│  │ [ICON] REP / HOUR             │   │ [ICON] HONOR / HOUR       │ │
│  │ +320/hr                      │   │ 1,200/hr                   │ │
│  │ Total: +3,400 Peak: +450/hr   │   │ Total: 14,500 Peak: 1,600 │ │
│  │                               │   │                           │ │
│  │ ▁▁▂▃▄▅▅▆▇▆▅▄▃▂▁               │   │ ▂▆▁▇▂▆▁▇▃▅▁▆▂▇▁           │ │
│  │ [ Focus ]                     │   │ [ Focus ]                │ │
│  └───────────────────────────────┘   └──────────────────────────┘ │
├──────────────────────────────────────────────────────────────────┤
│ Session Composition (optional)                                      │
│ [Gold ███████░░░] [XP ███░░░░░░] [Rep ██░░░░░░░] [Honor █░░░░░░░░] │
└──────────────────────────────────────────────────────────────────┘
```

### Focus Mode (on card click)

```
┌──────────────────────────── Focus: GOLD ───────────────────────────┐
│ 124g/hr   Total 1,560g   Peak 185g/hr                               │
│ ▂▃▄▅▆▇▆▅▄▃▂▁  (timeline 30–60m, optional markers)                   │
│ Breakdown: Loot 60% | Vendor 25% | AH 15% (if tracked)              │
│ [Back]                                                           [Pin]
└────────────────────────────────────────────────────────────────────┘
```

---

## Technical Design Document — Expanded Metric Cards

### 1. Objective

Replace the expanded-view vertical metric list with a **grid of metric cards** that:

- Improves scanability
- Gives equal visual weight to Gold, XP, Reputation, and Honor
- Supports a lightweight per-metric focus drill-down

---

### 2. Requirements

#### 2.1 Metric Cards

Each active metric card must include:

- Header: icon + label (`GOLD / HOUR`, etc.)
- Primary stat: `ratePerHour` (large typography)
- Secondary stats: `total`, `peakPerHour`
- Qualitative indicators:
  - None (trend and stability indicators removed)
- Mini sparkline (last 10–15 minutes)
- Clickable focus action

#### 2.2 Conditional Rendering

- Metrics with no gains may:
  - Be hidden and trigger grid reflow (default), or
  - Display an empty-state card (config option)
- Grid reflow rules:
  - 4 metrics → 2×2 grid
  - 3 metrics → 2×2 with one empty slot
  - 2 metrics → 1×2 row
  - 1 metric → centered single card

#### 2.3 Focus Mode

Clicking a card opens a focus panel that includes:

- Larger sparkline (30–60 minute window if available)
- Headline stats (rate, total, peak)
- Optional breakdown modules (only if tracked)
- Single-click exit (Back or Close button)

---

### 3. Data & Computation

#### 3.1 Inputs

Per session:

- `elapsedSec`
- `goldDeltaCopper`
- `xpDelta`
- `repDelta`
- `honorDelta`

#### 3.2 Derived Metrics

- `ratePerHour = delta / elapsedSec * 3600`
- `total = delta`
- `peakPerHour` = rolling peak of smoothed rates

Trend/stability calculations are not part of current metric card UI behavior.

#### 3.3 Sparkline Buffers

- Fixed-size ring buffer per metric
- Sample interval: 5–10 seconds
- Default capacity: 10–15 minutes
- Optional extended buffer for focus mode

---

### 4. Layout & Styling

#### 4.1 Card Layout

- Equal-sized cards within container
- Consistent padding and margins
- Primary stat visually dominant

#### 4.2 Visual Theme

- TBC-style ornate borders and dark panels
- Subtle metric tint (header + sparkline only)
- Status indicators use compact icons and text

---

### 5. Implementation Notes (WoW UI)

- Each card implemented as a `Frame` with child regions:
  - Icon `Texture`
  - `FontString` labels
  - Sparkline rendering region
- Sparkline options:
  - Polyline approximation using textures
  - Small histogram bar segments
- Layout helper manages grid anchoring and reflow
- Performance targets:
  - Stat updates: 0.25–0.5s
  - Sparkline sampling: 5–10s
  - No per-frame allocations

---

### 6. Acceptance Criteria

- Expanded view uses card grid instead of list
- All active metrics are equally legible
- Grid reflows correctly for 1–4 metrics
- Focus mode opens and closes reliably
- No noticeable performance degradation
