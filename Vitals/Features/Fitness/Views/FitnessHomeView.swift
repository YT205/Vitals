import SwiftData
import SwiftUI

/// Fitness tab: your saved workouts, plus a way in to a live session.
struct FitnessHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(sort: \WorkoutTemplate.name)
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
                    }
                } header: {
                    Text("My Workouts")
                }

                Section {
                    Button {
                        createTemplate()
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }

                    Button {
                        startEmptyWorkout()
                    } label: {
                        Label("Start Empty Workout", systemImage: "bolt")
                    }
                    .disabled(activeSession != nil)

                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
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
        .swipeActions(edge: .leading) {
            Button {
                editingTemplate = template
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    // MARK: - Actions

    private func createTemplate() {
        let template = WorkoutTemplate(name: "")
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
                    reps: item.targetReps
                )
                entry.session = session
                context.insert(entry)
            }
        }

        try? context.save()
        launch = WorkoutLaunch(session: session, template: template)
    }

    private func startEmptyWorkout() {
        let session = WorkoutSession(title: "Quick Workout")
        context.insert(session)
        try? context.save()
        launch = WorkoutLaunch(session: session, template: nil)
    }

    private func deleteTemplates(at offsets: IndexSet) {
        for index in offsets {
            context.delete(templates[index])
        }
        try? context.save()
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
