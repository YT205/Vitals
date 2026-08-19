import SwiftUI

/// One tile on the Health dashboard. Renders a dash when there's no data yet
/// rather than hiding, so you can tell the difference between "no data" and
/// "metric not supported".
struct VitalCard: View {
    @Environment(AppSettings.self) private var settings

    let kind: VitalKind
    let reading: VitalReading?
    /// Today vs the personal 30-day baseline; nil while learning or for sums.
    var status: VitalStatus?

    private func statusTint(_ status: VitalStatus) -> Color {
        switch status {
        case .aboveUsual: .orange
        case .belowUsual: .teal
        case .typical: .green
        }
    }

    /// Weight-based vitals convert kg to the user's unit; everything else uses
    /// the reading's own formatting.
    private var valueText: String {
        guard let reading else { return "--" }
        guard kind.respectsWeightUnit else { return reading.formattedValue }
        let converted = settings.displayWeight(fromKilograms: reading.value)
        return converted.formatted(.number.precision(.fractionLength(kind.fractionDigits)))
    }

    private var unitText: String {
        kind.respectsWeightUnit ? settings.weightUnit.label : kind.displayUnit
    }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(kind.tint)
                    Text(kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let reading {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(valueText)
                            .font(.title2.weight(.semibold))
                            .contentTransition(.numericText())
                        if !unitText.isEmpty {
                            Text(unitText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let status {
                        HStack(spacing: 3) {
                            Image(systemName: status.systemImage)
                                .font(.system(size: 8, weight: .bold))
                            Text(status.label)
                                .font(.caption2)
                        }
                        .foregroundStyle(statusTint(status))
                    } else {
                        Text(reading.formattedTimestamp ?? "Today")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text("--")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    ScrollView {
        LazyVGrid(columns: [GridItem(), GridItem()], spacing: 12) {
            VitalCard(
                kind: .restingHeartRate,
                reading: VitalReading(kind: .restingHeartRate, value: 54, date: .now)
            )
            VitalCard(kind: .heartRateVariability, reading: nil)
            VitalCard(
                kind: .bodyWeight,
                reading: VitalReading(kind: .bodyWeight, value: 82.5, date: .now)
            )
            VitalCard(
                kind: .bodyFat,
                reading: VitalReading(kind: .bodyFat, value: 18.2, date: .now)
            )
        }
        .padding()
    }
    .environment(AppSettings())
}
