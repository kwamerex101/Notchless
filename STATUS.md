# Build Status — Dynamic Island (Alcove replica)

Last updated: 2026-07-05. Build: **green** (`xcodebuild` succeeds), app launches and runs
without crashing. Everything below was written from scratch; see `PLAN.md` for the design spec
derived from the reference video + site.

## How to run

```bash
xcodegen generate          # regenerate the .xcodeproj from project.yml after any file add/remove
open DynamicIsland.xcodeproj   # then Run (⌘R) in Xcode — signs with your team, prompts for perms
```
Or from the CLI: `xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -derivedDataPath build build && open build/Build/Products/Debug/DynamicIsland.app`

A menu-bar icon appears (no Dock icon). Right-click the notch for the Version / Settings / Quit menu.

## What's built (all compiles + runs)

| Phase | Feature | State |
|---|---|---|
| 0 | Xcode project (XcodeGen), menu-bar agent, no sandbox | ✅ Done |
| 1 | Notch panel: transparent NSPanel flush over the notch, animatable `NotchShape`, geometry detection, reposition on display change | ✅ Done |
| 2 | State machine (bare/idle/HUD/notification/expanded) + priority resolver, hover-grow, click-expand, grace collapse, scoped hit-testing, right-click menu | ✅ Done |
| 3 | Sound HUD (CoreAudio volume/mute), Display HUD (DisplayServices brightness + media-key event tap), reversible OSD suppressor | ✅ Built — needs perms/tuning (below) |
| 4 | Now Playing: bundled mediaremote-adapter (works on macOS 26), provider, controller, elapsed interpolation; idle-compact + full expanded player (art, marquee title, scrubber, transport) | ✅ **Working & verified** (below) |
| 5 | Calendar (EventKit) + weather (Open-Meteo + CoreLocation); calendar panel with month grid | ✅ Built — needs perms |
| 6 | Idle activities None/Playing/Calendar/Duo + Duo two-column panel | ✅ Done |
| 7 | Settings window: sidebar sections/icons/"Soon" badge, toggle cards, both segmented card-pickers, Behaviour, License/About | ✅ Done |
| 8 | Notifications: Battery (IOKit), Connectivity (Bluetooth), Focus (assertions file) | ✅ Built — Focus needs Full Disk Access |
| 9 | Simulated notch + display-target picker; multi-monitor coords hardened (auto-detects local vs global aux rects + clamps into the frame) | ✅ Done — verify on a real 2nd display |
| 10 | Progressive blur (gradient-masked behind-window), haptics, springs | ✅ Built — blur is an approximation, tune visually |
| — | **File Tray** (drag files onto the notch, hold as chips, drag back out) — Alcove ships this as "Soon"; here it works | ✅ Done |
| — | **Output-device picker** in the player (lists + switches CoreAudio output) | ✅ Done |
| 12 | Trial (72h) + license scaffold, About pane | ✅ Scaffold |
| 11 | Lock Screen live activity | ❌ Descoped — infeasible for a standard app (see below) |

## What needs YOU (can't be done autonomously)

These are real limits, not omissions — they need your machine, your grants, or your judgement:

1. **Permissions** (the app prompts on first run; grant them in System Settings → Privacy):
   - **Accessibility** — for the media-key event tap (brightness HUD). Without it, the brightness
     HUD won't trigger (volume HUD still works via CoreAudio).
   - **Calendar** (Full Access) — for events.
   - **Location** — for weather. Denied → calendar still shows, weather hidden.
   - **Bluetooth** — for connectivity notifications.
   - **Full Disk Access** — only for Focus detection; optional.

2. **MediaRemote gating (macOS 15.4+) — RESOLVED.** The **mediaremote-adapter**
   (github.com/ungive/mediaremote-adapter, BSD-3-Clause) is built as a universal framework and
   bundled at `Resources/Adapter/` (framework + perl script + LICENSE). `AdapterNowPlayingProvider`
   runs `/usr/bin/perl … stream` as a subprocess and parses its JSON, so Now Playing works on
   macOS 26. **Verified end-to-end:** the app spawns the stream and parsed a live track title into
   the model. The direct `MediaRemoteBridge` remains as a fallback for older systems. Orphaned
   streams from a hard-kill are swept on next launch; graceful quit terminates the stream.
   To rebuild the framework: `cmake` the repo with `-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"` and
   copy `MediaRemoteAdapter.framework` + `bin/mediaremote-adapter.pl` into `Resources/Adapter/`.

