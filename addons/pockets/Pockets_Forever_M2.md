# Pockets on WoW Forever — M2 status (item interaction)

Branch: `feature/forever-m2` (from `feature/forever-m1`).

## Finding that changes the premise
The shipped item buttons do **not** use `SecureActionButtonTemplate` + `type2="item"`/`item2="bag slot"`.
They inherit `ContainerFrameItemButtonTemplate`, whose own Blizzard `OnClick` resolves bag/slot live from
`bagIndexFrame:GetID()` / `button:GetID()`. Pockets never replaces `OnClick`; `PreClick` only handles
split / modified-click / pickup. So the "secure target" is those two IDs. This architecture was kept.

## Runtime probe result (Forever beta, `/pockets debug secure`)
`templateProtected=false`, every button `protected=false`, `type2=nil`. So the item buttons are NOT
combat-protected on Forever and carry no secure item attribute: the combat deferral paths stay inert
(everything mutates normally in combat), stale targets rebind immediately, and open risks 1-2 below
do not apply. Still unverified: whether Blizzard's inherited OnClick can actually *use* items
(consumables/containers) from this non-secure button, in and out of combat.

## Not yet runtime-tested (needs the Forever client)
I cannot run the client here, so nothing below is verified in game. Run `/pockets debug secure`
(DumpSecureButtons) with a category open and report:
- `templateProtected=` (does the template make item buttons protected in combat on Forever?)
- per button: `protected=`, `type2=`, `secure=bag:slot`, `valid=`.
Then run the §36 interaction matrix and §35 combat matrix.

## What changed (defensive; Classic behaviour unchanged when buttons are not protected)
- `CombatAPI:CanMutateProtected(frame)`: asks the live frame (`IsProtected`) instead of assuming.
- `ItemButtonPool`:
  - Secure state tracked per button: `secureBagID/secureSlotID/secureItemID/secureBindingValid/pendingSecure`.
  - `Configure` = visual state (always) + `ConfigureSecure` (obeys combat).
  - `ValidateButton/ValidateAll`: stale target (item moved/gone/locked) is rebound to the smallest unlocked stack out of combat; in combat it is flagged stale (dimmed) and queued, IDs untouched.
  - `ReleaseAll`: no pcall; unbinds recycled buttons (no leaked target); in combat on protected buttons defers release (`pendingRelease`).
  - `Acquire` returns nil when blocked (combat + protected template); `ItemGrid`/`RecentItemStrip` stop placing.
  - `Probe`: learns `templateProtected` out of combat at Shell init.
  - `Reconcile`: after combat, flush releases and repair bindings from current state (never from queued targets).
  - Split: remembers the exact physical stack the split UI opened for; re-validates on confirm; amount must be < that stack's quantity; falls back to re-resolving, else no-op.
- `Shell`: `DeferIfItemsBlocked` (item-bearing renders wait for combat end; counts + stale flags still update), `OnCombatEnded` (Reconcile then render), `Events.lua` schedules a rescan on `PLAYER_REGEN_ENABLED`.
- Tests: `Tests/SecureBindingTests.lua` (bind, rebind, locked, gone, combat deferral, pool reuse, split, resolver order).

## Known residual risks / open questions for the runtime pass
1. If Forever's buttons are protected: while in combat, newly opened item views (category/all/search) cannot create/show buttons, so they appear after combat. Existing visible buttons stay and update counts. If this is unacceptable, M2.1 = pre-warm a button pool out of combat.
2. A stale protected button's right-click in combat still runs Blizzard's handler on the old IDs (we can't change them or cancel OnClick). It is dimmed and Pockets' own paths ignore it, but Blizzard's use-click could hit whatever now sits in that slot. Needs runtime confirmation of whether `SetID` is combat-safe (Blizzard's own bags call it in combat); if so rebind immediately instead of deferring.
3. Consumable right-click, container open, drag/drop, modified click, taint: unverified.
4. `HandleModifiedItemClick` and `SetBagItem` tooltip assumed available on Forever.
