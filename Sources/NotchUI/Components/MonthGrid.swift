import SwiftUI

/// Mini month grid: Monday-first week header, dimmed weekends / other-month
/// days, today circled in pink, month label in pink (see PLAN.md §1.1).
struct MonthGrid: View {
    let date: Date
    var calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2 // Monday
        return c
    }()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdaySymbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { idx, s in
                    Text(s)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(idx >= 5 ? .white.opacity(0.35) : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(gridDays.indices, id: \.self) { i in
                    dayCell(gridDays[i])
                }
            }
        }
    }

    private func dayCell(_ day: GridDay) -> some View {
        let isToday = day.inMonth && calendar.isDate(day.date, inSameDayAs: date)
        let weekend = day.weekday == 1 || day.weekday == 7
        return Text("\(calendar.component(.day, from: day.date))")
            .font(.system(size: 10, weight: isToday ? .bold : .regular))
            .foregroundStyle(cellColor(inMonth: day.inMonth, weekend: weekend, isToday: isToday))
            .frame(maxWidth: .infinity, minHeight: 15)
            .background(
                Circle()
                    .fill(isToday ? Color(nsColor: .systemPink) : .clear)
                    .frame(width: 18, height: 18)
            )
    }

    private func cellColor(inMonth: Bool, weekend: Bool, isToday: Bool) -> Color {
        if isToday { return .white }
        if !inMonth { return .white.opacity(0.18) }
        if weekend { return .white.opacity(0.4) }
        return .white.opacity(0.85)
    }

    private struct GridDay { let date: Date; let inMonth: Bool; let weekday: Int }

    private var gridDays: [GridDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        var days: [GridDay] = []
        var cursor = firstWeek.start
        let month = calendar.component(.month, from: date)
        for _ in 0..<42 {
            let inMonth = calendar.component(.month, from: cursor) == month
            let weekday = calendar.component(.weekday, from: cursor)
            days.append(GridDay(date: cursor, inMonth: inMonth, weekday: weekday))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        // Trim trailing all-other-month final week for a compact 5-row look.
        if days.suffix(7).allSatisfy({ !$0.inMonth }) { days.removeLast(7) }
        return days
    }
}
