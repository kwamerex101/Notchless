# Notch Tasks (Todos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a lightweight, glanceable checklist that lives in the notch — quick-add + check-off in the notch, full management in Settings, auto-hiding when empty.

**Architecture:** Follows the existing activity pattern (Timer/Clipboard are the closest analogs). A new `.shared` `TodoStore` (JSON in `UserDefaults`, iCloud-mirrored) holds the tasks; a new `NotchActivity.todos` case flows through content resolution, a compact idle cue, an expanded interactive panel, and a Settings pane. Only the enable toggle lives in `SettingsStore`. This is also the repo's **first** automated test target.

**Tech Stack:** Swift 5, SwiftUI, Combine, `UserDefaults` / `NSUbiquitousKeyValueStore`, XcodeGen, XCTest.

## Global Constraints

- Deployment target: macOS 14.0 (`project.yml`). No newer-only APIs without a fallback.
- **Every build/test command must include `-skipMacroValidation`** — the `LLM.swift` (llama.cpp) package fails macro validation otherwise. This is a hard requirement for this repo.
- Signing is Manual, Developer ID Application, `DEVELOPMENT_TEAM: 6697RW78AJ` — keep TCC grants stable. New targets mirror this.
- Regenerate the Xcode project with `xcodegen generate` after any `project.yml` change; `Notchless.xcodeproj` is generated and not hand-edited.
- Store the task list in its own store, NOT in `SettingsStore` (which holds scalar prefs only). Only the `todosEnabled` bool goes in `SettingsStore`.
- Product copy: the user-facing feature name is **"Tasks"** (sidebar label, pane title, headers). Internal identifiers use `todo`/`todos`.

**Build command (reused throughout):**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild -project Notchless.xcodeproj -scheme Notchless \
  -configuration Debug -destination 'platform=macOS' -skipMacroValidation build
```

**Test command (reused throughout):**
```bash
cd /Users/rexdanquah/Projects/dynamic_island && \
xcodebuild test -project Notchless.xcodeproj -scheme Notchless \
  -destination 'platform=macOS' -skipMacroValidation
```

---

## File Structure

**Create:**
- `Sources/State/TodoStore.swift` — `Todo` model + `TodoStore` (`.shared`, injectable deps for tests).
- `Sources/NotchUI/States/TodoExpandedView.swift` — the interactive expanded panel.
- `Sources/Settings/TodosPane.swift` — the Settings pane.
- `Tests/SmokeTests.swift` — proves the test target runs (Task 1).
- `Tests/TodoStoreTests.swift` — `TodoStore` unit tests (Task 2).

**Modify:**
- `project.yml` — add `NotchlessTests` target + a `schemes` block wiring it into the Notchless scheme's test action.
- `Sources/State/NotchState.swift` — add `case todos` to `NotchActivity`.
- `Sources/State/SettingsStore.swift` — add `todosEnabled` pref (published + key + default + persist).
- `Sources/State/NotchViewModel.swift` — hold `TodoStore.shared`, forward its changes, add `.todos` to `liveActivities` + `hasIdleContent`.
- `Sources/NotchUI/States/IdleCompactView.swift` — add `.todos` to `leading` + `trailing`.
- `Sources/NotchUI/NotchSizing.swift` — add `.todos` to the idle + expanded size switches.
- `Sources/NotchUI/NotchRootView.swift` — route `.expanded(.todos)` → `TodoExpandedView`.
- `Sources/App/DebugRender.swift` — add `.todos` to its expanded switch (keeps the debug preview compiling).
- `Sources/Settings/GeneralPane.swift` — add `.todos` to `pickerTitle` + `pickerImage` (idle-activity picker uses `allCases`, so the case must be handled).
- `Sources/Settings/SettingsView.swift` — add a `.tasks` `SettingsSection` (title/image/tint + content routing + sidebar row).

---

## Task 1: Add the XCTest target and prove it runs

**Files:**
- Modify: `project.yml`
- Create: `Tests/SmokeTests.swift`

**Interfaces:**
- Produces: a `NotchlessTests` unit-test target hosted by `Notchless`, run by the `Notchless` scheme's test action, so `@testable import Notchless` works and later tasks can add test files under `Tests/`.

- [ ] **Step 1: Add the test target and scheme to `project.yml`**

Append this `NotchlessTests` target under the existing `targets:` block (sibling of `Notchless:`, same indentation as `Notchless:` at line 27), and add the `schemes:` block at the top level (sibling of `targets:`):

```yaml
  NotchlessTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    dependencies:
      - target: Notchless
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.rexdanquah.NotchlessTests
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "Developer ID Application"
        DEVELOPMENT_TEAM: "6697RW78AJ"
        MACOSX_DEPLOYMENT_TARGET: "14.0"

