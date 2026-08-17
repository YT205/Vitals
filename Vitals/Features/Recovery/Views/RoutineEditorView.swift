import SwiftData
import SwiftUI

/// Create or edit a stretching / massage gun / mobility routine.
struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var routine: RecoveryRoutine
    let isNew: Bool

    private var canSave: Bool {
        !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Post Leg Day Stretch", text: $routine.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Type") {
                    Picker("Type", selection: $routine.kind) {
                        ForEach(RecoveryKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }
                    .labelsHidden()
                }

                Section {
                    DisclosureGroup {
                        ForEach(MuscleGroup.allCases) { group in
                            Toggle(group.label, isOn: Binding(
                                get: { routine.targetGroups.contains(group) },
                                set: { isOn in
                                    if isOn {
                                        routine.targetGroups.append(group)
                                    } else {
                                        routine.targetGroups.removeAll { $0 == group }
                                    }
                                }
                            ))
                        }
                    } label: {
                        HStack {
                            Text("Target Muscles")
                            Spacer()
                            Text(
                                routine.targetGroups.isEmpty
                                    ? "None"
                                    : "\(routine.targetGroups.count)"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Routines matching muscles you trained recently show up under Suggested for You.")
                }

                Section {
                    if routine.steps.isEmpty {
                        Text("No steps yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(routine.orderedSteps) { step in
                            stepRow(step)
                        }
                        .onDelete(perform: deleteSteps)
                        .onMove(perform: moveSteps)
                    }

                    Button {
                        addStep()
                    } label: {
                        Label("Add Step", systemImage: "plus")
                    }
                } header: {
                    HStack {
                        Text("Steps")
                        Spacer()
                        if routine.totalSeconds > 0 {
                            Text(routine.formattedDuration)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Turn on Per Side and the player runs the timer twice, once for each side.")
                }

                Section("Notes") {
                    TextField("Optional", text: $routine.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(isNew ? "New Routine" : "Edit Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(_ step: RecoveryStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Step name", text: Binding(
                get: { step.name },
                set: { step.name = $0 }
            ))
            .font(.body.weight(.medium))

            TextField("Cue or instruction (optional)", text: Binding(
                get: { step.instructions },
                set: { step.instructions = $0 }
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Stepper(
                    "\(step.seconds)s",
                    value: Binding(
                        get: { step.seconds },
                        set: { step.seconds = $0 }
                    ),
                    in: 5...600,
                    step: 5
                )
                .font(.caption)
                .fixedSize()

                Spacer()

                Toggle("Per Side", isOn: Binding(
                    get: { step.isPerSide },
                    set: { step.isPerSide = $0 }
                ))
                .font(.caption)
                .fixedSize()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func addStep() {
        let step = RecoveryStep(
            name: "",
            seconds: 30,
            order: (routine.steps.map(\.order).max() ?? -1) + 1
        )
        step.routine = routine
        context.insert(step)
    }

    private func deleteSteps(at offsets: IndexSet) {
        let ordered = routine.orderedSteps
        for index in offsets {
            context.delete(ordered[index])
        }
        renumber()
    }

    private func moveSteps(from source: IndexSet, to destination: Int) {
        var ordered = routine.orderedSteps
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, step) in ordered.enumerated() {
            step.order = index
        }
    }

    private func renumber() {
        for (index, step) in routine.orderedSteps.enumerated() {
            step.order = index
        }
    }

    private func save() {
        routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop blank steps rather than saving empty rows.
        for step in routine.steps
        where step.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.delete(step)
        }
        renumber()
        try? context.save()
        dismiss()
    }

    private func cancel() {
        if isNew {
            context.delete(routine)
        }
        context.rollback()
        dismiss()
    }
}
