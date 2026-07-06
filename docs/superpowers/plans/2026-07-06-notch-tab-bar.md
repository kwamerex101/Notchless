# Notch Tab Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a slim, tappable tab strip to the top edge of the expanded notch that makes the existing swipe-carousel visible and navigable.

**Architecture:** A new `NotchTabBar` SwiftUI view renders one monochrome SF Symbol per page in `NotchViewModel.carouselActivities`, highlights the active page by brightness, and shows a persistent battery-percentage status on the right. Tapping a tab calls a new `NotchViewModel.select(_:)` that sets the same `manualActivity` the swipe already mutates, so swipe and tap stay in sync. The strip is inserted above the expanded content in `NotchRootView` and its height is reserved so existing expanded views are not clipped.

**Tech Stack:** Swift, SwiftUI, AppKit; XcodeGen + xcodebuild; XCTest.

## Global Constraints

- Build: `xcodegen generate` after adding/removing files, then `xcodebuild -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation build`.
- `-skipMacroValidation` is **required** on every xcodebuild invocation (llama.cpp macro dependency).
- Tests run via: `xcodebuild test -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation -destination 'platform=macOS'`.
- The strip renders **only** when `settings.showTabBar == true` **and** `carouselActivities.count >= 2` **and** the notch is in the `.expanded` content state.
- Active-tab treatment is **brightness only** — no pill, no underline. Active glyph at full opacity; inactive glyphs dimmed.
- All animated state changes use `NotchViewModel.morph`.
- Follow the existing `SettingsStore` flag pattern exactly (@Published + didSet persist, Keys entry, register default, load line, persist tuple).

---

### Task 1: Model logic — `select(_:)` and per-activity tab glyph

**Files:**
- Modify: `Sources/State/NotchState.swift` (add `tabGlyph` to `NotchActivity`)
- Modify: `Sources/State/NotchViewModel.swift` (add `select(_:)`; the `cycleLiveActivity()` block near line 139 is the sibling to mirror)
- Test: `Tests/NotchTabBarModelTests.swift` (create)

**Interfaces:**
- Consumes: existing `NotchViewModel.carouselActivities: [NotchActivity]`, `NotchViewModel.activeExpandedActivity: NotchActivity`, `private var manualActivity`, `settings.hapticFeedback`, `HapticService.tap()`, `Self.morph`.
- Produces:
  - `NotchActivity.tabGlyph: String` — SF Symbol name for every case.
  - `NotchViewModel.select(_ activity: NotchActivity)` — sets `manualActivity = activity` (animated) and fires a haptic when enabled; no-op if `activity` is not in `carouselActivities`.

- [ ] **Step 1: Write the failing test**

Create `Tests/NotchTabBarModelTests.swift`:

```swift
import XCTest
@testable import Notchless

@MainActor
final class NotchTabBarModelTests: XCTestCase {
    /// A model with one live activity (media) so the carousel has ≥2 pages:
    /// [.playing, .calendar, .stats, .claudeUsage].
    private func makeModel() -> NotchViewModel {
        SettingsStore.shared.idleActivity = .auto
        let model = NotchViewModel()
        model.nowPlaying = NowPlayingInfo(
            title: "T", artist: "A", album: nil, artwork: nil,
            isPlaying: true, elapsed: 0, duration: 100,
            bundleIdentifier: nil, appName: nil
        )
        return model
    }

    func test_select_makesActivityTheActiveExpandedPage() {
        let model = makeModel()
        XCTAssertTrue(model.carouselActivities.contains(.stats))
        model.select(.stats)
        XCTAssertEqual(model.activeExpandedActivity, .stats)
    }

    func test_select_ignoresActivityNotInCarousel() {
        let model = makeModel()
        model.select(.stats)                 // valid, becomes active
        XCTAssertFalse(model.carouselActivities.contains(.timer))
        model.select(.timer)                 // invalid → ignored
        XCTAssertEqual(model.activeExpandedActivity, .stats)
    }

    func test_everyActivityHasNonEmptyTabGlyph() {
        for activity in NotchActivity.allCases {
            XCTAssertFalse(activity.tabGlyph.isEmpty, "\(activity) missing glyph")
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation -destination 'platform=macOS'`
Expected: FAIL — `value of type 'NotchActivity' has no member 'tabGlyph'` and `NotchViewModel has no member 'select'`.

