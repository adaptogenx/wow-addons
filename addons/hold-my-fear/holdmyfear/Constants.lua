--[[
    Constants.lua - Shared constants for Hold My Fear
]]

local _, HMF = ...

HMF.Constants = {
    SLASH = "/hmf",

    FEAR_SPELL = "Fear",
    DEFAULT_FEAR_DURATION = 20, -- used only until an aura scan confirms the real duration
    RESET_DELAY = 5,            -- seconds after combat ends before tracking resets
    PRUNE_TICK = 2,             -- seconds between sweeps for rows that should be gone
    PRUNE_GRACE = 2,            -- a new row is never pruned for this long
    STALE_SECONDS = 20,         -- idle row with an unreadable unit for this long is dropped

    -- Cycling order for assigned raid markers (preview order: moon, square, triangle, diamond first
    -- is cosmetic; any permutation of 1..8 works). Length is also the max tracked enemies.
    -- Player debuffs shown as icons on each row, in slot order. Durations are estimates used only
    -- until an aura scan confirms the real value; omit a duration to show the icon with no timer.
    TRACKED_DEBUFFS = {
        "Corruption", "Curse of Agony", "Immolate", "Siphon Life", "Unstable Affliction", "Seed of Corruption",
        "Curse of Doom", "Curse of the Elements", "Curse of Recklessness", "Curse of Tongues",
        "Curse of Weakness", "Curse of Exhaustion",
    },
    DEBUFF_ESTIMATES = {
        ["Corruption"] = 18, ["Curse of Agony"] = 24, ["Immolate"] = 15, ["Siphon Life"] = 30,
        ["Unstable Affliction"] = 18, ["Seed of Corruption"] = 18, ["Curse of Doom"] = 60,
        ["Curse of the Elements"] = 300,
    },
    -- Spell IDs per tracked spell (Classic ranks; Unstable Affliction and Seed are TBC IDs, not yet
    -- checked in client). Forever hides enemy auras from addon code, so the engine's aura slots
    -- filter by ID and player casts are matched by ID.
    SPELL_IDS = {
        Fear = { 5782, 6213, 6215 },
        Corruption = { 172, 6222, 6223, 7648, 11671, 11672, 25311 },
        ["Curse of Agony"] = { 980, 1014, 6217, 11711, 11712, 11713 },
        Immolate = { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309 },
        ["Siphon Life"] = { 18265, 18879, 18880, 18881 },
        ["Unstable Affliction"] = { 30108, 30404, 30405 },
        ["Seed of Corruption"] = { 27243 },
        ["Curse of Doom"] = { 603 },
        ["Curse of the Elements"] = { 1490, 11721, 11722 },
        ["Curse of Recklessness"] = { 704, 7658, 7659, 11717 },
        ["Curse of Tongues"] = { 1714, 11719 },
        ["Curse of Weakness"] = { 702, 1108, 6205, 7646, 11707, 11708 },
        ["Curse of Exhaustion"] = { 18223 },
    },
    -- Forever renames some spells; the aura engine and cast matching accept either name.
    SPELL_ALIASES = { ["Curse of Agony"] = "Bane of Agony" },
    -- Dimmed placeholders on every row (when the spell is known) until the spell is cast.
    PLACEHOLDER_DOTS = { "Corruption", "Curse of Agony", "Immolate", "Siphon Life", "Unstable Affliction" },
    -- DoTs whose damage is summed for the "will it die" estimate.
    DAMAGE_DOTS = { Corruption = true, ["Curse of Agony"] = true, Immolate = true, ["Siphon Life"] = true,
        ["Unstable Affliction"] = true },
    RECONCILE_GRACE = 1.5, -- seconds after a cast before a missing engine bar counts as "aura gone"
    -- Fear lasts 10/15/20s by rank (no aura read on Forever, so this is the timer).
    FEAR_DURATIONS = { [5782] = 10, [6213] = 15, [6215] = 20 },
    BROKEN_MIN_LEFT = 1.5, -- confirmed Fear removed with more than this left = broken early

    MARKER_ORDER = { 5, 6, 4, 3, 1, 2, 7, 8 },

    FOCUS = {
        MIN_DWELL = 5, -- seconds a suggestion is held before it may hand off to another enemy
    },

    HUD = {
        ROW_WIDTH = 330,
        WIDTH_MIN = 240,
        WIDTH_MAX = 380,
        ROW_HEIGHT = 68,
        ROW_GAP = 4,
        PAD = 8,
        ICON = 28,
        ICON_GAP = 4,
        PORTRAIT = 32,
        MARKER = 24,
        NAME_SIZE = 12,
        FOCUS_TAG_W = 134, -- right-hand space on the name line for the FOCUS / SET FOCUS tag and the health %
        PCT_W = 34,
        DMG_W = 42, -- width of the DoT damage sum next to the health %
        ARROW = 20,
        ARROW_HALF_FOV = 0.7, -- radians; camera half-width used to turn nameplate x into an angle
        ARROW_STALE = 0.6,    -- seconds without a visible nameplate before the arrow dims
        FEAR_BUFFER = 0.3, -- seconds added to Fear cast time for the Recast state
        DEFAULT_CAST = 1.5,
        TICK = 0.1,
        DEFAULT_POINT = { "CENTER", "CENTER", -380, 80 },
        SCALE_MIN = 0.5,
        SCALE_MAX = 1.5,
    },
}

-- Lookup tables derived from the lists above.
local C = HMF.Constants
C.DEBUFF_INDEX = {}
for i, name in ipairs(C.TRACKED_DEBUFFS) do C.DEBUFF_INDEX[name] = i end
C.SPELL_NAME_BY_ID = {}
for name, ids in pairs(C.SPELL_IDS) do
    for _, id in ipairs(ids) do C.SPELL_NAME_BY_ID[id] = name end
end
