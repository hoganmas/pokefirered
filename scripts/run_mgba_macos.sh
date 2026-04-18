#!/usr/bin/env bash
# Launch mGBA on macOS with a ROM and one or more Lua scripts.
#
# Usage:
#   ./scripts/run_mgba_macos.sh <rom.gba> <script.lua> [script2.lua ...]
#   MGBA=/path/to/mGBA ./scripts/run_mgba_macos.sh ...
#
# mGBA expects options before the ROM file; --script is applied before the ROM path.
# Requires: mGBA installed under /Applications/mGBA.app (override with MGBA=).

set -euo pipefail

MGBA_BIN="${MGBA:-/Applications/mGBA.app/Contents/MacOS/mGBA}"

if [[ ! -x "$MGBA_BIN" ]]; then
  echo "mGBA not found or not executable: $MGBA_BIN" >&2
  echo "Install mGBA to Applications or set MGBA=/path/to/mGBA" >&2
  exit 1
fi

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <rom.gba> <script.lua> [more_scripts.lua ...]" >&2
  echo "example: $0 pokefirered.gba scripts/reserved_species_mailbox.lua" >&2
  exit 1
fi

ROM="$1"
shift

if [[ ! -f "$ROM" ]]; then
  echo "ROM not found: $ROM" >&2
  exit 1
fi

SCRIPT_ARGS=()
for script in "$@"; do
  if [[ ! -f "$script" ]]; then
    echo "Script not found: $script" >&2
    exit 1
  fi
  SCRIPT_ARGS+=(--script "$script")
done

exec "$MGBA_BIN" "${SCRIPT_ARGS[@]}" "$ROM"
