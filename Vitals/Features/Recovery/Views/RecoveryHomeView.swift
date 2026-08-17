import SwiftData
import SwiftUI

/// Recovery tab: saved stretching, massage gun and mobility routines.
struct RecoveryHomeView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \RecoveryRoutine.name)
    private var routines: [RecoveryRoutine]

    @State private var editingRoutine: RecoveryRoutine?
    @State private var draftRoutine: RecoveryRoutine?

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

                Section {
                    Button {
                        createRoutine()
                    } label: {
                        Label("New Routine", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Recovery")
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(routine: routine, isNew: false)
            }
            .sheet(item: $draftRoutine) { routine in
                RoutineEditorView(routine: routine, isNew: true)
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
