import SwiftData
import SwiftUI

/// Create or edit a workout template ("Push Day A", "Legs", ...).
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Bindable var template: WorkoutTemplate
    /// When `true`, cancelling deletes the freshly inserted record.
    let isNew: Bool

    @State private var showingPicker = false
    @State private var createdRecoveryRoutine = false

    private var canSave: Bool {
        !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var templateGroups: [MuscleGroup] {
        var seen = Set<MuscleGroup>()
        return template.orderedItems.compactMap { item in
            seen.insert(item.muscleGroup).inserted ? item.muscleGroup : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Push Day A", text: $template.name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    if template.items.isEmpty {
                        Text("No exercises yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(template.orderedItems) { item in
                            itemRow(item)
                        }
                        .onDelete(perform: deleteItems)
                        .onMove(perform: moveItems)
                    }

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Exercises", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Exercises")
                        Spacer()
                        if template.items.count > 1 {
                            EditButton()
                                .font(.caption)
                        }
                    }
                } footer: {
                    if !template.items.isEmpty {
                        Text("Swipe left to remove an exercise. Tap Edit to drag them into a new order. Sets, reps and rest are the plan -- weights and reps can still change set by set during the workout.")
                    }
                }

                Section {
                    Button {
                        createRecoveryRoutine()
                    } label: {
                        Label(
                            createdRecoveryRoutine
                                ? "Recovery Routine Created"
                                : "Create Recovery Routine",
                            systemImage: createdRecoveryRoutine
                                ? "checkmark.circle.fill"
                                : "figure.cooldown"
                        )
                    }
                    .disabled(template.items.isEmpty || createdRecoveryRoutine)
                } footer: {
                    Text("Builds a stretch and massage gun sequence for this workout's muscle groups and saves it to the Recovery tab.")
                }
            }
            // Note: no forced editMode here. A Form locked in .active edit mode
            // suppresses swipe-to-delete and interferes with text fields and
            // steppers inside the reorderable rows -- it made the editor feel
            // broken. EditButton in the section header toggles it on demand.
            .navigationTitle(isNew ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(
                    excluding: Set(template.items.map(\.exerciseName))
                ) { exercises in
                    addExercises(exercises)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(_ item: TemplateItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.exerciseName)
                .font(.body.weight(.medium))

            HStack(spacing: 16) {
                Stepper(
                    "\(item.targetSets) sets",
                    value: Binding(
                        get: { item.targetSets },
                        set: { item.targetSets = $0 }
                    ),
                    in: 1...12
                )
                .font(.caption)

                Stepper(
                    "\(item.targetReps) reps",
                    value: Binding(
                        get: { item.targetReps },
                        set: { item.targetReps = $0 }
                    ),
                    in: 1...50
                )
                .font(.caption)
            }

            Stepper(
                "Rest: \(item.restSeconds)s",
                value: Binding(
                    get: { item.restSeconds },
                    set: { item.restSeconds = $0 }
                ),
                in: 15...300,
                step: 15
            )
            .font(.caption)

            if item.lastWeightKg > 0 {
                Text("Last: \(settings.formattedWeight(fromKilograms: item.lastWeightKg))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func createRecoveryRoutine() {
        let trimmed = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Workout" : trimmed
        let routine = RecoveryLibrary.generatedRoutine(
            named: "\(baseName) Recovery",
            for: templateGroups
        )
        context.insert(routine)
        createdRecoveryRoutine = true
    }

    private func addExercises(_ exercises: [Exercise]) {
        var nextOrder = (template.items.map(\.order).max() ?? -1) + 1
        for exercise in exercises {
            let item = TemplateItem(
                exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup,
                order: nextOrder
            )
            item.template = template
            context.insert(item)
            nextOrder += 1
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        let ordered = template.orderedItems
        for index in offsets {
            context.delete(ordered[index])
        }
        renumber()
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var ordered = template.orderedItems
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() {
            item.order = index
        }
    }

    private func renumber() {
        for (index, item) in template.orderedItems.enumerated() {
            item.order = index
        }
    }

    private func save() {
        template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        renumber()
        try? context.save()
        dismiss()
    }

    private func cancel() {
        if isNew {
            context.delete(template)
        }
        // Roll back any edits made to an existing template.
        context.rollback()
        dismiss()
    }
}
