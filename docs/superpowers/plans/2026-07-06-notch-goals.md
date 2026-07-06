# Notch Goals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a glanceable savings/progress tracker to the notch — goals with a target + deadline, logged contributions, a per-label breakdown, a pace hint, and celebrate-then-archive on completion — with full management in Settings and a pinned compact cue in the idle notch.

**Architecture:** Mirrors the existing activity pattern (Clipboard/Timer/FileTray are the live analogs): one `.shared` `@MainActor ObservableObject` store holding pure-Codable models, a new `.goals` `NotchActivity` case, a compact cue view, an expanded view, and a Settings pane. All money/pace math lives as pure functions on the `Goal`/`Contribution` value types so it can be asserted deterministically. Persistence is JSON in `UserDefaults`, iCloud-mirrored when `syncViaICloud` is on — identical to `SettingsStore`.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, Combine, XcodeGen. macOS 14.0 deployment target. No new dependencies.

## Global Constraints

- **Deployment target:** macOS 14.0. Swift 5 language mode. No new SPM packages.
- **Money type:** all amounts are `Decimal` (never `Double`/`Float`) to avoid rounding drift.
- **Currency:** single app-wide symbol, default `GHS` / `₵`, stored in `SettingsStore`. No FX conversion anywhere.
- **Persistence:** JSON `Data` under a single `UserDefaults` key; mirror the same `Data` to `NSUbiquitousKeyValueStore` when `SettingsStore.shared.syncViaICloud` is true. Decode failure ⇒ empty state, never crash.
- **Store shape:** `@MainActor final class GoalStore: ObservableObject`, singleton `static let shared`, exactly like `ClipboardStore`/`DictationHistory`. Support `GoalStore(defaults:)` dependency injection so the self-test uses an isolated `UserDefaults(suiteName:)`.
- **Regenerate after adding files:** every time you create a new `.swift` file you MUST run `xcodegen generate` before building, or Xcode won't see it.
- **Build command (the compile gate):**
  ```bash
  xcodegen generate
  xcodebuild -project Notchless.xcodeproj -scheme Notchless \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath build -skipMacroValidation build
  ```
  `-skipMacroValidation` is mandatory (the LLM.swift macro is blocked in non-interactive builds).
- **Verification approach (no XCTest target exists in this repo — do not add one):**
  - **Compile gate** — the build command above must succeed for every task.
  - **Logic gate** — pure-logic tasks add assertions to the env-gated harness `Sources/App/GoalSelfTest.swift` (built in Task 1). Run it with:
    ```bash
    DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
    ```
    It prints one `PASS <name>` / `FAIL <name>` line per check to stdout then calls `exit(0)`. A task passes only when every line is `PASS` and none is `FAIL`.
  - **Visual gate** — view/pane tasks add a case to `Sources/App/DebugRender.swift` and verify the PNG is written:
    ```bash
    DI_DEBUG_RENDER=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
    ```
  - **Manual gate** — the final view/pane tasks include a short human run-through (launch the app, add a goal, watch the notch).
- **Red/green rhythm adaptation:** "write the failing test" = add the assertion(s) to `GoalSelfTest` (or the compile-time reference) and watch it FAIL/not-compile; "make it pass" = implement; then rerun the harness.

---

## File Structure

**Create:**
- `Sources/State/GoalStore.swift` — `Contribution` + `Goal` models, derived values, `PaceStatus` + pace logic, currency formatting free functions, and the `GoalStore` `ObservableObject` (CRUD + persistence).
- `Sources/App/GoalSelfTest.swift` — env-gated assertion harness for all pure logic.
- `Sources/NotchUI/States/GoalCompactView.swift` — pinned-goal compact cue (ring + %).
- `Sources/NotchUI/States/GoalExpandedView.swift` — full list, breakdown, quick-log, celebration.
- `Sources/Settings/GoalsPane.swift` — Settings management pane.

**Modify:**
- `Sources/State/SettingsStore.swift` — add `goalsEnabled`, `currencyCode`, `currencySymbol` (default `true` / `"GHS"` / `"₵"`), wired through register/load/persist/Keys.
- `Sources/State/NotchState.swift` — add `case goals` to `NotchActivity`.
- `Sources/State/NotchViewModel.swift` — hold `GoalStore.shared`, forward its changes, resolve `.goals` idle content with auto-hide.
- `Sources/NotchUI/States/IdleCompactView.swift` — render `.goals` leading/trailing via `GoalCompactView`.
- `Sources/NotchUI/NotchRootView.swift` — route `.expanded(.goals)` to `GoalExpandedView`.
- `Sources/Settings/GeneralPane.swift` — add `.goals` to `pickerTitle` / `pickerImage`.
- `Sources/Settings/SettingsView.swift` — register the `goals` sidebar section + pane.
- `Sources/App/AppDelegate.swift` — call `GoalSelfTest.run()` early in launch.
- `Sources/App/DebugRender.swift` — add goal compact/expanded/pane render cases.

---

## Task 1: Goal & Contribution models, derived values, self-test harness

**Files:**
- Create: `Sources/State/GoalStore.swift`
- Create: `Sources/App/GoalSelfTest.swift`
- Modify: `Sources/App/AppDelegate.swift` (add one call in `applicationDidFinishLaunching`)

**Interfaces:**
- Produces:
  - `struct Contribution: Identifiable, Codable, Equatable { let id: UUID; var amount: Decimal; var label: String; var date: Date }`
  - `struct Goal: Identifiable, Codable, Equatable { let id: UUID; var name: String; var target: Decimal; var startDate: Date; var deadline: Date; var contributions: [Contribution]; var completedAt: Date? }`
  - `var Goal.current: Decimal` (sum of contribution amounts)
  - `var Goal.fraction: Double` (current/target, clamped 0…1; 0 when target ≤ 0)
  - `var Goal.breakdown: [(label: String, total: Decimal)]` (grouped by label, summed, sorted by total descending then label ascending for stable order)
  - `enum GoalSelfTest { @MainActor static func run() }`

- [ ] **Step 1: Write the model + derived values**

