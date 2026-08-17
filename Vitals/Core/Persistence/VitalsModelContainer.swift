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
            seedIfNeeded(container)
            return container
        } catch {
            fatalError("Could not create the preview model container: \(error)")
        }
    }()

    /// Populates the built-in exercise library and starter recovery routines the
    /// first time the app runs. Safe to call repeatedly.
    ///
    /// Deliberately *not* `@MainActor`: it runs inside the `static let` closures
    /// above, which are nonisolated. So it uses its own `ModelContext` rather than
    /// `container.mainContext`, which is main-actor isolated.
    private static func seedIfNeeded(_ container: ModelContainer) {
        let context = ModelContext(container)

        let exerciseCount = (try? context.fetchCount(FetchDescriptor<Exercise>())) ?? 0
        if exerciseCount == 0 {
            for exercise in ExerciseLibrary.starterExercises() {
                context.insert(exercise)
            }
        }

        let routineCount = (try? context.fetchCount(FetchDescriptor<RecoveryRoutine>())) ?? 0
        if routineCount == 0 {
            for routine in RecoveryLibrary.starterRoutines() {
                context.insert(routine)
            }
        }

        try? context.save()
    }
}
