# Notch Tasks (Todos) — Design

**Date:** 2026-07-06
**Status:** Approved for planning

## Summary

A lightweight, glanceable checklist that lives in the notch. You quick-add and
check off tasks directly in the notch, and manage the full list in Settings.
When you have open tasks, the idle notch shows your next one; when the list is
empty, the activity disappears entirely. Scope is deliberately minimal — a pure
checklist, not a project manager.

## Goals & non-goals

**Goals**
- Ambient, always-present "what's my next task" cue in the notch.
- Quick-add and check-off from the notch without opening Settings.
- Full list management (add / edit / reorder / delete / clear) in Settings.
- Self-contained: no permissions, no external dependencies, matches existing
  codebase conventions.

**Non-goals (v1)**
- Due dates, reminders/notifications, priority flags, tags, projects, subtasks.
- Completed-task history (completed tasks vanish, nothing accumulates).
- Apple Reminders / EventKit integration.

## Decisions (from brainstorming)

- **Interaction model:** both — quick-add + check-off in the notch, full
  management in Settings.
- **Compact cue:** next task only, auto-hiding when the list is empty.
- **Task richness:** pure checklist — title + done state only. Order = priority
  (drag to reorder). No due dates in v1.
- **Completion behavior:** brief strike-through (~0.9s), then the task
  auto-removes. Same end state as immediate removal, but with a satisfying,
  mis-tap-guarding confirmation.
- **Storage approach:** native lightweight store (own `TodoStore` + JSON in
  `UserDefaults`, iCloud-mirrored). Chosen over EventKit (permission + scope
  creep) and a plain-text file (worse fit for reorder/animation/iCloud).

## Architecture

The feature maps 1:1 onto the existing activity pattern (Timer/Clipboard are the
closest analogs): a dedicated store + a `NotchActivity` case + a compact view +
an expanded view + a Settings pane. Only the enable toggle lives in
`SettingsStore`; the task list lives in its own store, exactly as `FileTrayStore`
holds the file-tray items rather than putting them in `SettingsStore`.

### Data model

```swift
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool       // set true briefly during strike-through, then removed
    var createdAt: Date    // default ordering + stable sort key
}
```

### TodoStore (new `ObservableObject`, mirrors `FileTrayStore`)

- `@Published private(set) var items: [Todo]` — open tasks only, in display order.
- `add(_ title: String)` — appends a task; rejects empty/whitespace-only titles.
- `complete(_ id: UUID)` — sets `isDone = true`, then removes the task after
  ~0.9s (the strike-through-then-vanish behavior).
- `move(from: IndexSet, to: Int)` — drag-to-reorder (order = priority).
- `remove(_ id: UUID)` / `clear()` — for Settings management.
- `var next: Todo? { items.first }` — what the compact cue shows.
- **Persistence:** encodes `items` to JSON under one `UserDefaults` key; mirrored
  to `NSUbiquitousKeyValueStore` when `SettingsStore.syncViaICloud` is on. Loaded
  on init. Decode failure / missing data falls back to an empty list.

Both the Settings pane and the notch expanded view read/write this single
`TodoStore` instance, so edits in one reflect live in the other.

## Notch presentation

### Activity wiring
- Add `case todos` to `NotchActivity` (parallels `.timer` / `.clipboard`).
- Handle `.todos` in `NotchContent.idle` / `.expanded` resolution.

### Compact / idle cue — `TodoCompactView`
- Shows `☐ <next.title>`: an SF Symbol `circle` checkbox + truncated title
  (tail-truncate or reuse `MarqueeText`).
- **Auto-hide:** when `store.items.isEmpty`, the activity resolves to nothing.
  Under `.auto` idle mode it simply doesn't appear; under an explicit `.todos`
  idle pick, an empty list falls back to `.bare`.
- Tapping the checkbox completes the top task inline (strike-through → vanish),
  i.e. check-off without expanding.

### Expanded view — `TodoExpandedView`
- Scrollable list of rows: tap circle → complete (animated strike-through, then
  row removes); drag handle → reorder.
- **Quick-add** row at the bottom: text field + return-to-add. Auto-focus on
  expand so you can expand-and-type.
- Header: "Tasks · N left".
- Empty state: light "All clear ✓ — add a task" prompt with the quick-add field.

### Completion animation
On `complete()`, the row renders `strikethrough` + dims for ~0.9s (matched to the
store's removal delay), then SwiftUI's list diff animates removal. Identical
visual whether triggered from the compact cue or an expanded row.

## Settings — `TodosPane`

Follows the `FeaturePanes` / `GeneralPane` layout; added to `SettingsView`'s
sidebar (icon: `checklist`).

- **Enable Tasks** toggle → new `todosEnabled: Bool` in `SettingsStore`
  (registered default `true`, persisted + iCloud-mirrored, exactly like
  `fileTrayEnabled`). Gates whether the activity appears.
- **Manage list:** the full task list, editable — add (text field), edit title
  inline, delete (swipe / minus button), drag-to-reorder.
- **Clear all** button (with confirm) → `store.clear()`.
- No "clear completed" — completed tasks vanish, so nothing accumulates.

## Edge cases

- Empty / whitespace title → rejected on add.
- Long titles → truncate/marquee in compact; wrap-to-2-lines cap in
  expanded/Settings.
- Rapid completes → each schedules its own removal; store keyed by `id`, so no
  collision.
- Corrupt / absent persisted JSON → decode failure falls back to empty list;
  never crashes.
- iCloud sync race (edit on two machines) → last-writer-wins on the whole array,
  consistent with how `SettingsStore` mirrors scalars.
- Activity disabled mid-use → cue disappears; task data retained.

## Testing

`TodoStore` is pure logic with no UI or permission dependencies, so it is
unit-testable directly:
- add / complete-with-delay / reorder / remove / clear
- empty-title rejection
- JSON round-trip (encode → decode → equal)
- corrupt-data fallback to empty list

Views are thin wrappers over the store and are verified by running the app.

## Files (anticipated)

- `Sources/State/TodoStore.swift` — new store + `Todo` model.
- `Sources/State/NotchState.swift` — add `.todos` to `NotchActivity`.
- `Sources/NotchUI/States/TodoExpandedView.swift` — new expanded view.
- `Sources/NotchUI/States/TodoCompactView.swift` (or fold into `IdleCompactView`)
  — the compact cue.
- `Sources/Settings/TodosPane.swift` — new Settings pane.
- `Sources/Settings/SettingsView.swift` — register the pane in the sidebar.
- `Sources/State/SettingsStore.swift` — add `todosEnabled` pref.
- Content-resolution site (NotchViewModel / wherever activities resolve) —
  handle `.todos` + auto-hide when empty.
