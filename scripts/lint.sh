#!/usr/bin/env bash
# Lint everything. Always syncs shared/ui first.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
run_sync

command -v luacheck >/dev/null || die "luacheck not installed (brew install luacheck)"
"$REPO_ROOT/scripts/check-shared.sh"

# Pockets: zero warnings.
info "luacheck: pockets"
(cd "$REPO_ROOT/addons/pockets" && luacheck pockets/ --no-color --formatter plain) || die "pockets lint failed"
ok "pockets lint clean"
"$REPO_ROOT/addons/pockets/scripts/static-checks.sh" || die "pockets static checks failed"

# pH: existing warnings are a ratchet (baseline file); staged shared files must be clean.
info "luacheck: ph"
OUT="$(cd "$REPO_ROOT/addons/ph" && luacheck ph/ --no-color --formatter plain || true)"
if echo "$OUT" | grep -q "Shared/UI/"; then
    echo "$OUT" | grep "Shared/UI/" >&2
    die "ph: staged shared files have lint warnings"
fi
COUNT=$(echo "$OUT" | grep -cE '^ph/.*:[0-9]+:[0-9]+:' || true)
BASE=$(tr -d '[:space:]' < "$REPO_ROOT/scripts/luacheck-ph-baseline.txt")
echo "$OUT" | grep -E ': (E|\(E)|invalid syntax' >/dev/null 2>&1 && die "ph: luacheck syntax errors"
[ "$COUNT" -le "$BASE" ] || die "ph lint: $COUNT warnings > baseline $BASE (fix new warnings)"
ok "ph lint: $COUNT warnings (baseline $BASE)"
