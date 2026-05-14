#!/bin/bash
# Build the native macOS wrapper and bundle Mole's CLI runtime into the app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_ROOT/macos/MoleApp"
SWIFT_SRC="$APP_SRC/Sources/MoleApp"
BUILD_DIR="${MOLE_MACOS_BUILD_DIR:-$PROJECT_ROOT/build/macos}"
APP_DIR="$BUILD_DIR/Mole.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_DIR="$RESOURCES_DIR/MoleRuntime"

log() {
    printf '%s\n' "$*"
}

require() {
    if ! command -v "$1" > /dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$1" >&2
        exit 1
    fi
}

copy_path() {
    local src="$1"
    local dst="$2"
    if [[ -d "$src" ]]; then
        /usr/bin/ditto "$src" "$dst"
    else
        mkdir -p "$(dirname "$dst")"
        /usr/bin/ditto "$src" "$dst"
    fi
}

require swiftc
require plutil
require ditto

cd "$PROJECT_ROOT"

if command -v go > /dev/null 2>&1; then
    log "Building Go helper binaries..."
    make build
else
    log "Go was not found; building the app without analyze-go/status-go."
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$RUNTIME_DIR"

log "Compiling SwiftUI app..."
swift_sources=()
while IFS= read -r file; do
    swift_sources+=("$file")
done < <(find "$SWIFT_SRC" -type f -name '*.swift' | sort)

if [[ ${#swift_sources[@]} -eq 0 ]]; then
    printf 'No Swift sources found in %s\n' "$SWIFT_SRC" >&2
    exit 1
fi

swiftc -parse-as-library -O "${swift_sources[@]}" -o "$MACOS_DIR/Mole"

log "Copying app metadata..."
copy_path "$APP_SRC/Info.plist" "$CONTENTS_DIR/Info.plist"
plutil -lint "$CONTENTS_DIR/Info.plist" > /dev/null

log "Bundling Mole runtime..."
copy_path "$PROJECT_ROOT/mole" "$RUNTIME_DIR/mole"
copy_path "$PROJECT_ROOT/mo" "$RUNTIME_DIR/mo"
copy_path "$PROJECT_ROOT/bin" "$RUNTIME_DIR/bin"
copy_path "$PROJECT_ROOT/lib" "$RUNTIME_DIR/lib"
copy_path "$PROJECT_ROOT/LICENSE" "$RUNTIME_DIR/LICENSE"
copy_path "$PROJECT_ROOT/README.md" "$RUNTIME_DIR/README.md"

chmod +x "$MACOS_DIR/Mole"
chmod +x "$RUNTIME_DIR/mole" "$RUNTIME_DIR/mo"
find "$RUNTIME_DIR/bin" -type f -name '*.sh' -exec chmod +x {} +
find "$RUNTIME_DIR/bin" -type f \( -name '*-go' -o -name '*-darwin-*' \) -exec chmod +x {} + 2> /dev/null || true

if command -v codesign > /dev/null 2>&1; then
    log "Applying local ad-hoc signature..."
    codesign --force --deep --sign - "$APP_DIR" > /dev/null
fi

log "Created $APP_DIR"
