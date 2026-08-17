import SwiftData
import SwiftUI
import UIKit

/// Guided run-through of a routine, one timed stage at a time.
struct RoutinePlayerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let routine: RecoveryRoutine

    @State private var model = RoutinePlayerViewModel()

    var body: some View {
        VStack(spacing: 24) {
            if model.isFinished {
                finishedState
            } else {
                activeState
            }
        }
        .padding()
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { model.reset() }
                    .disabled(model.index == 0 && !model.isFinished)
            }
        }
        .onAppear {
            model.load(routine)
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.pause()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Active

    private var activeState: some View {
        VStack(spacing: 24) {
            Text(model.stageCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            ProgressRing(
                progress: model.stageProgress,
                lineWidth: 16,
                tint: routine.kind.tint
            ) {
                VStack(spacing: 2) {
                    Text(model.formattedRemaining)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if let side = model.currentStage?.sideLabel {
                        Text(side.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(routine.kind.tint)
                    }
                }
            }
            .frame(width: 240, height: 240)

            VStack(spacing: 8) {
                Text(model.currentStage?.stepName ?? "")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let instructions = model.currentStage?.instructions,
                   !instructions.isEmpty {
                    Text(instructions)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            if let next = model.nextStage {
                Text("Next: \(next.title)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            controls
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                model.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .clipShape(.circle)
            .disabled(model.index == 0)

            Button {
                Haptics.light()
                model.toggle()
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .frame(width: 84, height: 84)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.circle)

            Button {
                model.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.bordered)
            .clipShape(.circle)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Finished

    private var finishedState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Routine complete")
                    .font(.title2.weight(.semibold))
                Text("\(routine.name) · \(routine.formattedDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    routine.markCompleted()
                    try? context.save()
                    dismiss()
                } label: {
                    Text("Log and Finish")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Run Again") { model.reset() }
            }
        }
    }
}
