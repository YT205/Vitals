import SwiftData
import SwiftUI

/// Every finished session, newest first.
struct WorkoutHistoryView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    )
    private var sessions: [WorkoutSession]

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyStateView(
                    systemImage: "clock.arrow.circlepath",
                    title: "No workouts yet",
                    message: "Finish a workout and it'll show up here."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(sessions) { session in
                    NavigationLink {
                        WorkoutDetailView(session: session)
                    } label: {
                        row(for: session)
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("History")
    }

    private func row(for session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(session.title)
                    .font(.body.weight(.medium))
                Spacer()
                if !session.savedToHealthKit {
                    Image(systemName: "heart.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Not saved to Apple Health")
                }
            }

            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(session.formattedDuration, systemImage: "clock")
                Label(
                    settings.formattedWeight(fromKilograms: session.totalVolumeKg),
                    systemImage: "scalemass"
                )
                Label("\(session.completedSets.count) sets", systemImage: "list.bullet")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sessions[index])
        }
        try? context.save()
    }
}

/// Read-only breakdown of a finished workout.
struct WorkoutDetailView: View {
    @Environment(AppSettings.self) private var settings
    let session: WorkoutSession

    private var groups: [(name: String, sets: [SetEntry])] {
        var result: [(String, [SetEntry])] = []
        for entry in session.orderedSets {
            if let index = result.firstIndex(where: { $0.0 == entry.exerciseName }) {
                result[index].1.append(entry)
            } else {
                result.append((entry.exerciseName, [entry]))
            }
        }
        return result.map { (name: $0.0, sets: $0.1) }
    }

    private var bestSet: SetEntry? {
        session.completedSets.max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top) {
                    StatBlock(value: session.formattedDuration, caption: "Duration")
                    StatBlock(
                        value: settings.formattedWeight(fromKilograms: session.totalVolumeKg),
                        caption: "Volume"
                    )
                    StatBlock(value: "\(session.totalReps)", caption: "Reps")
                    if session.totalSetSeconds > 0 {
                        StatBlock(value: session.formattedSetTime, caption: "In Set")
                    }
                }

                if let bestSet {
                    HStack {
                        Text("Best set")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(bestSet.exerciseName) — \(settings.formattedWeight(fromKilograms: bestSet.weightKg)) x \(bestSet.reps)")
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                }

                if let effort = session.effortScore {
                    HStack {
                        Text("Effort")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(effort) of 10")
                    }
                    .font(.caption)
                }
            }

            ForEach(groups, id: \.name) { group in
                Section(group.name) {
                    setColumnHeader
                    ForEach(group.sets) { entry in
                        setTableRow(entry)
                    }
                }
            }
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Set table (same look as the workout preview)

    private var setColumnHeader: some View {
        HStack(spacing: 10) {
            Text("Set")
                .frame(width: 24)
            Text(settings.weightUnit.label.uppercased())
                .frame(maxWidth: .infinity)
            Text("")
                .font(.caption)
            Text("REPS")
                .frame(maxWidth: .infinity)
            Text("TIME")
                .frame(width: 44)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }

    private func setTableRow(_ entry: SetEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.isWarmup ? "W" : "\(entry.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isWarmup ? .orange : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(entry.isWarmup ? .orange.opacity(0.15) : .gray.opacity(0.15))
                )

            Text(
                settings.displayWeight(fromKilograms: entry.weightKg)
                    .formatted(.number.precision(.fractionLength(0...1)))
            )
            .font(.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.background.secondary, in: .rect(cornerRadius: 7))

            Text("x")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("\(entry.reps)")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.background.secondary, in: .rect(cornerRadius: 7))

            Text(
                entry.durationSeconds > 0
                    ? WorkoutSession.formatMinutesSeconds(entry.durationSeconds)
                    : "--"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .frame(width: 44)
        }
    }
}
