import Foundation
import SwiftData
import WatchConnectivity

/// The iPhone end of watch sync.
///
/// Outbound: the template library and unit preferences, pushed as application
/// context whenever templates change (and on every activation, so a fresh
/// watch install catches up immediately).
/// Inbound: finished watch workouts, ingested into SwiftData exactly like a
/// phone-logged session -- history, progress charts and plan write-back all
/// see them. The HKWorkout itself was already written by the watch.
final class PhoneSyncService: NSObject {
    static let shared = PhoneSyncService()

    private override init() {
        super.init()
    }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    /// Call once at launch. Safe to call repeatedly.
    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    // MARK: - Outbound: templates + preferences

    /// Snapshots every template into the wire format and pushes it. Runs its
    /// own fetch so callers don't need to pass a context.
    @MainActor
    func pushTemplates(settings: AppSettings? = nil) {
        guard let session, session.activationState == .activated else { return }

        let context = ModelContext(VitalsModelContainer.shared)
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        guard let templates = try? context.fetch(descriptor) else { return }

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

        guard let data = SyncCoder.encode(payload) else { return }

        var contextDict: [String: Any] = [
            SyncKeys.templates: data,
            // Uniquify each push; identical contexts are rejected by the API.
            SyncKeys.pushedAt: Date.now.timeIntervalSince1970,
        ]
        if let settings {
            contextDict[SyncKeys.weightUnit] = settings.weightUnit.rawValue
            contextDict[SyncKeys.volumeUnit] = settings.volumeUnit.rawValue
            contextDict[SyncKeys.waterGoalML] = settings.dailyWaterGoalML
        }

        try? session.updateApplicationContext(contextDict)
    }

    // MARK: - Inbound: finished watch workouts

    @MainActor
    private func ingest(_ finished: SyncFinishedWorkout) {
        let context = ModelContext(VitalsModelContainer.shared)

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
    @MainActor
    private func writeBackToTemplate(_ workout: WorkoutSession, context: ModelContext) {
        let title = workout.title
        let descriptor = FetchDescriptor<WorkoutTemplate>(
            predicate: #Predicate { $0.name == title }
        )
        guard let template = try? context.fetch(descriptor).first else { return }

        template.lastPerformedAt = workout.endedAt

        for item in template.items {
            let performed = workout.sets.filter {
                $0.exerciseName == item.exerciseName && !$0.isWarmup
            }
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
}

// MARK: - WCSessionDelegate

extension PhoneSyncService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.pushTemplates()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after a watch switch.
        session.activate()
    }

    /// Finished workouts arrive here, queued until the phone was reachable.
    func session(
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
