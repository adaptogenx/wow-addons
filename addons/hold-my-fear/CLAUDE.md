# CLAUDE.md

Guidance for Claude Code when working in this addon. Process rules are in
`AGENTS.md`; repo-wide rules are in the root `AGENTS.md`.

## Project Overview

Hold My Fear is a lightweight WoW Classic Anniversary / Forever Warlock
addon that tracks multiple feared enemies and their debuffs. See
`README.md` for the product description. Primary goal: one-click recasting
of individual debuffs on tracked enemies without switching targets.

Casting is mouseover/focus only (see `.plans/LAB_REPORT.md`, `.plans/DESIGN.md`); the HUD tracks and informs.

Initial scope is solo play. Secure targeting feasibility (casting against
nameplate unit tokens) must be proven with the lab addon in
`.plans/prompts/` before building the full addon.

Standalone: no dependency on pH or Pockets.

## Layout

- `holdmyfear/` - the addon (installed as `HoldMyFear`); `HoldMyFear.toc`
  declares `## Interface: 11509, 20504, 16001`.
  - `Init.lua`, `Constants.lua` - namespace bootstrap (load first)
  - `Adapters/` - only place allowed to call Blizzard unit/nameplate/
    spell/combat APIs directly
  - `Core/` - domain services with no frames (GUID tracking, marker
    assignment, debuff state); no `OnUpdate`
  - `UI/` - HUD rows and secure buttons; reads Core state, never owns it
  - `Events.lua`, `Debug.lua`, `Tests/` - wiring, debug, in-game tests
- `Lab/` - throwaway targeting lab (`/hmflab`), experiments 1-3 from `.plans/prompts/`; may use secure attributes directly
- `tests/` - offline Lua tests for Core (`lua tests/test_tracker.lua`)
- `scripts/static-checks.sh`, `install.sh`, `setup-hooks.sh`
- `.plans/` - specs and experiment prompts

## Namespace

`local ADDON_NAME, HMF = ...`, also exposed as `_G.HoldMyFear`. Sub-tables:
`Adapters`, `Services`, `UI`, `Tests`, `Constants`, `Debug`.

## Core Model

- Enemies are keyed by GUID. Each GUID gets a stable raid marker (cycling)
  and a stable HUD row for the whole encounter.
- HUD row: marker (outside left), arrow (outside right), portrait, DoT/curse
  icons with countdowns, Fear timer; name and level underneath.

## Constraints

- Lua 5.1 only.
- Forever-specific API differences must be documented in `.plans/`.
- Shared UI from `shared/ui/` may be used later; never edit staged copies.
