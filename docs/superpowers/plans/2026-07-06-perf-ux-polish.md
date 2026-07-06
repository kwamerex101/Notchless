# Notchless Optimization & Polish Plan (Perf · Energy · UX · Animation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Notchless dramatically cheaper to run 24/7 (CPU, energy, memory) and noticeably more fluid (animations, micro-interactions), while changing **zero user-facing features**. Every task is behavior-preserving except where it fixes an outright bug.

**Why now:** the app grew ~12K LOC in two days. The audit found the structural cost driver: **everything publishes into one god `NotchViewModel`**, so a 90 Hz audio-spectrum stream, a 0.5 s media ticker, and five always-on polling timers each re-evaluate the *entire* notch view tree — even when the notch is bare. Fixing the hot paths first makes every later polish task cheaper to verify.

**Tech Stack:** Swift 5, SwiftUI (macOS 14 target — `@Observable` and `contentTransition` are available), Combine, XcodeGen, XCTest.

## Global Constraints

- Deployment target: macOS 14.0. No newer-only APIs without a fallback.
- **Every build/test command must include `-skipMacroValidation`** (LLM.swift/llama.cpp macro).
- Signing is Manual, Developer ID Application, `DEVELOPMENT_TEAM: 6697RW78AJ` — keep TCC grants stable.
- Regenerate with `xcodegen generate` after any `project.yml` change.
- **No feature removals.** Feature toggles keep their exact semantics; anything gated "off" must still activate live when toggled on (no relaunch).
- One task = one commit. Build + tests green before every commit.

**Build command:**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild -project Notchless.xcodeproj -scheme Notchless \
  -configuration Debug -destination 'platform=macOS' -skipMacroValidation build
```

**Test command:**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild test -project Notchless.xcodeproj -scheme Notchless \
  -destination 'platform=macOS' -skipMacroValidation
```

**Perf verification (used by several tasks):**
```bash
# CPU sample while idle (music paused, notch untouched) — target: ~0% average
top -pid $(pgrep -x Notchless) -l 5 -stats cpu
# Energy: run 60s and compare "Energy Impact" in Activity Monitor before/after
```

---

## Audit Findings (evidence — file:line)

### Performance / Energy (highest cost first)

| # | Finding | Where |
|---|---------|-------|
| P1 | Audio tap publishes `model.musicSpectrum` on **every IO callback (~90+/s)** via `DispatchQueue.main.async`, invalidating the whole `NotchViewModel` → full `NotchRootView` body re-eval per frame | `SystemAudioTap.swift:58-69` |
| P2 | Audio tap + FFT run whenever music plays, even when no visualizer is on screen (notch bare, another carousel page, mirror, etc.) | `AppDelegate.swift:46-53` |
| P3 | Media ticker re-publishes the **whole `nowPlaying` struct (incl. artwork `NSImage`) every 0.5 s** while playing — 2 tree invalidations/sec even when the notch is bare | `MediaController.swift:63-74` |
| P4 | `StatsController` samples CPU + memory + walks `getifaddrs` every 1–2 s **forever**, even with `statsEnabled == false` and nothing visible | `StatsController.swift:19-30`, started unconditionally `AppDelegate.swift:39` |
| P5 | `PrivacyController` enumerates **all CMIO camera devices + CoreAudio** every 1.5 s; timer runs even when the indicator is disabled | `PrivacyController.swift:17-31` |
| P6 | `ClipboardStore` polls the pasteboard every 0.8 s even when `clipboardEnabled == false` (guard sits *after* the poll) | `ClipboardStore.swift:23-39` |
| P7 | `followTimer` fires every 0.35 s forever, but is only needed in `.active` display mode | `AppDelegate.swift:70-72` |
| P8 | `NotchMouseTracker.evaluate()` recomputes `model.content` + `NotchSizing` on **every system-wide mouse move** (global monitor) | `NotchMouseTracker.swift:52-69` |
| P9 | Every `VisualizerBars` instance owns a `Timer.publish(every: 0.11)` that runs even when paused/spectrum-driven; 7 capsules × per-bar `.shadow` at up to 90 Hz | `VisualizerBars.swift:26, 37` |
| P10 | `ClaudeStatsController.parse()` re-reads **every** `.jsonl` transcript (30 days) into a full `String` every 10 min — no per-file caching; ~/.claude can be very large | `ClaudeStatsController.swift:35-84` |
| P11 | `SettingsStore.persist` rewrites **all ~50 keys** + `cloud.synchronize()` on any single change | `SettingsStore.swift:231-292` |
| P12 | Structural: `NotchViewModel` is one `ObservableObject`; `todos`/`goals` `objectWillChange` are piped in (`NotchViewModel.swift:66-71`), so any store mutation repaints everything | `NotchViewModel.swift` |

### Bugs found in passing (fix, they're cheap)

| # | Finding | Where |
|---|---------|-------|
| B1 | Toggling **Hide in fullscreen** at runtime does nothing — the workspace observer is only registered if the setting was on at launch | `EffectsController.swift:31-37` |
| B2 | iCloud settings pull reads **every** key with `cloud.bool(forKey:)` — keys absent from iCloud come back `false`, silently flipping toggles off on any external change | `SettingsStore.swift:297-353` |
| B3 | `GoalStore.save()` uses `try?` — a failed encode silently drops data; no corruption recovery on load | `GoalStore.swift:259-261` |
| B4 | **Notch text fields can never receive keyboard input**: `NotchPanel.canBecomeKey == false` (`NotchPanel.swift:29`), but `TodoExpandedView` quick-add (`:51,88`) and `GoalExpandedView` quick-log (`:97-101`) host `TextField`s — a non-key, non-activating panel routes no key events | `NotchPanel.swift:29` |
| B5 | A second notification never replays its entrance — `@State appeared` is set in `onAppear`, and replacing the `TransientNotification` doesn't change view identity, so the icon-chip scale-in only fires once | `NotificationView.swift:36-51` |
| B6 | Calendar permission-denied is indistinguishable from a free day — denied auth falls back to an empty snapshot → "Your day is clear" | `CalendarExpandedView.swift:9-11` |

