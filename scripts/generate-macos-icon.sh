#!/bin/bash
# Generate the macOS .iconset and .icns from the source SVG.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PROJECT_ROOT/macos/MoleApp/Resources"
SOURCE_SVG="$RESOURCES_DIR/AppIcon.svg"
ICNS_PATH="$RESOURCES_DIR/AppIcon.icns"

require() {
    if ! command -v "$1" > /dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$1" >&2
        exit 1
    fi
}

require iconutil
require qlmanage
require sips

if [[ ! -f "$SOURCE_SVG" ]]; then
    printf 'Missing source icon: %s\n' "$SOURCE_SVG" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
ICONSET_DIR="$tmp_dir/AppIcon.iconset"

mkdir -p "$ICONSET_DIR"

qlmanage -t -s 1024 -o "$tmp_dir" "$SOURCE_SVG" > /dev/null 2>&1
master_png="$tmp_dir/$(basename "$SOURCE_SVG").png"
if [[ ! -f "$master_png" ]]; then
    master_png="$(find "$tmp_dir" -type f -name '*.png' -print -quit)"
fi

if [[ -z "${master_png:-}" || ! -f "$master_png" ]]; then
    printf 'Failed to render %s to PNG\n' "$SOURCE_SVG" >&2
    exit 1
fi

make_icon() {
    local size="$1"
    local filename="$2"
    sips -z "$size" "$size" "$master_png" --out "$ICONSET_DIR/$filename" > /dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
printf 'Generated %s\n' "$ICNS_PATH"
