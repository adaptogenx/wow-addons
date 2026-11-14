# Forever API Matrix

Tested build: WoW Forever 1.60.1 build 70790 (Nov 3 2026), `## Interface: 16001`, WOW_PROJECT_ID=18, enUS, Warlock L8.
Evidence: `HMF_API_LabDB` (SavedVariables) from `hmf-api-lab/`. Status: M0-M3 complete. M4 not yet run.

| API / feature | Status | Evidence |
|---|---|---|
| `UnitGUID/UnitName/UnitExists/UnitAffectingCombat/UnitCanAttack` on target, focus, mouseover, nameplateN | PASS: READABLE in and out of combat | M1 UNIT lines |
| `UnitThreatSituation` | INCONCLUSIVE: always nil, never secret (mob may not have been targeting player) | M1 UNIT lines |
| `UnitPosition` | exists; not probed | M0 CAP |
| `C_NamePlate.GetNamePlates` / `NAME_PLATE_UNIT_ADDED/REMOVED` | PASS: works in combat, payload token readable | M1 |
| `UNIT_SPELLCAST_SUCCEEDED` (player) | PASS: unit, castGUID, spellID all READABLE in combat | M1 CAST lines |
| `C_UnitAuras`: GetUnitAuraBySpellID, GetAuraDataByIndex, GetAuraDataByAuraInstanceID, GetAuraDuration, GetUnitAuraInstanceIDs, GetAuraCasterGUID, DoesAuraHaveExpirationTime | EXIST; behavior untested (M2) | M0 NS |
| `issecretvalue`, `canaccessvalue`, `issecrettable`, `hasanysecretvalues`, `scrubsecretvalues`, `secretwrap`, `dropsecretaccess`, `canaccesssecrets` | EXIST | M0 GSCAN |
| `C_Secrets.*` (HasSecretRestrictions, ShouldUnitIdentityBeSecret, ShouldUnitAuraInstanceBeSecret, CanCompareUnitTokens, ...) | EXIST; `HasSecretRestrictions()` = true (out of combat, at login) | M0 |
| `C_DamageMeter` | EXISTS (8 functions); not evaluated | M0 NS |
| Templates: SecureActionButtonTemplate, SecureUnitButtonTemplate, AuraContainerTemplate, AuraButtonTemplate, AuraFrameTemplate, CooldownFrameTemplate | PRESENT (via `C_XMLUtil.GetTemplateInfo`; not global names) | M0 TEMPLATE |
| Mixins: AuraContainerMixin, AuraButtonMixin, AuraFrameMixin, `C_AuraContainerUtil`, `CustomAuraContainer*` option tables | PRESENT | M0 GSCAN |
| CompactAuraTemplate, TargetDebuffFrameTemplate, TargetBuffFrameTemplate | ABSENT | M0 |
| Events valid: UNIT_AURA, UNIT_TARGET, RAID_TARGET_UPDATE, UNIT_THREAT_LIST_UPDATE, UNIT_FLAGS, PLAYER_FOCUS_CHANGED, UPDATE_MOUSEOVER_UNIT, REGEN_* | VALID (registration of UNIT_AURA etc. not yet tested) | M0 EVENT |
| `COMBAT_LOG_EVENT_UNFILTERED`, `SetRaidTarget` | NOT TOUCHED (known blocked, see `.plans/FOREVER.md`) | - |
| Forever UI source (AuraContainer/AuraButton impl), event payload fields | UNVERIFIED: not readable from client; install has CASC data only | - |
| `C_UnitAuras.GetUnitAuraBySpellID` OUT of combat (player DoT on mob) | PASS: table with spellId, auraInstanceID, duration (12.0), expirationTime all READABLE | M2 s2 |
| `C_UnitAuras.GetUnitAuraBySpellID` / `GetAuraDataBySpellName` IN combat | RESTRICTED: returns nil for known debuffs (Fear, Corruption, Agony, Immolate) | M2 s2, s2b |
| `GetUnitAuraInstanceIDs`, `GetUnitAuras`, `GetAuraSlots`, `GetDebuffDataByIndex` IN combat | RESTRICTED: error "Auras cannot be accessed when secret while tainted by 'HMF_API_Lab'" | M2 s2b PATH |
| `UNIT_AURA` payload IN combat | RESTRICTED: `updateInfo` readable, but isFullUpdate/addedAuras/updatedAuraInstanceIDs/removedAuraInstanceIDs SECRET | M2 s2 payload stats |
| `UNIT_AURA` payload OUT of combat | PASS: fields readable, instance IDs usable | M2 s2 |
| `C_Secrets.ShouldAurasBeSecret()` | false out of combat, true in combat (transitions with combat state) | M2 secrecy |
| `C_Secrets.GetSpellAuraSecrecy(Fear/Corruption/Agony/Immolate)` | 2 = `Enum.SecrecyLevel.ContextuallySecret` (0 Never, 1 Always) | M2 secretenums |
| `C_Secrets.ShouldUnitIdentityBeSecret`, `ShouldUnitComparisonBeSecret` | false in and out of combat; `ShouldUnitSpellCastBeSecret`/`ThreatState` true | M2 secrecy |
| `Cooldown:SetCooldownFromDurationObject`, `SetCooldownFromExpirationTime`, `GetCooldownDisplayDuration` | EXIST. Out of combat: HUD path A (native) rendered and matched real timer. In combat: untestable, no aura ID obtainable | M2 |
| `AuraContainerTemplate`/`AuraFrameTemplate`/`AuraButtonTemplate` | EXIST but are the player buff frame (grid layout, BuffFrame.lua); no unit/filter-setting API found. Creating AuraFrameTemplate raises a Blizzard_BuffFrame error | M2 containerapi |
| `C_AuraContainerUtil.ProcessCustomAuraButton*Options`, `CustomAuraContainer*` option tables | EXIST (option processors only); no container constructor found | M2 auracontainer |
| Enum.SecretAspect (Cooldown, RadialProgress, Text, Alpha, ...) | EXISTS: native frames can hold secret values for these aspects | M2 secretenums |
| Secure buttons (`SecureActionButtonTemplate`) pre-created out of combat, attributes set out of combat | PASS: no ADDON_ACTION_FORBIDDEN/BLOCKED events | M3 |
| `type=spell unit=target` Fear, player-clicked | PASS (in and out of combat); sent target name matched | M3 SENT |
| `/cast [@focus,harm,nodead] Fear` via secure macro button | PASS in combat with target cleared; sent target = focus | M3 SENT |
| `/cast [@mouseover,harm,nodead] Fear` via `SetOverrideBindingClick` key (SHIFT-F), out of combat setup | PASS in and out of combat; user confirmed the hovered mob got Fear | M3, user observation |
| `/cast [@nameplate1,...] Fear` | FAIL: ~15 clicks, no cast sent | M3 CLICK, no SENT |
| `/tm N` via player-clicked secure macro (target) | PASS: moon appeared on target, RAID_TARGET_UPDATE fires, works in combat | M3 + user observation |
| `/tm [@mouseover,harm] 6` via bound key; `/tm [@focus,harm] 7` | PASS (user saw square on hovered mob; focus mark fired events) | M3 |
| `GetRaidTargetIndex(token)` | RESTRICTED: SECRET for a marked target (even out of combat); nil for unmarked/empty tokens | M3 m3marks |
| Mouseover/focus/nameplate unit tokens vs `UnitName` equality for recipient check | LIMITED: mobs shared a name; recipient proof needs distinct names or observation | M3 |
