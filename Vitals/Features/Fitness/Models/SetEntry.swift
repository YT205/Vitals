import Foundation
import SwiftData

/// A single logged set: this weight, this many reps.
///
/// Exercise details are denormalised onto the entry so a workout you did last
/// year still reads correctly after you rename or delete the exercise.
@Model
final class SetEntry {
    var exerciseName: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.other
    /// Position of the exercise within the session.
    var exerciseOrder: Int = 0
    /// 1-based index of this set within its exercise.
    var setNumber: Int = 1
    /// Canonical storage is kilograms; the UI converts to the user's unit.
    var weightKg: Double = 0
    var reps: Int = 0
    var isWarmup: Bool = false
    var isDone: Bool = false
    /// Rate of perceived exertion, 1...10. Optional, ignore it if you don't care.
    var rpe: Double?
    var completedAt: Date?

    var session: WorkoutSession?

    init(
        exerciseName: String,
        muscleGroup: MuscleGroup = .other,
        exerciseOrder: Int = 0,
        setNumber: Int = 1,
        weightKg: Double = 0,
        reps: Int = 0,
        isWarmup: Bool = false
    ) {
        self.exerciseName = exerciseName
        self.muscleGroup = muscleGroup
        self.exerciseOrder = exerciseOrder
        self.setNumber = setNumber
        self.weightKg = weightKg
        self.reps = reps
        self.isWarmup = isWarmup
    }

    var volumeKg: Double { weightKg * Double(reps) }

    /// Estimated one-rep max using the Epley formula. Handy for tracking progress.
    var estimatedOneRepMaxKg: Double {
        guard reps > 0, weightKg > 0 else { return 0 }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    func markDone() {
        isDone = true
        completedAt = .now
    }

    func markNotDone() {
        isDone = false
        completedAt = nil
    }
}
