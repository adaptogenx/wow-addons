# pH ↔ shared PHUI — Phase B result and Phase C component inventory

Source of truth for shared code: `shared/ui/` (staged into `ph/Shared/UI/`). Nothing below
was replaced in Phase C; this is input for the HUD redesign TDD.

## Phase B — what was adopted (appearance unchanged)

Only values that are **byte-for-byte equivalent** were swapped. Everything else is listed under *Drift*.

| pH code | Now |
|---|---|
| `UI_HUD`: `PH_ACCENT_NEUTRAL`, `PH_ACCENT_GOLD_INCOME`, `PH_TEXT_DISABLED`, `PH_HOVER`, `PH_SELECTED` | `PHUI.Colors.*` |
| 10 inline `SetBackdrop({...})` tables (HUD stop/overflow/menu buttons + menu panel; History list/detail panes, filter button, detail card, tab, back button) | `PHUI.Backdrops.PANEL` (edge 12/inset 3), `.ICON_BUTTON` (10/2), `.ROUNDED_SMALL` (8/2) |

Files touched: `UI_HUD`, `UI_History`, `UI_History_Detail`, `UI_History_Filters` (each binds `local PHUI = addon.UI.PHUI`). `UI_History_List` had no equivalent backdrop.

### Drift (NOT equivalent — left alone, needs a design decision)

| Token | pH value (UI_HUD) | pH_Colors.lua | PHUI |
|---|---|---|---|
| TEXT_PRIMARY | .86 .82 .70 | .92 .89 .80 | .902 .867 .784 |
| TEXT_MUTED | .62 .58 .50 | .72 .68 .60 | .663 .627 .557 |
| ACCENT_GOOD | .25 .78 .42 | .30 .85 .48 | .388 .784 .475 |
| ACCENT_BAD | .85 .38 .32 | .85 .38 .32 | .871 .349 .322 |
| ACCENT_WARNING | .90 .65 .20 | .90 .65 .20 | .898 .722 .239 |
| BG_DARK / BG_PARCHMENT | .08 .07 .06 / .18 .16 .13 (a .85) | .06 .05 .04 / .16 .14 .11 | .082 .094 .090 (a .92) both |
| BORDER_BRONZE | .52 .42 .28 | .55 .45 .30 | .596 .451 .263 |
| DIVIDER | .28 .25 .22 a.5 | .28 .25 .22 | .380 .333 .255 a.6 |

Three-way drift (UI_HUD vs `pH_Colors.lua` vs PHUI). PHUI's palette came from the Pockets Glance spec, not from pH's current look. Choosing the winner is a visual change → HUD redesign. Backdrops with no PHUI twin: HUD frame & focus panel (edge 16/inset 4), HUD tile panel (10/3), detail panel (14/4), History frame (16/4), micro-bar track and History row (no edge).

## Phase C — component inventory

| # | Existing pH implementation | Shared alternative | Compatibility | Recommendation | Risk |
|---|---|---|---|---|---|
| 1 | Micro-bar tile icon + rate text (`UI_HUD` ~1226: 12px icon, `GameFontNormalSmall`, 2px gap, top-anchored; bar below) | `MetricRow` | Needs extension — row centers icon/text vertically with 6px gap and optional right-hand text; pH tile is top-anchored with 2px gap and owns a bar below | Extend (`gap`, anchor mode), then reuse for the icon+value part only | Icon/text baseline shifts 1–3px; tile height math (`TILE_HEIGHT`) depends on it |
| 2 | History list scrollbar (`UI_History_List` 55: `UIPanelScrollBarTemplate` Slider, virtualised rows via `OnScroll`) | `ScrollBar` | Unsuitable as-is — shared bar drives a real `ScrollFrame` (`SetVerticalScroll`); pH list is a row pool driven by slider value | Retain; revisit if list moves to ScrollFrame | Changes scroll model and visible bar width (16 → 6px) |
| 3 | History detail scroll (`UI_History_Detail` 104: `ScrollFrame`) | `ScrollBar` | Direct (ScrollFrame + `Create`/`Update`) — pH currently shows no custom bar | Reuse in redesign | Gutter: shared bar sits in the right padding; verify detail layout has ≥7px |
| 4 | HUD header icon buttons: `minMaxBtn`, `historyBtn` (borderless textures, ~957–990) | `PHUI.CreateNativeIconButton` | Direct (same pattern; Pockets copied it from these) | Reuse | pushed/highlight textures & tooltip anchor must match; low |
| 5 | `overflowBtn`, `stopBtn`, overflow-menu `CreateMenuIconButton` (boxed, 20px, hover→gold border) | `PHUI.CreateIconButton` | Needs extension — pH variants add `textGlyph`, border alpha 0.8, bg alpha 0.9, `iconFrame`, menu-hiding click wrapper | Extend (glyph option) then reuse; keep menu wrapper in pH | Border/bg alpha differ from PHUI defaults (`opts.bgAlpha`/`borderAlpha` cover it); glyph button not covered |
| 6 | History / focus-panel close buttons (`UIPanelCloseButton`, native size) | `PHUI.CreateCloseButton` | Direct — and gains Forever 24px sizing pH lacks | Reuse | Behavior change on Forever only (smaller X) — intended but visible |
| 7 | Dozens of `CreateFontString(..., "GameFont…")` + manual `SetTextColor(PH_*)` (HUD 32, Detail 59) | `PHUI.CreateLabel` / `ApplyTextStyle` | Direct where color is a PHUI style (primary/muted/gold…) — blocked by color drift above | Reuse after palette decision; mechanical swap | Color shifts if palette changes first; role-token fonts add shadow |
| 8 | Panel `SetBackdrop` + `SetBackdropColor/BorderColor` triplets | `PHUI.ApplyBackdrop` | Direct for the 10 adopted backdrops (colors per-site differ: alpha .85/.9/.95) | Reuse with `bgAlpha`/`borderAlpha` per site | Low; must pass each site's current alpha |
| 9 | HUD/History/focus frame position save & restore (`GetPoint`, `SetPoint(pos.point…)`, 2809, History 241/294) | `PositionStrategy` | Needs extension — shared version is TOPLEFT-only and re-derives offsets from `GetLeft/GetTop`; pH stores `point/relativePoint` | Retain until the HUD redesign defines anchoring | **High**: saved settings (`pH_Settings`) format/anchor change moves the HUD |
| 10 | No equivalent chrome | `GlanceFrame` (PortraitFrameTemplate) | Unsuitable — pH HUD is a custom backdrop frame with logo | Retain / not applicable | n/a |

Suggested order for the redesign: 4, 6, 8 (safe) → 5, 1 (small extensions) → 3 → 7 (after palette decision) → 2, 9 last/never.
