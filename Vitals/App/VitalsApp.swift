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
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .modelContainer(VitalsModelContainer.shared)
    }
}

extension AppSettings.Appearance {
    /// `nil` means "follow the system setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
