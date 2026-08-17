import Foundation

/// Starter recovery routines, inserted on first launch.
///
/// These are ordinary records once created, so edit or delete them in the app.
/// Add your own presets here if you'd rather start from a different set.
enum RecoveryLibrary {
    static func starterRoutines() -> [RecoveryRoutine] {
        [
            postLowerBodyStretch(),
            postUpperBodyStretch(),
            massageGunLowerBody(),
            massageGunUpperBody(),
            windDownBreathing(),
        ]
    }

    private static func build(
        name: String,
        kind: RecoveryKind,
        notes: String,
        steps: [(String, Int, Bool, String)]
    ) -> RecoveryRoutine {
        let routine = RecoveryRoutine(name: name, kind: kind, notes: notes)
        routine.steps = steps.enumerated().map { index, step in
            RecoveryStep(
                name: step.0,
                seconds: step.1,
                instructions: step.3,
                isPerSide: step.2,
                order: index
            )
        }
        return routine
    }

    // MARK: - Stretching

    static func postLowerBodyStretch() -> RecoveryRoutine {
        build(
            name: "Post Leg Day Stretch",
            kind: .stretching,
            notes: "Run this within 30 minutes of finishing lower body work.",
            steps: [
                ("Standing Quad Stretch", 40, true, "Heel to glute, knees together, push hips forward."),
                ("Couch Stretch", 60, true, "Rear foot elevated against a wall. Squeeze the glute."),
                ("Seated Hamstring Stretch", 45, true, "Hinge from the hip, keep the spine long."),
                ("Figure-4 Glute Stretch", 45, true, "On your back, ankle across the opposite knee."),
                ("Pigeon Pose", 60, true, "Shin parallel to the front edge of the mat."),
                ("Calf Stretch on Wall", 40, true, "Back leg straight, heel driving down."),
                ("Butterfly Stretch", 45, false, "Soles together, let the knees fall open."),
                ("Child's Pose", 60, false, "Knees wide, arms long, breathe into the low back."),
            ]
        )
    }

    static func postUpperBodyStretch() -> RecoveryRoutine {
        build(
            name: "Post Push Day Stretch",
            kind: .stretching,
            notes: "Chest, shoulders and triceps after pressing.",
            steps: [
                ("Doorway Chest Stretch", 45, true, "Forearm on the frame at 90 degrees, step through."),
                ("Overhead Triceps Stretch", 30, true, "Elbow up, hand down the spine, gentle pull."),
                ("Cross-Body Shoulder Stretch", 30, true, "Pull the arm across at chest height."),
                ("Sleeper Stretch", 40, true, "Side lying, rotate the forearm toward the floor."),
                ("Thread the Needle", 45, true, "From all fours, reach one arm under the other."),
                ("Thoracic Extension on Foam Roller", 60, false, "Roller under the mid back, support the head."),
                ("Wall Angel", 40, false, "Back flat to the wall, slide arms overhead slowly."),
            ]
        )
    }

    // MARK: - Massage gun

    static func massageGunLowerBody() -> RecoveryRoutine {
        build(
            name: "Massage Gun: Lower Body",
            kind: .massageGun,
            notes: "Medium speed. Float the head, never press into bone or joints.",
            steps: [
                ("Quads", 60, true, "Sweep hip to knee. Slow passes, keep the muscle relaxed."),
                ("IT Band / Lateral Quad", 45, true, "Light pressure only along the outer thigh."),
                ("Hamstrings", 60, true, "Sit with the leg extended, work glute to knee."),
                ("Glutes", 60, true, "Cross the ankle over the opposite knee to expose the muscle."),
                ("Calves", 60, true, "Ankle to just below the knee. Avoid the Achilles."),
                ("Plantar Foot", 30, true, "Soft head, gentle pressure through the arch."),
                ("Adductors", 45, true, "Inner thigh, stay clear of the groin."),
            ]
        )
    }

    static func massageGunUpperBody() -> RecoveryRoutine {
        build(
            name: "Massage Gun: Upper Body",
            kind: .massageGun,
            notes: "Low to medium speed. Skip the neck and anything bony.",
            steps: [
                ("Pecs", 45, true, "Just below the collarbone, out toward the shoulder."),
                ("Front Delts", 30, true, "Small circles on the muscle belly only."),
                ("Lats", 60, true, "Arm overhead, work the side of the ribcage."),
                ("Upper Traps", 45, true, "Light pressure. Stay off the spine and neck."),
                ("Rhomboids", 45, true, "Between the shoulder blade and spine, not on the blade."),
                ("Triceps", 45, true, "Elbow to shoulder along the back of the arm."),
                ("Forearms", 30, true, "Both sides, light pressure."),
            ]
        )
    }

    // MARK: - Breathing

    static func windDownBreathing() -> RecoveryRoutine {
        build(
            name: "Wind Down",
            kind: .breathing,
            notes: "Parasympathetic reset. Good right before bed or after a hard session.",
            steps: [
                ("Box Breathing", 120, false, "In 4, hold 4, out 4, hold 4."),
                ("Physiological Sigh", 60, false, "Double inhale through the nose, long slow exhale."),
                ("Extended Exhale", 120, false, "In for 4, out for 8. Let the shoulders drop."),
                ("Legs Up the Wall", 180, false, "Hips near the wall, legs vertical, arms relaxed."),
            ]
        )
    }
}
