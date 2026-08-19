import SwiftUI

/// Describes one value being edited by the number pad: what to call it, its
/// unit, how to step it, where the result goes, and how to reach the next
/// cell in the editing sequence.
struct NumberPadTarget: Identifiable {
    let id = UUID()
    let title: String
    let unit: String
    let allowsDecimal: Bool
    let initialValue: Double
    /// Increment for the +/- keys (0.5 for weight, 1 for reps).
    let step: Double
    let onCommit: (Double) -> Void
    /// Applies the value to this cell and every following set of the same
    /// exercise. `nil` hides the copy-down key.
    let onCopyDown: ((Double) -> Void)?
    /// The next cell in the sequence (weight -> reps -> next set's weight).
    /// `nil` means this is the last cell; Next behaves like Done.
    let next: (() -> NumberPadTarget?)?

    init(
        title: String,
        unit: String,
        allowsDecimal: Bool,
        initialValue: Double,
        step: Double = 1,
        onCommit: @escaping (Double) -> Void,
        onCopyDown: ((Double) -> Void)? = nil,
        next: (() -> NumberPadTarget?)? = nil
    ) {
        self.title = title
        self.unit = unit
        self.allowsDecimal = allowsDecimal
        self.initialValue = initialValue
        self.step = step
        self.onCommit = onCommit
        self.onCopyDown = onCopyDown
        self.next = next
    }
}

/// Bottom-sheet numeric keypad. Digits on the left 3x4, function column on
/// the right: done, minus/plus stepping, copy-down, and next-cell -- which
/// chains through the whole plan without closing the sheet.
struct NumberPadSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The cell currently being edited. Next swaps this in place.
    @State private var current: NumberPadTarget

    /// The value as typed. Starts empty so the first digit replaces rather
    /// than appends to the old value; the old value shows as a placeholder.
    @State private var text = ""

    init(target: NumberPadTarget) {
        _current = State(initialValue: target)
    }

    private var placeholder: String {
        guard current.initialValue > 0 else { return "0" }
        return current.initialValue.formatted(.number.precision(.fractionLength(0...1)))
    }

    private var typedValue: Double? {
        text.isEmpty ? nil : Double(text)
    }

    /// What the value currently *is*: typed if typed, else the existing one.
    private var effectiveValue: Double {
        typedValue ?? current.initialValue
    }

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(.tertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            Text(current.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 14)
                .padding(.horizontal)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text.isEmpty ? placeholder : text)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !current.unit.isEmpty {
                    Text(current.unit)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            keypad
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Keypad

    private var keypad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                key("1"); key("2"); key("3")
                functionKey("chevron.down", label: "Done") { commitAndClose() }
            }
            GridRow {
                key("4"); key("5"); key("6")
                stepKey
            }
            GridRow {
                key("7"); key("8"); key("9")
                functionKey(
                    "square.fill.on.square.fill",
                    label: "Copy to following sets",
                    disabled: current.onCopyDown == nil
                ) { copyDown() }
            }
            GridRow {
                if current.allowsDecimal {
                    key(".")
                } else {
                    Color.clear.frame(height: 54)
                }
                key("0")
                backspaceKey
                functionKey("arrow.turn.down.right", label: "Next field", prominent: true) {
                    goNext()
                }
            }
        }
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

    /// A minus/plus pair sharing one cell: steps the current value.
    private var stepKey: some View {
        HStack(spacing: 4) {
            Button {
                setValue(max(0, effectiveValue - current.step))
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Decrease by \(current.step.formatted())")

            Button {
                setValue(effectiveValue + current.step)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Increase by \(current.step.formatted())")
        }
    }

    private func functionKey(
        _ systemImage: String,
        label: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if prominent {
                Button(action: action) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.bordered)
            }
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    private func tap(_ digit: String) {
        if digit == "." {
            guard current.allowsDecimal, !text.contains(".") else { return }
            text = text.isEmpty ? "0." : text + "."
            return
        }
        // Cap sensible lengths: 5 digits + optional decimal is plenty.
        guard text.count < 7 else { return }
        if text == "0" { text = digit } else { text += digit }
    }

    /// Writes a stepped value into the display (and thus into the commit path).
    private func setValue(_ value: Double) {
        text = current.allowsDecimal
            ? value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            : "\(Int(value))"
    }

    private func commitIfEdited() {
        if let value = typedValue {
            current.onCommit(value)
        }
    }

    private func commitAndClose() {
        commitIfEdited()
        dismiss()
    }

    private func copyDown() {
        current.onCopyDown?(effectiveValue)
        Haptics.light()
        goNext()
    }

    private func goNext() {
        commitIfEdited()
        if let nextTarget = current.next?() {
            current = nextTarget
            text = ""
        } else {
            dismiss()
        }
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        NumberPadSheet(
            target: NumberPadTarget(
                title: "Bench Press · Set 2",
                unit: "lb",
                allowsDecimal: true,
                initialValue: 185,
                step: 0.5,
                onCommit: { _ in },
                onCopyDown: { _ in },
                next: { nil }
            )
        )
    }
}
