Future Pockets plan: adaptive viewport sizing and directional growth.

DO NOT IMPLEMENT THIS NOW.

This document is a design/technical plan for a later dedicated pass because screen-aware sizing and positioning will require in-game tuning across resolutions, UI scales, and anchor locations.

GOAL

Pockets should adapt its maximum panel size and growth direction based on where the user places the Glance widget on screen.

Current V1 rule:

TOPLEFT is the shared origin
expanded states grow right/down

Future rule:

growth direction and maximum available viewport derive from screen position.

==================================================
1. PRODUCT PRINCIPLE
==================================================

Do not shrink list rows to fit screen space.

Instead:

viewport adapts to available screen real estate.

One list geometry remains consistent everywhere.

==================================================
2. AVAILABLE SPACE MODEL
==================================================

Determine available space around the saved root anchor:

spaceRight
spaceLeft
spaceBelow
spaceAbove

based on:

UIParent dimensions
UI scale
saved anchor position
safe margins

Conceptually:

spaceRight =
    screenRight - anchorX - safeRightMargin

spaceLeft =
    anchorX - screenLeft - safeLeftMargin

spaceBelow =
    anchorY - screenBottom - safeBottomMargin

spaceAbove =
    screenTop - anchorY - safeTopMargin

Exact WoW coordinate semantics must be normalized carefully.

==================================================
3. FUTURE GROWTH STRATEGY
==================================================

Potential strategy:

If positioned toward upper-left:
-> grow right/down

upper-right:
-> grow left/down

lower-left:
-> grow right/up

lower-right:
-> grow left/up

center-ish:
-> choose direction with most usable space

Do not hardcode behavior solely from quadrants without testing.

Prefer a strategy based on actual available width/height.

==================================================
4. MAX HEIGHT FROM AVAILABLE SPACE
==================================================

Instead of a fixed:

MAX_VISIBLE_ROWS = 6

future sizing could compute:

availableBodyHeight =
    availableVerticalSpace
    - headerHeight
    - footerHeight
    - outerPadding

Then:

maxVisibleRows =
    floor(
        availableBodyHeight / rowHeight
    )

Clamp this to reasonable product bounds:

MIN_VISIBLE_ROWS
MAX_VISIBLE_ROWS

Example:

small screen / near bottom:
-> 4–5 rows

large screen / near top:
-> 8–10 rows

This lets Pockets exploit space without overwhelming the screen.

==================================================
5. MAX WIDTH / GRID BEHAVIOR
==================================================

The same future system can eventually inform:

- Grid column count
- All Items usable width
- dynamic category packing
- search-result width
- scrollbar geometry

Do not mix this work into the initial height pass.

==================================================
6. SAFE AREAS
==================================================

Introduce configurable/internal safe margins for:

top
bottom
left
right

Reason:

screen edge is not the same as useful UI edge.

Users may have:
- action bars
- chat
- raid frames
- minimap
- unit frames

Initial dynamic implementation should probably use conservative screen margins, not attempt addon collision detection.

==================================================
7. DO NOT ATTEMPT ADDON COLLISION DETECTION IN FIRST VERSION
==================================================

Do not try to discover arbitrary other addon frames and route around them.

That becomes fragile quickly.

First adaptive version should consider:

UIParent bounds
Pockets anchor
safe margins
Pockets dimensions

User remains responsible for choosing a sensible placement.

==================================================
8. POSITION STRATEGY ABSTRACTION
==================================================

Keep position/growth decisions centralized.

Conceptually:

PositionStrategy:GetAnchor()
PositionStrategy:GetHorizontalGrowth()
PositionStrategy:GetVerticalGrowth()
PositionStrategy:GetAvailableWidth()
PositionStrategy:GetAvailableHeight()

Current implementation can continue returning:

TOPLEFT
RIGHT
DOWN

Future adaptive implementation replaces this logic without state renderers caring.

==================================================
9. TRANSITION INVARIANT
==================================================

Even when directional growth becomes dynamic:

all states must share the same logical origin.

Example if anchored at TOPRIGHT:

Glance -> Menu

TOPRIGHT remains fixed.

Menu grows:
left/down

The same principle currently applied to TOPLEFT must generalize to the selected root anchor.

Do not preserve center.

==================================================
10. DRAG / REPOSITION
==================================================

When user drags Glance:

- save normalized screen position
- recompute preferred growth strategy
- do not unexpectedly jump during drag
- apply new strategy on next expansion or once drag completes

Need careful UX testing before deciding whether growth orientation updates live.

==================================================
11. UI SCALE / RESOLUTION TEST MATRIX
==================================================

Future implementation needs deliberate testing across:

- 1080p
- 1440p
- ultrawide
- lower resolutions if Classic supports them
- multiple UI scales

Test positions:

top-left
top-right
bottom-left
bottom-right
center-left
center-right
top-center
bottom-center

And test:

Menu
short Category
long Category
Grid
All Items

==================================================
12. HYSTERESIS / FLAPPING RISK
==================================================

Avoid choosing growth direction based on tiny differences in available space.

Otherwise dragging around the center of screen could cause left/right or up/down strategy to flap.

Consider:

- quadrant preference
- threshold/hysteresis
- retain previous direction until alternative is materially better

This should be tested rather than guessed.

==================================================
13. USER PREFERENCE POSSIBILITIES
==================================================

Potential future settings:

Growth Direction:
- Auto
- Down/Right
- Down/Left
- Up/Right
- Up/Left

Maximum Rows:
- Auto
- custom override

Do not expose these until Auto behavior proves insufficient.

Opinionated Auto should remain the default.

==================================================
14. PERFORMANCE
==================================================

Available-space calculations only need to occur on:

- drag completion
- UI scale/resolution change
- state transition where dimensions matter
- explicit settings change

Do not calculate layout strategy every frame.

==================================================
15. TESTS
==================================================

Future tests should cover:

- available-space calculations
- anchor selection
- growth directions
- min/max row clamping
- screen-bound clamping
- no center-based resizing
- root anchor stability
- resolution changes
- UI scale changes
- repeated state transitions
- drag persistence

==================================================
16. NON-GOALS FOR FIRST DYNAMIC VERSION
==================================================

Do not initially implement:

- collision avoidance with arbitrary addons
- action-bar detection
- chat-frame detection
- docking
- snapping to other addons
- automatic repositioning of other frames
- animated reflow across the screen

Keep it deterministic and bounded.

==================================================
17. IMPLEMENTATION ORDER WHEN WE RETURN TO THIS
==================================================

Phase A:
- normalize root position representation
- abstract growth strategy
- calculate available screen space

Phase B:
- adaptive max list height
- vertical growth up/down

Phase C:
- adaptive horizontal growth
- Grid/All width behavior

Phase D:
- UX tuning across screen positions/resolutions

Do not start this until the fixed-height list behavior has been used and validated in-game.