Create `Sources/State/GoalStore.swift`:

```swift
import SwiftUI
import Combine

/// One logged deposit toward a goal. Amount is normally positive; a correction
/// is an explicit negative entry. `label` groups deposits in the breakdown.
struct Contribution: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Decimal
    var label: String
    var date: Date

    init(id: UUID = UUID(), amount: Decimal, label: String, date: Date) {
        self.id = id
        self.amount = amount
        self.label = label
        self.date = date
    }
}

/// A savings/progress goal: a target amount to reach by a deadline, made up of
/// logged contributions. Pure value type — all math lives here so it is
/// deterministically testable.
struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var target: Decimal
    var startDate: Date
    var deadline: Date
    var contributions: [Contribution]
    var completedAt: Date?

    init(id: UUID = UUID(), name: String, target: Decimal, startDate: Date,
         deadline: Date, contributions: [Contribution] = [], completedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.startDate = startDate
        self.deadline = deadline
        self.contributions = contributions
        self.completedAt = completedAt
    }

    /// Sum of all logged contributions (true total; may exceed target).
    var current: Decimal { contributions.reduce(0) { $0 + $1.amount } }

    /// Progress in 0…1 for bars/rings. Clamped; 0 when target is non-positive.
    var fraction: Double {
        guard target > 0 else { return 0 }
        let ratio = (current as NSDecimalNumber).doubleValue / (target as NSDecimalNumber).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// Whole-number percent for display (0…100).
    var percent: Int { Int((fraction * 100).rounded()) }

    /// Per-label totals, largest first (label ascending as a stable tiebreak).
    var breakdown: [(label: String, total: Decimal)] {
        var totals: [String: Decimal] = [:]
        for c in contributions { totals[c.label, default: 0] += c.amount }
        return totals
            .map { (label: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.label < $1.label }
    }
}
```

- [ ] **Step 2: Write the self-test harness with the model assertions**

Create `Sources/App/GoalSelfTest.swift`:

```swift
import Foundation

/// Dev-only deterministic assertions for Goal math and GoalStore behavior.
/// Runs only when DI_GOAL_SELFTEST is set (mirrors DI_DEBUG_RENDER), prints one
/// PASS/FAIL line per check, then exits so it is scriptable from the CLI.
@MainActor
enum GoalSelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["DI_GOAL_SELFTEST"] != nil }

    private static var failures = 0

    private static func check(_ name: String, _ condition: Bool) {
        if condition { print("PASS \(name)") }
        else { print("FAIL \(name)"); failures += 1 }
    }

    // Fixed clock so nothing depends on the real date.
    private static let t0 = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
    private static func days(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }

    static func run() {
        guard isEnabled else { return }

        modelChecks()
        // Later tasks append: paceChecks(); formatChecks(); storeChecks()

        print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }

    private static func modelChecks() {
        let g = Goal(name: "Save", target: 100_000, startDate: t0, deadline: days(100),
                     contributions: [
                        Contribution(amount: 25_000, label: "MTN stocks", date: t0),
                        Contribution(amount: 12_000, label: "Petra", date: t0),
                        Contribution(amount: 5_000, label: "MTN stocks", date: t0),
                     ])
        check("current sums contributions", g.current == 42_000)
        check("percent rounds fraction", g.percent == 42)
        let bd = g.breakdown
        check("breakdown groups by label", bd.count == 2)
        check("breakdown sorts largest first", bd.first?.label == "MTN stocks" && bd.first?.total == 30_000)

        let over = Goal(name: "x", target: 100, startDate: t0, deadline: days(1),
                        contributions: [Contribution(amount: 150, label: "a", date: t0)])
        check("fraction clamps at 1", over.fraction == 1.0)
        let zero = Goal(name: "z", target: 0, startDate: t0, deadline: days(1))
        check("fraction is 0 for non-positive target", zero.fraction == 0)
    }
}
```

- [ ] **Step 3: Wire the harness into launch**

In `Sources/App/AppDelegate.swift`, inside `applicationDidFinishLaunching(_:)`, add as the **first** line of the method body (before any window/service setup so it exits fast):

```swift
        GoalSelfTest.run()   // no-op unless DI_GOAL_SELFTEST is set
```

- [ ] **Step 4: Regenerate, build, run the harness (expect PASS)**

```bash
xcodegen generate
xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
```
Expected stdout includes:
```
PASS current sums contributions
PASS percent rounds fraction
PASS breakdown groups by label
PASS breakdown sorts largest first
PASS fraction clamps at 1
PASS fraction is 0 for non-positive target
SELFTEST OK
```

- [ ] **Step 5: Commit**

```bash
git add Sources/State/GoalStore.swift Sources/App/GoalSelfTest.swift Sources/App/AppDelegate.swift project.yml
git commit -m "Add Goal/Contribution models + goal self-test harness"
```

---

## Task 2: Pace logic

**Files:**
- Modify: `Sources/State/GoalStore.swift` (append `PaceStatus` + `Goal.pace`)
- Modify: `Sources/App/GoalSelfTest.swift` (add `paceChecks()`, call it in `run()`)

**Interfaces:**
- Consumes: `Goal` (Task 1).
- Produces:
  - `enum PaceStatus: Equatable { case onTrack; case ahead(Decimal); case behind(Decimal); case overdue }`
  - `func Goal.pace(now: Date) -> PaceStatus`

- [ ] **Step 1: Add the failing pace assertions**

In `Sources/App/GoalSelfTest.swift`, add this method and call `paceChecks()` from `run()` (right after `modelChecks()`):

```swift
    private static func paceChecks() {
        // target 100k over 100 days; halfway ⇒ expected 50k.
        func goal(_ current: Decimal) -> Goal {
            Goal(name: "g", target: 100_000, startDate: t0, deadline: days(100),
                 contributions: current == 0 ? [] : [Contribution(amount: current, label: "a", date: t0)])
        }
        check("pace on-track at expected", goal(50_000).pace(now: days(50)) == .onTrack)
        check("pace within dead-band is on-track", goal(51_000).pace(now: days(50)) == .onTrack)
        check("pace ahead past dead-band", goal(53_000).pace(now: days(50)) == .ahead(3_000))
        check("pace behind past dead-band", goal(40_000).pace(now: days(50)) == .behind(10_000))
        check("pace overdue when past deadline unmet", goal(90_000).pace(now: days(101)) == .overdue)
        check("pace not overdue when target met", goal(100_000).pace(now: days(101)) == .onTrack)
    }
```

