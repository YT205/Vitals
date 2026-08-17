import Foundation

/// Built-in exercise library: ~230 movements organized by muscle group and
/// equipment, in the spirit of the big exercise directories.
///
/// Bump `version` whenever the list changes. Seeding inserts anything whose
/// name isn't already in the store and refreshes the group/equipment of
/// non-custom entries, so existing installs pick up changes without duplicates
/// and without touching exercises you created yourself.
enum ExerciseLibrary {
    /// Increment when `definitions` changes so installed apps re-seed.
    static let version = 2

    static func starterExercises() -> [Exercise] {
        definitions.map { Exercise(name: $0.0, muscleGroup: $0.1, equipment: $0.2) }
    }

    static var definitions: [(String, MuscleGroup, Equipment)] {
        chest + back + shoulders + biceps + triceps + forearms
            + legs + glutes + calves + core + fullBody
    }

    // MARK: - Chest

    private static let chest: [(String, MuscleGroup, Equipment)] = [
        ("Barbell Bench Press", .chest, .barbell),
        ("Incline Barbell Bench Press", .chest, .barbell),
        ("Decline Barbell Bench Press", .chest, .barbell),
        ("Barbell Floor Press", .chest, .barbell),
        ("Dumbbell Bench Press", .chest, .dumbbell),
        ("Incline Dumbbell Press", .chest, .dumbbell),
        ("Decline Dumbbell Press", .chest, .dumbbell),
        ("Dumbbell Fly", .chest, .dumbbell),
        ("Incline Dumbbell Fly", .chest, .dumbbell),
        ("Dumbbell Pullover", .chest, .dumbbell),
        ("Cable Fly", .chest, .cable),
        ("Low Cable Fly", .chest, .cable),
        ("High Cable Fly", .chest, .cable),
        ("Cable Crossover", .chest, .cable),
        ("Cable Chest Press", .chest, .cable),
        ("Pec Deck", .chest, .machine),
        ("Chest Press Machine", .chest, .machine),
        ("Incline Chest Press Machine", .chest, .machine),
        ("Smith Machine Bench Press", .chest, .machine),
        ("Smith Machine Incline Press", .chest, .machine),
        ("Push-Up", .chest, .bodyweight),
        ("Weighted Push-Up", .chest, .bodyweight),
        ("Deficit Push-Up", .chest, .bodyweight),
        ("Dip", .chest, .bodyweight),
        ("Weighted Dip", .chest, .bodyweight),
        ("Assisted Dip", .chest, .machine),
        ("Svend Press", .chest, .other),
        ("Banded Push-Up", .chest, .band),
    ]

    // MARK: - Back

    private static let back: [(String, MuscleGroup, Equipment)] = [
        ("Deadlift", .back, .barbell),
        ("Sumo Deadlift", .back, .barbell),
        ("Snatch-Grip Deadlift", .back, .barbell),
        ("Deficit Deadlift", .back, .barbell),
        ("Rack Pull", .back, .barbell),
        ("Block Pull", .back, .barbell),
        ("Barbell Row", .back, .barbell),
        ("Pendlay Row", .back, .barbell),
        ("Yates Row", .back, .barbell),
        ("T-Bar Row", .back, .barbell),
        ("Meadows Row", .back, .barbell),
        ("Seal Row", .back, .barbell),
        ("Good Morning", .back, .barbell),
        ("Dumbbell Row", .back, .dumbbell),
        ("Chest-Supported Dumbbell Row", .back, .dumbbell),
        ("Renegade Row", .back, .dumbbell),
        ("Lat Pulldown", .back, .cable),
        ("Close-Grip Lat Pulldown", .back, .cable),
        ("Wide-Grip Lat Pulldown", .back, .cable),
        ("Straight-Arm Pulldown", .back, .cable),
        ("Cable Pullover", .back, .cable),
        ("Seated Cable Row", .back, .cable),
        ("Wide-Grip Cable Row", .back, .cable),
        ("Single-Arm Cable Row", .back, .cable),
        ("Face Pull", .back, .cable),
        ("Machine Row", .back, .machine),
        ("High Row Machine", .back, .machine),
        ("Smith Machine Row", .back, .machine),
        ("Assisted Pull-Up", .back, .machine),
        ("Pull-Up", .back, .bodyweight),
        ("Chin-Up", .back, .bodyweight),
        ("Neutral-Grip Pull-Up", .back, .bodyweight),
        ("Weighted Pull-Up", .back, .bodyweight),
        ("Inverted Row", .back, .bodyweight),
        ("Back Extension", .back, .bodyweight),
        ("Reverse Hyperextension", .back, .machine),
    ]

    // MARK: - Shoulders