### UX / Animation

| # | Finding | Where |
|---|---------|-------|
| U1 | **The content cross-morph transition is dead code**: `.transition(.opacity.combined(with: .scale(0.96, anchor: .top)))` sits on the always-present overlay container; the state swap happens in the `switch` *inside* `contentView(_:)`, so branch changes fall back to default opacity and the scale-from-notch never fires | `NotchRootView.swift:53, 71-109` |
| U2 | Carousel swipes/tab taps have **no directional slide**, no `matchedGeometryEffect` (album art 20 pt compact → 44 pt expanded; goal ring; timer glyph). And `cycleLiveActivity()` mutates `manualActivity` with **no `withAnimation` and no haptic**, while `select()` has both — swipe jump-cuts, tab-tap animates | `NotchViewModel.swift:151-158`, `NotchRootView.swift:113-142` |
| U3 | Hover expands the full panel **instantly** — a mouse-past across the menu bar detonates a 480×178 panel. PLAN §1.3 specifies hover = slight "magnetic" growth, click/dwell = expand. The `.hovering` interaction state already exists but is only consumed by the file-tray path | `NotchViewModel.swift:210-217` |
| U4 | No hover or press feedback on **any** in-notch control (zero `onHover` in NotchUI; everything `.buttonStyle(.plain)`): transport row, tab glyphs, todo checkbox, timer presets, file chips, clipboard rows, output picker | `NowPlayingExpandedView.swift:104-151`, `NotchTabBar.swift:41`, `TodoExpandedView.swift:56` |
| U5 | `.contentTransition(.numericText())` exists exactly **once** (GoalCompactView). Missing on battery %, CPU %, timer, clipboard count, Claude cost, elapsed/remaining time | `IdleCompactView.swift:118-133`, `NotchTabBar.swift:47` |
| U6 | Scrubber: 6 pt hit band, no hover growth/knob, no scrub haptic (PLAN §1.3 asks for it), and 0.5 s elapsed stepping | `NowPlayingExpandedView.swift:73-102` |
| U7 | Motion constants scattered: `morph`/`quickMorph` are good tokens but three different curves exist for the same "ring/bar fill" concept (spring 0.5/0.8, easeInOut 0.5, easeOut 0.3), `NotificationView` uses an off-system damping (0.4/0.6), one bare `withAnimation {}` (GoalExpandedView:115), magic dismiss delays (1.4/2.2/0.35 s) | `BatteryExpandedView.swift:40`, `GoalCompactView.swift:22`, `StatsExpandedView.swift:45` |
| U8 | No `accessibilityReduceMotion` respect anywhere (repeatForever pulses, marquee, visualizer, heartbeat all run unconditionally); VoiceOver labels only on the tab bar — every other icon-only control unlabeled | throughout NotchUI |
| U9 | Todo check-off has no completion micro-animation (compact cue *and* expanded row — icon swap + strikethrough pop in unanimated) | `IdleCompactView.swift:85-92`, `TodoExpandedView.swift:56-66` |
| U10 | Swipe gesture is threshold-fire (accumulate 75 pt → fire once): content never tracks the finger, no rubber-band, no velocity | `NotchHostingView.swift:31-68` |
| U11 | Marquee starts scrolling with no lead-in hold, and `restart()` reassigns a property that may still carry a `repeatForever` animation (unreliable, can ghost-animate) | `MarqueeText.swift:48-55` |
| U12 | `ProgressiveBlur` + panel tint overlays appear via bare `if` with no transition (pop at 0.5 opacity); blur clip uses `RoundedRectangle`, not `NotchShape` (halo mismatch at the fillets) | `NotchRootView.swift:24-47` |
| U13 | Design constants scattered: top padding `notchHeight + 4/6/8/10` across panels, horizontal padding 16/19/24/26/30, chip radii 6/7/8/9, header style copy-pasted with drifting opacity (0.7 vs 0.6) | all expanded views |
| U14 | Pager-dot affordance for the carousel is plumbed (`IdleCompactView.liveActivities`) but never rendered; gestures have zero discoverability | `IdleCompactView.swift:16-17` |

*(Note: `NotchShape` already has animatable radii via `AnimatablePair` — the shape morph architecture is right; the gaps are in content transitions, not the shape.)*

### Architecture

| # | Finding | Where |
|---|---------|-------|
| A1 | Adding an activity touches 6+ files (`NotchActivity`, `NotchSizing`, `IdleCompactView`, `NotchRootView`, `GeneralPane`, `DebugRender`) — mechanical slop that grows per feature | multiple |
| A2 | Hit-test band (`NotchHostingView.hitTest`) and hover band (`NotchMouseTracker.notchRect`) duplicate the same geometry with different pads (4 vs 6) | `NotchHostingView.swift:77-100`, `NotchMouseTracker.swift:52-61` |
| A3 | No XCTest for `NotchViewModel.content` priority resolution, Claude JSONL session blocks, or `GoalStore`. **`GoalSelfTest.swift` already contains a complete Goal test suite** — it just runs as an env-var CLI harness, never in `xcodebuild test`. `neededPerMonth`/`monthsRemaining` (newest catch-up-rate feature) have zero coverage anywhere. The dictation text pipeline (`TextPolish`, `BuiltinTransforms`, `CleanupGate`, `TranscriptHygiene`, `SpokenCommands`, `CorrectionMiner`) is pure logic with zero tests | `Tests/`, `Sources/App/GoalSelfTest.swift` |

### Release hygiene

