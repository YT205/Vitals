import Charts
import SwiftData
import SwiftUI

/// Progress hub: every exercise you have logged sets for, with a chart of how
/// it's moving over time.
struct ExerciseProgressView: View {
    @Query(
        filter: #Predicate<SetEntry> { $0.isDone && !$0.isWarmup },
        sort: \SetEntry.completedAt
    )
    private var allSets: [SetEntry]

    @State private var search = ""

    /// One row per exercise, ordered by most recently trained.
    private var exercises: [(name: String, sets: [SetEntry])] {
        let grouped = Dictionary(grouping: allSets, by: \.exerciseName)
        return grouped
            .map { (name: $0.key, sets: $0.value) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.sets.last?.completedAt ?? .distantPast
                let rhsDate = rhs.sets.last?.completedAt ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    var body: some View {
        List {
            if allSets.isEmpty {
                EmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No data yet",
                    message: "Finish a workout and each exercise's progress shows up here."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(exercises, id: \.name) { exercise in
                    NavigationLink {
                        ExerciseChartView(name: exercise.name, sets: exercise.sets)
                    } label: {
                        row(exercise)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search exercises")
        .navigationTitle("Progress")
    }

    @ViewBuilder
    private func row(_ exercise: (name: String, sets: [SetEntry])) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.body.weight(.medium))
            HStack(spacing: 10) {
                Label("\(exercise.sets.count) sets", systemImage: "list.bullet")
                if let last = exercise.sets.last?.completedAt {
                    Label(
                        last.formatted(.relative(presentation: .named)),
                        systemImage: "clock"
                    )
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// The actual chart for one exercise.
struct ExerciseChartView: View {
    @Environment(AppSettings.self) private var settings

    let name: String
    let sets: [SetEntry]

    enum Metric: String, CaseIterable, Identifiable {
        case heaviest = "Heaviest"
        case oneRepMax = "Est. 1RM"
        case volume = "Volume"
        case setTime = "Set Time"

        var id: String { rawValue }
        /// Weight metrics convert to the user's unit; time renders as m:ss.
        var isWeight: Bool { self != .setTime }
    }

    @State private var metric: Metric = .heaviest

    /// One point per training day.
    private var points: [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: sets.filter { $0.completedAt != nil }) {
            calendar.startOfDay(for: $0.completedAt ?? .now)
        }

        return byDay
            .map { day, entries in
                let value: Double = switch metric {
                case .heaviest:
                    settings.displayWeight(fromKilograms: entries.map(\.weightKg).max() ?? 0)
                case .oneRepMax:
                    settings.displayWeight(
                        fromKilograms: entries.map(\.estimatedOneRepMaxKg).max() ?? 0
                    )
                case .volume:
                    settings.displayWeight(
                        fromKilograms: entries.reduce(0) { $0 + $1.volumeKg }
                    )
                case .setTime:
                    entries.reduce(0) { $0 + $1.durationSeconds }
                }
                return (date: day, value: value)
            }
            .filter { $0.value > 0 }
            .sorted { $0.date < $1.date }
    }

    private var best: Double {
        points.map(\.value).max() ?? 0
    }

    private var latest: Double {
        points.last?.value ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            StatBlock(
                                value: format(latest),
                                caption: "Latest",
                                tint: .accentColor
                            )
                            StatBlock(value: format(best), caption: "Best")
                            StatBlock(value: "\(points.count)", caption: "Sessions")
                        }

                        if points.count >= 2 {
                            chart
                        } else {
                            Text("Log this exercise a couple of times and the trend line appears.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        Chart(points, id: \.date) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value(metric.rawValue, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(Color.accentColor)

            PointMark(
                x: .value("Date", point.date),
                y: .value(metric.rawValue, point.value)
            )
            .foregroundStyle(Color.accentColor)

            AreaMark(
                x: .value("Date", point.date),
                y: .value(metric.rawValue, point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.25), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 220)
    }

    private func format(_ value: Double) -> String {
        guard metric.isWeight else {
            return WorkoutSession.formatMinutesSeconds(value)
        }
        let digits = value.rounded() == value ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return "\(number) \(settings.weightUnit.label)"
    }
}

#Preview {
    NavigationStack {
        ExerciseProgressView()
    }
    .environment(AppSettings())
    .modelContainer(VitalsModelContainer.preview)
}
