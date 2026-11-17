# DisplayTidy

A native macOS menu bar utility for arranging displays. Choose a reference display and a display to move, select one of 12 alignments, and apply the layout. DisplayTidy remembers the last applied relationship and provides a draggable two-display preview.

Full multi-display previews, numbered screen overlays, named layouts, arbitrary positioning, and automatic layout restoration are not implemented.

## Build and run

Requires macOS 13+ and a Swift 6 compiler (Xcode or Command Line Tools). No third-party dependencies are required. The build script targets Apple Silicon; Intel builds have not been verified.

```sh
./scripts/build.sh
open build/DisplayTidy.app
```

Click the two-display menu bar icon to open the quick panel. It contains display selectors, a draggable arrangement preview, refresh, and settings. Click outside the panel or press Esc to dismiss it without quitting.

Choose **Open Main Window** for the full interface, including display dimensions, status, and an alignment menu. Both interfaces share the same selections and state. Reopening the main window reuses it and restores it if minimized. The Dock icon appears while the main window is open, remains visible when minimized, and disappears when the window closes. DisplayTidy continues running in the background. Use **Quit** or **Quit DisplayTidy** to exit; quitting is disabled while an operation is running.

The main window's **Settings** button and the panel's gear open the same settings window. **View Log** opens a separate window with live, selectable log text. Logs are kept only in memory for the current process. Closing these windows does not quit the app.

The blue app icon depicts a Studio Display and a landscape iPad with their display areas aligned along the bottom. `Resources/AppIcon.png` is the source image; `Resources/AppIcon.icns` contains the macOS icon sizes. Both build variants include it.

## Language

**English is the default language**, regardless of the system language. In Settings, use **Language** to switch between **English** and **中文**. Language names always use their native spelling. Changes immediately update interface text, status messages, errors, and window titles. The selection is saved in UserDefaults under `appLanguage` and restored on subsequent launches. Existing saved language choices are preserved; missing or unsupported choices fall back to English.

Source code uses English text as localization keys and fallback text. `Resources/en.lproj/Localizable.strings` contains the English source strings; `Resources/zh-Hans.lproj/Localizable.strings` maps those same English keys to Simplified Chinese. The build copies both tables into the app bundle and sets English as the development language. When adding interface text, use an English key and add matching entries to both tables, preserving format placeholders such as `%@`.

Device names retain their system-provided spelling. Existing log entries retain the language used when recorded; new entries use the current language. Error details returned by macOS may use the system language.

## Arrange displays

1. Select a **Reference** display and a display to **Move**.
2. Drag the blue display rectangle to a candidate position. Gray outlines show the available positions, and blue highlights the current candidate. The main window also provides an alignment menu below the preview.
3. Click the blue checkmark to **Apply Layout**.

Above and below support left, center, and right alignment. Left and right support top, center, and bottom alignment. Releasing a drag snaps the preview to the selected alignment; cancelling a drag leaves the selection unchanged. Reduce Motion disables the snap animation. When candidate positions coincide, the current alignment is preserved where possible.

The neutral rectangle represents the reference display; the blue rectangle represents the display to move. The preview and candidate outlines use the same scale and occupy 80% of the available width or height. Custom positions are included in the preview bounds. Other displays are not shown, but all active displays are validated before applying a layout.

The apply button appears only when the proposed position differs from the actual position. It disappears when dragged back or after a successful application, and shows progress while applying. Selecting an alignment changes only the preview until you apply it.

Each time the panel or main window opens, the active display under the pointer becomes the reference. If it cannot be identified, a valid existing selection is retained, otherwise the system primary display is used. The display with the lowest remaining ID is selected as the target. You can change either selection manually; pointer movement and focus changes do not keep changing it afterward. Ordinary refreshes preserve valid manual selections.

Any active display, including the system primary display, can be the reference or target, but the two must be different. When moving the primary display, all coordinates are rebased so it remains at `(0, 0)` without changing its primary identity or the relative positions of the other displays. If the target disconnects or matches the reference, another display is selected by lowest ID. With only one display, there is no target.

**Refresh Displays** reads actual coordinates and updates the preview without moving displays or changing the saved relationship. Positions that do not match a preset are shown as **Current Position**. Switching targets also checks the last-read position.

Every application recalculates coordinates from current display dimensions. Center offsets are rounded before adding the reference coordinates to avoid one-pixel differences after rebasing. A successful application saves both display UUIDs and the alignment relationship. Restarting restores the selection, but moving displays always requires manual application. Connect Sidecar through macOS first; DisplayTidy does not establish the connection. Layouts use `.forSession`; closing the panel or quitting does not actively restore the previous layout.

## Settings

### Menu bar icon visibility

**Show menu icon only with multiple displays** is off by default and remembers your choice. When enabled, the icon is shown only when macOS reports at least two available desktop displays. A single external display with the laptop lid closed still counts as one. The app continues running when the icon is hidden; reopen `DisplayTidy.app` to access the main window and settings.

Startup, activation, and display-change notifications refresh display information and icon visibility without automatically moving displays. Consecutive display events are coalesced over 150 milliseconds. The app uses SwiftUI's native `MenuBarExtra(.window)` and retains a standard Settings scene so hiding the menu bar item does not quit it.