- [ ] **Step 2: Run harness to verify it fails**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
```
Expected: **compile error** — `pace(now:)` and `PaceStatus` do not exist yet.

- [ ] **Step 3: Implement pace logic**

In `Sources/State/GoalStore.swift`, add at file scope (below `Goal`):

```swift
/// Whether a goal is keeping up with the straight-line pace implied by its
/// start→deadline window. `ahead`/`behind` carry the money gap vs. expected.
enum PaceStatus: Equatable {
    case onTrack
    case ahead(Decimal)
    case behind(Decimal)
    case overdue
}

extension Goal {
    /// Compares actual `current` against the linear expected amount for `now`.
    /// A ±2%-of-target dead-band keeps the status from flickering at the line.
    func pace(now: Date) -> PaceStatus {
        if now > deadline && current < target { return .overdue }

        let total = deadline.timeIntervalSince(startDate)
        guard total > 0 else { return .onTrack }
        let elapsed = min(max(now.timeIntervalSince(startDate), 0), total)
        let ratio = elapsed / total
        let expected = target * Decimal(ratio)         // clamped by ratio ∈ 0…1
        let delta = current - expected
        let band = target * Decimal(0.02)

        if abs(delta) <= band { return .onTrack }
        return delta > 0 ? .ahead(delta) : .behind(-delta)
    }
}
```

- [ ] **Step 4: Run harness to verify PASS**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
```
Expected: all six `PASS pace …` lines and `SELFTEST OK`.

> Note on Decimal: `target * Decimal(0.02)` for target 100_000 yields 2_000, and `abs()` on `Decimal` is `Swift.abs` (available). If `abs` fails to resolve, use `(delta < 0 ? -delta : delta)`.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/GoalStore.swift Sources/App/GoalSelfTest.swift
git commit -m "Add goal pace status (ahead/behind/on-track/overdue)"
```

---

## Task 3: Currency formatting + SettingsStore prefs

**Files:**
- Modify: `Sources/State/GoalStore.swift` (append formatting free functions)
- Modify: `Sources/State/SettingsStore.swift` (add `goalsEnabled`, `currencyCode`, `currencySymbol`)
- Modify: `Sources/App/GoalSelfTest.swift` (add `formatChecks()`)

**Interfaces:**
- Produces:
  - `func goalFormatAmount(_ amount: Decimal, symbol: String) -> String` — grouped, no decimals, e.g. `"42,000 ₵"`.
  - `func goalAbbreviate(_ amount: Decimal, symbol: String) -> String` — compact, e.g. `"100k ₵"`, `"1.5k ₵"`, `"250 ₵"`, `"1.2m ₵"`.
  - `SettingsStore.goalsEnabled: Bool` (default `true`), `SettingsStore.currencyCode: String` (default `"GHS"`), `SettingsStore.currencySymbol: String` (default `"₵"`).

- [ ] **Step 1: Add the failing format assertions**

In `GoalSelfTest.swift`, add and call `formatChecks()` from `run()`:

```swift
    private static func formatChecks() {
        check("format groups thousands", goalFormatAmount(42_000, symbol: "₵") == "42,000 ₵")
        check("format handles small", goalFormatAmount(250, symbol: "₵") == "250 ₵")
        check("abbrev k whole", goalAbbreviate(100_000, symbol: "₵") == "100k ₵")
        check("abbrev k decimal", goalAbbreviate(1_500, symbol: "₵") == "1.5k ₵")
        check("abbrev under 1000", goalAbbreviate(250, symbol: "₵") == "250 ₵")
        check("abbrev millions", goalAbbreviate(1_200_000, symbol: "₵") == "1.2m ₵")
    }
```

- [ ] **Step 2: Run to verify failure (compile error — functions undefined)**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
```
Expected: compile error, `goalFormatAmount` / `goalAbbreviate` undefined.

- [ ] **Step 3: Implement the formatters**

Append to `Sources/State/GoalStore.swift`:

```swift
/// Full grouped amount with the currency symbol suffixed, no decimals.
/// e.g. goalFormatAmount(42000, symbol: "₵") == "42,000 ₵"
func goalFormatAmount(_ amount: Decimal, symbol: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    let n = f.string(from: amount as NSDecimalNumber) ?? "0"
    return "\(n) \(symbol)"
}

/// Compact amount for the notch cue. 1_000→"1k", 1_500→"1.5k", 1_200_000→"1.2m".
func goalAbbreviate(_ amount: Decimal, symbol: String) -> String {
    let value = (amount as NSDecimalNumber).doubleValue
    func trim(_ d: Double) -> String {
        // one decimal, drop a trailing ".0"
        let s = String(format: "%.1f", d)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    let body: String
    if abs(value) >= 1_000_000 { body = "\(trim(value / 1_000_000))m" }
    else if abs(value) >= 1_000 { body = "\(trim(value / 1_000))k" }
    else { body = String(Int(value.rounded())) }
    return "\(body) \(symbol)"
}
```

- [ ] **Step 4: Add the SettingsStore prefs**

In `Sources/State/SettingsStore.swift` make these edits (follow the existing triple-registration pattern exactly):

1. Add published properties near the File Tray / Timer block (after line 65, `fileTrayEnabled`):
```swift
    // Goals
    @Published var goalsEnabled: Bool { didSet { persist(oldValue != goalsEnabled) } }
    @Published var currencyCode: String { didSet { persist(oldValue != currencyCode) } }
    @Published var currencySymbol: String { didSet { persist(oldValue != currencySymbol) } }
```

2. In `defaults.register(defaults: [ … ])` add:
```swift
            Keys.goalsEnabled: true,
            Keys.currencyCode: "GHS",
            Keys.currencySymbol: "₵",
```

