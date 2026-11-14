#!/bin/bash
# Install the optional HMF_API_Lab addon to detected WoW AddOns dirs.
# Forever only by default. Usage: ./install-lab.sh [AddOns path]
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/hmf-api-lab"
if [ -n "$1" ]; then DIRS=("$1"); else
  DIRS=()
  for p in "/Applications/World of Warcraft/_forever_/Interface/AddOns" "$HOME/Applications/World of Warcraft/_forever_/Interface/AddOns"; do
    [ -d "$p" ] && DIRS+=("$p")
  done
fi
[ ${#DIRS[@]} -gt 0 ] || { echo "No Forever AddOns dir found"; exit 1; }
for d in "${DIRS[@]}"; do
  rm -rf "$d/HMF_API_Lab"; mkdir -p "$d/HMF_API_Lab"
  cp -R "$SRC/." "$d/HMF_API_Lab/"
  echo "Installed HMF_API_Lab -> $d"
done
