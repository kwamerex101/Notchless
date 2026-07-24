import SwiftUI

/// The calendar panel: left column (weekday caps, big date, weather, next
/// event / empty state) and right column (mini month grid) — PLAN.md §1.1.
/// Flat-dark: monochrome white content, no accent colour
/// (docs/flat-dark-spec.md §3).
struct CalendarExpandedView: View {
    let snapshot: CalendarSnapshot?
    let metrics: NotchMetrics

    private var snap: CalendarSnapshot {
        snapshot ?? CalendarSnapshot(date: Date(), events: [])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftColumn
            rightColumn
        }
        .padding(.top, metrics.notchHeight + 8)
        .padding(.horizontal, 19)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snap.weekdayCaps)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.66) // 0.06em of 11pt
                .foregroundStyle(NotchTheme.textSecondary)
            Text(snap.dayNumber)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)

            if let symbol = snap.weatherSymbol, let text = snap.weatherText {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 12))
                    Text(text).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(NotchTheme.textBrightSecondary)
                .padding(.top, 8)
            }

            if snap.authDenied {
                Text("Calendar access off").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).padding(.top, 2)
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text("Enable in Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textSecondary)
                }
                .buttonStyle(.plain)
            } else if let next = snap.events.first {
                Text(next.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                    .padding(.top, 2)
            } else {
                Text("No events today").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).padding(.top, 2)
                Text("Your day is clear").font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 150, alignment: .leading)
    }

    // Month label pinned top-right, grid starts 14pt below it — PLAN §3 (Calendar).
    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(snap.monthCaps)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NotchTheme.textSecondary)
            MonthGrid(date: snap.date)
                .padding(.top, 14)
        }
        .frame(width: 190, alignment: .trailing)
    }
}