3. In the load block (the run of `xEnabled = defaults.bool(...)` assignments in `init`) add:
```swift
        goalsEnabled = defaults.bool(forKey: Keys.goalsEnabled)
        currencyCode = defaults.string(forKey: Keys.currencyCode) ?? "GHS"
        currencySymbol = defaults.string(forKey: Keys.currencySymbol) ?? "₵"
```

4. In the `persist` `pairs` array add:
```swift
            (Keys.goalsEnabled, goalsEnabled),
            (Keys.currencyCode, currencyCode),
            (Keys.currencySymbol, currencySymbol),
```

5. In `private enum Keys` add:
```swift
        static let goalsEnabled = "goalsEnabled"
        static let currencyCode = "currencyCode"
        static let currencySymbol = "currencySymbol"
```

- [ ] **Step 5: Build + run harness (expect all format PASS)**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
```
Expected: the six `PASS … format/abbrev …` lines and `SELFTEST OK`.

- [ ] **Step 6: Commit**

```bash
git add Sources/State/GoalStore.swift Sources/State/SettingsStore.swift Sources/App/GoalSelfTest.swift
git commit -m "Add goal currency formatting + Settings prefs (goalsEnabled, currency)"
```

---

## Task 4: GoalStore — CRUD, completion/archive, persistence

**Files:**
- Modify: `Sources/State/GoalStore.swift` (append the `GoalStore` class)
- Modify: `Sources/App/GoalSelfTest.swift` (add `storeChecks()`)

**Interfaces:**
- Consumes: `Goal`, `Contribution` (Task 1).
- Produces (`@MainActor final class GoalStore: ObservableObject`):
  - `static let shared: GoalStore`
  - `init(defaults: UserDefaults = .standard, mirrorsICloud: Bool = true)`
  - `@Published private(set) var goals: [Goal]` (active, display order)
  - `@Published private(set) var completed: [Goal]`
  - `@Published var pinnedID: UUID?`
  - `var pinned: Goal?` — active goal matching `pinnedID`, else first active
  - `var hasActiveGoals: Bool`
  - `@discardableResult func addGoal(name: String, target: Decimal, deadline: Date, startDate: Date = Date()) -> Goal?` — rejects empty name / `target ≤ 0` / `deadline ≤ startDate` (returns nil)
  - `func updateGoal(_ goal: Goal)`
  - `func deleteGoal(_ id: UUID)` (active or completed)
  - `@discardableResult func logContribution(goalID: UUID, amount: Decimal, label: String, date: Date = Date()) -> Bool` — rejects `amount == 0` / blank label; on reaching target sets `completedAt` and moves the goal to `completed`, re-pinning if needed
  - `func removeContribution(goalID: UUID, contributionID: UUID)`
  - `func setPinned(_ id: UUID?)`
  - `func restore(_ id: UUID)` — completed → active, clears `completedAt`

- [ ] **Step 1: Add the failing store assertions**

In `GoalSelfTest.swift`, add and call `storeChecks()` from `run()`. Use an isolated defaults suite so the real prefs are untouched:

```swift
    private static func storeChecks() {
        let suite = "goal.selftest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GoalStore(defaults: defaults, mirrorsICloud: false)

        // add validation
        check("addGoal rejects empty name", store.addGoal(name: " ", target: 100, deadline: days(10), startDate: t0) == nil)
        check("addGoal rejects non-positive target", store.addGoal(name: "x", target: 0, deadline: days(10), startDate: t0) == nil)
        check("addGoal rejects bad deadline", store.addGoal(name: "x", target: 100, deadline: t0, startDate: t0) == nil)

        guard let g = store.addGoal(name: "Save", target: 100, deadline: days(10), startDate: t0) else {
            check("addGoal succeeds", false); return
        }
        check("addGoal succeeds", store.goals.count == 1)
        check("first goal auto-pins", store.pinnedID == g.id)

        // log validation + sum
        check("log rejects zero", store.logContribution(goalID: g.id, amount: 0, label: "a", date: t0) == false)
        check("log rejects blank label", store.logContribution(goalID: g.id, amount: 10, label: " ", date: t0) == false)
        _ = store.logContribution(goalID: g.id, amount: 40, label: "MTN", date: t0)
        check("log adds to current", store.goals.first?.current == 40)

        // completion → archive + repin
        let g2 = store.addGoal(name: "Second", target: 50, deadline: days(10), startDate: t0)!
        _ = store.logContribution(goalID: g.id, amount: 60, label: "MTN", date: t0) // reaches 100
        check("reaching target archives goal", store.completed.contains { $0.id == g.id })
        check("completed goal leaves active list", store.goals.contains { $0.id == g.id } == false)
        check("pin moves to next active goal", store.pinnedID == g2.id)

        // persistence round-trip
        let reloaded = GoalStore(defaults: defaults, mirrorsICloud: false)
        check("goals persist across reload", reloaded.goals.contains { $0.id == g2.id })
        check("completed persist across reload", reloaded.completed.contains { $0.id == g.id })

        // corrupt data ⇒ empty, no crash
        defaults.set(Data("nonsense".utf8), forKey: "goals.store.v1")
        let corrupt = GoalStore(defaults: defaults, mirrorsICloud: false)
        check("corrupt data falls back to empty", corrupt.goals.isEmpty && corrupt.completed.isEmpty)
    }
```

- [ ] **Step 2: Run to verify failure (compile error — GoalStore undefined)**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
```
Expected: compile error, `GoalStore` type not found.

- [ ] **Step 3: Implement GoalStore**

Append to `Sources/State/GoalStore.swift`:

