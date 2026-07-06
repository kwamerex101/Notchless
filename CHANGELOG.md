# Changelog

All notable changes to Notchless are documented here.

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
