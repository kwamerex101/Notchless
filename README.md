<div align="center">

<img src=".github/assets/hero.svg" width="100%" alt="Notchless — turn your Mac's notch into a Dynamic Island" />

<br/>

[![Release](https://img.shields.io/badge/release-v1.6.0-6C63E8)](https://github.com/kwamerex101/Notchless/releases)
[![Platform](https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![AI](https://img.shields.io/badge/AI-on--device-35C6CE)](#dictation-ported-from-a-standalone-app-fully-integrated)
[![License](https://img.shields.io/badge/license-proprietary-8891A2)](#license)

</div>

---

**Notchless** is a native macOS menu-bar app that turns your Mac's notch into a
Dynamic Island. Live activities, HUDs, and hold-to-talk dictation live in the
notch — with an iOS-style, physics-driven feel, and the AI runs **on-device**.

- 🎧 **It reacts to what's happening** — music, calls, timers, battery, and more surface in the notch and morph as things change.
- 🎙️ **Dictation anywhere** — hold a hotkey, speak, and it types into the focused app, transcribed on-device.
- 🔊 **Native HUDs** — notch-anchored volume and brightness overlays that replace the system OSD.
- 🖥️ **Follows you** — moves to your active display and can stay visible over fullscreen apps.

> **Requires macOS 14.0+.** Grab a notarized build from the
> [**Releases**](https://github.com/kwamerex101/Notchless/releases) page, or
> [build from source](#build).

---

## Features

### Live Activities (the notch reacts to what's happening)
- **Now Playing** — album art, a real audio-reactive visualizer (system-audio FFT), scrubber, and transport controls. The bars pick up the album-art glow.
- **Auto carousel** — when several things are live at once (music + a call, etc.), swipe horizontally to page between them; browse Calendar and System Stats too.
- **Battery hub** — charge, charging state, time remaining, with a charge ring.
- **System Stats** — live CPU / memory / network, with a refresh interval and per-metric toggles.
- **Claude Usage** — parses local Claude Code transcripts for token usage: a pie of the input/output/cache split, a daily line chart, and 5-hour session / weekly / daily estimated spend.
- **Timer** — a countdown with presets and a ring, controllable from the notch.
- **Clipboard history** — recent copies, click to re-copy, plus a screen colour picker.
- **Privacy indicator** — a pulsing dot when the camera/mic is in use (green/orange), like macOS's own.
- **Calendar** — upcoming events and weather.
- **File Tray** — drag files onto the notch to hold them, drag them back out anywhere.
- **Todos** — a notch checklist with subtasks and free-text (URL-aware) notes; edits stay in sync between the notch and Settings.
- **Goals** — savings goals with a target and deadline, logged contributions, a required monthly-pace calculation, and a progress ring; pin one to the notch.

### Dictation (ported from a standalone app, fully integrated)
- Hold-to-talk anywhere; types into the focused app.
- Two on-device engines: **Apple Speech** and **Parakeet** (NVIDIA Parakeet TDT on the Neural Engine via FluidAudio).
- Optional AI cleanup — local `claude` CLI, the Anthropic API, or **on-device Gemma** (llama.cpp).
- Custom vocabulary, snippets/text-expansion, spoken operators, per-app tone learning, encrypted history, and more.

### HUDs &amp; notifications
- Notch-anchored **volume** and **brightness** HUDs replacing the system OSD.
- Polished transient banners for charging, Bluetooth, Focus, and network (No Internet / Back online).

### System &amp; polish
- **Follows your active display** across the built-in screen and external monitors.
- **Stays visible over fullscreen** apps (optional).
- **Liquid Glass** theming (Clear / Tinted + intensity) on macOS 26; the primary accent follows your macOS accent colour.
- iCloud-synced settings, launch-at-login, hide-from-screen-capture, and per-feature toggles.
- Two-finger swipe gestures over the notch.

## Requirements

- macOS 14.0+ (Liquid Glass effects and Parakeet require newer macOS / Apple Silicon)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Notchless.xcodeproj -scheme Notchless \
  -configuration Debug -destination 'platform=macOS' \
  -skipMacroValidation build
```

`-skipMacroValidation` is required because the on-device Gemma path depends on
[LLM.swift](https://github.com/eastriverlee/LLM.swift), which uses a Swift macro
that Xcode blocks in non-interactive builds.

The project is generated from `project.yml` — the `.xcodeproj` is not committed.

## Permissions

Grant these in **System Settings → Privacy &amp; Security** (the in-app **Permissions**
pane lists them with live status):

- **Accessibility** — hold-to-talk hotkey and pasting dictated text
- **Microphone** / **Speech Recognition** — dictation
- **Camera** — the notch camera mirror
- **Audio Recording** — the live system-audio music visualizer
- **Calendar**, **Bluetooth**, **Location** — the respective live activities

## Tech

SwiftUI + AppKit, a borderless non-activating `NSPanel` over the notch, XcodeGen
for the project, and Combine for state. Speech via `AVAudioEngine` + `vDSP` FFT.
Dependencies: [FluidAudio](https://github.com/FluidInference/FluidAudio) (Parakeet,
Apache-2.0), [LLM.swift](https://github.com/eastriverlee/LLM.swift) (Gemma, MIT),
and [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (now-playing, BSD-3).

## Acknowledgements

Inspired by the great work of the macOS notch community — Alcove, boring.notch,
Atoll, DynamicNotch, rtaudio, and SkyLightWindow. All designs and code here are
original reimplementations; no GPL code or assets from those projects were used.

## Author

Built by **Theophilus RexDanquah** — [rexdanquah.dev](https://rexdanquah.dev)

## License

Copyright © HOMEKARE TECHNOLOGY LTD. All rights reserved.
