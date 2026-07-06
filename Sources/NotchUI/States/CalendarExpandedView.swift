import SwiftUI

/// The calendar panel: left column (weekday caps, big date, weather, next
/// event / empty state) and right column (mini month grid) — PLAN.md §1.1.
struct CalendarExpandedView: View {
    let snapshot: CalendarSnapshot?
    let metrics: NotchMetrics

    private var snap: CalendarSnapshot {
        snapshot ?? CalendarSnapshot(date: Date(), events: [])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            leftColumn
            MonthGrid(date: snap.date)
                .frame(width: 190)
                .overlay(alignment: .topTrailing) {
                    Text(snap.monthCaps)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemPink))
                        .offset(y: -14)
                }
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
                .foregroundStyle(Color(nsColor: .systemPink))
            Text(snap.dayNumber)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)

            if let symbol = snap.weatherSymbol, let text = snap.weatherText {
                HStack(spacing: 5) {
                    Image(systemName: symbol).font(.system(size: 12))
                    Text(text).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.top, 8)
            }

            if let next = snap.events.first {
                Text(next.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                    .padding(.top, 2)
            } else {
                Text("No events today").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).padding(.top, 2)
                Text("Your day is clear").font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
        }
        .frame(width: 150, alignment: .leading)
    }
}
