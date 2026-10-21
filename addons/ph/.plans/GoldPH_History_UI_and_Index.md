# GoldPH History Screen — UI & Index Design Plan
*(Journey-style history, filters, insights, and fast indexing)*

> Note: Metric-card trend/stability indicators in HUD/History summary were removed from the current implementation. Trend mentions in this document refer to historical/future concepts (for example, price trend insights), not active summary-card trend UI.

---

## 1. Goals

Design a **Journey-style History screen** for GoldPH that allows users to:

- Browse past sessions efficiently
- Identify best **gold/hour** (and future XP/Rep/Honor per hour)
- Filter by character, zone, gathering, pickpocketing, mob levels (future)
- Understand:
  - Most lucrative sessions
  - Most lucrative items
  - Best gathering spots
- Compare sessions across characters
- Integrate TSM to show **price trends** (up/down since farm)
- Support future:
  - Charts over time
  - Uploading sessions for shared “best farms” discovery

Design priorities:
- Fast (no per-frame full scans)
- Scalable to hundreds/thousands of sessions
- Minimal UI complexity (Questie Journey–inspired)

---

## 2. High-Level UI Layout

### Overall Structure
```
+--------------------------------------------------+
| Title + Mode (Gold/hr | XP/hr | Rep/hr | Honor/hr)|
| Filters (search, sort, zone, char, min/hr, flags)|
+----------------------+---------------------------+
| Session List (left)  | Session Detail (right)    |
| virtualized rows     | Tabs: Summary / Items /   |
|                      |       Gathering / Compare |
+----------------------+---------------------------+
```

### Design Pattern
- Mirrors **Questie Journey**
- Left pane = **virtualized scroll list**
- Right pane = **detail view with tabs**
- Index built once; UI queries indexes

---

## 3. UI Module Skeleton

### File Layout
```
GoldPH/
  UI_History.lua
  UI_History_Filters.lua
  UI_History_List.lua
  UI_History_Detail.lua
  Index.lua
```

---

## 4. History Screen Entry (UI_History.lua)

Responsibilities:
- Create main frame
- Initialize filters, list, detail panes
- Wire selection and refresh callbacks

Key behaviors:
- Build indexes once on open
- Refresh list only when filters change
- Never scan all sessions per frame

---

## 5. Filter System (UI_History_Filters.lua)

### Filter State
```lua
state = {
  mode = "gold",           -- gold | xp | rep | honor
  search = "",
  sort = "totalPerHour",   -- totalPerHour | cashPerHour | expectedPerHour | date
  charKeys = nil,          -- nil = all
  zone = nil,              -- nil = any
  minPerHour = 0,          -- copper/hour
  hasGathering = false,
  hasPickpocket = false,
}
```

### Filter UI
- Search box (zone, character, item name)
- Sort dropdown
- Mode toggle (future-proof)
- Zone dropdown
- Character multi-select
- Checkboxes: Gathering / Pickpocket
- Min gold/hour slider or presets

On change → `HistoryList:Refresh()`

---

## 6. Session List (UI_History_List.lua)

### Key Concepts
- Virtualized row pool (HybridScrollFrame pattern)
- Only visible rows are rendered
- Pre-filtered + pre-sorted session ID list

### Row Contents
Each row shows:
- **Total/hr** (primary)
- Zone
- Duration
- Character
- Small badges (Gathering / Pickpocket)

### Flow
1. `Refresh()` → query index → list of sessionIds
2. `Render()` → reuse row frames, populate visible rows
3. Click row → update detail pane

---

## 7. Session Detail Pane (UI_History_Detail.lua)

### Tabs

#### 7.1 Summary
- Total/hr, Cash/hr, Expected/hr
- Cash in/out breakdown
- Inventory expected by bucket
- Pickpocket totals
- Nodes gathered summary

#### 7.2 Items
- Top items by expected value
- Filter by bucket (gathering / rare / trash)
- Snapshot price vs current TSM price
- Trend indicator (↑ / ↓)

#### 7.3 Gathering
- Node types by count
- Nodes/hour
- Zone-level best gathering heuristics

#### 7.4 Compare
- Compare against:
  - Another selected session
  - Zone average
  - Character average

---

## 8. Index Builder (Index.lua)

### Purpose
- Build **fast queryable caches**
- Avoid scanning all sessions during UI rendering
- Power insights (best farms, best items, trends)

### Runtime Cache Structure
```lua
cache = {
  sessions = { [id] = sessionRef },
  summary = { [id] = summary },

  byZone = { [zone] = {ids...} },
  byChar = { [charKey] = {ids...} },

  sorted = {
    totalPerHour = {ids...},
    cashPerHour = {ids...},
    expectedPerHour = {ids...},
    date = {ids...},
  },

  itemAgg = {
    [itemID] = {
      value,
      count,
      zones = {zone->value},
      chars = {charKey->value},
      name, quality, bucket
    }
  },

  nodeAgg = {
    [nodeName] = {
      count,
      zones = {zone->count},
      chars = {charKey->count}
    }
  },

  zoneAgg = {
    [zone] = {
      sessions,
      bestTotalPerHour,
      bestNodesPerHour
    }
  }
}
```

---

## 9. Summary Computation

Each session summary precomputes:
- netCash
- expectedInventory
- totalEconomic
- per-hour metrics
- flags: hasGathering / hasPickpocket
- character key
- zone
- duration

Used directly by:
- list rows
- filters
- sorters

---

## 10. Query API

### QuerySessions(filters)
- Uses pre-sorted base list
- Applies filters in one pass
- Returns sessionId array

### GetTopItems(filters, N)
- Uses itemAgg
- Supports zone/character constraints

### GetBestZonesByNodesPerHour(N)
- Uses per-session node density
- Surfaces best gathering spots

---

## 11. TSM Integration (UI-Level)

- Snapshot price stored at farm time
- UI fetches **current TSM price** for visible items only
- Show:
  - Snapshot price
  - Current price
  - % delta + trend arrow
- Cache TSM lookups for ~30–60s

Index does **not** store live prices.

---

## 12. Charts (Future-Safe)

Planned charts:
1. Sessions over time (Total/hr)
2. Distribution of sessions by Total/hr range

Implementation:
- Simple texture-based bars/lines
- No heavy charting libs required

---

## 13. Cross-Character Support

- Sessions stored globally with `charKey`
- History defaults to “All Characters”
- Filters allow per-character views
- Aggregates computed across all characters

---

## 14. Performance Principles

- Build indexes once (on load or first open)
- Virtualized scrolling
- No per-frame scans
- Cache summaries and aggregates
- Query only what’s visible

---

## 15. Future Extensions

- Upload sessions to shared service
- Community “best farms” leaderboard
- Heatmaps when coordinates added
- Rep/hr, XP/hr, Honor/hr modes
- Consistency scoring (variance, median)
- Session notes and pinning

---

## 16. Why This Works

- Mirrors proven Questie Journey UX
- Scales cleanly with data size
- Keeps WoW UI responsive
- Makes gold-making patterns obvious
- Sets foundation for *any per-hour metric*

---

*This document is intended to be consumed directly by an LLM (e.g., Claude Code) or used as a build reference for addon implementation.*
