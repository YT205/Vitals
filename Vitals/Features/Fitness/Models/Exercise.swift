import Foundation
import SwiftData

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case legs
    case glutes
    case core
    case fullBody
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .legs: "Legs"
        case .glutes: "Glutes"
        case .core: "Core"
        case .fullBody: "Full Body"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .chest: "figure.arms.open"
        case .back: "figure.stand"
        case .shoulders: "figure.boxing"
        case .biceps, .triceps: "figure.strengthtraining.functional"
        case .legs, .glutes: "figure.step.training"
        case .core: "figure.core.training"
        case .fullBody: "figure.mixed.cardio"
        case .other: "dumbbell"
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case band
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .other: "Other"
        }
    }
}

/// A movement you can put in a workout. Seeded with a starter library on first
/// launch; you can add your own from the exercise picker.
@Model
final class Exercise {
    var name: String = ""
    var muscleGroup: MuscleGroup = MuscleGroup.other
    var equipment: Equipment = Equipment.other
    /// `true` for exercises you created, so they can be edited or deleted.
    var isCustom: Bool = false
    var createdAt: Date = Date.now

    init(
        name: String,
        muscleGroup: MuscleGroup = .other,
        equipment: Equipment = .other,
        isCustom: Bool = false
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.isCustom = isCustom
        self.createdAt = .now
    }
}
