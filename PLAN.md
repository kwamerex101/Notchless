# Dynamic Island for Mac — Full Replica Build Plan (Alcove clone)

Source research: frame-by-frame analysis of Ali Nasser's video (7:50–9:45, ~120 frames at 1fps
plus 495 frames at 15fps around every animated transition) and the tryalcove.com marketing site
shown in the video (Alcove v1.7.2).

## 0. Reference materials (in this repo)

- `references/alcove_segment.mp4` — the full 2-minute Alcove segment (1080p). **Primary animation
  reference — play it side-by-side when tuning springs.**
- `references/video-frames/f_001–f_120.jpg` — 1 fps over the whole segment (state inventory).
  Key frames: f_021/f_025/f_033/f_039 (Sound/Display HUDs), f_029 (calendar, notch display),
  f_048/f_054 (idle now-playing compact), f_051 (expanded player), f_063 (calendar on simulated
  notch), f_069 (right-click menu), f_071–f_086 (settings window, all panes/pickers),
  f_077 (Duo expanded), f_089/f_093 (tryalcove.com hero + FAQ).
- `references/bursts/` — 15 fps bursts: `hud_*` (18–32s, Sound/Display HUDs), `media_*` (48–56s,
  expanded player), `cal_*` (59–65s, calendar on external display), `duo_*` (74–79s, Duo).

Findings from the 15 fps pass (beyond the 1 fps inventory):
- **Marquee titles**: long track titles scroll horizontally (leftward, ~15–20 pt/s, seamless loop)
  in the expanded player — visible across consecutive `media_028–038` frames.
- **Visualizer** animates per-frame (fluid at 15 fps+), both in compact and expanded states.
- **HUD bar animates live** during key-repeat — the fill level springs to each new value while the
  HUD stays open (`hud_025–045`).
- **Collapse endpoint**: with no media playing, the HUD collapses back to the *bare physical
  notch*, not a widened idle state (`hud_150`).
- **Timing limits**: the YouTube edit cuts mid-morph in places (verified via per-frame luma
  analysis — a hard cut at ~25.2s), so exact morph durations can't be measured from this video.
  Spring parameters in §3 are estimates; tune them side-by-side against `alcove_segment.mp4`.

Goal: a 1:1 functional + visual replica of Alcove — same features, layout, animations, and
settings — as a private learning/base project. (Ship it later under your own name, icon, and
branding: cloning *functionality and layout* is fine; reusing the "Alcove" name, logo, or their
marketing assets is not.)

---

## 1. Feature inventory (everything observed)

### 1.1 Notch states (the core state machine)

| State | Trigger | What's shown |
|---|---|---|
| **Hidden/Bare** | Nothing active | Window is invisible; physical notch only |
| **Idle-compact** | Media playing, mouse away | Notch grows ~40–60 px wider than physical notch; ~20 px album-art thumbnail on the **left** edge, 4-bar animated audio **visualizer** on the right edge; black fill, rounded bottom corners |
| **HUD (Sound)** | Volume key / volume change | Notch expands **leftward + slightly down**: speaker icon + label "Sound" on the left, white horizontal progress bar on the right. System OSD is suppressed. Bar animates with the keypress |
| **HUD (Display)** | Brightness key | Same layout: sun icon + "Display" label + white bar |
| **Expanded — Now Playing** | Hover/click on notch while media active | Large panel (~480×230): album art (rounded ~12 px) top-left; **title + artist/channel** beside it (long titles scroll marquee-style); visualizer bars top-right; scrubber row (elapsed `0:30` — draggable progress bar — remaining `-3:04`); transport row: **shuffle, previous, play/pause (large, in a highlighted circle), next, output-device picker** |
| **Expanded — Calendar** | One click on notch (calendar mode) | Panel (~450×260): left column — weekday in red caps ("WED"), huge date number ("29"), weather (icon + "Cloudy"), "No events today" + gray "Your day is clear" (or the next meetings list); right column — mini month grid: `M T W T F S S` header, month label in red top-right ("APR"/"MAY"), today circled in red/pink, weekends + adjacent-month days dimmed |
| **Expanded — Duo** | Duo idle-activity mode | Wide two-column panel: Now Playing (art, title, artist, prev/play/next) on the **left** + date/events list (colored event rows, e.g. "May Day", "Erster Mai") on the **right** |
| **Simulated notch** | Non-notch Mac / external display | Identical black notch pill drawn at top-center of the display; all states above work in it (frames showed idle art+visualizer and full calendar on an external display) |

