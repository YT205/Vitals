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

/// A vital's usual range, learned from its own last 30 days in HealthKit.
/// Mean plus/minus one standard deviation; needs at least 5 days of data.
struct VitalBaseline: Sendable, Equatable {
    let mean: Double
    let stdDev: Double
    let sampleCount: Int

    static func compute(from values: [Double]) -> VitalBaseline? {
        guard values.count >= 5 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(values.count)
        let stdDev = variance.squareRoot()
        guard stdDev.isFinite, stdDev > 0 else { return nil }
        return VitalBaseline(mean: mean, stdDev: stdDev, sampleCount: values.count)
    }

    var range: ClosedRange<Double> { (mean - stdDev)...(mean + stdDev) }

    func status(for value: Double) -> VitalStatus {
        if value > mean + stdDev { return .aboveUsual }
        if value < mean - stdDev { return .belowUsual }
        return .typical
    }
}

/// Where today's reading sits against the personal baseline. Deliberately
/// neutral wording: "above usual" is not "bad" -- high HRV is good, high
/// resting HR usually isn't. The app reports direction; you know the metric.
enum VitalStatus: Sendable, Equatable {
    case aboveUsual
    case belowUsual
    case typical

    var label: String {
        switch self {
        case .aboveUsual: "Above usual"
        case .belowUsual: "Below usual"
        case .typical: "Usual range"
        }
    }

    var systemImage: String {
        switch self {
        case .aboveUsual: "arrow.up.right"
        case .belowUsual: "arrow.down.right"
        case .typical: "checkmark"
        }
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
