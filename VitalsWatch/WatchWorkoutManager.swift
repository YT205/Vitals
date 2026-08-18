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

    /// Live metrics from the workout builder.
    private(set) var heartRate: Double = 0
    private(set) var activeEnergy: Double = 0

    /// Set/rest dial, same phases as the phone.
    enum Phase: Equatable { case idle, set, rest, overtime }
    private(set) var phase: Phase = .idle
    private(set) var setCount = 0
    private(set) var setElapsed = 0
    private(set) var restRemaining = 0
    private(set) var restTotal = 0
    private(set) var overtimeSeconds = 0

    /// Rest applied after each set. Adjustable from the controls page.
    var restSeconds = 90

    var errorMessage: String?

    private var setAnchor: Date?
    private var restEndsAt: Date?
    private var tickTask: Task<Void, Never>?

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
        case .set: "Set \(setCount + 1)"
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

    func startWorkout() async {
        guard !isRunning else { return }
        errorMessage = nil

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

            startDate = start
            isRunning = true
            setCount = 0
            phase = .idle
        } catch {
            errorMessage = "Couldn't start the workout: \(error.localizedDescription)"
        }
    }

    func endWorkout() async {
        guard let session, let builder else { return }
        goIdle()
        stopTicking()

        let end = Date.now
        session.end()
        do {
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch {
            errorMessage = "Saving to Health failed: \(error.localizedDescription)"
        }

        self.session = nil
        self.builder = nil
        isRunning = false
        startDate = nil
        heartRate = 0
        activeEnergy = 0
        setCount = 0
    }

    // MARK: - Set flow

    func startSet() {
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
        guard phase == .set else { return }
        setCount += 1
        setAnchor = nil
        Haptics.stageComplete()

        if restSeconds > 0 {
            restTotal = restSeconds
            restRemaining = restSeconds
            restEndsAt = Date.now.addingTimeInterval(TimeInterval(restSeconds))
            phase = .rest
            startTicking()
        } else {
            goIdle()
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
