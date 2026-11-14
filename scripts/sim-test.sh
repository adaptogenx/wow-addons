#!/usr/bin/env bash
# DEV ONLY, optional. Runs sim-tests/<addon>/*.lua in wow-ui-sim against a
# staged copy of the shipped addon. Not part of lint/test/build/release.
# Usage: scripts/sim-test.sh [ph|pockets|hmf ...]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BIN="${WOW_SIM_HOME:-$HOME/tools/wow-ui-sim}/app/Contents/MacOS/wow-sim"
[ -x "$BIN" ] || die "wow-sim missing. Run scripts/sim-install.sh"

WOW_INSTALL_PATH="${WOW_INSTALL_PATH:-/Applications/World of Warcraft}"
[ -d "$WOW_INSTALL_PATH" ] || die "No WoW install at $WOW_INSTALL_PATH (set WOW_INSTALL_PATH). Sim needs it for Blizzard UI."
export WOW_INSTALL_PATH WOW_SIM_NO_SOUND=1 WOW_SIM_NO_ERROR_DIALOG=1

# Drops Blizzard_* Lua error blocks (sim noise) from log output. SIM_RAW=1 keeps all.
strip_blizzard() {
    if [ -n "${SIM_RAW:-}" ]; then cat; return; fi
    sed 's/\x1b\[[0-9;]*m//g' | awk '
        /^(Lua [Ee]rror|Interface\/AddOns\/Blizzard_|\[Interface\/AddOns\/Blizzard_)/ { skip = 1; next }
        skip && (/^$/ || /^\[ *[0-9.]+s\]/ || /^ +(✓|✗)/ || /^[0-9]+ tests,/ || /^Running/ || /^===/) { skip = 0 }
        !skip { print }'
}

run_sync
STAGE="$REPO_ROOT/.sim/AddOns"
rm -rf "$REPO_ROOT/.sim"; mkdir -p "$STAGE"

# hmf is not in lib.sh ADDONS on purpose (that table drives build/lint/release).
# resolve <id> -> "<toc path>|<staged folder name>"
resolve() {
    case "$1" in
        hmf) echo "addons/hold-my-fear/holdmyfear/HoldMyFear.toc|HoldMyFear" ;;
        *)   echo "$(addon_field "$1" 4)|$(addon_field "$1" 5)" ;;
    esac
}

ids=("$@"); [ ${#ids[@]} -gt 0 ] || ids=($(addon_ids) hmf)
fail=0
for id in "${ids[@]}"; do
    r="$(resolve "$id")"; toc="${r%%|*}"; folder="${r##*|}"
    [ -n "${toc%%|*}" ] && [ "$toc" != "|" ] || die "unknown addon: $id"
    src="$REPO_ROOT/sim-tests/$id"
    [ -d "$src" ] || { info "skip $id (no sim-tests/$id)"; continue; }
    dest="$STAGE/$folder"
    cp -R "$REPO_ROOT/$(dirname "$toc")" "$dest"
    rm -rf "$dest/tests"; mkdir -p "$dest/tests"
    cp "$src"/*.lua "$dest/tests/"
    info "sim: $id"
    log="$(mktemp)"
    if "$BIN" --addons-path "$STAGE" --no-saved-vars --allow-ui-version-mismatch \
        run-tests "$folder" </dev/null >"$log" 2>&1; then rc=0; else rc=$?; fi
    if [ $rc -ne 0 ] || [ -n "${SIM_VERBOSE:-}" ]; then
        strip_blizzard < "$log"; [ $rc -eq 0 ] || fail=1
    else
        # Quiet: only test results. Blizzard_* Lua errors are sim noise.
        sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E '^ +(✓|✗)|^[0-9]+ tests,|Failed during loading: [1-9]|Loaded with Lua errors during loading: [1-9]'
        grep -qE '[1-9][0-9]* failed' <(sed 's/\x1b\[[0-9;]*m//g' "$log") && fail=1
    fi
    rm -f "$log"
done
rm -rf "$REPO_ROOT/.sim"
[ $fail -eq 0 ] && ok "sim tests passed" || die "sim tests failed"
