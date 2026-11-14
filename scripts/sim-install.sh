#!/usr/bin/env bash
# DEV ONLY. Installs the wow-ui-sim (Forever, macOS arm64) outside the repo.
# Not called by lint/test/build/release. Never vendor or ship this binary (GPL-3.0).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SIM_VERSION="0.1.40"
SIM_SHA256="91a03d06d88144e7fa497062b188cbbaf1fc7f245a29e92223cd55627d954668"
SIM_HOME="${WOW_SIM_HOME:-$HOME/tools/wow-ui-sim}"
DMG="wow-ui-sim-v${SIM_VERSION}-forever-macos-aarch64.dmg"
URL="https://github.com/Osso/wow-ui-sim/releases/download/v${SIM_VERSION}/${DMG}"
BIN="$SIM_HOME/app/Contents/MacOS/wow-sim"

[ "$(uname -s)-$(uname -m)" = "Darwin-arm64" ] || die "macOS arm64 only"
case "$SIM_HOME" in "$REPO_ROOT"*) die "SIM_HOME must be outside the repo";; esac

if [ -x "$BIN" ] && [ "$(cat "$SIM_HOME/VERSION" 2>/dev/null)" = "$SIM_VERSION" ]; then
    ok "wow-sim $SIM_VERSION already installed: $BIN"; exit 0
fi

mkdir -p "$SIM_HOME/dl"
if [ ! -f "$SIM_HOME/dl/$DMG" ]; then
    info "Downloading $DMG"
    curl -fsSL -o "$SIM_HOME/dl/$DMG" "$URL"
fi
echo "$SIM_SHA256  $SIM_HOME/dl/$DMG" | shasum -a 256 -c - >/dev/null || die "checksum mismatch"

MNT="$(mktemp -d)"
trap 'hdiutil detach "$MNT" >/dev/null 2>&1 || true' EXIT
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$SIM_HOME/dl/$DMG" >/dev/null 2>&1
rm -rf "$SIM_HOME/app"
cp -R "$MNT"/*.app "$SIM_HOME/app"
xattr -cr "$SIM_HOME/app"
echo "$SIM_VERSION" > "$SIM_HOME/VERSION"
ok "Installed wow-sim $SIM_VERSION: $BIN"
