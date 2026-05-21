#!/bin/bash
# Build and package the native macOS wrapper for GitHub Releases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Mole"
BUILD_DIR="${MOLE_MACOS_BUILD_DIR:-$PROJECT_ROOT/build/macos}"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$PROJECT_ROOT/dist"
ZIP_PATH="$DIST_DIR/$APP_NAME.app.zip"

require() {
    if ! command -v "$1" > /dev/null 2>&1; then
        printf 'Missing required tool: %s\n' "$1" >&2
        exit 1
    fi
}

require ditto
require shasum

cd "$PROJECT_ROOT"

"$PROJECT_ROOT/scripts/build-macos-app.sh"

if [[ ! -d "$APP_DIR" ]]; then
    printf 'Expected app bundle was not created: %s\n' "$APP_DIR" >&2
    exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$ZIP_PATH"

(
    cd "$DIST_DIR"
    shasum -a 256 "$APP_NAME.app.zip" > "$APP_NAME.app.zip.sha256"
)

printf '%s\n' "$ZIP_PATH"
