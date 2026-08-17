import Charts
import SwiftUI

/// Sleep drill-down: last night's full breakdown plus a stacked history chart.
/// All of it reads live from HealthKit, which keeps every night permanently.
struct SleepDetailView: View {
    /// Last night, passed from the dashboard for an instant header.
    let lastNight: SleepSummary?

    @State private var history: [(night: Date, summary: SleepSummary)] = []
    @State private var isLoading = true

    private struct StagePoint: Identifiable {
        let night: Date
        let stage: String
        let hours: Double

        var id: String { "\(night.timeIntervalSince1970)-\(stage)" }
    }

    /// Flattened per-stage rows for the stacked bar chart.
    private var stagePoints: [StagePoint] {
        history.flatMap { entry in
            [
                StagePoint(night: entry.night, stage: "Deep", hours: entry.summary.deep / 3600),
                StagePoint(night: entry.night, stage: "Core", hours: entry.summary.core / 3600),
                StagePoint(night: entry.night, stage: "REM", hours: entry.summary.rem / 3600),
            ].filter { $0.hours > 0 }
        }
    }

    private var averageAsleep: TimeInterval? {
        guard !history.isEmpty else { return nil }
        return history.map(\.summary.asleep).reduce(0, +) / Double(history.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                lastNightCard
                historyCard
                if let averageAsleep { averagesCard(averageAsleep) }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            history = (try? await HealthKitService.shared.sleepHistory(nights: 14)) ?? []
            isLoading = false
        }
    }

    // MARK: - Cards

    private var lastNightCard: some View {
        VStack(spacing: 0) {
            SleepCard(summary: lastNight)

            if let lastNight, lastNight.hasData {
                Card {
                    VStack(spacing: 10) {
                        detailRow(
                            label: "Time asleep",
                            value: SleepSummary.formatted(lastNight.asleep)
                        )
                        if lastNight.inBed > 0 {
                            detailRow(
                                label: "Time in bed",
                                value: SleepSummary.formatted(lastNight.inBed)
                            )
                        }
                        if let bedtime = lastNight.bedtime {
                            detailRow(
                                label: "Fell asleep",
                                value: bedtime.formatted(date: .omitted, time: .shortened)
                            )
                        }
                        if let wake = lastNight.wakeTime {
                            detailRow(
                                label: "Woke up",
                                value: wake.formatted(date: .omitted, time: .shortened)
                            )
                        }
                        if lastNight.awake > 0 {
                            detailRow(
                                label: "Awake during night",
                                value: SleepSummary.formatted(lastNight.awake)
                            )
                        }
                        if lastNight.asleep > 0 {
                            detailRow(
                                label: "Deep sleep share",
                                value: "\(Int((lastNight.deep / lastNight.asleep * 100).rounded()))%"
                            )
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var historyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 14 nights")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if stagePoints.isEmpty {
                    Text("No sleep history yet. Wear your watch overnight and nights stack up here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(stagePoints) { point in
                        BarMark(
                            x: .value("Night", point.night, unit: .day),
                            y: .value("Hours", point.hours)
                        )
                        .foregroundStyle(by: .value("Stage", point.stage))
                    }
                    .chartForegroundStyleScale([
                        "Deep": Color.indigo,
                        "Core": Color.blue,
                        "REM": Color.cyan,
                    ])
                    .chartYAxisLabel("hours")
                    .frame(height: 220)
                }
            }
        }
    }

    private func averagesCard(_ average: TimeInterval) -> some View {
        Card {
            HStack(alignment: .top) {
                StatBlock(
                    value: SleepSummary.formatted(average),
                    caption: "Avg asleep (14 nights)",
                    tint: .indigo
                )
                StatBlock(
                    value: SleepSummary.formatted(
                        history.map(\.summary.asleep).max() ?? 0
                    ),
                    caption: "Best night"
                )
                StatBlock(
                    value: "\(history.count)",
                    caption: "Nights tracked"
                )
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }
}

#Preview {
    NavigationStack {
        SleepDetailView(lastNight: .sample)
    }
    .environment(AppSettings())
}
