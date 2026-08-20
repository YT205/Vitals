import SwiftUI

/// App-wide preferences. Reached from the gear on the Health tab.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var sync: PhoneSyncService { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: Binding(
                        get: { settings.appearance },
                        set: { settings.appearance = $0 }
                    )) {
                        ForEach(AppSettings.Appearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Units") {
                    Picker("Weight", selection: Binding(
                        get: { settings.weightUnit },
                        set: { settings.weightUnit = $0 }
                    )) {
                        ForEach(AppSettings.WeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Volume", selection: Binding(
                        get: { settings.volumeUnit },
                        set: { settings.volumeUnit = $0 }
                    )) {
                        ForEach(AppSettings.VolumeUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Link(destination: URL(string: "x-apple-health://")!) {
                        Label("Open Apple Health", systemImage: "heart.text.square")
                    }
                } header: {
                    Text("Health Access")
                }

                Section {
                    LabeledContent("Watch paired", value: sync.isPaired ? "Yes" : "No")
                    LabeledContent("Watch app installed", value: sync.isWatchAppInstalled ? "Yes" : "No")
                    if let pushed = sync.lastPushAt {
                        LabeledContent(
                            "Workouts pushed",
                            value: pushed.formatted(date: .omitted, time: .shortened)
                        )
                    }
                    if let error = sync.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button("Push Workouts to Watch Now") {
                        PhoneSyncService.shared.pushTemplates(settings: settings)
                    }
                } header: {
                    Text("Apple Watch Sync")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
