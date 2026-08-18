import SwiftData
import SwiftUI

/// Recovery page: the routine library (watch-local, seeded with the same
/// starters as the phone) driving a compact guided player.
struct WatchRecoveryView: View {
    @Query(sort: \RecoveryRoutine.name)
    private var routines: [RecoveryRoutine]

    var body: some View {
        NavigationStack {
            List {
                ForEach(routines) { routine in
                    NavigationLink {
                        WatchRoutinePlayerView(routine: routine)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(2)
                            Label(routine.formattedDuration, systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Recovery")
        }
    }
}

/// The guided player, wrist-sized: ring, step name, controls. Reuses the
/// phone's RoutinePlayerViewModel -- haptics are platform-routed already.
struct WatchRoutinePlayerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let routine: RecoveryRoutine

    @State private var model = RoutinePlayerViewModel()

    var body: some View {
        Group {
            if model.isFinished {
                finished
            } else {
                active
            }
        }
        .navigationTitle(routine.name)
        .onAppear { model.load(routine) }
        .onDisappear { model.pause() }
    }

    private var active: some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(
                    progress: model.stageProgress,
                    lineWidth: 6,
                    tint: routine.kind.tint
                )
                .frame(width: 70, height: 70)

                VStack(spacing: 0) {
                    Text(model.formattedRemaining)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    if let side = model.currentStage?.sideLabel {
                        Text(side)
                            .font(.system(size: 9).weight(.bold))
                            .foregroundStyle(routine.kind.tint)
                    }
                }
            }

            Text(model.currentStage?.stepName ?? "")
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 6) {
                Button {
                    model.previous()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.bordered)
                .disabled(model.index == 0)

                Button {
                    model.toggle()
                } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    model.skip()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 4)
    }

    private var finished: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("Complete")
                .font(.headline)

            Button("Log and Finish") {
                routine.markCompleted()
                try? context.save()
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Button("Run Again") { model.reset() }
                .buttonStyle(.bordered)
        }
    }
}
