import Foundation
import SwiftData

/// A reusable workout plan, e.g. "Push Day A".
@Model
final class WorkoutTemplate {
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    var lastPerformedAt: Date?
    /// Manual position in the Fitness tab list (drag to reorder).
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template)
    var items: [TemplateItem] = []

    init(name: String, notes: String = "") {
        self.name = name
        self.notes = notes
        self.createdAt = .now
    }

    /// Items in the order you arranged them.
    var orderedItems: [TemplateItem] {
        items.sorted { $0.order < $1.order }
    }

    var summary: String {
        let count = items.count
        guard count > 0 else { return "No exercises yet" }
        return "\(count) exercise\(count == 1 ? "" : "s")"
    }
}

/// One exercise slot inside a template, with its set and rep targets.
@Model
final class TemplateItem {
    /// Stored by name so history survives deleting the `Exercise` record.
    var exerciseName: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.other
    var targetSets: Int = 3
    var targetReps: Int = 8
    /// Last weight used, in kilograms. Prefilled the next time you run this.
    var lastWeightKg: Double = 0
    /// Rest between sets of this exercise, in seconds. Copied onto each set
    /// when a session starts, so the rest clock is per-exercise.
    var restSeconds: Int = 90
    var order: Int = 0

    var template: WorkoutTemplate?

    init(
        exerciseName: String,
        muscleGroup: MuscleGroup = .other,
        targetSets: Int = 3,
        targetReps: Int = 8,
        restSeconds: Int = 90,
        order: Int = 0
    ) {
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.restSeconds = restSeconds
        self.order = order
    }
}
