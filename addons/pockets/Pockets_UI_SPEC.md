# Pockets — UI Implementation Specification

**Status:** v1 implementation spec  
**Audience:** Coding agent / Claude  
**Related:** `Pockets_PRD.md`, `Pockets_TDD.md`  

## 1. Authority and goal

Implement the compact Pockets interaction model shown in the visual reference while keeping screen usage extremely small. The image is directional; **this written spec is authoritative** when they differ.

The interaction hierarchy is:

`HUD → Category Flyout → Item Panel`

`Shift-B → Full Inventory`

## 2. Primary HUD

Replace the current text-only capacity box with a fixed-size control containing a prominent square Blizzard bag icon.

Concept:

```text
┌──────┬──────────────────┐
│      │                  │
│ BAG  │  76 / 86   ~28m │
│ ICON │                  │
│      │                  │
└──────┴──────────────────┘
```

Requirements:

- Large square bag icon, initially ~40–48 px at UI scale 1.0.
- Use an existing Blizzard/WoW bag texture, not custom artwork.
- `used / total` represents GENERAL capacity only.
- ETA is shown only when valid/confident enough.
- **HUD width is fixed.** Reserve capacity and ETA regions so appearance/disappearance or digit-count changes never resize it.
- Bag icon is part of the clickable HUD target.
- Click toggles category flyout.
- Hover opens category flyout outside combat.
- Hover does nothing in combat; click still works.
- Preserve drag/move behavior.

## 3. Blizzard icon assets

Pockets should use the large built-in WoW icon library wherever icons are needed.

**Do not bundle custom category or item icon art.**

### Actual items

Use the item's actual Blizzard icon returned by the target-client item/container APIs. Never choose an item icon based on its Pockets category.

### Category icons

Maintain one centralized mapping:

```lua
Pockets.CategoryIcons = {
    recent      = "<verified Blizzard texture>",
    equipment   = "<verified Blizzard texture>",
    consumable  = "<verified Blizzard texture>",
    trade_goods = "<verified Blizzard texture>",
    quest       = "<verified Blizzard texture>",
    ammo        = "<verified Blizzard texture>",
    junk        = "<verified Blizzard texture>",
    other       = "<verified Blizzard texture>",
}
```

Suggested visual concepts are clock/recent, sword/armor, potion/food, materials/coins, scroll, arrows/ammo, junk bag, and generic bag.

**Do not trust guessed texture path strings. Verify every selected icon exists in the target Classic TBC client before committing it.**

The main HUD should similarly use a recognizable verified Blizzard backpack/bag icon.

## 4. Category flyout geometry

The first prototype changes width based on content. It must not.

Initial targets at scale 1.0:

- Width: **220 px fixed**
- Row height: ~30 px
- Padding: ~10 px
- Category icon: 20–22 px

Height may vary vertically with visible categories.

Row layout:

```text
[icon] Category Name                 Count [>]
```

Example:

```text
[ ] Recent Items                        8  >
[ ] Equipment                          13  >
[ ] Consumables                       104  >
[ ] Trade Goods                       104  >
[ ] Quest                              37  >
[ ] Ammo                            1,248  >
[ ] Junk                                9  >
[ ] Other                             142  >
```

Counts occupy a fixed, right-aligned region. Labels truncate before pushing the count region. Neither counts nor labels may change panel width.

## 5. Hover navigation responsiveness

The current hover navigation feels laggy. Opening must feel effectively immediate.

Outside combat:

- HUD hover → category panel opens immediately/nearly immediately.
- Category hover → item panel switches immediately/nearly immediately.
- Moving from category panel into item panel keeps both open.

Target opening delay: **0–50 ms**.

A close grace period of roughly **150–250 ms** is acceptable to allow crossing a small physical gap between panels. A close grace period must never become an open delay.

Treat HUD + category panel + currently open item panel as one interactive hover region. Only start closing after the pointer leaves the complete region.

Do not rebuild frames or inventory state because the mouse moved.

## 6. No inventory work on hover

Hover must only read precomputed state.

Never synchronously perform these because of hover:

- bag scan;
- whole-category item metadata discovery;
- categorization;
- stack consolidation;
- ETA calculation;
- SavedVariables writes.

Conceptually:

```lua
selectedCategory = categoryID
ItemFlyout:Render(InventoryState:GetItemsByCategory(categoryID))
```

Bag/event processing belongs to the state layer defined in the TDD.

## 7. Category item panel

Open adjacent to the category flyout, preferably on the right. Flip left when required by screen bounds.

Initial layout target:

- 4 columns
- 40 px item buttons
- 4 px gap
- 8–10 px padding

Panel width derives from this fixed grid geometry, not item names.

For large categories, bound height and scroll/page rather than expanding off-screen.

## 8. Item icons must be real interactive WoW item buttons

This is a required correction to the first implementation.

**Icons in Pockets cannot be decorative textures.**

Every currently carried inventory item rendered in a category or full-inventory view must be backed by its real physical item location.

Normalized records therefore retain at least:

```lua
{
    bagID = ...,
    slotID = ...,
    itemID = ...,
    quantity = ...,
    texture = ...,
}
```

Required interactions, subject to target Classic TBC restrictions:

- left click: normal WoW use/equip behavior;
- right click: normal WoW item behavior;
- shift-click: normal link/split behavior where applicable;
- drag: normal item pickup/movement;
- hover: normal GameTooltip;
- visible stack count;
- locked-state handling.

Use Blizzard's normal container-item/button mechanisms appropriate to the target client rather than implementing fake click semantics.

The categorized view is virtual, but item interaction must always resolve to the real bag + slot.

### Stale-location safety

If inventory revision changes while a panel is open, update the rendered button's backing location. Never allow a stale categorized button to act on whatever item later occupies an old bag/slot.

## 9. Recent Items

Recent represents acquisition history, so it differs from a normal category.

If a Recent item is still carried, its entry may resolve to a current physical stack and be interactive.

If it is no longer carried, it must not expose a fake item action.

For v1, limiting Recent's clickable presentation to recently acquired items that are still carried is acceptable if it keeps interaction safe and simple.

## 10. Full Inventory

`Shift-B` opens the full categorized inventory.

Requirements:

- Recent first.
- Category-based layout.
- Simple search.
- Actual Blizzard item icons.
- Same real interactive item-button component used by the flyout.
- Fixed/bounded overall width.
- Internal scrolling when needed.
- No physical-bag columns.
- No width changes caused by counts/content.

Share item rendering/pooling code between item flyout and full inventory.

## 11. Ammo

Ammo remains a separate capacity pool.

Primary HUD:

```text
76 / 86   ~28m
```

This is GENERAL capacity only.

Expanded views may show:

```text
Ammo     1,248
```

Free ammo slots never increase the main bag capacity.

## 12. Combat behavior

Outside combat:

- HUD hover/click → categories.
- Category hover/click → items.
- Shift-B → full inventory.
- Item buttons behave normally.

In combat:

- HUD hover → no expansion.
- HUD click → categories.
- Category hover → no expansion.
- Category click → items.
- Shift-B → full inventory.
- Item interactions remain available wherever WoW permits.

Do not hide Pockets in combat. If one operation is protected/unavailable, fail only that operation.

## 13. Panel anchoring

Panels form one anchored system:

```text
HUD
 └─ CategoryFlyout
     └─ ItemFlyout
```

Requirements:

- Fixed panel widths.
- Consistent anchors.
- Item panel normally opens right; flips left near screen edge.
- Clamp panels to screen bounds.
- Switching categories reuses/repopulates one item panel rather than creating additional panels.

## 14. Frame reuse and pooling

Pool/reuse:

- category rows;
- item buttons;
- full-inventory item buttons if a single shared pool is impractical.

Do not create/destroy frames continuously during hover.

When switching categories, update backing bag/slot/item data, hide excess pooled buttons, and show required buttons.

## 15. Styling

Use restrained WoW-native styling:

- dark translucent backgrounds;
- Blizzard-like borders;
- WoW-native fonts where practical;
- yellow/gold primary labels consistent with the prototype;
- actual item quality colors for items;
- minimal decorative whitespace.

The visual reference is intentionally more spacious than the final target. **Bias smaller.**

## 16. Acceptance criteria

This UI revision is complete when:

1. HUD has a recognizable large default WoW bag icon.
2. HUD width never changes as counts/ETA change.
3. Category flyout width never changes as counts change.
4. Category counts remain aligned.
5. HUD → category → items hover navigation feels immediate.
6. Crossing between connected panels does not flicker or close/reopen.
7. Hover performs no bag scan/categorization work.
8. Actual items use their actual Blizzard icons.
9. Item icons are clickable and preserve normal WoW interactions.
10. Rendered buttons cannot act on stale bag/slot references.
11. Category icons come from verified built-in Blizzard/WoW icons.
12. No custom category icon image assets are required.
13. Hover expansion is suppressed in combat while click navigation remains.
14. Shift-B uses the same interactive item-button behavior.
15. The UI remains substantially smaller than a conventional all-bags-open layout.
