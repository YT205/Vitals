import Foundation
import SwiftData
import SwiftUI

enum RecoveryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case stretching
    case massageGun
    case foamRoll
    case mobility
    case breathing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stretching: "Stretching"
        case .massageGun: "Massage Gun"
        case .foamRoll: "Foam Roll"
        case .mobility: "Mobility"
        case .breathing: "Breathing"
        }
    }

    var systemImage: String {
        switch self {
        case .stretching: "figure.flexibility"
        case .massageGun: "waveform.badge.magnifyingglass"
        case .foamRoll: "cylinder.split.1x2"
        case .mobility: "figure.cooldown"
        case .breathing: "wind"
        }
    }

    var tint: Color {
        switch self {
        case .stretching: .teal
        case .massageGun: .purple
        case .foamRoll: .orange
        case .mobility: .green
        case .breathing: .blue
        }
    }
}

/// A saved recovery sequence: stretches, massage gun passes, foam rolling.
@Model
final class RecoveryRoutine {
    var name: String = ""
    var kind: RecoveryKind = RecoveryKind.stretching
    var notes: String = ""
    var createdAt: Date = Date.now
    var lastPerformedAt: Date?
    /// How many times you've completed this routine.
    var completionCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RecoveryStep.routine)
    var steps: [RecoveryStep] = []

    init(name: String, kind: RecoveryKind = .stretching, notes: String = "") {
        self.name = name
        self.kind = kind
        self.notes = notes
        self.createdAt = .now
    }

    var orderedSteps: [RecoveryStep] {
        steps.sorted { $0.order < $1.order }
    }

    /// Total routine length in seconds, including per-side repeats.
    var totalSeconds: Int {
        steps.reduce(0) { $0 + $1.totalSeconds }
    }

    var formattedDuration: String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "\(seconds)s" }
        if seconds == 0 { return "\(minutes) min" }
        return "\(minutes)m \(seconds)s"
    }

    func markCompleted() {
        lastPerformedAt = .now
        completionCount += 1
    }
}

/// One timed step within a routine.
@Model
final class RecoveryStep {
    var name: String = ""
    /// Hold time per side, in seconds.
    var seconds: Int = 30
    var instructions: String = ""
    /// When `true` the player runs the timer twice, once per side.
    var isPerSide: Bool = false
    var order: Int = 0

    var routine: RecoveryRoutine?

    init(
        name: String,
        seconds: Int = 30,
        instructions: String = "",
        isPerSide: Bool = false,
        order: Int = 0
    ) {
        self.name = name
        self.seconds = seconds
        self.instructions = instructions
        self.isPerSide = isPerSide
        self.order = order
    }

    var totalSeconds: Int { isPerSide ? seconds * 2 : seconds }
}
