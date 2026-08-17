import SwiftData
import SwiftUI
import UIKit

/// The live logging screen. Every edit writes straight to SwiftData, so leaving
/// the app mid-workout loses nothing.
struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Bindable var session: WorkoutSession
    /// Present when the workout came from a template, so weights can be written
    /// back on finish.
    var template: WorkoutTemplate?

    @State private var model = ActiveWorkoutViewModel()
    @State private var showingPicker = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false

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
                        SetRowView(entry: entry) {
                            model.startRest(seconds: settings.defaultRestSeconds)
                        }
                        .swipeActions(edge: .trailing) {
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

                    Button {
                        model.addSet(toExercise: group.name, in: session, context: context)
                    } label: {
                        Label("Add Set", systemImage: "plus")
                            .font(.subheadline)
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

            Section {
                Button {
                    showingPicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle")
                }

                Button(role: .destructive) {
                    confirmDiscard = true
                } label: {
                    Label("Discard Workout", systemImage: "trash")
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
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { confirmFinish = true }
                    .fontWeight(.semibold)
                    .disabled(model.isSaving)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView(
                excluding: Set(session.sets.map(\.exerciseName))
            ) { exercises in
                model.addExercises(exercises, to: session, context: context)
            }
        }
        .confirmationDialog(
            "Finish this workout?",
            isPresented: $confirmFinish,
            titleVisibility: .visible
        ) {
            Button("Finish and Save") { finish() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("\(session.completedSets.count) sets logged. Unfinished sets are dropped, and the workout is written to Apple Health.")
        }
        .confirmationDialog(
            "Discard this workout?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                model.discard(session: session, context: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        Card {
            HStack(alignment: .top) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    StatBlock(
                        value: session.formattedDuration,
                        caption: "Duration"
                    )
                }
                StatBlock(
                    value: settings.formattedWeight(fromKilograms: session.totalVolumeKg),
                    caption: "Volume"
                )
                StatBlock(
                    value: "\(session.completedSets.count)",
                    caption: "Sets Done"
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
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

    private func finish() {
        Task {
            await model.finish(
                session: session,
                template: template,
                context: context
            )
            dismiss()
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
