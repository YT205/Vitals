import Foundation

/// Starter exercise library, inserted on first launch.
///
/// Edit this list freely -- it only runs when the store is empty. Once the app has
/// data, add exercises from the picker instead so you don't lose your own.
enum ExerciseLibrary {
    static func starterExercises() -> [Exercise] {
        definitions.map { Exercise(name: $0.0, muscleGroup: $0.1, equipment: $0.2) }
    }

    private static let definitions: [(String, MuscleGroup, Equipment)] = [
        // Chest
        ("Barbell Bench Press", .chest, .barbell),
        ("Incline Barbell Bench Press", .chest, .barbell),
        ("Dumbbell Bench Press", .chest, .dumbbell),
        ("Incline Dumbbell Press", .chest, .dumbbell),
        ("Cable Fly", .chest, .cable),
        ("Chest Press Machine", .chest, .machine),
        ("Push-Up", .chest, .bodyweight),
        ("Dip", .chest, .bodyweight),

        // Back
        ("Deadlift", .back, .barbell),
        ("Barbell Row", .back, .barbell),
        ("Pendlay Row", .back, .barbell),
        ("Dumbbell Row", .back, .dumbbell),
        ("Lat Pulldown", .back, .cable),
        ("Seated Cable Row", .back, .cable),
        ("Pull-Up", .back, .bodyweight),
        ("Chin-Up", .back, .bodyweight),
        ("Face Pull", .back, .cable),

        // Shoulders
        ("Overhead Press", .shoulders, .barbell),
        ("Seated Dumbbell Press", .shoulders, .dumbbell),
        ("Arnold Press", .shoulders, .dumbbell),
        ("Lateral Raise", .shoulders, .dumbbell),
        ("Cable Lateral Raise", .shoulders, .cable),
        ("Rear Delt Fly", .shoulders, .dumbbell),
        ("Shrug", .shoulders, .dumbbell),

        // Arms
        ("Barbell Curl", .biceps, .barbell),
        ("Dumbbell Curl", .biceps, .dumbbell),
        ("Hammer Curl", .biceps, .dumbbell),
        ("Incline Dumbbell Curl", .biceps, .dumbbell),
        ("Preacher Curl", .biceps, .machine),
        ("Cable Curl", .biceps, .cable),
        ("Close-Grip Bench Press", .triceps, .barbell),
        ("Skull Crusher", .triceps, .barbell),
        ("Triceps Pushdown", .triceps, .cable),
        ("Overhead Cable Extension", .triceps, .cable),
        ("Triceps Kickback", .triceps, .dumbbell),

        // Legs
        ("Back Squat", .legs, .barbell),
        ("Front Squat", .legs, .barbell),
        ("Romanian Deadlift", .legs, .barbell),
        ("Leg Press", .legs, .machine),
        ("Bulgarian Split Squat", .legs, .dumbbell),
        ("Walking Lunge", .legs, .dumbbell),
        ("Leg Extension", .legs, .machine),
        ("Leg Curl", .legs, .machine),
        ("Standing Calf Raise", .legs, .machine),
        ("Seated Calf Raise", .legs, .machine),
        ("Hip Thrust", .glutes, .barbell),
        ("Cable Kickback", .glutes, .cable),
        ("Hip Abduction Machine", .glutes, .machine),

        // Core
        ("Plank", .core, .bodyweight),
        ("Hanging Leg Raise", .core, .bodyweight),
        ("Cable Crunch", .core, .cable),
        ("Ab Wheel Rollout", .core, .other),
        ("Russian Twist", .core, .other),

        // Full body
        ("Clean and Press", .fullBody, .barbell),
        ("Kettlebell Swing", .fullBody, .kettlebell),
        ("Farmer's Carry", .fullBody, .dumbbell),
    ]
}