schemes:
  Notchless:
    build:
      targets:
        Notchless: all
    test:
      targets:
        - NotchlessTests
```

- [ ] **Step 2: Write the smoke test**

Create `Tests/SmokeTests.swift`:

```swift
import XCTest
@testable import Notchless

final class SmokeTests: XCTestCase {
    func test_harnessRuns() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project**

Run: `cd /Users/rexdanquah/Projects/dynamic_island && xcodegen generate`
Expected: `Created project at .../Notchless.xcodeproj` with no errors.

- [ ] **Step 4: Run the test to verify the harness works**

Run the **Test command** from Global Constraints.
Expected: build succeeds and `SmokeTests.test_harnessRuns` passes — `** TEST SUCCEEDED **`.

If it fails to launch the host app for testing, that's a real signing/host issue to resolve now (before any logic depends on it), not later.

- [ ] **Step 5: Commit**

```bash
git add project.yml Tests/SmokeTests.swift Notchless.xcodeproj
git commit -m "test: add NotchlessTests XCTest target"
```

---

## Task 2: Todo model and TodoStore (TDD)

**Files:**
- Create: `Sources/State/TodoStore.swift`
- Create: `Tests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: nothing (self-contained; reads `SettingsStore.shared.syncViaICloud` only when a non-nil cloud store is injected).
- Produces:
  - `struct Todo: Identifiable, Codable, Equatable { let id: UUID; var title: String; var isDone: Bool; var createdAt: Date }`
  - `final class TodoStore: ObservableObject` (`@MainActor`) with `static let shared`, `static let storageKey = "todoItems"`, `@Published private(set) var items: [Todo]`, computed `isEmpty: Bool`, `next: Todo?` (first not-done), `openCount: Int`, and methods `add(_ title: String)`, `complete(_ id: UUID)`, `remove(_ id: UUID)`, `move(from: IndexSet, to: Int)`, `updateTitle(_ id: UUID, to: String)`, `clear()`.
  - Test-only init params: `init(defaults: UserDefaults = .standard, cloud: NSUbiquitousKeyValueStore? = .default, removalDelay: TimeInterval = 0.9, schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = default-async)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TodoStoreTests.swift`:

```swift
import XCTest
@testable import Notchless

@MainActor
final class TodoStoreTests: XCTestCase {
    /// A store backed by an ephemeral suite, no iCloud, and an immediate
    /// scheduler so completion removal happens synchronously in tests.
    private func makeStore(
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { _, work in work() }
    ) -> TodoStore {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        return TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: schedule)
    }

    func test_add_appendsTrimmedTask() {
        let store = makeStore()
        store.add("  Ship v1.1  ")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Ship v1.1")
    }

