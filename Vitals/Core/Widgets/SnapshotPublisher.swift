import Foundation
import SwiftData
import WidgetKit

/// App-side half of the widget pipeline: formats current data into the shared
/// snapshot and drains water adds queued by the widget button.
@MainActor
enum SnapshotPublisher {
    /// The vitals shown on the widget, in order. A wrist-sized subset.
    private static let widgetKinds: [VitalKind] = [
        .restingHeartRate, .heartRateVariability, .steps, .activeEnergy,
    ]

    /// Publishes vitals after a dashboard refresh.
    static func publishVitals(
        readings: [VitalKind: VitalReading],
        baselines: [VitalKind: VitalBaseline],
        settings: AppSettings
    ) {
        var snapshot = WidgetStore.loadSnapshot() ?? emptySnapshot(settings: settings)

        snapshot.vitals = widgetKinds.compactMap { kind in
            guard let reading = readings[kind] else { return nil }

            let value: String
            let unit: String
            if kind.respectsWeightUnit {
                value = settings.displayWeight(fromKilograms: reading.value)
                    .formatted(.number.precision(.fractionLength(kind.fractionDigits)))
                unit = settings.weightUnit.label
            } else {
                value = reading.formattedValue
                unit = kind.displayUnit
            }

            let status: String? = {
                guard kind.aggregation == .mostRecent,
                      let baseline = baselines[kind] else { return nil }
                switch baseline.status(for: reading.value) {
                case .aboveUsual: return "above"
                case .belowUsual: return "below"
                case .typical: return "typical"
                }
            }()

            return WidgetVital(
                title: kind.title,
                systemImage: kind.systemImage,
                value: value,
                unit: unit,
                status: status
            )
        }
        snapshot.updatedAt = .now

        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Publishes today's water total (and current unit prefs) after any log.
    static func publishWater(todayML: Double, settings: AppSettings) {
        var snapshot = WidgetStore.loadSnapshot() ?? emptySnapshot(settings: settings)

        snapshot.waterTodayML = todayML
        snapshot.waterGoalML = settings.dailyWaterGoalML
        snapshot.waterDisplay = settings.formattedVolume(fromMillilitres: todayML)
        snapshot.waterGoalDisplay = settings.formattedVolume(
            fromMillilitres: settings.dailyWaterGoalML
        )

        let quickAdd = settings.volumeUnit == .ounces
            ? 8 * AppSettings.VolumeUnit.ounces.toMillilitres
            : 250
        snapshot.quickAddML = quickAdd
        snapshot.quickAddLabel = "+" + settings.formattedVolume(fromMillilitres: quickAdd)
        snapshot.updatedAt = .now

        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Writes widget-queued water adds into HealthKit and the local store.
    /// Call when the app becomes active. Idempotent: the queue is cleared
    /// first so a slow HealthKit write can't double-drain.
    static func drainPendingWater(
        context: ModelContext,
        settings: AppSettings,
        health: HealthKitService = .shared
    ) async {
        let pending = WidgetStore.loadPendingWater()
        guard !pending.isEmpty else { return }
        WidgetStore.clearPendingWater()

        for entry in pending {
            let record = WaterEntry(amountML: entry.millilitres, loggedAt: entry.date)
            context.insert(record)
            if (try? await health.saveWater(
                millilitres: entry.millilitres,
                at: entry.date
            )) != nil {
                record.savedToHealthKit = true
            }
        }
        try? context.save()

        // Republish so the widget's optimistic total becomes the real one.
        let total = (try? await health.waterTotalToday()) ?? 0
        publishWater(todayML: total, settings: settings)
    }

    private static func emptySnapshot(settings: AppSettings) -> WidgetSnapshot {
        let quickAdd = settings.volumeUnit == .ounces
            ? 8 * AppSettings.VolumeUnit.ounces.toMillilitres
            : 250
        return WidgetSnapshot(
            vitals: [],
            waterTodayML: 0,
            waterGoalML: settings.dailyWaterGoalML,
            quickAddML: quickAdd,
            quickAddLabel: "+" + settings.formattedVolume(fromMillilitres: quickAdd),
            waterDisplay: settings.formattedVolume(fromMillilitres: 0),
            waterGoalDisplay: settings.formattedVolume(
                fromMillilitres: settings.dailyWaterGoalML
            ),
            updatedAt: .now
        )
    }
}
