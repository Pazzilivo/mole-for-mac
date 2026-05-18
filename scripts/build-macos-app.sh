#!/bin/bash
# Build the native macOS wrapper and bundle Mole's CLI runtime into the app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SRC="$PROJECT_ROOT/macos/MoleApp"
SWIFT_SRC="$APP_SRC/Sources/MoleApp"
APP_RESOURCES="$APP_SRC/Resources"
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

copy_tracked_tree() {
    local src_dir="$1"
    local dst_dir="$2"

    mkdir -p "$dst_dir"
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        while IFS= read -r -d '' rel; do
            local rel_dst="${rel#"$src_dir"/}"
            copy_path "$PROJECT_ROOT/$rel" "$dst_dir/$rel_dst"
        done < <(git -C "$PROJECT_ROOT" ls-files -z -- "$src_dir")
    else
        copy_path "$PROJECT_ROOT/$src_dir" "$dst_dir"
    fi
}

require swiftc
require xcrun
require plutil
require ditto

cd "$PROJECT_ROOT"

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

MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
HOST_ARCH="$(uname -m)"
SWIFT_TARGET="${MOLE_SWIFT_TARGET:-${HOST_ARCH}-apple-macosx${MACOS_DEPLOYMENT_TARGET}}"

log "Using Swift target $SWIFT_TARGET"
swiftc \
    -parse-as-library \
    -O \
    -sdk "$SDKROOT" \
    -target "$SWIFT_TARGET" \
    "${swift_sources[@]}" \
    -o "$MACOS_DIR/Mole"

log "Copying app metadata..."
copy_path "$APP_SRC/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -x /usr/libexec/PlistBuddy ]]; then
    /usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MACOS_DEPLOYMENT_TARGET" "$CONTENTS_DIR/Info.plist"
fi
plutil -lint "$CONTENTS_DIR/Info.plist" > /dev/null

log "Copying app icon..."
copy_path "$APP_RESOURCES/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

log "Bundling Mole runtime..."
copy_path "$PROJECT_ROOT/mole" "$RUNTIME_DIR/mole"
copy_path "$PROJECT_ROOT/mo" "$RUNTIME_DIR/mo"
copy_tracked_tree "bin" "$RUNTIME_DIR/bin"
copy_tracked_tree "lib" "$RUNTIME_DIR/lib"
copy_path "$PROJECT_ROOT/LICENSE" "$RUNTIME_DIR/LICENSE"
copy_path "$PROJECT_ROOT/README.md" "$RUNTIME_DIR/README.md"

chmod +x "$MACOS_DIR/Mole"
chmod +x "$RUNTIME_DIR/mole" "$RUNTIME_DIR/mo"
find "$RUNTIME_DIR/bin" -type f -name '*.sh' -exec chmod +x {} +

if command -v codesign > /dev/null 2>&1; then
    log "Applying local ad-hoc signature..."
    codesign --force --deep --sign - "$APP_DIR" > /dev/null
fi

log "Created $APP_DIR"
