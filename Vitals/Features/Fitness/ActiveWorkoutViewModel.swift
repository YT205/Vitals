import Foundation
import Observation
import SwiftData

/// Owns the transient state of a workout in progress: the rest timer, and the
/// finishing handshake with SwiftData and HealthKit.
///
/// The logged sets themselves live in SwiftData, so nothing here needs to hold
/// them -- the views bind straight to the model objects.
@MainActor
@Observable
final class ActiveWorkoutViewModel {
    /// Seconds left on the rest countdown. Zero means not resting.
    var restRemaining: Int = 0
    var restTotal: Int = 0
    var isSaving = false
    var saveError: String?

    private var restTask: Task<Void, Never>?

    var isResting: Bool { restRemaining > 0 }

    var restProgress: Double {
        guard restTotal > 0 else { return 0 }
        return Double(restTotal - restRemaining) / Double(restTotal)
    }

    var formattedRest: String {
        let minutes = restRemaining / 60
        let seconds = restRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // No deinit: `deinit` is nonisolated and can't touch main-actor state. The
    // rest loop captures `self` weakly and returns once this object is gone (and
    // also returns on its own when the countdown reaches zero).

    // MARK: - Rest timer

    func startRest(seconds: Int) {
        restTask?.cancel()
        restTotal = seconds
        restRemaining = seconds

        restTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.restRemaining > 0 else { return }
                self.restRemaining -= 1
            }
        }
    }

    func addRest(seconds: Int) {
        guard isResting else { return }
        restRemaining += seconds
        restTotal += seconds
    }

    func stopRest() {
        restTask?.cancel()
        restTask = nil
        restRemaining = 0
        restTotal = 0
    }

    // MARK: - Set management

    /// Adds one more set to an exercise, copying the weight and reps of the last
    /// set so you only change what actually changed.
    func addSet(
        toExercise name: String,
        in session: WorkoutSession,
        context: ModelContext
    ) {
        let existing = session.orderedSets.filter { $0.exerciseName == name }
        guard let template = existing.last else { return }

        let entry = SetEntry(
            exerciseName: name,
            muscleGroup: template.muscleGroup,
            exerciseOrder: template.exerciseOrder,
            setNumber: (existing.map(\.setNumber).max() ?? 0) + 1,
            weightKg: template.weightKg,
            reps: template.reps
        )
        entry.session = session
        context.insert(entry)
    }

    func addExercises(
        _ exercises: [Exercise],
        to session: WorkoutSession,
        context: ModelContext,
        setsEach: Int = 3,
        reps: Int = 8
    ) {
        var nextOrder = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1

        for exercise in exercises {
            // Skip anything already in the session.
            guard !session.sets.contains(where: { $0.exerciseName == exercise.name }) else {
                continue
            }
            for setNumber in 1...max(1, setsEach) {
                let entry = SetEntry(
                    exerciseName: exercise.name,
                    muscleGroup: exercise.muscleGroup,
                    exerciseOrder: nextOrder,
                    setNumber: setNumber,
                    weightKg: lastWeight(for: exercise.name, context: context),
                    reps: reps
                )
                entry.session = session
                context.insert(entry)
            }
            nextOrder += 1
        }
    }

    func delete(_ entry: SetEntry, context: ModelContext) {
        context.delete(entry)
    }

    /// Heaviest completed set for this exercise across all past sessions, used to
    /// prefill new rows.
    func lastWeight(for exerciseName: String, context: ModelContext) -> Double {
        var descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exerciseName == exerciseName && $0.isDone },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let match = try? context.fetch(descriptor).first
        return match?.weightKg ?? 0
    }

    // MARK: - Finishing

    /// Closes the session, mirrors it to Apple Health, and writes the weights
    /// used back onto the template so next time is prefilled.
    func finish(
        session: WorkoutSession,
        template: WorkoutTemplate?,
        context: ModelContext,
        health: HealthKitService = .shared
    ) async {
        stopRest()
        isSaving = true
        saveError = nil

        let end = Date.now
        session.endedAt = end

        // Drop any sets that were never completed so history stays honest.
        for entry in session.sets where !entry.isDone {
            context.delete(entry)
        }

        if let template {
            template.lastPerformedAt = end
            for item in template.items {
                let heaviest = session.completedSets
                    .filter { $0.exerciseName == item.exerciseName }
                    .map(\.weightKg)
                    .max()
                if let heaviest, heaviest > 0 {
                    item.lastWeightKg = heaviest
                }
            }
        }

        try? context.save()

        do {
            try await health.saveStrengthWorkout(
                start: session.startedAt,
                end: end,
                activeEnergyKcal: nil
            )
            session.savedToHealthKit = true
            try? context.save()
        } catch {
            // The workout is still saved locally; only the Health mirror failed.
            saveError = "Saved locally, but writing to Apple Health failed: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Throws the session away entirely.
    func discard(session: WorkoutSession, context: ModelContext) {
        stopRest()
        context.delete(session)
        try? context.save()
    }
}
