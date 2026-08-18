import Foundation
import Observation
import WatchConnectivity

/// The watch end of phone sync.
///
/// Templates and unit preferences arrive as application context and are
/// persisted locally, so the workout list works offline and across launches.
/// Finished workouts go back as queued user info, which survives the phone
/// being out of reach until it isn't.
@MainActor
@Observable
final class WatchSyncService: NSObject {
    static let shared = WatchSyncService()

    /// The phone's workout library, newest push wins.
    private(set) var templates: [SyncTemplate] = []

    /// The app's live settings object, injected at activation so unit changes
    /// from the phone take effect immediately, not on next launch.
    private var settings: AppSettings?

    private static let templatesKey = "sync.templates"

    private override init() {
        super.init()
        // Boot from the last persisted push so the list is instant.
        if let data = UserDefaults.standard.data(forKey: Self.templatesKey),
           let cached = SyncCoder.decode([SyncTemplate].self, from: data) {
            templates = cached.sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    func activate(settings: AppSettings) {
        self.settings = settings
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
    }

    /// Queues a finished workout for the phone. Delivery is the system's
    /// problem from here -- it retries until the phone takes it.
    func sendFinishedWorkout(_ finished: SyncFinishedWorkout) {
        guard let session, let data = SyncCoder.encode(finished) else { return }
        session.transferUserInfo([SyncKeys.finishedWorkout: data])
    }

    /// Asks the phone for the library right now. Works only while the phone
    /// app is reachable (foreground or recently backgrounded); the application
    /// context path covers every other case eventually.
    func requestTemplates() {
        guard let session,
              session.activationState == .activated,
              session.isReachable else { return }

        session.sendMessage(
            [SyncKeys.requestTemplates: true],
            replyHandler: { reply in
                Task { @MainActor in
                    self.apply(reply)
                }
            },
            errorHandler: nil
        )
    }

    // MARK: - Applying pushes

    fileprivate func apply(_ context: [String: Any]) {
        if let data = context[SyncKeys.templates] as? Data,
           let received = SyncCoder.decode([SyncTemplate].self, from: data) {
            templates = received.sorted { $0.sortOrder < $1.sortOrder }
            UserDefaults.standard.set(data, forKey: Self.templatesKey)
        }

        // Mirror the phone's unit preferences so numbers read the same.
        guard let settings else { return }
        if let raw = context[SyncKeys.weightUnit] as? String,
           let unit = AppSettings.WeightUnit(rawValue: raw) {
            settings.weightUnit = unit
        }
        if let raw = context[SyncKeys.volumeUnit] as? String,
           let unit = AppSettings.VolumeUnit(rawValue: raw) {
            settings.volumeUnit = unit
        }
        if let goal = context[SyncKeys.waterGoalML] as? Double, goal > 0 {
            settings.dailyWaterGoalML = goal
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        // The context the phone pushed while we weren't running.
        let cached = session.receivedApplicationContext
        Task { @MainActor in
            if !cached.isEmpty {
                self.apply(cached)
            }
            // Nothing cached or nothing stored: ask the phone directly, in
            // case it's live right now (covers the fresh-install case).
            if self.templates.isEmpty {
                self.requestTemplates()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            self.apply(applicationContext)
        }
    }
}
