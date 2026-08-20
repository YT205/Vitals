import Foundation
import Observation

@MainActor
@Observable
final class HealthDashboardViewModel {
    private let health: HealthKitService

    var readings: [VitalKind: VitalReading] = [:]
    var sleep: SleepSummary?
    /// Personal usual ranges, learned from each vital's last 30 days.
    var baselines: [VitalKind: VitalBaseline] = [:]
    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?

    // Optional-with-nil-default instead of `= .shared`: default argument
    // expressions are nonisolated, so referencing the MainActor singleton
    // there is a Swift 6 error. The init body is isolated; resolving here
    // is fine.
    init(health: HealthKitService? = nil) {
        self.health = health ?? .shared
    }

    var isHealthAvailable: Bool { health.isAvailable }

    /// `true` when we asked for permission but got nothing back, which almost
    /// always means read access was denied in the Health app.
    var looksLikePermissionProblem: Bool {
        health.hasRequestedAuthorization && readings.isEmpty && sleep?.hasData != true
    }

    func vitals(in section: VitalSection) -> [VitalKind] {
        VitalKind.allCases.filter { $0.section == section }
    }

    func reading(for kind: VitalKind) -> VitalReading? {
        readings[kind]
    }

    /// Today's reading vs the personal baseline. Only for latest-value
    /// vitals: a mid-day partial sum of steps would always read "below
    /// usual" against full-day baselines, which is noise, not signal.
    func status(for kind: VitalKind) -> VitalStatus? {
        guard kind.aggregation == .mostRecent,
              let baseline = baselines[kind],
              let reading = readings[kind] else { return nil }
        return baseline.status(for: reading.value)
    }

    func refresh() async {
        guard health.isAvailable else {
            errorMessage = HealthKitError.unavailable.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil

        // Make sure we've asked before querying, otherwise everything reads empty.
        if !health.hasRequestedAuthorization {
            try? await health.requestAuthorization()
        }

        readings = await health.loadAllVitals()

        do {
            sleep = try await health.loadSleepSummary()
        } catch {
            sleep = nil
        }

        lastRefreshed = .now
        isLoading = false

        // Baselines load after the cards are already showing values; badges
        // fill in as each history query lands.
        await loadBaselines()
    }

    /// Learns each latest-value vital's usual range from its past 30 days,
    /// excluding today (today is the value being judged).
    private func loadBaselines() async {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        var result: [VitalKind: VitalBaseline] = [:]

        for kind in VitalKind.allCases
        where kind.aggregation == .mostRecent && readings[kind] != nil {
            let history = (try? await health.dailyHistory(for: kind, days: 30)) ?? []
            let pastValues = history
                .filter { $0.date < startOfToday }
                .map(\.value)
            if let baseline = VitalBaseline.compute(from: pastValues) {
                result[kind] = baseline
            }
        }

        baselines = result
    }
}
