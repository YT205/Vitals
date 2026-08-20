import SwiftData
import SwiftUI
import UIKit

/// The live logging screen. Every edit writes straight to SwiftData, so leaving
/// the app mid-workout loses nothing.
///
/// Deliberately minimal: no adding exercises or sets mid-workout. The plan is
/// the plan; change the template if the plan changes. Finishing (and the
/// under-10-minute discard) goes through `FinishWorkoutSheet`.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Bindable var session: WorkoutSession
    /// Present when the workout came from a template, so weights can be written
    /// back on finish.
    var template: WorkoutTemplate?

    /// Shared, app-lived: the timer keeps running when this screen is popped
    /// and picks up exactly where it was on return.
    private var model: ActiveWorkoutViewModel { .shared }

    @State private var showingFinishSheet = false
    /// Set by the sheet, executed in `onDismiss` -- never during dismissal.
    @State private var pendingAction: FinishAction?
    /// Completed exercises the user tapped back open.
    @State private var manuallyExpanded: Set<String> = []
    /// Weight or reps value being edited via the bottom number pad.
    @State private var padTarget: NumberPadTarget?

    /// Sets grouped by exercise, in the order the exercises were added.
    private var groups: [ExerciseGroup] {
        var result: [ExerciseGroup] = []
        for entry in session.orderedSets {
            if let index = result.firstIndex(where: { $0.name == entry.exerciseName }) {
                result[index].sets.append(entry)
            } else {
                result.append(
                    ExerciseGroup(
                        name: entry.exerciseName,
                        muscleGroup: entry.muscleGroup,
                        sets: [entry]
                    )
                )
            }
        }
        return result
    }

    var body: some View {
        List {
            Section { headerCard }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            // Always present -- the dial changes phase instead of the bar
            // appearing and disappearing (which also caused transient
            // invalid-frame warnings during the insert/remove animation).
            Section { timerBar }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            ForEach(groups) { group in
                if isCollapsed(group) {
                    Section {
                        collapsedRow(group)
                    }
                } else {
                    Section {
                        SetHeaderRow()
                        ForEach(group.sets) { entry in
                            SetRowView(
                                entry: entry,
                                isTiming: model.isTiming(entry),
                                elapsedText: model.dialValueText,
                                onStart: { model.startSet(entry, in: session) },
                                // Finishing the last set folds the exercise;
                                // animate so it slides rather than snaps.
                                onFinish: {
                                    withAnimation(.snappy) {
                                        model.finishSet(entry)
                                    }
                                },
                                onReset: {
                                    withAnimation(.snappy) {
                                        model.resetSet(entry)
                                    }
                                },
                                onEditWeight: {
                                    padTarget = makePadTarget(for: entry, field: .weight)
                                },
                                onEditReps: {
                                    padTarget = makePadTarget(for: entry, field: .reps)
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                // Swipe away sets you skipped -- anything left
                                // with data in it gets saved at finish.
                                Button(role: .destructive) {
                                    model.delete(entry, context: context)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    entry.isWarmup.toggle()
                                } label: {
                                    Label(
                                        entry.isWarmup ? "Working" : "Warmup",
                                        systemImage: "flame"
                                    )
                                }
                                .tint(.orange)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.name)
                            Spacer()
                            if group.isComplete {
                                Button {
                                    withAnimation(.snappy) {
                                        _ = manuallyExpanded.remove(group.name)
                                    }
                                } label: {
                                    Label("Collapse", systemImage: "chevron.up")
                                        .font(.caption2)
                                }
                            } else if let alternate = model.alternateName(
                                forGroup: group.name,
                                template: template
                            ) {
                                // Swap to the paired exercise: undone sets
                                // become the other variant's plan.
                                Button {
                                    withAnimation(.snappy) {
                                        model.swapExercise(
                                            groupName: group.name,
                                            in: session,
                                            template: template,
                                            context: context
                                        )
                                    }
                                } label: {
                                    Label(alternate, systemImage: "arrow.left.arrow.right")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                            } else {
                                Text(group.muscleGroup.label)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            if let error = model.saveError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isSaving)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if model.isSaving {
                    ProgressView()
                } else {
                    Button("Finish") { showingFinishSheet = true }
                        .fontWeight(.semibold)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $showingFinishSheet, onDismiss: handlePendingAction) {
            FinishWorkoutSheet(session: session) { action in
                pendingAction = action
            }
        }
        .sheet(item: $padTarget) { target in
            // .id forces fresh sheet state per target. Without it, SwiftUI
            // reuses the sheet's @State across presentations and the pad
            // keeps editing the FIRST cell it ever showed -- the "always
            // says Set 1" / "copy-down does nothing" bug.
            NumberPadSheet(target: target)
                .id(target.id)
        }
        // Live-ish heart rate for the duration of the workout. The task is
        // cancelled automatically when this screen goes away.
        .task { await model.pollHeartRate() }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        StatBlock(
                            value: session.formattedDuration,
                            caption: "Duration"
                        )
                    }
                    StatBlock(
                        value: liveSetTimeText,
                        caption: "In Set"
                    )
                    StatBlock(
                        value: settings.formattedWeight(fromKilograms: session.totalVolumeKg),
                        caption: "Volume"
                    )
                    StatBlock(
                        value: "\(session.completedSets.count)",
                        caption: "Sets"
                    )
                }

                Divider()

                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: model.heartRate != nil)

                    if let heartRate = model.heartRate {
                        Text("\(Int(heartRate.bpm.rounded())) BPM")
                            .font(.footnote.weight(.semibold))
                            .contentTransition(.numericText())
                        Text("· \(heartRate.date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No heart rate yet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
            }
        }
        // 20pt matches the insetGrouped list margin so this card lines up
        // flush with the exercise tables below.
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// Saved set time plus the live clock if a set is running.
    private var liveSetTimeText: String {
        let total = session.totalSetSeconds + Double(model.setElapsed)
        return WorkoutSession.formatMinutesSeconds(total)
    }

    /// The persistent dial. Idle grey, filling while lifting, draining blue
    /// during rest, orange counting up once the planned rest is spent.
    private var timerBar: some View {
        Card(padding: 12) {
            HStack(spacing: 14) {
                ProgressRing(progress: model.dialProgress, lineWidth: 5, tint: model.dialTint)
                    .frame(width: 34, height: 34)
                    .animation(.snappy, value: model.dialTint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.dialValueText)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(model.phase == .overtime ? model.dialTint : .primary)
                    Text(model.dialCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.phase == .rest {
                    Button("+30s") { model.addRest(seconds: 30) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if model.phase == .rest || model.phase == .overtime {
                    Button("Skip") { model.skipRest() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Collapsed exercises

    /// A finished exercise folds to one row (tap to reopen). Order preserved.
    private func isCollapsed(_ group: ExerciseGroup) -> Bool {
        group.isComplete && !manuallyExpanded.contains(group.name)
    }

    private func collapsedRow(_ group: ExerciseGroup) -> some View {
        Button {
            withAnimation(.snappy) {
                _ = manuallyExpanded.insert(group.name)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(group.summary(using: settings))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    /// Runs after the finish sheet has fully dismissed. Doing the work here --
    /// not in the sheet's buttons -- is what fixes the discard freeze: the
    /// session is never deleted while a presentation is mid-flight.
    private func handlePendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action {
        case .save(let effortScore, let updatePlan):
            Task {
                await model.finish(
                    session: session,
                    template: template,
                    effortScore: effortScore,
                    updatePlan: updatePlan,
                    context: context
                )
                dismiss()
            }
        case .discard:
            dismiss()
            model.discardAfterDismiss(session: session, context: context)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    // MARK: - Number pad chaining

    private enum PadField { case weight, reps }

    /// One editable cell, wired so Next walks weight -> reps -> next set,
    /// crossing into the next exercise, and Copy Down fills the remaining
    /// sets of the same exercise.
    private func makePadTarget(for entry: SetEntry, field: PadField) -> NumberPadTarget {
        NumberPadTarget(
            title: "\(entry.exerciseName) · Set \(entry.setNumber)",
            unit: field == .weight ? settings.weightUnit.label : "reps",
            allowsDecimal: field == .weight,
            initialValue: field == .weight
                ? settings.displayWeight(fromKilograms: entry.weightKg)
                : Double(entry.reps),
            step: field == .weight ? 0.5 : 1,
            onCommit: { value in
                apply(value, to: entry, field: field)
            },
            onCopyDown: { value in
                apply(value, to: entry, field: field)
                for follower in session.orderedSets
                where follower.exerciseName == entry.exerciseName
                    && follower.setNumber > entry.setNumber {
                    apply(value, to: follower, field: field)
                }
            },
            next: {
                nextPadTarget(after: entry, field: field)
            }
        )
    }

    private func apply(_ value: Double, to entry: SetEntry, field: PadField) {
        switch field {
        case .weight:
            entry.weightKg = settings.kilograms(fromDisplayWeight: value)
        case .reps:
            entry.reps = max(0, Int(value))
        }
    }

    private func nextPadTarget(after entry: SetEntry, field: PadField) -> NumberPadTarget? {
        if field == .weight {
            return makePadTarget(for: entry, field: .reps)
        }
        let ordered = session.orderedSets
        guard let index = ordered.firstIndex(where: {
            $0.persistentModelID == entry.persistentModelID
        }), index + 1 < ordered.count else { return nil }
        return makePadTarget(for: ordered[index + 1], field: .weight)
    }
}

/// Display-only grouping of one exercise's sets.
private struct ExerciseGroup: Identifiable {
    let name: String
    let muscleGroup: MuscleGroup
    var sets: [SetEntry]

    var id: String { name }

    var isComplete: Bool {
        !sets.isEmpty && sets.allSatisfy(\.isDone)
    }

    /// "3 sets · top 185 lb" for the collapsed row.
    func summary(using settings: AppSettings) -> String {
        let working = sets.filter { !$0.isWarmup }
        var parts = ["\(working.count) set\(working.count == 1 ? "" : "s")"]
        if let top = working.map(\.weightKg).max(), top > 0 {
            parts.append("top \(settings.formattedWeight(fromKilograms: top))")
        }
        return parts.joined(separator: " · ")
    }
}
