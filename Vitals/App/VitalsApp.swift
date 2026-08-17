import SwiftData
import SwiftUI

@main
struct VitalsApp: App {
    /// One shared settings object for unit preferences, water goal and reminders.
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(settings)
        }
        .modelContainer(VitalsModelContainer.shared)
    }
}
