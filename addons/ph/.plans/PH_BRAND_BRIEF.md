# pH — Brand & Copy Brief  
**World of Warcraft Classic Addon**

---

## Overview

**pH** is a lightweight World of Warcraft Classic addon that measures player progress **per hour**.

The name “pH” stands for **per hour**, with a subtle nod to scientific measurement. The brand is intentionally restrained, neutral, and instrument-like—designed to feel compatible with Blizzard’s Classic UI rather than a modern overlay.

This addon does not tell players *how* to play.  
It measures outcomes so players can decide for themselves.

---

## Brand Positioning

- Functional, not flashy  
- Measured, not opinionated  
- Quietly authoritative  
- Classic-appropriate  

pH should feel like a built-in readout, not a mod competing for attention.

---

## Logo Spec (Theme A — Alchemical Readout)

### Wordmark

```
pH
```

- Lowercase `p`, uppercase `H`
- Designed to read clearly at 10–12px
- Subtle asymmetry improves recognition in dense UI layouts

### Font

- **Primary**: Friz Quadrata Std (or closest available)
- **Fallback**: Cinzel (Google Fonts), reduced letter spacing
- Weight: Regular → Semibold
- Never bold

### Icon Treatment (Optional)

A thin horizontal scale line beneath the wordmark:

```
pH
─────┼─────
```

- Center tick represents a neutral baseline
- No numbers or labels
- Used only in expanded views, settings, or summaries

### Spacing & Sizing

| Context | Size | Notes |
|------|----|----|
| Collapsed frame | 12–14px | Text only |
| Expanded header | 16–18px | Include scale line |
| Settings / splash | 20–24px | Wordmark + scale |

Minimum padding equals the height of the lowercase `p`.

---

## Color Tokens (Classic-Safe)

```lua
-- Primary text
PH_TEXT_PRIMARY   = { r=0.86, g=0.82, b=0.70 }
PH_TEXT_MUTED     = { r=0.62, g=0.58, b=0.50 }

-- Accent (Alchemy Green)
PH_ACCENT_GOOD    = { r=0.25, g=0.78, b=0.42 }
PH_ACCENT_NEUTRAL = { r=0.55, g=0.70, b=0.55 }
PH_ACCENT_BAD     = { r=0.78, g=0.32, b=0.28 }

-- Backgrounds
PH_BG_DARK        = { r=0.08, g=0.07, b=0.06 }
PH_BG_PARCHMENT   = { r=0.18, g=0.16, b=0.13 }

-- Borders
PH_BORDER_BRONZE  = { r=0.52, g=0.42, b=0.28 }
```

---

## Copy System

### Primary Description
> **pH measures your progress per hour.**

### Short Description
> Track gold, experience, honor, and reputation **per hour**, live and by session.

### Long Description
> **pH** tracks what you earn **per hour**—gold, experience, honor, and reputation—so you can compare sessions without guessing.

---

## Brand Principles

- No slang  
- No hype  
- Measurement over motivation  
- Calm, readable, accurate
