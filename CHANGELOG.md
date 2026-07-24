# Changelog

All notable changes to Notchless are documented here.

## [1.7.2] — 2026-07-24

### Fixed
- **Settings no longer revert via iCloud.** A setting changed on this Mac
  could be silently reverted on the next launch when iCloud held an older
  value for it — so toggling a setting appeared to do nothing. The initial
  iCloud sync now leaves values you've already set on this device alone,
  while a fresh install still adopts your synced settings.

## [1.7.1] — 2026-07-24

### Fixed
- **Fullscreen auto-hide on external monitors.** The notch now detects a
  fullscreen app on an external display and hides, revealing on a top-edge
  hover. The previous check used a menu-bar heuristic that never passed on
  external monitors, so the notch stayed on top of fullscreen content there.
- **Battery panel.** The expanded battery ring no longer overflows and clips
  at the bottom of the panel.

### Changed
- **Hide in fullscreen is now on by default**, matching the native menu-bar
  behaviour (auto-hide in fullscreen, reveal on a top-edge hover). Turn it off
  in Settings › General.

## [1.7.0] — 2026-07-24

### Changed
- **Flat dark redesign.** The whole notch UI and the Settings window move to a
  flat, tinted-dark language: one opaque surface, a hairline edge, and
  monochrome white content, with colour kept for meaning (charge, alert, done).
  No more glass, glow, or gradients.
- **Settings window.** Rebuilt dark end to end — a monochrome sidebar
  (selection is the only highlight), flat grouped cards, and a consistent set
  of controls (switches, sliders, menus, segmented pickers, chip grids).

### Added
- **Notch surface tint.** Pick the notch's tint — Graphite, Blue, Purple,
  Green, or Black — in Settings › General › Theme; it applies across every
  state.
- **Two-line notifications.** The charging banner shows time-to-full, and a
  connected-but-no-route network state now reads "connected without
  internet".

### Fixed
- Expanded panels now hold a minimum width so the tab strip stays clear of
  the hardware notch on narrower panels (Meeting, Privacy, Timer, Battery).

## [1.6.0] — 2026-07-13

### Added
- **HUD styles.** The volume/brightness overlay now comes in four styles —
  Notch (the default, integrated in the notch), Classic, iOS, and Circular —
  each with a live preview in Settings › Sound, plus a Line/Dot indicator for
  the dial and an optional accent-color tint.
- **Off-notch HUD placement.** Show the HUD at any of nine screen positions
  (or on all displays), via a floating panel. "Top" keeps it in the notch.
- **Drag to change value.** Click-drag on a floating HUD to set volume or
  brightness live.
- **True system-HUD replacement (opt-in).** Suppress the native macOS volume/
  brightness overlay and show only Notchless's own — off by default; enable in
  Settings › Sound. Also: react to external/Control-Center volume changes,
  mute-as-empty, percentage label, output-device glyph, and a configurable
  hide delay.
- **Brightness control.** Read and set built-in display brightness; external
  displays are driven through BetterDisplay or Lunar when installed.
- **Now Playing options.** Choose which transport buttons appear (including
  15-second skip), and restrict Now Playing to specific apps (System-wide vs
  an allowed-apps list).
- **Sound feedback.** Optional beep when the volume changes.

### Changed
- The default notch sound HUD now shows the current output-device glyph and
  empties the bar when muted. Both are toggleable in Settings › Sound.

## [1.5.0] — 2026-07-09

### Added
- **Redesigned dictation in the notch.** A calmer, more legible recording
  experience: a scrolling voice waveform that fills the panel, your live
  transcript streaming in as you speak, and a control row showing the target app,
  an elapsed timer, and an `esc`-to-cancel affordance. The notch grows from a
  listening sliver into the full panel on start, and morphs smoothly through
  transcribing → polishing → a compact result chip.
- **Dictation Modes.** Named presets that override your dictation settings — a
  custom AI-cleanup instruction/tone, output destination, formatting, engine, and
  language. Ships Default, Email, Code, Notes, and Casual (create your own too).
  The right mode is chosen automatically by the frontmost app, pinned manually
  from the notch menu or a hover **quick-pick bar**, or triggered by a mode's own
  dedicated **hold-to-talk hotkey**. The active mode shows in the recording pill.

### Changed
- **Settings refresh.** A cohesive, theme-adaptive visual pass across the whole
  settings window: each pane now carries a subtle identity from its section tint,
  with richer headers (icon tile + one-line description) and consistent,
  refined cards.

### Fixed
- Dictation cleanup no longer leaks chat-template stop tokens (e.g. `<|im_end|>`)
  into the pasted text.

## [1.4.0] — 2026-07-09

