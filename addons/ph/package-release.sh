#!/bin/bash

# pH Addon Release Packaging Script
# Packages all required lua and resource files into a versioned zip file

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Extract version from ph.toc
TOC_FILE="ph/ph.toc"
if [ ! -f "$TOC_FILE" ]; then
    echo -e "${RED}Error: ph.toc not found at $TOC_FILE${NC}"
    exit 1
fi

VERSION=$(grep "^## Version:" "$TOC_FILE" | sed 's/## Version: //')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from ph.toc${NC}"
    exit 1
fi

echo -e "${BLUE}Packaging pH version ${GREEN}${VERSION}${NC}"

# Create releases directory if it doesn't exist
RELEASES_DIR="releases"
mkdir -p "$RELEASES_DIR"

# Define output zip filename
ZIP_NAME="ph-${VERSION}.zip"
ZIP_PATH="${RELEASES_DIR}/${ZIP_NAME}"

# Remove old zip if it exists
if [ -f "$ZIP_PATH" ]; then
    echo -e "${BLUE}Removing existing ${ZIP_NAME}${NC}"
    rm "$ZIP_PATH"
fi

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
TARGET_DIR="${TEMP_DIR}/ph"
mkdir -p "$TARGET_DIR"

echo -e "${BLUE}Copying files to temporary directory...${NC}"

# Copy all .lua files
cp ph/*.lua "$TARGET_DIR/"

# Copy .toc file
cp ph/ph.toc "$TARGET_DIR/"

# Copy logo image
cp ph/logo-256.jpg "$TARGET_DIR/"

# Create the zip file (cd into temp dir so zip contains ph/ folder structure)
echo -e "${BLUE}Creating ${ZIP_NAME}...${NC}"
cd "$TEMP_DIR"
zip -r -q "$SCRIPT_DIR/$ZIP_PATH" ph/ \
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
if [[ "$OSTYPE" == "darwin"* ]]; then
    SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
else
    SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
fi

echo -e "${GREEN}✓ Successfully created ${ZIP_NAME} (${SIZE})${NC}"
echo -e "${BLUE}Location: ${ZIP_PATH}${NC}"
