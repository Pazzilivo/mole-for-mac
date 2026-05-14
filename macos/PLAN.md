# macOS App Plan

## Product Shape

Mole Desktop is a native utility workspace, not a marketing surface. The app
opens directly into system status and actionable maintenance work. Every
destructive flow follows the same pattern:

1. Scan
2. Preview
3. Review risk and selection
4. Apply
5. Show result and audit log

The CLI remains the engine. SwiftUI owns navigation, presentation, selection,
permission guidance, and progress display.

## Main Navigation

The app should use a left sidebar with these primary areas:

- Overview
- Clean
- Uninstall
- Analyze
- Optimize
- Artifacts
- Logs
- Settings

`Artifacts` groups project build artifacts and installer cleanup because both
are file-selection cleanup flows rather than whole-system maintenance.

## Screens

### 1. Overview

Purpose: show current Mac health and the next useful actions.

Data sources:

- `mole status --json`
- last operation log summary from `~/Library/Logs/mole/operations.log`
- optional cleanup/analyze cache when structured scan APIs exist

UI:

- health score, CPU, memory, disk, battery, and top processes
- primary disk usage and Trash size
- last cleanup result and last scan time
- warning area for missing Full Disk Access, missing bundled Go binaries, or
  unavailable sudo helper
- quick actions: Scan Cleanup, Analyze Disk, Review Apps, Optimize

Behavior:

- refreshes status on launch and on manual refresh
- never performs destructive actions from this screen
- quick actions navigate to the relevant screen and start a scan only when safe

MVP status: implemented as the launch screen with `status --json`, runtime
warnings, and quick navigation actions.

### 2. Clean

Purpose: preview and apply deep cleanup for caches, logs, browser leftovers,
developer caches, app leftovers, and safe system maintenance targets.

Required CLI/API work:

- `mole clean --plan-json`
- `mole clean --apply-plan <plan-file>`
- NDJSON progress events during apply

UI:

- grouped cleanup categories with size, item count, and risk level
- expandable file list per category
- whitelist indicators and one-click protect action
- dry-run summary before enabling the apply button
- apply progress with current path, completed categories, skipped items, and
  permission failures

Safety:

- default to preview only
- require explicit confirmation for high-risk categories
- show Full Disk Access guidance when scan misses protected locations
- keep shell-side `validate_path_for_deletion` as the final gate

MVP status: screen scaffold implemented; pending structured JSON API.

### 3. Uninstall

Purpose: list installed apps, preview leftovers, and remove selected apps plus
related files.

Data sources:

- `mole uninstall --list` for installed app inventory

Required CLI/API work:

- `mole uninstall --plan-json <uninstall-name>`
- `mole uninstall --apply-plan <plan-file>`
- optional `mole uninstall --trash-only` default surfaced in plan metadata

UI:

- searchable app table with name, bundle ID, source, size, and last-used hint
- app detail inspector with app path, cask name, bundle ID, and related files
- leftover groups: application, preferences, caches, containers, launch items,
  receipts, logs
- clear distinction between Trash move and permanent delete

Safety:

- default deletion mode is Trash
- app removal requires a per-app confirmation screen
- protected system apps are visible as blocked, not silently hidden
- permanent delete is an advanced option

MVP status: app listing implemented; destructive preview pending.

### 4. Analyze

Purpose: inspect disk usage and reveal large files before cleanup.

Data sources:

- `mole analyze --json <path>`

UI:

- path picker for Home, Downloads, Applications, external volume, or custom
  directory
- sortable table/tree with name, path, size, type, and last access where
  available
- large files section
- actions: Reveal in Finder, Open, Move to Trash

Safety:

- delete action moves to Trash through Finder behavior
- delete requires explicit selection confirmation
- no sudo in analyzer

MVP status: Home analysis table implemented when `analyze-go` is bundled.

### 5. Optimize

Purpose: apply system refresh and repair tasks such as DNS refresh,
LaunchServices rebuild, Finder/Dock refresh, SQLite vacuum, and diagnostics.

Data sources:

- `lib/check/health_json.sh` currently feeds `bin/optimize.sh`

Required CLI/API work:

