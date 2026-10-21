#!/usr/bin/env bash
# Packaging + sync-guard tests. Builds both zips from the real tree, and
# exercises stale/obsolete detection in a throwaway copy.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

FAILED=0
check() { # check <desc> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else echo "${RED}✗ $desc${NC}" >&2; FAILED=1; fi
}
check_fails() { # command must exit nonzero
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then echo "${RED}✗ $desc (expected failure)${NC}" >&2; FAILED=1; else ok "$desc"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- sync guard, in a scratch copy of the repo ---------------------------
COPY="$WORK/repo"
mkdir -p "$COPY"
(cd "$REPO_ROOT" && tar --exclude=.git --exclude=dist --exclude='releases' -cf - scripts shared addons) | tar -xf - -C "$COPY"
S="$COPY/scripts/sync-shared.sh"

check "sync --check passes on a synced tree" "$S" --check
echo "-- tamper" >> "$COPY/addons/pockets/pockets/Shared/UI/PHUI.lua"
check_fails "stale staged file fails --check (pockets)" "$S" --check
check "sync repairs stale file" "$S"
check "tree is clean after repair" "$S" --check

echo "return 1" > "$COPY/addons/ph/ph/Shared/UI/Obsolete.lua"
check_fails "obsolete staged file fails --check" "$S" --check
check "sync removes obsolete file" "$S"
check "obsolete file is gone" test ! -e "$COPY/addons/ph/ph/Shared/UI/Obsolete.lua"

rm "$COPY/addons/ph/ph/Shared/UI/MetricRow.lua"
check_fails "missing staged file fails --check" "$S" --check
"$S" >/dev/null

# sync failure must be fatal for callers
mv "$COPY/shared/ui" "$COPY/shared/ui.gone"
check_fails "sync fails when canonical dir is missing" "$S"
mv "$COPY/shared/ui.gone" "$COPY/shared/ui"

# build self-heals stale files rather than shipping them
echo "-- tamper" >> "$COPY/addons/ph/ph/Shared/UI/PHUI.lua"
check "build re-syncs stale files before packaging" "$COPY/scripts/build.sh" ph
check "built zip carries canonical PHUI" bash -c "
    d=\$(mktemp -d); unzip -q '$COPY/dist/ph.zip' -d \$d && cmp '$REPO_ROOT/shared/ui/PHUI.lua' \$d/ph/Shared/UI/PHUI.lua; r=\$?; rm -rf \$d; exit \$r"

# --- real build ----------------------------------------------------------
"$REPO_ROOT/scripts/build.sh" >/dev/null || { echo "${RED}✗ build.sh failed${NC}" >&2; exit 1; }
ok "build.sh builds both zips"

EXTRACT="$WORK/extract"
for id in $(addon_ids); do
    folder="$(addon_field "$id" 5)"
    zip="$REPO_ROOT/dist/$id.zip"
    [ -f "$zip" ] || { echo "${RED}✗ dist/$id.zip missing${NC}" >&2; FAILED=1; continue; }
    mkdir -p "$EXTRACT/$id"
    unzip -q "$zip" -d "$EXTRACT/$id"
    root="$EXTRACT/$id/$folder"

    check "[$id] zip root folder is $folder with $folder.toc" test -f "$root/$folder.toc"
    check "[$id] every TOC file reference exists" bash -c "
        grep -v '^[[:space:]]*#' '$root/$folder.toc' | grep -E '\.(lua|xml)[[:space:]]*\$' | tr -d '\r' | while read -r f; do [ -f '$root/'\"\$f\" ] || { echo missing \$f; exit 1; }; done"
    for src in "$SHARED_UI_SRC"/*.lua; do
        check "[$id] shared $(basename "$src") identical to canonical" cmp "$src" "$root/Shared/UI/$(basename "$src")"
    done
    check "[$id] declares no addon dependencies" bash -c "! grep -iE '^## *(RequiredDeps|Dependencies|OptionalDeps|Dep[0-9]*):' '$root/$folder.toc'"
    check "[$id] has no shared-lib-only leftovers (no .DS_Store)" bash -c "[ -z \"\$(find '$root' -name .DS_Store)\" ]"
done

# No runtime dependency on the other addon, by identifier.
check "ph zip never references Pockets" bash -c "! grep -rIl 'Pockets' '$EXTRACT/ph'"
check "pockets zip never references pH globals" bash -c "! grep -rIlE '\bpH_[A-Za-z]|GoldPH' --include=*.lua '$EXTRACT/pockets' | grep -v LootLogTests"

# Both zips ship the same shared source (hash of Shared/UI).
H1=$(cd "$EXTRACT/ph/ph/Shared/UI" && cat $(ls | sort) | shasum | cut -d' ' -f1)
H2=$(cd "$EXTRACT/pockets/Pockets/Shared/UI" && cat $(ls | sort) | shasum | cut -d' ' -f1)
check "both zips contain identical shared sources" test "$H1" = "$H2"

[ "$FAILED" -eq 0 ] || exit 1
ok "packaging tests passed"