Also on tryalcove.com and in settings (not fully demoed in video):
- **Lock Screen live activity** — big clock "16:38", date "Fri, 1 May", Focus name ("Work"), temperature ("24°") shown around the notch on the lock screen.
- **Notifications** (transient notch expansions): **Battery** (charge state), **Connectivity** (device connect, e.g. AirPods), **Focus** (mode changes), **Display**, **Sound**.
- **File Tray** — marked "Soon" in v1.7 (drag-and-drop file shelf in the notch). Optional/last.

### 1.2 Settings window (fully visible in frames — replicate exactly)

Window: light, wallpaper-tinted translucent material; sidebar + content pane; traffic lights top-left; header icon + "General" title.

**Sidebar** (colored rounded-square icons, iOS-style):
- General (gear)
- **Notifications**: Battery (orange bolt), Connectivity (green headphones), Focus (indigo moon), Display (purple sun), Sound (purple speaker)
- **Live Activities**: Now Playing (red play), Calendar (red calendar), File Tray (gray tray + "Soon" capsule badge), Lock Screen (black lock)
- **Alcove**: License (teal check-seal), About (gray info)

**General pane** (top→bottom, each row in a rounded card with a green iOS toggle):
1. Launch at login — ON
2. Sync settings via iCloud — ON
3. Hide in fullscreen — ON
4. Hide in mission control — ON
5. Hide from screen capture — OFF
6. **Force simulated notch** — toggle + 3-card segmented picker: `Built-in display` / `Main display` (selected: mint outline + tint) / `Active display`, each with a monitor glyph
7. **Idle Activity** section: "Most Recent" row (clock icon + toggle), then 4-card picker: `None` (⊘) / `Playing` (play icon, pink card) / `Calendar` (calendar icon, pink card) / `Duo` (combined icon) — selected card gets mint border
8. "Force enable activity" — toggle (appears when Duo selected)
9. **Behaviour** section: Progressive blur — ON; Haptic feedback — OFF

**Right-click menu on the notch** (small translucent popover, left-aligned under notch):
`Version 1.7.2` (dimmed) / `Settings… ⌘,` / divider / `Quit Alcove ⌘Q`

### 1.3 Animation & feel (the actual product)

- Every state change is a **spring morph of the black shape itself** (notch grows/shrinks; contents fade+scale in). No hard cuts, no separate windows visually.
- Notch shape: top corners square (flush with screen edge), **bottom corners rounded**, plus small **inward-curving fillets** where the shape meets the menu bar (like the real notch / iOS Dynamic Island).
- HUD expansion is **asymmetric**: label slides out to the left edge while the bar appears on the right; collapse reverses it.
- **Progressive blur** behind expanded panels (content behind top of screen blurs, strongest at top, fading downward) — toggleable.
- **Haptic feedback** on open/close/scrub (Force Touch trackpads) — toggleable.
- Springs look like `response ≈ 0.35–0.45, dampingFraction ≈ 0.7–0.8` — snappy with a slight overshoot.
- Hover grows the notch slightly before click ("magnetic" feel); mouse-away collapses after a short delay.

### 1.4 Commercial shell (replicate the mechanics, not the brand)

- One-time purchase **$13.99–$15**, **72 h free trial**, trial reset on request, license recovery, device management ("remove a device"), future updates included, "no data collection" stance.

---

## 2. Tech stack