- [ ] **Step 3: Add the `tabGlyph` mapping**

In `Sources/State/NotchState.swift`, add to `enum NotchActivity` (after the cases, inside the enum):

```swift
    /// SF Symbol shown for this page in the expanded tab strip.
    var tabGlyph: String {
        switch self {
        case .auto, .none: return "circle"        // never shown as a tab
        case .playing:     return "music.note"
        case .calendar:    return "calendar"
        case .duo:         return "rectangle.split.2x1"
        case .dictation:   return "mic"
        case .battery:     return "battery.75"
        case .stats:       return "speedometer"
        case .timer:       return "timer"
        case .clipboard:   return "doc.on.clipboard"
        case .todos:       return "checklist"
        case .privacy:     return "dot.radiowaves.left.and.right"
        case .claudeUsage: return "sparkle"
        }
    }
```

- [ ] **Step 4: Add the `select(_:)` method**

In `Sources/State/NotchViewModel.swift`, immediately after `cycleLiveActivity()` (ends ~line 146):

```swift
    /// Jumps the carousel straight to `activity` (a tab tap). Mirrors what a
    /// swipe does for one step: sets the manual pick and gives haptic feedback.
    /// Ignored if `activity` isn't a current carousel page.
    func select(_ activity: NotchActivity) {
        guard carouselActivities.contains(activity) else { return }
        withAnimation(Self.morph) { manualActivity = activity }
        if settings.hapticFeedback { HapticService.tap() }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation -destination 'platform=macOS'`
Expected: PASS (all three `NotchTabBarModelTests`).

- [ ] **Step 6: Regenerate project and commit**

```bash
xcodegen generate
git add Sources/State/NotchState.swift Sources/State/NotchViewModel.swift Tests/NotchTabBarModelTests.swift project.yml
git commit -m "feat: add tab-strip model (select + per-activity glyph)"
```

---

### Task 2: `showTabBar` setting and settings toggle

**Files:**
- Modify: `Sources/State/SettingsStore.swift` (@Published property, Keys entry, register default, load line, persist tuple)
- Modify: `Sources/Settings/FeaturePanes.swift` (toggle row next to the existing swipe toggle)

**Interfaces:**
- Consumes: existing `SettingsStore` persistence machinery, `ToggleRow(title:isOn:)`.
- Produces: `SettingsStore.showTabBar: Bool` (default `true`), persisted like every other flag.

- [ ] **Step 1: Add the published property**

In `Sources/State/SettingsStore.swift`, in the "Now Playing / media" group (after `swipeGesturesEnabled`, ~line 76):

```swift
    @Published var showTabBar: Bool { didSet { persist(oldValue != showTabBar) } }
```

- [ ] **Step 2: Register the default**

In the `defaults.register(defaults: [ ... ])` dictionary (after `Keys.swipeGesturesEnabled: true,`, ~line 136):

```swift
            Keys.showTabBar: true,
```

- [ ] **Step 3: Add the Keys entry**

In `private enum Keys` (after `static let swipeGesturesEnabled = "swipeGesturesEnabled"`, ~line 356):

```swift
        static let showTabBar = "showTabBar"
```

- [ ] **Step 4: Load and persist the value**

In the load block (after `swipeGesturesEnabled = defaults.bool(forKey: Keys.swipeGesturesEnabled)`, ~line 184):

```swift
        showTabBar = defaults.bool(forKey: Keys.showTabBar)
```

In the persist tuple list (after `(Keys.swipeGesturesEnabled, swipeGesturesEnabled),`, ~line 241):

```swift
            (Keys.showTabBar, showTabBar),
```

- [ ] **Step 5: Add the settings toggle**

In `Sources/Settings/FeaturePanes.swift`, directly below the existing swipe-gesture / swipe-to-seek rows (the media section around line 115):

```swift
                ToggleRow(title: "Show tab bar in expanded view", isOn: $settings.showTabBar)
                Text("A row of page icons across the top of the expanded notch; tap or swipe to move between pages.")
```

Match the surrounding `Text(...)` modifier style (font/foreground) used by the adjacent description lines in that section.

