import SwiftData
import SwiftUI

/// The AI recovery assistant: pick a recent workout or describe one, add your
/// goals, and get a generated stretch or massage routine to review and save.
/// Generation runs entirely on-device.
struct AIRecoveryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<WorkoutSession> { $0.endedAt != nil },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    )
    private var finishedSessions: [WorkoutSession]

    // Inputs
    @State private var selectedSession: WorkoutSession?
    @State private var freeText = ""
    @State private var goals = ""
    @State private var kind: RecoveryKind = .stretching

    // Generation
    @State private var isGenerating = false
    @State private var generated: RecoveryRoutine?
    @State private var fallbackNote: String?
    @State private var errorMessage: String?

    /// The last few workouts are the realistic candidates.
    private var recentSessions: [WorkoutSession] {
        Array(finishedSessions.prefix(5))
    }

    private var canGenerate: Bool {
        selectedSession != nil
            || !freeText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var availabilityNote: String? {
        if case .unavailable(let reason) = RecoveryAIService.availability() {
            return reason + " A routine from the built-in bank is created instead."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let generated {
                    previewSections(generated)
                } else {
                    inputSections
                }
            }
            .navigationTitle("AI Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isGenerating)
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSections: some View {
        Section {
            if recentSessions.isEmpty {
                Text("No finished workouts yet. Describe one below instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentSessions) { session in
                    Button {
                        selectedSession = selectedSession == session ? nil : session
                        if selectedSession != nil { freeText = "" }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(session.startedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedSession == session {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Which workout?")
        }

        Section {
            TextField(
                "e.g. heavy squats and deadlifts this morning",
                text: $freeText,
                axis: .vertical
            )
            .lineLimit(2...4)
            .onChange(of: freeText) { _, newValue in
                if !newValue.isEmpty { selectedSession = nil }
            }
        } header: {
            Text("Or describe it")
        }

        Section {
            Picker("Type", selection: $kind) {
                Label("Stretch", systemImage: "figure.flexibility")
                    .tag(RecoveryKind.stretching)
                Label("Massage Gun", systemImage: "waveform.badge.magnifyingglass")
                    .tag(RecoveryKind.massageGun)
            }
            .pickerStyle(.segmented)

            TextField(
                "e.g. lower back is tight, keep it under 10 minutes",
                text: $goals,
                axis: .vertical
            )
            .lineLimit(2...4)
        } header: {
            Text("Your goals")
        } footer: {
            // Only surfaces when Apple Intelligence is unavailable.
            if let availabilityNote {
                Text(availabilityNote)
            }
        }

        Section {
            Button {
                generate()
            } label: {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Generating...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Generate Routine", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!canGenerate || isGenerating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewSections(_ routine: RecoveryRoutine) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.headline)
                if !routine.notes.isEmpty {
                    Text(routine.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Label(routine.formattedDuration, systemImage: "clock")
                    Label("\(routine.steps.count) steps", systemImage: "list.bullet")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        } footer: {
            if let fallbackNote {
                Text(fallbackNote)
            }
        }

        Section("Steps") {
            ForEach(routine.orderedSteps) { step in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(step.name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(step.seconds)s\(step.isPerSide ? " / side" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !step.instructions.isEmpty {
                        Text(step.instructions)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section {
            Button {
                save(routine)
            } label: {
                Label("Save to Recovery", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Button {
                generated = nil
                generate()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isGenerating)

            Button(role: .destructive) {
                generated = nil
                fallbackNote = nil
            } label: {
                Text("Start Over")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Actions

    private func generate() {
        isGenerating = true
        errorMessage = nil

        let summary: String
        let groups: [MuscleGroup]
        if let session = selectedSession {
            let exercises = session.exerciseNames.joined(separator: ", ")
            summary = "\(session.title): \(exercises)"
            groups = Array(Set(session.sets.map(\.muscleGroup)))
        } else {
            summary = freeText.trimmingCharacters(in: .whitespaces)
            groups = []
        }

        Task {
            do {
                let result = try await RecoveryAIService.generate(
                    workoutSummary: summary,
                    muscleGroups: groups,
                    goals: goals.trimmingCharacters(in: .whitespaces),
                    kind: kind
                )
                generated = result.routine
                fallbackNote = result.fallbackNote
            } catch {
                errorMessage = "Generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    private func save(_ routine: RecoveryRoutine) {
        context.insert(routine)
        try? context.save()
        dismiss()
    }
}
