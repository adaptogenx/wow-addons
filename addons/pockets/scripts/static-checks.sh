#!/bin/bash
# Repository static checks for Pockets (TDD §25.3, §25.4)
#
# Validates:
#   1. Every Lua file referenced by Pockets.toc exists.
#   2. No duplicate file entries in the .toc.
#   3. No stale pH_/GoldPH_ namespace references leaked into Pockets code.
#   4. No direct bag API access outside Adapters/BagAPI.lua.
#   5. No OnUpdate handlers in Core/ (domain state must stay event-driven).
#   6. No stray print() calls outside Debug.lua/Events.lua/Tests/TestRunner.lua.
#
# Pass --verbose to also print the informational TODO/FIXME report.

set -u

VERBOSE=0
for arg in "$@"; do
    if [ "$arg" = "--verbose" ]; then
        VERBOSE=1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDON_DIR="$ROOT_DIR/pockets"
TOC_FILE="$ADDON_DIR/Pockets.toc"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAIL=0

fail() {
    echo -e "${RED}✗ $1${NC}"
    FAIL=1
}

pass() {
    echo -e "${GREEN}✓ $1${NC}"
}

if [ ! -f "$TOC_FILE" ]; then
    fail "Pockets.toc not found at $TOC_FILE"
    exit 1
fi

# --- Check 1 & 2: every referenced Lua/XML file exists, no duplicates ---
# bash 3.2 (macOS default) has no mapfile/associative arrays, so this uses
# plain word-splitting and a temp file instead.
TOC_ENTRIES_FILE="$(mktemp)"
grep -v '^[[:space:]]*#' "$TOC_FILE" | grep -E '\.(lua|xml)[[:space:]]*$' | sed 's/\r$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$TOC_ENTRIES_FILE"

MISSING_FOUND=0
while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if [ ! -f "$ADDON_DIR/$entry" ]; then
        fail "Missing file referenced by Pockets.toc: $entry"
        MISSING_FOUND=1
    fi
done < "$TOC_ENTRIES_FILE"
if [ "$MISSING_FOUND" -eq 0 ]; then
    pass "All .toc file references exist"
fi

DUPLICATES=$(sort "$TOC_ENTRIES_FILE" | uniq -d)
rm -f "$TOC_ENTRIES_FILE"
if [ -n "$DUPLICATES" ]; then
    fail "Duplicate .toc entries found:"
    echo "$DUPLICATES"
else
    pass "No duplicate .toc entries"
fi

# Bindings.xml is intentionally excluded from the .toc's Files list (WoW
# auto-discovers it by filename), so verify its presence separately.
if [ -f "$ADDON_DIR/Bindings.xml" ]; then
    pass "Bindings.xml present (auto-discovered by WoW, not in .toc Files)"
else
    fail "Bindings.xml missing from $ADDON_DIR"
fi
if grep -qE '^[[:space:]]*Bindings\.xml[[:space:]]*$' "$TOC_FILE"; then
    fail "Bindings.xml must NOT be listed in Pockets.toc's Files (breaks WoW's bindings parser)"
fi

# --- Check 3: stale pH_/GoldPH_ namespace references ---
STALE=$(grep -rnE '\b(pH_[A-Za-z]+|GoldPH_[A-Za-z]+)\b' "$ADDON_DIR" --include='*.lua' 2>/dev/null || true)
if [ -n "$STALE" ]; then
    fail "Found stale pH_/GoldPH_ references (copied code not generalized):"
    echo "$STALE"
else
    pass "No stale pH_/GoldPH_ references"
fi

# --- Check 4: direct bag/container API access outside BagAPI ---
BAG_API_PATTERN='C_Container\.|GetContainerNumSlots|GetContainerItemInfo|GetContainerItemLink|GetContainerItemID|PickupContainerItem|SplitContainerItem|GetContainerNumFreeSlots|UseContainerItem'
# Exclude comment-only lines (leading whitespace then --) so doc comments
# that merely mention these API names don't false-positive.
LEAKED_BAG_CALLS=$(grep -rnE "$BAG_API_PATTERN" "$ADDON_DIR" --include='*.lua' 2>/dev/null \
    | grep -v 'Adapters/BagAPI.lua' \
    | grep -v '/Tests/' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*--' || true)
if [ -n "$LEAKED_BAG_CALLS" ]; then
    fail "Direct bag/container API access outside Adapters/BagAPI.lua:"
    echo "$LEAKED_BAG_CALLS"
else
    pass "Bag/container API access is concentrated in Adapters/BagAPI.lua"
fi

# --- Check 5: no OnUpdate handlers in Core/ ---
ONUPDATE_IN_CORE=$(grep -rn 'OnUpdate' "$ADDON_DIR/Core" --include='*.lua' 2>/dev/null || true)
if [ -n "$ONUPDATE_IN_CORE" ]; then
    fail "OnUpdate handler found in Core/ (domain state must stay event-driven):"
    echo "$ONUPDATE_IN_CORE"
else
    pass "No OnUpdate handlers in Core/"
fi

# --- Check 6: stray print() outside Debug.lua ---
# Events.lua (slash-command help/output) and Tests/TestRunner.lua (/pockets
# test run results) are established, intentional chat-output call sites,
# same category as Debug.lua - not "stray" debug scaffolding, so they're
# excluded the same way. A genuinely new stray print() anywhere else still
# fails this check.
STRAY_PRINT=$(grep -rn '\bprint(' "$ADDON_DIR" --include='*.lua' 2>/dev/null \
    | grep -v 'Debug.lua' \
    | grep -v 'Events.lua' \
    | grep -v 'Tests/TestRunner.lua' || true)
if [ -n "$STRAY_PRINT" ]; then
    echo -e "${YELLOW}⚠ print() found outside Debug.lua/Events.lua/Tests/TestRunner.lua (review before release):${NC}"
    echo "$STRAY_PRINT"
else
    pass "No stray print() calls outside known chat-output call sites"
fi

# --- Informational: TODO/FIXME report (only with --verbose - these are
# tracked in .plans/Fix_TODO.md and planned follow-up work, not build
# blockers, so they'd otherwise clutter every release run) ---
if [ "$VERBOSE" -eq 1 ]; then
    TODOS=$(grep -rn 'TODO\|FIXME' "$ADDON_DIR" --include='*.lua' 2>/dev/null || true)
    if [ -n "$TODOS" ]; then
        echo -e "${YELLOW}ℹ TODO/FIXME markers present:${NC}"
        echo "$TODOS"
    fi
fi

if [ "$FAIL" -ne 0 ]; then
    echo -e "${RED}Static checks failed.${NC}"
    exit 1
fi

echo -e "${GREEN}All static checks passed.${NC}"
exit 0
