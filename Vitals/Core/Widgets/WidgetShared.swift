import Foundation

// Shared between the app and the widget extension via App Group storage.
//
// Widgets can't query HealthKit, so the app publishes a pre-formatted
// snapshot whenever its own data refreshes, and widgets just render it.
// The water widget's +button writes a *pending* entry; the app drains
// pending entries into HealthKit next time it becomes active.

enum WidgetStore {
    static let appGroupID = "group.com.yashst.vitals"

    static let snapshotKey = "widget.snapshot"
    static let pendingWaterKey = "widget.pendingWater"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // MARK: - Snapshot

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    // MARK: - Pending water (widget button -> app)

    static func loadPendingWater() -> [PendingWater] {
        guard let data = defaults?.data(forKey: pendingWaterKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWater].self, from: data)) ?? []
    }

    static func appendPendingWater(_ entry: PendingWater) {
        var pending = loadPendingWater()
        pending.append(entry)
        if let data = try? JSONEncoder().encode(pending) {
            defaults?.set(data, forKey: pendingWaterKey)
        }
    }

    static func clearPendingWater() {
        defaults?.removeObject(forKey: pendingWaterKey)
    }
}

/// Everything the widgets render, pre-formatted by the app so the extension
/// needs no models, units, or HealthKit.
struct WidgetSnapshot: Codable {
    var vitals: [WidgetVital]
    /// Today's water in millilitres, including pending widget adds.
    var waterTodayML: Double
    var waterGoalML: Double
    /// The quick-add amount in millilitres and its display label ("8 oz").
    var quickAddML: Double
    var quickAddLabel: String
    /// Display string for the current total, e.g. "24 oz".
    var waterDisplay: String
    var waterGoalDisplay: String
    var updatedAt: Date
}

/// One pre-formatted vital line for the vitals widget.
struct WidgetVital: Codable, Identifiable {
    var id: String { title }
    let title: String
    let systemImage: String
    let value: String
    let unit: String
    /// "above", "below", "typical", or nil -- mapped to colors widget-side.
    let status: String?
}

/// A water add made from the widget, awaiting HealthKit write by the app.
struct PendingWater: Codable {
    let millilitres: Double
    let date: Date
}
