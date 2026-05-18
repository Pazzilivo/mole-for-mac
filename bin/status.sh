#!/bin/bash
# Mole - Status command.
# Shows system metrics with a native fallback.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/status-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

host_name="$(scutil --get ComputerName 2> /dev/null || hostname)"
os_version="$(sw_vers -productName 2> /dev/null) $(sw_vers -productVersion 2> /dev/null)"
kernel="$(uname -m)"
uptime_text="$(uptime | sed 's/^.* up //; s/, [0-9][0-9]* users.*$//; s/, [0-9][0-9]* user.*$//')"
load_avg="$(sysctl -n vm.loadavg 2> /dev/null | tr -d '{}')"
disk_root="$(df -h / 2> /dev/null | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}')"
memory_pressure="$(memory_pressure 2> /dev/null | awk -F': ' '/System-wide memory free percentage/ {print $2; exit}')"

printf 'Mole Status\n'
printf '%s\n' '-----------'
printf 'Host:   %s\n' "${host_name:-Unknown}"
printf 'OS:     %s\n' "${os_version:-Unknown}"
printf 'Arch:   %s\n' "${kernel:-Unknown}"
printf 'Uptime: %s\n' "${uptime_text:-Unknown}"
printf 'Load:   %s\n' "${load_avg:-Unknown}"
printf 'Disk:   %s\n' "${disk_root:-Unknown}"
if [[ -n "${memory_pressure:-}" ]]; then
    printf 'Memory: %s free\n' "$memory_pressure"
fi