| Concern | Choice |
|---|---|
| Language/UI | **Swift 6 + SwiftUI** (macOS 14+ target; AppKit interop where needed) |
| Notch window | Borderless, non-activating **NSPanel** (`.nonactivatingPanel`), `level = .statusBar + 1`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, transparent background, `hasShadow = false` (shadow drawn in SwiftUI) |
| Notch geometry | `NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` to get exact physical notch rect; hard-coded default (200×32 pt @ menu-bar height) for simulated notch |
| Now Playing | **MediaRemote** private framework via the **mediaremote-adapter** technique (github.com/ungive/mediaremote-adapter) — required on macOS 15.4+ where raw MediaRemote calls are entitlement-gated. Fallback: AppleScript for Music/Spotify |
| Audio visualizer | Tap system audio is not needed — animate bars from `MRMediaRemote` playback state + random smoothing (Alcove's bars are decorative), or `AVAudioEngine` tap on default output via aggregate device (v2) |
| Volume watch/set | CoreAudio (`AudioObjectAddPropertyListenerBlock` on default output device, `kAudioDevicePropertyVolumeScalar`) |
| Brightness watch/set | Private `DisplayServices` (`DisplayServicesGetBrightness/SetBrightness`) + `CGDisplayStream` fallback; media-key events via `CGEventTap` on `NX_SYSDEFINED` (needs Accessibility permission) |
| Suppress system HUD | Kill/neuter `OSDUIHelper` trick (launchctl unload or SIGSTOP approach used by community notch apps) — degrade gracefully if it fails |
| Calendar | **EventKit** (`EKEventStore`) — full-access prompt; next-meetings list + month grid |
| Weather | **WeatherKit** (needs paid dev account) or **Open-Meteo** free API + CoreLocation |
| Battery | IOKit power sources (`IOPSNotificationCreateRunLoopSource`) |
| Connectivity | IOBluetooth device connect/disconnect notifications (AirPods battery via Apple-specific L2CAP/`IOBluetoothDevice` battery props) |
| Focus | Read `~/Library/DoNotDisturb/DB/Assertions.json` (needs Full Disk Access) or private `DoNotDisturbServer` — v2, ship behind a toggle |
| Lock screen activity | Window at `CGShieldingWindowLevel()` + `canBecomeVisibleWithoutLogin`; verify feasibility early (spike) |
| Haptics | `NSHapticFeedbackManager` |
| Launch at login | `SMAppService.mainApp` |
| iCloud sync | `NSUbiquitousKeyValueStore` mirroring `UserDefaults` |
| Screen-capture hiding | `NSWindow.sharingType = .none` |
| Licensing/trial (last) | Keygen/LemonSqueezy/Paddle + local trial clock |

**Reference codebases** (read, don't copy verbatim): `TheBoredTeam/boring.notch` (MIT — closest OSS analog), `MrKai77/DynamicNotchKit` (notch-shaped window + animations), `ungive/mediaremote-adapter` (now-playing on 15.4+).

---

## 3. Design system (from frames)

- **Notch black**: pure `#000000` (must match physical notch exactly — any off-black is visible).
- **Panel corner radius**: bottom ~24 pt expanded, ~10 pt compact; top corners 0 (flush) + fillet curves outward at the top edges.
- **Accent red/pink** (calendar, selected day, weekday label): ~`#FF375F` (Apple systemPink).
- **HUD bar**: white rounded-cap bar on dim gray track, right-aligned, ~140 pt wide, ~6 pt tall.
- **Typography**: SF Pro. Big date ≈ 40 pt bold; weekday/month label ≈ 11 pt bold, tracking +0.5, red; body 13 pt; secondary text 60 % white.
- **Settings tint**: window material tinted by wallpaper (mint in video); toggles = system green; selection = mint `#5ED5C0`-ish border + 10 % fill.
- **Springs**: `spring(response: 0.4, dampingFraction: 0.75)` default; scrubber/dial interactions interactive-spring.

---

## 4. Build phases

Each phase ends with a runnable, demoable state. Test on notch + non-notch displays throughout.

### Phase 0 — Project scaffold ✅ DONE
Built: XcodeGen `project.yml` → `DynamicIsland.xcodeproj`, SwiftUI app, `LSUIElement`
(menu-bar-only, no Dock icon), macOS 14+ target, Swift 5 language mode (flip to 6 in hardening),
no sandbox. `xcodebuild` green.
- Xcode project `DynamicIsland`, SwiftUI app, menu-bar-only (`LSUIElement = true`), no Dock icon.
- Targets macOS 14+. Git init. SwiftLint/SwiftFormat.
- **Deliverable**: app runs with empty status item.

### Phase 1 — The notch window ✅ DONE
Built: `NotchPanel` (borderless non-activating transparent `NSPanel`, `.statusBar` level,
click-through, all-spaces); `NotchGeometry` (real notch rect from `auxiliaryTopLeft/RightArea` +
`safeAreaInsets`, simulated fallback); `NotchShape` (animatable flared-top / rounded-bottom
silhouette); `NotchRootView` + `NotchViewModel` interpolate size on a spring; `AppDelegate`
positions the panel flush to screen top, centred on the notch, and repositions on
`didChangeScreenParameters`. Menu-bar `DebugMenu` slider morphs it. Verified: builds, launches
without crashing, expanded shape renders below the notch. (Multi-display = Phase 9.)
- `NotchPanel: NSPanel` positioned over the physical notch (from `safeAreaInsets`/auxiliary areas), spanning top-center, click-through except over the drawn shape.
- `NotchShape: Shape` — parametric width/height/bottom-radius with top fillets.
- Multi-display handling: one panel per screen; simulated notch rect on displays without one.
- Screen-change observers (`NSApplication.didChangeScreenParametersNotification`).
- **Deliverable**: invisible black shape perfectly overlaying the real notch; a debug slider morphs its size with a spring and the shape stays pixel-flush.

### Phase 2 — State machine + hover interactions ✅ DONE
Built: `NotchState` (activity / HUD / notification / interaction / resolved `NotchContent`),
`SettingsStore` (all observed prefs, UserDefaults + iCloud KVS), `NotchViewModel` priority resolver
(HUD > notification > expanded > idle > bare) with hover-grow, click-expand, grace-delay collapse,
HUD/notification auto-dismiss; `NotchHostingView` scopes hit-testing to the shape so the rest stays
click-through; right-click menu (Version / Settings / Quit). Builds + runs.

### Phase 2 (legacy heading) — State machine + hover interactions
- `NotchViewModel` (`@Observable`): `.bare, .idle(activity), .hud(kind), .expanded(mode)` with priority rules (HUD > expanded > idle) and auto-collapse timers.
- `NSTrackingArea`/global mouse monitor: hover-grow, click-to-expand, mouse-exit collapse (with ~0.3 s grace).
- Right-click → popover menu: Version / Settings… ⌘, / Quit ⌘Q.
- Haptic hooks on open/close.
- **Deliverable**: click the notch → an empty black panel springs open; click away → collapses. Feels "magnetic".

### Phase 3 — Sound & Display HUDs (2–3 days)
- CoreAudio listener for volume/mute; `CGEventTap` for brightness keys; DisplayServices for brightness value.
- Suppress the system OSD (OSDUIHelper trick) with graceful fallback.
- HUD view: icon + "Sound"/"Display" label sliding out left, white bar right, exact asymmetric morph from the frames; live-updates while keys repeat; collapses ~1.5 s after last change.
- **Deliverable**: pressing volume/brightness keys shows *only* our notch HUD, buttery morph in/out.

### Phase 4 — Now Playing (3–4 days)
- Integrate mediaremote-adapter: now-playing info (title, artist, artwork, elapsed/duration, playback rate, bundle id) + commands (play/pause/next/prev/seek/shuffle).
- Idle-compact state: artwork sliver left + 4-bar visualizer right (animate from playback state).
- Expanded player: full layout from §1.1 including draggable scrubber (seek on release), shuffle, output-picker button (v1: opens Sound settings; v2: real route picking via CoreAudio default-device switch).
- Works with Music, Spotify, Safari/Chrome YouTube (all come through MediaRemote).
- **Deliverable**: play YouTube in Safari → art + visualizer appear; hover → full player; controls all work.

### Phase 5 — Calendar + weather (2–3 days)
- EventKit: today's remaining events; next-meeting line ("No events today / Your day is clear" empty state).
- Month grid component (M-first week, dimmed weekends/other days, red today circle, red month label).
- Weather via Open-Meteo + CoreLocation (icon + condition text).
- One-click open per the video; day-cell click could show that day's events (matches "MON 11 / No events / This day is clear" frame).
- **Deliverable**: calendar panel identical to frames, real data.

### Phase 6 — Idle activities & Duo (1–2 days)
- Settings-driven idle mode: None / Playing / Calendar / Duo / "Most Recent".
- Duo expanded layout: player left + date/events right (event rows with colored calendar dots).
- "Force enable activity" behavior (show even when nothing playing/no events).
- **Deliverable**: all four idle modes switchable and correct.

### Phase 7 — Settings window (2–3 days)
- SwiftUI window replicating §1.2 exactly: sidebar sections/icons/"Soon" badge, card rows, toggles, the two segmented card-pickers, Behaviour section.
- Wire every toggle: launch-at-login (SMAppService), hide-in-fullscreen (watch active app fullscreen state), hide-in-Mission-Control (private CGS space type or window-level tricks — best-effort), hide-from-screen-capture (`sharingType`), simulated-notch force + display choice, progressive blur, haptics.
- iCloud sync via `NSUbiquitousKeyValueStore`.
- **Deliverable**: settings window indistinguishable from the frames; every switch does something real.

### Phase 8 — Notifications: Battery, Connectivity, Focus (2–3 days)
- Battery: IOKit events → transient notch expansion (bolt icon + %) on plug/unplug/low.
- Connectivity: Bluetooth connect/disconnect → device name + battery.
- Focus: mode change → icon + name (behind a toggle; needs Full Disk Access).
- Shared "transient notification" presentation with per-category enable toggles (the sidebar's Notifications section).
- **Deliverable**: plugging in / connecting AirPods pops the notch like the real app.

### Phase 9 — Simulated notch & external displays (1–2 days)
- Force-simulated-notch on Built-in/Main/Active display per settings; draw the full notch pill on notchless screens (the video demos this on an external monitor).
- Menu-bar-height differences, scaling, and hot-plug handled.
- **Deliverable**: full experience on an external display.

### Phase 10 — Progressive blur + polish pass (2–3 days)
- Progressive blur behind expanded panels (private `CAFilter`/variable-blur layer, or gradient-masked `NSVisualEffectView` stack).
- Frame-by-frame animation comparison against the reference video; tune springs, timings, hover thresholds, shadows.
- Performance: 120 Hz ProMotion smoothness, <1 % idle CPU (pause visualizer timers when hidden), memory soak.
- **Deliverable**: side-by-side with the video is indistinguishable.

### Phase 11 — Lock Screen live activity (spike + build, 2–4 days, risky)
- Spike: window at shielding level visible on lock screen showing clock/date/Focus/temperature (per tryalcove.com hero). If blocked by modern macOS, descope to "screen-saver companion" or drop.

### Phase 12 — Productization (later, after the replica)
- Onboarding, license/trial (72 h, reset, device management), $13.99 one-time via Paddle/LemonSqueezy, Sparkle updates, notarization, your own name/icon/site.

---

## 5. Risks & mitigations

1. **MediaRemote lockdown (macOS 15.4+)** — biggest one. Mitigate with mediaremote-adapter (perl-hosted entitlement approach) and AppleScript fallbacks for Music/Spotify. Decide support floor early.
2. **OSD suppression fragility** — OSDUIHelper tricks can break across macOS updates; always degrade to "both HUDs show" rather than crash.
3. **Brightness private APIs** — DisplayServices works on Apple Silicon builtin displays; external displays need DDC (v2).
4. **Focus detection** requires Full Disk Access — make it optional.
5. **Lock screen windows** may be impossible on current macOS — spike before promising.
6. **Permissions UX**: Accessibility (event tap), Calendar, Location, Bluetooth, Full Disk (optional) — build a permission-request flow early (Phase 3–5) so demos don't stall.
7. **Trademark/IP**: functionality + your own implementation = fine; don't ship the Alcove name/logo/screenshots.

## 6. Suggested project structure

```
DynamicIsland/
  App/                (DynamicIslandApp, AppDelegate, StatusItem)
  NotchWindow/        (NotchPanel, NotchPositioner, ScreenObserver)
  NotchUI/            (NotchShape, NotchRootView, IdleCompactView,
                       HUDView, NowPlayingExpandedView, CalendarExpandedView,
                       DuoView, TransientNotificationView, VisualizerBars,
                       ProgressiveBlur)
  State/              (NotchViewModel, NotchState, ActivityPriority)
  Services/
    MediaRemote/      (adapter bridge, NowPlayingService)
    AudioService      (CoreAudio volume)
    BrightnessService (DisplayServices + event tap)
    OSDSuppressor
    CalendarService   (EventKit)
    WeatherService    (Open-Meteo)
    PowerService      (IOKit battery)
    BluetoothService
    FocusService
    HapticService
  Settings/           (SettingsWindow, SidebarModel, GeneralPane, panes…,
                       SettingsStore + iCloud sync)
  Resources/
```

## 7. Milestone order (what to build first)

`0 → 1 → 2 → 4 → 3 → 5 → 7 → 6 → 8 → 9 → 10 → 11 → 12`

(Now Playing before HUDs if you want the wow-demo sooner; HUDs before calendar because they define the morph language. ~4–6 weeks of focused evenings for a faithful replica through Phase 10.)