- `mole optimize --apply-plan <plan-file>`
- structured task result events

UI:

- task list with title, description, sudo requirement, and whitelist status
- system health header: memory, disk, uptime
- dry-run result summary
- per-task progress and final status

Safety:

- whitelisted tasks stay disabled by default
- sudo-required tasks are grouped and explained before authentication
- failed privileged tasks are skipped, not retried in loops

MVP status: `mole optimize --plan-json` and read-only plan viewing implemented;
apply-plan and progress events are pending.

### 6. Artifacts

Purpose: clean project build artifacts and installer files.

Subsections:

- Project Artifacts
- Installer Files

Project Artifacts data/API:

- `mole purge --list-json`
- `mole purge --apply-plan <plan-file>`
- settings link for purge scan paths

Installer data/API:

- `mole installer --list-json`
- `mole installer --apply-plan <plan-file>`

UI:

- segmented control between Project Artifacts and Installer Files
- table with name, path, type/source, size, age, selected state
- recent project warning and default unselected state
- path configuration panel for project scan roots

Safety:

- recent project artifacts default off
- nested parent/child selections are deduplicated before apply
- installer cleanup should prefer Trash where practical

MVP status: screen scaffold implemented; pending structured JSON APIs.

### 7. Logs

Purpose: make destructive operations auditable and recoverable.

Data sources:

- `~/Library/Logs/mole/operations.log`
- `~/Library/Logs/mole/deletions.log`
- command stderr/stdout captured by the app session

UI:

- recent operations table with command, status, item count, size, timestamp
- deletion log table with mode, path, size, and result
- filters for clean, uninstall, purge, installer, optimize
- copy diagnostic bundle action

Safety:

- expose warnings for missing audit logs
- never mutate logs from this screen except user-triggered export

MVP status: implemented for read-only operations and deletions log viewing.

### 8. Settings

Purpose: configure runtime, CLI access, privacy guidance, and update behavior.

UI:

- bundled runtime path
- install `mo` shim into `~/.local/bin`
- Full Disk Access instructions and detection
- cleanup whitelist editor
- optimize whitelist editor
- purge scan path editor
- update channel and app version
- advanced diagnostics: verify bundled runtime, run `mole --version`

Safety:

- writing to `/usr/local/bin` is not a default path
- user-level CLI shim is preferred
- privileged helper status is visible but installed only after explicit consent

MVP status: runtime path, runtime diagnostics, and user-level CLI shim
implemented.

## UI Principles

- Dense, readable, utility-first layout.
- No landing page.
- No destructive action without a preview.
- Cards only for repeated items or bounded tools, not page sections.
- Tables and inspectors are preferred for file/app selection.
- Long-running commands must stream progress.
- Every skipped item should have a reason.
- Every destructive result should be traceable to an operation log.

## Phase 1: Thin App Shell

- Add a SwiftUI macOS app target that can be built without relying on a global
  `mo` installation.
- Bundle the existing CLI runtime into
  `Mole.app/Contents/Resources/MoleRuntime`.
- Call the bundled `mole` entrypoint from Swift with `Process`.
- Surface read-only status, analysis, and application listing views first.

Status: in progress. Overview, Clean scaffold, Uninstall listing, Analyze,
Optimize scaffold, Artifacts scaffold, Logs, Settings, and runtime bundling
have initial implementations.

## Phase 2: Structured Command API

- Add JSON plan commands for cleanup, purge, installer cleanup, and uninstall.
- Add apply commands that accept stable IDs or a generated plan file.
- Emit NDJSON progress events for long-running tasks.
- Keep destructive shell helpers as the final safety gate.

Status: pending.

## Phase 3: Privileges and Privacy

- Replace ad-hoc GUI sudo prompting with a proper privileged helper for bounded
  root-only operations.
- Add Full Disk Access guidance and detection.
- Keep Trash-first behavior for recoverable user-level deletion.
- Preserve operation and deletion audit logs.

Status: pending.

## Phase 4: Distribution

- Sign all app and helper executables with Developer ID.
- Enable Hardened Runtime.
- Notarize and staple the app or DMG.
- Add update flow for the app bundle without relying on Homebrew.

Status: pending.