- [ ] **Step 6: Build to verify it compiles**

```bash
xcodegen generate
xcodebuild -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 7: Commit**

```bash
git add Sources/State/SettingsStore.swift Sources/Settings/FeaturePanes.swift
git commit -m "feat: add showTabBar setting and toggle"
```

---

### Task 3: `NotchTabBar` view component

**Files:**
- Create: `Sources/NotchUI/Components/NotchTabBar.swift`

**Interfaces:**
- Consumes: `NotchActivity.tabGlyph` (Task 1), `BatteryInfo.level: Int`, `NotchMetrics`.
- Produces:
  - `NotchTabBar` view with initializer:
    `NotchTabBar(activities: [NotchActivity], active: NotchActivity, battery: BatteryInfo?, metrics: NotchMetrics, onSelect: @escaping (NotchActivity) -> Void)`
  - `static let NotchTabBar.height: CGFloat = 22` — the reserved strip height (consumed by Task 4).

- [ ] **Step 1: Create the component**

Create `Sources/NotchUI/Components/NotchTabBar.swift`:

```swift
import SwiftUI

/// The slim tab strip along the top of the expanded notch. Left: one monochrome
/// glyph per carousel page (active at full brightness, others dimmed). Right: a
/// persistent battery-percentage status. Tapping a glyph selects that page.
struct NotchTabBar: View {
    let activities: [NotchActivity]
    let active: NotchActivity
    let battery: BatteryInfo?
    let metrics: NotchMetrics
    var onSelect: (NotchActivity) -> Void

