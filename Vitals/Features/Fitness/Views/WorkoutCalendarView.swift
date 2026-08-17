import SwiftData
import SwiftUI
import UIKit

/// Month grid showing which days you trained. Tap a day to see what you did.
struct WorkoutCalendarView: View {
    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt
    )
    private var sessions: [WorkoutSession]

    @State private var monthAnchor = Date.now
    @State private var selectedDay: Date?
    /// Collapsed by default: a one-row week strip. Expands to the full month.
    @State private var isExpanded = false

    private var calendar: Calendar { .current }

    /// The last 7 days, oldest first, for the compact strip.
    private var lastSevenDays: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    private var monthTitle: String {
        monthAnchor.formatted(.dateTime.month(.wide).year())
    }

    /// Days that have at least one finished workout, normalized to start of day.
    private var trainedDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// The month split into whole weeks: leading and trailing `nil`s pad each
    /// week to exactly 7 slots so every `GridRow` has the same shape.
    private var weeks: [[Date?]] {
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
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
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
            if isExpanded {
                expandedMonth
            } else {
                compactWeek
            }
        }
    }

    // MARK: - Compact strip

    /// One row: the last 7 days with a dot on training days.
    private var compactWeek: some View {
        VStack(spacing: 10) {
            HStack {
                Text("This Week")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.snappy) { isExpanded = true }
                } label: {
                    Label("Month", systemImage: "chevron.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 6) {
                ForEach(lastSevenDays, id: \.self) { day in
                    let trained = trainedDays.contains(calendar.startOfDay(for: day))
                    let isToday = calendar.isDateInToday(day)

                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.caption2.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? Color.accentColor : .primary)
                        Circle()
                            .fill(trained ? Color.accentColor : Color.gray.opacity(0.2))
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(accessibilityLabel(for: day, trained: trained))
                }
            }
        }
    }

    // MARK: - Full month

    private var expandedMonth: some View {
        VStack(spacing: 12) {
            header

            // A non-lazy Grid, on purpose. A LazyVGrid inside a self-sizing List
            // row measures against the List's size proposal while the row sizes
            // against the grid -- a feedback loop UIKit kills with a fatal
            // "recursive layout loop". A fixed month of cells doesn't need
            // laziness; Grid resolves in a single deterministic pass.
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    // ID by position, not letter: veryShortWeekdaySymbols repeats
                    // "S" and "T", and duplicate ForEach IDs are undefined behavior.
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                dayCell(day)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 34)
                            }
                        }
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
                withAnimation(.snappy) {
                    isExpanded = false
                    selectedDay = nil
                }
            } label: {
                Label("Week", systemImage: "chevron.up")
                    .font(.caption)
            }

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
                    .foregroundStyle(dayNumberColor(isFuture: isFuture, isToday: isToday))
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

    /// Concrete `Color` for the day number. `.tertiary` the hierarchical style
    /// can't sit in the same ternary as a `Color`, so future days use the
    /// equivalent UIKit label color instead.
    private func dayNumberColor(isFuture: Bool, isToday: Bool) -> Color {
        if isFuture { return Color(.tertiaryLabel) }
        if isToday { return .accentColor }
        return .primary
    }

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
