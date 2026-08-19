import Foundation
import SwiftData

/// The app's SwiftData stack.
///
/// HealthKit owns vitals, workouts and water *samples*. SwiftData owns the things
/// HealthKit can't model: exercise library, workout templates, per-set logs and
/// recovery routines. Register new `@Model` types in `schema` below.
enum VitalsModelContainer {
    static let schema = Schema([
        Exercise.self,
        WorkoutTemplate.self,
        TemplateItem.self,
        TemplateSet.self,
        WorkoutSession.self,
        SetEntry.self,
        RecoveryRoutine.self,
        RecoveryStep.self,
        WaterEntry.self,
    ])

    /// On-disk container used by the real app.
    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            "Vitals",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            seedIfNeeded(container)
            return container
        } catch {
            fatalError("Could not create the Vitals model container: \(error)")
        }
    }()

    /// In-memory container for SwiftUI previews, pre-seeded with library content.
    static let preview: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            seedIfNeeded(container, trackVersion: false)
            return container
        } catch {
            fatalError("Could not create the preview model container: \(error)")
        }
    }()

    private static let exerciseSeedVersionKey = "seed.exerciseLibraryVersion"

    /// Populates the built-in exercise library and starter recovery routines.
    ///
    /// Exercises are seeded by version: when `ExerciseLibrary.version` is newer
    /// than what this install last seeded, any library exercise not already in
    /// the store (matched by name, case-insensitive) is inserted. Existing rows
    /// and custom exercises are never touched, so re-seeding can't create
    /// duplicates or overwrite your data.
    ///
    /// Deliberately *not* `@MainActor`: it runs inside the `static let` closures
    /// above, which are nonisolated. So it uses its own `ModelContext` rather than
    /// `container.mainContext`, which is main-actor isolated.
    ///
    /// - Parameter trackVersion: `false` for the in-memory preview container,
    ///   which should always seed fully and must not read or write the real
    ///   install's version marker in `UserDefaults`.
    private static func seedIfNeeded(_ container: ModelContainer, trackVersion: Bool = true) {
        let context = ModelContext(container)

        let storedVersion = trackVersion
            ? UserDefaults.standard.integer(forKey: exerciseSeedVersionKey)
            : 0

        if storedVersion < ExerciseLibrary.version {
            let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            let existingNames = Set(existing.map { $0.name.lowercased() })

            for exercise in ExerciseLibrary.starterExercises()
            where !existingNames.contains(exercise.name.lowercased()) {
                context.insert(exercise)
            }

            if trackVersion {
                UserDefaults.standard.set(
                    ExerciseLibrary.version,
                    forKey: exerciseSeedVersionKey
                )
            }
        }

        let routineCount = (try? context.fetchCount(FetchDescriptor<RecoveryRoutine>())) ?? 0
        if routineCount == 0 {
            for routine in RecoveryLibrary.starterRoutines() {
                context.insert(routine)
            }
        } else if trackVersion {
            backfillRoutineTargets(context)
        }

        if trackVersion {
            removeDuplicateSessions(context)
        }

        try? context.save()
    }

    private static let dedupeKey = "cleanup.duplicateSessions.v1"

    /// One-shot: watch sync could ingest the same finished workout twice
    /// before ingest became idempotent (WCSession re-delivers unacknowledged
    /// transfers). Removes exact duplicates -- same title, same start time --
    /// keeping the first of each.
    private static func removeDuplicateSessions(_ context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: dedupeKey) < 1 else { return }

        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt)]
        )
        guard let sessions = try? context.fetch(descriptor) else { return }

        var seen = Set<String>()
        for session in sessions {
            let key = "\(session.title)|\(session.startedAt.timeIntervalSince1970)"
            if seen.contains(key) {
                context.delete(session)
            } else {
                seen.insert(key)
            }
        }

        UserDefaults.standard.set(1, forKey: dedupeKey)
    }

    private static let routineTargetsKey = "seed.recoveryTargetsVersion"

    /// One-shot: installs that seeded routines before `targetGroups` existed get
    /// targets backfilled by name, so the Suggested section works for them too.
    /// Routines you created or renamed are untouched.
    private static func backfillRoutineTargets(_ context: ModelContext) {
        guard UserDefaults.standard.integer(forKey: routineTargetsKey) < 1 else { return }

        let known: [String: [MuscleGroup]] = [
            "Post Leg Day Stretch": [.legs, .glutes, .calves],
            "Post Push Day Stretch": [.chest, .shoulders, .triceps],
            "Massage Gun: Lower Body": [.legs, .glutes, .calves],
            "Massage Gun: Upper Body": [.chest, .back, .shoulders, .biceps, .triceps],
        ]

        let routines = (try? context.fetch(FetchDescriptor<RecoveryRoutine>())) ?? []
        for routine in routines where routine.targetGroups.isEmpty {
            if let targets = known[routine.name] {
                routine.targetGroups = targets
            }
        }

        UserDefaults.standard.set(1, forKey: routineTargetsKey)
    }
}
