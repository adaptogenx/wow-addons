# Forever Feasibility (preliminary: M0-M3)

| Core feature | Status | Basis |
|---|---|---|
| Identify enemies by GUID (target/focus/mouseover/nameplate) | Supported | M1 |
| Detect enemies entering/leaving range (nameplate events) | Supported | M1 |
| Fear/DoT detection and authoritative timers in combat | Unsupported | M2: aura data is secret/blocked for addon code in combat |
| Fear/DoT timers out of combat | Supported (limited use) | M2 |
| Native display of secret aura durations | Unverified / no API found | M2 |
| Estimated Fear timer from player casts | Partially Supported (estimate only, labeled, non-authoritative) | M2 |
| Recast-due logic | Supported on readable/estimated input; never on unknown | M2 |
| One-click recast via secure buttons (target/focus/mouseover tokens, in combat) | Supported | M3 |
| One-click recast on a specific GUID/nameplate row | Unsupported | M3 (@nameplateN casts nothing) |
| Assign raid markers via player-clicked/bound secure `/tm` | Supported (focus/target/mouseover; unverifiable) | M3 |
| Read back / verify raid markers | Unsupported (GetRaidTargetIndex is secret) | M3 |

Architecture implication: GUID-keyed insecure tracking of enemies is viable. Authoritative Fear/DoT state is not readable in combat, so the HUD cannot show real Fear timers or detect breaks. Any timer must be an explicitly labeled estimate from player casts, or the feature is disabled.