    /// Reserved height of the strip; Task 4 grows the panel by this amount.
    static let height: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            ForEach(activities, id: \.self) { activity in
                Image(systemName: activity.tabGlyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(activity == active ? 1.0 : 0.4)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(activity) }
                    .accessibilityLabel(Text(String(describing: activity)))
                    .accessibilityAddTraits(activity == active ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 8)
            if let battery {
                Text("\(battery.level)%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .animation(NotchViewModel.morph, value: active)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodegen generate
xcodebuild -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchUI/Components/NotchTabBar.swift project.yml
git commit -m "feat: add NotchTabBar component"
```

---

### Task 4: Integrate the strip into `NotchRootView` and reserve its height

**Files:**
- Modify: `Sources/NotchUI/NotchRootView.swift`

**Interfaces:**
- Consumes: `NotchTabBar` and `NotchTabBar.height` (Task 3), `NotchViewModel.carouselActivities`, `NotchViewModel.select(_:)` (Task 1), `model.settings.showTabBar` (Task 2), `model.battery`.
- Produces: expanded panel that renders the strip above its content, with panel height grown by `NotchTabBar.height` so existing views are not clipped.

- [ ] **Step 1: Add a visibility helper and extract the expanded body**

In `NotchRootView`, add a computed property (place near `glowColor`, ~line 104):

```swift
    /// The strip shows only in the expanded state, when enabled, and only if
    /// there is more than one page to move between.
    private var tabBarVisible: Bool {
        guard case .expanded = model.content else { return false }
        return model.settings.showTabBar && model.carouselActivities.count >= 2
    }
```

Extract the current `.expanded(activity)` switch body (lines 68–94) into a helper so it can sit under the strip. Add:

```swift
    @ViewBuilder
    private func expandedBody(_ activity: NotchActivity) -> some View {
        switch activity {
        case .playing, .none, .auto:
            NowPlayingExpandedView(info: model.nowPlaying, musicSpectrum: model.musicSpectrum,
                                   metrics: metrics, glow: glowColor, onCommand: onCommand,
                                   onActivateSource: { activateSource(model.nowPlaying?.bundleIdentifier) })
        case .calendar:
            CalendarExpandedView(snapshot: model.calendar, metrics: metrics)
        case .duo:
            DuoExpandedView(info: model.nowPlaying, snapshot: model.calendar,
                            metrics: metrics, onCommand: onCommand)
        case .dictation:
            DictationHintView(metrics: metrics)
        case .battery:
            BatteryExpandedView(battery: model.battery, metrics: metrics)
        case .stats:
            StatsExpandedView(stats: model.stats, metrics: metrics)
        case .timer:
            TimerExpandedView(timer: model.notchTimer, metrics: metrics)
        case .clipboard:
            ClipboardExpandedView(metrics: metrics)
        case .todos:
            TodoExpandedView(metrics: metrics)
        case .privacy:
            PrivacyExpandedView(privacy: model.privacy, metrics: metrics)
        case .claudeUsage:
            ClaudeStatsExpandedView(stats: model.claudeStats, metrics: metrics)
        }
    }
```

- [ ] **Step 2: Render the strip above the expanded body**

Replace the `.expanded(activity)` case inside `contentView(_:)` (the block that currently begins `case let .expanded(activity):` and holds the switch) with:

```swift
        case let .expanded(activity):
            if tabBarVisible {
                VStack(spacing: 0) {
                    NotchTabBar(activities: model.carouselActivities,
                                active: activity,
                                battery: model.battery,
                                metrics: metrics,
                                onSelect: { model.select($0) })
                    expandedBody(activity)
                }
            } else {
                expandedBody(activity)
            }
```

- [ ] **Step 3: Reserve the strip height in the panel geometry**

In `NotchRootView.body`, just after `let sizing = NotchSizing.size(for: content, metrics: metrics)` (~line 13), add:

```swift
        let barExtra = tabBarVisible ? NotchTabBar.height : 0
        let panelHeight = sizing.height + barExtra
```

Then replace the two uses of `sizing.height` inside `body` — the shape's `.frame(width: sizing.width, height: sizing.height)` (~line 20) and the overlay content's `.frame(width: sizing.width, height: sizing.height)` (~line 32) — with `height: panelHeight`. Also update the `.animation(..., value: sizing.height)` call (~line 48) to `value: panelHeight`.

- [ ] **Step 4: Build to verify it compiles**

```bash
xcodegen generate
xcodebuild -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation build
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -project Notchless.xcodeproj -scheme Notchless -skipMacroValidation -destination 'platform=macOS'`
Expected: PASS (Task 1 tests still green; nothing else broken).

- [ ] **Step 6: Manual verification**

Launch the app (`open build/Build/Products/Debug/Notchless.app` after a build, per README) and confirm:
- Expanded notch shows a row of glyphs on the top-left and battery `%` on the top-right.
- The glyph for the current page is bright; the others are dimmed.
- Tapping a glyph switches the page; swiping also moves the highlight — they stay in sync.
- With only one carousel page (e.g. nothing live and info pages absent), the strip does not appear.
- Toggling "Show tab bar in expanded view" off in Settings removes the strip and the panel returns to its prior height.

- [ ] **Step 7: Commit**

```bash
git add Sources/NotchUI/NotchRootView.swift
git commit -m "feat: render tab strip atop the expanded notch"
```

---

## Self-Review

**Spec coverage:**
- Concept / passenger-not-driver → Task 1 (`select` mutates `manualActivity`) + Task 4 (render). ✓
- Top-edge layout, icons left / battery right → Task 3 (`NotchTabBar`) + Task 4 (VStack above body). ✓
- Mirror live carousel → Task 4 passes `model.carouselActivities`. ✓
- Icon mapping table → Task 1 `tabGlyph`. ✓
- Brightness-only active state → Task 3 opacity 1.0 vs 0.4, no pill/underline. ✓
- Tap → `select`, swipe unchanged, haptic → Task 1 + Task 4. ✓
- Battery status slot, hidden when nil → Task 3 `if let battery`. ✓
- `showTabBar` setting default true + toggle → Task 2. ✓
- Show only expanded & ≥2 pages → Task 4 `tabBarVisible`. ✓
- Layout wrinkle / reserve height (spec prefers sizing-aware) → Task 4 Step 3 grows `panelHeight` by `NotchTabBar.height`. ✓
- Testing bullets (glyph count, active match, select sets manualActivity, absent when <2 / off, battery nil) → Task 1 unit tests + Task 4 manual checks. ✓

**Placeholder scan:** No TBD/TODO; all steps show concrete code and exact commands. ✓

**Type consistency:** `NotchTabBar(activities:active:battery:metrics:onSelect:)`, `NotchTabBar.height`, `select(_:)`, `tabGlyph`, `carouselActivities`, `activeExpandedActivity`, `BatteryInfo.level`, `NotchViewModel.morph` used identically across tasks. ✓
