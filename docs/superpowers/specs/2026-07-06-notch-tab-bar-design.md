# Notch Tab Bar — Design Spec

**Date:** 2026-07-06
**Status:** Approved for planning

## Motivation

The expanded notch already lets the user swipe horizontally between "notch"
pages — the live activities plus the always-available info pages — via
[`NotchViewModel.cycleLiveActivity()`](../../../Sources/State/NotchViewModel.swift)
driven by a two-finger trackpad swipe in
[`NotchHostingView.scrollWheel`](../../../Sources/NotchWindow/NotchHostingView.swift).

The problem: **there is no visual indication that other pages exist.** A new
user can't discover the swipe, and even a power user can't see where they are in
the sequence or jump directly to a page.

Reference: an Alcove-style demo (YouTube Short) shows the expanded notch with a
slim toolbar along its top edge — small monochrome nav glyphs left-aligned, a
persistent battery-percentage status on the right, and the tab body below. This
spec adapts that pattern to make our existing carousel **visible and clickable**.

## Principle

The tab bar is a **passenger, not a driver.** It does not introduce a new
navigation model — it renders the existing carousel and mutates the same state
the swipe already mutates (`manualActivity`). Swipe and tap therefore stay in
perfect sync by construction. The notch stays as calm as it is now: the bar
appears **only in the expanded state**, and **only when there are ≥2 pages**.

## Layout

Mirrors the macOS menu bar (and the reference video):

```
┌────────────────────────────────────────────┐
│  ⌂  🛍                               9% 🔋 │   ← tab strip (top edge)
│                                            │
│            (active tab's content)          │
│                                            │
└────────────────────────────────────────────┘
```

- **Left:** a row of small monochrome SF Symbol glyphs, one per page in
  `carouselActivities`, in carousel order.
- **Right:** a single persistent **battery status slot** showing the current
  percentage (matching the reference frame). This is status, not a tab — it is
  not selectable and does not participate in the carousel.

## Tab → page mapping

The bar **mirrors the live carousel**: one icon per entry in
`NotchViewModel.carouselActivities`. Tabs appear and disappear as live
activities come and go — fully in sync with the current swipe behavior. No fixed
section set, no overflow handling in v1 (the carousel is realistically small;
revisit only if it proves crowded on a narrow notch).

Icon per `NotchActivity` (SF Symbols; tunable):

| Activity     | Glyph                              |
|--------------|------------------------------------|
| playing      | `music.note`                       |
| calendar     | `calendar`                         |
| stats        | `speedometer`                      |
| claudeUsage  | `sparkle`                          |
| timer        | `timer`                            |
| todos        | `checklist`                        |
| battery      | `battery.75`                       |
| fileTray     | `tray`                             |
| dictation    | `mic`                              |
| privacy      | `dot.radiowaves.left.and.right`    |
| duo          | `rectangle.split.2x1`              |

`none` / `auto` never appear as tabs (they are not concrete pages in the
carousel).

## Active-tab styling

**Brightness only — no pill, no underline.** The active tab's glyph renders at
full opacity; inactive glyphs are dimmed (~40% opacity). This is the quietest,
most native treatment and keeps the strip visually silent until scanned. The
transition between active tabs animates with the existing `NotchViewModel.morph`
animation so the highlight glides as the user swipes.

## Interaction

- **Tap a tab** → calls a new `NotchViewModel.select(_ activity:)` method that
  sets `manualActivity = activity` (mirroring what `cycleLiveActivity()` does for
  one step), animated with `Self.morph`.
- **Swipe** → unchanged. The active-brightness highlight simply follows the new
  `manualActivity`.
- **Haptic** → on tap, fire `HapticService.tap()` when `settings.hapticFeedback`
  is enabled, consistent with the hover-to-expand haptic.
- **Battery slot** → reads `model.battery` percentage; hidden if battery info is
  unavailable.

## Settings

Add `SettingsStore.showTabBar: Bool` (default `true`), persisted like every other
feature flag, with a toggle row in the relevant settings pane. When off, the
strip never renders and behavior is exactly as today.

## Components & integration

**New file:** `Sources/NotchUI/Components/NotchTabBar.swift`
- A `View` taking the `NotchViewModel` (or the minimal slice: `carouselActivities`,
  active activity, battery, and a select callback) plus `NotchMetrics`.
- Renders the left glyph row + right battery slot in an `HStack`.

**Integration point:** [`NotchRootView.contentView`](../../../Sources/NotchUI/NotchRootView.swift),
`.expanded` branch. Wrap the expanded content in a `VStack(spacing: 0)`:

```
VStack(spacing: 0) {
    NotchTabBar(...)          // only if settings.showTabBar && carouselActivities.count >= 2
    expandedContentView(activity)
}
```

**Layout wrinkle:** the expanded views (`NowPlayingExpandedView`, `FileTrayView`,
`CalendarExpandedView`, …) currently assume they fill the full panel frame. The
tab strip consumes a small fixed height at the top. Reserve that height so the
existing views are not clipped — either by adding a small top inset to the
expanded content or by having `NotchSizing` account for the strip height when the
bar is shown. The plan should choose one approach and apply it consistently;
`NotchSizing`-aware sizing is preferred so the black shape grows to fit rather
than the content compressing.

## Scope / YAGNI

**In scope (v1):** the tab strip, brightness-only active state, battery status
slot, tap-to-select, `showTabBar` setting, icon mapping.

**Out of scope (v1):** overflow/condensing for many tabs, tab labels or
hover-reveal names, a compact tab hint in the non-expanded/hover state, per-tab
badges, reordering. Revisit only if real usage demands them.

## Testing

- `NotchTabBar` renders exactly `carouselActivities.count` glyphs, in order.
- The active glyph matches the model's current active activity; others dimmed.
- `select(_:)` sets `manualActivity` and the active highlight follows.
- The strip is absent when `carouselActivities.count < 2` or `showTabBar == false`.
- Expanded content is not clipped when the strip is present (sizing reserves its
  height).
- Battery slot hidden when `model.battery == nil`.