```swift
/// Owns the user's goals and archived (completed) goals. Persists as JSON in
/// UserDefaults, mirrored to iCloud KVS when syncViaICloud is on — the same
/// approach as SettingsStore. Mirrors the ClipboardStore/DictationHistory
/// singleton shape; views observe `.shared` directly.
@MainActor
final class GoalStore: ObservableObject {
    static let shared = GoalStore()

    @Published private(set) var goals: [Goal] = []
    @Published private(set) var completed: [Goal] = []
    @Published var pinnedID: UUID? { didSet { if oldValue != pinnedID { save() } } }

    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    private let mirrorsICloud: Bool
    private let key = "goals.store.v1"

    init(defaults: UserDefaults = .standard, mirrorsICloud: Bool = true) {
        self.defaults = defaults
        self.mirrorsICloud = mirrorsICloud
        load()
        if mirrorsICloud {
            NotificationCenter.default.addObserver(
                self, selector: #selector(cloudChanged),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud)
        }
    }

    // MARK: Derived

    var hasActiveGoals: Bool { !goals.isEmpty }

    var pinned: Goal? {
        if let pinnedID, let g = goals.first(where: { $0.id == pinnedID }) { return g }
        return goals.first
    }

    // MARK: Mutations

    @discardableResult
    func addGoal(name: String, target: Decimal, deadline: Date, startDate: Date = Date()) -> Goal? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, target > 0, deadline > startDate else { return nil }
        let goal = Goal(name: trimmed, target: target, startDate: startDate, deadline: deadline)
        goals.append(goal)
        if pinnedID == nil { pinnedID = goal.id }
        save()
        return goal
    }

    func updateGoal(_ goal: Goal) {
        guard let i = goals.firstIndex(where: { $0.id == goal.id }) else { return }
        goals[i] = goal
        save()
    }

    func deleteGoal(_ id: UUID) {
        goals.removeAll { $0.id == id }
        completed.removeAll { $0.id == id }
        if pinnedID == id { pinnedID = goals.first?.id }
        save()
    }

    @discardableResult
    func logContribution(goalID: UUID, amount: Decimal, label: String, date: Date = Date()) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount != 0, !trimmed.isEmpty,
              let i = goals.firstIndex(where: { $0.id == goalID }) else { return false }
        goals[i].contributions.append(Contribution(amount: amount, label: trimmed, date: date))
        if goals[i].current >= goals[i].target { archive(index: i, at: date) }
        save()
        return true
    }

    func removeContribution(goalID: UUID, contributionID: UUID) {
        guard let i = goals.firstIndex(where: { $0.id == goalID }) else { return }
        goals[i].contributions.removeAll { $0.id == contributionID }
        save()
    }

    func setPinned(_ id: UUID?) { pinnedID = id }

    func restore(_ id: UUID) {
        guard let i = completed.firstIndex(where: { $0.id == id }) else { return }
        var g = completed.remove(at: i)
        g.completedAt = nil
        goals.append(g)
        if pinnedID == nil { pinnedID = g.id }
        save()
    }

    /// Moves the goal at `index` from active → completed and re-pins if it was
    /// the pinned goal. Caller persists.
    private func archive(index: Int, at date: Date) {
        var g = goals.remove(at: index)
        g.completedAt = date
        completed.insert(g, at: 0)
        if pinnedID == g.id { pinnedID = goals.first?.id }
    }

    // MARK: Persistence

    private struct Payload: Codable { var goals: [Goal]; var completed: [Goal]; var pinnedID: UUID? }

    private func load() {
        let data = defaults.data(forKey: key)
            ?? (mirrorsICloud && SettingsStore.shared.syncViaICloud ? cloud.data(forKey: key) : nil)
        guard let data, let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            goals = []; completed = []; pinnedID = nil; return
        }
        goals = payload.goals
        completed = payload.completed
        pinnedID = payload.pinnedID
    }

    private func save() {
        let payload = Payload(goals: goals, completed: completed, pinnedID: pinnedID)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: key)
        if mirrorsICloud && SettingsStore.shared.syncViaICloud {
            cloud.set(data, forKey: key)
            cloud.synchronize()
        }
    }

    @objc private func cloudChanged() {
        guard mirrorsICloud, SettingsStore.shared.syncViaICloud,
              let data = cloud.data(forKey: key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        Task { @MainActor in
            goals = payload.goals; completed = payload.completed; pinnedID = payload.pinnedID
        }
    }
}
```

> Note: `pinnedID`'s `didSet` calls `save()`, and `addGoal`/`archive` also set `pinnedID` before their own `save()`. Double-save is harmless (idempotent write). The self-test uses `mirrorsICloud: false` so iCloud is never touched.

- [ ] **Step 4: Run harness (expect all store PASS)**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
```
Expected: every `PASS …` store line and `SELFTEST OK`. If any `FAIL`, fix before committing.

- [ ] **Step 5: Commit**

```bash
git add Sources/State/GoalStore.swift Sources/App/GoalSelfTest.swift
git commit -m "Add GoalStore: CRUD, completion→archive, JSON+iCloud persistence"
```

---

## Task 5: NotchActivity.goals + model wiring + auto-hide

**Files:**
- Modify: `Sources/State/NotchState.swift` (add `case goals`)
- Modify: `Sources/State/NotchViewModel.swift` (hold store, forward changes, resolve idle content)
- Modify: `Sources/Settings/GeneralPane.swift` (`pickerTitle` / `pickerImage`)

**Interfaces:**
- Consumes: `GoalStore.shared`, `SettingsStore.goalsEnabled` (Tasks 3–4).
- Produces: `.goals` is a valid `NotchActivity`; `NotchViewModel.goals: GoalStore`; idle `.goals` resolves only when `goalsEnabled` and there is a pinned/active goal.

- [ ] **Step 1: Add the enum case**

In `Sources/State/NotchState.swift`, add `case goals` to `NotchActivity` (after `case claudeUsage`):
```swift
    case claudeUsage
    case goals
```

- [ ] **Step 2: Handle the new case everywhere the compiler now demands it**

The `NotchActivity` switches are exhaustive, so the build will now fail until each is handled. Make these edits:

In `Sources/Settings/GeneralPane.swift`, add to `pickerTitle`:
```swift
        case .goals: return "Goals"
```
and to `pickerImage`:
```swift
        case .goals: return "target"
```

In `Sources/NotchUI/States/IdleCompactView.swift`, add a placeholder branch to **both** `leading` and `trailing` switches (real content comes in Task 6 — this just keeps the build green):
```swift
        case .goals:
            EmptyView()
