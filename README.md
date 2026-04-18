# HyperCaps

A macOS utility that turns Caps Lock into a Hyper Key — one key that sends ⌘⌃⌥⇧ simultaneously. Create powerful, conflict-free keyboard shortcuts for any app.

## Requirements

- macOS 14 (Sonoma) or later

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/HyperCaps/releases/latest/download/HyperCaps.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places the app in `/Applications` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/HyperCaps/releases/latest)** — unzip and drag `HyperCaps.app` to your Applications folder.

After installation:

1. Launch HyperCaps — a Caps Lock icon appears in your menu bar
2. Grant Accessibility permission when prompted

## How It Works

HyperCaps remaps Caps Lock at the HID level so it acts as a modifier key rather than a toggle. Hold Caps Lock and press any other key to send a shortcut that includes all four modifier keys at once — a combination no application will ever conflict with.

| You press | macOS receives |
|-----------|----------------|
| Caps Lock + E | ⌘⌃⌥⇧E |
| Caps Lock + Space | ⌘⌃⌥⇧Space |
| Caps Lock alone | Nothing (consumed silently) |
| ⇧ + Caps Lock | Toggles Caps Lock on/off |

Caps Lock alone does nothing. It sits silently until you combine it with another key, giving you a completely new layer of keyboard shortcuts.

## Caps Lock Toggle

Traditional Caps Lock isn't gone. Hold Shift and tap Caps Lock to toggle Caps Lock on and off. A centred HUD appears briefly to confirm the state.

## Menu Bar Icon

The Caps Lock icon in the menu bar reflects the engine state:

- **Outlined**: Engine is starting up (waiting for permission)
- **Filled**: Hyper Key is active

Click the icon to access:

- **Hyper Key Active** — toggle the engine on/off
- **Caps Lock status** — current on/off state
- **Modifier display** — shows which modifiers are being sent
- **Settings** — configure modifiers and permissions
- **About** — version info and update check

## Settings

### Hyper Key Modifiers

Choose which modifiers the Hyper Key sends. All four are enabled by default, but you can disable any combination. At least one must remain active.

| Modifier | Default |
|----------|---------|
| Command (⌘) | On |
| Control (⌃) | On |
| Option (⌥) | On |
| Shift (⇧) | On |

### General

- **Accessibility** — permission status and grant button
- **Menu bar icon pill** — optional coloured background for improved contrast on custom wallpapers
- **Launch at Login** — start automatically when you log in
- **Auto-update** — check for new versions on a configurable schedule with optional automatic installation

## Permissions

### Accessibility (required)

Needed to intercept keyboard events and inject modifier flags.

- Prompted automatically on first launch
- Grant in: **System Settings → Privacy & Security → Accessibility**
- Without this, the Hyper Key will not function

## Important: System Settings Caps Lock

macOS System Settings must have Caps Lock set to its **default behaviour**. If you have previously remapped Caps Lock to Escape, Control, or No Action in **System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys**, reset it to "Caps Lock" before using HyperCaps.

HyperCaps will alert you on launch if it detects a conflicting system-level remap.

## Building from Source

HyperCaps uses Swift Package Manager. No Xcode project is required.

```bash
cd ~/Desktop/"Jorvik Software"/HyperCaps
./build.sh
open _BuildOutput/HyperCaps.app
```

The build script runs `swift build -c release`, then assembles the `.app` bundle in `_BuildOutput/` with the executable, icon, and Info.plist.

## How It Works (Technical)

HyperCaps operates in three layers:

1. **HID remap** — uses `hidutil` to remap Caps Lock (USB usage `0x39`) to F18 (`0x6D`) at the hardware input level
2. **CGEvent tap** — a global event tap intercepts F18 key events and injects the configured modifier flags into any key pressed while F18 is held
3. **IOKit** — directly toggles the physical Caps Lock LED state for the Shift+Caps Lock toggle

The `hidutil` remap is cleaned up on quit, and safety handlers ensure cleanup on SIGTERM, SIGINT, and atexit. All blocking operations (process spawning) run on background threads to keep the main run loop responsive.

## Troubleshooting

### The Hyper Key doesn't work

Make sure HyperCaps has **Accessibility** permission in System Settings → Privacy & Security → Accessibility. You may need to remove and re-add it if you've rebuilt the app.

### Caps Lock is set to "No Action" in System Settings

HyperCaps needs the system-level Caps Lock mapping set to its default. Go to **System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys** and set Caps Lock to "Caps Lock". HyperCaps handles the remapping itself.

### The menu bar icon stays outlined

The engine is waiting for Accessibility permission. Check System Settings → Privacy & Security → Accessibility and ensure HyperCaps is listed and enabled.

### Caps Lock LED doesn't toggle

The LED toggle requires Shift + Caps Lock (a bare tap). If you pressed another key while Caps Lock was held, it counts as a Hyper Key combo and the toggle is suppressed.

---

HyperCaps is provided by [Jorvik Software](https://jorviksoftware.cc/utilities/hypercaps). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
