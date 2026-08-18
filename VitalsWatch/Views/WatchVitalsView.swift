import SwiftUI

/// Watch-local choice of which vitals show, independent of the phone
/// dashboard's selection (the wrist wants a shorter list).
@MainActor
enum WatchVitalsSelection {
    private static let key = "watch.visibleVitals"

    static let defaultKinds: [VitalKind] = [
        .restingHeartRate, .heartRateVariability, .bloodOxygen,
        .steps, .activeEnergy, .exerciseMinutes, .bodyWeight,
    ]

    static func visibleKinds() -> [VitalKind] {
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else {
            return defaultKinds
        }
        let stored = Set(raw)
        return VitalKind.allCases.filter { stored.contains($0.rawValue) }
    }

    static func isVisible(_ kind: VitalKind) -> Bool {
        visibleKinds().contains(kind)
    }

    static func setVisible(_ kind: VitalKind, _ visible: Bool) {
        var kinds = visibleKinds()
        if visible, !kinds.contains(kind) {
            kinds.append(kind)
        } else if !visible {
            kinds.removeAll { $0 == kind }
        }
        UserDefaults.standard.set(kinds.map(\.rawValue), forKey: key)
    }
}

/// Compact vitals list with a picker for which metrics appear.
struct WatchVitalsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var kinds: [VitalKind] = []
    @State private var readings: [VitalKind: VitalReading] = [:]
    @State private var isLoading = true
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(kinds) { kind in
                    row(kind)
                }
            }
            .listStyle(.carousel)
            .navigationTitle("Vitals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingPicker = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Choose metrics")
                }
            }
            .overlay {
                if isLoading && readings.isEmpty {
                    ProgressView()
                } else if kinds.isEmpty {
                    Text("No metrics selected.\nTap the sliders to add some.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .sheet(isPresented: $showingPicker, onDismiss: reloadSelection) {
                WatchMetricPickerView()
            }
            .task {
                reloadSelection()
                await refresh()
            }
            .refreshable { await refresh() }
        }
    }

    private func reloadSelection() {
        kinds = WatchVitalsSelection.visibleKinds()
        Task { await refresh() }
    }

    private func row(_ kind: VitalKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.caption)
                .foregroundStyle(kind.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(kind.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let reading = readings[kind] {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(valueText(kind: kind, reading: reading))
                            .font(.body.weight(.semibold))
                        Text(unitText(kind: kind))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("--")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func valueText(kind: VitalKind, reading: VitalReading) -> String {
        guard kind.respectsWeightUnit else { return reading.formattedValue }
        return settings.displayWeight(fromKilograms: reading.value)
            .formatted(.number.precision(.fractionLength(kind.fractionDigits)))
    }

    private func unitText(kind: VitalKind) -> String {
        kind.respectsWeightUnit ? settings.weightUnit.label : kind.displayUnit
    }

    private func refresh() async {
        isLoading = true
        var result: [VitalKind: VitalReading] = [:]
        for kind in kinds {
            if let reading = try? await HealthKitService.shared.reading(for: kind) {
                result[kind] = reading
            }
        }
        readings = result
        isLoading = false
    }
}

/// Toggle any metric on or off for the watch list.
private struct WatchMetricPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var visible: Set<VitalKind> = []

    var body: some View {
        List {
            ForEach(VitalKind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { visible.contains(kind) },
                    set: { isOn in
                        if isOn { visible.insert(kind) } else { visible.remove(kind) }
                        WatchVitalsSelection.setVisible(kind, isOn)
                    }
                )) {
                    Label {
                        Text(kind.title)
                            .font(.caption)
                    } icon: {
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(kind.tint)
                    }
                }
            }
        }
        .navigationTitle("Metrics")
        .onAppear {
            visible = Set(WatchVitalsSelection.visibleKinds())
        }
    }
}
