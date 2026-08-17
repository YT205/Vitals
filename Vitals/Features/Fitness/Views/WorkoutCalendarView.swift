import SwiftData
import SwiftUI

/// Month grid showing which days you trained. Tap a day to see what you did.
struct WorkoutCalendarView: View {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt
    )
    private var sessions: [WorkoutSession]

    @State private var monthAnchor = Date.now
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    /// Days that have at least one finished workout, normalized to start of day.
    private var trainedDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// The grid: leading blanks for alignment, then every day of the month.
    private var gridDays: [Date?] {
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor),
            let dayCount = calendar.range(of: .day, in: .month, for: monthAnchor)?.count
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            days.append(calendar.date(byAdding: .day, value: offset, to: monthInterval.start))
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var selectedDayWorkouts: [WorkoutSession] {
        guard let selectedDay else { return [] }
        return sessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: selectedDay)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }

            if let selectedDay, !selectedDayWorkouts.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedDay.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(selectedDayWorkouts) { session in
                        HStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                            Text(session.title)
                                .font(.footnote)
                            Spacer()
                            Text(session.formattedDuration)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text(monthTitle)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous month")

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next month")
            .disabled(isCurrentMonth)
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let normalized = calendar.startOfDay(for: day)
        let trained = trainedDays.contains(normalized)
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isFuture = normalized > calendar.startOfDay(for: .now)

        Button {
            selectedDay = isSelected ? nil : normalized
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isFuture ? .tertiary : (isToday ? Color.accentColor : .primary)
                    )
                Circle()
                    .fill(trained ? Color.accentColor : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture || !trained)
        .accessibilityLabel(accessibilityLabel(for: day, trained: trained))
    }

    // MARK: - Helpers

    private var isCurrentMonth: Bool {
        calendar.isDate(monthAnchor, equalTo: .now, toGranularity: .month)
    }

    private func shiftMonth(by value: Int) {
        if let shifted = calendar.date(byAdding: .month, value: value, to: monthAnchor) {
            monthAnchor = shifted
            selectedDay = nil
        }
    }

    private func accessibilityLabel(for day: Date, trained: Bool) -> String {
        let dateText = day.formatted(date: .long, time: .omitted)
        return trained ? "\(dateText), worked out" : dateText
    }
}

#Preview {
    List {
        Section {
            WorkoutCalendarView()
        }
    }
    .environment(AppSettings())
    .modelContainer(VitalsModelContainer.preview)
}
