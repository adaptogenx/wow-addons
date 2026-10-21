#!/usr/bin/env bash
# Build dist/<addon>.zip for each addon (or just the ones named).
#   build.sh [ph] [pockets]
# Syncs shared/ui first, lints, then verifies the staged tree before and
# after zipping. A stale staged file fails the build.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
run_sync
"$REPO_ROOT/scripts/lint.sh"
"$REPO_ROOT/scripts/sync-shared.sh" --check

command -v zip >/dev/null || die "zip not installed"
TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=($(addon_ids))

DIST="$REPO_ROOT/dist"
mkdir -p "$DIST"

build_one() {
    local id="$1" addon_dir folder toc_rel toc stage_src tmp zip_path
    addon_dir="$(addon_field "$id" 2)" || die "unknown addon: $id"
    toc_rel="$(addon_field "$id" 4)"
    folder="$(addon_field "$id" 5)"
    toc="$REPO_ROOT/$toc_rel"
    stage_src="$(dirname "$toc")"
    zip_path="$DIST/$id.zip"

    [ -f "$toc" ] || die "[$id] missing TOC: $toc_rel"
    [ "$(basename "$toc")" = "$folder.toc" ] || die "[$id] TOC name must match zip folder '$folder'"

    # Every file the TOC loads must exist in the tree being packaged.
    while IFS= read -r entry; do
        [ -f "$stage_src/$entry" ] || die "[$id] TOC references missing file: $entry"
    done < <(grep -v '^[[:space:]]*#' "$toc" | grep -E '\.(lua|xml)[[:space:]]*$' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # No dependency on the other addon.
    if grep -iE '^## *(RequiredDeps|Dependencies|OptionalDeps|Dep[0-9]*):' "$toc" >/dev/null; then
        die "[$id] TOC declares addon dependencies"
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    mkdir -p "$tmp/$folder"
    cp -R "$stage_src/." "$tmp/$folder/"
    find "$tmp" \( -name '.DS_Store' -o -name '*.swp' -o -name '*~' -o -name '*.bak' \) -delete

    rm -f "$zip_path"
    (cd "$tmp" && zip -X -r -q "$zip_path" "$folder") || die "[$id] zip failed"

    # Verify the artifact itself, not just the source tree.
    local check
    check="$(mktemp -d)"
    unzip -q "$zip_path" -d "$check"
    for src in "$SHARED_UI_SRC"/*.lua; do
        cmp -s "$src" "$check/$folder/Shared/UI/$(basename "$src")" || { rm -rf "$check"; die "[$id] zip has stale/missing shared file $(basename "$src")"; }
    done
    [ -f "$check/$folder/$folder.toc" ] || { rm -rf "$check"; die "[$id] zip missing $folder.toc"; }
    rm -rf "$check"
    ok "built dist/$id.zip ($(du -h "$zip_path" | cut -f1 | tr -d ' '))"
}

for id in "${TARGETS[@]}"; do build_one "$id"; done