| # | Finding | Where |
|---|---------|-------|
| H1 | `ENABLE_HARDENED_RUNTIME: NO` in **all** configurations — a Release build from this config can't be notarized; the distributed DMG likely triggers Gatekeeper blocks on other Macs | `project.yml:48` |
| H2 | `GoalSelfTest.swift` (calls `exit()`!) and `DebugRender.swift` compile into the production target, gated only by runtime env vars — a stray env var in a production launch context silently kills the app | `AppDelegate.swift:32,96`, `project.yml:35-36` |
| H3 | No CI: `.github/workflows/` doesn't exist; the test target never runs automatically | `.github/` |
| H4 | No update mechanism (no Sparkle, no "check for updates") — users can't learn about new releases | — |

---

## Phasing (dependency order)

- **Phase 1 — Stop the idle burn** (Tasks 1–6): timers and pollers become event-driven or feature-gated. Pure wins, no visual change.
- **Phase 2 — Kill render churn** (Tasks 7–9): split the high-frequency channels out of the god object. This is the structural fix; do it before animation work so polish is measured against a quiet baseline.
- **Phase 3 — Bug fixes** (Task 10): B1–B6, including the keyboard-input bug that blocks quick-add/quick-log.
- **Phase 4 — Motion & micro-interaction polish** (Tasks 11–16): one motion vocabulary, then apply it.
- **Phase 5 — Deepening, tests, release hygiene** (Tasks 17–20): activity descriptor seam, geometry unification, test back-fill, hardened runtime + CI.

Phases 1–3 are safe to land independently. Phase 4 tasks are independent of each other. Task 20 (release hygiene) can land any time and should land **before the next public DMG**.

---

## Task 1: Gate ClipboardStore, StatsController, PrivacyController on their toggles

**Files:** `Sources/Services/Clipboard/ClipboardStore.swift`, `Sources/Services/Stats/StatsController.swift`, `Sources/Services/Privacy/PrivacyController.swift`, `Sources/App/AppDelegate.swift`

