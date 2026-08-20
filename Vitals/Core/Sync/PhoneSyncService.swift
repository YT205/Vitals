import Foundation
import SwiftData
import WatchConnectivity

/// The iPhone end of watch sync.
///
/// Outbound: the template library and unit preferences, pushed as application
/// context whenever templates change, when the session activates, and when
/// the watch app first becomes installed (`sessionWatchStateDidChange`) --
/// that last one is what makes install order not matter. The watch can also
/// request the library directly via message when both apps are live.
/// Inbound: finished watch workouts, ingested into SwiftData exactly like a
/// phone-logged session -- history, progress charts and plan write-back all
/// see them. The HKWorkout itself was already written by the watch.
@MainActor
@Observable
final class PhoneSyncService: NSObject {
    static let shared = PhoneSyncService()

    // Status, surfaced in Settings so sync failures are visible, not silent.
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var lastPushAt: Date?
    private(set) var lastError: String?

    private override init() {
        super.init()
    }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    /// Call once at launch. Safe to call repeatedly; pushes if already active.
    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState == .activated {
            refreshStatus()
            pushTemplates()
        } else {
            session.activate()
        }
    }

    private func refreshStatus() {
        guard let session else { return }
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
    }

    // MARK: - Outbound: templates + preferences

    /// Snapshots every template into the wire format. Used for both the
    /// context push and direct replies to watch requests.
    private func templatesPayload(settings: AppSettings? = nil) -> [String: Any]? {
        let context = ModelContext(VitalsModelContainer.shared)
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        guard let templates = try? context.fetch(descriptor) else { return nil }

        let payload = templates.map { template in
            SyncTemplate(
                name: template.name,
                sortOrder: template.sortOrder,
                items: template.orderedItems.map { item in
                    SyncTemplateItem(
                        exerciseName: item.exerciseName,
                        muscleGroupRaw: item.muscleGroup.rawValue,
                        restSeconds: item.restSeconds,
                        sets: item.displayPlan.map {
                            SyncPlanSet(
                                setNumber: $0.setNumber,
                                reps: $0.reps,
                                weightKg: $0.weightKg
                            )
                        }
                    )
                }
            )
        }

        guard let data = SyncCoder.encode(payload) else { return nil }

        var dict: [String: Any] = [
            SyncKeys.templates: data,
            // Uniquify each push; identical contexts are rejected by the API.
            SyncKeys.pushedAt: Date.now.timeIntervalSince1970,
        ]
        if let settings {
            dict[SyncKeys.weightUnit] = settings.weightUnit.rawValue
            dict[SyncKeys.volumeUnit] = settings.volumeUnit.rawValue
            dict[SyncKeys.waterGoalML] = settings.dailyWaterGoalML
        }
        return dict
    }

    /// Pushes the library as application context (latest state wins, delivered
    /// to the watch whenever it's ready). Errors are kept, not swallowed.
    func pushTemplates(settings: AppSettings? = nil) {
        guard let session, session.activationState == .activated else {
            lastError = "Sync session not active yet."
            return
        }
        refreshStatus()
        guard let dict = templatesPayload(settings: settings) else { return }

        do {
            try session.updateApplicationContext(dict)
            lastPushAt = .now
            lastError = nil
        } catch {
            // Most commonly: watch not paired, or the watch app not installed
            // yet. sessionWatchStateDidChange retries when that changes.
            lastError = error.localizedDescription
        }
    }

    // MARK: - Inbound: finished watch workouts

    private func ingest(_ finished: SyncFinishedWorkout) {
        let context = ModelContext(VitalsModelContainer.shared)

        // Idempotency: WCSession re-delivers queued transfers when the app
        // was killed before acknowledging them (constant during development
        // rebuilds). Same title + same start time = the same workout.
        let title = finished.title
        let start = finished.startedAt
        let existing = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.title == title && $0.startedAt == start }
        )
        if let count = try? context.fetchCount(existing), count > 0 {
            return
        }

        let workout = WorkoutSession(title: finished.title, startedAt: finished.startedAt)
        workout.endedAt = finished.endedAt
        // The watch's HKWorkoutSession already wrote the HealthKit record.
        workout.savedToHealthKit = true
        context.insert(workout)

        for performed in finished.sets {
            let entry = SetEntry(
                exerciseName: performed.exerciseName,
                muscleGroup: MuscleGroup(rawValue: performed.muscleGroupRaw) ?? .other,
                exerciseOrder: performed.exerciseOrder,
                setNumber: performed.setNumber,
                weightKg: performed.weightKg,
                reps: performed.reps,
                restSeconds: performed.restSeconds
            )
            entry.durationSeconds = performed.durationSeconds
            entry.isDone = true
            entry.completedAt = finished.endedAt
            entry.session = workout
            context.insert(entry)
        }

        writeBackToTemplate(workout, context: context)
        try? context.save()

        // The plan may have moved (weights written back); let the watch know.
        pushTemplates()
    }

    /// Same write-back the phone's finish flow does: performed weights and
    /// reps update the matching plan sets so next session is prefilled.
    private func writeBackToTemplate(_ workout: WorkoutSession, context: ModelContext) {
        let title = workout.title
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.name == title }
        )
        guard let template = try? context.fetch(descriptor).first else { return }

        template.lastPerformedAt = workout.endedAt

        for item in template.items {
            writeBack(workout, to: item)
            if let alternate = item.alternate {
                writeBack(workout, to: alternate)
            }
        }
    }

    /// Matches performed sets to one variant by its own name, so swapped
    /// sessions update only the variant that was actually done.
    @MainActor
    private func writeBack(_ workout: WorkoutSession, to item: TemplateItem) {
        let performed = workout.sets.filter {
            $0.exerciseName == item.exerciseName && !$0.isWarmup
        }
        guard !performed.isEmpty else { return }

        for planSet in item.sets {
            if let match = performed.first(where: { $0.setNumber == planSet.setNumber }),
               match.weightKg > 0 {
                planSet.weightKg = match.weightKg
                planSet.reps = match.reps
            }
        }
        if let heaviest = performed.map(\.weightKg).max(), heaviest > 0 {
            item.lastWeightKg = heaviest
        }
        item.refreshLegacySummary()
    }
}

// MARK: - WCSessionDelegate

extension PhoneSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.refreshStatus()
            self.pushTemplates()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after a watch switch.
        session.activate()
    }

    /// Fires when pairing changes or the watch app gets installed -- the fix
    /// for "ran the phone app before the watch app existed".
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus()
            if session.isPaired && session.isWatchAppInstalled {
                self.pushTemplates()
            }
        }
    }

    /// The watch asking for the library right now (both apps live).
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[SyncKeys.requestTemplates] != nil else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            replyHandler(self.templatesPayload() ?? [:])
        }
    }

    /// Finished workouts arrive here, queued until the phone was reachable.
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard
            let data = userInfo[SyncKeys.finishedWorkout] as? Data,
            let finished = SyncCoder.decode(SyncFinishedWorkout.self, from: data)
        else { return }

        Task { @MainActor in
            self.ingest(finished)
        }
    }
}
