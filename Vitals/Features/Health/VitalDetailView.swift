import Charts
import SwiftUI

/// Tap-through detail for one vital: latest value, stats, and a history chart.
/// Data comes straight from HealthKit, which already keeps the full history --
/// nothing needs to be re-saved app-side.
struct VitalDetailView: View {
    @Environment(AppSettings.self) private var settings

    let kind: VitalKind
    /// Today's reading, passed from the dashboard so the header renders
    /// instantly while history loads.
    let latest: VitalReading?

    enum Range: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "7D"
            case .month: "30D"
            case .quarter: "90D"
            }
        }
    }

    @State private var range: Range = .month
    @State private var points: [(date: Date, value: Double)] = []
    @State private var isLoading = true

    /// Chart and stat values in the user's display unit.
    private var displayPoints: [(date: Date, value: Double)] {
        guard kind.respectsWeightUnit else { return points }
        return points.map {
            (date: $0.date, value: settings.displayWeight(fromKilograms: $0.value))
        }
    }

    private var values: [Double] { displayPoints.map(\.value) }

    private var headerValueText: String {
        guard let latest else { return "--" }
        guard kind.respectsWeightUnit else { return latest.formattedValue }
        let converted = settings.displayWeight(fromKilograms: latest.value)
        return converted.formatted(.number.precision(.fractionLength(kind.fractionDigits)))
    }

    private var unitText: String {
        kind.respectsWeightUnit ? settings.weightUnit.label : kind.displayUnit
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                chartCard

                if !points.isEmpty { statsCard }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) {
            isLoading = true
            points = (try? await HealthKitService.shared.dailyHistory(
                for: kind,
                days: range.rawValue
            )) ?? []
            isLoading = false
        }
    }

    private var headerCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(kind.tint)

                VStack(alignment: .leading, spacing: 2) {
                    if let latest {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(headerValueText)
                                .font(.largeTitle.weight(.semibold))
                            if !unitText.isEmpty {
                                Text(unitText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(latest.formattedTimestamp ?? "Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.largeTitle.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text("No recent reading")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
            }
        }
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(kind.aggregation == .dailySum ? "Daily totals" : "Daily average")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if displayPoints.count < 2 {
                    Text("Not enough history in this range yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    chart
                }
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if kind.aggregation == .dailySum {
            Chart(displayPoints, id: \.date) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(kind.title, point.value)
                )
                .foregroundStyle(kind.tint.gradient)
            }
            .frame(height: 220)
        } else {
            Chart(displayPoints, id: \.date) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(kind.title, point.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(kind.tint)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(kind.title, point.value)
                )
                .foregroundStyle(kind.tint)
                .symbolSize(20)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 220)
        }
    }

    private var statsCard: some View {
        Card {
            HStack(alignment: .top) {
                StatBlock(
                    value: format(values.reduce(0, +) / Double(values.count)),
                    caption: "Average",
                    tint: kind.tint
                )
                StatBlock(value: format(values.min() ?? 0), caption: "Low")
                StatBlock(value: format(values.max() ?? 0), caption: "High")
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(kind.fractionDigits)))
    }
}

#Preview {
    NavigationStack {
        VitalDetailView(
            kind: .restingHeartRate,
            latest: VitalReading(kind: .restingHeartRate, value: 54, date: .now)
        )
    }
    .environment(AppSettings())
}
