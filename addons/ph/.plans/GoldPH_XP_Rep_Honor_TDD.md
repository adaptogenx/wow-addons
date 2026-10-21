# GoldPH — XP / Reputation / Honor per Hour (Concise TDD Addendum)
*(WoW Classic / TBC / Anniversary)*

## 0) Summary
Extend GoldPH beyond gold/hour to also track:
- **XP/hour**
- **Reputation/hour**
- **Honor/hour**

These metrics are **session-based** and **adaptive**:
- A metric is only displayed if the session recorded **any gain** for that metric.
- UI stays compact via “chips” and progressive disclosure when multiple metrics are active (e.g., AV at sub-60).

Gold remains the source-of-truth via the **double-ledger** system; XP/Rep/Honor are tracked as **delta metrics**.

---

## 1) Goals (MVP for XP/Rep/Honor)
1. Track per-session totals and per-hour rates for XP, Rep, and Honor.
2. Show metrics only if **gained > 0** in that session.
3. Support browsing and filtering/sorting sessions by XP/hr, Rep/hr, Honor/hr (in History screen).
4. Keep implementation low-risk and performant:
   - Prefer **event + snapshot delta** methods.
   - Avoid heavy per-frame computations.
5. Cross-character support: sessions include a `charKey`; metrics roll up across characters.

---

## 2) Non-Goals (for this addendum)
- No “best rep/honor by sub-zone coordinates” (no coordinate tracking yet)
- No faction standing UI beyond basic deltas (standing level changes optional)
- No precise “current honor pool” reconstruction (use gained honor events)
- No uploads/community sharing (future)

---

## 3) Data Model Changes

### 3.1 Session additions
```lua
Session.metrics = {
  xp = {
    gained = 0,          -- integer points
    enabled = false,
  },

  rep = {
    gained = 0,          -- total rep points across factions
    enabled = false,
    byFaction = {
      -- ["Stormpike Guard"] = 1100
    },
  },

  honor = {
    gained = 0,          -- honor points
    enabled = false,
    kills = 0,           -- optional (HK count)
  },
}

Session.snapshots = {
  xp = { cur=0, max=0 },         -- for rollover at level-ups
  rep = { byFactionID = {} },    -- cached values for delta computation
}
```

### 3.2 Index summary additions (History screen)
`Index:ComputeSummary(session)` must compute:
- `xpPerHour`, `repPerHour`, `honorPerHour`
- boolean flags: `hasXP`, `hasRep`, `hasHonor`

Add sorted lists:
- `sorted.xpPerHour`
- `sorted.repPerHour`
- `sorted.honorPerHour`

---

## 4) Runtime State (not persisted)
```lua
state = {
  -- XP tracking
  xpLast = nil,
  xpMaxLast = nil,

  -- Rep tracking
  repCache = {
    -- [factionID] = barValue
  },

  -- Honor tracking (no snapshot required for MVP)
}
```

---

## 5) Event → Metric Mapping

## 5.1 XP Tracking
### Start of session
- `state.xpLast = UnitXP("player")`
- `state.xpMaxLast = UnitXPMax("player")`
- `session.snapshots.xp.cur = state.xpLast`
- `session.snapshots.xp.max = state.xpMaxLast`

### Event: `PLAYER_XP_UPDATE`
Compute delta with rollover support:
- `newXP = UnitXP("player")`
- `newMax = UnitXPMax("player")`
- If `newXP >= state.xpLast`:
  - `delta = newXP - state.xpLast`
- Else (level-up rollover):
  - `delta = (state.xpMaxLast - state.xpLast) + newXP`
- Update:
  - `state.xpLast = newXP`
  - `state.xpMaxLast = newMax`
  - `session.metrics.xp.gained += max(delta, 0)`
  - If `delta > 0`: `session.metrics.xp.enabled = true`

Optional attribution (future):
- Parse `CHAT_MSG_COMBAT_XP_GAIN` for “source” labeling only.

---

## 5.2 Reputation Tracking
### Start of session
Build initial cache by scanning all factions:
- Iterate `i=1..GetNumFactions()`
- Read faction info, extract:
  - `factionID` (or stable key), `name`, `barValue`
- Save:
  - `state.repCache[factionKey] = barValue`
  - `session.snapshots.rep.byFactionID[factionKey] = barValue`

