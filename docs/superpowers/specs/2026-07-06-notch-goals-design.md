# Notch Goals — Design

**Date:** 2026-07-06
**Status:** Approved for planning

## Summary

A glanceable savings/progress tracker that lives in the notch. You define goals
(a target amount by a deadline), log dated contributions into them, and watch a
percentage climb. The idle notch shows one *pinned* goal's ring + percentage;
the expanded notch shows every active goal with its breakdown and lets you
quick-log a contribution. Full management — creating goals, editing the
contribution log, archives — lives in Settings.

Scope is deliberately a **tracker, not a finance app**: manual entry, one
currency, no live balances, no FX, no forecasting beyond a simple pace hint.

## Goals & non-goals

**Goals**
- Ambient "am I on track" cue in the notch (one pinned goal, ring + %).
- Log contributions over time (append `+amount` entries, never overwrite).
- Per-label breakdown ("MTN stocks / Petra / Cash") computed by grouping.
- Simple pace hint (ahead / on-track / behind) from a start→deadline timeline.
- Celebrate + auto-archive a goal when it reaches its target.
- Self-contained: no permissions, no external dependencies, matches existing
  codebase conventions (mirrors the Todos / FileTray pattern).

**Non-goals (v1)**
- Live-connected balances (brokerage / mobile-money APIs).
- Multi-currency + FX conversion.
- Forecasting/projection beyond the linear pace hint.
- Recurring/scheduled contributions, reminders, notifications.
- Sub-goals, categories-as-first-class-entities (labels stay free-form).

## Decisions (from brainstorming)

- **Update model:** manual, but *log contributions over time* — each is an
  appended `+amount` entry, not an overwrite. A correction is a negative entry.
- **Breakdown structure:** free-form labeled contributions (not fixed buckets).
  The breakdown is computed by grouping contributions by label. Label input
  autocompletes from existing labels to keep spelling consistent.
- **Compact cue:** one *pinned* focused goal shows in the idle notch (ring + %).
  Expanded view shows all goals.
- **Deadline & pace:** goals have a deadline; the app computes a pace hint
  (ahead / on-track / behind / overdue) from elapsed vs expected progress.
- **Currency:** single app-wide currency (default `GHS ₵`), configurable. No
  conversion.
- **Interaction split:** read-only glance + **quick-log a contribution from the
  expanded notch**; goal creation / editing / log management / archives in
  Settings.
- **Reaching 100%:** celebrate, then **auto-archive** the goal into a Completed
  section (removed from the active list; can be restored or deleted).

## Architecture

Maps 1:1 onto the existing activity pattern; the Todos feature
(`docs/superpowers/specs/2026-07-06-notch-todos-design.md`) is the direct
analog: a dedicated store + a `NotchActivity` case + a compact view + an
expanded view + a Settings pane. Only the enable toggle and currency live in
`SettingsStore`; the goals themselves live in their own store, exactly as
`FileTrayStore`/`TodoStore` hold their data rather than putting it in
`SettingsStore`.

### Data model

```swift
struct Contribution: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Decimal      // positive; a correction is an explicit negative entry
    var label: String        // free-form; autocompletes from prior labels
    var date: Date
}

struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String              // "End-of-year savings"
    var target: Decimal           // 100_000
    var startDate: Date           // set at creation; pace baseline
    var deadline: Date            // "Dec 31"
    var contributions: [Contribution]
    var completedAt: Date?        // non-nil once archived
}
```

Derived (computed, not stored):
- `current = contributions.reduce(0) { $0 + $1.amount }`
- `fraction = clamp(current / target, 0...1)` (display clamp; true total kept)
- `breakdown = Dictionary(grouping: contributions, by: \.label)
     .mapValues { $0.reduce(0){ $0 + $1.amount } }`

### GoalStore (new `ObservableObject`, mirrors `TodoStore`)

- `@Published private(set) var goals: [Goal]` — active goals, in display order.
- `@Published private(set) var completed: [Goal]` — archived goals.
- `@Published var pinnedID: UUID?` → `var pinned: Goal?` — the compact cue's goal.
- `addGoal(name:target:deadline:)` — validates `target > 0`,
  `deadline > startDate`; `startDate = now` at creation.
- `updateGoal(_:)` — edit name / target / deadline.
- `deleteGoal(_ id:)` — from active or completed.
- `logContribution(goalID:amount:label:)` — appends a `Contribution`; rejects
  zero / non-numeric amount and empty/whitespace label. If the new total reaches
  `target`, sets `completedAt`, fires the celebration, and moves the goal into
  `completed`.
- `removeContribution(goalID:contributionID:)` — for fixing a mis-entry.
- `setPinned(_ id:)` / auto-repin: if the pinned goal is deleted or completed,
  pin the next active goal, else clear.
- `restore(_ id:)` — move a completed goal back to active (clears `completedAt`).
- **Persistence:** encodes `{ goals, completed, pinnedID }` to JSON under one
  `UserDefaults` key; mirrored to `NSUbiquitousKeyValueStore` when
  `SettingsStore.syncViaICloud` is on. Loaded on init. Decode failure / missing
  data falls back to empty lists.

Both the Settings pane and the notch views read/write this single `GoalStore`
instance, so edits in one reflect live in the other.

### Currency

- `currencyCode` / symbol stored in `SettingsStore` (default `GHS` / `₵`),
  persisted + iCloud-mirrored like other scalars.
