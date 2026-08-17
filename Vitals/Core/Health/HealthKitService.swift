import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case missingType(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Health data isn't available on this device."
        case .missingType(let name):
            "HealthKit does not expose a type named \(name)."
        }
    }
}

/// Thin wrapper over `HKHealthStore`.
///
/// Everything is `async` and main-actor isolated so views can call it directly.
/// The HealthKit callbacks are bridged to `async` with continuations, and only
/// plain value types cross back out -- never `HKSample` objects.
@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    /// `false` on iPad and in some simulators.
    let isAvailable = HKHealthStore.isHealthDataAvailable()

    /// Set once the permission sheet has been answered. HealthKit deliberately
    /// never tells us whether *read* access was granted, so treat this as
    /// "we asked", not "we can read".
    var hasRequestedAuthorization = false

    private init() {}

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for kind in VitalKind.allCases {
            if let type = kind.quantityType { types.insert(type) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        if let water = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            types.insert(water)
        }
        if let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.unavailable }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        hasRequestedAuthorization = true
    }

    // MARK: - Reading vitals

    /// Reads every vital in parallel. Missing values are simply absent from the
    /// result, which the dashboard renders as a dash.
    func loadAllVitals() async -> [VitalKind: VitalReading] {
        var results: [VitalKind: VitalReading] = [:]
        // Sequential is fine here: HealthKit queries are fast and this keeps the
        // code readable. Switch to a TaskGroup if the list grows a lot.
        for kind in VitalKind.allCases {
            if let reading = try? await reading(for: kind) {
                results[kind] = reading
            }
        }
        return results
    }

    func reading(for kind: VitalKind) async throws -> VitalReading? {
        switch kind.aggregation {
        case .mostRecent:
            guard let sample = try await mostRecentQuantity(for: kind) else { return nil }
            return VitalReading(
                kind: kind,
                value: sample.value * kind.displayScale,
                date: sample.date
            )
        case .dailySum:
            guard let total = try await dailySum(for: kind) else { return nil }
            return VitalReading(
                kind: kind,
                value: total * kind.displayScale,
                date: nil
            )
        }
    }

    /// Newest sample within the last 30 days.
    private func mostRecentQuantity(
        for kind: VitalKind
    ) async throws -> (value: Double, date: Date)? {
        guard let type = kind.quantityType else { return nil }
        let unit = kind.unit
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                // Extract plain values before crossing back out.
                let value = sample.quantity.doubleValue(for: unit)
                let date = sample.endDate
                continuation.resume(returning: (value, date))
            }
            store.execute(query)
        }
    }

    /// Everything recorded since midnight.
    private func dailySum(for kind: VitalKind) async throws -> Double? {
        guard let type = kind.quantityType else { return nil }
        let unit = kind.unit
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: .now,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    // No data for the day is reported as an error by HealthKit.
                    let hkError = error as NSError
                    if hkError.code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let total = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: total)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    /// Assembles last night's sleep from 6pm yesterday to now.
    func loadSleepSummary() async throws -> SleepSummary {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.missingType("sleepAnalysis")
        }
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let windowStart = startOfToday.addingTimeInterval(-6 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: .now)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var summary = SleepSummary()
                for case let sample as HKCategorySample in samples ?? [] {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    guard let stage = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
                        continue
                    }
                    switch stage {
                    case .inBed:
                        summary.inBed += duration
                    case .awake:
                        summary.awake += duration
                    case .asleepCore:
                        summary.core += duration
                        summary.asleep += duration
                    case .asleepDeep:
                        summary.deep += duration
                        summary.asleep += duration
                    case .asleepREM:
                        summary.rem += duration
                        summary.asleep += duration
                    case .asleepUnspecified:
                        summary.asleep += duration
                    @unknown default:
                        continue
                    }
                    if stage != .inBed && stage != .awake {
                        if summary.bedtime == nil { summary.bedtime = sample.startDate }
                        summary.wakeTime = sample.endDate
                    }
                }
                continuation.resume(returning: summary)
            }
            store.execute(query)
        }
    }

    // MARK: - Water

    private var waterType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: .dietaryWater)
    }

    /// Total water logged today, in millilitres.
    func waterTotalToday() async throws -> Double {
        guard let type = waterType else { throw HealthKitError.missingType("dietaryWater") }
        let unit = HKUnit.literUnit(with: .milli)
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: .now,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    let hkError = error as NSError
                    if hkError.code == HKError.errorNoData.rawValue {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                continuation.resume(
                    returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                )
            }
            store.execute(query)
        }
    }

    func saveWater(millilitres: Double, at date: Date = .now) async throws {
        guard let type = waterType else { throw HealthKitError.missingType("dietaryWater") }
        let quantity = HKQuantity(
            unit: .literUnit(with: .milli),
            doubleValue: millilitres
        )
        let sample = HKQuantitySample(
            type: type,
            quantity: quantity,
            start: date,
            end: date
        )
        try await store.save(sample)
    }

    // MARK: - Workouts

    /// Writes a finished lifting session to Health so it shows up in the Fitness
    /// and Health apps -- and so it survives deleting this app.
    func saveStrengthWorkout(
        start: Date,
        end: Date,
        activeEnergyKcal: Double?
    ) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining

        let builder = HKWorkoutBuilder(
            healthStore: store,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: start)

        if let activeEnergyKcal,
           activeEnergyKcal > 0,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let sample = HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: activeEnergyKcal),
                start: start,
                end: end
            )
            try await builder.addSamples([sample])
        }

        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
    }
}
