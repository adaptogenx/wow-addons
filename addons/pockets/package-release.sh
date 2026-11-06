#!/bin/bash

# Pockets Addon Release Packaging Script
# Validates the repository then packages the addon into a versioned zip file.

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Stage the shared UI library (generated copies under Shared/UI) - never
# package or install stale shared files.
"$SCRIPT_DIR/../../scripts/sync-shared.sh" || { echo "sync-shared failed" >&2; exit 1; }

TOC_FILE="pockets/Pockets.toc"
if [ ! -f "$TOC_FILE" ]; then
    echo -e "${RED}Error: Pockets.toc not found at $TOC_FILE${NC}"
    exit 1
fi

VERSION=$(grep "^## Version:" "$TOC_FILE" | sed 's/## Version: //')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from Pockets.toc${NC}"
    exit 1
fi

echo -e "${BLUE}Validating Pockets before packaging...${NC}"

if command -v luacheck &> /dev/null; then
    echo -e "${BLUE}Running luacheck...${NC}"
    luacheck pockets/
else
    echo -e "${RED}Error: luacheck not installed. Install with 'brew install luacheck'.${NC}"
    exit 1
fi

if [ -x "./scripts/static-checks.sh" ]; then
    echo -e "${BLUE}Running static repository checks...${NC}"
    ./scripts/static-checks.sh
fi

echo -e "${BLUE}Packaging Pockets version ${GREEN}${VERSION}${NC}"

# Create releases directory if it doesn't exist
RELEASES_DIR="releases"
mkdir -p "$RELEASES_DIR"

# Define output zip filename
ZIP_NAME="pockets-${VERSION}.zip"
ZIP_PATH="${RELEASES_DIR}/${ZIP_NAME}"

# Remove old zip if it exists
if [ -f "$ZIP_PATH" ]; then
    echo -e "${BLUE}Removing existing ${ZIP_NAME}${NC}"
    rm "$ZIP_PATH"
fi

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
TARGET_DIR="${TEMP_DIR}/Pockets"
mkdir -p "$TARGET_DIR"

echo -e "${BLUE}Copying files to temporary directory...${NC}"

# Copy addon directory contents, excluding repo-only files
cp -r pockets/. "$TARGET_DIR/"

# Create the zip file (cd into temp dir so zip contains Pockets/ folder structure)
echo -e "${BLUE}Creating ${ZIP_NAME}...${NC}"
cd "$TEMP_DIR"
zip -r -q "$SCRIPT_DIR/$ZIP_PATH" Pockets/ \
    -x "*.DS_Store" \
    -x "*__MACOSX*" \
    -x "*.git*" \
    -x "*.swp" \
    -x "*~" \
    -x "*.bak"

# Clean up temporary directory
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

# Release notes: the FEATURES.md section for this version, or "Unreleased"
# when the version hasn't been named yet (a warning is printed).
NOTES_PATH="${RELEASES_DIR}/pockets-${VERSION}-notes.md"
extract_section() {
    awk -v want="$1" '
        /^## / { on = ($0 == "## " want); next }
        on { print }
    ' FEATURES.md | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed '/./,$!d'
}
NOTES=""
NOTES_SECTION=""
if [ -f FEATURES.md ]; then
    NOTES=$(extract_section "$VERSION")
    NOTES_SECTION="$VERSION"
    if [ -z "$NOTES" ]; then
        NOTES=$(extract_section "Unreleased")
        NOTES_SECTION="Unreleased"
    fi
fi
if [ -n "$NOTES" ]; then
    printf '# Pockets %s\n\n%s\n' "$VERSION" "$NOTES" > "$NOTES_PATH"
    echo -e "${GREEN}✓ Release notes written from FEATURES.md (${NOTES_SECTION})${NC}"
    if [ "$NOTES_SECTION" = "Unreleased" ]; then
        echo -e "${RED}Note: no '## ${VERSION}' section in FEATURES.md - used 'Unreleased'. Rename it to '${VERSION}' when you release.${NC}"
    fi
else
    rm -f "$NOTES_PATH"
    echo -e "${RED}Warning: no release notes found in FEATURES.md for ${VERSION} or Unreleased${NC}"
fi

# Get file size for display
SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')

echo -e "${GREEN}✓ Successfully created ${ZIP_NAME} (${SIZE})${NC}"
echo -e "${BLUE}Location: ${ZIP_PATH}${NC}"
if [ -f "$NOTES_PATH" ]; then
    echo -e "${BLUE}Notes: ${NOTES_PATH}${NC}"
fi
