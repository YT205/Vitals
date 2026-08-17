import SwiftData
import SwiftUI

/// Recovery tab: saved stretching, massage gun and mobility routines, with
/// suggestions driven by what you actually trained in the last few days.
struct RecoveryHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \RecoveryRoutine.name)
    private var routines: [RecoveryRoutine]

    /// Working sets from roughly the last week; filtered to 3 days in code
    /// because #Predicate can't reference Date.now dynamically per render.
    @Query(
        filter: #Predicate<SetEntry> { $0.isDone && !$0.isWarmup },
        sort: \SetEntry.completedAt,
        order: .reverse
    )
    private var recentSets: [SetEntry]

    @State private var editingRoutine: RecoveryRoutine?
    @State private var draftRoutine: RecoveryRoutine?

    /// Muscle groups trained in the last 3 days, mapped to the most recent day
    /// each was hit.
    private var recentlyTrained: [MuscleGroup: Date] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -3, to: .now) ?? .now
        var result: [MuscleGroup: Date] = [:]
        for entry in recentSets {
            guard let done = entry.completedAt else { continue }
            if done < cutoff { break }  // sorted newest-first, safe to stop
            if let existing = result[entry.muscleGroup], existing >= done { continue }
            result[entry.muscleGroup] = done
        }
        return result
    }

    /// Routines whose targets overlap recent training, best match first.
    private var suggested: [(routine: RecoveryRoutine, matched: [MuscleGroup])] {
        let trained = recentlyTrained
        guard !trained.isEmpty else { return [] }

        return routines
            .compactMap { routine -> (RecoveryRoutine, [MuscleGroup])? in
                // Swiped-away suggestions stay hidden for the 3-day cycle.
                guard !settings.isSuggestionDismissed(routine.name) else { return nil }
                let matched = routine.targetGroups.filter { trained.keys.contains($0) }
                guard !matched.isEmpty else { return nil }
                return (routine, matched)
            }
            .sorted { lhs, rhs in
                if lhs.1.count != rhs.1.count { return lhs.1.count > rhs.1.count }
                // Tie-break: the one you've done least recently.
                let lhsDone = lhs.0.lastPerformedAt ?? .distantPast
                let rhsDone = rhs.0.lastPerformedAt ?? .distantPast
                return lhsDone < rhsDone
            }
            .prefix(3)
            .map { (routine: $0.0, matched: $0.1) }
    }

    private var grouped: [(kind: RecoveryKind, items: [RecoveryRoutine])] {
        Dictionary(grouping: routines, by: \.kind)
            .map { (kind: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { lhs, rhs in
                let order = RecoveryKind.allCases
                let lhsIndex = order.firstIndex(of: lhs.kind) ?? 0
                let rhsIndex = order.firstIndex(of: rhs.kind) ?? 0
                return lhsIndex < rhsIndex
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if routines.isEmpty {
                    EmptyStateView(
                        systemImage: "figure.cooldown",
                        title: "No routines yet",
                        message: "Build a stretching or massage gun sequence and run it with a guided timer.",
                        actionTitle: "New Routine",
                        action: createRoutine
                    )
                    .listRowBackground(Color.clear)
                } else {
                    if !suggested.isEmpty {
                        Section {
                            ForEach(suggested, id: \.routine.id) { suggestion in
                                suggestedRow(suggestion.routine, matched: suggestion.matched)
                                    // Hiding snoozes the suggestion; the routine
                                    // itself stays in the library below.
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            settings.dismissSuggestion(suggestion.routine.name)
                                        } label: {
                                            Label("Hide", systemImage: "eye.slash")
                                        }
                                        .tint(.gray)
                                    }
                            }
                            .onDelete { offsets in
                                // Edit-mode minus circles hide, they don't delete.
                                for index in offsets {
                                    settings.dismissSuggestion(suggested[index].routine.name)
                                }
                            }
                        } header: {
                            Label("Suggested for You", systemImage: "sparkles")
                        } footer: {
                            Text("Based on the muscle groups you trained in the last 3 days.")
                        }
                    }

                    ForEach(grouped, id: \.kind) { section in
                        Section {
                            ForEach(section.items) { routine in
                                routineRow(routine)
                            }
                            .onDelete { offsets in
                                delete(offsets, in: section.items)
                            }
                        } header: {
                            Label(section.kind.label, systemImage: section.kind.systemImage)
                        }
                    }
                }

            }
            .navigationTitle("Recovery")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !routines.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createRoutine()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New routine")
                }
            }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(routine: routine, isNew: false)
            }
            .sheet(item: $draftRoutine) { routine in
                RoutineEditorView(routine: routine, isNew: true)
            }
        }
    }

    private func suggestedRow(
        _ routine: RecoveryRoutine,
        matched: [MuscleGroup]
    ) -> some View {
        NavigationLink {
            RoutinePlayerView(routine: routine)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.body.weight(.medium))
                Text("You trained \(matched.map(\.label).formatted(.list(type: .and)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(routine.formattedDuration, systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func routineRow(_ routine: RecoveryRoutine) -> some View {
        NavigationLink {
            RoutinePlayerView(routine: routine)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.body.weight(.medium))

                HStack(spacing: 10) {
                    Label(routine.formattedDuration, systemImage: "clock")
                    Label("\(routine.steps.count) steps", systemImage: "list.bullet")
                    if routine.completionCount > 0 {
                        Label("\(routine.completionCount)x", systemImage: "checkmark.circle")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let last = routine.lastPerformedAt {
                    Text("Last done \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                editingRoutine = routine
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                editingRoutine = routine
            } label: {
                Label("Edit Routine", systemImage: "pencil")
            }
            Button(role: .destructive) {
                context.delete(routine)
                try? context.save()
            } label: {
                Label("Delete Routine", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func createRoutine() {
        let routine = RecoveryRoutine(name: "")
        context.insert(routine)
        draftRoutine = routine
    }

    private func delete(_ offsets: IndexSet, in items: [RecoveryRoutine]) {
        for index in offsets {
            context.delete(items[index])
        }
        try? context.save()
    }
}

#Preview {
    RecoveryHomeView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
