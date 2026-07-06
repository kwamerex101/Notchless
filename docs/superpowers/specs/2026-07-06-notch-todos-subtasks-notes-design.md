# Notch Tasks — Subtasks & Link-Aware Notes — Design

**Date:** 2026-07-06
**Status:** Approved for planning
**Builds on:** [2026-07-06-notch-todos-design.md](2026-07-06-notch-todos-design.md) (the v1 pure checklist, now shipped)

## Summary

Extend the notch task list so each task can carry **subtasks** (a nested
checklist that shows progress on the parent) and **notes** (free text where any
URL becomes a clickable domain chip). The notch stays lean — it only *signals*
subtask progress and the presence of notes/links; all the actual subtask
checking, note editing, and link opening happen in Settings. Deliberately no
network: links are detected and opened, never fetched.

## Goals & non-goals

**Goals**
- Each task gains an ordered list of checkable subtasks.
- The parent shows subtask progress ("2/5") and auto-completes when all subtasks
  are done, with a manual-complete override at any time.
- Each task gains a free-text notes field; URLs in it are auto-detected, shown
  as clickable domain chips (`🔗 github.com`), and open in the browser.
- The notch stays glanceable: read-only progress badge + note/link glyph only.
- All new logic is pure and unit-testable; existing saved tasks keep working
  (backward-compatible persistence).

**Non-goals**
- No rich link previews (no fetching page titles/favicons/thumbnails).
- No nested-deeper hierarchy (subtasks have no sub-subtasks).
- No subtask checking or note editing *in the notch* (Settings only).
- No due dates / priorities / tags (still out of scope from v1).

## Decisions (from brainstorming)

- **Subtask → parent relationship:** hybrid with manual override. Parent shows
  "done/total"; checking the last subtask auto-completes the parent; completing
  the parent manually at any time still works and drops remaining subtasks.
- **Where you interact:** the notch stays lean — a task shows a "2/5" progress
  badge and a note/link glyph. Subtask checking, note editing, and link opening
  happen in **Settings**.
- **Link awareness:** auto-detect URLs in notes, render clickable, and show each
  as a compact domain chip (`🔗 github.com`). No fetching.
- **Subtask completion:** a checked subtask *stays* in the list (struck
  through), so the "done/total" fraction stays stable. Only the parent vanishes.
- **Settings editing UI:** inline disclosure — tap a task's chevron to reveal
  its subtasks + notes editor in place; extract a `TodoRowEditor` subview.

## Architecture

Extends the existing v1 units rather than adding parallel ones: the `Todo`
model grows two fields, `TodoStore` grows subtask/notes methods (with the
auto-complete rule), `TodoExpandedView` rows gain read-only indicators, and
`TodosPane` gains inline disclosure delegating each task's editor to a new
`TodoRowEditor`. A new pure `LinkDetector` helper backs both the notch glyph
and the Settings chips.

### Data model & migration

```swift
struct Subtask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
}

struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var subtasks: [Subtask]   // new
    var notes: String         // new
}
```

Derived on `Todo`:
- `subtaskProgress -> (done: Int, total: Int)` — `total = subtasks.count`,
  `done = subtasks.filter(\.isDone).count`.
- `hasNotes: Bool` — `!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`.
- `allSubtasksDone: Bool` — `!subtasks.isEmpty && subtasks.allSatisfy(\.isDone)`.

**Migration (critical):** v1 tasks are already persisted as JSON without
`subtasks`/`notes`. A plain non-optional field makes `JSONDecoder` throw on that
old data — existing tasks would be lost. `Todo` therefore gets a custom
`init(from decoder:)` that uses `decodeIfPresent(...) ?? []` for `subtasks` and
`decodeIfPresent(...) ?? ""` for `notes` (other fields decoded normally). Old
tasks load with empty subtasks/notes; nothing is lost. Encoding stays synthesized
(or a matching `encode(to:)` if the custom init disables synthesis).

### TodoStore behavior

New methods (all persist via the existing `persist()`, all `@MainActor`):

- `addSubtask(to parentID: UUID, title: String)` — appends a `Subtask`; rejects
  empty/whitespace titles (same rule as `add`).
- `toggleSubtask(_ subtaskID: UUID, in parentID: UUID)` — flips the subtask's
  `isDone`. **Hybrid auto-complete lives here:** after the flip, if the parent
  `allSubtasksDone`, call the existing `complete(parentID)` (the ~0.9s
  strike-through then removal, which takes the subtasks with it).
- `updateSubtaskTitle(_ subtaskID: UUID, in parentID: UUID, to title: String)` —
  trims; rejects empty (no-op).
