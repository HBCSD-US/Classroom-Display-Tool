# HBCSD Classroom Display Tool

A local macOS utility for classroom MacBooks that lets teachers switch between
safe display presets without opening raw Terminal commands or manually
rebuilding display layouts in System Settings.

The tool supports Apple Silicon and Intel Macs and bundles the required
`displayplacer` binaries inside the app package.

## What It Does

- Shows connected classroom displays in a visual native macOS app.
- Offers the relevant presets for the current display topology.
- Hides unavailable or duplicate options, such as `Extend All Displays` when
  only two displays are connected.
- Refreshes when displays are connected, disconnected, or when the app becomes
  active.
- Logs display detection and apply results for IT troubleshooting.

## Teacher Presets

- `Mirror Everything`: mirrors detected displays and prefers an external
  classroom display as the mirror source when possible.
- `Teacher Private Mode`: keeps the built-in MacBook display private while
  classroom-facing displays show shared content.
- `Extend All Displays`: keeps all displays separate when three or more
  displays are connected.

## Repository Layout

- `Sources/ClassroomDisplayToolApp/main.swift`: native macOS app.
- `Sources/ClassroomDisplayToolApp/Resources/display_backend.sh`: internal app
  backend for display detection, preset planning, and `displayplacer` commands.
- `build_distribution.sh`: builds the app bundle, no-admin zip, and installer
  package.
- `assets/`: app icon and visual preset cards.
- `bin/`: bundled `displayplacer` binaries for Apple Silicon and Intel Macs.
- `diagrams/`: source and preview files for the display utility flow diagram.
- `README_DEPLOYMENT.md`: teacher usage, logging, and build notes.
- `USER_TEST_STEPS.md`: checklist for classroom validation.
- `THIRD_PARTY_NOTICES.md`: bundled dependency license notices.

## Build

Run from the repository root:

```sh
./build_distribution.sh
```

The build script creates local artifacts in `dist/`:

- `HBCSD-Classroom-Display-Tool.zip`
- `HBCSD-Classroom-Display-Tool-<version>.pkg`

`dist/` is intentionally ignored by git. Rebuild artifacts locally or attach
them to a GitHub release when they are ready for distribution.

## Distribution Notes

Use `README_DEPLOYMENT.md` for the current deployment and teacher-facing usage
details. Use `USER_TEST_STEPS.md` when validating a new package with staff or a
classroom.
