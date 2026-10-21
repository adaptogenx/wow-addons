# TDD — Collapsed State Micro-Bars (Gold / XP / Rep / Honor)

**Goal:** Replace (or augment) raw numbers in the collapsed session row with **tiny “micro-bars”** that communicate metric intensity at-a-glance, while keeping the UI compact and low-cost to render.

---

## 1) Product Requirements

### 1.1 What the user sees
In the collapsed state, each active metric tile shows:

- **Icon**
- **Primary value** (rate, e.g., `124g/h`, `42k XP/h`, `+320 Rep/h`, `1.2k Honor/h`)
- **Micro-bar** beneath or beside the value (5–8px tall)

The micro-bar represents the **current session rate** normalized to a **reference max** so the player can visually compare “how strong” each metric is.

### 1.2 Scope
- Collapsed state only
- Metrics supported: **Gold**, **XP**, **Reputation**, **Honor**
- Micro-bars shown only for **active metrics** (rate > 0)

### 1.3 Non-goals
- No long history graphs (sparklines) in collapsed state
- No cross-session leaderboard UI here (handled by history screen)
- No dependency on external libraries

---

## 2) UX & Layout Spec

### 2.1 Tile layout (collapsed)
Each metric tile is a compact horizontal block:

```
[icon]  124g/h
        ███████░░░
```

- Icon size: 14–16px
- Value font: same as current collapsed metric font
- Micro-bar:
  - Height: **6px** (configurable 5–8px)
  - Width: **tile inner width** (value width or fixed width)
  - Rounded corners: 2px (optional)
  - Background: subdued (low alpha)
  - Fill: metric color token (see §7)

### 2.2 Conditional display
- If a metric has **no gain** (or rate <= 0), **hide** the tile completely (and therefore its micro-bar).
- If only one metric is active, micro-bar still shows (helps indicate relative intensity vs typical).

---

## 3) Data Model

### 3.1 Session snapshot
The session tracker should already provide:

- `sessionStartTime` (seconds)
- `elapsedSec`
- `goldDelta` (copper)
- `xpDelta` (integer)
- `repDelta` (integer)
- `honorDelta` (integer)

### 3.2 Derived rates (per hour)
Compute on update tick:

- `goldPerHour = (goldDelta / elapsedSec) * 3600`
- `xpPerHour   = (xpDelta   / elapsedSec) * 3600`
- `repPerHour  = (repDelta  / elapsedSec) * 3600`
- `honorPerHour= (honorDelta/ elapsedSec) * 3600`

All rates are **>= 0** (clamp).

---

## 4) Normalization Strategy (Micro-bar Scaling)

Micro-bar fill is driven by a normalized value `n` in `[0, 1]`:

- `n = clamp(rate / refMax, 0, 1)`

### 4.1 Reference max options
Provide a config toggle with three strategies:

1. **Rolling Session Peak (default)**
   - `refMax = max(peakRateSinceStart, minRefFloor)`
   - Gives best “within this session” comparability and responsiveness.

2. **Rolling Window Peak**
   - `refMax = peak rate in last N minutes` (e.g., 10 minutes)
   - More reactive; good for “farm is getting worse” detection.

3. **Player Baseline**
   - `refMax = persisted baseline` (e.g., 90th percentile of last 20 sessions for that metric)
   - Best for consistent meaning across sessions.

**Default recommendation:** Rolling Session Peak (simple, stable).

### 4.2 Floors to prevent jitter
To avoid a first-minute session where tiny values render huge bars, apply floors per metric:

- `minRefFloorGold  = 5g/h` (in copper)
- `minRefFloorXP    = 5000 XP/h`
- `minRefFloorRep   = 50 Rep/h`
- `minRefFloorHonor = 100 Honor/h`

(Exact numbers should be configurable; these are starting points.)

### 4.3 Smoothing (optional but recommended)
Raw rates can spike. Use exponential smoothing for the *display* rate, not the underlying totals:

- `displayRate = (alpha * currentRate) + ((1 - alpha) * prevDisplayRate)`
- `alpha = 0.25` (tunable; 0.15–0.35 typical)

Then normalize `displayRate` rather than `currentRate`.

---

## 5) Update Loop & Performance

### 5.1 Update frequency
- Update display values + micro-bars every **0.25s–0.5s** while session is running.
- When the UI is hidden/minimized, stop updates.

### 5.2 Work per update tick
For each active metric:
1. Compute current rate (or use cached)
2. Apply smoothing
3. Update peak (if needed)
4. Normalize
5. Set micro-bar fill width

This must remain O(metrics) = O(4) and avoid allocations.

### 5.3 Avoid string churn
- Only reformat the value string if the displayed rate changed beyond a threshold:
  - Gold: 0.1g/h
  - XP: 100 XP/h
  - Rep: 5 Rep/h
  - Honor: 10 Honor/h

---

