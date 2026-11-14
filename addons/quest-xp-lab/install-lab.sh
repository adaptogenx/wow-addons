#!/bin/bash
# Install the optional QuestXPLab addon to detected WoW AddOns dirs.
# Forever only by default. Usage: ./install-lab.sh [AddOns path]
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/QuestXPLab"
if [ -n "$1" ]; then DIRS=("$1"); else
  DIRS=()
  for p in "/Applications/World of Warcraft/_forever_/Interface/AddOns" "$HOME/Applications/World of Warcraft/_forever_/Interface/AddOns"; do
    [ -d "$p" ] && DIRS+=("$p")
  done
fi
[ ${#DIRS[@]} -gt 0 ] || { echo "No Forever AddOns dir found"; exit 1; }
for d in "${DIRS[@]}"; do
  rm -rf "$d/QuestXPLab"; mkdir -p "$d/QuestXPLab"
  cp -R "$SRC/." "$d/QuestXPLab/"
  echo "Installed QuestXPLab -> $d"
done
