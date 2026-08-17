import SwiftData
import SwiftUI

/// Fitness tab: heart rate, your saved workouts (drag to reorder), progress
/// charts, history, and a month calendar of training days.
struct FitnessHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: [
        SortDescriptor(\WorkoutTemplate.sortOrder),
        SortDescriptor(\WorkoutTemplate.name),
    ])
    private var templates: [WorkoutTemplate]

    /// There should only ever be one, but querying defensively avoids a crash if
    /// something goes sideways.
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil })
    private var activeSessions: [WorkoutSession]

    @State private var launch: WorkoutLaunch?
    @State private var editingTemplate: WorkoutTemplate?
    @State private var draftTemplate: WorkoutTemplate?
    /// Set when a delete is requested; the confirmation dialog acts on it.
    @State private var templatePendingDelete: WorkoutTemplate?

    private var activeSession: WorkoutSession? { activeSessions.first }

    var body: some View {
        NavigationStack {
            List {
                if let activeSession {
                    Section {
                        resumeRow(activeSession)
                    } header: {
                        Text("In Progress")
                    }
                }

                Section {
                    if templates.isEmpty {
                        Text("No workouts saved yet. Create one to get started.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        // No .onDelete here on purpose: every deletion path
                        // funnels through the confirmation dialog instead.
                        ForEach(templates) { template in
                            templateRow(template)
                        }
                        .onMove(perform: moveTemplates)
                    }
                } header: {
                    HStack {
                        Text("My Workouts")
                        Spacer()
                        if templates.count > 1 {
                            EditButton()
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button {
                        createTemplate()
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }

                    NavigationLink {
                        ExerciseProgressView()
                    } label: {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    WorkoutCalendarView()
                        .padding(.vertical, 4)
                } header: {
                    Text("Training Days")
                }
            }
            .navigationTitle("Fitness")
            .navigationDestination(item: $launch) { launch in
                ActiveWorkoutView(session: launch.session, template: launch.template)
            }
            .sheet(item: $editingTemplate) { template in
                TemplateEditorView(template: template, isNew: false)
            }
            // A blank template is inserted first so the editor can bind to it;
            // cancelling deletes it again.
            .sheet(item: $draftTemplate) { template in
                TemplateEditorView(template: template, isNew: true)
            }
            .confirmationDialog(
                "Delete this workout?",
                isPresented: Binding(
                    get: { templatePendingDelete != nil },
                    set: { if !$0 { templatePendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: templatePendingDelete
            ) { template in
                Button("Delete \"\(template.name)\"", role: .destructive) {
                    delete(template)
                }
                Button("Cancel", role: .cancel) {}
            } message: { template in
                Text("\"\(template.name)\" and its exercise plan are removed. Finished workouts in History are kept.")
            }
        }
    }

    // MARK: - Rows

    private func resumeRow(_ session: WorkoutSession) -> some View {
        Button {
            launch = WorkoutLaunch(
                session: session,
                template: templates.first { $0.name == session.title }
            )
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(.body.weight(.semibold))
                    Text("Started \(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.completedSets.count) sets logged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func templateRow(_ template: WorkoutTemplate) -> some View {
        Button {
            start(from: template)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name)
                        .font(.body.weight(.medium))
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let last = template.lastPerformedAt {
                        Text("Last done \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .disabled(activeSession != nil)
        // Swipe left: Delete at the edge, Edit next to it. Delete asks first.
        .swipeActions(edge: .trailing) {
            Button {
                templatePendingDelete = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Button {
                editingTemplate = template
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        // Long-press for the same options.
        .contextMenu {
            Button {
                editingTemplate = template
            } label: {
                Label("Edit Workout", systemImage: "pencil")
            }
            Button(role: .destructive) {
                templatePendingDelete = template
            } label: {
                Label("Delete Workout", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func createTemplate() {
        let template = WorkoutTemplate(name: "")
        template.sortOrder = (templates.map(\.sortOrder).max() ?? -1) + 1
        context.insert(template)
        draftTemplate = template
    }

    private func start(from template: WorkoutTemplate) {
        let session = WorkoutSession(title: template.name)
        context.insert(session)

        for (index, item) in template.orderedItems.enumerated() {
            for setNumber in 1...max(1, item.targetSets) {
                let entry = SetEntry(
                    exerciseName: item.exerciseName,
                    muscleGroup: item.muscleGroup,
                    exerciseOrder: index,
                    setNumber: setNumber,
                    weightKg: item.lastWeightKg,
                    reps: item.targetReps,
                    restSeconds: item.restSeconds
                )
                entry.session = session
                context.insert(entry)
            }
        }

        try? context.save()
        launch = WorkoutLaunch(session: session, template: template)
    }

    private func delete(_ template: WorkoutTemplate) {
        context.delete(template)
        renumberTemplates()
        try? context.save()
    }

    private func moveTemplates(from source: IndexSet, to destination: Int) {
        var reordered = templates
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in reordered.enumerated() {
            template.sortOrder = index
        }
        try? context.save()
    }

    private func renumberTemplates() {
        for (index, template) in templates.enumerated() {
            template.sortOrder = index
        }
    }
}

/// Pairs a session with the template it came from, so `navigationDestination`
/// can carry both.
struct WorkoutLaunch: Hashable {
    let session: WorkoutSession
    let template: WorkoutTemplate?
}

#Preview {
    FitnessHomeView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