    private static let shoulders: [(String, MuscleGroup, Equipment)] = [
        ("Overhead Press", .shoulders, .barbell),
        ("Push Press", .shoulders, .barbell),
        ("Seated Barbell Press", .shoulders, .barbell),
        ("Z Press", .shoulders, .barbell),
        ("Barbell Upright Row", .shoulders, .barbell),
        ("Barbell Shrug", .shoulders, .barbell),
        ("Landmine Press", .shoulders, .other),
        ("Seated Dumbbell Press", .shoulders, .dumbbell),
        ("Standing Dumbbell Press", .shoulders, .dumbbell),
        ("Arnold Press", .shoulders, .dumbbell),
        ("Lateral Raise", .shoulders, .dumbbell),
        ("Front Raise", .shoulders, .dumbbell),
        ("Rear Delt Fly", .shoulders, .dumbbell),
        ("Shrug", .shoulders, .dumbbell),
        ("Plate Front Raise", .shoulders, .other),
        ("Cable Lateral Raise", .shoulders, .cable),
        ("Cable Front Raise", .shoulders, .cable),
        ("Cable Rear Delt Fly", .shoulders, .cable),
        ("Cable Upright Row", .shoulders, .cable),
        ("Cable External Rotation", .shoulders, .cable),
        ("Machine Shoulder Press", .shoulders, .machine),
        ("Machine Lateral Raise", .shoulders, .machine),
        ("Reverse Pec Deck", .shoulders, .machine),
        ("Smith Machine Shoulder Press", .shoulders, .machine),
        ("Pike Push-Up", .shoulders, .bodyweight),
        ("Handstand Push-Up", .shoulders, .bodyweight),
        ("Band Pull-Apart", .shoulders, .band),
    ]

    // MARK: - Biceps

    private static let biceps: [(String, MuscleGroup, Equipment)] = [
        ("Barbell Curl", .biceps, .barbell),
        ("EZ-Bar Curl", .biceps, .barbell),
        ("Drag Curl", .biceps, .barbell),
        ("Dumbbell Curl", .biceps, .dumbbell),
        ("Hammer Curl", .biceps, .dumbbell),
        ("Incline Dumbbell Curl", .biceps, .dumbbell),
        ("Concentration Curl", .biceps, .dumbbell),
        ("Cross-Body Hammer Curl", .biceps, .dumbbell),
        ("Zottman Curl", .biceps, .dumbbell),
        ("Dumbbell Preacher Curl", .biceps, .dumbbell),
        ("Spider Curl", .biceps, .dumbbell),
        ("Preacher Curl", .biceps, .machine),
        ("Machine Curl", .biceps, .machine),
        ("Cable Curl", .biceps, .cable),
        ("Rope Hammer Curl", .biceps, .cable),
        ("Bayesian Curl", .biceps, .cable),
        ("Band Curl", .biceps, .band),
    ]

    // MARK: - Triceps

    private static let triceps: [(String, MuscleGroup, Equipment)] = [
        ("Close-Grip Bench Press", .triceps, .barbell),
        ("Skull Crusher", .triceps, .barbell),
        ("JM Press", .triceps, .barbell),
        ("Dumbbell Skull Crusher", .triceps, .dumbbell),
        ("Overhead Dumbbell Extension", .triceps, .dumbbell),
        ("Triceps Kickback", .triceps, .dumbbell),
        ("EZ-Bar Overhead Extension", .triceps, .barbell),
        ("Triceps Pushdown", .triceps, .cable),
        ("Rope Pushdown", .triceps, .cable),
        ("Single-Arm Pushdown", .triceps, .cable),
        ("Overhead Cable Extension", .triceps, .cable),
        ("Cable Triceps Kickback", .triceps, .cable),
        ("Machine Triceps Extension", .triceps, .machine),
        ("Bench Dip", .triceps, .bodyweight),
        ("Diamond Push-Up", .triceps, .bodyweight),
        ("Close-Grip Push-Up", .triceps, .bodyweight),
    ]

    // MARK: - Forearms

    private static let forearms: [(String, MuscleGroup, Equipment)] = [
        ("Wrist Curl", .forearms, .barbell),
        ("Reverse Wrist Curl", .forearms, .barbell),
        ("Behind-the-Back Wrist Curl", .forearms, .barbell),
        ("Reverse Curl", .forearms, .barbell),
        ("Dumbbell Wrist Curl", .forearms, .dumbbell),
        ("Wrist Roller", .forearms, .other),
        ("Plate Pinch", .forearms, .other),
        ("Dead Hang", .forearms, .bodyweight),
    ]

    // MARK: - Legs (quads and hamstrings)

