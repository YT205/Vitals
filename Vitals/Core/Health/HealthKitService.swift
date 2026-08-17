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
        // Raw heart rate stream (the dashboard vitals only cover resting/walking).
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        // Height, for deriving BMI when weight is logged.
        if let height = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(height)
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
        // Workout effort (1-10), same scale the Workout app asks about.
        if let effort = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
            types.insert(effort)
        }
        // Body composition: logged weight and calculated body fat, plus the
        // two values derived from them.
        let bodyIdentifiers: [HKQuantityTypeIdentifier] = [
            .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex,
        ]
        for identifier in bodyIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
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

    // MARK: - History

    /// One value per day for the last `days` days, for charting.
    ///
    /// Sum-style vitals (steps, energy, exercise minutes) get the day's total;
    /// everything else gets the day's average. Days with no data are omitted.
    func dailyHistory(
        for kind: VitalKind,
        days: Int
    ) async throws -> [(date: Date, value: Double)] {
        guard let type = kind.quantityType else { return [] }

        let unit = kind.unit
        let scale = kind.displayScale
        let calendar = Calendar.current
        let end = Date.now
        let anchor = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: anchor) else {
            return []
        }

        let options: HKStatisticsOptions =
            kind.aggregation == .dailySum ? .cumulativeSum : .discreteAverage
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var points: [(date: Date, value: Double)] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = options == .cumulativeSum
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    if let value = quantity?.doubleValue(for: unit) {
                        points.append((date: statistics.startDate, value: value * scale))
                    }
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }

    /// One `SleepSummary` per night for the last `nights` nights, newest last.
    ///
    /// A sample belongs to the night it *ended*: everything ending between 6pm
    /// yesterday and 6pm today counts as "last night". Nights with no sleep
    /// data are omitted.
    func sleepHistory(
        nights: Int
    ) async throws -> [(night: Date, summary: SleepSummary)] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.missingType("sleepAnalysis")
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        guard let windowStart = calendar.date(
            byAdding: .day, value: -nights, to: startOfToday
        ) else { return [] }

        let predicate = HKQuery.predicateForSamples(
            withStart: windowStart.addingTimeInterval(-6 * 3600),
            end: .now
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]

        let raw: [(start: Date, end: Date, value: Int)] =
            try await withCheckedThrowingContinuation { continuation in
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
                    let extracted = (samples ?? []).compactMap { sample ->
                        (start: Date, end: Date, value: Int)? in
                        guard let categorySample = sample as? HKCategorySample else {
                            return nil
                        }
                        return (
                            categorySample.startDate,
                            categorySample.endDate,
                            categorySample.value
                        )
                    }
                    continuation.resume(returning: extracted)
                }
                store.execute(query)
            }

        // Bucket by the day the sample ended, shifted 6 hours so a night that
        // ends at 7am and one that ends at 11pm both land on the same key.
        var buckets: [Date: SleepSummary] = [:]
        for sample in raw {
            let night = calendar.startOfDay(for: sample.end.addingTimeInterval(6 * 3600))
            var summary = buckets[night] ?? SleepSummary()
            let duration = sample.end.timeIntervalSince(sample.start)
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
                if summary.bedtime == nil || sample.start < summary.bedtime! {
                    summary.bedtime = sample.start
                }
                if summary.wakeTime == nil || sample.end > summary.wakeTime! {
                    summary.wakeTime = sample.end
                }
            }
            buckets[night] = summary
        }

        return buckets
            .filter { $0.value.hasData }
            .sorted { $0.key < $1.key }
            .map { (night: $0.key, summary: $0.value) }
    }

    // MARK: - Heart rate

    /// The newest heart rate sample from the last 4 hours, in BPM.
    ///
    /// Without a watch app streaming live, "current" means the most recent
    /// reading the watch has synced -- typically a few minutes old. The
    /// timestamp is returned so the UI can be honest about that.
    func latestHeartRate() async throws -> (bpm: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let start = Date.now.addingTimeInterval(-4 * 3600)
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
                let bpm = sample.quantity.doubleValue(for: unit)
                let date = sample.endDate
                continuation.resume(returning: (bpm, date))
            }
            store.execute(query)
        }
    }

    // MARK: - Body composition

    /// Newest sample of a quantity type within the last `days` days, in `unit`.
    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        withinDays days: Int
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now)
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
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    /// Latest height in metres. Height rarely changes, so look back 10 years.
    func latestHeightMeters() async throws -> Double? {
        try await latestQuantity(.height, unit: .meter(), withinDays: 3_650)
    }

    /// Latest body weight in kilograms from the last year.
    func latestBodyMassKg() async throws -> Double? {
        try await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), withinDays: 365)
    }

    /// Saves a weight sample, deriving BMI alongside it when height is on file.
    func saveBodyWeight(kilograms: Double, at date: Date = .now) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.missingType("bodyMass")
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: date,
            end: date
        )
        try await store.save(sample)

        // Derive BMI = kg / m^2 when we know the height.
        if let height = try? await latestHeightMeters(),
           height > 0,
           let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            let bmi = kilograms / (height * height)
            let bmiSample = HKQuantitySample(
                type: bmiType,
                quantity: HKQuantity(unit: .count(), doubleValue: bmi),
                start: date,
                end: date
            )
            try? await store.save(bmiSample)
        }
    }

    /// Saves a body fat percentage (0...100 input), deriving lean body mass
    /// alongside it when a recent weight is on file.
    func saveBodyFat(percent: Double, at date: Date = .now) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthKitError.missingType("bodyFatPercentage")
        }
        let fraction = min(max(percent / 100, 0), 1)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .percent(), doubleValue: fraction),
            start: date,
            end: date
        )
        try await store.save(sample)

        // Derive lean mass = weight x (1 - fat fraction) when weight is known.
        if let weight = try? await latestBodyMassKg(),
           weight > 0,
           let leanType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            let leanSample = HKQuantitySample(
                type: leanType,
                quantity: HKQuantity(
                    unit: .gramUnit(with: .kilo),
                    doubleValue: weight * (1 - fraction)
                ),
                start: date,
                end: date
            )
            try? await store.save(leanSample)
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
    ///
    /// `effortScore` (1...10) is saved as a workout effort sample and related to
    /// the workout, which is exactly what the Workout app's own "Effort" prompt
    /// does. Passing `nil` skips it.
    func saveStrengthWorkout(
        start: Date,
        end: Date,
        activeEnergyKcal: Double?,
        effortScore: Int? = nil
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
        let workout = try await builder.finishWorkout()

        if let workout, let effortScore {
            try await relateEffort(effortScore, to: workout)
        }
    }

    /// Saves an effort score sample and links it to the workout.
    /// Effort failures are deliberately not fatal: the workout itself is already
    /// in Health by the time this runs.
    private func relateEffort(_ score: Int, to workout: HKWorkout) async throws {
        guard let effortType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            return
        }
        let clamped = min(max(score, 1), 10)
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(clamped)),
            start: workout.startDate,
            end: workout.endDate
        )
        try await store.save(sample)
        try await store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
    }
}
