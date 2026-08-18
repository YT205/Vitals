import Foundation
import SwiftData

/// The watch's own SwiftData stack: recovery routines only.
///
/// Deliberately separate from the iPhone store -- there is no automatic sync
/// between the two databases. The watch seeds the same starter routines, and
/// workouts/water converge through Apple Health instead. Syncing custom
/// routines and workout templates is the WatchConnectivity phase, later.
enum WatchModelContainer {
    static let schema = Schema([
        RecoveryRoutine.self,
        RecoveryStep.self,
    ])

    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            "VitalsWatch",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            seedIfNeeded(container)
            return container
        } catch {
            fatalError("Could not create the watch model container: \(error)")
        }
    }()

    private static func seedIfNeeded(_ container: ModelContainer) {
        let context = ModelContext(container)
        let count = (try? context.fetchCount(FetchDescriptor<RecoveryRoutine>())) ?? 0
        guard count == 0 else { return }
        for routine in RecoveryLibrary.starterRoutines() {
            context.insert(routine)
        }
        try? context.save()
    }
}
