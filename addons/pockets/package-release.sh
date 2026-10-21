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

# Get file size for display
SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')

echo -e "${GREEN}✓ Successfully created ${ZIP_NAME} (${SIZE})${NC}"
echo -e "${BLUE}Location: ${ZIP_PATH}${NC}"
