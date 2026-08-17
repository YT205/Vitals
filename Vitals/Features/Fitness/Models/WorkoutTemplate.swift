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

/// One exercise slot inside a template.
///
/// The plan is per-set (`planSets`): each set carries its own weight and reps,
/// mirroring the live workout UI. `targetSets`/`targetReps` are kept as legacy
/// fields (pre-per-set installs) and as a cheap summary; `planSets(in:)`
/// synthesizes plan rows from them the first time an old item is opened.
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

    @Relationship(deleteRule: .cascade, inverse: \TemplateSet.item)
    var sets: [TemplateSet] = []

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

    var orderedSets: [TemplateSet] {
        sets.sorted { $0.setNumber < $1.setNumber }
    }

    /// The per-set plan, creating it from the legacy target fields the first
    /// time an item that predates per-set editing is touched.
    @discardableResult
    func materializedPlan(in context: ModelContext) -> [TemplateSet] {
        if !sets.isEmpty { return orderedSets }
        for number in 1...max(1, targetSets) {
            let planSet = TemplateSet(
                setNumber: number,
                reps: targetReps,
                weightKg: lastWeightKg
            )
            planSet.item = self
            context.insert(planSet)
        }
        return orderedSets
    }

    /// Display-only plan for previews: real sets when present, otherwise a
    /// synthesized view of the legacy fields (nothing is inserted).
    var displayPlan: [(setNumber: Int, reps: Int, weightKg: Double)] {
        if !sets.isEmpty {
            return orderedSets.map { ($0.setNumber, $0.reps, $0.weightKg) }
        }
        return (1...max(1, targetSets)).map { ($0, targetReps, lastWeightKg) }
    }

    /// Keeps the legacy summary fields roughly in sync after per-set edits.
    func refreshLegacySummary() {
        guard !sets.isEmpty else { return }
        targetSets = sets.count
        if let firstReps = orderedSets.first?.reps {
            targetReps = firstReps
        }
    }
}

/// One planned set inside a template item: its own weight and reps, exactly
/// like a set row in the live workout.
@Model
final class TemplateSet {
    var setNumber: Int = 1
    var reps: Int = 8
    /// Kilograms, converted to the user's unit at display time.
    var weightKg: Double = 0

    var item: TemplateItem?

    init(setNumber: Int, reps: Int = 8, weightKg: Double = 0) {
        self.setNumber = setNumber
        self.reps = reps
        self.weightKg = weightKg
    }
}