### Added
- **Trackpad feedback.** Optional haptic + sound feedback as you scroll and click
  anywhere in macOS: velocity-aware detent "ticks" while scrolling (tight when
  slow, a smooth blur on a fast fling) and a pulse on click down and up. Choose a
  Light/Medium/Strong haptic strength, one of three click-sound voices
  (Pebble/Twig/Drop), and the volume. Off by default; enable it in
  Settings → General → Trackpad Feedback (requires Accessibility to observe
  scrolling). Haptics need a built-in Force Touch trackpad; the sound works on any
  Mac.
- **Multi-finger gesture feedback.** A confirming tick when you swipe between
  spaces or full-screen apps (3/4-finger left/right), open Mission Control or App
  Exposé (up/down), or pinch to Launchpad / spread to Show Desktop (4-finger).
  Shares the same strength/voice/volume settings; toggle it under Trackpad
  Feedback. Observe-only — it never changes what your gestures do.

## [1.3.0] — 2026-07-08

### Added
- **Meeting minutes.** One-click meeting capture from the notch: records your
  mic and the far-side participants (via the system-audio tap), transcribes and
  separates speakers entirely on-device (FluidAudio VAD + diarization + NVIDIA
  Parakeet), and generates AI meeting minutes — a summary, decisions, and action
  items — from the transcript. Raw audio never leaves the Mac; only the finished
  transcript text is sent for summarization.
- **Summarize on your Claude subscription.** The minutes can be generated via the
  local `claude` CLI (Claude Code sign-in) with no API key and no per-token cost,
  or via a stored Anthropic API key. Both are selectable in Settings → Meetings.
- **Meetings library.** A native Settings pane to browse past meetings, read the
  speaker-labelled transcript and minutes, rename speakers, re-run the summary,
  and export Markdown. A one-time consent notice gates the feature, and a
  recording indicator shows while capture is active.
- **Works on laptop speakers.** The system-audio tap runs during a meeting (not
  just for the visualizer), and acoustic echo cancellation on the mic keeps the
  far side from bleeding in — so a headset is no longer required for speaker
  separation. Capturing the far side still needs the system-audio recording
  permission.

## [1.2.3] — 2026-07-07

### Fixed
- **The audio-visualizer recovery could churn the system audio engine.** The
  silence watchdog added in 1.2.2 recreated the audio tap whenever music was
  playing but no sound was captured — but it never stopped, so a *legitimately*
  silent stream (paused-but-reported-playing, denied permission, or a quiet
  passage) made it rebuild the tap every few seconds indefinitely. That rapid
  churn could wedge macOS's audio daemon. The watchdog now retries a bounded
  number of times, then gives up gracefully and falls back to the decorative
  animation until real audio returns.

## [1.2.2] — 2026-07-07

### Fixed
- **The now-playing audio visualizer stayed flat and never reacted to music.**
  Capturing system audio needs the `NSAudioCaptureUsageDescription` permission —
  a separate grant from the microphone — which the app never declared, so macOS
  handed the audio tap buffers full of silence instead of the real signal. The
  key is now present, so the visualizer reacts to whatever you're playing (you'll
  be asked once to allow audio recording). A tap created before that permission
  is granted — or one that spontaneously goes dormant mid-playback — used to stay
  silent forever; a watchdog now detects the silence and rebuilds the tap so it
  recovers on its own.

## [1.2.1] — 2026-07-06

### Fixed
- **Launch-freeze deadlock when a Bluetooth device is connected.** IOBluetooth
  delivers connect/disconnect notifications on a background queue as well as the
  main run loop; the handlers touched `@MainActor` state (publishing a notch
  notification) directly off-thread, which deadlocked Combine's publisher at
  launch — the app opened Not Responding, with no hover. The handlers now marshal
  all work onto the main queue. (Pre-existing bug, surfaced once a device was
  connected at startup.)

## [1.2.0] — 2026-07-06

A performance, battery, and polish release. No features were removed; test
coverage went from 30 to 67.

### Performance & battery
- **Idle CPU is now ~0%.** The always-on pollers (clipboard, system stats,
  privacy camera/mic scan) start and stop with their settings toggles instead of
  running constantly, and stats sample slowly unless their readout is on screen.
- **The music visualizer no longer repaints the whole notch.** Audio levels live
  in a dedicated model and the system-audio tap feeds the UI at a throttled
  30 Hz — and only runs while music is playing *and* its visualizer is visible.
- **Dropped the twice-a-second now-playing refresh** — elapsed time is
  extrapolated locally in the scrubber, so nothing updates while collapsed.
- **Claude usage stats parse incrementally** — only changed transcript files are
  re-read. The follow-screen timer runs only in Active-display mode, the hover
  region is cached, and settings write only the key that changed.

### Fixed
- **Keyboard input works in the notch** — Tasks quick-add and Goals quick-log
  could not be typed into before.
- **"Hide in fullscreen" now applies when toggled** (not only at launch).
- **iCloud sync no longer flips settings off** when another Mac has a different
  key set; a corrupt Goals save is backed up instead of discarded.
