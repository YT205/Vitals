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
                        ForEach(templates) { template in
                            templateRow(template)
                        }
                        .onDelete(perform: deleteTemplates)
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
        HStack(spacing: 12) {
            // Tap the row to start the workout...
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
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(activeSession != nil)

            // ...tap the pencil to change the plan. Always enabled, even
            // mid-workout (edits apply from the next session).
            Button {
                editingTemplate = template
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(template.name)")
        }
        .swipeActions(edge: .leading) {
            Button {
                editingTemplate = template
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        // Long-press for the same options -- swipe wasn't discoverable.
        .contextMenu {
            Button {
                editingTemplate = template
            } label: {
                Label("Edit Workout", systemImage: "pencil")
            }
            Button(role: .destructive) {
                context.delete(template)
                try? context.save()
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

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            context.delete(templates[index])
        }
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
