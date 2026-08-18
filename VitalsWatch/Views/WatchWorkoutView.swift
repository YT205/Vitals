import SwiftUI
import WatchKit

/// The workout page. Idle: pick one of the phone's workouts. Running: three
/// horizontal pages -- overall metrics, the current set (with the full plan
/// below it), and the system Now Playing controls for whatever's on (Spotify
/// included).
struct WatchWorkoutView: View {
    private var manager: WatchWorkoutManager { .shared }
    private var sync: WatchSyncService { .shared }

    var body: some View {
        if manager.isRunning {
            ActiveWorkoutPages()
        } else {
            templatePicker
        }
    }

    /// Workouts are planned on the phone; the watch just starts them.
    private var templatePicker: some View {
        NavigationStack {
            Group {
                if sync.templates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Create workouts in the iPhone app and they appear here.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            sync.requestTemplates()
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 6)
                } else {
                    List {
                        ForEach(sync.templates) { template in
                            Button {
                                Task {
                                    await manager.startWorkout(template: template)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(2)
                                    Text(summary(for: template))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.carousel)
                }
            }
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sync.requestTemplates()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityLabel("Sync workouts from iPhone")
                }
            }
        }
    }

    private func summary(for template: SyncTemplate) -> String {
        let sets = template.items.reduce(0) { $0 + $1.sets.count }
        return "\(template.items.count) exercises · \(sets) sets"
    }
}

// MARK: - Active workout

/// Left: totals. Middle: current set + plan. Right: music.
private struct ActiveWorkoutPages: View {
    @State private var selectedPage = 1

    var body: some View {
        TabView(selection: $selectedPage) {
            MetricsPage()
                .tag(0)
            CurrentSetPage()
                .tag(1)
            NowPlayingView()
                .tag(2)
        }
        .tabViewStyle(.page)
    }
}

/// Overall workout metrics, like the phone's header card.
private struct MetricsPage: View {
    @Environment(AppSettings.self) private var settings