3. **OSD suppression** is implemented but **disabled by default** (`OSDSuppressor.enabled = false`)
   because pausing `OSDUIHelper` is intrusive/fragile. Flip it on to test replacing the system HUD.

4. **Visual pixel-tuning** — I could not screenshot (Screen Recording isn't granted to the shell),
   so shape radii, per-state sizes, HUD/idle proportions, and blur strength are best-guess from the
   frames. Play `references/alcove_segment.mp4` side-by-side and adjust the numbers in
   `NotchSizing.swift`, `NotchShape.swift`, and the state views.

5. **Lock Screen activity (Phase 11) — DESCOPED (infeasible).** On macOS 10.13+ the lock screen
   is drawn by `loginwindow` in a separate secure session; third-party apps cannot render UI there,
   and there is no public API for it. The old login-window plugin mechanism is removed. So Alcove's
   "lock screen clock/weather" is not reproducible by a normal app — pursuing it would mean private
   or unsupported hacks that break on updates. Recommendation: drop it, or reframe as a
   screen-saver/idle companion (which *is* allowed) if you want something in that space.

### Newly completed this pass
- **Compact idle padding** — symmetric, corner-clearing insets (was jammed into the left corner).
- **File Tray** — drop files on the notch → chips you can drag back out; enable toggle in Settings.
- **Output-device picker** — the player's speaker button lists and switches audio output devices.
- **Multi-monitor geometry** — auto-detects whether aux-area rects are local or global and clamps
  the notch centre into the target screen, so a 2nd display can't push the panel off-screen.

## Perf / UX / polish pass (branch `feat/perf-ux-polish`, 2026-07-06)

Executed the 20-task plan in `docs/superpowers/plans/2026-07-06-perf-ux-polish.md`.
Build green, 67 tests pass (was 30). No features removed.

- **Idle cost:** every always-on poller (clipboard, stats, privacy) is now gated on its
  settings toggle and, for stats, on visibility; the follow-screen timer runs only in
  Active-display mode; Claude-usage parsing is incremental (per-file mtime/size cache); the
  audio tap is throttled to 30 Hz and gated on the visualizer being on screen; the 0.5 s
  now-playing republish is gone (view-local elapsed extrapolation). High-frequency audio
  levels live in a dedicated `AudioLevelsModel`, so the visualizer no longer repaints the
  whole notch tree.
- **Bugs fixed:** notch text fields can now receive keyboard input (Tasks quick-add / Goals
  quick-log); live fullscreen-hide toggle; partial iCloud pulls no longer flip toggles off;
  goal save/load is corruption-resilient; notifications replay their entrance; calendar
  permission-denied shows a real prompt.
- **Motion/UX:** one `NotchMotion`/`NotchDesign` vocabulary; real (previously dead) content
  transitions with directional carousel slides and matched-geometry album art; hover-intent
  dwell + universal hover/press feedback (`NotchButtonStyle`); rolling numerals; grabbable
  scrubber; HUD/notification bloom; Reduce Motion + VoiceOver labels.
- **Hygiene:** Release enables hardened runtime (Debug off); `GoalSelfTest`/`DebugRender`
  are `#if DEBUG`-gated; GitHub Actions CI runs build+test.

**Still to verify on-device (not measurable in CI):** actual CPU/energy/idle-wakeup numbers
via `powermetrics`/Activity Monitor, and a visual pass on the new animations. **Deferred:**
the `ActivityDescriptor` registry refactor (T18 — pure internal, needs pixel-diff verification)
and Sparkle auto-update (T20 H4). Re-cut + notarize the DMG from a Release build before the
next public release.

## Suggested next session

- Bundle mediaremote-adapter so Now Playing works on macOS 26 (unblocks the headline feature).
- Do a screenshot-driven tuning pass against the reference video.
