import Foundation
import HealthKit
import Observation
import SwiftUI

/// Runs the live workout on the watch: an `HKWorkoutSession` (which keeps the
/// app alive with the wrist down and streams real sensor data) plus the same
/// set/rest/overtime dial the phone uses, date-anchored.
///
/// Sets are counted, not itemized -- the per-set weight/reps plan lives on the
/// phone until WatchConnectivity sync exists. The finished workout lands in
/// Apple Health either way, so both devices see it.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    static let shared = WatchWorkoutManager()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // MARK: - Published state

    private(set) var isRunning = false
    private(set) var startDate: Date?
    private(set) var workoutTitle = ""

    /// Live metrics from the workout builder.
    private(set) var heartRate: Double = 0
    private(set) var activeEnergy: Double = 0

    /// One performed set, born from the template plan and edited in place.
    struct PerformedSet: Identifiable {
        let id = UUID()
        let exerciseName: String
        let muscleGroupRaw: String
        let exerciseOrder: Int
        let setNumber: Int
        var weightKg: Double
        var reps: Int
        var durationSeconds: Double = 0
        var isDone = false
        let restSeconds: Int
    }

    /// Every set of the session, in plan order.
    private(set) var sets: [PerformedSet] = []
    /// Index of the set currently up (next to do, or being done).
    private(set) var currentIndex = 0

    /// Set/rest dial, same phases as the phone.
    enum Phase: Equatable { case idle, set, rest, overtime }
    private(set) var phase: Phase = .idle
    private(set) var setElapsed = 0
    private(set) var restRemaining = 0
    private(set) var restTotal = 0
    private(set) var overtimeSeconds = 0

    var errorMessage: String?

    private var setAnchor: Date?
    private var restEndsAt: Date?
    private var tickTask: Task<Void, Never>?

    // MARK: - Derived session state

    var currentSet: PerformedSet? {
        sets.indices.contains(currentIndex) ? sets[currentIndex] : nil
    }

    var doneCount: Int { sets.filter(\.isDone).count }

    var totalVolumeKg: Double {
        sets.filter(\.isDone).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }

    var totalSetSeconds: Double {
        sets.reduce(0) { $0 + $1.durationSeconds }
    }

    var allDone: Bool { !sets.isEmpty && sets.allSatisfy(\.isDone) }

    /// The sets belonging to the current exercise, for the position bar.
    var currentExerciseSets: [PerformedSet] {
        guard let current = currentSet else { return [] }
        return sets.filter { $0.exerciseName == current.exerciseName }
    }

    func updateSet(id: UUID, weightKg: Double? = nil, reps: Int? = nil) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        if let weightKg { sets[index].weightKg = weightKg }
        if let reps { sets[index].reps = reps }
    }

    private override init() {
        super.init()
    }

    // MARK: - Elapsed

    var elapsedText: String {
        guard let startDate else { return "0:00" }
        let seconds = Date.now.timeIntervalSince(startDate)
        let total = Int(seconds)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var dialProgress: Double {
        switch phase {
        case .idle: 0
        case .set: Double(setElapsed % 60) / 60
        case .rest: restTotal > 0 ? Double(restTotal - restRemaining) / Double(restTotal) : 0
        case .overtime: Double(overtimeSeconds % 60) / 60
        }
    }

    var dialTint: Color {
        switch phase {
        case .idle: .gray
        case .set: .green
        case .rest: .blue
        case .overtime: .orange
        }
    }

    var dialText: String {
        switch phase {
        case .idle: "--"
        case .set: format(setElapsed)
        case .rest: format(restRemaining)
        case .overtime: "+" + format(overtimeSeconds)
        }
    }

    var dialCaption: String {
        switch phase {
        case .idle: "Ready"
        case .set: "In set"
        case .rest: "Rest"
        case .overtime: "Over"
        }
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Workout lifecycle

    func requestAuthorization() async {
        let read: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
        ].compactMap { $0 }.reduce(into: []) { $0.insert($1) }

        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            share.insert(energy)
        }

        try? await healthStore.requestAuthorization(toShare: share, read: read)
    }

    /// Starts a session from one of the phone's synced templates. There is no
    /// blank-workout path on purpose: plans are made on the phone.
    func startWorkout(template: SyncTemplate) async {
        guard !isRunning else { return }
        errorMessage = nil

        // Flatten the plan into the session's set list, in order.
        var flattened: [PerformedSet] = []
        for (order, item) in template.items.enumerated() {
            for planSet in item.sets.sorted(by: { $0.setNumber < $1.setNumber }) {
                flattened.append(
                    PerformedSet(
                        exerciseName: item.exerciseName,
                        muscleGroupRaw: item.muscleGroupRaw,
                        exerciseOrder: order,
                        setNumber: planSet.setNumber,
                        weightKg: planSet.weightKg,
                        reps: planSet.reps,
                        restSeconds: item.restSeconds
                    )
                )
            }
        }
        guard !flattened.isEmpty else {
            errorMessage = "This workout has no sets. Add some on your iPhone."
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder

            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            workoutTitle = template.name
            sets = flattened
            currentIndex = 0
            startDate = start
            isRunning = true
            phase = .idle
        } catch {
            errorMessage = "Couldn't start the workout: \(error.localizedDescription)"
        }
    }

    func endWorkout() async {
        guard let session, let builder else { return }
        goIdle()
        stopTicking()

        let start = startDate ?? .now
        let end = Date.now
        session.end()
        do {
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            errorMessage = "Saving to Health failed: \(error.localizedDescription)"
        }

        // Ship the performed sets back to the phone: history, progress charts
        // and plan write-back all happen there.
        let performed = sets.filter { $0.isDone && ($0.weightKg > 0 || $0.reps > 0) }
        if !performed.isEmpty {
            let finished = SyncFinishedWorkout(
                title: workoutTitle,
                startedAt: start,
                endedAt: end,
                sets: performed.map {
                    SyncPerformedSet(
                        exerciseName: $0.exerciseName,
                        muscleGroupRaw: $0.muscleGroupRaw,
                        exerciseOrder: $0.exerciseOrder,
                        setNumber: $0.setNumber,
                        weightKg: $0.weightKg,
                        reps: $0.reps,
                        durationSeconds: $0.durationSeconds,
                        restSeconds: $0.restSeconds
                    )
                }
            )
            WatchSyncService.shared.sendFinishedWorkout(finished)
        }

        self.session = nil
        self.builder = nil
        isRunning = false
        startDate = nil
        workoutTitle = ""
        heartRate = 0
        activeEnergy = 0
        sets = []
        currentIndex = 0
    }

    // MARK: - Set flow

    func startSet() {
        guard currentSet != nil else { return }
        setAnchor = .now
        restEndsAt = nil
        setElapsed = 0
        restRemaining = 0
        overtimeSeconds = 0
        phase = .set
        Haptics.light()
        startTicking()
    }

    func endSet() {
        guard phase == .set, let index = sets.indices.contains(currentIndex)
            ? currentIndex : nil else { return }

        if let anchor = setAnchor {
            sets[index].durationSeconds = Date.now.timeIntervalSince(anchor)
        }
        sets[index].isDone = true
        let restSeconds = sets[index].restSeconds
        setAnchor = nil
        Haptics.stageComplete()

        advanceToNextUndone()

        if allDone {
            goIdle()
        } else if restSeconds > 0 {
            restTotal = restSeconds
            restRemaining = restSeconds
            restEndsAt = Date.now.addingTimeInterval(TimeInterval(restSeconds))
            phase = .rest
            startTicking()
        } else {
            goIdle()
        }
    }

    private func advanceToNextUndone() {
        if let next = sets.indices.first(where: { $0 > currentIndex && !sets[$0].isDone }) {
            currentIndex = next
        } else if let anyUndone = sets.indices.first(where: { !sets[$0].isDone }) {
            currentIndex = anyUndone
        }
    }

    func skipRest() {
        goIdle()
    }

    private func goIdle() {
        phase = .idle
        setAnchor = nil
        restEndsAt = nil
        setElapsed = 0
        restRemaining = 0
        restTotal = 0
        overtimeSeconds = 0
    }

    // MARK: - Clock (date-anchored, same as the phone)

    private func startTicking() {
        refreshFromAnchors()
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }
                if self.phase == .idle {
                    self.tickTask = nil
                    return
                }
                self.refreshFromAnchors()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

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
                restRemaining = 0
                phase = .overtime
                refreshFromAnchors()
                Haptics.routineComplete()
            }
        case .overtime:
            overtimeSeconds = max(0, Int(-(restEndsAt?.timeIntervalSinceNow ?? 0)))
        }
    }
}

// MARK: - HealthKit delegates

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else {
                continue
            }

            let identifier = HKQuantityTypeIdentifier(rawValue: quantityType.identifier)
            switch identifier {
            case .heartRate:
                let unit = HKUnit.count().unitDivided(by: .minute())
                let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
                Task { @MainActor in self.heartRate = value }
            case .activeEnergyBurned:
                let value = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                Task { @MainActor in self.activeEnergy = value }
            default:
                break
            }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
