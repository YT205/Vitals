import AppIntents
import SwiftUI
import WidgetKit

/// The widget button's action: queue the water add and update the snapshot
/// optimistically. The app writes it to HealthKit next time it's active.
struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Adds a glass of water to today's total.")

    func perform() async throws -> some IntentResult {
        guard var snapshot = WidgetStore.loadSnapshot() else { return .result() }

        WidgetStore.appendPendingWater(
            PendingWater(millilitres: snapshot.quickAddML, date: .now)
        )

        // Optimistic total so the ring moves immediately. The display string
        // is rebuilt from the ratio the app last published.
        snapshot.waterTodayML += snapshot.quickAddML
        snapshot.waterDisplay = Self.approximateDisplay(
            millilitres: snapshot.waterTodayML,
            modeledOn: snapshot.quickAddLabel
        )
        snapshot.updatedAt = .now
        WidgetStore.save(snapshot)

        WidgetCenter.shared.reloadTimelines(ofKind: "WaterWidget")
        return .result()
    }

    /// "8 fl oz"-style labels tell us the unit; scale accordingly.
    private static func approximateDisplay(
        millilitres: Double,
        modeledOn quickAddLabel: String
    ) -> String {
        if quickAddLabel.contains("oz") {
            let ounces = millilitres / 29.573_53
            return "\(Int(ounces.rounded())) fl oz"
        }
        return "\(Int(millilitres.rounded())) mL"
    }
}

/// Today's water with a one-tap add.
struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaterWidget", provider: SnapshotProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Today's water total with a quick-add button.")
        .supportedFamilies([.systemSmall])
    }
}

struct WaterWidgetView: View {
    let entry: SnapshotEntry

    private var progress: Double {
        guard let snapshot = entry.snapshot, snapshot.waterGoalML > 0 else { return 0 }
        return min(snapshot.waterTodayML / snapshot.waterGoalML, 1)
    }

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(.blue.opacity(0.2), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(snapshot.waterDisplay)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("of \(snapshot.waterGoalDisplay)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }

                Button(intent: AddWaterIntent()) {
                    Label(snapshot.quickAddLabel, systemImage: "drop.fill")
                        .font(.caption2.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "drop")
                    .foregroundStyle(.secondary)
                Text("Open Vitals once to fill this in")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
