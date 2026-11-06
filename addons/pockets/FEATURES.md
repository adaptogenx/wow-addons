# Pockets Feature Log

Player-facing changes, newest first. Written to paste into CurseForge release notes.
Add an entry under **Unreleased** whenever a user-visible feature ships; on release,
rename it to the version number.

## 1.2.1

### Resizable bag window
- Drag the bottom-right corner of the bag window to make it wider or taller. The grid reflows to fit, and the size is remembered per character.
- Height snaps to whole rows. The window can be shortened to about three rows, and can't be made narrower than its original width.
- Resizing is disabled in combat. `/pockets panel reset` restores the default size and position.

### Separate panel position
- The bag panel can now be moved independently of the Mini. It starts lined up exactly where it opened before; drag it anywhere from there. The Mini stays put and stays visible, underneath the panel.
- `/pockets panel attached` restores the old behavior, `/pockets panel separate` turns it back on, `/pockets panel reset` returns the panel to its default spot.

### Fixes
- Scrolling the bag window with the mouse wheel or trackpad in combat no longer throws an "action blocked" error.
- Moving or resizing the window when combat starts mid-drag no longer throws an error.

### Supply counts
- **Soul Shards** for warlocks, shown beside the gold and ammo pills.
- **Water** for mana classes (mage, priest, warlock, druid, paladin, shaman, hunter). Every kind of water rolls up into one count. The tooltip names the best water you carry.
- **Food** for any class, off by default. Turn it on with `/pockets food on`. One count for all food; the tooltip names the best.
- Click a supply pill to open the Consumable category. Counts also show in the bag footer.
- `/pockets supplies off` hides the shard and water counts.

## 1.1.0

- Grid bag view is now the default.
- Clicking the Mini can open your regular bags (`/pockets bags on`).
- Live gold display.
