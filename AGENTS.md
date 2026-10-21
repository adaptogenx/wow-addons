WoW Addons — Agent Instructions

Repository

Monorepo containing independently distributed World of Warcraft addons.

* addons/ph/ — pH: session-based metrics tracking.
* addons/pockets/ — Pockets: inventory HUD and management.
* shared/ — reusable code and UI components.
* scripts/ — shared development and packaging tooling.

Each addon must remain independently installable, versioned, and released.

Instructions

* Follow the nearest AGENTS.md for addon-specific architecture and constraints.
* Read relevant code and specifications before making changes.
* Preserve existing behavior unless explicitly asked to change it.
* Make focused changes; avoid unrelated refactoring.
* Use Lua 5.1-compatible syntax and supported WoW APIs.
* Avoid accidental globals and cross-addon runtime dependencies.
* Keep shared implementations in shared/, not duplicated across addons.

Shared Code

* shared/ is the canonical source for reusable components.
* Shared code must not depend on addon-specific services or namespaces.
* Each addon bundles its own copy of shared code.
* Automatically synchronize shared code before linting, testing, or building.
* Validate changes to shared code against both addons.

Quality

After changes:

1. Run applicable linting and static checks.
2. Run relevant automated tests.
3. Validate packaging when manifests or shared code change.
4. Report results and any remaining in-game verification.

Never claim in-game tests passed without confirmation.

Documentation

Keep instructions close to their scope:

* Root AGENTS.md — repository-wide rules.
* addons/*/AGENTS.md — addon-specific rules.
* shared/AGENTS.md — shared library constraints.

Avoid duplicating instructions across files.
