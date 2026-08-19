import SwiftData
import SwiftUI

/// One editable set: weight, reps, and a play/stop timing control.
///
/// Flow: tap play to start the set (in-set timer runs), tap stop when you rack
/// the weight (duration saved, rest countdown starts). A finished set shows a
/// checkmark; tap it to reset. Timing is optional -- untimed sets with data
/// still save when the workout finishes.
struct SetRowView: View {
    @Environment(AppSettings.self) private var settings

    @Bindable var entry: SetEntry
    /// `true` while this row's set timer is running.
    let isTiming: Bool
    /// Live elapsed text for the active set (from the view model's clock).
    let elapsedText: String
    let onStart: () -> Void
    let onFinish: () -> Void
    let onReset: () -> Void
    /// Opens the number pad for this row's weight / reps.
    let onEditWeight: () -> Void
    let onEditReps: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            setBadge

            // Values open the bottom number pad rather than inline keyboards.
            valueBox(
                settings.displayWeight(fromKilograms: entry.weightKg)
                    .formatted(.number.precision(.fractionLength(0...1))),
                isPlaceholder: entry.weightKg <= 0,
                action: onEditWeight
            )
            .accessibilityLabel("Weight, \(settings.formattedWeight(fromKilograms: entry.weightKg))")

            Text("x")
                .font(.caption)
                .foregroundStyle(.tertiary)

            valueBox(
                "\(entry.reps)",
                isPlaceholder: entry.reps <= 0,
                action: onEditReps
            )
            .accessibilityLabel("Reps, \(entry.reps)")

            timingControl
        }
        .opacity(entry.isDone ? 0.6 : 1)
        .listRowBackground(isTiming ? Color.accentColor.opacity(0.08) : nil)
    }

    private func valueBox(
        _ text: String,
        isPlaceholder: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(isPlaceholder ? "--" : text)
                .font(.callout)
                .foregroundStyle(isPlaceholder ? .tertiary : .primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                // A slightly lighter grey than the row, so the tappable area
                // reads as a filled field without an outline.
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var setBadge: some View {
        Text(entry.isWarmup ? "W" : "\(entry.setNumber)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(entry.isWarmup ? .orange : .secondary)
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(entry.isWarmup ? .orange.opacity(0.15) : .gray.opacity(0.15))
            )
    }

    @ViewBuilder
    private var timingControl: some View {
        if entry.isDone {
            Button {
                onReset()
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    if entry.durationSeconds > 0 {
                        Text(WorkoutSession.formatMinutesSeconds(entry.durationSeconds))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44)
            .accessibilityLabel("Set complete, tap to reset")
        } else if isTiming {
            Button {
                onFinish()
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                    Text(elapsedText)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44)
            .accessibilityLabel("Finish set")
        } else {
            Button {
                onStart()
            } label: {
                Image(systemName: "play.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .frame(width: 44)
            .accessibilityLabel("Start set")
        }
    }
}

/// Column titles above a group of set rows.
struct SetHeaderRow: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 10) {
            Text("Set")
                .frame(width: 24)
            Text(settings.weightUnit.label.uppercased())
                .frame(maxWidth: .infinity)
            Text("")
                .font(.caption)
            Text("REPS")
                .frame(maxWidth: .infinity)
            Text("")
                .frame(width: 44)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
}
