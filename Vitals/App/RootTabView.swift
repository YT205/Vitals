import SwiftUI

/// The bottom tab bar. Adding a new section to the app is a one-line change here
/// plus a new folder under `Features/`.
struct RootTabView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var health = HealthKitService.shared
    @State private var didRequestAuthorization = false

    var body: some View {
        TabView {
            Tab("Health", systemImage: "heart.text.square") {
                HealthDashboardView()
            }
            Tab("Fitness", systemImage: "dumbbell") {
                FitnessHomeView()
            }
            Tab("Recovery", systemImage: "figure.cooldown") {
                RecoveryHomeView()
            }
            Tab("Water", systemImage: "drop") {
                WaterHomeView()
            }
        }
        .task {
            // Watch sync: activate the session and push the current library.
            PhoneSyncService.shared.activate()

            // Water logged from the widget while we weren't running.
            await SnapshotPublisher.drainPendingWater(
                context: context,
                settings: settings
            )

            // Ask once per launch. HealthKit itself only shows the sheet the
            // first time, so this is cheap to call.
            guard !didRequestAuthorization else { return }
            didRequestAuthorization = true
            try? await health.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await SnapshotPublisher.drainPendingWater(
                    context: context,
                    settings: settings
                )
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
