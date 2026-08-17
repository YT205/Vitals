import SwiftData
import SwiftUI

/// One editable set: weight, reps, and a done toggle.
struct SetRowView: View {
    @Environment(AppSettings.self) private var settings

    @Bindable var entry: SetEntry
    /// Called when the set flips from not-done to done, so the caller can kick
    /// off the rest timer.
    let onComplete: () -> Void

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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.background.secondary, in: .rect(cornerRadius: 8))

            Text("x")
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField("0", value: $entry.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(.background.secondary, in: .rect(cornerRadius: 8))

            doneButton
        }
        .opacity(entry.isDone ? 0.6 : 1)
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

    private var doneButton: some View {
        Button {
            if entry.isDone {
                entry.markNotDone()
            } else {
                entry.markDone()
                onComplete()
            }
        } label: {
            Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(entry.isDone ? .green : .secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 30)
        .accessibilityLabel(entry.isDone ? "Mark set incomplete" : "Mark set complete")
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
                .frame(width: 30)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
}
