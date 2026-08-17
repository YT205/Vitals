import SwiftUI

/// The bottom tab bar. Adding a new section to the app is a one-line change here
/// plus a new folder under `Features/`.
struct RootTabView: View {
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
            // Ask once per launch. HealthKit itself only shows the sheet the
            // first time, so this is cheap to call.
            guard !didRequestAuthorization else { return }
            didRequestAuthorization = true
            try? await health.requestAuthorization()
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppSettings())
        .modelContainer(VitalsModelContainer.preview)
}
