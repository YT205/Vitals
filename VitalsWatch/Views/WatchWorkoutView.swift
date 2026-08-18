import SwiftUI

/// The workout page. Idle: a start button. Running: live metrics, the set/rest
/// dial, and set controls, split across horizontal pages watchOS-style.
struct WatchWorkoutView: View {
    private var manager: WatchWorkoutManager { .shared }

    var body: some View {
        if manager.isRunning {
            ActiveWorkoutPages()
        } else {
            startScreen
        }
    }

    private var startScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "dumbbell.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            Text("Strength Workout")
                .font(.headline)

            Text("Live heart rate and calories, with the set and rest dial on your wrist.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task { await manager.startWorkout() }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Metrics page and controls page, side by side like the Workout app.
private struct ActiveWorkoutPages: View {
    private var manager: WatchWorkoutManager { .shared }

    var body: some View {
        TabView {
            metricsPage
            controlsPage
        }
        .tabViewStyle(.page)
    }

    // MARK: - Metrics

    private var metricsPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(manager.elapsedText)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
            }

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(manager.heartRate > 0 ? "\(Int(manager.heartRate.rounded()))" : "--")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(Int(manager.activeEnergy.rounded()))")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text("KCAL")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("\(manager.setCount)")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                Text("SETS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    // MARK: - Controls

    private var controlsPage: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(
                    progress: manager.dialProgress,
                    lineWidth: 6,
                    tint: manager.dialTint
                )
                .frame(width: 74, height: 74)

                VStack(spacing: 0) {
                    Text(manager.dialText)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(manager.phase == .overtime ? .orange : .primary)
                    Text(manager.dialCaption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            switch manager.phase {
            case .idle:
                Button {
                    manager.startSet()
                } label: {
                    Label("Start Set", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            case .set:
                Button {
                    manager.endSet()
                } label: {
                    Label("End Set", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            case .rest, .overtime:
                HStack(spacing: 6) {
                    Button("Skip") { manager.skipRest() }
                        .buttonStyle(.bordered)
                    Button {
                        manager.startSet()
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button(role: .destructive) {
                Task { await manager.endWorkout() }
            } label: {
                Label("End Workout", systemImage: "xmark")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 6)
    }
}
