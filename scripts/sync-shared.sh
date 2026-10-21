#!/usr/bin/env bash
# Stage shared/ui/*.lua into every addon's Shared/UI directory.
#
#   sync-shared.sh           copy canonical files, delete obsolete staged files
#   sync-shared.sh --check   change nothing; exit 1 if staged files differ
#
# shared/ui/ is the only source of truth. Staged copies are generated.
set -eu
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE=sync
[ "${1:-}" = "--check" ] && MODE=check

[ -d "$SHARED_UI_SRC" ] || die "missing canonical dir: shared/ui"
shopt -s nullglob
SRC_FILES=("$SHARED_UI_SRC"/*.lua)
[ ${#SRC_FILES[@]} -gt 0 ] || die "no canonical files in shared/ui"

FAIL=0
for id in $(addon_ids); do
    dest="$REPO_ROOT/$(addon_field "$id" 3)"

    if [ "$MODE" = check ]; then
        [ -d "$dest" ] || { echo "${RED}✗ [$id] staged dir missing: ${dest#$REPO_ROOT/}${NC}" >&2; FAIL=1; continue; }
    else
        mkdir -p "$dest"
    fi

    # Obsolete: anything staged that has no canonical counterpart.
    if [ -d "$dest" ]; then
        for f in "$dest"/* "$dest"/.[!.]*; do
            [ -e "$f" ] || continue
            if [ ! -f "$SHARED_UI_SRC/$(basename "$f")" ] || [ -d "$f" ]; then
                if [ "$MODE" = check ]; then
                    echo "${RED}✗ [$id] obsolete staged file: ${f#$REPO_ROOT/}${NC}" >&2; FAIL=1
                else
                    rm -rf "$f"
                fi
            fi
        done
    fi

    for src in "${SRC_FILES[@]}"; do
        name="$(basename "$src")"
        if [ "$MODE" = check ]; then
            if ! cmp -s "$src" "$dest/$name"; then
                echo "${RED}✗ [$id] stale or missing: ${dest#$REPO_ROOT/}/$name${NC}" >&2; FAIL=1
            fi
        else
            cmp -s "$src" "$dest/$name" 2>/dev/null || cp "$src" "$dest/$name"
        fi
    done
done

[ "$FAIL" -eq 0 ] || exit 1
if [ "$MODE" = check ]; then ok "staged shared files match shared/ui"; else info "shared/ui synced (${#SRC_FILES[@]} files)"; fi
