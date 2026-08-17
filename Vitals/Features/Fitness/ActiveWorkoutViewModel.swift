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

    func delete(_ entry: SetEntry, context: ModelContext) {
        context.delete(entry)
    }

    // MARK: - Finishing

    /// Closes the session, mirrors it to Apple Health, and writes the weights
    /// used back onto the template so next time is prefilled.
    ///
    /// Every set with real data (weight or reps entered) is kept and counted,
    /// whether or not its checkmark was tapped -- the checkmark just drives the
    /// rest timer. Only rows that are still completely empty are dropped.
    func finish(
        session: WorkoutSession,
        template: WorkoutTemplate?,
        effortScore: Int?,
        context: ModelContext,
        health: HealthKitService = .shared
    ) async {
        stopRest()
        isSaving = true
        saveError = nil

        let end = Date.now
        session.endedAt = end
        session.effortScore = effortScore

        for entry in session.sets where !entry.isDone {
            if entry.weightKg > 0 || entry.reps > 0 {
                entry.markDone()
            } else {
                context.delete(entry)
            }
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
                activeEnergyKcal: nil,
                effortScore: effortScore
            )
            session.savedToHealthKit = true
            try? context.save()
        } catch {
            // The workout is still saved locally; only the Health mirror failed.
            saveError = "Saved locally, but writing to Apple Health failed: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Deletes the session *after* the workout screen has animated away.
    ///
    /// Deleting immediately was the freeze you hit: the screen's `@Bindable`
    /// session was destroyed while SwiftUI was still rendering it, mid-dismissal.
    /// The delay lets the pop animation finish so nothing is observing the
    /// object when it dies.
    func discardAfterDismiss(session: WorkoutSession, context: ModelContext) {
        stopRest()
        let target = session
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            context.delete(target)
            try? context.save()
        }
    }
}
