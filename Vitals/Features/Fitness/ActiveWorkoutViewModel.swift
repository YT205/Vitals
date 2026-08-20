import Foundation
import Observation
import SwiftData
import SwiftUI

/// Owns the transient state of a workout in progress: the timer state machine,
/// live heart rate, and the finishing handshake with SwiftData and HealthKit.
///
/// The logged sets themselves live in SwiftData, so nothing here needs to hold
/// them -- the views bind straight to the model objects.
@MainActor
@Observable
final class ActiveWorkoutViewModel {
    /// One shared instance, because at most one workout runs at a time.
    ///
    /// App-lived on purpose: the timer belongs to the *workout*, not the
    /// workout screen. Leaving the screen mid-rest and coming back finds the
    /// clock exactly where it should be.
    static let shared = ActiveWorkoutViewModel()

    private init() {}

    /// The persistent dial cycles through these. One phase at a time:
    /// lifting (`set`), resting (`rest`), past the planned rest (`overtime`),
    /// or between exercises (`idle`).
    enum TimerPhase: Equatable {
        case idle
        case set
        case rest
        case overtime
    }

    // MARK: - Timer state

    private(set) var phase: TimerPhase = .idle

    /// The set currently being performed, if any.
    private(set) var activeSetID: PersistentIdentifier?
    /// Seconds since the active set started.
    private(set) var setElapsed: Int = 0

    /// Seconds left on the rest countdown.
    private(set) var restRemaining: Int = 0
    private(set) var restTotal: Int = 0
    /// Seconds past the planned rest (counts up, dial turns orange).
    private(set) var overtimeSeconds: Int = 0

    // Timing is anchored to wall-clock dates, not accumulated ticks: the tick
    // loop just re-derives the displayed values from these. Suspend the app
    // for two minutes mid-rest and the dial is correct the moment it returns.
    private var setAnchor: Date?
    private var restEndsAt: Date?

    private var tickTask: Task<Void, Never>?

    // MARK: - Heart rate

    var heartRate: (bpm: Double, date: Date)?

    // MARK: - Saving

    var isSaving = false
    var saveError: String?

    // No deinit: `deinit` is nonisolated and can't touch main-actor state. The
    // tick loop captures `self` weakly and returns once this object is gone.

    // MARK: - Dial presentation

    /// Ring fill for the current phase. Count-up phases (set, overtime) sweep
    /// once per minute; rest drains the planned time.
    var dialProgress: Double {
        switch phase {
        case .idle:
            0
        case .set:
            Double(setElapsed % 60) / 60
        case .rest:
            restTotal > 0 ? Double(restTotal - restRemaining) / Double(restTotal) : 0
        case .overtime:
            Double(overtimeSeconds % 60) / 60
        }
    }

    var dialTint: Color {
        switch phase {
        case .idle: .gray
        case .set: .accentColor
        case .rest: .blue
        case .overtime: .orange
        }
    }

    var dialValueText: String {
        switch phase {
        case .idle:
            "0:00"
        case .set:
            WorkoutSession.formatMinutesSeconds(Double(setElapsed))
        case .rest:
            WorkoutSession.formatMinutesSeconds(Double(restRemaining))
        case .overtime:
            "+" + WorkoutSession.formatMinutesSeconds(Double(overtimeSeconds))
        }
    }

    var dialCaption: String {
        switch phase {
        case .idle: "Ready"
        case .set: "In set"
        case .rest: "Rest"
        case .overtime: "Over rest"
        }
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

        let now = Date.now
        entry.startedAt = now
        activeSetID = entry.persistentModelID
        setAnchor = now
        setElapsed = 0
        restEndsAt = nil
        restRemaining = 0
        overtimeSeconds = 0
        phase = .set
        startTicking()
    }

    /// Stops the set timer, records the duration, marks the set done, and
    /// rolls the dial into that exercise's rest countdown.
    func finishSet(_ entry: SetEntry) {
        if let start = entry.startedAt {
            entry.durationSeconds = Date.now.timeIntervalSince(start)
        }
        entry.markDone()

        if isTiming(entry) {
            activeSetID = nil
            setElapsed = 0
        }

        if entry.restSeconds > 0 {
            startRest(seconds: entry.restSeconds)
        } else {
            goIdle()
        }
    }

    /// Un-does a completed set (checkmark tapped by mistake). Clears its
    /// timing so re-running it re-times it.
    func resetSet(_ entry: SetEntry) {
        entry.markNotDone()
    }

    // MARK: - Rest flow