- Notifications replay their entrance; the Calendar panel shows a real "enable
  access" prompt instead of a blank day when permission is denied.

### Changed (feel)
- **Real morph and page transitions** (the previous ones were inert): the
  carousel slides directionally and album art grows from the compact sliver into
  the expanded tile.
- **Hover no longer over-triggers** — the notch grows slightly, then expands
  after a short dwell. Every button reacts to hover and press; play/pause and
  task checkboxes animate their icon swap.
- **Numbers roll** instead of flashing (battery %, CPU %, timer, cost, track
  time); the scrubber grows with a grab knob and a release haptic; HUD and
  notifications bloom out of the notch.
- Respects **Reduce Motion** and adds **VoiceOver labels** on notch controls.

### Internal
- Hardened runtime on Release builds (notarization-ready); dev-only tooling is
  `#if DEBUG`-gated; added GitHub Actions CI (build + test).

## [1.1.3] — 2026-07-06

### Added
- **Goal timeline & catch-up rate.** Each goal now shows its start → deadline
  (both editable), months remaining, and **"Save ₵X/mo to finish on time"** —
  the amount you need to save each month from now, `(target − current) ÷ months
  left`. Shown in Settings and in the expanded notch goal row.

### Changed
- The **pinned goal's pin is now red** (Settings card + notch row).

## [1.1.2] — 2026-07-06

### Added
- **Master show/hide toggles** for System Stats and Claude Usage in the notch
  (matching Tasks, Goals, File Tray).
- **Goals quick-log in Settings** — add a contribution (amount + label) to a goal
  without leaving Settings; progress and the breakdown update live.
- **Task initials in the compact cue** — a tight monogram (e.g. "MXN Wallet KYC
  Integration" → "MWKI") instead of a title truncated to nothing.

### Changed
- **Tab strip moved into the wings beside the notch** — a 3-glyph window
  (prev · active · next) to the left of the camera, battery to the right, with
  the strip sharing the active view's background so it reads as one surface.
- **Swipe-to-cycle works in every idle mode** (not just Auto); scrub a track by
  dragging the scrubber. Goals now appears in the swipe carousel when enabled.
- **Goal progress polish** — green progress ring/bar, light-green percentage,
  animated fill + rolling number, and a wider compact cue so the percentage
  (up to 100%) clears the notch.
- Trimmed expanded-panel horizontal padding by ~⅓ for more content width.

## [1.1.1] — 2026-07-06

### Fixed
- **Notch tab bar visibility.** The expanded-notch tab strip no longer hides
  behind the hardware notch. It now shows a compact three-glyph window on the
  left — previous · active · next, active highlighted — with the battery
  percentage on the right, sitting just below the notch. Tapping a neighbour
  slides the window so every page stays reachable.
- **Seamless tab-bar background.** The strip now shares the active view's
  background — plain black views stay black, and Now Playing's album-art glow
  now flows up through the strip so it reads as one surface.

## [1.1.0] — 2026-07-06

A big feature release: the notch gains a task manager, a goals tracker, and a
tab bar for navigating activities — plus iCloud sync and polish.

### Added
- **Tasks** — a glanceable to-do checklist in the notch. Quick-add and check
  off from the notch; full management in Settings (add / rename / delete /
  clear). Your next task rests in the notch and auto-hides when the list is
  clear. Completing a task strikes it through, then it vanishes.
- **Subtasks** — each task can hold an ordered checklist of subtasks with a
  `done/total` progress badge. Checking the last subtask auto-completes the
  parent (with a manual-complete override); completion is cancellable if you
  un-check within the strike-through window.
- **Link-aware notes** — each task can carry free-text notes; URLs are
  auto-detected and shown as clickable domain chips that open in your browser.
- **Goals** — a savings / progress tracker in the notch: define goals with a
  target and deadline, log contributions, and see pace (ahead / behind /
  on-track / overdue). Pin a goal to rest in the idle notch; completed goals
  archive.
- **Notch tab bar** — an app-bar-style strip atop the expanded notch for
  navigating between live activities, with per-activity glyphs. Toggle in
  Settings.
- **iCloud sync** — tasks (and goals) sync two-way across your Macs via iCloud
  when enabled.

### Changed / Fixed
- Claude Usage: proper cost formatting (grouping + compact notch cue), fixed
  session/weekly windows that read `$0` (fractional-second timestamp parsing),
  and widened the panel so the header clears the notch.
- Removed the unused Lock Screen settings entry.
- Added the project's first automated test target (`NotchlessTests`) with unit
  coverage for the task/goal stores and link detection.

## [1.0.0] — 2026-07-06

Initial release: the Dynamic-Island-style notch replica with Now Playing,
Calendar, Battery, System Stats, Claude Usage, Dictation, File Tray, Timer,
Clipboard, and the privacy indicator.
