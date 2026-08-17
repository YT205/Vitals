import Foundation
import SwiftData

/// A reusable workout plan, e.g. "Push Day A".
@Model
final class WorkoutTemplate {
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    var lastPerformedAt: Date?

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
    var order: Int = 0

    var template: WorkoutTemplate?

    init(
        exerciseName: String,
        muscleGroup: MuscleGroup = .other,
        targetSets: Int = 3,
        targetReps: Int = 8,
        order: Int = 0
    ) {
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.order = order
    }
}
