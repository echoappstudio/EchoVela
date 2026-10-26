<p align="center">
  <img src="docs/images/echovela-icon.png" width="88" alt="EchoVela app icon">
</p>

<h1 align="center">EchoVela</h1>

<p align="center">Brightness, contrast and volume for every display on your Mac, from the menu bar or your keyboard.</p>

<p align="center"><a href="https://github.com/echoappstudio/EchoVela/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+ · Apple Silicon</p>

<p align="center">
  <a href="https://github.com/echoappstudio/EchoVela/releases/latest"><img src="https://img.shields.io/github/v/release/echoappstudio/EchoVela?display_name=tag" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 or later">
  <a href="https://github.com/echoappstudio/EchoVela/actions/workflows/macos-ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/echoappstudio/EchoVela/macos-ci.yml?branch=main&amp;label=macOS%20CI" alt="macOS CI status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

## Features

- **Every display in one place.** Click the sun in the menu bar for a brightness slider for each screen, plus contrast and volume sliders for monitors that have them, and your presets one click away. Open EchoVela for the full window, with Displays, Presets, Shortcuts and Settings in the sidebar.
- **Real monitor brightness.** External monitors change their own backlight over the video cable (DDC), just like pressing the buttons on the monitor, so the picture stays sharp and colors stay true. Your MacBook and Apple displays use macOS's own brightness control.
- **Works with every screen.** Monitors that can't be controlled directly (some HDMI ports, docks, adapters and TVs, AirPlay and Sidecar) are dimmed in software instead. EchoVela works out which is which on its own; you can also choose for each monitor in **Displays**.
- **Darker than dark.** For late nights, the bottom quarter of the slider dims the picture further once a monitor reaches its lowest setting. The screen never goes fully black.
- **Your keyboard just works.** The brightness keys change the monitor under the pointer (or every display), and the volume keys control a monitor's speakers when your Mac's sound plays through them. Hold Option and Shift for finer steps.
- **Presets.** Day, Evening and Night set every display at once with one click or one shortcut. Add your own (up to 12), pick a symbol, reorder them, and restore the original three anytime. Presets fade in slowly, so the change is easy on your eyes.
- **Your own shortcuts** for Brighter, Dimmer and each preset. They work in every app, and EchoVela warns you if two of them clash.
- **Gentle changes.** Brightness glides to its new level instead of jumping, and a small glass indicator shows the new level in the top-right corner of the screen you changed. Turn on **Move all displays together** to keep every screen at the same level.
- **Stays out of your way.** EchoVela lives in the menu bar and opens when you log in. Its window and Dock icon only appear when you open them.
- **Black and silver.** One look in Echo App Studio's colors, light or dark to match your Mac, and an icon to go with it.
- **Updates itself.** EchoVela checks for a new version when it starts and every hour, then installs it and reopens once any brightness change has finished. Turn this off, or check by hand, in **Settings → Updates** or with **Check for Updates…** in the menu.
- **Private.** No account and no tracking. EchoVela only goes online to check GitHub for a new version.

## Install

1. Download `EchoVela.zip` from the [latest release](https://github.com/echoappstudio/EchoVela/releases/latest) and unzip it.
2. Drag **EchoVela** into **Applications** (choose **Replace** when updating), then open it from there.
3. If macOS blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway**. (Builds aren't notarized by Apple yet, so macOS asks on first launch.)
4. EchoVela appears in the menu bar as a sun. To use your keyboard's brightness and volume keys on your monitors, allow EchoVela in **System Settings → Privacy & Security → Accessibility** when it asks. The sliders, presets and your own shortcuts work without it.
5. **Updates install themselves.** EchoVela 0.3.0 is the first version under this name and a fresh install, so it doesn't update an old copy. If you used the earlier version, delete it and its Accessibility entry first. If the brightness keys stop working after an update, remove the old EchoVela entry from the Accessibility list and turn on the new one.

You need an Apple Silicon Mac with macOS 26 or later.

## Shortcuts

| Keys | What they do |
|---|---|
| **Brightness keys** | Brighter or dimmer on the display with the pointer, or on every display (choose in **Shortcuts**). Needs Accessibility. |
| **Option + Shift + brightness keys** | The same in smaller steps. |
| **Volume keys** | Change the monitor's speakers when your Mac's sound output is set to that monitor. Otherwise they work as usual. Needs Accessibility. |
| **Your Brighter and Dimmer shortcuts** | Set them in **Shortcuts**. They change the same displays as the brightness keys and don't need Accessibility. |
| **Your preset shortcuts** | One for each preset, set in **Shortcuts**. |

Your MacBook and Apple displays keep their usual brightness keys.

## How it works

1. **Finding your displays.** EchoVela asks each external monitor what it supports: brightness, contrast and volume. The answers decide which sliders you see.
2. **Monitors over DDC.** Most external monitors accept brightness, contrast and volume commands over their video cable (DDC/CI). EchoVela sends them through macOS's display services on Apple Silicon. Some HDMI ports, docks and adapters don't pass these commands on.
3. **Software dimming.** A dark layer over the whole screen. It's used for screens that can't be controlled directly, and for the extra dimming below a monitor's minimum. Clicks pass straight through it.
4. **MacBook and Apple displays.** EchoVela uses macOS's own brightness control, and the keyboard keeps working as usual on them.
5. **Remembering.** Each monitor's brightness and control choice is remembered by name and serial number, so it comes back the same after you reconnect it.

## Where your settings are

| What | Where | Notes |
|---|---|---|
| **Settings, presets, shortcuts and per-display levels** | `~/Library/Preferences/com.echoapps.echovela.plist` | Managed by macOS. |

EchoVela keeps no other files.

## Privacy

Everything runs on your Mac. EchoVela has no account, no analytics, and doesn't connect to the internet.

<details>
<summary>Build and test</summary>

You need macOS 26 and Xcode 26.

```sh
swift test                       # tests
bash Scripts/package-app.sh      # build dist/EchoVela.app and dist/EchoVela.zip
bash Scripts/smoke-test.sh       # launch the packaged app from a clean copy
```

</details>

## License

MIT. See [LICENSE](LICENSE).
