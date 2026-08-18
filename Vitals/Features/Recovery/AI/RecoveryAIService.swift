import Foundation
import FoundationModels

// MARK: - Generable output shape

/// What the model fills in. Guides constrain the ranges so the output lands
/// valid; code-level clamping below backstops it anyway.
@Generable(description: "A post-workout recovery routine")
struct AIGeneratedRoutine {
    @Guide(description: "Short routine name, at most five words, no quotes")
    var name: String

    @Guide(description: "One sentence of overall guidance for the routine")
    var notes: String

    @Guide(description: "Muscle groups this routine targets", .count(1...6))
    var targetMuscles: [String]

    @Guide(description: "The ordered steps of the routine", .count(4...12))
    var steps: [AIGeneratedStep]
}

@Generable(description: "One timed step in a recovery routine")
struct AIGeneratedStep {
    @Guide(description: "Name of the stretch or the muscle to massage, at most six words")
    var name: String

    @Guide(description: "Seconds to hold the stretch or work the muscle", .range(20...120))
    var seconds: Int

    @Guide(description: "True when the step is done once per side of the body")
    var isPerSide: Bool

    @Guide(description: "One short coaching cue, a single sentence")
    var instruction: String
}

// MARK: - Service

/// On-device routine generation via Apple's Foundation Models.
///
/// Everything runs locally: the workout summary and goals never leave the
/// phone. When Apple Intelligence isn't available (unsupported device, model
/// still downloading, feature off), `generate` falls back to the rule-based
/// bank so the button always produces something.
@MainActor
enum RecoveryAIService {
    enum Availability {
        case available
        case unavailable(String)
    }

    static func availability() -> Availability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            let text = switch reason {
            case .deviceNotEligible:
                "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                "Turn on Apple Intelligence in Settings to generate routines."
            case .modelNotReady:
                "The on-device model is still downloading. Try again shortly."
            @unknown default:
                "Apple Intelligence isn't available right now."
            }
            return .unavailable(text)
        }
    }

    struct Result {
        let routine: RecoveryRoutine
        /// `true` when the rule-based bank produced it (model unavailable).
        let usedFallback: Bool
    }

    /// Generates a routine for a workout description and the user's goals.
    ///
    /// - Parameters:
    ///   - workoutSummary: e.g. "Push Day A: Bench Press 4 sets, ..." or the
    ///     user's free text about what they trained.
    ///   - muscleGroups: groups from the picked workout; used by the fallback
    ///     and attached to the saved routine for suggestions.
    ///   - goals: the user's own words ("hamstrings tight, 10 minutes max").
    ///   - kind: stretching or massage gun.
    static func generate(
        workoutSummary: String,
        muscleGroups: [MuscleGroup],
        goals: String,
        kind: RecoveryKind
    ) async throws -> Result {
        guard case .available = availability() else {
            return Result(
                routine: fallbackRoutine(muscleGroups: muscleGroups, kind: kind),
                usedFallback: true
            )
        }

        let session = LanguageModelSession(instructions: instructions(for: kind))
        let prompt = buildPrompt(
            workoutSummary: workoutSummary,
            goals: goals,
            kind: kind
        )

        let response = try await session.respond(
            to: prompt,
            generating: AIGeneratedRoutine.self
        )

        let routine = sanitized(response.content, kind: kind, muscleGroups: muscleGroups)
        return Result(routine: routine, usedFallback: false)
    }

    // MARK: - Prompting

    private static func instructions(for kind: RecoveryKind) -> String {
        let modality = kind == .massageGun
            ? """
            You design massage gun recovery sequences. Safety rules that must \
            never be violated: never target the neck, throat, spine, abdomen, \
            armpits, or any bone or joint. Only name large muscle bellies. \
            Recommend light to medium pressure.
            """
            : """
            You design post-workout static stretching sequences. Prefer \
            well-known stretches with common names. Holds are gentle; never \
            suggest ballistic or painful stretching.
            """

        return modality + """
         Order steps so adjacent steps flow into each other (standing \
        together, floor together). Mark a step per-side only when it \
        genuinely works one side at a time. Keep instructions to one short \
        cue each. Target muscles must be chosen from: \
        \(MuscleGroup.allCases.map(\.rawValue).joined(separator: ", ")).
        """
    }

    private static func buildPrompt(
        workoutSummary: String,
        goals: String,
        kind: RecoveryKind
    ) -> String {
        var parts: [String] = []
        parts.append("Create a \(kind == .massageGun ? "massage gun" : "stretching") recovery routine.")
        if !workoutSummary.isEmpty {
            parts.append("The workout just completed: \(workoutSummary).")
        }
        if !goals.isEmpty {
            parts.append("The lifter's goals and constraints: \(goals).")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Validation

    /// Model output crosses a trust boundary: clamp durations, cap counts,
    /// drop empty steps, and map muscle names leniently.
    private static func sanitized(
        _ generated: AIGeneratedRoutine,
        kind: RecoveryKind,
        muscleGroups: [MuscleGroup]
    ) -> RecoveryRoutine {
        var targets = generated.targetMuscles.compactMap { raw in
            MuscleGroup(rawValue: raw.lowercased().trimmingCharacters(in: .whitespaces))
        }
        if targets.isEmpty { targets = muscleGroups }

        let name = generated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = RecoveryRoutine(
            name: name.isEmpty ? "AI Recovery" : String(name.prefix(40)),
            kind: kind,
            notes: String(generated.notes.prefix(160)),
            targetGroups: Array(Set(targets))
        )

        let steps = generated.steps
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(15)

        routine.steps = steps.enumerated().map { index, step in
            RecoveryStep(
                name: String(step.name.prefix(50)),
                seconds: min(max(step.seconds, 15), 180),
                instructions: String(step.instruction.prefix(120)),
                isPerSide: step.isPerSide,
                order: index
            )
        }
        return routine
    }

    // MARK: - Fallback

    /// The rule-based bank, kept for devices without Apple Intelligence.
    private static func fallbackRoutine(
        muscleGroups: [MuscleGroup],
        kind: RecoveryKind
    ) -> RecoveryRoutine {
        let groups = muscleGroups.isEmpty ? [.fullBody] : muscleGroups
        let suffix = kind == .massageGun ? "Massage" : "Stretch"
        return RecoveryLibrary.generatedRoutine(
            named: "Recovery \(suffix)",
            for: groups,
            kind: kind
        )
    }
}
