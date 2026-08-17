import SwiftUI

/// What the user chose on the finish sheet. Handled by `ActiveWorkoutView`
/// *after* the sheet dismisses, so dismissal and deletion never overlap.
enum FinishAction {
    case save(effortScore: Int?)
    case discard
}

/// Shown when you tap Finish. Logs effort on the same 1-10 scale as the
/// Workout app, and offers discard only when the session was under 10 minutes.
struct FinishWorkoutSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let session: WorkoutSession
    let onAction: (FinishAction) -> Void

    @State private var logEffort = true
    @State private var effort: Double = 5

    /// Under 10 minutes: probably a false start, so offer to throw it away.
    private var isShortWorkout: Bool {
        session.duration < 10 * 60
    }

    private var effortBand: (label: String, color: Color) {
        switch Int(effort) {
        case 1...3: ("Easy", .green)
        case 4...6: ("Moderate", .yellow)
        case 7...8: ("Hard", .orange)
        default: ("All Out", .red)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .top) {
                        StatBlock(value: session.formattedDuration, caption: "Duration")
                        StatBlock(
                            value: settings.formattedWeight(fromKilograms: session.totalVolumeKg),
                            caption: "Volume"
                        )
                        StatBlock(value: "\(session.sets.count)", caption: "Sets")
                    }
                } footer: {
                    Text("Every set with a weight or reps entered is saved, checked off or not.")
                }

                Section {
                    Toggle("Log effort", isOn: $logEffort.animation())

                    if logEffort {
                        VStack(spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(Int(effort))")
                                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                                    .contentTransition(.numericText())
                                    .foregroundStyle(effortBand.color)
                                Text(effortBand.label)
                                    .font(.headline)
                                    .foregroundStyle(effortBand.color)
                                Spacer()
                            }

                            Slider(value: $effort, in: 1...10, step: 1)
                                .tint(effortBand.color)

                            HStack {
                                Text("Easy")
                                Spacer()
                                Text("Moderate")
                                Spacer()
                                Text("Hard")
                                Spacer()
                                Text("All Out")
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Effort")
                } footer: {
                    Text("Saved to Apple Health as your workout effort, same as rating it in the Workout app.")
                }

                Section {
                    Button {
                        onAction(.save(effortScore: logEffort ? Int(effort) : nil))
                        dismiss()
                    } label: {
                        Text("Save Workout")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                }

                if isShortWorkout {
                    Section {
                        Button(role: .destructive) {
                            onAction(.discard)
                            dismiss()
                        } label: {
                            Text("Discard Workout")
                                .frame(maxWidth: .infinity)
                        }
                    } footer: {
                        Text("Under 10 minutes. If this was a false start, discarding deletes it entirely -- nothing is written to history or Apple Health.")
                    }
                }
            }
            .navigationTitle("Finish Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Going") { dismiss() }
                }
            }
            .interactiveDismissDisabled(false)
        }
        .presentationDetents([.medium, .large])
    }
}