- [ ] Add a shared pattern: each controller gets `func setEnabled(_ on: Bool)` that starts/stops its timer (idempotent). Keep `start()` as `setEnabled(true)` for call-site compatibility.
- [ ] In `AppDelegate` (or the controller's own init), subscribe to the relevant `SettingsStore` publisher (`$clipboardEnabled`, `$statsEnabled`, `$privacyIndicatorEnabled`) with `.removeDuplicates()` and drive `setEnabled`. Toggling **on** must resume live sampling (no relaunch), toggling **off** must invalidate the timer *and* nil out the published model value (`model.stats = nil`, `model.privacy = nil`).
- [ ] `PrivacyController`: also skip the CMIO camera scan entirely when the mic check already returned and both are cached-off? No — keep semantics; only gate on the toggle.
- [ ] Verify: toggle each setting off in Settings → `top` shows the timer stopped (add a temporary `os_log` if needed, remove before commit); toggle on → cue reappears within one interval.
- [ ] Build + tests, commit: `perf: gate clipboard/stats/privacy pollers on their settings toggles`

## Task 2: Make the stats sampler visibility-aware

**Files:** `Sources/Services/Stats/StatsController.swift`, `Sources/State/NotchViewModel.swift`

- [ ] Even when `statsEnabled`, sampling every 1–2 s only matters when stats are *visible* (idle cue is `.stats`, expanded page is `.stats`, or the tab bar is showing). Add a cheap `var statsVisible: Bool` on `NotchViewModel` derived from `content`, and have `StatsController` sample at the user interval when visible, and at a slow keep-warm interval (30 s) when not — so the page opens with fresh-ish data but idle cost is ~0.
- [ ] Keep the existing "tick every 1 s, sample when interval elapsed" slider behavior when visible.
- [ ] Verify: with stats enabled but notch bare, Activity Monitor shows no 1 s wakeups from `getifaddrs` (use `sudo powermetrics --samplers tasks -n 1 | grep -A2 Notchless` for idle wakeups before/after).
- [ ] Build + tests, commit: `perf: sample system stats slowly unless stats are on screen`

## Task 3: Run the follow-screen timer only in Active-display mode

**Files:** `Sources/App/AppDelegate.swift`

- [ ] Start `followTimer` only when `settings.simulatedDisplay == .active`; subscribe to `$simulatedDisplay` to start/stop it live. `.builtIn`/`.main` already reposition via `didChangeScreenParametersNotification`.
- [ ] On switching *to* `.active`, call `repositionIfNeeded()` once immediately.
- [ ] Verify: default (`.main`) config has no 0.35 s timer firing (breakpoint or log); switching modes in Settings still moves the notch.
- [ ] Build + tests, commit: `perf: follow-screen timer only runs in Active-display mode`

## Task 4: Cache the hover band in NotchMouseTracker

**Files:** `Sources/NotchWindow/NotchMouseTracker.swift`, `Sources/State/NotchViewModel.swift`

- [ ] `evaluate()` currently recomputes `model.content` → `NotchSizing` on every global mouse move. Cache `notchRect()` in a stored property; recompute it only when content/sizing actually changes — e.g. the tracker observes `model.objectWillChange` (coalesced via `DispatchQueue.main.async`) or, simpler, `NotchRootView` already computes sizing each body pass: push the current `NotchSizing` onto the model (`model.currentSizing`) from wherever it changes, and let both the tracker and `hitTest` read it.
- [ ] Do NOT change the hover semantics (pad, band position).
- [ ] Verify: hover in/out still expands/collapses exactly as before, including over expanded content; mouse-move CPU (drag cursor in circles for 10 s, watch `top`) drops.
- [ ] Build + tests, commit: `perf: cache notch hover band instead of recomputing per mouse move`

## Task 5: Incremental Claude-stats parsing

**Files:** `Sources/Services/ClaudeStats/ClaudeStatsController.swift`

- [ ] Add a per-file cache: `[path: (mtime: Date, size: Int, aggregate: FileAggregate)]` where `FileAggregate` holds the same sums the parser produces per file (input/output/cache totals, per-day token+cost dicts, entries for windowed costs — entries can stay, they're small). On refresh, re-parse only files whose `(mtime, size)` changed; merge cached aggregates for the rest.
- [ ] Replace `String(contentsOf:)` whole-file reads with line streaming (`FileHandle` + split on `\n`, or keep `enumerateLines` but only for changed files — the cache is the main win).
- [ ] Evict cache entries for files older than the 30-day cutoff.
- [ ] Keep `parse()`'s output identical — same `ClaudeUsageStats` result for the same inputs. The cache lives in the controller (instance state), not statics, so tests can construct fresh ones.
- [ ] Add unit tests: fixture jsonl files in a temp dir → parse → mutate one file → re-parse touches only that file (expose a `parsedFileCount` test hook) and totals stay correct.
- [ ] Verify: first refresh unchanged; second refresh (no transcript changes) completes in ms with no file reads.
- [ ] Build + tests, commit: `perf: incremental per-file caching for Claude usage parsing`

## Task 6: Persist only the changed settings key

**Files:** `Sources/State/SettingsStore.swift`

- [ ] Replace the write-everything `persist(_ changed: Bool)` with `persist(_ key: String, _ value: Any, changed: Bool)` — each `didSet` passes its own key/value. Keep the iCloud mirror per-key; call `cloud.synchronize()` at most once per runloop tick (coalesce with a pending flag) instead of per keystroke.
- [ ] This is mechanical (50 call sites) but shrinks `persist` from 60 lines to 6 and fixes the slider-drag write-storm (`glassIntensity`, `statsRefreshSeconds` write 50 keys per tick today).
- [ ] Verify: change one setting, relaunch — it stuck; all other settings unchanged.
- [ ] Build + tests, commit: `perf: settings persist only the changed key`

## Task 7: Split high-frequency audio state out of NotchViewModel

**Files:** new `Sources/State/AudioLevelsModel.swift`; `Sources/State/NotchViewModel.swift`, `Sources/Services/NowPlaying/SystemAudioTap.swift`, `Sources/Services/Dictation/DictationController.swift` (level/spectrum writers), `Sources/NotchUI/NotchRootView.swift`, `Sources/NotchUI/States/IdleCompactView.swift`, `Sources/NotchUI/States/NowPlayingExpandedView.swift`, `Sources/NotchUI/States/DictationView.swift`, `Sources/NotchUI/Components/VisualizerBars.swift`

This is the single biggest win. Two parts:

- [ ] **Throttle at the source.** In `SystemAudioTap`, coalesce IO-callback publishes to max ~30 Hz: keep the latest bands in a lock-protected slot written by the RT thread; drain it with a repeating 1/30 s main-queue source (started/stopped with the tap). Skip publishing when `max(abs(new-old)) < 0.01`.
- [ ] **Isolate the observers.** Create `final class AudioLevelsModel: ObservableObject` holding `@Published musicSpectrum: [CGFloat]`, `@Published dictationLevel: CGFloat`, `@Published dictationSpectrum: [CGFloat]`. `NotchViewModel` owns it (`let audio = AudioLevelsModel()`) but does **not** republish it. Writers (`SystemAudioTap`, dictation) write to `model.audio`. Views that render bars take `@ObservedObject var audio: AudioLevelsModel` (or `VisualizerBars` gains an optional `@ObservedObject` source) so **only the visualizer subtree** invalidates per frame — `NotchRootView` stops receiving spectrum updates entirely. Pass `model.audio` down instead of `model.musicSpectrum` values.
- [ ] Sizing must not depend on spectrum (it doesn't today — confirm no `content` path reads it).
- [ ] Verify: play music, expanded player open — bars still live and springy; `top` CPU while playing drops sharply vs. baseline (record numbers in the commit message). With the notch bare and music playing, CPU ≈ idle.
- [ ] Build + tests, commit: `perf: 30Hz-throttled spectrum in a dedicated observable, off the god model`

## Task 8: Stop the 0.5 s now-playing republish; make elapsed time view-local

**Files:** `Sources/Services/NowPlaying/MediaController.swift`, `Sources/Services/NowPlaying/NowPlayingInfo.swift`, `Sources/NotchUI/States/NowPlayingExpandedView.swift` (+ `DuoExpandedView` if it shows time)

- [ ] Replace the interpolating ticker with extrapolation data: give `NowPlayingInfo` `elapsedBase: TimeInterval` + `elapsedAt: Date` (set when the provider reports) and a method `elapsed(at now: Date)`. Delete `MediaController.updateTicker` entirely — the model then publishes **only when the provider reports a real change**.
- [ ] In the scrubber/time row, wrap just that row in `TimelineView(.periodic(from: .now, by: 0.5))` (only while `isPlaying` and the view is on screen) and compute displayed elapsed via `info.elapsed(at: context.date)`. SwiftUI now redraws *that row* at 2 Hz only while visible — zero cost when the notch is bare or collapsed.
- [ ] Keep the optimistic play/pause flip in `send(_:)`.
- [ ] Verify: scrubber advances smoothly, pause freezes it, seek still works, and with the notch collapsed there are no periodic invalidations (Instruments → SwiftUI → View Body count).
- [ ] Build + tests, commit: `perf: view-local elapsed-time extrapolation; media publishes only on real changes`

## Task 9: Tame VisualizerBars (timer + shadows) and gate the audio tap on visibility

**Files:** `Sources/NotchUI/Components/VisualizerBars.swift`, `Sources/App/AppDelegate.swift`, `Sources/State/NotchViewModel.swift`

- [ ] Replace the per-instance `Timer.publish(0.11)` with `TimelineView(.periodic(from: .now, by: 0.11), paused:)`-style gating: simplest correct form — keep the timer but make it conditional: `onReceive` of a timer created only when `isPlaying && !useSpectrum` (move the publisher behind `if` via a small wrapper view), so paused/spectrum-driven instances register no timer at all.
- [ ] Replace per-bar `.shadow(...)` (7 shadows/frame) with one `drawingGroup()` on the HStack when a glow color is set, or a single soft glow behind the group. Visual result must match (compare screenshots).
- [ ] Respect `@Environment(\.accessibilityReduceMotion)`: when set, bars render the resting shape (no dance).
- [ ] **Tap visibility gate:** in `AppDelegate`, extend the `playbackObserver` condition: start the tap only when `isPlaying && settings.liveAudioVisualizer && model.visualizerOnScreen` — add `visualizerOnScreen: Bool` on the VM, true when `content` is `.idle(.playing/.auto/...)`, `.expanded(.playing/.duo/...)`, or dictation is recording. Observe content changes via the same publisher chain (`model.objectWillChange` debounced 0.3 s, checking the flag). Tap stops when you swipe to Calendar; restarts when you swipe back. Bars fall back to the decorative dance during the ~0.3 s gap, which is the existing no-spectrum behavior — acceptable and invisible in practice.
- [ ] Verify: visualizer identical while watching it; swiping to another page stops the tap (log once, then remove); paused music leaves zero timers running.
- [ ] Build + tests, commit: `perf: visualizer timers and tap run only when visible and playing`

## Task 10: Bug fixes — keyboard input, fullscreen toggle, iCloud pull, goal persistence, notification replay, calendar denied state

**Files:** `Sources/NotchWindow/NotchPanel.swift`, `Sources/Services/System/EffectsController.swift`, `Sources/State/SettingsStore.swift`, `Sources/State/GoalStore.swift`, `Sources/NotchUI/States/NotificationView.swift`, `Sources/NotchUI/States/CalendarExpandedView.swift` (+ `CalendarController`)

- [ ] **B4 (do this first — it blocks two shipped features):** make the panel able to take keyboard focus when expanded content is editable. `override var canBecomeKey: Bool { true }` on `NotchPanel` is not enough alone for a `.nonactivatingPanel` — also call `panel.makeKey()` when a text field gains focus (e.g. via a `focusNotch()` hook the expanded views call on `@FocusState` change), and resign key on collapse so normal click-through behavior is unaffected. Verify: type into Tasks quick-add and Goals quick-log directly in the notch; verify hover/click-through elsewhere is unchanged and the panel never steals focus while collapsed.
- [ ] **B1:** register the `activeSpaceDidChangeNotification` observer unconditionally in `EffectsController.start()`; the handler already guards on `settings.hideInFullscreen`. Also re-show the panel (`alphaValue = 1`) when the setting is turned off while hidden — subscribe to `$hideInFullscreen`.
- [ ] **B2:** in `cloudChanged`, only apply keys actually present in iCloud: `if cloud.object(forKey: key) != nil { ... }` per key. Extract a small helper (`pullBool(_ keyPath:, _ key:)`) to avoid 50 hand-written ifs, or iterate a key table. Absent keys keep local values.
- [ ] **B3:** `GoalStore.save()`: replace `try?` with `do/catch` + `os_log` on failure; on `load()`, if decode fails, move the corrupt blob to a `goals.backup.<timestamp>` defaults key before starting empty (never silently destroy). Mirror the same pattern in `TodoStore` if it shares it (check `TodoStore.persist`).
- [ ] **B5:** key `NotificationView`'s content on the note (`.id(note.id)` — give `TransientNotification` an `id` if it lacks one) so each notification replays its entrance.
- [ ] **B6:** propagate calendar auth state into `CalendarSnapshot` (e.g. `authDenied: Bool`); `CalendarExpandedView` shows "Calendar access is off — enable in System Settings" with a button (`x-apple.systempreferences:...Privacy_Calendars`) instead of the empty-day copy.
- [ ] Add a regression test for B2's semantics at the store level if injectable (TodoStore has a `CloudKeyValueStore` protocol — reuse the pattern).
- [ ] Build + tests, commit: `fix: notch keyboard input, live fullscreen toggle, partial iCloud pulls, goal persistence, notification replay, calendar denied state`

## Task 11: One motion vocabulary — `NotchMotion` + `NotchDesign`

**Files:** new `Sources/NotchUI/NotchMotion.swift`; sweep of NotchUI + NotchViewModel

- [ ] Create `enum NotchMotion` with the app's complete motion set, replacing scattered constants:
  - `morph` (shape/size, springy: current `0.42/0.78`)
  - `quick` (transients in/out: current `0.3/0.82`)
  - `micro` = `.spring(response: 0.18, dampingFraction: 0.7)` (hover/press/checkbox)
  - `fill` = one curve for **all** ring/bar/level fills (pick `.spring(response: 0.35, dampingFraction: 0.8)`) — today the same concept uses spring 0.5/0.8 (battery ring), easeInOut 0.5 (goal ring/bar), easeOut 0.3 (stats bars)
  - `spectrum` = current `0.16/0.6`
  - plus the dwell/dismiss intervals as constants: `hoverDwell = 0.15`, `collapseGrace = 0.35`, `hudDismiss = 1.4`, `dictationDismiss = 2.2`
  - a helper `NotchMotion.animation(_:reduceMotion:)` that returns opacity-only/short-easeInOut motion when Reduce Motion is on.
- [ ] Replace `NotchViewModel.morph`/`quickMorph` and every ad-hoc spring in NotchUI with the vocabulary. Fix the off-system `NotificationView` spring (0.4/0.6 → `quick`) and the bare `withAnimation { }` in `GoalExpandedView:115`. Existing `morph`/`quick` values stay identical.
- [ ] Add `enum NotchDesign`: `panelTopPadding(metrics:)`, `panelHPadding = 16`, `chipRadius = 8`, `headerFont`/`headerOpacity = 0.7`, shared glow radius — sweep the expanded views' scattered 4/6/8/10-pt top paddings, 16/19/24/26/30 h-paddings, 6/7/8/9 chip radii, and copy-pasted header styles onto them. Values converge to the most common current value per constant (visual delta is a few pt of padding in outlier panels — inspect each before/after).
- [ ] Build + tests, commit: `refactor: NotchMotion + NotchDesign vocabularies replace scattered constants`

## Task 12: Make content transitions real (the current one is dead code)

**Files:** `Sources/NotchUI/NotchRootView.swift`, `Sources/State/NotchViewModel.swift`

`NotchShape` already animates its radii (`AnimatablePair`) and the shape morph is architecturally right — the gap is that **content** swaps don't animate as designed:

- [ ] The `.transition(...)` on the content overlay (`NotchRootView.swift:53`) never fires because the container is always present and only the internal `switch` changes. Key the content on its case identity: derive a stable `contentKey` (hashable case discriminator + activity) and apply `.id(contentKey)` so SwiftUI actually inserts/removes on state change and the `.opacity + .scale(0.96, anchor: .top)` transition runs. Keep `anchor: .top` — content should grow out of the notch.
- [ ] Wrap `cycleLiveActivity()`'s mutation in `withAnimation(NotchMotion.morph)` and give it the same `HapticService.tap()` as `select()` — swipe and tab-tap become one motion.
- [ ] Animate the overlays that currently pop: `.transition(.opacity)` on the `ProgressiveBlur` and panel-tint `if` branches; clip the blur with `NotchShape` (same radii) instead of `RoundedRectangle` so the halo hugs the fillets.
- [ ] Consolidate the size animation: make `NotchSizing` `Equatable` and replace the two `.animation(_, value: width/height)` modifiers with one `.animation(NotchMotion.morph, value: sizing)` so width, height, and radii always share the spring.
- [ ] Verify visually: bare → idle → expanded → HUD → notification; content scales from the notch, nothing pops. Screenshot before/after for the PR.
- [ ] Build + tests, commit: `feel: real content transitions — keyed identity, animated swipe, no popping overlays`

## Task 13: Directional carousel transitions + album-art continuity

**Files:** `Sources/State/NotchViewModel.swift`, `Sources/NotchUI/NotchRootView.swift`, `Sources/NotchUI/States/IdleCompactView.swift`, `Sources/NotchUI/States/NowPlayingExpandedView.swift`

- [ ] Track swipe direction: `cycleLiveActivity()` gains a `direction` (+1 default; the tab-bar `select` computes direction from index delta). Store `lastMove: Int` on the VM.
- [ ] In `NotchRootView`, key the expanded/idle activity content with `.id(activity)` and give it an asymmetric transition: `.transition(.asymmetric(insertion: .move(edge: lastMove > 0 ? .trailing : .leading).combined(with: .opacity), removal: .move(edge: opposite).combined(with: .opacity)))` under `NotchMotion.morph`. State-class changes (idle→expanded, HUD in/out) keep the current fade+scale.
- [ ] Album-art continuity: introduce a `@Namespace` in `NotchRootView` passed to both `IdleCompactView.artwork` and `NowPlayingExpandedView.artwork` with `matchedGeometryEffect(id: "artwork", in: ns)` so the 20 pt sliver grows into the 44 pt tile on expand. If it works cleanly, extend the same pattern to the goal ring and timer glyph (compact ↔ expanded).
- [ ] Tab bar: give the `[prev, active, next]` window stable glyph identities and slide them (offset animation or asymmetric move transitions matching swipe direction) instead of the current in-place re-render; optionally a `matchedGeometryEffect` highlight pill under the active glyph.
- [ ] Respect Reduce Motion (fall back to opacity-only).
- [ ] Discoverability: render the pager dots the idle cue is already plumbed for (`IdleCompactView.liveActivities` is passed in but unused) — small dots under/beside the compact content while hovering, so the carousel is visible without documentation.
- [ ] Verify: swipe left/right slides the correct way; tab taps slide toward the tapped page; hover-expand grows the artwork instead of cross-fading; no clipping artifacts at the notch edges.
- [ ] Build + tests, commit: `feel: directional page transitions and matched-geometry artwork`

## Task 14: Hover intent + interactive feedback everywhere

**Files:** `Sources/State/NotchViewModel.swift`, new `Sources/NotchUI/Components/NotchButtonStyle.swift`, sweep of in-notch controls

- [ ] **Hover intent:** in `hoverChanged(true)`, don't expand immediately — set a `hoverIntent` `DispatchWorkItem` that expands after `NotchMotion.hoverDwell`; cancel it on `hoverChanged(false)`. During the dwell, set `interaction = .hovering` and give it a real visual: a slight magnetic growth (scale 1.02–1.03 anchored `.top`, or a few pt of width via `NotchSizing` — PLAN §1.3's "magnetic" hover). `.hovering` already exists and is currently only consumed by the file-tray path. A quick pass-through no longer yanks the panel open; an intentional hover feels *more* responsive because it acknowledges instantly. Tune dwell 0.15–0.25 s by feel.
- [ ] Keep click-to-expand instant (`tapped()` unchanged). Keep file-tray hover-expand behavior unchanged.
- [ ] **`NotchButtonStyle`:** a `ButtonStyle` with hover highlight (`Circle`/`Capsule` fill `white.opacity(0.12)` fading in via `micro`) and pressed state (`scaleEffect(0.92)` + opacity 0.8). Apply to: transport buttons, output picker label, todo check-off (idle cue + expanded rows), tab-bar glyphs, file-tray actions, timer controls.
- [ ] **Task-check micro-animation (U9):** on check-off (compact cue *and* expanded row), the icon swaps with `.contentTransition(.symbolEffect(.replace))` and pops (scale 1→1.25→1 with `micro`), the strike-through animates in, then the existing removal flow runs. Don't change the pending-removal logic.
- [ ] **File tray feedback:** highlight while drop-targeted (brightened border on the shape + `scaleEffect(1.02)`), and animate chip insert/remove (`.animation(NotchMotion.quick, value: store.items)` + `.transition(.scale.combined(with: .opacity))`).
- [ ] **Play/pause icon:** `.contentTransition(.symbolEffect(.replace))` on the transport toggle; same for the battery glyph swap in the idle cue.
- [ ] Add `.accessibilityLabel` to every icon-only button touched here (play/pause, next, previous, shuffle, output device, check off task, tab glyphs).
- [ ] Verify: every interactive element in the notch visibly reacts to hover and press; VoiceOver reads sensible names.
- [ ] Build + tests, commit: `feel: hover intent dwell, universal hover/press feedback, a11y labels`

## Task 15: Numeric content transitions + scrubber polish

**Files:** `Sources/NotchUI/States/IdleCompactView.swift`, `BatteryExpandedView`, `StatsExpandedView`, `TimerExpandedView`, `ClaudeStatsExpandedView`, `Sources/NotchUI/States/NowPlayingExpandedView.swift`

- [ ] Add `.contentTransition(.numericText())` (with `.animation(NotchMotion.quick, value:)`) to: battery %, CPU %, timer countdown, Claude cost/total, elapsed/remaining time labels. All these are already `monospacedDigit` or should become it.
- [ ] Scrubber: enlarge the hit area (`contentShape` to height ~20 centered on the 6 pt track), grow the track to 8–10 pt on hover (`micro`), show a small knob circle at the fill edge while hovering/scrubbing, animate non-scrubbing progress with `.linear(duration: 0.5)` so the 2 Hz updates read as continuous motion (with Task 8's TimelineView this becomes perfectly smooth), and fire `HapticService.tap()` on scrub-end (PLAN §1.3 calls for scrub haptics; respect the `hapticFeedback` setting).
- [ ] Marquee: add a lead-in hold (~1.5 s) before scrolling and a hold at the loop point, and fix the unreliable restart — `restart()` reassigns `offset` while a `repeatForever` animation may still be attached (can ghost-animate). Rebuild as a `TimelineView`/phase-driven marquee or cancel the old animation (`withAnimation(nil)`/token) before restarting.
- [ ] Verify: digits roll instead of flashing; scrubber is easy to grab and glides; long titles hold, scroll, hold, repeat.
- [ ] Build + tests, commit: `feel: rolling numerals, grabbable scrubber, proper marquee`

## Task 16: HUD & notification entrance polish

**Files:** `Sources/NotchUI/States/HUDView.swift`, `NotificationView.swift` (locate under States/), `Sources/State/NotchViewModel.swift`

- [ ] HUD/notification currently pop via the generic fade+scale. Give them a drop-from-notch entrance: `.transition(.move(edge: .top).combined(with: .opacity))` inside the clip shape, `quick` in / `morph` out — the classic island "bloom".
- [ ] Volume/brightness HUD: animate the level bar with `NotchMotion.fill` and `numericText` on any % label; ensure repeated key presses restart the dismiss timer smoothly (they do — `hudDismiss?.cancel()`), and the bar animates *between* values rather than jumping.
- [ ] Optional (PLAN §1.3 specifies it): asymmetric HUD growth — icon stays at the notch edge, label slides in from the trailing edge (`.transition(.move(edge: .trailing).combined(with: .opacity))`) instead of the static centered HStack.
- [ ] Respect Reduce Motion (opacity only).
- [ ] Verify: volume keys feel fluid; notifications bloom out of the notch and retract into it.
- [ ] Build + tests, commit: `feel: HUD and notification bloom transitions`

## Task 17: Unify notch band geometry (hit-test + hover)

**Files:** `Sources/NotchWindow/NotchHostingView.swift`, `Sources/NotchWindow/NotchMouseTracker.swift`, `Sources/NotchUI/NotchSizing.swift`

- [ ] Add `NotchSizing.band(in:metrics:pad:)` (or a small `NotchBand` helper) producing the interactive rect in a given coordinate space; make `NotchHostingView.hitTest` and `NotchMouseTracker.notchRect` both call it (they currently re-derive it with different pads, 4 vs 6 — keep 4 for hit-test, 6 for hover as explicit parameters, but one formula).
- [ ] This builds on Task 4's cached sizing.
- [ ] Verify: clicks land everywhere on the expanded panel; the dead-zone regression fixed earlier (see git history) stays fixed — click every corner of the expanded panel and the compact wings.
- [ ] Build + tests, commit: `refactor: single source of truth for the interactive notch band`

## Task 18: Activity descriptor seam (stop the 6-file ritual)

**Files:** new `Sources/NotchUI/ActivityDescriptor.swift`; `Sources/NotchUI/NotchSizing.swift`, `IdleCompactView.swift`, `NotchRootView.swift`, `Sources/Settings/GeneralPane.swift`, `Sources/App/DebugRender.swift`

- [ ] Introduce a descriptor that gathers everything currently switch-scattered per `NotchActivity`: `title`, `systemImage`, idle sizing delta, expanded sizing, `@ViewBuilder` compact leading/trailing, `@ViewBuilder` expanded body. One static registry `ActivityDescriptor.for(_ activity:)`.
- [ ] Migrate the existing switches to delegate to the registry **one call-site at a time** (sizing first, then idle views, then expanded routing, then the settings picker labels). Behavior must be pixel-identical — this is a pure deepening refactor so the *next* activity is a one-file add.
- [ ] Keep `NotchActivity` as the enum key (Codable settings depend on its rawValues).
- [ ] Build + tests after each migration step; commit per step or as one: `refactor: ActivityDescriptor registry replaces per-activity switch sprawl`

## Task 19: Test back-fill for the logic that guards everything above

**Files:** `Tests/GoalStoreTests.swift` (new), `Tests/NotchViewModelTests.swift` (new), `Tests/ClaudeStatsParserTests.swift` (new, extends Task 5's), `Tests/DictationPipelineTests.swift` (new)

- [ ] **Port `GoalSelfTest.swift` into real XCTest.** The complete Goal suite already exists (`modelChecks`/`paceChecks`/`formatChecks`/`storeChecks`) but only runs behind a `DI_GOAL_SELFTEST` env var — it never runs in `xcodebuild test`. Port the assertions near-verbatim into `Tests/GoalStoreTests.swift`, then reduce `GoalSelfTest.swift` to a thin wrapper or delete it (see Task 20's `#if DEBUG` gate either way).
- [ ] **`neededPerMonth`/`monthsRemaining`** (catch-up rate — zero coverage anywhere): past deadline clamps to 0 months not negative; target already met → nil; deadline today/passed uses the `max(1, …)` floor (no divide-by-~0); linear math on-pace vs. behind; overdue + unmet returns a sane figure.
- [ ] `NotchViewModel.content` priority resolution: HUD > dictation > notification > mirror > drop-target > expanded > file-tray > idle > bare — table-driven over combinations (init takes `settings:`; use a fresh suite like `NotchTabBarModelTests`). Plus `liveActivities` ordering (privacy first; battery only when plugged/charging), `hasIdleContent` per-case rules, and `cycleLiveActivity` wraparound.
- [ ] Claude session-block windowing (5-hour blocks, floor-to-hour) with synthetic entries around block edges; formatter boundaries (`format` at 999/1k/1M, `moneyCompact` at 10k, `ModelPricing.forModel` substring matching).
- [ ] **Dictation text pipeline** (pure logic, zero coverage, directly shapes user-visible output): `TranscriptHygiene.clean` (marker stripping, whitespace collapse), `BuiltinTransforms.apply` ("c plus plus"→"C++" without double-processing, semver dots, repeat-collapse honoring the `legitimateDoubles` allowlist — "that that" must survive), `CleanupGate.needsCleanup` truth table (fillers as whole words only, ≤3-word punctuation exemption), `TextPolish.apply` (whole-word vocabulary rewrite with stored casing — including a sentence-initial "iPhone"-style term, a likely real bug), `SpokenCommands.apply` ("scratch that" sentence deletion incl. no-punctuation fallback and first-word position).
- [ ] `GoalStore` save/load round-trip + corrupt-payload recovery (Task 10's backup path).
- [ ] Build + tests, commit: `test: goals (ported + catch-up rate), content resolution, session blocks, dictation pipeline`

## Task 20: Release hygiene — hardened runtime, debug-code gating, CI

**Files:** `project.yml`, `Sources/App/GoalSelfTest.swift`, `Sources/App/DebugRender.swift`, `.github/workflows/build.yml` (new)

- [ ] **H1 (blocks distribution):** split `project.yml` configs so Release sets `ENABLE_HARDENED_RUNTIME: YES` (Debug can stay off). Verify a Release build still gets mic/accessibility TCC prompts correctly (hardened runtime needs the `com.apple.security.device.audio-input` entitlement — already present) and that `codesign -dv --verbose=4` + `spctl -a -vvv` pass. Re-cut and notarize the DMG before the next public release.
- [ ] **H2:** wrap `GoalSelfTest.swift` (it calls `exit()`!) and `DebugRender.swift` in `#if DEBUG` (add `SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG` to the Debug config in project.yml if not implied), and guard their `AppDelegate` call sites the same way. A stray env var must never be able to kill or side-effect a production launch.
- [ ] **H3:** add `.github/workflows/build.yml`: macOS runner, `xcodegen generate`, `xcodebuild test … -skipMacroValidation` on push/PR. (Signing: use `CODE_SIGNING_ALLOWED=NO` for CI builds.)
- [ ] **H4 (defer if desired):** decide the update story — Sparkle + GitHub-Releases appcast, or minimally a "Check for Updates…" menu item linking to the releases page.
- [ ] `xcodegen generate`, build + tests, commit: `chore: hardened-runtime release config, DEBUG-gate dev tooling, CI workflow`

---

## Verification gates

After Phase 2 lands, record the headline numbers in `STATUS.md`:

- [ ] **Idle** (notch bare, no music): CPU ≈ 0.0–0.1%, idle wakeups < 30/s (`powermetrics --samplers tasks`).
- [ ] **Music playing, notch bare**: CPU near-idle (tap gated off unless visualizer visible).
- [ ] **Music playing, expanded player**: smooth 30 Hz bars, CPU a fraction of the pre-plan baseline (measure baseline **before Task 1** and note it).
- [ ] **Memory**: steady-state RSS flat over 30 min of playback (no artwork/entry accumulation).
- [ ] Full manual pass: every activity's idle cue + expanded page, swipe both directions, tab taps, file tray drop, dictation start/stop, HUD keys, mirror, todos check-off with subtasks, goals pin — nothing regressed.

## Explicit non-goals (features are untouchable)

- No removal or simplification of any activity, setting, gesture, or pane.
- No change to dictation engines, model downloads, or the Claude cost model.
- No visual redesign — polish tasks refine motion and feedback on the existing design.
- Interactive finger-tracking swipe (U10) is noted but deferred — the threshold-fire gesture works; rebuilding it as an interactive pager is a feature-sized change, not polish.
- Lock-Screen phase and new features stay out of scope. Sparkle integration is optional (Task 20 H4) — the decision is in scope, the integration can be its own follow-up.
