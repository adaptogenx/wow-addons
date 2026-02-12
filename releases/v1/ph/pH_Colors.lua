--[[
    pH_Colors.lua - pH Brand Color Tokens

    Centralized color palette following pH brand guidelines.
    Referenced from: PH_BRAND_BRIEF.md and PH_UI_DESIGN_BRIEF_AND_RULES.md
]]

local pH_Colors = {}

-- Primary text
pH_Colors.TEXT_PRIMARY = {0.92, 0.89, 0.80}
pH_Colors.TEXT_MUTED = {0.72, 0.68, 0.60}
pH_Colors.TEXT_DISABLED = {0.45, 0.42, 0.38}

-- Accents
pH_Colors.ACCENT_GOOD = {0.30, 0.85, 0.48}  -- Alchemy green (for rep)
pH_Colors.ACCENT_NEUTRAL = {0.60, 0.76, 0.60}
pH_Colors.ACCENT_BAD = {0.85, 0.38, 0.32}  -- Red (for paused state)
pH_Colors.ACCENT_WARNING = {0.90, 0.65, 0.20}  -- Amber (for expenses)
pH_Colors.ACCENT_GOLD = {1.00, 0.82, 0.00}  -- Classic gold (for income)

-- Backgrounds
pH_Colors.BG_DARK = {0.06, 0.05, 0.04}
pH_Colors.BG_PARCHMENT = {0.16, 0.14, 0.11}

-- Borders & Dividers
pH_Colors.BORDER_BRONZE = {0.55, 0.45, 0.30}
pH_Colors.DIVIDER = {0.28, 0.25, 0.22}

-- Interactive states
pH_Colors.HOVER = {0.22, 0.20, 0.17}
pH_Colors.SELECTED = {0.35, 0.32, 0.26}

-- Metric-specific (from micro-bars)
pH_Colors.METRIC_GOLD = {1.00, 0.82, 0.00, 0.85}
pH_Colors.METRIC_XP = {0.58, 0.51, 0.79, 0.85}
pH_Colors.METRIC_REP = {0.30, 0.85, 0.48, 0.85}
pH_Colors.METRIC_HONOR = {0.90, 0.60, 0.20, 0.85}

-- Export
_G.pH_Colors = pH_Colors
