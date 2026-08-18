import SwiftUI

/// Compact vitals list: the highest-signal subset of the phone dashboard.
struct WatchVitalsView: View {
    @Environment(AppSettings.self) private var settings

    /// Watch-sized subset; the phone shows the full grid.
    private let kinds: [VitalKind] = [
        .restingHeartRate, .heartRateVariability, .bloodOxygen,
        .steps, .activeEnergy, .exerciseMinutes, .bodyWeight,
    ]

    @State private var readings: [VitalKind: VitalReading] = [:]
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(kinds) { kind in
                row(kind)
            }
        }
        .listStyle(.carousel)
        .navigationTitle("Vitals")
        .overlay {
            if isLoading && readings.isEmpty {
                ProgressView()
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func row(_ kind: VitalKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.caption)
                .foregroundStyle(kind.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let reading = readings[kind] {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(valueText(kind: kind, reading: reading))
                            .font(.body.weight(.semibold))
                        Text(unitText(kind: kind))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func valueText(kind: VitalKind, reading: VitalReading) -> String {
        guard kind.respectsWeightUnit else { return reading.formattedValue }
        return settings.displayWeight(fromKilograms: reading.value)
            .formatted(.number.precision(.fractionLength(kind.fractionDigits)))
    }

    private func unitText(kind: VitalKind) -> String {
        kind.respectsWeightUnit ? settings.weightUnit.label : kind.displayUnit
    }

    private func refresh() async {
        isLoading = true
        var result: [VitalKind: VitalReading] = [:]
        for kind in kinds {
            if let reading = try? await HealthKitService.shared.reading(for: kind) {
                result[kind] = reading
            }
        }
        readings = result
        isLoading = false
    }
}
