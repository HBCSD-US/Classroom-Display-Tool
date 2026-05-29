# HBCSD Classroom Display Tool

This lightweight local macOS utility helps teachers choose a classroom display
preset from a visual native app without opening System Settings or running raw
Terminal commands.

Homebrew is not required. The package includes `displayplacer` binaries for
Apple Silicon and Intel Macs.

## Teacher Use

Open `HBCSD Classroom Display Tool.app`, then choose one of the available visual
display modes:

- `Mirror Everything`: all detected displays show the same content.
- `Teacher Private Mode`: the built-in MacBook display stays private, and
  classroom-facing displays show shared content.
- `Extend All Displays`: all displays are separate, with the built-in display
  as main when possible.

The app applies a mode as soon as the teacher selects a card. The selected card
stays highlighted with an `ACTIVE NOW` badge, and the app remains open so the
teacher can switch modes again before closing the window.

The top of the app lists the currently connected external displays. The
display list and available mode cards refresh automatically when macOS reports
that displays were connected or disconnected, and they refresh again when the
app becomes active. The `Refresh` button manually re-scans displays if a
classroom cable, projector, or Apple TV takes longer to settle. The `Display
Settings` shortcut opens macOS Display Settings for additional manual display
changes.

If only one display is connected, the app shows a helpful message and does not
offer display mode cards.

## Expected Preset Behavior

With 2 displays:

- Mirror Everything mirrors built-in + external and uses the best external
  classroom display as the mirror source when available.
- Teacher Private Mode keeps built-in main/private and external extended.
- Extend All Displays is hidden because it duplicates Teacher Private Mode in
  two-display classroom setups.
- If the external display is disconnected while the app is open, the app
  refreshes to the one-display message and removes the mode cards.

With 3 displays:

- Mirror Everything mirrors all 3 and avoids using the built-in Mac display as
  the classroom source when an external display is available.
- Teacher Private Mode keeps built-in private and mirrors the classroom displays.
- Extend All Displays keeps all displays separate.
- If one classroom display is disconnected while the app is open, the app
  refreshes to the two-display preset list and hides Extend All Displays.

## Smart Display Detection

Before applying a preset, the app scans the active displays with the bundled
`displayplacer` backend and `system_profiler`, then logs a normalized inventory.
The inventory includes display names, IDs, built-in/external classification,
current resolution, dimensions, aspect ratio, close-to-16:9 status, current main
display state, and available modes when `displayplacer` reports them. The log
also records the mirror resolution/scaling candidate used for Mirror Everything.

For classroom output, the tool ranks source displays by preferring external
displays, then close-to-16:9 displays, then larger resolutions, with a stable
deterministic order when displays are otherwise similar. In Mirror Everything,
the selected classroom display is placed first in the `displayplacer` mirror
group so macOS optimizes the mirror set for that display instead of the
MacBook's built-in aspect ratio. The mirror command also carries the selected
source display resolution and scaling mode together, preferring non-scaled
external display modes when available so macOS does not fall back to a mismatched
HiDPI/scaled mirror resolution.

## Logging

IT troubleshooting logs are written to:

```text
~/Library/Logs/HBCSD Display Mirror/display-config.log
```

The log includes detected displays, aspect ratios, selected preset, classroom
source choice, planned mirror resolution/scaling, generated displayplacer
commands, errors, fallback behavior, and post-apply verification output.

AirPlay displays are treated as external classroom displays even if
`displayplacer` reports a MacBook-style screen type. When display ordering
differs between `displayplacer` and `system_profiler`, the tool matches the
built-in panel by internal connection and matches AirPlay/other classroom
screens as external displays before planning presets.

## Build Test Artifacts

Run:

```sh
./build_distribution.sh
```

This creates:

- `dist/HBCSD-Classroom-Display-Tool.zip`
- `dist/HBCSD-Classroom-Display-Tool-2.8.pkg`

Use the zip for a quick no-admin launch. Use the package when you want a cleaner
install into `/Applications/HBCSD Classroom Display Tool.app`.
