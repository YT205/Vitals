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

    private var weightBinding: Binding<Double> {
        Binding(
            get: { settings.displayWeight(fromKilograms: entry.weightKg) },
            set: { entry.weightKg = settings.kilograms(fromDisplayWeight: $0) }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            setBadge

            TextField("0", value: weightBinding, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.background.secondary, in: .rect(cornerRadius: 7))

            Text("x")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField("0", value: $entry.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.callout)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.background.secondary, in: .rect(cornerRadius: 7))

            timingControl
        }
        .opacity(entry.isDone ? 0.6 : 1)
        .listRowBackground(isTiming ? Color.accentColor.opacity(0.08) : nil)
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
