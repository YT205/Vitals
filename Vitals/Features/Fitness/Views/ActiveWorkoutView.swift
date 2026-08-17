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

    @State private var model = ActiveWorkoutViewModel()
    @State private var showingFinishSheet = false
    /// Set by the sheet, executed in `onDismiss` -- never during dismissal.
    @State private var pendingAction: FinishAction?

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

            if model.isResting {
                Section { restBar }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach(groups) { group in
                Section {
                    SetHeaderRow()
                    ForEach(group.sets) { entry in
                        SetRowView(
                            entry: entry,
                            isTiming: model.isTiming(entry),
                            elapsedText: model.formattedSetElapsed,
                            onStart: { model.startSet(entry, in: session) },
                            onFinish: { model.finishSet(entry) },
                            onReset: { model.resetSet(entry) }
                        )
                        .swipeActions(edge: .trailing) {
                            // Swipe away sets you skipped -- anything left with
                            // data in it gets saved at finish.
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
                        Text(group.muscleGroup.label)
                            .foregroundStyle(.tertiary)
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
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Saved set time plus the live clock if a set is running.
    private var liveSetTimeText: String {
        let total = session.totalSetSeconds + Double(model.setElapsed)
        return WorkoutSession.formatMinutesSeconds(total)
    }

    private var restBar: some View {
        Card {
            HStack(spacing: 14) {
                ProgressRing(progress: model.restProgress, lineWidth: 5, tint: .blue)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.formattedRest)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("Rest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("+30s") { model.addRest(seconds: 30) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Skip") { model.stopRest() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Actions

    /// Runs after the finish sheet has fully dismissed. Doing the work here --
    /// not in the sheet's buttons -- is what fixes the discard freeze: the
    /// session is never deleted while a presentation is mid-flight.
    private func handlePendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action {
        case .save(let effortScore):
            Task {
                await model.finish(
                    session: session,
                    template: template,
                    effortScore: effortScore,
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
}

/// Display-only grouping of one exercise's sets.
private struct ExerciseGroup: Identifiable {
    let name: String
    let muscleGroup: MuscleGroup
    var sets: [SetEntry]

    var id: String { name }
}
