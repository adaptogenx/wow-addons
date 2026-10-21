#!/bin/bash
# Setup script to install git hooks for Pockets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up git hooks for Pockets..."

if [ ! -d "$SCRIPT_DIR/.git" ]; then
    echo "❌ Error: not a git repository (run 'git init' first)"
    exit 1
fi

# Copy pre-commit hook
if [ -f "$SCRIPT_DIR/.git/hooks/pre-commit" ]; then
    echo "✅ Pre-commit hook already installed"
else
    cat > "$SCRIPT_DIR/.git/hooks/pre-commit" << 'HOOK_EOF'
#!/bin/bash
# Pre-commit hook to run luacheck on Lua files

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if luacheck is installed
if ! command -v luacheck &> /dev/null; then
    echo -e "${YELLOW}Warning: luacheck is not installed. Skipping lint check.${NC}"
    echo -e "${YELLOW}Install with: pip install luacheck${NC}"
    echo -e "${YELLOW}Or: brew install luacheck${NC}"
    exit 0  # Don't block commit if luacheck isn't installed
fi

# Get list of staged Lua files
STAGED_LUA_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.lua$')

# If no Lua files are staged, skip linting
if [ -z "$STAGED_LUA_FILES" ]; then
    exit 0
fi

echo "Running luacheck on staged Lua files..."

# Run luacheck on staged files
luacheck $STAGED_LUA_FILES

# Capture exit code
LINT_EXIT_CODE=$?

if [ $LINT_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Luacheck found issues. Please fix them before committing.${NC}"
    echo -e "${YELLOW}To bypass this check (not recommended), use: git commit --no-verify${NC}"
    exit 1
fi

# Run repository static checks as well
if [ -x "./scripts/static-checks.sh" ]; then
    echo "Running repository static checks..."
    if ! ./scripts/static-checks.sh; then
        echo -e "${RED}❌ Static checks failed. Please fix them before committing.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Luacheck and static checks passed!${NC}"
exit 0
HOOK_EOF

    chmod +x "$SCRIPT_DIR/.git/hooks/pre-commit"
    echo "✅ Pre-commit hook installed"
fi

echo ""
echo "Git hooks setup complete!"
echo ""
echo "The pre-commit hook will automatically run luacheck and static checks on staged .lua files."
echo "To install luacheck: pip install luacheck  (or: brew install luacheck)"
