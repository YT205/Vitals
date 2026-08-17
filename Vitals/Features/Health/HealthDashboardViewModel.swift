import Foundation
import Observation

@MainActor
@Observable
final class HealthDashboardViewModel {
    private let health: HealthKitService

    var readings: [VitalKind: VitalReading] = [:]
    var sleep: SleepSummary?
    var isLoading = false
    var errorMessage: String?
    var lastRefreshed: Date?

    init(health: HealthKitService = .shared) {
        self.health = health
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
    }
}
