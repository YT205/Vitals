import Foundation
import SwiftData

/// One performed workout. Created when you tap Start and finished when you tap
/// Finish, at which point a matching `HKWorkout` is written to Apple Health.
@Model
final class WorkoutSession {
    var title: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    var notes: String = ""
    /// `true` once the session has been mirrored into HealthKit.
    var savedToHealthKit: Bool = false
    /// Apple Health workout effort, 1...10. `nil` when skipped.
    /// 1-3 Easy, 4-6 Moderate, 7-8 Hard, 9-10 All Out.
    var effortScore: Int?

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    var sets: [SetEntry] = []

    init(title: String, startedAt: Date = .now) {
        self.title = title
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    /// Sets grouped by exercise, preserving the order they were added.
    var orderedSets: [SetEntry] {
        sets.sorted {
            if $0.exerciseOrder != $1.exerciseOrder {
                return $0.exerciseOrder < $1.exerciseOrder
            }
            return $0.setNumber < $1.setNumber
        }
    }

    var exerciseNames: [String] {
        var seen = Set<String>()
        return orderedSets.compactMap { entry in
            guard !seen.contains(entry.exerciseName) else { return nil }
            seen.insert(entry.exerciseName)
            return entry.exerciseName
        }
    }

    var completedSets: [SetEntry] {
        sets.filter { $0.isDone && !$0.isWarmup }
    }

    /// Sum of weight x reps across completed working sets, in kilograms.
    var totalVolumeKg: Double {
        completedSets.reduce(0) { $0 + $1.volumeKg }
    }

    var totalReps: Int {
        completedSets.reduce(0) { $0 + $1.reps }
    }

    /// Total seconds spent actually lifting (sum of timed set durations).
    var totalSetSeconds: Double {
        sets.reduce(0) { $0 + $1.durationSeconds }
    }

    var formattedSetTime: String {
        Self.formatMinutesSeconds(totalSetSeconds)
    }

    static func formatMinutesSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let hours = minutes / 60
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
