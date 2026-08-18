import SwiftData
import SwiftUI
import UIKit

/// Create or edit a workout template ("Push Day A", "Legs", ...).
///
/// Each exercise is planned per set -- every set has its own weight and reps,
/// laid out like the live workout screen -- plus a rest time for the exercise.
struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @Bindable var template: WorkoutTemplate
    /// When `true`, cancelling deletes the freshly inserted record.
    let isNew: Bool

    @State private var showingPicker = false
    @State private var showingReorder = false
    @State private var createdStretchRoutine = false
    @State private var createdMassageRoutine = false
    /// Weight or reps value being edited via the bottom number pad.
    @State private var padTarget: NumberPadTarget?

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

                if template.items.isEmpty {
                    Section("Exercises") {
                        Text("No exercises yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(template.orderedItems) { item in
                        exerciseSection(item)
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add Exercises", systemImage: "plus")
                    }
                } footer: {
                    if !template.items.isEmpty {
                        Text("Each set keeps its own weight and reps. After a workout, what you actually lifted is written back into the plan.")
                    }
                }

                Section {
                    Button {
                        createRecoveryRoutine(kind: .stretching)
                        createdStretchRoutine = true
                    } label: {
                        Label(
                            createdStretchRoutine
                                ? "Stretch Routine Created"
                                : "Create Stretch Routine",
                            systemImage: createdStretchRoutine
                                ? "checkmark.circle.fill"
                                : "figure.flexibility"
                        )
                    }
                    .disabled(template.items.isEmpty || createdStretchRoutine)

                    Button {
                        createRecoveryRoutine(kind: .massageGun)
                        createdMassageRoutine = true
                    } label: {
                        Label(
                            createdMassageRoutine
                                ? "Massage Gun Routine Created"
                                : "Create Massage Gun Routine",
                            systemImage: createdMassageRoutine
                                ? "checkmark.circle.fill"
                                : "waveform.badge.magnifyingglass"
                        )
                    }
                    .disabled(template.items.isEmpty || createdMassageRoutine)
                } header: {
                    Text("Recovery")
                } footer: {
                    Text("Each builds a sequence for this workout's muscle groups and saves it to the Recovery tab. Cancelling this editor removes them again.")
                }
            }
            .navigationTitle(isNew ? "New Workout" : "Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if template.items.count > 1 {
                        Button {
                            showingReorder = true
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Reorder exercises")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showingReorder) {
                ReorderExercisesSheet(template: template)
            }
            .sheet(item: $padTarget) { target in
                NumberPadSheet(target: target)
            }
            .sheet(isPresented: $showingPicker) {
                ExercisePickerView(
                    excluding: Set(template.items.map(\.exerciseName))
                ) { exercises in
                    addExercises(exercises)
                }
            }
            .onAppear {
                // Items created before per-set planning get plan rows built
                // from their legacy targets, once.
                for item in template.items {
                    item.materializedPlan(in: context)
                }
            }
        }
    }

    // MARK: - Exercise section

    /// One exercise: its planned sets laid out like the live workout rows,
    /// an Add Set button, and the rest picker.
    @ViewBuilder
    private func exerciseSection(_ item: TemplateItem) -> some View {
        Section {
            PlanSetHeaderRow()

            ForEach(item.orderedSets) { planSet in
                planSetRow(planSet, itemName: item.exerciseName)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteSet(planSet, from: item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            Button {
                addSet(to: item)
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
            }

            Picker("Rest between sets", selection: Binding(
                get: { item.restSeconds },
                set: { item.restSeconds = $0 }
            )) {
                ForEach(Array(stride(from: 15, through: 300, by: 15)), id: \.self) { seconds in
                    Text("\(seconds)s").tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .font(.subheadline)
        } header: {
            HStack {
                Text(item.exerciseName)
                Spacer()
                // Sections can't drag-reorder, so ordering lives here instead.
                Menu {
                    Button {
                        move(item, by: -1)
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(item.order == 0)

                    Button {
                        move(item, by: 1)
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(item.order == template.items.count - 1)

                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .accessibilityLabel("Options for \(item.exerciseName)")
            }
        }
    }

    private func move(_ item: TemplateItem, by offset: Int) {
        var ordered = template.orderedItems
        guard let index = ordered.firstIndex(where: { $0 === item }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for (newIndex, moved) in ordered.enumerated() {
            moved.order = newIndex
        }
    }

    private func planSetRow(_ planSet: TemplateSet, itemName: String) -> some View {
        HStack(spacing: 10) {
            Text("\(planSet.setNumber)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.gray.opacity(0.15)))

            planValueBox(
                settings.displayWeight(fromKilograms: planSet.weightKg)
                    .formatted(.number.precision(.fractionLength(0...1))),
                isPlaceholder: planSet.weightKg <= 0
            ) {
                padTarget = NumberPadTarget(
                    title: "\(itemName) · Set \(planSet.setNumber)",
                    unit: settings.weightUnit.label,
                    allowsDecimal: true,
                    initialValue: settings.displayWeight(fromKilograms: planSet.weightKg)
                ) { value in
                    planSet.weightKg = settings.kilograms(fromDisplayWeight: value)
                }
            }

            Text("x")
                .font(.caption)
                .foregroundStyle(.tertiary)

            planValueBox("\(planSet.reps)", isPlaceholder: planSet.reps <= 0) {
                padTarget = NumberPadTarget(
                    title: "\(itemName) · Set \(planSet.setNumber)",
                    unit: "reps",
                    allowsDecimal: false,
                    initialValue: Double(planSet.reps)
                ) { value in
                    planSet.reps = Int(value)
                }
            }
        }
    }

    private func planValueBox(
        _ text: String,
        isPlaceholder: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(isPlaceholder ? "--" : text)
                .font(.callout)
                .foregroundStyle(isPlaceholder ? .tertiary : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.background.secondary, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func addSet(to item: TemplateItem) {
        let last = item.orderedSets.last
        let planSet = TemplateSet(
            setNumber: (item.sets.map(\.setNumber).max() ?? 0) + 1,
            reps: last?.reps ?? 8,
            weightKg: last?.weightKg ?? 0
        )
        planSet.item = item
        context.insert(planSet)
    }

    private func deleteSet(_ planSet: TemplateSet, from item: TemplateItem) {
        context.delete(planSet)
        for (index, remaining) in item.orderedSets.filter({ $0 !== planSet }).enumerated() {
            remaining.setNumber = index + 1
        }
    }

    private func deleteItem(_ item: TemplateItem) {
        context.delete(item)
        renumber()
    }

    private func createRecoveryRoutine(kind: RecoveryKind) {
        let trimmed = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Workout" : trimmed
        let suffix = kind == .massageGun ? "Massage Gun" : "Stretch"
        let routine = RecoveryLibrary.generatedRoutine(
            named: "\(baseName) \(suffix)",
            for: templateGroups,
            kind: kind
        )
        context.insert(routine)
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
            item.materializedPlan(in: context)
            nextOrder += 1
        }
    }

    private func renumber() {
        for (index, item) in template.orderedItems.enumerated() {
            item.order = index
        }
    }

    private func save() {
        template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in template.items {
            item.refreshLegacySummary()
        }
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Drag-to-reorder every exercise at once. Text-only rows, so a permanently
/// active edit mode is safe here (unlike the main editor form, where it
/// fought the text fields).
private struct ReorderExercisesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let template: WorkoutTemplate

    var body: some View {
        NavigationStack {
            List {
                ForEach(template.orderedItems) { item in
                    HStack {
                        Text(item.exerciseName)
                        Spacer()
                        Text(item.muscleGroup.label)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onMove { source, destination in
                    var ordered = template.orderedItems
                    ordered.move(fromOffsets: source, toOffset: destination)
                    for (index, item) in ordered.enumerated() {
                        item.order = index
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Column titles for the plan rows, matching the live workout header.
private struct PlanSetHeaderRow: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            Text("Set")
                .frame(width: 24)
            Text(settings.weightUnit.label.uppercased())
                .frame(maxWidth: .infinity)
            Text("")
                .font(.caption)
            Text("REPS")
                .frame(maxWidth: .infinity)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
}
