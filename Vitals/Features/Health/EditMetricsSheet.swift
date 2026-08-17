import SwiftUI

/// Choose which cards appear on the Health dashboard. Changes apply live and
/// persist; anything hidden keeps recording in Apple Health regardless.
struct EditMetricsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Cards") {
                    Toggle("Sleep", isOn: Binding(
                        get: { settings.showSleepCard },
                        set: { settings.showSleepCard = $0 }
                    ))
                }

                ForEach(VitalSection.allCases) { section in
                    Section(section.title) {
                        ForEach(VitalKind.allCases.filter { $0.section == section }) { kind in
                            Toggle(isOn: Binding(
                                get: { settings.isVisible(kind) },
                                set: { settings.setVisible(kind, $0) }
                            )) {
                                Label {
                                    Text(kind.title)
                                } icon: {
                                    Image(systemName: kind.systemImage)
                                        .foregroundStyle(kind.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Metrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    EditMetricsSheet()
        .environment(AppSettings())
}
