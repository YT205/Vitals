import HealthKit
import SwiftUI

/// How a vital is reduced to a single number for the dashboard.
enum VitalAggregation: Sendable {
    /// Take the newest sample (resting HR, HRV, SpO2...).
    case mostRecent
    /// Add up everything recorded since midnight (steps, calories...).
    case dailySum
}

/// Which dashboard section a vital belongs to.
enum VitalSection: String, CaseIterable, Identifiable, Sendable {
    case recovery
    case activity
    case bodyComposition

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recovery: "Recovery & Vitals"
        case .activity: "Today's Activity"
        case .bodyComposition: "Body"
        }
    }
}

/// Every metric the Health tab can display.
///
/// This is the single place to touch when you want a new vital on the dashboard:
/// add a case, fill in the switches, and it appears automatically. Nothing else
/// in the app needs to change.
enum VitalKind: String, CaseIterable, Identifiable, Sendable {
    case restingHeartRate
    case heartRateVariability
    case respiratoryRate
    case bloodOxygen
    case wristTemperature
    case walkingHeartRate
    case vo2Max
    case steps
    case activeEnergy
    case exerciseMinutes
    case bodyWeight
    case bodyFat
    case leanBodyMass
    case bmi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: "Resting Heart Rate"
        case .heartRateVariability: "HRV"
        case .respiratoryRate: "Respiratory Rate"
        case .bloodOxygen: "Blood Oxygen"
        case .wristTemperature: "Wrist Temperature"
        case .walkingHeartRate: "Walking Heart Rate"
        case .vo2Max: "Cardio Fitness"
        case .steps: "Steps"
        case .activeEnergy: "Active Energy"
        case .exerciseMinutes: "Exercise"
        case .bodyWeight: "Weight"
        case .bodyFat: "Body Fat"
        case .leanBodyMass: "Lean Mass"
        case .bmi: "BMI"
        }
    }

    var systemImage: String {
        switch self {
        case .restingHeartRate: "heart.fill"
        case .heartRateVariability: "waveform.path.ecg"
        case .respiratoryRate: "lungs.fill"
        case .bloodOxygen: "drop.degreesign.fill"
        case .wristTemperature: "thermometer.medium"
        case .walkingHeartRate: "figure.walk"
        case .vo2Max: "lungs"
        case .steps: "shoeprints.fill"
        case .activeEnergy: "flame.fill"
        case .exerciseMinutes: "stopwatch.fill"
        case .bodyWeight: "scalemass.fill"
        case .bodyFat: "percent"
        case .leanBodyMass: "figure.arms.open"
        case .bmi: "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .restingHeartRate, .walkingHeartRate: .red
        case .heartRateVariability: .purple
        case .respiratoryRate: .teal
        case .bloodOxygen: .blue
        case .wristTemperature: .orange
        case .vo2Max: .mint
        case .steps: .indigo
        case .activeEnergy: .pink
        case .exerciseMinutes: .green
        case .bodyWeight: .brown
        case .bodyFat: .yellow
        case .leanBodyMass: .cyan
        case .bmi: .gray
        }
    }

    var section: VitalSection {
        switch self {
        case .restingHeartRate, .heartRateVariability, .respiratoryRate,
             .bloodOxygen, .wristTemperature, .vo2Max, .walkingHeartRate:
            .recovery
        case .steps, .activeEnergy, .exerciseMinutes:
            .activity
        case .bodyWeight, .bodyFat, .leanBodyMass, .bmi:
            .bodyComposition
        }
    }

    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .restingHeartRate: .restingHeartRate
        case .heartRateVariability: .heartRateVariabilitySDNN
        case .respiratoryRate: .respiratoryRate
        case .bloodOxygen: .oxygenSaturation
        case .wristTemperature: .appleSleepingWristTemperature
        case .walkingHeartRate: .walkingHeartRateAverage
        case .vo2Max: .vo2Max
        case .steps: .stepCount
        case .activeEnergy: .activeEnergyBurned
        case .exerciseMinutes: .appleExerciseTime
        case .bodyWeight: .bodyMass
        case .bodyFat: .bodyFatPercentage
        case .leanBodyMass: .leanBodyMass
        case .bmi: .bodyMassIndex
        }
    }

    var quantityType: HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: identifier)
    }

    /// The unit the raw value is read in.
    var unit: HKUnit {
        switch self {
        case .restingHeartRate, .respiratoryRate, .walkingHeartRate:
            HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability:
            HKUnit.secondUnit(with: .milli)
        case .bloodOxygen:
            HKUnit.percent()
        case .wristTemperature:
            HKUnit.degreeCelsius()
        case .vo2Max:
            HKUnit(from: "ml/kg*min")
        case .steps:
            HKUnit.count()
        case .activeEnergy:
            HKUnit.kilocalorie()
        case .exerciseMinutes:
            HKUnit.minute()
        case .bodyWeight, .leanBodyMass:
            HKUnit.gramUnit(with: .kilo)
        case .bodyFat:
            HKUnit.percent()
        case .bmi:
            HKUnit.count()
        }
    }

    var aggregation: VitalAggregation {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes: .dailySum
        default: .mostRecent
        }
    }

    /// Multiplier applied to the raw HealthKit value before display.
    /// HealthKit reports oxygen saturation and body fat as 0...1 fractions.
    var displayScale: Double {
        switch self {
        case .bloodOxygen, .bodyFat: 100
        default: 1
        }
    }

    /// `true` for kilogram-based vitals that should render in the user's
    /// preferred weight unit (lb/kg). The raw reading stays in kilograms.
    var respectsWeightUnit: Bool {
        self == .bodyWeight || self == .leanBodyMass
    }

    var displayUnit: String {
        switch self {
        case .restingHeartRate, .walkingHeartRate: "BPM"
        case .heartRateVariability: "ms"
        case .respiratoryRate: "br/min"
        case .bloodOxygen, .bodyFat: "%"
        case .wristTemperature: ""      // formatted as a Measurement instead
        case .vo2Max: "ml/kg·min"
        case .steps: "steps"
        case .activeEnergy: "kcal"
        case .exerciseMinutes: "min"
        case .bodyWeight, .leanBodyMass: "kg"  // overridden by settings in the UI
        case .bmi: ""
        }
    }

    var fractionDigits: Int {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .restingHeartRate,
             .walkingHeartRate, .heartRateVariability:
            0
        case .bloodOxygen, .respiratoryRate, .vo2Max, .wristTemperature,
             .bodyWeight, .bodyFat, .leanBodyMass, .bmi:
            1
        }
    }
}