## 6) Rendering Implementation (WoW UI)

### 6.1 UI primitives
Each metric tile has:
- `Frame` container
- `Texture` icon
- `FontString` value
- `StatusBar` OR 2 `Texture`s for micro-bar (bg + fill)

**Preferred:** `StatusBar` (simple width updates; can be skinned).
Alternative (more control): `bgTexture` + `fillTexture` and set `fillTexture:SetWidth(...)`.

### 6.2 StatusBar approach
- `bar:SetMinMaxValues(0, 1)`
- `bar:SetValue(n)`
- `bar:SetHeight(6)`
- `bar:SetStatusBarTexture(texturePath)`
- `barBg:SetColorTexture(r,g,b,a)`

### 6.3 Texture approach
- Create a fixed-size bg
- Fill texture anchored LEFT
- Update width: `fill:SetWidth(n * barWidth)`

---

## 7) Color & Tokens

Do not use full WoW default neon colors. Use a **muted semantic palette** in collapsed state.

Define tokens (RGBA), ideally configurable:

- `COLOR_GOLD   = {1.00, 0.78, 0.22, 0.90}`
- `COLOR_XP     = {0.35, 0.62, 0.95, 0.90}`
- `COLOR_REP    = {0.35, 0.82, 0.45, 0.90}`
- `COLOR_HONOR  = {0.72, 0.40, 0.90, 0.90}`
- `COLOR_BG_BAR = {0.10, 0.10, 0.10, 0.55}`

Collapsed bars should be subtle:
- Background alpha ~0.4–0.6
- Fill alpha ~0.8–0.95

---

## 8) Edge Cases

1. **Very short sessions (<30s)**
   - Apply floors and smoothing.
   - Optionally hide micro-bars until `elapsedSec >= 15`.

2. **Paused sessions**
   - Freeze `displayRate` and bar width (do not decay).

3. **Metric spikes**
   - Peak-based refMax can “lock in” a huge spike making bars small later.
   - Provide a config option:
     - “Peak decays” over time: `peak = max(currentPeak * decay, currentRate)`
     - e.g., decay every minute by 2–5%.

4. **All metrics zero**
   - Collapsed row shows only session timer (or “No gains yet”); no micro-bars.

---

## 9) Configuration

Add settings (defaults in parentheses):

- `microBarsEnabled` (true)
- `microBarHeight` (6)
- `microBarWidthMode` (`"tile"` or `"fixed"`) (`"tile"`)
- `normalizationMode` (`"sessionPeak"`, `"windowPeak"`, `"baseline"`) (`"sessionPeak"`)
- `smoothingAlpha` (0.25)
- `minRefFloors` per metric (see §4.2)
- `peakDecayEnabled` (false)
- `peakDecayRatePerMin` (0.03)

---

## 10) Testing Plan

### 10.1 Unit-ish tests (in Lua)
- Rate calculations for each metric given deltas + elapsed
- Normalization clamp behavior
- Floor behavior at low elapsed times
- Smoothing correctness across ticks

### 10.2 Visual checks (in-game)
- Gold-only farm: bar stable, not jittery in first minute
- Dungeon rep grind: rep bar appears and scales sensibly
- BG: honor + XP + gold all visible; layout remains compact
- Spike simulation: verify peak behavior and optional decay

### 10.3 Performance checks
- Ensure no frame drops at 0.25s update cadence
- Confirm no growing tables/garbage per update tick

---

## 11) Pseudocode (for clarity)

```lua
-- called on update tick
function UpdateCollapsedMetrics(session)
  local elapsed = max(session.elapsedSec, 1)

  for metric in ActiveMetrics do
    local rate = (metric.delta / elapsed) * 3600
    rate = max(rate, 0)

    metric.displayRate = Smooth(metric.displayRate, rate, cfg.smoothingAlpha)

    metric.peak = max(metric.peak or 0, metric.displayRate)
    local refMax = max(metric.peak, metric.minFloor)

    if cfg.peakDecayEnabled then
      metric.peak = max(metric.peak * (1 - cfg.peakDecayRatePerMin * minutesSinceLastTick), metric.displayRate)
      refMax = max(metric.peak, metric.minFloor)
    end

    local n = clamp(metric.displayRate / refMax, 0, 1)
    metric.bar:SetValue(n)

    if ShouldUpdateLabel(metric, metric.displayRate) then
      metric.valueText:SetText(FormatRate(metric, metric.displayRate))
    end
  end
end
```

---

## 12) Acceptance Criteria

- Collapsed state height reduced or unchanged; micro-bars add **no extra vertical padding**
- Each active metric shows a micro-bar with fill proportional to normalized intensity
- First-minute sessions do not show misleading full bars (floors + smoothing)
- Update loop at 0.25–0.5s does not cause noticeable performance issues
- Inactive metrics are not displayed (no empty placeholders)
- Colors are muted and readable, not full WoW default neon
