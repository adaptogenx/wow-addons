#!/usr/bin/env bash
# Shared helpers for repo scripts. Source, don't execute.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED_UI_SRC="$REPO_ROOT/shared/ui"

# addon-id : addon dir : staged shared dir : toc : zip root folder
ADDONS=(
    "ph|addons/ph|addons/ph/ph/Shared/UI|addons/ph/ph/ph.toc|ph"
    "pockets|addons/pockets|addons/pockets/pockets/Shared/UI|addons/pockets/pockets/Pockets.toc|Pockets"
)

if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
    RED=""; GREEN=""; BLUE=""; NC=""
fi

info() { echo "${BLUE}$*${NC}"; }
ok()   { echo "${GREEN}✓ $*${NC}"; }
die()  { echo "${RED}✗ $*${NC}" >&2; exit 1; }

# addon_field <id> <1-based field>
addon_field() {
    local row
    for row in "${ADDONS[@]}"; do
        if [ "${row%%|*}" = "$1" ]; then
            echo "$row" | cut -d'|' -f"$2"
            return 0
        fi
    done
    return 1
}

addon_ids() {
    local row
    for row in "${ADDONS[@]}"; do echo "${row%%|*}"; done
}

# Every test/lint/build entry point calls this first. Failure aborts the
# caller (callers run with set -e / explicit checks).
run_sync() {
    "$REPO_ROOT/scripts/sync-shared.sh" || die "sync-shared failed"
}