```

In `Sources/NotchUI/NotchRootView.swift`, in the `.expanded(activity)` switch add (placeholder until Task 7):
```swift
            case .goals:
                EmptyView()
```

- [ ] **Step 3: Wire the store into the view model + forward its changes**

In `Sources/State/NotchViewModel.swift`:

1. After `let fileTray = FileTrayStore()` (line ~32) add:
```swift
    // Goals
    let goals = GoalStore.shared
```

2. Add a cancellables set near the other private vars (after line ~51):
```swift
    private var goalObserver: AnyCancellable?
```

3. In `init`, after `self.settings = settings ?? .shared`, forward store changes so `content` recomputes when goals change (the store is a separate ObservableObject):
```swift
        goalObserver = goals.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
```

4. In `hasIdleContent(_:)`, add a case:
```swift
        case .goals: return settings.goalsEnabled && goals.hasActiveGoals
```

5. In `activeExpandedActivity`'s `default` branch the existing `return settings.idleActivity` already covers `.goals`; no change needed there.

> `.goals` is intentionally NOT added to `liveActivities`/`carouselActivities` — it's an explicit idle pick (like `.clipboard`/`.stats`), not an auto-carousel activity. Under `.auto` idle mode it won't appear; that matches the spec's "auto-hide, explicit pick falls back to bare when empty."

- [ ] **Step 4: Build (compile gate) + confirm logic still green**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_GOAL_SELFTEST=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
```
Expected: build succeeds; harness still prints `SELFTEST OK` (no regressions).

- [ ] **Step 5: Commit**

```bash
git add Sources/State/NotchState.swift Sources/State/NotchViewModel.swift Sources/Settings/GeneralPane.swift \
  Sources/NotchUI/States/IdleCompactView.swift Sources/NotchUI/NotchRootView.swift
git commit -m "Wire .goals activity into state machine with empty-list auto-hide"
```

---

## Task 6: GoalCompactView (pinned cue) + IdleCompactView integration

**Files:**
- Create: `Sources/NotchUI/States/GoalCompactView.swift`
- Modify: `Sources/NotchUI/States/IdleCompactView.swift` (use it for `.goals`)
- Modify: `Sources/App/DebugRender.swift` (render the compact cue)

**Interfaces:**
- Consumes: `GoalStore.shared`, `goalAbbreviate` (Tasks 3–4).
- Produces: `struct GoalCompactView: View` (a small ring + `NN% · <target>` reading the pinned goal).

- [ ] **Step 1: Create the compact cue**

Create `Sources/NotchUI/States/GoalCompactView.swift`:

```swift
import SwiftUI

/// Compact idle cue for the pinned goal: a progress ring + percentage on the
/// left, the abbreviated target on the right. Reads GoalStore.shared directly.
struct GoalCompactView: View {
    @ObservedObject private var store = GoalStore.shared

    /// The leading ring + percent.
    struct Ring: View {
        let fraction: Double
        let tint: Color
        var body: some View {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }

    private var symbol: String { SettingsStore.shared.currencySymbol }

    @ViewBuilder var leading: some View {
        if let g = store.pinned {
            HStack(spacing: 6) {
                Ring(fraction: g.fraction, tint: g.percent >= 100 ? .green : .white)
                Text("\(g.percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "target").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder var trailing: some View {
        if let g = store.pinned {
            Text(goalAbbreviate(g.target, symbol: symbol))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // Standalone body (used by DebugRender previews).
    var body: some View {
        HStack { leading; Spacer(minLength: 0); trailing }
    }
}
```

- [ ] **Step 2: Use it in IdleCompactView**

In `Sources/NotchUI/States/IdleCompactView.swift`, replace the `case .goals: EmptyView()` placeholders:

In `leading`:
```swift
        case .goals:
            GoalCompactView().leading
```
In `trailing`:
```swift
        case .goals:
            GoalCompactView().trailing
```

- [ ] **Step 3: Add a DebugRender case**

In `Sources/App/DebugRender.swift`, in the `.idle(let a)` branch the existing `IdleCompactView(...)` already renders any activity. Add a render call in `run(...)` alongside the others:
```swift
        render(.idle(.goals), np: nil, cal: nil, name: "state_idle_goals", metrics: metrics)
```
Because the cue reads `GoalStore.shared`, seed one goal at the top of `run(...)` (before the render calls) so the snapshot isn't empty:
```swift
        if GoalStore.shared.goals.isEmpty {
            _ = GoalStore.shared.addGoal(name: "Save 100k", target: 100_000,
                                         deadline: Date().addingTimeInterval(120 * 86_400))
            _ = GoalStore.shared.logContribution(goalID: GoalStore.shared.goals[0].id,
                                                 amount: 42_000, label: "MTN stocks")
        }
```

- [ ] **Step 4: Build + render + verify the PNG**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_DEBUG_RENDER=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
ls -la /tmp/state_idle_goals.png
```
Expected: build succeeds and `/tmp/state_idle_goals.png` exists. Open it — a ring at ~42% + "42%" on the left, "100k ₵" on the right.

> The DebugRender seeding writes to real UserDefaults. Remove the seed goal afterward if it clutters your dev app, or leave it — it's harmless test data.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchUI/States/GoalCompactView.swift Sources/NotchUI/States/IdleCompactView.swift Sources/App/DebugRender.swift
git commit -m "Add pinned-goal compact cue in the idle notch"
```

---

## Task 7: GoalExpandedView — list, breakdown, quick-log, celebration

**Files:**
- Create: `Sources/NotchUI/States/GoalExpandedView.swift`
- Modify: `Sources/NotchUI/NotchRootView.swift` (route `.expanded(.goals)`)
- Modify: `Sources/App/DebugRender.swift` (render the expanded panel)

**Interfaces:**
- Consumes: `GoalStore.shared`, `goalFormatAmount`, `Goal.pace`, `PaceStatus` (Tasks 2–4).
- Produces: `struct GoalExpandedView: View`.

- [ ] **Step 1: Create the expanded view**

Create `Sources/NotchUI/States/GoalExpandedView.swift`:

```swift
import SwiftUI

/// The expanded goals panel: every active goal with its bar, pace hint, and
/// per-label breakdown, plus a quick-log row for the focused goal.
struct GoalExpandedView: View {
    @ObservedObject private var store = GoalStore.shared
    let metrics: NotchMetrics

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool

    private var symbol: String { SettingsStore.shared.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goals").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(store.goals.count) active").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }

            if store.goals.isEmpty {
                Text("No goals yet — add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.goals) { goal in row(goal) }
                    }
                }
                quickLog
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if goal.id == store.pinnedID {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                }
                Text(goal.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            ProgressView(value: goal.fraction).tint(goal.percent >= 100 ? .green : .white)
            HStack {
                Text("\(goalFormatAmount(goal.current, symbol: symbol)) / \(goalFormatAmount(goal.target, symbol: symbol))")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(paceLabel(goal)).font(.system(size: 10, weight: .medium)).foregroundStyle(paceColor(goal))
            }
            if !goal.breakdown.isEmpty {
                ForEach(goal.breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(goalFormatAmount(item.total, symbol: symbol)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }

    private var quickLog: some View {
        HStack(spacing: 6) {
            TextField("Amount", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 70).focused($amountFocused)
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        guard let goal = focused,
              let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
        amountText = ""; labelText = ""
    }

    private func paceLabel(_ g: Goal) -> String {
        switch g.pace(now: Date()) {
        case .onTrack: return "On track"
        case .ahead(let d): return "Ahead \(goalAbbreviate(d, symbol: symbol))"
        case .behind(let d): return "Behind \(goalAbbreviate(d, symbol: symbol))"
        case .overdue: return "Overdue"
        }
    }

    private func paceColor(_ g: Goal) -> Color {
        switch g.pace(now: Date()) {
        case .onTrack: return .white.opacity(0.6)
        case .ahead: return .green
        case .behind: return .orange
        case .overdue: return .red
        }
    }
}
```

- [ ] **Step 2: Route it in NotchRootView**

In `Sources/NotchUI/NotchRootView.swift`, replace the `case .goals: EmptyView()` placeholder in the `.expanded` switch:
```swift
            case .goals:
                GoalExpandedView(metrics: metrics)
```

- [ ] **Step 3: Add a DebugRender case**

In `Sources/App/DebugRender.swift`, add to the `.expanded` switch inside `render(...)`:
```swift
                    case .goals: GoalExpandedView(metrics: metrics)
```
and add a render call in `run(...)` (the goal seeding from Task 6 covers the data):
```swift
        render(.expanded(.goals), np: nil, cal: nil, name: "state_expanded_goals", metrics: metrics)
```

- [ ] **Step 4: Build + render + verify**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_DEBUG_RENDER=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
ls -la /tmp/state_expanded_goals.png
```
Expected: `/tmp/state_expanded_goals.png` shows the "Save 100k" goal, a ~42% bar, `42,000 ₵ / 100,000 ₵`, a pace hint, and the "MTN stocks 42,000 ₵" breakdown row + the quick-log field.

- [ ] **Step 5: Commit**

```bash
git add Sources/NotchUI/States/GoalExpandedView.swift Sources/NotchUI/NotchRootView.swift Sources/App/DebugRender.swift
git commit -m "Add expanded goals panel with breakdown, pace, and quick-log"
```

---

## Task 8: GoalsPane (Settings) + sidebar registration

**Files:**
- Create: `Sources/Settings/GoalsPane.swift`
- Modify: `Sources/Settings/SettingsView.swift` (add `.goals` section + route)
- Modify: `Sources/App/DebugRender.swift` (render the pane)

**Interfaces:**
- Consumes: `GoalStore.shared`, `SettingsStore` prefs, shared UI (`CardGroup`, `ToggleRow`, `SectionLabel`, `PaneHeader`) from `GeneralPane.swift`/`SettingsView.swift`.
- Produces: `struct GoalsPane: View`; a `SettingsSection.goals` sidebar entry.

- [ ] **Step 1: Add the sidebar section**

In `Sources/Settings/SettingsView.swift`:

1. Add `goals` to the enum's Live Activities group:
```swift
    case nowPlaying, calendar, fileTray, dictation, stats, claudeStats, timer, clipboard, privacyDot, goals
```
2. In `title`: `case .goals: return "Goals"`
3. In `systemImage`: `case .goals: return "target"`
4. In `tint`: `case .goals: return .pink`
5. In the `List` Live Activities `ForEach`, append `.goals`:
```swift
                    ForEach([SettingsSection.nowPlaying, .calendar, .fileTray, .dictation,
                             .stats, .claudeStats, .timer, .clipboard, .privacyDot, .goals]) { row($0) }
```
6. In `content`'s switch: `case .goals: GoalsPane(settings: settings)`

- [ ] **Step 2: Create the pane**

Create `Sources/Settings/GoalsPane.swift`:

```swift
import SwiftUI