### Event: `UPDATE_FACTION`
On each update:
- Iterate all factions again
- For each faction:
  - compute `delta = newBarValue - state.repCache[factionKey]`
  - if `delta > 0`:
    - `session.metrics.rep.gained += delta`
    - `session.metrics.rep.byFaction[name] = (prev or 0) + delta`
    - `session.metrics.rep.enabled = true`
  - update `state.repCache[factionKey] = newBarValue`

Optional (future):
- Parse `CHAT_MSG_COMBAT_FACTION_CHANGE` for attribution/UX; deltas remain source-of-truth.

Notes:
- Reputation “headers” and collapsed categories: ensure scanning accounts for all visible factions.
- Use a stable faction key (prefer `factionID` if available; otherwise name).

---

## 5.3 Honor Tracking
MVP uses event-based accumulation.

### Event: `CHAT_MSG_COMBAT_HONOR_GAIN`
- Parse honor gained amount (integer)
- `session.metrics.honor.gained += amount`
- `session.metrics.honor.enabled = true`

Optional:
- If message indicates an HK:
  - `session.metrics.honor.kills += 1`

Fallback:
- If honor gain appears in `CHAT_MSG_SYSTEM` for your client version, parse there too.

---

## 6) Per-Hour Computation
For each metric:
- `hours = max(session.durationSec, 1) / 3600`

Compute:
- `xpPerHour = xp.gained / hours`
- `repPerHour = rep.gained / hours`
- `honorPerHour = honor.gained / hours`

Gold/hr remains from ledger:
- `cashPerHour`, `expectedPerHour`, `totalPerHour`

---

## 7) UI Rules (Adaptive + Non-Overwhelming)

### 7.1 Visibility
- Only show a metric if `metrics.<x>.enabled == true` (or gained > 0).
- Gold metrics remain available (but can be visually de-emphasized when mode != gold).

### 7.2 HUD / Compact Summary (“chips”)
Render a horizontal “metric chip” strip:
- Always show **Total/hr** (current mode’s primary value)
- Then show chips for **enabled** metrics:
  - Gold (Cash/hr + Value/hr or Total/hr)
  - XP/hr
  - Rep/hr (and top faction name, optional)
  - Honor/hr

If more than 3 chips active:
- Show top 3 by “impact” and display “+N” overflow
- Overflow expands on click/hover

### 7.3 History list rows
Keep rows compact:
- Primary: value/hr (based on selected mode) + zone
- Secondary: duration + character
- Badges: XP / REP / HON shown only if enabled

### 7.4 Session detail pane
In “Summary” tab:
- Show a “Metrics” section listing only enabled metrics:
  - Gold: cash/value/total
  - XP: total + xp/hr
  - Rep: total + rep/hr + top factions (top 3)
  - Honor: total + honor/hr + HKs (if tracked)

In “Reputation” subpanel (optional):
- Table of factions gained this session, sorted by rep gained

---

## 8) Indexing & Filtering
Extend `Index.cache.summary[sessionId]`:
- `hasXP`, `hasRep`, `hasHonor`
- `xpPerHour`, `repPerHour`, `honorPerHour`

Add sort keys:
- `sorted.xpPerHour`, `sorted.repPerHour`, `sorted.honorPerHour`

Filtering (History filters):
- Checkbox: “Only sessions with XP/Rep/Honor”
- Zone + character filters apply normally

---

## 9) Testing Plan (MVP)
1. XP:
   - Gain XP without level-up → delta correct
   - Level-up rollover → delta correct
2. Rep:
   - Gain rep from quest turn-in → byFaction delta correct
   - Multiple factions in one session → totals correct
3. Honor:
   - Gain honor in BG → sum correct
4. UI:
   - Session with only gold → only gold shown
   - Session with gold+xp+rep+honor → chips show top 3 + overflow
5. Index:
   - Sorting by xpPerHour/repPerHour/honorPerHour works
   - Filtering by enabled metrics works

---

## 10) Implementation Notes
- Keep metric tracking independent from gold ledger (no need for ledger postings).
- Use **runtime caches** for XP/Rep to compute deltas; persist totals in session.
- Avoid per-frame scanning; only process events and update counters.
- Treat honor as event-accumulated for MVP (simplest and robust).

---

*End of addendum.*
