import SwiftData
import SwiftUI

@main
struct VitalsWatchApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(settings)
        }
        .modelContainer(WatchModelContainer.shared)
    }
}

/// Horizontal page navigation: swipe right-to-left between the four areas.
struct WatchRootView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView {
            WatchWorkoutView()
            WatchVitalsView()
            WatchRecoveryView()
            WatchWaterView()
        }
        .tabViewStyle(.page)
        .task {
            WatchSyncService.shared.activate(settings: settings)
            await WatchWorkoutManager.shared.requestAuthorization()
            try? await HealthKitService.shared.requestAuthorization()
        }
    }
}
