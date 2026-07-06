# Notch Tasks — Subtasks & Link-Aware Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each notch task an ordered list of checkable subtasks (with progress + hybrid auto-complete) and a free-text notes field whose URLs render as clickable domain chips — rich in Settings, read-only signals in the notch.

**Architecture:** Extends the shipped v1 units in place. `Todo` grows `subtasks`/`notes` (with a backward-compatible `init(from:)` so existing saved tasks still load), `TodoStore` grows subtask/notes methods (the auto-complete rule lives in `toggleSubtask`), a new pure `LinkDetector` backs both the notch glyph and the Settings chips, `TodoExpandedView` rows gain read-only badge+glyph, and `TodosPane` gains inline disclosure delegating each task's editor to a new `TodoRowEditor`.

**Tech Stack:** Swift 5, SwiftUI, `NSDataDetector`, `NSWorkspace`, `UserDefaults`/`NSUbiquitousKeyValueStore`, XcodeGen, XCTest.

## Global Constraints

- Deployment target macOS 14.0. Swift 5. Match the surrounding code's style.
- **Every `xcodebuild` command MUST include `-skipMacroValidation`** (llama.cpp macro requirement).
- **Adding a NEW source or test file requires `xcodegen generate` BEFORE `xcodebuild`**, or the file isn't in the project and won't compile. `Notchless.xcodeproj` is gitignored/generated — never commit it.
- **Backward-compatible persistence is mandatory:** existing tasks are already persisted as JSON without `subtasks`/`notes`; decoding must not throw on that old data (custom `Todo.init(from:)` with `decodeIfPresent`).
- The notch stays read-only for subtasks/notes — only a progress badge + a note/link glyph. No subtask checking or note editing in the notch. No `NotchSizing` change.
- **No network.** Links are detected and opened, never fetched.
- Store the task list only in `TodoStore` (unchanged); no `SettingsStore` schema change in this feature.

**Build command (reused):**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild -project Notchless.xcodeproj -scheme Notchless \
  -configuration Debug -destination 'platform=macOS' -skipMacroValidation build
```

**Test command (reused):**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild test -project Notchless.xcodeproj -scheme Notchless \
  -destination 'platform=macOS' -skipMacroValidation
```

---

## File Structure

**Create:**
- `Sources/State/LinkDetector.swift` — pure URL-in-text helper (`DetectedLink`, `LinkDetector.links(in:)`).
- `Sources/Settings/TodoRowEditor.swift` — one task's disclosure body (subtasks + notes + chips).
- `Tests/LinkDetectorTests.swift` — `LinkDetector` unit tests.

**Modify:**
- `Sources/State/TodoStore.swift` — add `Subtask`; extend `Todo` (fields, convenience init, `CodingKeys`, custom `init(from:)`, derived props); add subtask/notes store methods.
- `Sources/NotchUI/States/TodoExpandedView.swift` — add read-only badge + glyph to `row(_:)`.
- `Sources/Settings/TodosPane.swift` — add disclosure chevron + collapsed badge/glyph; render `TodoRowEditor` when expanded.
- `Tests/TodoStoreTests.swift` — model migration/derived tests + subtask/notes method tests.

---

## Task 1: Extend the Todo model with subtasks, notes, and safe migration (TDD)