    private static let legs: [(String, MuscleGroup, Equipment)] = [
        ("Back Squat", .legs, .barbell),
        ("Front Squat", .legs, .barbell),
        ("Box Squat", .legs, .barbell),
        ("Pause Squat", .legs, .barbell),
        ("Safety Bar Squat", .legs, .barbell),
        ("Romanian Deadlift", .legs, .barbell),
        ("Stiff-Leg Deadlift", .legs, .barbell),
        ("Trap Bar Deadlift", .legs, .other),
        ("Goblet Squat", .legs, .dumbbell),
        ("Dumbbell Romanian Deadlift", .legs, .dumbbell),
        ("Single-Leg Romanian Deadlift", .legs, .dumbbell),
        ("Bulgarian Split Squat", .legs, .dumbbell),
        ("Walking Lunge", .legs, .dumbbell),
        ("Reverse Lunge", .legs, .dumbbell),
        ("Lateral Lunge", .legs, .dumbbell),
        ("Step-Up", .legs, .dumbbell),
        ("Leg Press", .legs, .machine),
        ("Single-Leg Press", .legs, .machine),
        ("Hack Squat", .legs, .machine),
        ("Smith Machine Squat", .legs, .machine),
        ("Leg Extension", .legs, .machine),
        ("Leg Curl", .legs, .machine),
        ("Seated Leg Curl", .legs, .machine),
        ("Hip Adduction Machine", .legs, .machine),
        ("Nordic Hamstring Curl", .legs, .bodyweight),
        ("Sissy Squat", .legs, .bodyweight),
        ("Pistol Squat", .legs, .bodyweight),
        ("Wall Sit", .legs, .bodyweight),
    ]

    // MARK: - Glutes

    private static let glutes: [(String, MuscleGroup, Equipment)] = [
        ("Hip Thrust", .glutes, .barbell),
        ("Barbell Glute Bridge", .glutes, .barbell),
        ("Sumo Squat", .glutes, .dumbbell),
        ("Curtsy Lunge", .glutes, .dumbbell),
        ("Single-Leg Hip Thrust", .glutes, .bodyweight),
        ("Cable Kickback", .glutes, .cable),
        ("Cable Pull-Through", .glutes, .cable),
        ("Hip Abduction Machine", .glutes, .machine),
        ("Machine Hip Thrust", .glutes, .machine),
        ("Glute Kickback Machine", .glutes, .machine),
        ("Banded Lateral Walk", .glutes, .band),
        ("Donkey Kick", .glutes, .bodyweight),
    ]

    // MARK: - Calves

    private static let calves: [(String, MuscleGroup, Equipment)] = [
        ("Standing Calf Raise", .calves, .machine),
        ("Seated Calf Raise", .calves, .machine),
        ("Leg Press Calf Raise", .calves, .machine),
        ("Smith Machine Calf Raise", .calves, .machine),
        ("Donkey Calf Raise", .calves, .machine),
        ("Single-Leg Calf Raise", .calves, .bodyweight),
        ("Tibialis Raise", .calves, .bodyweight),
    ]

    // MARK: - Core

    private static let core: [(String, MuscleGroup, Equipment)] = [
        ("Plank", .core, .bodyweight),
        ("Side Plank", .core, .bodyweight),
        ("Weighted Plank", .core, .bodyweight),
        ("Crunch", .core, .bodyweight),
        ("Reverse Crunch", .core, .bodyweight),
        ("Bicycle Crunch", .core, .bodyweight),
        ("Sit-Up", .core, .bodyweight),
        ("Weighted Sit-Up", .core, .other),
        ("Decline Sit-Up", .core, .bodyweight),
        ("V-Up", .core, .bodyweight),
        ("Lying Leg Raise", .core, .bodyweight),
        ("Hanging Knee Raise", .core, .bodyweight),
        ("Hanging Leg Raise", .core, .bodyweight),
        ("Captain's Chair Leg Raise", .core, .machine),
        ("Cable Crunch", .core, .cable),
        ("Cable Woodchopper", .core, .cable),
        ("Pallof Press", .core, .cable),
        ("Machine Crunch", .core, .machine),
        ("Ab Wheel Rollout", .core, .other),
        ("Russian Twist", .core, .other),
        ("Dead Bug", .core, .bodyweight),
        ("Bird Dog", .core, .bodyweight),
        ("Mountain Climber", .core, .bodyweight),
        ("Hollow Body Hold", .core, .bodyweight),
        ("L-Sit", .core, .bodyweight),
        ("Dragon Flag", .core, .bodyweight),
        ("Suitcase Carry", .core, .dumbbell),
    ]

    // MARK: - Full body

    private static let fullBody: [(String, MuscleGroup, Equipment)] = [
        ("Clean and Press", .fullBody, .barbell),
        ("Power Clean", .fullBody, .barbell),
        ("Hang Clean", .fullBody, .barbell),
        ("Clean and Jerk", .fullBody, .barbell),
        ("Snatch", .fullBody, .barbell),
        ("Power Snatch", .fullBody, .barbell),
        ("Thruster", .fullBody, .barbell),
        ("Kettlebell Swing", .fullBody, .kettlebell),
        ("Kettlebell Clean and Press", .fullBody, .kettlebell),
        ("Turkish Get-Up", .fullBody, .kettlebell),
        ("Farmer's Carry", .fullBody, .dumbbell),
        ("Sled Push", .fullBody, .other),
        ("Sled Drag", .fullBody, .other),
        ("Medicine Ball Slam", .fullBody, .other),
        ("Burpee", .fullBody, .bodyweight),
    ]
}
