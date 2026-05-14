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

If Go is available, the script runs `make build` first so `bin/analyze-go` and
`bin/status-go` are included. Without Go, the app still builds, but status and
disk analysis views will report that the bundled Go binaries are missing.

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

