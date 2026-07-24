import SwiftUI

/// The expanded goals panel: every active goal with its bar, pace hint, and
/// per-label breakdown, plus a quick-log row for the focused goal.
struct GoalExpandedView: View {
    // GoalStore has no isolated-instance seam (NotchViewModel.goals is a hard
    // alias onto `GoalStore.shared`, iCloud-synced) — this stays on `.shared`
    // deliberately. See DebugStateDump.seed's "Goals/Tasks are the user's
    // real shared stores" note; injecting a seam here would mean giving
    // GoalStore a non-singleton mode, which is out of scope for this pass.
    @ObservedObject private var store = GoalStore.shared
    let metrics: NotchMetrics
    /// Injected rather than read from `.shared` so the debug-dump harness's
    /// isolated settings (currency symbol) drive this too.
    let settings: SettingsStore

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    private var symbol: String { settings.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goals").notchSectionHeader()
                Spacer()
                Text("\(store.goals.count) active").font(.system(size: 11)).foregroundStyle(NotchTheme.textSecondary)
            }

            if store.goals.isEmpty {
                Text("No goals yet — add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(NotchTheme.textSecondary)
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
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { keyFocus(true) }
        .onDisappear { keyFocus(false) }
    }

    private func row(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if goal.id == store.pinnedID {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.red)
                }
                Text(goal.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                Spacer()
                Text("\(goal.percent)%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textPrimary)
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(goal.id == store.pinnedID ? .red : NotchTheme.textSecondary)
                }.buttonStyle(.plain)
            }
            goalBar(fraction: goal.fraction)
            HStack(spacing: 6) {
                Text("\(goalFormatAmount(goal.current, symbol: symbol)) / \(goalFormatAmount(goal.target, symbol: symbol))")
                    .font(.system(size: 10)).foregroundStyle(NotchTheme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer()
                Text(paceLabel(goal)).font(.system(size: 10, weight: .medium)).foregroundStyle(paceColor(goal))
            }
            HStack {
                Text("Ends \(goalFormatDate(goal.deadline))")
                    .font(.system(size: 9)).foregroundStyle(NotchTheme.textTertiary)
                Spacer()
                if let need = goal.neededPerMonth(now: Date()) {
                    Text("Need \(goalFormatAmount(need, symbol: symbol))/mo")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(NotchTheme.textSecondary)
                }
            }
            if !goal.breakdown.isEmpty {
                ForEach(goal.breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label).font(.system(size: 10)).foregroundStyle(NotchTheme.textSecondary)
                        Spacer()
                        Text(goalFormatAmount(item.total, symbol: symbol)).font(.system(size: 10)).foregroundStyle(NotchTheme.textSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
    }

    /// 4pt track/fill bar (flat-dark spec §3) — a plain `RoundedRectangle` pair
    /// instead of `ProgressView` so the height, radius, and tokens are exact.
    private func goalBar(fraction: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(NotchTheme.track)
                RoundedRectangle(cornerRadius: 2).fill(NotchTheme.fill).frame(width: width)
                    .animation(NotchMotion.fill, value: fraction)
            }
        }
        .frame(height: 4)
    }

    // Spec §3 draws this footer as a static "+ Log contribution" row; the real
    // feature needs inline Amount/Label entry, so that behaviour is kept as-is
    // and only the colours/metrics are brought onto the token system.
    private var quickLog: some View {
        HStack(spacing: 6) {
            TextField("Amount", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 70).focused($amountFocused)
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(NotchTheme.textPrimary)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textBrightSecondary.opacity(0.75))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
    }

    private func submit() {
        guard let goal = focused,
              let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchMotion.fill) { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
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

    // These panels are monochrome except `positive` (on/ahead of pace) and
    // `warning` (behind/overdue) — flat-dark spec §1 allows no other colour here.
    private func paceColor(_ g: Goal) -> Color {
        switch g.pace(now: Date()) {
        case .onTrack, .ahead: return NotchTheme.positive
        case .behind, .overdue: return NotchTheme.warning
        }
    }
}
