#!/bin/bash
# Repository static checks for Hold My Fear.
#
# Validates:
#   1. Every file referenced by HoldMyFear.toc exists.
#   2. No duplicate toc entries.
#   3. No OnUpdate handlers in Core/ (domain state stays event-driven).
#   4. No secure-attribute writes (SetAttribute) outside UI/ and Adapters/.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/holdmyfear"
TOC="$ADDON_DIR/HoldMyFear.toc"
FAIL=0
fail() { echo "✗ $1"; FAIL=1; }

ENTRIES=$(grep -vE '^\s*(#|##|$)' "$TOC")
while IFS= read -r f; do
    [ -f "$ADDON_DIR/$f" ] || fail "toc references missing file: $f"
done <<< "$ENTRIES"
DUPES=$(echo "$ENTRIES" | sort | uniq -d)
[ -z "$DUPES" ] || fail "duplicate toc entries: $DUPES"

if grep -rn 'OnUpdate' "$ADDON_DIR/Core" 2>/dev/null; then fail "OnUpdate in Core/"; fi
if grep -rln 'SetAttribute' "$ADDON_DIR" --include=*.lua 2>/dev/null | grep -vE "/(UI|Adapters|Lab)/"; then
    fail "SetAttribute outside UI/ or Adapters/"
fi

[ "$FAIL" -eq 0 ] && echo "✓ static checks passed"
exit "$FAIL"
