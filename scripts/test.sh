#!/usr/bin/env bash
# Run all offline tests. Always syncs shared/ui first.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
run_sync

command -v lua >/dev/null || die "lua not installed (brew install lua)"

info "pH unit tests"
for t in "$REPO_ROOT"/addons/ph/tests/*.lua; do
    (cd "$REPO_ROOT/addons/ph" && lua "tests/$(basename "$t")") || die "ph test failed: $(basename "$t")"
done
ok "pH unit tests"

info "shared library + namespace tests"
(cd "$REPO_ROOT" && lua tests/run.lua) || die "shared tests failed"

info "packaging tests"
"$REPO_ROOT/tests/test_packaging.sh" || die "packaging tests failed"
ok "all tests passed (in-game suites such as /pockets test run are NOT covered)"
