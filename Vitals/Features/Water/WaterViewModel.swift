import Foundation
import Observation
import SwiftData

/// Logging logic for the Water tab.
///
/// Entries are written to SwiftData first (so the UI is instant and works even
/// without Health permission) and mirrored to HealthKit as `dietaryWater`.
@MainActor
@Observable
final class WaterViewModel {
    private let health: HealthKitService

    var syncError: String?

    // See HealthDashboardViewModel.init for why this isn't `= .shared`.
    init(health: HealthKitService? = nil) {
        self.health = health ?? .shared
    }

    // MARK: - Logging

    func log(millilitres: Double, context: ModelContext) async {
        guard millilitres > 0 else { return }

        let entry = WaterEntry(amountML: millilitres)
        context.insert(entry)
        try? context.save()

        Haptics.light()
        await mirror(entry, context: context)
    }

    func delete(_ entry: WaterEntry, context: ModelContext) {
        // Note: this removes the local record only. The matching HealthKit sample
        // stays put -- delete it in the Health app if you want it gone there too.
        context.delete(entry)
        try? context.save()
    }

    /// Retries any entries that failed to reach HealthKit earlier.
    func retryFailedSyncs(_ entries: [WaterEntry], context: ModelContext) async {
        for entry in entries where !entry.savedToHealthKit {
            await mirror(entry, context: context)
        }
    }

    private func mirror(_ entry: WaterEntry, context: ModelContext) async {
        guard health.isAvailable else { return }
        do {
            try await health.saveWater(millilitres: entry.amountML, at: entry.loggedAt)
            entry.savedToHealthKit = true
            try? context.save()
            syncError = nil
        } catch {
            syncError = "Logged locally. Apple Health write failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Totals

    func entriesToday(from entries: [WaterEntry]) -> [WaterEntry] {
        entries.filter { Calendar.current.isDateInToday($0.loggedAt) }
    }

    func total(of entries: [WaterEntry]) -> Double {
        entries.reduce(0) { $0 + $1.amountML }
    }

    /// Totals for the last `days` days, oldest first. Used for the mini history.
    func dailyTotals(from entries: [WaterEntry], days: Int = 7) -> [(date: Date, total: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let total = entries
                .filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.amountML }
            return (date: day, total: total)
        }
    }
}
