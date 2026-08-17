import Foundation
import Observation
import SwiftData

/// Owns the transient state of a workout in progress: which set is being
/// timed, the rest countdown, live heart rate, and the finishing handshake
/// with SwiftData and HealthKit.
///
/// The logged sets themselves live in SwiftData, so nothing here needs to hold
/// them -- the views bind straight to the model objects.
@MainActor
@Observable
final class ActiveWorkoutViewModel {
    // MARK: - Set timing

    /// The set currently being performed, if any.
    private(set) var activeSetID: PersistentIdentifier?
    /// Seconds since the active set started.
    private(set) var setElapsed: Int = 0

    private var setTask: Task<Void, Never>?

    // MARK: - Rest timer

    /// Seconds left on the rest countdown. Zero means not resting.
    var restRemaining: Int = 0
    var restTotal: Int = 0

    private var restTask: Task<Void, Never>?

    // MARK: - Heart rate

    var heartRate: (bpm: Double, date: Date)?

    // MARK: - Saving

    var isSaving = false
    var saveError: String?

    // No deinit: `deinit` is nonisolated and can't touch main-actor state. All
    // timer loops capture `self` weakly and return once this object is gone.

    var isResting: Bool { restRemaining > 0 }

    var restProgress: Double {
        guard restTotal > 0 else { return 0 }
        return Double(restTotal - restRemaining) / Double(restTotal)
    }

    var formattedRest: String {
        WorkoutSession.formatMinutesSeconds(Double(restRemaining))
    }

    var formattedSetElapsed: String {
        WorkoutSession.formatMinutesSeconds(Double(setElapsed))
    }

    func isTiming(_ entry: SetEntry) -> Bool {
        activeSetID == entry.persistentModelID
    }

    // MARK: - Set flow

    /// Begins timing a set. If another set is mid-flight it gets finished
    /// first, so exactly one set is ever active.
    func startSet(_ entry: SetEntry, in session: WorkoutSession) {
        if let activeSetID, activeSetID != entry.persistentModelID {
            if let current = session.sets.first(where: {
                $0.persistentModelID == activeSetID
            }) {
                finishSet(current)
            }
        }

        stopRest()  // lifting now; the rest break is over either way
        entry.startedAt = .now
        activeSetID = entry.persistentModelID
        setElapsed = 0

        setTask?.cancel()
        setTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self, self.activeSetID != nil else { return }
                self.setElapsed += 1
            }
        }
    }

    /// Stops the set timer, records the duration, marks the set done, and
    /// starts that exercise's rest countdown.
    func finishSet(_ entry: SetEntry) {
        if let start = entry.startedAt {
            entry.durationSeconds = Date.now.timeIntervalSince(start)
        }
        entry.markDone()

        if isTiming(entry) {
            setTask?.cancel()
            setTask = nil
            activeSetID = nil
            setElapsed = 0
        }

        startRest(seconds: entry.restSeconds)
    }

    /// Un-does a completed set (checkmark tapped by mistake). Clears its
    /// timing so re-running it re-times it.
    func resetSet(_ entry: SetEntry) {
        entry.markNotDone()
    }

    // MARK: - Rest timer

    func startRest(seconds: Int) {
        guard seconds > 0 else { return }
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

    // MARK: - Heart rate

    /// Polls HealthKit for the newest heart rate sample until the view goes
    /// away. During a workout the watch samples much more often than at rest,
    /// so this stays reasonably fresh even without a watch app.
    func pollHeartRate(every interval: Duration = .seconds(15)) async {
        while !Task.isCancelled {
            heartRate = try? await HealthKitService.shared.latestHeartRate()
            try? await Task.sleep(for: interval)
        }
    }

    // MARK: - Set management

    func delete(_ entry: SetEntry, context: ModelContext) {
        if isTiming(entry) {
            setTask?.cancel()
            setTask = nil
            activeSetID = nil
            setElapsed = 0
        }
        context.delete(entry)
    }

    // MARK: - Finishing

    /// Closes the session, mirrors it to Apple Health, and writes the weights
    /// used back onto the template so next time is prefilled.
    ///
    /// Every set with real data (weight or reps entered) is kept and counted,
    /// whether or not it was explicitly finished -- timing is optional. Only
    /// rows that are still completely empty are dropped.
    func finish(
        session: WorkoutSession,
        template: WorkoutTemplate?,
        effortScore: Int?,
        context: ModelContext,
        health: HealthKitService = .shared
    ) async {
        // Close out a set still on the clock.
        if let activeSetID,
           let current = session.sets.first(where: {
               $0.persistentModelID == activeSetID
           }) {
            finishSet(current)
        }
        stopRest()
        setTask?.cancel()
        setTask = nil

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
        setTask?.cancel()
        setTask = nil
        let target = session
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            context.delete(target)
            try? context.save()
        }
    }
}