- One shared formatting helper (`formatAmount(_:)`) used by every view. Compact
  amounts abbreviate (e.g. `100k ₵`); expanded/Settings show full grouped values
  (`42,000 / 100,000 ₵`).

### Pace logic (pure, unit-testable)

```
elapsed  = now - startDate
total    = deadline - startDate            // guaranteed > 0 at creation
expected = target * (elapsed / total)      // clamped to 0...target
delta    = current - expected
status =
    now > deadline && current < target        -> .overdue
    |delta| <= target * 0.02                   -> .onTrack
    delta > 0                                  -> .ahead(delta)
    else                                       -> .behind(-delta)
```

Rendered gently: "On track", "Ahead ~5k", "Behind ~8k", "Overdue". The ~2%
dead-band keeps the status from flickering around the exact line.

## Notch presentation

### Activity wiring
- Add `case goals` to `NotchActivity` (parallels `.todos` / `.timer`).
- Resolve `.goals` in the idle / expanded content sites.
- **Auto-hide:** when there are no active goals, the activity resolves to
  nothing — under `.auto` idle it doesn't appear; under an explicit `.goals`
  idle pick with no active goals it falls back to `.bare`.

### Compact / idle cue — `GoalCompactView` (pinned goal only)
- A small progress ring (`Circle().trim`) + percentage, plus the goal's short
  name or abbreviated target, e.g. `◔ 42% · 100k ₵`.
- Ring carries a subtle pace tint (neutral on-track, warm behind, green
  reached). *(Optional — cuttable from v1.)*
- Tapping expands to the full list.

### Expanded view — `GoalExpandedView` (all active goals)
- Header: `Goals · N active`.
- One row per active goal: name, `current / target` (formatted), a progress bar
  with %, `days-left · pace hint` (e.g. `178 days · Behind ~8k`), and a small
  **pin** control to make it the compact cue.
- Expanding a goal reveals its **label breakdown** as sub-rows (MTN stocks 25k,
  Petra 12k, Cash 5k).
- **Quick-log row** (the recurring action): amount field + label field (label
  autocompletes from existing labels) + return-to-add; logs into the currently
  focused/expanded goal.
- Reaching 100% plays the celebration (brief scale-glow / confetti, ~1s), then
  the goal animates out to Completed.
- Empty active state: "No goals yet — add one in Settings."

## Settings — `GoalsPane`

Follows the `FeaturePanes` / `GeneralPane` layout; added to `SettingsView`'s
sidebar (icon: `chart.line.uptrend.xyaxis` or `target`).

- **Enable Goals** toggle → new `goalsEnabled: Bool` in `SettingsStore`
  (registered default `true`, persisted + iCloud-mirrored, exactly like
  `todosEnabled` / `fileTrayEnabled`). Gates whether the activity appears.
- **Currency** row — code + symbol.
- **Active goals** — full management: add / edit / delete a goal (name, target,
  deadline); choose which goal is **pinned**; per-goal view & edit the
  contribution log (each a dated `amount + label`, deletable to fix a mis-entry).
  This is where the detailed breakdown you enter lives.
- **Completed** section (collapsible) — archived goals with their reached date;
  **restore** *(optional — cuttable from v1)* or delete.

## Edge cases

- Empty / zero / non-numeric amount → rejected on log. Negative allowed only as
  an explicit correction entry.
- Empty / whitespace label → rejected on log.
- `target <= 0` → rejected on goal create/edit.
- `deadline <= startDate` → rejected (pace needs a positive span).
- Pinned goal deleted or completed → auto-pin the next active goal, else clear
  the cue.
- Over-contribution (`current > target`) → clamp the bar at 100% but show the
  true total; still triggers completion/archive.
- Corrupt / absent persisted JSON → falls back to empty lists; never crashes.
- iCloud sync race (edit on two machines) → last-writer-wins on the whole
  payload, consistent with how the rest of the app mirrors state.
- Activity disabled mid-use → cue disappears; goal data retained.

## Testing

`GoalStore` and the pace/currency helpers are pure logic with no UI or
permission dependencies, so they are unit-testable directly:
- add / log-contribution / reject-invalid / remove-contribution
- completion → auto-archive, and pinned-goal auto-repin
- breakdown grouping (labels summed correctly)
- pace status: on-track / ahead / behind / overdue, including the dead-band
- currency formatting (compact abbreviation + full grouped)
- JSON round-trip (encode → decode → equal) and corrupt-data fallback

Views are thin wrappers over the store and are verified by running the app.

## Files (anticipated)

- `Sources/State/GoalStore.swift` — new store + `Goal` / `Contribution` models +
  pace logic.
- `Sources/State/NotchState.swift` — add `.goals` to `NotchActivity`.
- `Sources/NotchUI/States/GoalCompactView.swift` — the pinned compact cue.
- `Sources/NotchUI/States/GoalExpandedView.swift` — the full expanded list +
  quick-log.
- `Sources/Settings/GoalsPane.swift` — new Settings pane.
- `Sources/Settings/SettingsView.swift` — register the pane in the sidebar.
- `Sources/State/SettingsStore.swift` — add `goalsEnabled` + `currencyCode` /
  symbol.
- Content-resolution site (`NotchViewModel` / wherever activities resolve) —
  handle `.goals` + auto-hide when there are no active goals.

## Optional / cuttable from v1

Flagged so the plan can defer them without touching the core:
- Pace tint on the compact ring (status still shows in expanded).
- Restore-from-completed (delete-only archive is fine for v1).
