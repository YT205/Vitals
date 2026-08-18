import Foundation

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
#if os(watchOS)
import WatchKit
#endif

/// Small wrapper so haptics stay in one place -- and so shared code (timer
/// phases, routine player) fires the right feedback on either platform.
enum Haptics {
    @MainActor
    static func stageComplete() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.directionUp)
        #elseif canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    @MainActor
    static func routineComplete() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #elseif canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    @MainActor
    static func light() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.click)
        #elseif canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