    func test_add_rejectsEmptyOrWhitespace() {
        let store = makeStore()
        store.add("")
        store.add("   \n ")
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_complete_removesTaskViaScheduler() {
        let store = makeStore() // immediate scheduler + delay 0 → removed synchronously
        store.add("A")
        store.complete(store.items[0].id)
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_next_skipsDoneTaskDuringStrikeThrough() {
        // Scheduler that never fires, so the completed task lingers (the
        // strike-through window). `next` must skip it.
        let store = makeStore(schedule: { _, _ in })
        store.add("A")
        store.add("B")
        store.complete(store.items[0].id)
        XCTAssertTrue(store.items[0].isDone)
        XCTAssertEqual(store.next?.title, "B")
    }

    func test_move_reorders() {
        let store = makeStore()
        store.add("A"); store.add("B"); store.add("C")
        store.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.items.map(\.title), ["C", "A", "B"])
    }

    func test_updateTitle_changesTitleAndRejectsEmpty() {
        let store = makeStore()
        store.add("old")
        let id = store.items[0].id
        store.updateTitle(id, to: "  new  ")
        XCTAssertEqual(store.items.first?.title, "new")
        store.updateTitle(id, to: "   ")
        XCTAssertEqual(store.items.first?.title, "new") // unchanged
    }

    func test_clear_removesAll() {
        let store = makeStore()
        store.add("A"); store.add("B")
        store.clear()
        XCTAssertTrue(store.items.isEmpty)
    }

    func test_persistence_roundTrips() {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        let s1 = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        s1.add("Persist me")
        let s2 = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        XCTAssertEqual(s2.items.map(\.title), ["Persist me"])
    }

    func test_load_recoversFromCorruptData() {
        let suite = UserDefaults(suiteName: "TodoStoreTests-\(UUID().uuidString)")!
        suite.set(Data("not json".utf8), forKey: TodoStore.storageKey)
        let store = TodoStore(defaults: suite, cloud: nil, removalDelay: 0, schedule: { _, w in w() })
        XCTAssertTrue(store.items.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the **Test command**.
Expected: FAIL to compile with "cannot find 'TodoStore' in scope" (type not defined yet).

- [ ] **Step 3: Write the minimal implementation**

Create `Sources/State/TodoStore.swift`:

```swift
import SwiftUI

/// A single task in the notch checklist. Pure data — title + done state.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    var createdAt: Date

    init(id: UUID = UUID(), title: String, isDone: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
    }
}

/// Holds the notch task list. Mirrors `FileTrayStore` (a dedicated store, not
/// `SettingsStore`), but persists to `UserDefaults` as JSON and mirrors to
/// iCloud when the user's sync pref is on. Both the Settings pane and the notch
/// read/write the `.shared` instance, so edits stay in sync.
@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()
    static let storageKey = "todoItems"

    @Published private(set) var items: [Todo] = []

    var isEmpty: Bool { items.isEmpty }
    /// The task the compact cue shows: the first still-open one (skips a task
    /// that's mid-strike-through after being checked off).
    var next: Todo? { items.first { !$0.isDone } }
    var openCount: Int { items.lazy.filter { !$0.isDone }.count }

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private let removalDelay: TimeInterval
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(
        defaults: UserDefaults = .standard,
        cloud: NSUbiquitousKeyValueStore? = .default,
        removalDelay: TimeInterval = 0.9,
        schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.removalDelay = removalDelay
        self.schedule = schedule
        load()
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(Todo(title: trimmed))
        persist()
    }

    /// Marks a task done (drives the strike-through), then removes it after
    /// `removalDelay` so it briefly shows completed before vanishing.
    func complete(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].isDone else { return }
        items[i].isDone = true
        persist()
        schedule(removalDelay) { [weak self] in self?.remove(id) }
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func updateTitle(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = trimmed
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.storageKey)
        if let cloud, SettingsStore.shared.syncViaICloud {
            cloud.set(data, forKey: Self.storageKey)
            cloud.synchronize()
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Todo].self, from: data)
        else {
            items = []
            return
        }
        items = decoded
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the **Test command**.
Expected: PASS — all `TodoStoreTests` green, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/TodoStore.swift Tests/TodoStoreTests.swift
git commit -m "feat: add Todo model and TodoStore with unit tests"
```

---

## Task 3: Wire the activity, the enable pref, and content resolution

**Files:**
- Modify: `Sources/State/NotchState.swift`
- Modify: `Sources/State/SettingsStore.swift`
- Modify: `Sources/State/NotchViewModel.swift:31-58` (add store + forwarding), `Sources/State/NotchViewModel.swift:83-90` (liveActivities), `Sources/State/NotchViewModel.swift:154-169` (hasIdleContent)

**Interfaces:**
- Consumes: `TodoStore.shared`, `Todo` (Task 2).
- Produces: `NotchActivity.todos`; `SettingsStore.todosEnabled: Bool`; `NotchViewModel.todos` (public `let`), with `.todos` participating in idle resolution so the cue auto-shows/hides live.

- [ ] **Step 1: Add the `.todos` activity case**

In `Sources/State/NotchState.swift`, add `case todos` to `NotchActivity` (after `case clipboard`, line 16):

```swift
    case clipboard
    case todos
    case privacy
```

- [ ] **Step 2: Add the `todosEnabled` pref to SettingsStore**

In `Sources/State/SettingsStore.swift`, make four edits mirroring `fileTrayEnabled`:

1. Add the published property (after line 65, `fileTrayEnabled`):
```swift
    @Published var todosEnabled: Bool { didSet { persist(oldValue != todosEnabled) } }
```
2. Register the default (in the `defaults.register` dict, after `Keys.fileTrayEnabled: true,`):
```swift
            Keys.todosEnabled: true,
```
3. Load it (after the `fileTrayEnabled = defaults.bool(...)` line ~155):
```swift
        todosEnabled = defaults.bool(forKey: Keys.todosEnabled)
```
4. Persist it (in the `pairs` array, after `(Keys.fileTrayEnabled, fileTrayEnabled),`):
```swift
            (Keys.todosEnabled, todosEnabled),
```
5. Add the key (in `enum Keys`, after `static let fileTrayEnabled = "fileTrayEnabled"`):
```swift
        static let todosEnabled = "todosEnabled"
```

- [ ] **Step 3: Hold the store and forward its changes in NotchViewModel**

In `Sources/State/NotchViewModel.swift`:

a. Add a cancellables set and the store reference. After `let fileTray = FileTrayStore()` (line 32) add:
```swift
    let todos = TodoStore.shared
    private var todosObserver: AnyCancellable?
```

b. In `init` (lines 56-58), forward the store's changes so `content` re-resolves when tasks change (auto show/hide):
```swift
    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? .shared
        todosObserver = todos.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
```

c. In `liveActivities` (lines 83-90), append `.todos` when enabled and non-empty, after the `.playing` append (so media stays the default when it's playing, but tasks show at idle when nothing else is live and remain swipeable):
```swift
        if nowPlaying != nil { result.append(.playing) }
        if settings.todosEnabled, !todos.isEmpty { result.append(.todos) }
        if let battery, battery.isPluggedIn || battery.isCharging { result.append(.battery) }
```

d. In `hasIdleContent(_:)` (the switch at line 155), add the `.todos` case (after `case .clipboard: return true`):
```swift
        case .clipboard: return true
        case .todos: return settings.todosEnabled && !todos.isEmpty
```

- [ ] **Step 4: Build to verify wiring compiles (partial — UI switches added next task)**

Run the **Build command**.
Expected: FAIL — the compiler now flags every remaining exhaustive switch missing `.todos`: `GeneralPane` (`pickerTitle`, `pickerImage`), `NotchSizing` (idle + expanded), `IdleCompactView` (leading + trailing), `NotchRootView` (expanded), `DebugRender` (expanded). This is the expected checklist for Tasks 4–6. Do NOT fix them here.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/NotchState.swift Sources/State/SettingsStore.swift Sources/State/NotchViewModel.swift
git commit -m "feat: wire .todos activity, todosEnabled pref, and content resolution"
```

---

## Task 4: Compact idle cue + notch sizing + picker labels

**Files:**
- Modify: `Sources/NotchUI/States/IdleCompactView.swift:44-89` (leading), `:91-136` (trailing)
- Modify: `Sources/NotchUI/NotchSizing.swift:19-45` (idle), `:66-88` (expanded)
- Modify: `Sources/Settings/GeneralPane.swift:82-113` (pickerTitle + pickerImage)

**Interfaces:**
- Consumes: `TodoStore.shared`, `NotchActivity.todos`.
- Produces: the compact cue rendering (`☐ <next title>`), the idle + expanded notch sizes for `.todos`, and the idle-activity picker label/icon. After this task the app compiles except for the two expanded-view routers (Task 5) and the Settings section (Task 6).

- [ ] **Step 1: Add a `.todos` observer to IdleCompactView and render the cue**

In `Sources/NotchUI/States/IdleCompactView.swift`:

a. Add an observed store near the top of the struct (after `let metrics: NotchMetrics`, line 18). `IdleCompactView` already reads `SettingsStore.shared` directly, so reading `TodoStore.shared` here is consistent:
```swift
    @ObservedObject private var todos = TodoStore.shared
```

b. In the `leading` switch (add before `case .privacy:` at line 83) — a circle checkbox that completes the top open task:
```swift
        case .todos:
            Button {
                if let id = todos.next?.id { todos.complete(id) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
```

c. In the `trailing` switch (add before `case .privacy:` at line 125) — the next task's title, truncated to fit the wing:
```swift
        case .todos:
            Text(todos.next?.title ?? "All clear")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 96, alignment: .trailing)
```

- [ ] **Step 2: Add `.todos` sizes to NotchSizing**

In `Sources/NotchUI/NotchSizing.swift`:

a. In the idle switch (before `case .privacy:` at line 41), size it like `.timer` (icon + short text):
```swift
            case .todos:
                return NotchSizing(width: w + 128, height: h + 2, topRadius: 8, bottomRadius: 11)
```

b. In the expanded switch (before `case .privacy:` at line 84), size it like `.clipboard` (a scrollable list + quick-add):
```swift
            case .todos:
                return NotchSizing(width: max(w + 40, 420), height: 220, topRadius: 10, bottomRadius: 24)
```

- [ ] **Step 3: Add `.todos` picker label + icon**

In `Sources/Settings/GeneralPane.swift`:

a. In `pickerTitle` (before `case .privacy:` at line 94):
```swift
        case .todos: return "Tasks"
```
b. In `pickerImage` (before `case .privacy:` at line 110):
```swift
        case .todos: return "checklist"
```

- [ ] **Step 4: Build — expect only the two expanded routers to remain**

Run the **Build command**.
Expected: FAIL with exactly two remaining errors — `NotchRootView.swift` and `DebugRender.swift` expanded switches missing `.todos`. (No errors from `IdleCompactView`, `NotchSizing`, or `GeneralPane`.)

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchUI/States/IdleCompactView.swift Sources/NotchUI/NotchSizing.swift Sources/Settings/GeneralPane.swift
git commit -m "feat: add todos compact cue, notch sizing, and picker label"
```

---

## Task 5: Expanded interactive panel + routing

**Files:**
- Create: `Sources/NotchUI/States/TodoExpandedView.swift`
- Modify: `Sources/NotchUI/NotchRootView.swift:67-92` (add `.todos` route)
- Modify: `Sources/App/DebugRender.swift:100-112` (add `.todos` route)

**Interfaces:**
- Consumes: `TodoStore.shared`, `NotchMetrics`.
- Produces: `struct TodoExpandedView: View { let metrics: NotchMetrics }` — the checklist panel with per-row complete + drag reorder, a quick-add field, and an empty state.

- [ ] **Step 1: Create the expanded view**

Create `Sources/NotchUI/States/TodoExpandedView.swift`. Mirrors `ClipboardExpandedView`'s header/padding conventions; adds a `List` for reorder + a focused quick-add field:

```swift
import SwiftUI

/// The expanded task panel: a reorderable checklist with per-row check-off
/// (strike-through, then auto-remove) and a quick-add field at the bottom.
struct TodoExpandedView: View {
    @ObservedObject private var store = TodoStore.shared
    let metrics: NotchMetrics

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if store.openCount > 0 {
                    Text("\(store.openCount) left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if store.items.isEmpty {
                Text("All clear ✓ — add a task below.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(store.items) { todo in
                        row(todo)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.easeInOut(duration: 0.25), value: store.items)
            }

            quickAdd
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { addFocused = true }
    }

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
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($addFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        store.add(newTitle)
        newTitle = ""
        addFocused = true
    }
}
```

- [ ] **Step 2: Route `.expanded(.todos)` in NotchRootView**

In `Sources/NotchUI/NotchRootView.swift`, add to the expanded switch (before `case .privacy:` at line 88):
```swift
            case .todos:
                TodoExpandedView(metrics: metrics)
```

- [ ] **Step 3: Route `.todos` in DebugRender**

In `Sources/App/DebugRender.swift`, add to its expanded switch (before `case .privacy:` at line 110):
```swift
                    case .todos: TodoExpandedView(metrics: metrics)
```

- [ ] **Step 4: Build to verify the whole app compiles**

Run the **Build command**.
Expected: `** BUILD SUCCEEDED **` — no remaining switch errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchUI/States/TodoExpandedView.swift Sources/NotchUI/NotchRootView.swift Sources/App/DebugRender.swift
git commit -m "feat: add TodoExpandedView with quick-add, check-off, and reorder"
```

---

## Task 6: Settings pane

**Files:**
- Create: `Sources/Settings/TodosPane.swift`
- Modify: `Sources/Settings/SettingsView.swift:6-8` (enum case), `:12-54` (title/image/tint), `:92-95` (sidebar list), `:147-166` (content routing)

**Interfaces:**
- Consumes: `SettingsStore.todosEnabled`, `TodoStore.shared`, existing `PaneHeader`, `SectionLabel`, `CardGroup`, `ToggleRow`.
- Produces: a `.tasks` `SettingsSection` and `TodosPane` for full list management.

- [ ] **Step 1: Add the `.tasks` settings section**

In `Sources/Settings/SettingsView.swift`:

a. Add the enum case (line 7, in the `Live Activities` group of cases):
```swift
    case nowPlaying, calendar, fileTray, dictation, stats, claudeStats, timer, clipboard, tasks, privacyDot
```
b. `title` (before `case .privacyDot:` at line 28):
```swift
        case .tasks: return "Tasks"
```
c. `systemImage` (before `case .privacyDot:` at line 50):
```swift
        case .tasks: return "checklist"
```
d. `tint` (before `case .privacyDot:` at line 72):
```swift
        case .tasks: return .yellow
```
e. Sidebar list (line 93-94), add `.tasks` to the `Live Activities` `ForEach`:
```swift
                Section("Live Activities") {
                    ForEach([SettingsSection.nowPlaying, .calendar, .fileTray, .dictation,
                             .stats, .claudeStats, .timer, .clipboard, .tasks, .privacyDot]) { row($0) }
                }
```
f. Content routing (in the `content` switch, before `case .privacyDot:` at line 161):
```swift
        case .tasks: TodosPane(settings: settings)
```

- [ ] **Step 2: Create the pane**

Create `Sources/Settings/TodosPane.swift`. Uses the shared pane building blocks; provides the enable toggle plus full list management (add / edit / delete / reorder / clear):

```swift
import SwiftUI

/// Settings for the notch task list: enable toggle plus full management of the
/// tasks (add, rename, delete, reorder, clear). Shares `TodoStore.shared` with
/// the notch, so edits here reflect live in the notch and vice versa.
struct TodosPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var store = TodoStore.shared
    @State private var newTitle = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .tasks)

            SectionLabel("Notch")
            CardGroup {
                ToggleRow(title: "Show tasks in the notch", isOn: $settings.todosEnabled)
            }
            Text("Your next task rests in the notch when you have open tasks, and disappears when the list is clear. Check tasks off or add new ones from the notch, or manage the full list here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            SectionLabel("Tasks")
            CardGroup {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                    TextField("Add a task…", text: $newTitle)
                        .textFieldStyle(.plain)
                        .onSubmit(addTask)
                }
                if !store.items.isEmpty {
                    Divider()
                    // Add / rename / delete here; drag-to-reorder is the notch's
                    // expanded list (a CardGroup isn't a reorderable List, and
                    // order = priority is most useful right where you glance at it).
                    ForEach(store.items) { todo in
                        HStack(spacing: 8) {
                            TextField("Task", text: binding(for: todo))
                                .textFieldStyle(.plain)
                            Spacer()
                            Button {
                                store.remove(todo.id)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        if todo.id != store.items.last?.id { Divider() }
                    }
                }
            }

            if !store.items.isEmpty {
                Button("Clear all tasks", role: .destructive) { confirmClear = true }
                    .buttonStyle(.link)
                    .confirmationDialog("Clear all tasks?", isPresented: $confirmClear) {
                        Button("Clear all", role: .destructive) { store.clear() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            Spacer()
        }
    }

    private func addTask() {
        store.add(newTitle)
        newTitle = ""
    }

    /// A binding that renames the task on edit; empty edits are ignored by
    /// `updateTitle`, so the displayed value falls back to the stored title.
    private func binding(for todo: Todo) -> Binding<String> {
        Binding(
            get: { store.items.first { $0.id == todo.id }?.title ?? todo.title },
            set: { store.updateTitle(todo.id, to: $0) }
        )
    }
}
```

- [ ] **Step 3: Build to verify Settings compiles**

Run the **Build command**.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Settings/TodosPane.swift Sources/Settings/SettingsView.swift
git commit -m "feat: add Tasks settings pane"
```

---

## Task 7: Full-flow verification in the running app

**Files:** none (manual verification + final commit if any tweak needed)

**Interfaces:** Consumes everything above. No new code unless a defect is found.

- [ ] **Step 1: Run the full test suite once more**

Run the **Test command**.
Expected: `** TEST SUCCEEDED **` (Smoke + all `TodoStoreTests`).

- [ ] **Step 2: Launch the app and verify the end-to-end flow**

Use the project's run path (`/run` skill or the built `.app` under `build/`). Verify, in order:

1. **Settings › Tasks** exists in the Live Activities sidebar group with a checklist icon; the "Show tasks in the notch" toggle is ON by default.
2. Add 2–3 tasks in the pane → they appear in the list; rename one inline → persists; delete one → removed.
3. Set **General › Idle activity** to **Tasks** (or leave Auto with nothing else live). The compact notch shows `☐ <top task>` and **hides when the list is empty**.
4. **Hover/expand** the notch → the task list shows; type in the quick-add field + Return → task appears at the bottom; tap a row's circle → it strikes through, then vanishes after ~0.9s; drag a row → reorder sticks.
5. Tap the compact cue's checkbox (collapsed state) → top task completes (strike-through → vanish). If the tap instead expands the notch (gesture precedence), note it — the expanded-row check-off is the primary path and this is an acceptable v1 limitation.
6. Quit and relaunch → the task list persists (loaded from `UserDefaults`).

- [ ] **Step 3: If any defect is found, fix minimally, rebuild, and commit**

```bash
git add -A
git commit -m "fix: <specific issue found during verification>"
```

If no defects: the feature is complete; nothing to commit.

---

## Notes / known v1 limitations (from the spec)

- **Empty-list quick-add in Auto mode:** when the list is empty *and* idle activity is Auto with something else live, there's no notch entry point to add the first task (hovering expands the other activity). Add via Settings, or set idle activity to **Tasks** to always have the expand-to-quick-add path. Documented, acceptable for v1.
- **Reorder location:** drag-to-reorder lives in the notch's expanded list (order = priority, glanceable right where you use it). The Settings pane does add / rename / delete / clear. This is a minor scope trim from the spec's "reorder in Settings too" — flag it if you want reorder in Settings as well (would require restructuring the pane around a `List`).
- **iCloud sync** is last-writer-wins on the whole array, matching how `SettingsStore` mirrors scalars.
- No due dates, priority flags, tags, or completed-history — deliberately out of scope (pure checklist).