    func startRest(seconds: Int) {
        guard seconds > 0 else {
            goIdle()
            return
        }
        restTotal = seconds
        restRemaining = seconds
        restEndsAt = Date.now.addingTimeInterval(TimeInterval(seconds))
        setAnchor = nil
        overtimeSeconds = 0
        phase = .rest
        startTicking()
    }

    func addRest(seconds: Int) {
        guard phase == .rest, let deadline = restEndsAt else { return }
        restEndsAt = deadline.addingTimeInterval(TimeInterval(seconds))
        restRemaining += seconds
        restTotal += seconds
    }

    /// Ends the rest (or overtime) and parks the dial.
    func skipRest() {
        goIdle()
    }

    private func goIdle() {
        phase = .idle
        setAnchor = nil
        restEndsAt = nil
        restRemaining = 0
        restTotal = 0
        overtimeSeconds = 0
        // The tick loop parks itself when it sees .idle.
    }

    // MARK: - The clock

    /// One shared 1 Hz loop re-derives the display from the date anchors; it
    /// never accumulates, so missed ticks (backgrounding, screen changes)
    /// can't drift the clock. Restarting is idempotent.
    private func startTicking() {
        refreshFromAnchors()
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }

                if self.phase == .idle {
                    // Nothing to advance; park the loop until the next start.
                    self.tickTask = nil
                    return
                }
                self.refreshFromAnchors()
            }
        }
    }

    /// Recomputes the published values from wall-clock time.
    private func refreshFromAnchors() {
        switch phase {
        case .idle:
            break
        case .set:
            setElapsed = max(0, Int(Date.now.timeIntervalSince(setAnchor ?? .now)))
        case .rest:
            let remaining = Int((restEndsAt?.timeIntervalSinceNow ?? 0).rounded(.up))
            if remaining > 0 {
                restRemaining = remaining
            } else {
                // Planned rest is up: flip to counting up, in orange.
                restRemaining = 0
                phase = .overtime
                refreshFromAnchors()
                Haptics.routineComplete()
            }
        case .overtime:
            overtimeSeconds = max(0, Int(-(restEndsAt?.timeIntervalSinceNow ?? 0)))
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
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
            activeSetID = nil
            setElapsed = 0
            goIdle()
        }
        context.delete(entry)
    }

    // MARK: - Finishing

    /// Closes the session, mirrors it to Apple Health, and writes what you
    /// actually lifted back into the template's per-set plan so next time is
    /// prefilled with real numbers.
    ///
    /// Every set with real data (weight or reps entered) is kept and counted,
    /// whether or not it was explicitly finished -- timing is optional. Only
    /// rows that are still completely empty are dropped.
    func finish(
        session: WorkoutSession,
        template: WorkoutTemplate?,
        effortScore: Int?,
        updatePlan: Bool = true,
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
        goIdle()
        stopTicking()

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
            // "Last done" always updates; the plan's numbers only move when
            // the user chose to update them on the finish sheet.
            template.lastPerformedAt = end
            if updatePlan {
                writeBackPlan(from: session, to: template)
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
        activeSetID = nil
        heartRate = nil
    }

    /// Copies performed weights and reps back onto the matching plan sets
    /// (matched by exercise name + set number), so the plan tracks reality.
    private func writeBackPlan(from session: WorkoutSession, to template: WorkoutTemplate) {
        for item in template.items {
            let performed = session.completedSets
                .filter { $0.exerciseName == item.exerciseName && !$0.isWarmup }

            for planSet in item.sets {
                if let match = performed.first(where: { $0.setNumber == planSet.setNumber }),
                   match.weightKg > 0 {
                    planSet.weightKg = match.weightKg
                    planSet.reps = match.reps
                }
            }

            // Legacy prefill field, still used when a plan has no per-set rows.
            if let heaviest = performed.map(\.weightKg).max(), heaviest > 0 {
                item.lastWeightKg = heaviest
            }
            item.refreshLegacySummary()
        }
    }

    /// Deletes the session *after* the workout screen has animated away.
    ///
    /// Deleting immediately was the freeze you hit: the screen's `@Bindable`
    /// session was destroyed while SwiftUI was still rendering it, mid-dismissal.
    /// The delay lets the pop animation finish so nothing is observing the
    /// object when it dies.
    func discardAfterDismiss(session: WorkoutSession, context: ModelContext) {
        goIdle()
        stopTicking()
        activeSetID = nil
        heartRate = nil
        saveError = nil
        let target = session
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            context.delete(target)
            try? context.save()
        }
    }
}
