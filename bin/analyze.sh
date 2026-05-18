#!/bin/bash
# Mole - Analyze command.
# Shows disk usage with a native fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/analyze-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

target="${1:-$HOME}"
if [[ ! -d "$target" ]]; then
    printf 'Analyze target is not a directory: %s\n' "$target" >&2
    exit 2
fi

printf 'Mole Analyze\n'
printf '%s\n' '------------'
printf 'Target: %s\n\n' "$target"
printf 'Largest direct children:\n'
du -xhd 1 "$target" 2> /dev/null | sort -hr | head -20