The panel uses the system background and rounded corners without a custom arrow or outer frame. Its top edge is positioned at the screen's available upper boundary; horizontal placement remains system-controlled. Separate windows use `underWindowBackground` material extending into the transparent title bar, while controls respect the title bar safe area. Material appearance follows window focus and system settings. See Apple's [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) and [window background material documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground).

### Launch at login

**Launch at Login** uses macOS 13+ `SMAppService.mainApp`. Enabling it registers the app; disabling it unregisters it. The switch reads the system state rather than a separately stored Boolean. Pending approval is shown with an **Open Login Items Settings** button, and the state refreshes when the app becomes active again.

Keep the app at a stable path after enabling this option. Local builds can run from the project's `build` directory. The app does not register automatically.

### Hide notch (experimental)

This option is off by default and is saved under `hideNotch`. It adds a black background window at the top of a built-in display with a notch, without changing wallpaper, resolution, or system menu bar settings. External displays are unaffected. The overlay does not take focus or intercept clicks and is removed when disabled or when the app exits. It works independently of menu bar icon visibility.

The background is rebuilt when screen parameters change, Spaces switch, or the Mac wakes, using the screen's top safe area for placement and height. This is an overlay prototype: the system menu bar background may cover it, and macOS may not switch menu text to white. Light/dark appearance, full screen, auto-hiding menu bars, dynamic wallpapers, and sleep/wake behavior have not been verified on real hardware. Turn the option off if the result looks incorrect. Lock and login screens are unsupported.

## Command line

The command-line interface uses the same display APIs as the app:

```sh
build/DisplayTidy.app/Contents/MacOS/DisplayTidy --self-test
build/DisplayTidy.app/Contents/MacOS/DisplayTidy --list
# Use a current non-primary display ID from --list, not an old saved ID.
build/DisplayTidy.app/Contents/MacOS/DisplayTidy --move-below-center DISPLAY_ID
build/DisplayTidy.app/Contents/MacOS/DisplayTidy --move-below-left DISPLAY_ID
build/DisplayTidy.app/Contents/MacOS/DisplayTidy --move-below-right DISPLAY_ID
```

Run display commands inside a local graphical login session. Restricted command execution has previously reported zero displays even when the same command worked in the local login session. This restriction is separate from App Sandbox below.

## Persistence and limitations

- Successful applications atomically save the target UUID, reference UUID, direction, and alignment to `~/Library/Application Support/local.DisplayTidy/arrangement.json`. Historical coordinates and dimensions are not saved.
- New layouts use schema version 2. Legacy below-display arrangements remain readable and are upgraded only after a successful application, not on startup.
- Only the last successful relationship is saved; multiple named layouts are not supported. Current dimensions are used each time.
- Missing or duplicate UUIDs, mirroring, overlap, and disconnected layouts prevent application. Displays must share an edge of at least one desktop coordinate unit; corner contact is insufficient.
- Reconnected displays are matched by UUID. If the reference disconnects, selection falls back to the system primary display. If the target disconnects or becomes the reference, the lowest-ID alternative is selected, or cleared if none exists. A target becoming primary remains selectable. Selection changes never move displays automatically.
- Actual coordinates are reread after submission. Failures show an error without automatic retries. Three-display moves that would overlap or disconnect the layout are rejected; the app does not rearrange other displays to compensate.
- Corrupt or unsupported arrangement files are preserved and reported instead of being overwritten during loading.
- Legacy `recovery.json` and `RecoveryArchive` data are preserved but no longer read or used to block operations. Recovery/archive buttons and `--restore` have been removed.
- Builds use local ad-hoc signing for the development device. Developer ID signing, notarization, public distribution, and real macOS 13 operation have not been verified. Signing is verified in a temporary directory before copying the build output; file-provider metadata added afterward can invalidate the generated app's signature.

## App Sandbox comparison build

```sh
./scripts/build.sh --sandbox
open build/DisplayTidy-Sandbox.app
```

This variant adds only the `com.apple.security.app-sandbox` entitlement. It contains no Accessibility, Screen Recording, or administrator permission request code. Layout data is stored in the bundle's container Application Support directory, and settings are independent of the regular app. Actual permission requirements depend on macOS behavior and must be verified on the target system.


## Local files

Development builds update `build/DisplayTidy.app` using the same app name and bundle identifier.

- `Sources/`, `Resources/`, `scripts/`: source code, English/Chinese localization and icons, and build scripts.
- `build/DisplayTidy.app`: the regular app. `build/DisplayTidy-Sandbox.app`: the optional sandbox comparison build.
- `.build/module-cache/`: regenerable compiler cache.
- `~/Library/Application Support/local.DisplayTidy/`: regular app data. Only `arrangement.json` is currently read; legacy recovery files remain untouched.
- `~/Library/Containers/local.DisplayTidy-Sandbox/`: the macOS-managed sandbox container. The old `local.DisplayTidyM0-Sandbox` container retains historical data but is not used by new builds.
- `~/Library/Preferences/local.DisplayTidy.plist`: UserDefaults preferences, including language and icon visibility. The old `local.DisplayTidyM0.plist` is retained but unused. Arrangement data lives in Application Support.
- `/private/tmp/DisplayTidy-build.*`: temporary build staging directories, removed when the build script exits.

The build script does not install the app into `/Applications` or `~/Applications`. Enable launch at login in Settings. Startup after a real logout/login and launch at login for the sandbox build remain unverified.
