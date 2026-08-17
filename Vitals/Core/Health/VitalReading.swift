import Foundation

/// One resolved value for a vital, ready to render.
struct VitalReading: Identifiable, Sendable, Equatable {
    let kind: VitalKind
    /// Already scaled for display (see `VitalKind.displayScale`).
    let value: Double
    /// When the underlying sample ended. `nil` for daily sums.
    let date: Date?

    var id: String { kind.rawValue }

    /// The big number on the card.
    var formattedValue: String {
        if kind == .wristTemperature {
            let measurement = Measurement(value: value, unit: UnitTemperature.celsius)
            return measurement.formatted(
                .measurement(
                    width: .narrow,
                    usage: .person,
                    numberFormatStyle: .number.precision(.fractionLength(1))
                )
            )
        }
        return value.formatted(
            .number.precision(.fractionLength(kind.fractionDigits))
        )
    }

    var formattedTimestamp: String? {
        guard let date else { return nil }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.relative(presentation: .named))
    }
}

/// Summary of last night's sleep, assembled from `HKCategoryTypeIdentifier.sleepAnalysis`.
struct SleepSummary: Sendable, Equatable {
    var inBed: TimeInterval = 0
    var asleep: TimeInterval = 0
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var awake: TimeInterval = 0
    var bedtime: Date?
    var wakeTime: Date?

    var hasData: Bool { asleep > 0 || inBed > 0 }

    static func formatted(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}
