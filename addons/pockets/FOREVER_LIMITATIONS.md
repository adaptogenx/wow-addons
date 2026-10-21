# Known Forever Limitations (developer-facing)

| Feature | Forever behavior | Pockets behavior | Fixable? | Deferred? |
|---|---|---|---|---|
| Item tooltips | No `OnTooltipSetItem`; uses `TooltipDataProcessor` | Carried-count line added via post-call on GameTooltip/ItemRefTooltip only | n/a | no |
| Secret Values | Item fields may be secret in restricted contexts | Secret id/quantity/quality/family treated as unavailable; slot skipped or conservative category | n/a | no |
| Item buttons in combat | Probe (M2): buttons not protected | Normal mutation in combat; combat-deferral paths stay inert | re-probe if client changes | no |
| Item use from Pockets buttons | Relies on Blizzard's inherited OnClick via secure attributes (`type2`/`item2`) | Works per M2 notes; needs in-game re-verification per beta patch | yes | no |
| Runtime verification | Not performed in CI | M3 matrix (mail/AH, bag swap, relog, combat) must be run in-game | n/a | pending |
