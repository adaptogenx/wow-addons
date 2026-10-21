# Trend/Stable Indicators Removed

## Current State

Trend and stability indicators are fully removed from addon UI and metric-card payloads.

## What Was Removed

- No trend computation usage in UI:
  - `ComputeTrend` removed from:
    - `GoldPH/UI_History_Detail.lua`
    - `GoldPH/UI_HUD.lua`
- No stability computation usage in UI:
  - `ComputeStability` removed from:
    - `GoldPH/UI_History_Detail.lua`
    - `GoldPH/UI_HUD.lua`
- No trend/stability fields in metric card or focus payloads.
- No trend/stability labels, symbols, or abbreviations in the Summary tab metric cards.
- No stability suffix in HUD focus stats line.

## What Remains

- Metric history sampling remains active for sparkline rendering.
- Summary and focus views still show:
  - Rate
  - Total
  - Peak
  - Sparkline
- Compare-tab directional percentage formatting remains unchanged and is not part of removed trend functionality.

## Acceptance Criteria

- No `Trend`, `trendText`, `ComputeTrend`, `stability`, or `ComputeStability` references remain in `GoldPH/UI_History_Detail.lua` and `GoldPH/UI_HUD.lua`.
- Summary tab no longer shows `S`, `V`, `HV`, or any trend/stability icon/text.
- HUD focus line no longer includes a stability label.

