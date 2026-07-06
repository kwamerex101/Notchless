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

/// Full grouped amount with the currency symbol suffixed, no decimals.
/// e.g. goalFormatAmount(42000, symbol: "₵") == "42,000 ₵"
func goalFormatAmount(_ amount: Decimal, symbol: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    f.locale = Locale(identifier: "en_US_POSIX")
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
