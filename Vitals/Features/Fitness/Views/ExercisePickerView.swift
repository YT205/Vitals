import SwiftData
import SwiftUI

/// Searchable, multi-select exercise list. Used when building a template and
/// when adding an exercise mid-workout.
struct ExercisePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var search = ""
    @State private var selectedNames: Set<String> = []
    @State private var showingCreate = false

    /// Names already in the template or session, shown greyed out.
    var excluding: Set<String> = []
    let onAdd: ([Exercise]) -> Void

    private var filtered: [Exercise] {
        guard !search.isEmpty else { return exercises }
        return exercises.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.muscleGroup.label.localizedCaseInsensitiveContains(search)
                || $0.equipment.label.localizedCaseInsensitiveContains(search)
        }
    }

    private var grouped: [(group: MuscleGroup, items: [Exercise])] {
        Dictionary(grouping: filtered, by: \.muscleGroup)
            .map { (group: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                let order = MuscleGroup.allCases
                let lhsIndex = order.firstIndex(of: lhs.group) ?? 0
                let rhsIndex = order.firstIndex(of: rhs.group) ?? 0
                return lhsIndex < rhsIndex
            }
    }

    private var selectedExercises: [Exercise] {
        exercises.filter { selectedNames.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.group) { section in
                    Section(section.group.label) {
                        ForEach(section.items) { exercise in
                            row(for: exercise)
                        }
                    }
                }

                Section {
                    Button {
                        showingCreate = true
                    } label: {
                        Label("Create Custom Exercise", systemImage: "plus.circle")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add\(selectedNames.isEmpty ? "" : " (\(selectedNames.count))")") {
                        onAdd(selectedExercises)
                        dismiss()
                    }
                    .disabled(selectedNames.isEmpty)
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateExerciseView { newExercise in
                    // Auto-select whatever you just created.
                    selectedNames.insert(newExercise.name)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for exercise: Exercise) -> some View {
        let isExcluded = excluding.contains(exercise.name)
        let isSelected = selectedNames.contains(exercise.name)

        Button {
            if isSelected {
                selectedNames.remove(exercise.name)
            } else {
                selectedNames.insert(exercise.name)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .foregroundStyle(isExcluded ? .secondary : .primary)
                    Text(exercise.equipment.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isExcluded {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .disabled(isExcluded)
    }
}

/// Sheet for adding your own movement to the library.
struct CreateExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscleGroup: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell

    let onCreate: (Exercise) -> Void

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Landmine Press", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Muscle Group") {
                    Picker("Muscle Group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.label).tag(group)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                }
                Section("Equipment") {
                    Picker("Equipment", selection: $equipment) {
                        ForEach(Equipment.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.wheel)
                }
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let exercise = Exercise(
            name: trimmed,
            muscleGroup: muscleGroup,
            equipment: equipment,
            isCustom: true
        )
        context.insert(exercise)
        try? context.save()
        onCreate(exercise)
        dismiss()
    }
}

#Preview {
    ExercisePickerView { _ in }
        .modelContainer(VitalsModelContainer.preview)
}
