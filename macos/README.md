# Mole macOS App

This directory contains the native macOS wrapper for Mole.

The first version is intentionally thin:

- The app does not require a separately installed `mo` command.
- The bundled CLI runtime lives at `Mole.app/Contents/Resources/MoleRuntime`.
- SwiftUI calls the bundled `mole` entrypoint with `Process`.
- Existing shell safety checks and Go JSON outputs remain the source of truth.

## Build

```bash
./scripts/build-macos-app.sh
```

The script creates:

```text
build/macos/Mole.app
```

The app icon source lives at `macos/MoleApp/Resources/AppIcon.svg`. Regenerate
the bundled `.icns` after icon changes with:

```bash
./scripts/generate-macos-icon.sh
```

If Go is available, the script runs `make build` first so `bin/analyze-go` and
`bin/status-go` are included. Without Go, the app still builds, but status and
disk analysis views will report that the bundled Go binaries are missing.

## Package

```bash
./scripts/package-macos-app.sh
```

The release package is written to:

```text
dist/Mole.app.zip
dist/Mole.app.zip.sha256
```

The archive keeps `Mole.app` as the top-level item so the built-in updater can
extract and replace the current app.

## Release

Formal releases are produced by `.github/workflows/release.yml` when a `v*` or
`V*` tag is pushed to `Pazzilivo/mole-for-mac`. The workflow stamps the app
version from the tag, packages the native app, verifies the archive, and creates
the macOS app GitHub Release.

The app updater reads the static manifest at:
`https://github.com/Pazzilivo/mole-for-mac/releases/latest/download/latest.json`

The manifest contains:

```json
{
  "version": "1.38.1",
  "tag": "v1.38.1",
  "asset": "Mole-1.38.1.zip",
  "sha256": "<hex digest>",
  "notes": "<release notes>"
}
```

The workflow publishes versioned app assets matching the existing
updater-compatible names:

```text
Mole-<version>.zip
Mole-<tag>.zip
latest.json
```

The legacy `macos-app-release.yml` workflow is disabled to avoid conflicts.

Local preflight:

```bash
git status --short --branch
make verify
./scripts/package-macos-app.sh
unzip -t dist/Mole.app.zip
```

## Architecture

```text
Mole.app
  Contents/
    MacOS/Mole                 SwiftUI app executable
    Info.plist
    Resources/
      MoleRuntime/
        mole                   CLI router
        mo                     CLI alias
        bin/
        lib/
```

Future production work should add structured JSON plan/apply commands for
cleanup, purge, installer cleanup, and uninstall previews before exposing those
destructive actions in the GUI.

