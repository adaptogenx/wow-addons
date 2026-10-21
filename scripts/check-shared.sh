#!/usr/bin/env bash
# Validate the shared library itself: strict lint, no addon-specific
# references, no global publication. Syncs first.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
run_sync
"$REPO_ROOT/scripts/sync-shared.sh" --check

command -v luacheck >/dev/null || die "luacheck not installed (brew install luacheck)"
(cd "$REPO_ROOT/shared" && luacheck . --no-color --formatter plain) || die "shared/ui lint failed"
ok "shared/ui lint clean (no global writes)"

# Addon-specific identifiers must never appear in shared code (comments
# included, so the rule stays greppable).
FORBIDDEN='Pockets|pH_[A-Za-z]|GoldPH|Adapters|ClientAPI|PH_HUD_WIDTH|_G\.PHUI|InventoryState|SessionManager'
HITS=$(grep -nE "$FORBIDDEN" "$SHARED_UI_SRC"/*.lua || true)
[ -z "$HITS" ] || { echo "$HITS" >&2; die "addon-specific references in shared/ui"; }
ok "no addon-specific references in shared/ui"

# Every shared file must take the injected namespace.
for f in "$SHARED_UI_SRC"/*.lua; do
    grep -qE '^local (_|addonName), addon = \.\.\.' "$f" || die "$(basename "$f") does not use the injected addon namespace"
done
ok "all shared files use the injected addon namespace"
