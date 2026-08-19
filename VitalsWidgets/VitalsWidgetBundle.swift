import SwiftUI
import WidgetKit

@main
struct VitalsWidgetBundle: WidgetBundle {
    var body: some Widget {
        VitalsWidget()
        WaterWidget()
    }
}

// MARK: - Shared timeline plumbing

/// Both widgets render the app-published snapshot; nothing is fetched here.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetStore.loadSnapshot() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetStore.loadSnapshot())
        // The app reloads timelines whenever data changes; the hourly refresh
        // just keeps "updated at" honest if the app isn't opened.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    /// Believable sample for the widget gallery.
    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            vitals: [
                WidgetVital(title: "Resting Heart Rate", systemImage: "heart.fill",
                            value: "54", unit: "BPM", status: "typical"),
                WidgetVital(title: "HRV", systemImage: "waveform.path.ecg",
                            value: "62", unit: "ms", status: "above"),
                WidgetVital(title: "Steps", systemImage: "shoeprints.fill",
                            value: "8,432", unit: "steps", status: nil),
                WidgetVital(title: "Active Energy", systemImage: "flame.fill",
                            value: "512", unit: "kcal", status: nil),
            ],
            waterTodayML: 1_420,
            waterGoalML: 3_000,
            quickAddML: 236.6,
            quickAddLabel: "+8 fl oz",
            waterDisplay: "48 fl oz",
            waterGoalDisplay: "101 fl oz",
            updatedAt: .now
        )
    }
}
