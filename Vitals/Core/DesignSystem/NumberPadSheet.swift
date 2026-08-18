import SwiftUI

/// Describes one value being edited by the number pad: what to call it, its
/// unit, whether decimals are allowed, and where the result goes.
struct NumberPadTarget: Identifiable {
    let id = UUID()
    let title: String
    let unit: String
    let allowsDecimal: Bool
    let initialValue: Double
    let onCommit: (Double) -> Void
}

/// Bottom-sheet numeric keypad for weight and reps. Big digits, no fiddly
/// inline text fields.
struct NumberPadSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: NumberPadTarget

    /// The value as typed. Starts empty so the first digit replaces rather
    /// than appends to the old value; the old value shows as a placeholder.
    @State private var text = ""

    private var placeholder: String {
        guard target.initialValue > 0 else { return "0" }
        return target.initialValue.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var committedValue: Double? {
        text.isEmpty ? nil : Double(text)
    }

    var body: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(target.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !target.unit.isEmpty {
                    Text(target.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            keypad

            Button {
                if let value = committedValue {
                    target.onCommit(value)
                }
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(committedValue == nil && !text.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    private var keypad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow { key("1"); key("2"); key("3") }
            GridRow { key("4"); key("5"); key("6") }
            GridRow { key("7"); key("8"); key("9") }
            GridRow {
                if target.allowsDecimal {
                    key(".")
                } else {
                    Color.clear.frame(height: 54)
                }
                key("0")
                backspaceKey
            }
        }
        .padding(.horizontal)
    }

    private func key(_ digit: String) -> some View {
        Button {
            tap(digit)
        } label: {
            Text(digit)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.bordered)
    }

    private var backspaceKey: some View {
        Button {
            if !text.isEmpty { text.removeLast() }
        } label: {
            Image(systemName: "delete.left")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Delete digit")
    }

    private func tap(_ digit: String) {
        if digit == "." {
            guard target.allowsDecimal, !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
            return
        }
        // Cap sensible lengths: 5 digits + optional decimal is plenty.
        guard text.count < 7 else { return }
        if text == "0" { text = digit } else { text += digit }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        NumberPadSheet(
            target: NumberPadTarget(
                title: "Bench Press · Set 2",
                unit: "lb",
                allowsDecimal: true,
                initialValue: 185
            ) { _ in }
        )
    }
}
