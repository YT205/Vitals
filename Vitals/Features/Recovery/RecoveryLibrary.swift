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
        targetGroups: [MuscleGroup] = [],
        steps: [(String, Int, Bool, String)]
    ) -> RecoveryRoutine {
        let routine = RecoveryRoutine(
            name: name,
            kind: kind,
            notes: notes,
            targetGroups: targetGroups
        )
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

    // MARK: - Per-muscle step bank

    /// Stretch steps for one muscle group. Used by the routine generator and
    /// as the vocabulary for anything recovery-related you want to add later.
    static func stretchSteps(for group: MuscleGroup) -> [(String, Int, Bool, String)] {
        switch group {
        case .chest:
            [
                ("Doorway Chest Stretch", 45, true, "Forearm on the frame at 90 degrees, step through."),
                ("Floor Chest Opener", 40, true, "Lie prone, arm out at 90, roll gently away."),
            ]
        case .back:
            [
                ("Lat Stretch on Rack", 40, true, "Grab a post, hinge back, let the lat lengthen."),
                ("Child's Pose", 60, false, "Knees wide, arms long, breathe into the low back."),
                ("Thread the Needle", 45, true, "From all fours, reach one arm under the other."),
            ]
        case .shoulders:
            [
                ("Cross-Body Shoulder Stretch", 30, true, "Pull the arm across at chest height."),
                ("Sleeper Stretch", 40, true, "Side lying, rotate the forearm toward the floor."),
                ("Wall Angel", 40, false, "Back flat to the wall, slide arms overhead slowly."),
            ]
        case .biceps:
            [
                ("Wall Biceps Stretch", 30, true, "Palm on the wall behind you, arm straight, turn away."),
            ]
        case .triceps:
            [
                ("Overhead Triceps Stretch", 30, true, "Elbow up, hand down the spine, gentle pull."),
            ]
        case .forearms:
            [
                ("Wrist Flexor Stretch", 30, true, "Arm straight, palm up, pull fingers back gently."),
                ("Wrist Extensor Stretch", 30, true, "Arm straight, palm down, press the back of the hand."),
            ]
        case .legs:
            [
                ("Standing Quad Stretch", 40, true, "Heel to glute, knees together, push hips forward."),
                ("Couch Stretch", 60, true, "Rear foot elevated against a wall. Squeeze the glute."),
                ("Seated Hamstring Stretch", 45, true, "Hinge from the hip, keep the spine long."),
            ]
        case .glutes:
            [
                ("Figure-4 Glute Stretch", 45, true, "On your back, ankle across the opposite knee."),
                ("Pigeon Pose", 60, true, "Shin parallel to the front edge of the mat."),
            ]
        case .calves:
            [
                ("Calf Stretch on Wall", 40, true, "Back leg straight, heel driving down."),
                ("Soleus Stretch", 30, true, "Same position, back knee bent."),
            ]
        case .core:
            [
                ("Cobra Stretch", 40, false, "Press the hips down, lift the chest, long exhale."),
                ("Supine Twist", 45, true, "Knees to one side, shoulders flat, look the other way."),
            ]
        case .fullBody, .other:
            [
                ("World's Greatest Stretch", 45, true, "Deep lunge, elbow to instep, then rotate up."),
                ("Standing Forward Fold", 45, false, "Soft knees, hang heavy, sway gently."),
            ]
        }
    }

    /// Massage gun steps for one muscle group.
    static func massageSteps(for group: MuscleGroup) -> [(String, Int, Bool, String)] {
        switch group {
        case .chest:
            [("Pecs", 45, true, "Just below the collarbone, out toward the shoulder.")]
        case .back:
            [
                ("Lats", 60, true, "Arm overhead, work the side of the ribcage."),
                ("Upper Traps", 45, true, "Light pressure. Stay off the spine and neck."),
            ]
        case .shoulders:
            [("Delts", 40, true, "Small circles on the muscle belly only.")]
        case .biceps:
            [("Biceps", 30, true, "Elbow to shoulder along the front of the arm.")]
        case .triceps:
            [("Triceps", 45, true, "Elbow to shoulder along the back of the arm.")]
        case .forearms:
            [("Forearms", 30, true, "Both sides, light pressure.")]
        case .legs:
            [
                ("Quads", 60, true, "Sweep hip to knee. Slow passes, muscle relaxed."),
                ("Hamstrings", 60, true, "Sit with the leg extended, work glute to knee."),
            ]
        case .glutes:
            [("Glutes", 60, true, "Cross the ankle over the opposite knee to expose the muscle.")]
        case .calves:
            [("Calves", 60, true, "Ankle to just below the knee. Avoid the Achilles.")]
        case .core:
            []  // No massage gun on the abdomen.
        case .fullBody, .other:
            [
                ("Quads", 45, true, "Sweep hip to knee, light pressure."),
                ("Upper Back", 45, true, "Between shoulder blade and spine, not on bone."),
            ]
        }
    }

    /// Builds a stretch + massage routine covering the given muscle groups,
    /// used by "Create Recovery Routine" in the workout editor.
    static func generatedRoutine(
        named name: String,
        for groups: [MuscleGroup]
    ) -> RecoveryRoutine {
        // Preserve a stable, sensible order and drop duplicates.
        let ordered = MuscleGroup.allCases.filter { groups.contains($0) }

        var steps: [(String, Int, Bool, String)] = []
        var seen = Set<String>()
        for group in ordered {
            for step in stretchSteps(for: group) where !seen.contains(step.0) {
                seen.insert(step.0)
                steps.append(step)
            }
        }
        for group in ordered {
            for step in massageSteps(for: group) where !seen.contains(step.0) {
                seen.insert(step.0)
                steps.append(step)
            }
        }

        return build(
            name: name,
            kind: .stretching,
            notes: "Generated from your workout. Edit steps freely -- it won't regenerate on its own.",
            targetGroups: ordered,
            steps: steps
        )
    }

    // MARK: - Stretching

    static func postLowerBodyStretch() -> RecoveryRoutine {
        build(
            name: "Post Leg Day Stretch",
            kind: .stretching,
            notes: "Run this within 30 minutes of finishing lower body work.",
            targetGroups: [.legs, .glutes, .calves],
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
            targetGroups: [.chest, .shoulders, .triceps],
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
            targetGroups: [.legs, .glutes, .calves],
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
            targetGroups: [.chest, .back, .shoulders, .biceps, .triceps],
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
