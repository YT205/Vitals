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

/// Vertical page navigation: crown or swipe between the four areas.
struct WatchRootView: View {
    var body: some View {
        TabView {
            WatchWorkoutView()
            WatchVitalsView()
            WatchRecoveryView()
            WatchWaterView()
        }
        .tabViewStyle(.verticalPage)
        .task {
            await WatchWorkoutManager.shared.requestAuthorization()
            try? await HealthKitService.shared.requestAuthorization()
        }
    }
}
