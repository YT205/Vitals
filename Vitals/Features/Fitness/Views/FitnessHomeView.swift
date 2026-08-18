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
    /// The workout being previewed in the bottom sheet.
    @State private var previewTemplate: WorkoutTemplate?
    /// Chosen in the preview sheet; executed after it dismisses.
    @State private var pendingPreview: (action: WorkoutPreviewAction, template: WorkoutTemplate)?

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
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                    NavigationLink {
                        ExerciseProgressView()
                    } label: {
                        Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createTemplate()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New workout")
                }
            }
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
            .sheet(item: $previewTemplate, onDismiss: handlePreviewAction) { template in
                WorkoutPreviewSheet(
                    template: template,
                    canStart: activeSession == nil
                ) { action in
                    pendingPreview = (action, template)
                }
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
        // Tapping opens the preview sheet; starting happens from there.
        Button {
            previewTemplate = template
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
                Image(systemName: "chevron.up.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        // Swipe right for Edit, swipe left for Delete -- opposite edges.
        .swipeActions(edge: .leading) {
            Button {
                editingTemplate = template
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button {
                templatePendingDelete = template
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
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

    /// Runs after the preview sheet fully dismisses, so opening the editor or
    /// pushing the workout never overlaps an in-flight sheet transition.
    private func handlePreviewAction() {
        guard let pending = pendingPreview else { return }
        pendingPreview = nil

        switch pending.action {
        case .edit:
            editingTemplate = pending.template
        case .start:
            start(from: pending.template)
        }
    }

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
            // Per-set plan when it exists; legacy items synthesize one first.
            let plan = item.materializedPlan(in: context)
            for planSet in plan {
                let entry = SetEntry(
                    exerciseName: item.exerciseName,
                    muscleGroup: item.muscleGroup,
                    exerciseOrder: index,
                    setNumber: planSet.setNumber,
                    weightKg: planSet.weightKg,
                    reps: planSet.reps,
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
