# HBCSD Classroom Display Tool Test Steps

Use this when asking a teacher or staff member to test the display preset
utility before or after installing it.

## Option 1: No-Admin Test from Zip

1. Download or receive `HBCSD-Classroom-Display-Tool.zip`.
2. Double-click the zip file to extract it.
3. Double-click `HBCSD Classroom Display Tool.app`.
4. If macOS blocks it, right-click `HBCSD Classroom Display Tool.app`, choose
   `Open`, then choose `Open` again.
5. Confirm the connected external display names appear near the top of the app.
6. Click `Refresh` and confirm the app still shows the correct connected
   external display names.
7. Click `Display Settings` and confirm macOS Display Settings opens.
8. Choose one of the visual display mode cards.
9. Confirm the card gets a light blue background, blue outline, and `ACTIVE NOW`
   badge, and the displays changed as expected.
10. Close the app using the normal macOS window controls.

## Option 2: Installer Package Test

1. Download or receive `HBCSD-Classroom-Display-Tool-2.8.pkg`.
2. Double-click the package.
3. Follow the installer prompts.
4. Open `/Applications/HBCSD Classroom Display Tool.app`.
5. Confirm the connected external display names appear near the top of the app.
6. Click `Refresh` and confirm the app still shows the correct connected
   external display names.
7. Click `Display Settings` and confirm macOS Display Settings opens.
8. Choose one of the visual display mode cards.
9. Confirm the card gets a light blue background, blue outline, and `ACTIVE NOW`
   badge, and the displays changed as expected.
10. Close the app using the normal macOS window controls.

## Manual Test Cases

### 1 Display Only

1. Disconnect classroom displays.
2. Open `HBCSD Classroom Display Tool.app`.
3. Confirm the app says only one display is connected.
4. Confirm no display mode cards are shown and no display change is attempted.
5. Click `Refresh` and confirm the app still shows no display mode cards.

### 2 Displays: Built-In + One External

1. Connect one projector, HDMI display, or Apple TV display.
2. Open `HBCSD Classroom Display Tool.app`.
3. Test each available preset:
   - Mirror Everything: both displays show the same content, with the external
     classroom display used as the mirror source/main display when possible.
   - Teacher Private Mode: built-in stays private/main, external is extended.
   - Extend All Displays: not shown with only two displays.
4. Confirm each selected card gets a light blue background, blue outline, and
   `ACTIVE NOW` badge, and the app remains open after the display mode changes.
5. After Mirror Everything, open macOS Display Settings and confirm the external
   display is optimized/primary and its resolution is selected, not left in an
   unset or visually mismatched scaled state.
6. While the app is still open, disconnect the external display.
7. Confirm the app automatically refreshes to the one-display message, removes
   the mode cards, and clears any stale `ACTIVE NOW` badge.
8. Reconnect the external display and confirm the app automatically returns to
   the two-display preset list. If macOS is slow to report the display, click
   `Refresh` and confirm the same result.

### 2 Displays: Built-In + Apple TV/AirPlay

1. Connect to the Apple TV/AirPlay classroom display.
2. Open `HBCSD Classroom Display Tool.app`.
3. Confirm the AirPlay display appears in the connected external display list.
4. Confirm `Extend All Displays` is not shown with only the built-in display and
   the AirPlay display connected.
5. Test `Teacher Private Mode` and confirm the built-in display remains private
   and the AirPlay display is extended without an app error.
6. Disconnect from AirPlay while the app is open and confirm the app refreshes
   to the one-display message with no stale display mode cards.

### 3 Displays: Built-In + HDMI + Apple TV/AirPlay

1. Connect the HDMI classroom display.
2. Connect the Apple TV/AirPlay display.
3. Open `HBCSD Classroom Display Tool.app`.
4. Test each available preset:
   - Mirror Everything: all three displays show the same content, using an
     external classroom display as the mirror source.
   - Teacher Private Mode: built-in stays private, external displays mirror.
   - Extend All Displays: all three displays are separate.
5. Confirm both external displays appear near the top of the app.
6. While the app is still open, disconnect one classroom display.
7. Confirm the app automatically refreshes to the two-display preset list and
   `Extend All Displays` disappears.
8. Reconnect the second classroom display and confirm `Extend All Displays`
   returns after the app refreshes. Use `Refresh` if macOS needs a manual
   re-scan.

### Non-16:9 External Display

1. Connect an external display or projector that is not 16:9, if available.
2. Open `HBCSD Classroom Display Tool.app`, test `Mirror Everything`, and
   confirm the tool either applies a usable mirror layout or shows a clear
   warning/fallback message.
3. IT can review the log afterward to confirm the unusual aspect ratio was
   recorded.

## What to Report Back

Ask the tester to send:

- Which display setup they tested: 1, 2, or 3 displays.
- Which preset they chose.
- Whether the displays changed as expected.
- Whether macOS showed any warning or permission prompt.
- If it failed, send a screenshot or photo of the app message.

IT can also review:

```text
~/Library/Logs/HBCSD Display Mirror/display-config.log
```
