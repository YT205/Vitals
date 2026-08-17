import SwiftUI

/// One tile on the Health dashboard. Renders a dash when there's no data yet
/// rather than hiding, so you can tell the difference between "no data" and
/// "metric not supported".
struct VitalCard: View {
    let kind: VitalKind
    let reading: VitalReading?

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
                        Text(reading.formattedValue)
                            .font(.title2.weight(.semibold))
                            .contentTransition(.numericText())
                        if !kind.displayUnit.isEmpty {
                            Text(kind.displayUnit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(reading.formattedTimestamp ?? "Today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
                kind: .bloodOxygen,
                reading: VitalReading(kind: .bloodOxygen, value: 98.2, date: .now)
            )
            VitalCard(
                kind: .steps,
                reading: VitalReading(kind: .steps, value: 8_432, date: nil)
            )
        }
        .padding()
    }
}
