# Hold My Fear — UI Guidelines v1.1

Compact, combat-first WoW Forever Warlock HUD. These are implementation wireframes, **not final artwork**. Use native WoW spell and raid-target textures and existing PHUI utilities.

## Primary row

```text
   [Moon]  ┌──────────────────────────────────────────┐  [↗]
           │ [POR]  [DoT] [Curse] [DoT]        [FEAR] │
           │ Deepmoss Venomspitter                   │
           └──────────────────────────────────────────┘
```

- **Raid marker:** outside the frame on the left.
- **Direction arrow:** outside the frame on the right.
- **Top row, left to right:** mob portrait, only previously applied DoTs/Curses, fixed Fear button.
- **Bottom row:** mob name begins at the **same left padding as the portrait**, not under the debuff icons. This gives long names the full frame width. No level label.
- **Fear button is permanently right-anchored** and does not move when debuff count changes.
- All spell icons—including Fear—are **the same size**.

## Dimensions and spacing (starting targets)

| Element | Target |
|---|---|
| Frame width | 300px default; adjustable 240–340px |
| Frame height | 68–74px, depending on font metrics |
| Frame horizontal padding | 8px |
| Frame vertical padding | 8px |
| Portrait | 32 × 32px |
| DoT/Curse icon | 28 × 28px |
| Fear icon | **28 × 28px**, fixed at right |
| Spell-icon gap | 4px |
| Portrait-to-first-spell gap | 8px |
| Name font | 12px, one line; truncate on overflow |
| Name positioning | left-aligned with portrait/frame content edge |
| Name gap below icons | 4–5px |
| Raid marker | 24px, outside left frame |
| Direction arrow | 20px, outside right frame |
| Vertical gap between mobs | 4px |

Allow debuff icons to use the space between portrait and Fear. If there are more than fit, show a compact `+N` overflow rather than shrinking icons or moving Fear.

## DoT / Curse visuals

```text
Full             Mid-duration      Near expiry        Expired
[████████]       [████░░░░]        [█░░░░░░░]        [░░░░░░░░]
```

- Display **only debuffs that the player actually applied** to this mob; don't prepopulate a rotation.
- Use real spell artwork and horizontal remaining-duration depletion, with the colored remainder on the **left** and desaturation expanding from the **right** as time runs out.
- No DoT/Curse numbers by default.
- Expired debuffs stay visible and clickable for recasting.
- No dramatic warning colors for ordinary DoT/Curse expirations.

## Fear control

```text
Normal           Recast             Critical          Broken           Expired
[ Fear  8 ]      [ Fear  2 ]        [ Fear  1 ]      [ Fear  ⛓̸ ]      [ Fear  – ]
 purple          amber              red               red              muted
```

The Fear icon uses **recognizable Fear spell artwork behind the overlay**, same 28 × 28px box as other spells. Keep an integer-only countdown in front, no decimals or extra Fear bar. Maintain constant size in all states.

- **Normal:** muted purple border and readable integer countdown.
- **Recast:** amber border when `remaining <= actual_cast_time + safety_buffer` (plus any relevant casting availability delay, if measured).
- **Critical:** red border when uninterrupted recast can no longer safely finish before expiration.
- **Broken early:** distinct broken-chain overlay on the Fear art, with brief red feedback; do not resize or replace the button.
- **Expired naturally:** muted icon, distinct from an early break.
- Use `ceil(remaining)` to display integer seconds; use precise remaining time for threshold logic.
- The **whole Fear icon is the recast target**, conditional on validated secure casting behavior.

Avoid busy continuous pulsing, oversized Fear icons, separate Fear timers, or duplicated numbers.

## Stable combat layout

- Maintain `GUID ↔ raid marker ↔ HUD position` mapping throughout one combat encounter.
- Never reassign markers or reorder rows mid-combat.
- New enemies take the next available marker/position; freed positions remain reserved until combat ends.
- A Fear break, expiration, or reapplication must not move the row.
- DoT/Curse icons may be added to a row, but the Fear control remains fixed.
- Solo play is the initial scope; marker rotation is deterministic.

## Native WoW / Lua guidance

- Mob portraits: Blizzard `SetPortraitTexture` where available.
- Raid markers: Blizzard `UI-RaidTargetingIcon` art or supported equivalent.
- Spell textures: supported `GetSpellTexture` / spell API for Forever.
- Timer text: stable-width, high-contrast `FontString` with tabular-style numerals where available.
- Depletion: clipped Blizzard `Texture` with horizontal desaturation/masking; preserve artwork readability.
- Clicks: secure spell buttons and unit references only where verified by the in-game targeting experiments; never silently cast on the wrong mob.
- Tooltips: standard `GameTooltip`.
- Reuse PHUI spacing, positioning, settings, and scaling conventions where suitable.

## Acceptance checklist

- [ ] Mob name starts **at the portrait's left edge**, never indented under DoTs.
- [ ] Marker and directional arrow are **outside** frame borders.
- [ ] Portrait and spell icons have consistent assigned dimensions; all spell icons equal-sized.
- [ ] Fear icon is right-anchored through all debuff/state changes.
- [ ] Fear Normal/Recast/Critical/Broken/Expired states never resize controls.
- [ ] DoTs use horizontal depletion and no default numeric labels.
- [ ] Fear has integer-only timer; no decimal countdown or duplicated progress bar.
- [ ] The HUD remains readable with several mobs at typical small-screen WoW scale.
- [ ] Row order and raid markers remain stable during combat.