    private var manager: WatchWorkoutManager { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(manager.elapsedText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
            }

            metricRow(
                icon: "heart.fill", tint: .red,
                value: manager.heartRate > 0 ? "\(Int(manager.heartRate.rounded()))" : "--",
                unit: "BPM"
            )
            metricRow(
                icon: "flame.fill", tint: .orange,
                value: "\(Int(manager.activeEnergy.rounded()))",
                unit: "KCAL"
            )
            metricRow(
                icon: "scalemass.fill", tint: .cyan,
                value: settings.formattedWeight(fromKilograms: manager.totalVolumeKg),
                unit: ""
            )
            metricRow(
                icon: "checkmark.circle", tint: .green,
                value: "\(manager.doneCount)/\(manager.sets.count)",
                unit: "SETS"
            )

            Spacer(minLength: 0)

            Button(role: .destructive) {
                Task { await manager.endWorkout() }
            } label: {
                Label("End", systemImage: "xmark")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private func metricRow(icon: String, tint: Color, value: String, unit: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The main page: what you're lifting right now, the dial, a set-position
/// bar -- and the whole plan below it, crown-scrollable, with per-set editing.
private struct CurrentSetPage: View {
    @Environment(AppSettings.self) private var settings

    private var manager: WatchWorkoutManager { .shared }

    @State private var editingSet: WatchWorkoutManager.PerformedSet?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                currentSetCard
                planList
            }
        }
        .sheet(item: $editingSet) { target in
            EditSetSheet(target: target)
        }
    }

    // MARK: - Current set

    @ViewBuilder
    private var currentSetCard: some View {
        if manager.allDone {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("All sets done")
                    .font(.headline)
                Button {
                    Task { await manager.endWorkout() }
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if let current = manager.currentSet {
            VStack(spacing: 6) {
                Text(current.exerciseName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(
                        current.weightKg > 0
                            ? settings.displayWeight(fromKilograms: current.weightKg)
                                .formatted(.number.precision(.fractionLength(0...1)))
                            : "--"
                    )
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    Text(settings.weightUnit.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("x \(current.reps)")
                        .font(.title3.weight(.medium))
                }

                // The dial lives here too: set time, rest countdown, overtime.
                ZStack {
                    ProgressRing(
                        progress: manager.dialProgress,
                        lineWidth: 5,
                        tint: manager.dialTint
                    )
                    .frame(width: 56, height: 56)

                    VStack(spacing: 0) {
                        Text(manager.dialText)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(manager.phase == .overtime ? .orange : .primary)
                        Text(manager.dialCaption)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                controls

                setPositionBar
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch manager.phase {
        case .idle:
            Button {
                manager.startSet()
            } label: {
                Label("Start Set", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        case .set:
            Button {
                manager.endSet()
            } label: {
                Label("End Set", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .rest, .overtime:
            HStack(spacing: 6) {
                Button("Skip") { manager.skipRest() }
                    .buttonStyle(.bordered)
                Button {
                    manager.startSet()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Which set of the current exercise you're on: one segment per set.
    private var setPositionBar: some View {
        let exerciseSets = manager.currentExerciseSets
        let currentID = manager.currentSet?.id

        return HStack(spacing: 3) {
            ForEach(exerciseSets) { planSet in
                Capsule()
                    .fill(
                        planSet.isDone
                            ? Color.green
                            : (planSet.id == currentID
                                ? Color.accentColor
                                : Color.gray.opacity(0.3))
                    )
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityLabel(positionLabel(exerciseSets: exerciseSets, currentID: currentID))
    }

    private func positionLabel(
        exerciseSets: [WatchWorkoutManager.PerformedSet],
        currentID: UUID?
    ) -> String {
        guard let index = exerciseSets.firstIndex(where: { $0.id == currentID }) else {
            return ""
        }
        return "Set \(index + 1) of \(exerciseSets.count)"
    }

    // MARK: - Full plan

    /// Every exercise and set, grouped, with an edit affordance per set.
    private var planList: some View {
        let grouped = Dictionary(grouping: manager.sets, by: \.exerciseName)
        let ordered = manager.sets
            .map(\.exerciseName)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(ordered, id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(grouped[name] ?? []) { planSet in
                        setRow(planSet)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func setRow(_ planSet: WatchWorkoutManager.PerformedSet) -> some View {
        HStack(spacing: 6) {
            Image(
                systemName: planSet.isDone
                    ? "checkmark.circle.fill"
                    : (planSet.id == manager.currentSet?.id ? "arrow.right.circle" : "circle")
            )
            .font(.caption)
            .foregroundStyle(planSet.isDone ? .green : .secondary)

            Text("\(planSet.setNumber)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(
                planSet.weightKg > 0
                    ? settings.displayWeight(fromKilograms: planSet.weightKg)
                        .formatted(.number.precision(.fractionLength(0...1)))
                    : "--"
            )
            .font(.caption.weight(.medium))

            Text("x \(planSet.reps)")
                .font(.caption)

            Spacer(minLength: 0)

            Button {
                editingSet = planSet
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit set \(planSet.setNumber) of \(planSet.exerciseName)")
        }
    }
}

/// Fix a weight or rep count from the wrist: +/- steppers, coarse on purpose.
private struct EditSetSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let target: WatchWorkoutManager.PerformedSet

    @State private var weightDisplay: Double = 0
    @State private var reps: Int = 0

    private var manager: WatchWorkoutManager { .shared }

    /// lb moves in 2.5s, kg in 1.25s -- typical plate jumps.
    private var weightStep: Double {
        settings.weightUnit == .pounds ? 2.5 : 1.25
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("\(target.exerciseName) · Set \(target.setNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                stepper(
                    value: weightDisplay.formatted(.number.precision(.fractionLength(0...2))),
                    unit: settings.weightUnit.label,
                    minus: { weightDisplay = max(0, weightDisplay - weightStep) },
                    plus: { weightDisplay += weightStep }
                )

                stepper(
                    value: "\(reps)",
                    unit: "reps",
                    minus: { reps = max(0, reps - 1) },
                    plus: { reps += 1 }
                )

                Button("Save") {
                    manager.updateSet(
                        id: target.id,
                        weightKg: settings.kilograms(fromDisplayWeight: weightDisplay),
                        reps: reps
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            weightDisplay = settings.displayWeight(fromKilograms: target.weightKg)
            reps = target.reps
        }
    }

    private func stepper(
        value: String,
        unit: String,
        minus: @escaping () -> Void,
        plus: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button(action: minus) {
                Image(systemName: "minus")
            }
            .buttonStyle(.bordered)

            VStack(spacing: 0) {
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button(action: plus) {
                Image(systemName: "plus")
            }
            .buttonStyle(.bordered)
        }
    }
}