**Files:**
- Modify: `Sources/State/TodoStore.swift:3-16` (the `Todo` struct)
- Test: `Tests/TodoStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct Subtask: Identifiable, Codable, Equatable { let id: UUID; var title: String; var isDone: Bool }` with `init(id: UUID = UUID(), title: String, isDone: Bool = false)`.
  - `Todo` gains `var subtasks: [Subtask]` and `var notes: String`; convenience `init` gains `subtasks: [Subtask] = [], notes: String = ""`; a custom `init(from:)` decoding the two new fields with `decodeIfPresent` (defaults `[]` / `""`); derived `subtaskProgress: (done: Int, total: Int)`, `hasNotes: Bool`, `allSubtasksDone: Bool`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TodoStoreTests.swift` (inside the existing `TodoStoreTests` class):

```swift
    // MARK: - Model: subtasks, notes, migration

    func test_todo_derivedProgressAndFlags() {
        var todo = Todo(title: "Parent")
        XCTAssertEqual(todo.subtaskProgress.total, 0)
        XCTAssertFalse(todo.allSubtasksDone)   // empty is NOT "all done"
        XCTAssertFalse(todo.hasNotes)
        todo.subtasks = [Subtask(title: "a", isDone: true), Subtask(title: "b", isDone: false)]
        todo.notes = "  hello  "
        XCTAssertEqual(todo.subtaskProgress.done, 1)
        XCTAssertEqual(todo.subtaskProgress.total, 2)
        XCTAssertFalse(todo.allSubtasksDone)
        XCTAssertTrue(todo.hasNotes)
        todo.subtasks[1].isDone = true
        XCTAssertTrue(todo.allSubtasksDone)
    }

    func test_todo_hasNotes_isFalseForWhitespaceOnly() {
        var todo = Todo(title: "P")
        todo.notes = "   \n "
        XCTAssertFalse(todo.hasNotes)
    }

    func test_todo_decodesOldJSONWithoutSubtasksOrNotes() throws {
        // v1 JSON: no `subtasks` / `notes` keys; createdAt is the default
        // JSONEncoder Date form (timeIntervalSinceReferenceDate, a number).
        let id = UUID()
        let json = "{\"id\":\"\(id.uuidString)\",\"title\":\"Legacy\",\"isDone\":false,\"createdAt\":0}"
        let todo = try JSONDecoder().decode(Todo.self, from: Data(json.utf8))
        XCTAssertEqual(todo.id, id)
        XCTAssertEqual(todo.title, "Legacy")
        XCTAssertTrue(todo.subtasks.isEmpty)
        XCTAssertEqual(todo.notes, "")
    }

    func test_todo_roundTripsSubtasksAndNotes() throws {
        var todo = Todo(title: "P", notes: "see https://x.com")
        todo.subtasks = [Subtask(title: "s1", isDone: true)]
        let data = try JSONEncoder().encode(todo)
        let back = try JSONDecoder().decode(Todo.self, from: data)
        XCTAssertEqual(back, todo)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the **Test command**.
Expected: FAIL to compile — `Subtask` unknown, `Todo` has no `subtasks`/`notes`/`subtaskProgress`.

- [ ] **Step 3: Write the implementation**

In `Sources/State/TodoStore.swift`, replace the `Todo` struct (lines 3-16) with:

```swift
/// A checkable sub-item of a `Todo`. Pure data.
struct Subtask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool

    init(id: UUID = UUID(), title: String, isDone: Bool = false) {
        self.id = id
        self.title = title
        self.isDone = isDone
    }
}

/// A single task in the notch checklist: title + done state, plus an optional
/// ordered list of subtasks and a free-text notes field.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date
    var subtasks: [Subtask]
    var notes: String

    init(id: UUID = UUID(), title: String, isDone: Bool = false,
         createdAt: Date = Date(), subtasks: [Subtask] = [], notes: String = "") {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.subtasks = subtasks
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, isDone, createdAt, subtasks, notes
    }

    // Custom decode so v1 JSON (no `subtasks`/`notes`) still loads — existing
    // saved tasks must not be lost. Encoding stays synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    /// (completed, total) subtasks — drives the "2/5" progress badge.
    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter(\.isDone).count, subtasks.count)
    }

    /// True when there's non-whitespace note text (drives the note/link glyph).
    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True only when there is at least one subtask and all are done — the
    /// trigger for hybrid auto-complete.
    var allSubtasksDone: Bool {
        !subtasks.isEmpty && subtasks.allSatisfy(\.isDone)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the **Test command**.
Expected: PASS — the 4 new model tests plus all pre-existing tests green (`** TEST SUCCEEDED **`). No new file was added, so no `xcodegen generate` is needed.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/TodoStore.swift Tests/TodoStoreTests.swift
git commit -m "feat: add Subtask + notes to Todo with backward-compatible decode"
```

---

## Task 2: TodoStore subtask & notes methods, with hybrid auto-complete (TDD)

**Files:**
- Modify: `Sources/State/TodoStore.swift` (add methods after `updateTitle`, before `clear`)
- Test: `Tests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: `Todo.allSubtasksDone`, `Subtask` (Task 1); existing `complete(_:)`.
- Produces on `TodoStore`: `addSubtask(to:title:)`, `toggleSubtask(_:in:)` (auto-completes the parent via `complete` when `allSubtasksDone`), `updateSubtaskTitle(_:in:to:)`, `removeSubtask(_:from:)`, `moveSubtask(in:from:to:)`, `updateNotes(of:to:)`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TodoStoreTests.swift`:

```swift
    // MARK: - Store: subtasks & notes

    func test_addSubtask_appendsTrimmedAndRejectsEmpty() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "  step 1  ")
        store.addSubtask(to: pid, title: "   ")
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["step 1"])
    }

    func test_toggleSubtask_flipsAndStays() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.addSubtask(to: pid, title: "b")
        let sid = store.items[0].subtasks[0].id
        store.toggleSubtask(sid, in: pid)
        XCTAssertTrue(store.items[0].subtasks[0].isDone)   // stays in the list
        XCTAssertEqual(store.items[0].subtasks.count, 2)
    }

    func test_toggleLastSubtask_autoCompletesParent() {
        let store = makeStore() // immediate scheduler + delay 0 → removal is synchronous
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.addSubtask(to: pid, title: "b")
        store.toggleSubtask(store.items[0].subtasks[0].id, in: pid)
        XCTAssertEqual(store.items.count, 1)               // not yet: one subtask open
        store.toggleSubtask(store.items[0].subtasks[1].id, in: pid)
        XCTAssertTrue(store.items.isEmpty)                 // all done → parent vanished
    }

    func test_manualComplete_withOpenSubtasks_removesParent() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.addSubtask(to: pid, title: "a")
        store.complete(pid)                                // manual override
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_updateSubtaskTitle_removeSubtask_moveSubtask() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        ["a", "b", "c"].forEach { store.addSubtask(to: pid, title: $0) }
        let a = store.items[0].subtasks[0].id
        store.updateSubtaskTitle(a, in: pid, to: "A")
        XCTAssertEqual(store.items[0].subtasks[0].title, "A")
        store.moveSubtask(in: pid, from: IndexSet(integer: 2), to: 0)   // "c" → front
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["c", "A", "b"])
        store.removeSubtask(store.items[0].subtasks[0].id, from: pid)   // removes "c"
        XCTAssertEqual(store.items[0].subtasks.map(\.title), ["A", "b"])
    }

    func test_updateNotes_setsNotes() {
        let store = makeStore()
        store.add("Parent")
        let pid = store.items[0].id
        store.updateNotes(of: pid, to: "ping https://x.com")
        XCTAssertEqual(store.items[0].notes, "ping https://x.com")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the **Test command**.
Expected: FAIL to compile — `addSubtask`/`toggleSubtask`/etc. are not members of `TodoStore`.

- [ ] **Step 3: Write the implementation**

In `Sources/State/TodoStore.swift`, insert these methods immediately after `updateTitle(_:to:)` (currently ending at line 106) and before `clear()`:

```swift
    func addSubtask(to parentID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.append(Subtask(title: trimmed))
        persist()
    }

    /// Flips a subtask's done state (it stays in the list, struck through). If
    /// that leaves every subtask done, the parent auto-completes (hybrid rule):
    /// `complete` runs its strike-through-then-vanish, taking the subtasks along.
    func toggleSubtask(_ subtaskID: UUID, in parentID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == parentID }),
              let j = items[i].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        items[i].subtasks[j].isDone.toggle()
        persist()
        if items[i].allSubtasksDone { complete(parentID) }
    }

    func updateSubtaskTitle(_ subtaskID: UUID, in parentID: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = items.firstIndex(where: { $0.id == parentID }),
              let j = items[i].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        items[i].subtasks[j].title = trimmed
        persist()
    }

    func removeSubtask(_ subtaskID: UUID, from parentID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.removeAll { $0.id == subtaskID }
        persist()
    }

    func moveSubtask(in parentID: UUID, from source: IndexSet, to destination: Int) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].subtasks.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func updateNotes(of parentID: UUID, to notes: String) {
        guard let i = items.firstIndex(where: { $0.id == parentID }) else { return }
        items[i].notes = notes
        persist()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the **Test command**.
Expected: PASS — all subtask/notes tests green plus prior tests. `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/TodoStore.swift Tests/TodoStoreTests.swift
git commit -m "feat: add TodoStore subtask/notes methods with hybrid auto-complete"
```

---

## Task 3: LinkDetector helper (TDD)

**Files:**
- Create: `Sources/State/LinkDetector.swift`
- Create: `Tests/LinkDetectorTests.swift`

**Interfaces:**
- Produces:
  - `struct DetectedLink: Equatable { let url: URL; let domain: String }`
  - `enum LinkDetector { static func links(in text: String) -> [DetectedLink] }` — URLs in appearance order, de-duplicated by absolute string, `domain` = `url.host` with a leading `www.` stripped; URLs without a host (e.g. `mailto:`) are skipped. No network.

- [ ] **Step 1: Write the failing tests**

Create `Tests/LinkDetectorTests.swift`:

```swift
import XCTest
@testable import Notchless

final class LinkDetectorTests: XCTestCase {
    func test_extractsMultipleLinksInOrder() {
        let links = LinkDetector.links(in: "see https://github.com/foo then https://apple.com/x")
        XCTAssertEqual(links.map(\.domain), ["github.com", "apple.com"])
    }

    func test_dedupesByAbsoluteURL() {
        let links = LinkDetector.links(in: "https://x.com and again https://x.com")
        XCTAssertEqual(links.count, 1)
    }

    func test_stripsLeadingWww() {
        let links = LinkDetector.links(in: "http://www.example.com/page")
        XCTAssertEqual(links.first?.domain, "example.com")
    }

    func test_noLinks_returnsEmpty() {
        XCTAssertTrue(LinkDetector.links(in: "just some plain text").isEmpty)
        XCTAssertTrue(LinkDetector.links(in: "").isEmpty)
    }

    func test_skipsHostlessLinks() {
        // NSDataDetector reads emails as mailto: URLs (no host) — no chip.
        XCTAssertTrue(LinkDetector.links(in: "reach me at a@b.com").isEmpty)
    }
}
```

- [ ] **Step 2: Regenerate the project and run the tests to verify they fail**

New files were added, so regenerate first:
```bash
cd /Users/rexdanquah/Projects/dynamic_island && xcodegen generate
```
Then run the **Test command**.
Expected: FAIL to compile — `LinkDetector` / `DetectedLink` unknown.

- [ ] **Step 3: Write the implementation**

Create `Sources/State/LinkDetector.swift`:

```swift
import Foundation

/// A URL found in free text, with a tidy display domain.
struct DetectedLink: Equatable {
    let url: URL
    let domain: String
}

/// Finds URLs in note text via `NSDataDetector`. Pure and offline — it detects
/// and returns links; it never fetches them. Single source of truth for both
/// the notch's note/link glyph and the Settings domain chips.
enum LinkDetector {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// URLs in appearance order, de-duplicated by absolute string. `domain` is
    /// the host with a leading `www.` removed. URLs without a host are skipped.
    static func links(in text: String) -> [DetectedLink] {
        guard let detector, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [DetectedLink] = []
        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let url = match?.url, let host = url.host else { return }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { return }
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            result.append(DetectedLink(url: url, domain: domain))
        }
        return result
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the **Test command** (project already regenerated in Step 2).
Expected: PASS — all `LinkDetectorTests` green plus prior suites. `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/LinkDetector.swift Tests/LinkDetectorTests.swift
git commit -m "feat: add LinkDetector for URL-in-notes detection"
```

---

## Task 4: Notch read-only progress badge + note/link glyph

**Files:**
- Modify: `Sources/NotchUI/States/TodoExpandedView.swift:54-70` (`row(_:)`)

**Interfaces:**
- Consumes: `Todo.subtaskProgress`, `Todo.hasNotes` (Task 1), `LinkDetector.links(in:)` (Task 3).
- Produces: expanded-notch rows that show `done/total` and a `link`/`note.text` glyph, read-only.

- [ ] **Step 1: Replace `row(_:)` with the badge+glyph version**

In `Sources/NotchUI/States/TodoExpandedView.swift`, replace the `row(_:)` method (lines 54-70) with:

```swift
    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            Button { store.complete(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? .green : .white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 13))
                .foregroundStyle(todo.isDone ? .white.opacity(0.4) : .white)
                .strikethrough(todo.isDone, color: .white.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Read-only signals (checking/editing happens in Settings).
            if todo.subtaskProgress.total > 0 {
                Text("\(todo.subtaskProgress.done)/\(todo.subtaskProgress.total)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            if todo.hasNotes {
                Image(systemName: LinkDetector.links(in: todo.notes).isEmpty ? "note.text" : "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
```

(Note: the title's `lineLimit` drops from 2 to 1 to leave room for the trailing badge/glyph on a single row.)

- [ ] **Step 2: Build to verify it compiles**

Run the **Build command**. (No new file, no regen needed.)
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Sources/NotchUI/States/TodoExpandedView.swift
git commit -m "feat: show subtask progress + note/link glyph in notch task rows"
```

---

## Task 5: Settings inline disclosure + TodoRowEditor

**Files:**
- Create: `Sources/Settings/TodoRowEditor.swift`
- Modify: `Sources/Settings/TodosPane.swift:31-49` (the task `ForEach`) + add an `expanded` state and a toggle helper

**Interfaces:**
- Consumes: all `TodoStore` subtask/notes methods (Task 2), `LinkDetector` (Task 3), `Todo.subtaskProgress`/`hasNotes` (Task 1).
- Produces: `struct TodoRowEditor: View { let todoID: UUID }`; a `TodosPane` where each task row has a disclosure chevron + collapsed badge/glyph and reveals `TodoRowEditor` when expanded.

- [ ] **Step 1: Create the row editor**

Create `Sources/Settings/TodoRowEditor.swift`:

```swift
import SwiftUI
import AppKit

/// One task's expanded editor in the Settings Tasks pane: its subtasks
/// (add / check / rename / delete / reorder) and a notes field with clickable
/// domain chips for any URLs. Reads/writes `TodoStore.shared`.
struct TodoRowEditor: View {
    @ObservedObject private var store = TodoStore.shared
    let todoID: UUID
    @State private var newSubtask = ""

    private var todo: Todo? { store.items.first { $0.id == todoID } }

    var body: some View {
        if let todo {
            VStack(alignment: .leading, spacing: 8) {
                subtaskList(todo)
                addSubtaskField
                Divider()
                notesSection(todo)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
        }
    }

    private func subtaskList(_ todo: Todo) -> some View {
        ForEach(Array(todo.subtasks.enumerated()), id: \.element.id) { index, sub in
            HStack(spacing: 8) {
                Button { store.toggleSubtask(sub.id, in: todoID) } label: {
                    Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(sub.isDone ? .green : .secondary)
                }.buttonStyle(.plain)

                TextField("Subtask", text: subtaskBinding(sub))
                    .textFieldStyle(.plain)
                    .strikethrough(sub.isDone)
                    .foregroundStyle(sub.isDone ? .secondary : .primary)

                Spacer()

                // Up/down reorder (a CardGroup VStack isn't a reorderable List;
                // buttons call the same moveSubtask the store exposes).
                Button { move(index, by: -1, in: todo) } label: {
                    Image(systemName: "chevron.up")
                }.buttonStyle(.plain).disabled(index == 0).foregroundStyle(.secondary)
                Button { move(index, by: 1, in: todo) } label: {
                    Image(systemName: "chevron.down")
                }.buttonStyle(.plain).disabled(index == todo.subtasks.count - 1).foregroundStyle(.secondary)

                Button { store.removeSubtask(sub.id, from: todoID) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .font(.callout)
        }
    }

    private var addSubtaskField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(.secondary)
            TextField("Add subtask…", text: $newSubtask)
                .textFieldStyle(.plain)
                .onSubmit {
                    store.addSubtask(to: todoID, title: newSubtask)
                    newSubtask = ""
                }
        }
        .font(.callout)
    }

    private func notesSection(_ todo: Todo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: notesBinding)
                .font(.callout)
                .frame(minHeight: 54)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))

            let links = LinkDetector.links(in: todo.notes)
            if !links.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)],
                    alignment: .leading, spacing: 6
                ) {
                    ForEach(links, id: \.url) { link in
                        Button { NSWorkspace.shared.open(link.url) } label: {
                            Label(link.domain, systemImage: "link")
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// SwiftUI move offsets: moving an item DOWN by one needs `to: index + 2`.
    private func move(_ index: Int, by delta: Int, in todo: Todo) {
        let target = delta < 0 ? index - 1 : index + 2
        store.moveSubtask(in: todoID, from: IndexSet(integer: index), to: target)
    }

    private func subtaskBinding(_ sub: Subtask) -> Binding<String> {
        Binding(
            get: {
                store.items.first { $0.id == todoID }?
                    .subtasks.first { $0.id == sub.id }?.title ?? sub.title
            },
            set: { store.updateSubtaskTitle(sub.id, in: todoID, to: $0) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.items.first { $0.id == todoID }?.notes ?? "" },
            set: { store.updateNotes(of: todoID, to: $0) }
        )
    }
}
```

- [ ] **Step 2: Add disclosure to TodosPane**

In `Sources/Settings/TodosPane.swift`:

a. Add expansion state after line 10 (`@State private var confirmClear = false`):
```swift
    @State private var expanded: Set<UUID> = []
```

b. Replace the task `ForEach` block (lines 36-48) with a chevron + collapsed badge/glyph + expandable editor:
```swift
                    ForEach(store.items) { todo in
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Button { toggleExpanded(todo.id) } label: {
                                    Image(systemName: expanded.contains(todo.id) ? "chevron.down" : "chevron.right")
                                        .font(.caption).foregroundStyle(.secondary).frame(width: 12)
                                }.buttonStyle(.plain)

                                TextField("Task", text: binding(for: todo))
                                    .textFieldStyle(.plain)
                                Spacer()

                                if todo.subtaskProgress.total > 0 {
                                    Text("\(todo.subtaskProgress.done)/\(todo.subtaskProgress.total)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                if todo.hasNotes {
                                    Image(systemName: LinkDetector.links(in: todo.notes).isEmpty ? "note.text" : "link")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Button {
                                    store.remove(todo.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                }.buttonStyle(.plain)
                            }
                            if expanded.contains(todo.id) {
                                TodoRowEditor(todoID: todo.id)
                            }
                        }
                        if todo.id != store.items.last?.id { Divider() }
                    }
```

c. Add the toggle helper after `addTask()` (after line 67):
```swift
    private func toggleExpanded(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
```

- [ ] **Step 3: Regenerate the project and build**

New file added, so regenerate first:
```bash
cd /Users/rexdanquah/Projects/dynamic_island && xcodegen generate
```
Then run the **Build command**.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Settings/TodoRowEditor.swift Sources/Settings/TodosPane.swift
git commit -m "feat: add subtasks + link-aware notes editor to Tasks settings pane"
```

---

## Task 6: Full-flow verification in the running app

**Files:** none (manual verification + final commit only if a defect is found)

**Interfaces:** Consumes everything above.

- [ ] **Step 1: Run the full test suite**

Run the **Test command**.
Expected: `** TEST SUCCEEDED **` — all model, store, and LinkDetector tests plus the originals.

- [ ] **Step 2: Launch and verify end-to-end**

Build a Debug app and launch it (per the repo's build memory: `xcodegen generate` then build to `build/`, `pkill -x Notchless` before `open`). Verify:

1. **Existing task survives** — the task you already had ("MXN Wallet KYC Integration") is still present (migration works).
2. **Settings › Tasks** — expand a task via the chevron. Add 2-3 subtasks; check one → it stays struck-through and the collapsed badge shows e.g. `1/3`. Rename a subtask; reorder with the up/down chevrons; delete one.
3. **Auto-complete** — check the *last* remaining subtask → the whole parent task strikes through and vanishes (~0.9s).
4. **Manual override** — on a task with open subtasks, delete it via the minus button (or complete its parent checkbox in the notch) → it's gone.
5. **Notes + links** — type notes containing a URL (e.g. `docs at https://github.com/foo`). A `🔗 github.com` chip appears below; clicking it opens the browser. The collapsed row and the notch row show the `link` glyph; notes without a URL show `note.text`.
6. **Notch signals** — set idle activity to Tasks (or expand the notch); a task with subtasks shows `1/3`, and the note/link glyph appears — both read-only (no checking in the notch).
7. **Persistence** — quit and relaunch → subtasks and notes persist.

- [ ] **Step 3: If a defect is found, fix minimally, rebuild, commit**

```bash
git add -A
git commit -m "fix: <specific issue found during verification>"
```
If no defects: feature complete; nothing to commit.

---

## Notes / decisions

- **Subtask reorder uses up/down buttons, not drag.** A `CardGroup` VStack isn't a reorderable `List`, and subtasks don't exist in the notch (which is where v1 put task drag-reorder). Up/down buttons call the same `moveSubtask` store method and avoid a fragile nested-`List`-in-`ScrollView`. This is a deliberate deviation from the spec's literal "drag-reorder" wording; the capability is preserved.
- **Migration is the load-bearing part** — the custom `Todo.init(from:)` is what keeps existing saved tasks alive; the `test_todo_decodesOldJSONWithoutSubtasksOrNotes` test guards it.
- **No `NotchSizing` change** — badge + glyph fit the existing expanded-row width; the title drops to `lineLimit(1)` to make room.
- Notch stays read-only for subtasks/notes by design; all editing is in Settings.
