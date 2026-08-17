import Foundation
import Observation
import UIKit

/// Drives the guided, timed run-through of a recovery routine.
///
/// Steps marked "per side" are flattened into two stages so the player can say
/// Left, then Right, without special-casing anything in the view.
@MainActor
@Observable
final class RoutinePlayerViewModel {
    struct Stage: Identifiable, Equatable {
        let id = UUID()
        let stepName: String
        let instructions: String
        let seconds: Int
        /// "Left" / "Right" for per-side steps, `nil` otherwise.
        let sideLabel: String?

        var title: String {
            guard let sideLabel else { return stepName }
            return "\(stepName) · \(sideLabel)"
        }
    }

    private(set) var stages: [Stage] = []
    private(set) var index = 0
    private(set) var remaining = 0
    private(set) var isRunning = false
    private(set) var isFinished = false

    private var task: Task<Void, Never>?

    // No deinit: `deinit` is nonisolated and can't touch main-actor state. It
    // isn't needed anyway -- the countdown loop captures `self` weakly and bails
    // out on the next tick once this object is gone. `RoutinePlayerView` also
    // calls `pause()` in `onDisappear`, which cancels it immediately.

    // MARK: - Derived state

    var currentStage: Stage? {
        stages.indices.contains(index) ? stages[index] : nil
    }

    var nextStage: Stage? {
        stages.indices.contains(index + 1) ? stages[index + 1] : nil
    }

    var stageProgress: Double {
        guard let currentStage, currentStage.seconds > 0 else { return 0 }
        return Double(currentStage.seconds - remaining) / Double(currentStage.seconds)
    }

    var overallProgress: Double {
        guard !stages.isEmpty else { return 0 }
        return Double(index) / Double(stages.count)
    }

    var formattedRemaining: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var stageCountLabel: String {
        guard !stages.isEmpty else { return "" }
        return "Step \(min(index + 1, stages.count)) of \(stages.count)"
    }

    // MARK: - Lifecycle

    func load(_ routine: RecoveryRoutine) {
        stages = routine.orderedSteps.flatMap { step -> [Stage] in
            guard step.isPerSide else {
                return [
                    Stage(
                        stepName: step.name,
                        instructions: step.instructions,
                        seconds: step.seconds,
                        sideLabel: nil
                    )
                ]
            }
            return ["Left", "Right"].map { side in
                Stage(
                    stepName: step.name,
                    instructions: step.instructions,
                    seconds: step.seconds,
                    sideLabel: side
                )
            }
        }
        index = 0
        remaining = stages.first?.seconds ?? 0
        isFinished = stages.isEmpty
        isRunning = false
    }

    func start() {
        guard !stages.isEmpty, !isFinished else { return }
        isRunning = true
        tick()
    }

    func pause() {
        isRunning = false
        task?.cancel()
        task = nil
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func skip() {
        advance(playHaptic: false)
    }

    func previous() {
        pause()
        guard index > 0 else {
            remaining = currentStage?.seconds ?? 0
            return
        }
        index -= 1
        remaining = currentStage?.seconds ?? 0
        isFinished = false
    }

    func reset() {
        pause()
        index = 0
        remaining = stages.first?.seconds ?? 0
        isFinished = stages.isEmpty
    }

    // MARK: - Internals

    private func tick() {
        task?.cancel()
        task = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self, self.isRunning else { return }

                if self.remaining > 1 {
                    self.remaining -= 1
                } else {
                    self.advance(playHaptic: true)
                    return
                }
            }
        }
    }

    private func advance(playHaptic: Bool) {
        task?.cancel()
        task = nil

        if playHaptic { Haptics.stageComplete() }

        guard index + 1 < stages.count else {
            index = stages.count
            remaining = 0
            isRunning = false
            isFinished = true
            if playHaptic { Haptics.routineComplete() }
            return
        }

        index += 1
        remaining = stages[index].seconds

        if isRunning { tick() }
    }
}

/// Small wrapper so haptics stay in one place.
enum Haptics {
    @MainActor
    static func stageComplete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    static func routineComplete() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