/// Full goal management: enable toggle, currency, add/edit/delete goals,
/// per-goal contribution log, pin selection, and the completed archive.
struct GoalsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var store = GoalStore.shared

    @State private var newName = ""
    @State private var newTarget = ""
    @State private var newDeadline = Date().addingTimeInterval(90 * 86_400)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .goals)

            CardGroup {
                ToggleRow(title: "Enable Goals", isOn: $settings.goalsEnabled)
                Divider()
                HStack {
                    Text("Currency")
                    Spacer()
                    TextField("Code", text: $settings.currencyCode).frame(width: 70)
                    TextField("Symbol", text: $settings.currencySymbol).frame(width: 50)
                }
            }

            SectionLabel("New goal")
            CardGroup {
                TextField("Name (e.g. End-of-year savings)", text: $newName)
                HStack {
                    TextField("Target amount", text: $newTarget).frame(width: 140)
                    DatePicker("Deadline", selection: $newDeadline, displayedComponents: .date).labelsHidden()
                    Spacer()
                    Button("Add") { addGoal() }.disabled(!canAdd)
                }
            }

            if !store.goals.isEmpty {
                SectionLabel("Active goals")
                ForEach(store.goals) { goal in goalCard(goal) }
            }

            if !store.completed.isEmpty {
                SectionLabel("Completed")
                ForEach(store.completed) { goal in completedRow(goal) }
            }
        }
    }

    private var canAdd: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty && Decimal(string: newTarget) != nil
    }

    private func addGoal() {
        guard let target = Decimal(string: newTarget) else { return }
        _ = store.addGoal(name: newName, target: target, deadline: newDeadline)
        newName = ""; newTarget = ""
    }

    private func goalCard(_ goal: Goal) -> some View {
        CardGroup {
            HStack {
                Text(goal.name).font(.headline)
                Spacer()
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help("Pin as the notch cue")
                Button(role: .destructive) { store.deleteGoal(goal.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)
            }
            Text("\(goalFormatAmount(goal.current, symbol: settings.currencySymbol)) / \(goalFormatAmount(goal.target, symbol: settings.currencySymbol)) · \(goal.percent)%")
                .font(.callout).foregroundStyle(.secondary)
            if !goal.contributions.isEmpty {
                Divider()
                ForEach(goal.contributions) { c in
                    HStack {
                        Text(c.label)
                        Spacer()
                        Text(goalFormatAmount(c.amount, symbol: settings.currencySymbol)).foregroundStyle(.secondary)
                        Button { store.removeContribution(goalID: goal.id, contributionID: c.id) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }.font(.caption)
                }
            }
        }
    }

    private func completedRow(_ goal: Goal) -> some View {
        CardGroup {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(goal.name)
                Spacer()
                Button("Restore") { store.restore(goal.id) }.buttonStyle(.borderless)
                Button(role: .destructive) { store.deleteGoal(goal.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)
            }
        }
    }
}
```

- [ ] **Step 3: Add a DebugRender case for the pane**

In `Sources/App/DebugRender.swift`, add near the other `renderPlain(...)` calls in `run(...)`:
```swift
        renderPlain(GoalsPane(settings: .shared).padding(20).frame(width: 560, height: 700)
            .background(Color(nsColor: .windowBackgroundColor)), name: "settings_goals")
```

- [ ] **Step 4: Build + render + verify**

```bash
xcodegen generate && xcodebuild -project Notchless.xcodeproj -scheme Notchless -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build -skipMacroValidation build
DI_DEBUG_RENDER=1 build/Build/Products/Debug/Notchless.app/Contents/MacOS/Notchless
ls -la /tmp/settings_goals.png
```
Expected: `/tmp/settings_goals.png` shows the enable toggle, currency row, new-goal form, and the seeded active goal card with its contribution.

- [ ] **Step 5: Manual end-to-end run-through**

```bash
open build/Build/Products/Debug/Notchless.app
```
Then, by hand:
1. Open Settings → **Goals**. Confirm the pane loads with the enable toggle + currency.
2. Add a goal (name, target, deadline). Confirm it appears as a card.
3. Set idle activity to **Goals** (General → Idle Activity) or hover the notch — confirm the pinned goal's ring + % shows in the compact notch.
4. Expand the notch → confirm the goal row, breakdown, pace hint, and quick-log field. Log a contribution from the notch; confirm the bar and Settings both update.
5. Log enough to reach the target → confirm the celebration and that the goal moves to **Completed**, and the compact cue re-pins to another goal (or disappears if none remain).

- [ ] **Step 6: Commit**

```bash
git add Sources/Settings/GoalsPane.swift Sources/Settings/SettingsView.swift Sources/App/DebugRender.swift
git commit -m "Add Goals settings pane with management + completed archive"
```

---

## Self-Review

**Spec coverage:**
- Manual + logged contributions over time → `Contribution` + `logContribution` (Task 4). ✓
- Free-form labeled contributions, breakdown by grouping → `Goal.breakdown` (Task 1), shown in expanded (Task 7) + Settings (Task 8). Label autocomplete: **deferred** — see note below.
- Pin one focused goal for the compact cue → `pinnedID`/`pinned` (Task 4), `GoalCompactView` (Task 6). ✓
- Deadline + pace → `PaceStatus`/`pace(now:)` (Task 2), rendered (Task 7). ✓
- Single app-wide currency → `currencyCode`/`currencySymbol` + formatters (Task 3). ✓
- Read-only glance + quick-log from expanded notch; management in Settings → Tasks 6/7/8. ✓
- Celebrate + auto-archive at 100%, restore/delete → `archive`/`restore` (Task 4), Completed section (Task 8). ✓
- Auto-hide when no active goals → `hasIdleContent(.goals)` (Task 5). ✓
- Persistence JSON + iCloud mirror, corrupt fallback → Task 4. ✓
- Edge cases (empty/zero/blank, target≤0, deadline≤start, over-contribution clamp, repin) → Tasks 4 + 1. ✓

**Two deliberate simplifications from the spec (both flagged there as cuttable or minor):**
- **Label autocomplete** (spec "Notch presentation" + Decisions): not wired in Task 7's quick-log to keep the first cut simple. Follow-up: back the `Label` field with a `Menu`/completions list sourced from `Set(store.goals.flatMap { $0.contributions.map(\.label) })`. Low risk; does not change the data model.
- **Pace tint on the compact ring** (spec "Optional"): the ring shows green at ≥100% but not a behind/ahead warm tint. Pace already shows in the expanded row. Add later by passing `pinned.pace(now:)` into `GoalCompactView.Ring.tint` if wanted.
- **Celebration animation** is a simple `withAnimation` list-removal + green bar, not confetti. The spec's "brief scale-glow/confetti" is a visual nicety; upgrade in `GoalExpandedView` later without touching logic.

**Placeholder scan:** no TBD/TODO left; every code step has full code. ✓

**Type consistency:** `logContribution` returns `Bool`, `addGoal` returns `Goal?`, `pace(now:)`, `goalFormatAmount(_:symbol:)`, `goalAbbreviate(_:symbol:)`, `pinnedID`/`pinned`/`setPinned` are used identically across Tasks 4–8. `Decimal` used for all money. ✓

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-06-notch-goals.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