- `removeSubtask(_ subtaskID: UUID, from parentID: UUID)`.
- `moveSubtask(in parentID: UUID, from: IndexSet, to: Int)`.
- `updateNotes(of parentID: UUID, to notes: String)` — sets the notes string.

The existing `complete(_ id:)` is unchanged and remains the manual override:
completing a parent works anytime and discards remaining subtasks.

A checked subtask stays in the list (struck through); only `toggleSubtask`
flips state, never removes. Only the parent vanishes (via `complete`).

### LinkDetector

A pure helper: `LinkDetector.links(in: String) -> [DetectedLink]` where
`DetectedLink` carries the `url: URL` and a `domain: String` (from `url.host`,
stripping a leading `www.`). Backed by a shared `NSDataDetector(types:
NSTextCheckingResult.CheckingType.link.rawValue)`. Returns links in appearance
order, de-duplicated by absolute URL string. Single source of truth for both the
notch glyph (`hasNotes && !links.isEmpty` → `link` glyph) and the Settings
chips. No network.

## Notch presentation (stays lean)

- **Compact cue** — unchanged: `☐ <next task title>`, no badges.
- **Expanded list (`TodoExpandedView`)** — each row gains, trailing:
  - progress badge `"\(done)/\(total)"` shown only when `total > 0`;
  - a note/link glyph shown when `hasNotes` — `link` if the notes contain a
    detected URL, else `note.text`.
  Both are **read-only** in the notch. The parent's own ○ checkbox still
  completes it (manual override). No `NotchSizing` change — badge + glyph fit the
  existing row width.

## Settings editing (`TodosPane` + new `TodoRowEditor`)

Each task row gets a disclosure chevron; expansion state is view-local
(`@State private var expanded: Set<UUID>`), not persisted. Collapsed, a row looks
like today plus the same badge/glyph. Expanded, `TodoRowEditor` (new file) renders
that task's body:

- **Subtasks** — inline list: checkbox (`toggleSubtask`) + editable title
  (`updateSubtaskTitle`) + minus delete (`removeSubtask`); a checked subtask is
  struck through but stays. Drag-reorder (`moveSubtask`). An "Add subtask…" field
  (`addSubtask`).
- **Notes** — a multi-line `TextEditor` bound through `updateNotes`, with a wrap
  of clickable domain chips (`🔗 github.com`) below it, one per `LinkDetector`
  result; tapping a chip opens the URL via `NSWorkspace.shared.open`.

Everything reads/writes `TodoStore.shared`, so notch badges update live.
`TodosPane` stays a thin list that delegates each expanded body to
`TodoRowEditor`, keeping both files focused.

## Edge cases

- Old tasks lacking the new fields → decode to empty (migration); badge/glyph
  hidden.
- Empty/whitespace subtask title → rejected on add and on rename.
- Deleting the last subtask → progress badge disappears; parent reverts to
  manual-only completion.
- Checking the final subtask → parent auto-completes and vanishes with its
  subtasks.
- Manual parent-complete with open subtasks → parent vanishes, subtasks
  discarded (intended).
- Malformed/partial URL text (`http://`, bare `foo.com`) → whatever
  `NSDataDetector` recognizes becomes a chip; junk yields no chips, no crash.
- A URL with no host → skipped (no chip) rather than an empty chip.
- Very long notes → `TextEditor` scrolls within the disclosure; chips wrap.

## Testing

All new logic is pure/unit-testable in `TodoStore` + `LinkDetector`:
- add / toggle / rename / remove / reorder subtasks
- **auto-complete when all subtasks done** (parent removed via scheduler)
- manual override with open subtasks (parent removed, subtasks discarded)
- `updateNotes` round-trip; `subtaskProgress` math; `hasNotes`
- **backward-compatible decode of old JSON lacking `subtasks`/`notes`** (guards
  existing data)
- `LinkDetector`: multiple URLs, order preserved, dedupe by absolute string,
  `www.`/host stripping, junk input → empty, host-less URL skipped

Views (`TodoRowEditor`, notch badges) stay thin and are verified by running the
app.

## Files (anticipated)

- `Sources/State/TodoStore.swift` — extend `Todo` (fields + custom `init(from:)`
  + derived props), add `Subtask`, add the subtask/notes store methods.
- `Sources/State/LinkDetector.swift` — new pure helper.
- `Sources/NotchUI/States/TodoExpandedView.swift` — add read-only badge + glyph
  to rows.
- `Sources/Settings/TodoRowEditor.swift` — new: one task's disclosure body
  (subtasks + notes + chips).
- `Sources/Settings/TodosPane.swift` — add disclosure; delegate to
  `TodoRowEditor`.
- `Tests/TodoStoreTests.swift` — subtask/notes/migration tests.
- `Tests/LinkDetectorTests.swift` — new.
