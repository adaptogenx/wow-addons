# TDD — Hold My Fear HUD Redesign

## Objective

- Replace the existing HUD with a compact, combat-first design.
- Adopt **Combat Minimal** styling with native WoW UI assets.
- Prioritize readability, consistent sizing, and rapid recognition of Fear urgency.
- Preserve existing tracking, combat-cache, and secure casting functionality.

## 1. Layout

**Target dimensions**

| Element | Specification |
|---|---|
| Frame width | 292px default; configurable 240–340px |
| Row height | 68px |
| Frame padding | 8px |
| Mob portrait | 32 × 32px |
| DoT/Curse icons | 28 × 28px |
| Fear icon | 28 × 28px |
| Icon spacing | 4px |
| Row spacing | 4px |
| Mob name | 12px, single line |
| Raid marker | 24px, outside left |
| Direction arrow | 20px, outside right |

**Structure**

- No header.
- Top: `[Portrait] [DoTs/Curses →] [Fear]`
- Bottom: Mob name, left-aligned with portrait.
- Raid marker outside left border.
- Direction arrow outside right border.
- Fear icon permanently anchored to the right.
- All spell icons identical in size.
- Long names truncate with ellipsis.
- Do not display mob level.
- No empty debuff placeholders.

## 2. Visual Design

**Combat Minimal + Blizzard assets**

- Dark, semi-transparent background.
- Thin, neutral border with subtle corner rounding.
- No ornate framing, decorative runes, or excessive glow.
- Native WoW mob portraits and spell textures.
- Native raid-marker textures.
- Blizzard-style icon borders and font conventions.
- Neutral text; reserve saturated colors for spell artwork and urgency.
- No full-row color changes unless necessary for accessibility.

## 3. DoT / Curse Icons

- Display only debuffs the player has applied to a tracked mob.
- Preserve expired icons for one-click recasting.
- Use horizontal depletion across the spell artwork:
  - Full duration: Fully colored.
  - As duration decreases: Desaturation advances from right to left.
  - Expired: Fully desaturated.
- No numeric timers.
- No animation or glow for ordinary expiration.
- Preserve each spell's recognizable artwork.
- Never resize icons to fit additional debuffs.
- Use `+N` overflow when necessary.
- Reuse existing secure click-casting behavior; do not change targeting architecture.

## 4. Fear Control

**Fixed 28 × 28px icon at the right edge.**

- Use the actual Blizzard Fear spell texture.
- Darken artwork sufficiently for legible text.
- Overlay integer-only remaining seconds.
- Use `ceil(remaining)` for display.
- No separate Fear progress bar.
- No duplicate Fear icon.
- Maintain identical dimensions in every state.

| State | Trigger | Appearance |
|---|---|---|
| Normal | Sufficient time remaining | Purple border, white number |
| Recast | Remaining ≤ cast time + buffer | Amber border, brief glow |
| Critical | Remaining ≤ cast time | Red border, red/white number |
| Broken | Fear removed early | Red border, broken-chain overlay |
| Expired | Duration reaches zero | Desaturated Fear icon |

**Timing**

- Use the player's actual Fear cast time.
- Configurable safety buffer; default 0.3 seconds.
- Calculate thresholds using unrounded remaining time.
- Account for applicable cast-time modifiers.
- Do not infer an early break merely because an aura disappears without reliable expiration evidence.
- Preserve click-to-recast behavior in every applicable state.

## 5. Combat Stability

- Preserve GUID ↔ raid marker ↔ row-position mappings throughout combat.
- Never reorder existing rows during combat.
- Never recycle raid markers during the same encounter.
- Fear remains fixed at the right edge regardless of debuff count.
- Adding/removing debuffs cannot move the Fear button.
- Broken or expired Fear cannot resize the row.
- Preserve secure button bindings and combat-lockdown protections.
- Do not silently cast on an unintended target.

## 6. Implementation

- Reuse PHUI utilities where appropriate.
- Prefer native WoW `Texture`, `FontString`, `Frame`, and secure button components.
- Use Blizzard spell textures and raid-target textures.
- Implement horizontal icon depletion using clipped textures or equivalent supported UI primitives.
- Avoid expensive per-frame updates; use an appropriate throttled timer.
- Support configurable scale and frame position.
- Do not introduce new dependencies or a separate UI framework.
- Keep changes scoped to HUD presentation unless required for correctness.

## 7. Success Criteria

**Layout**
- [ ] All spell icons are exactly 28 × 28px.
- [ ] Fear always occupies the rightmost icon position.
- [ ] Mob name begins at the frame's left padding, directly below the portrait.
- [ ] Raid marker and direction arrow remain outside the frame.
- [ ] No level, header, redundant timer, or empty spell slots.
- [ ] One through five mobs display without overlaps or unexpected layout shifts.

**Visual states**
- [ ] DoT depletion progresses horizontally and remains legible at 28px.
- [ ] Expired DoTs remain visible and recognizable.
- [ ] Fear countdown displays whole seconds only.
- [ ] Normal, Recast, Critical, Broken, and Expired states are visually distinct.
- [ ] All Fear states preserve identical button dimensions.
- [ ] Fear urgency is recognizable without reading other debuffs.

**Functionality**
- [ ] Existing GUID tracking and raid-marker assignment remain operational.
- [ ] Row and marker mappings remain stable throughout combat.
- [ ] Existing supported click-to-recast interactions continue working.
- [ ] Secure button operations do not introduce combat-lockdown errors.
- [ ] Performance remains stable with at least five tracked mobs.

## Out of Scope

- Reworking secure targeting architecture.
- Group/raid support.
- Additional tracking categories.
- New combat alerts or audio cues.
- New configuration panels beyond layout/scale settings.

