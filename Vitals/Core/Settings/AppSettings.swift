import Foundation
import Observation

/// App-wide preferences, persisted in `UserDefaults`.
///
/// Injected into the environment by `VitalsApp` so any view can read or change
/// it. Add a new preference by adding a stored property plus a key -- the
/// `didSet` writes it through automatically.
@Observable
final class AppSettings {
    enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
        case pounds
        case kilograms

        var id: String { rawValue }
        var label: String { self == .pounds ? "lb" : "kg" }

        /// Multiplier from this unit to kilograms (the canonical storage unit).
        var toKilograms: Double { self == .pounds ? 0.453_592_37 : 1 }
    }

    enum VolumeUnit: String, CaseIterable, Identifiable, Sendable {
        case ounces
        case millilitres

        var id: String { rawValue }
        var label: String { self == .ounces ? "fl oz" : "mL" }

        /// Multiplier from this unit to millilitres (the canonical storage unit).
        var toMillilitres: Double { self == .ounces ? 29.573_53 : 1 }
    }

    private enum Key {
        static let weightUnit = "settings.weightUnit"
        static let volumeUnit = "settings.volumeUnit"
        static let dailyWaterGoalML = "settings.dailyWaterGoalML"
        static let waterRemindersEnabled = "settings.waterRemindersEnabled"
        static let reminderStartHour = "settings.reminderStartHour"
        static let reminderEndHour = "settings.reminderEndHour"
        static let reminderIntervalMinutes = "settings.reminderIntervalMinutes"
        static let hiddenVitals = "settings.hiddenVitals"
        static let showSleepCard = "settings.showSleepCard"
    }

    private let defaults: UserDefaults

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) }
    }

    var volumeUnit: VolumeUnit {
        didSet { defaults.set(volumeUnit.rawValue, forKey: Key.volumeUnit) }
    }

    /// Daily water target in millilitres.
    var dailyWaterGoalML: Double {
        didSet { defaults.set(dailyWaterGoalML, forKey: Key.dailyWaterGoalML) }
    }

    var waterRemindersEnabled: Bool {
        didSet { defaults.set(waterRemindersEnabled, forKey: Key.waterRemindersEnabled) }
    }

    var reminderStartHour: Int {
        didSet { defaults.set(reminderStartHour, forKey: Key.reminderStartHour) }
    }

    var reminderEndHour: Int {
        didSet { defaults.set(reminderEndHour, forKey: Key.reminderEndHour) }
    }

    var reminderIntervalMinutes: Int {
        didSet { defaults.set(reminderIntervalMinutes, forKey: Key.reminderIntervalMinutes) }
    }

    /// Vitals hidden from the Health dashboard. Stored as the *hidden* set (not
    /// the visible one) so any metric added in a future update shows up
    /// automatically instead of being invisible to existing installs.
    var hiddenVitals: Set<String> {
        didSet { defaults.set(Array(hiddenVitals), forKey: Key.hiddenVitals) }
    }

    /// Whether the sleep card appears on the Health dashboard.
    var showSleepCard: Bool {
        didSet { defaults.set(showSleepCard, forKey: Key.showSleepCard) }
    }

    func isVisible(_ kind: VitalKind) -> Bool {
        !hiddenVitals.contains(kind.rawValue)
    }

    func setVisible(_ kind: VitalKind, _ visible: Bool) {
        if visible {
            hiddenVitals.remove(kind.rawValue)
        } else {
            hiddenVitals.insert(kind.rawValue)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        weightUnit = WeightUnit(
            rawValue: defaults.string(forKey: Key.weightUnit) ?? ""
        ) ?? .pounds

        volumeUnit = VolumeUnit(
            rawValue: defaults.string(forKey: Key.volumeUnit) ?? ""
        ) ?? .ounces

        let storedGoal = defaults.double(forKey: Key.dailyWaterGoalML)
        dailyWaterGoalML = storedGoal > 0 ? storedGoal : 3_000

        waterRemindersEnabled = defaults.bool(forKey: Key.waterRemindersEnabled)

        let storedStart = defaults.integer(forKey: Key.reminderStartHour)
        reminderStartHour = storedStart > 0 ? storedStart : 8

        let storedEnd = defaults.integer(forKey: Key.reminderEndHour)
        reminderEndHour = storedEnd > 0 ? storedEnd : 21

        let storedInterval = defaults.integer(forKey: Key.reminderIntervalMinutes)
        reminderIntervalMinutes = storedInterval > 0 ? storedInterval : 90

        hiddenVitals = Set(defaults.stringArray(forKey: Key.hiddenVitals) ?? [])

        // Default true; `bool(forKey:)` alone would default to false.
        showSleepCard = defaults.object(forKey: Key.showSleepCard) == nil
            ? true
            : defaults.bool(forKey: Key.showSleepCard)
    }

    // MARK: - Weight helpers

    /// Converts a stored kilogram value into the user's preferred unit.
    func displayWeight(fromKilograms kilograms: Double) -> Double {
        kilograms / weightUnit.toKilograms
    }

    /// Converts a value the user typed into kilograms for storage.
    func kilograms(fromDisplayWeight value: Double) -> Double {
        value * weightUnit.toKilograms
    }

    func formattedWeight(fromKilograms kilograms: Double) -> String {
        let value = displayWeight(fromKilograms: kilograms)
        let digits = value.rounded() == value ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return "\(number) \(weightUnit.label)"
    }

    // MARK: - Volume helpers

    func displayVolume(fromMillilitres millilitres: Double) -> Double {
        millilitres / volumeUnit.toMillilitres
    }

    func millilitres(fromDisplayVolume value: Double) -> Double {
        value * volumeUnit.toMillilitres
    }

    func formattedVolume(fromMillilitres millilitres: Double) -> String {
        let value = displayVolume(fromMillilitres: millilitres)
        return "\(value.formatted(.number.precision(.fractionLength(0)))) \(volumeUnit.label)"
    }

    /// The quick-add buttons on the Water tab, in millilitres.
    var quickAddOptions: [Double] {
        switch volumeUnit {
        case .ounces:
            [8, 12, 16, 24, 32].map { $0 * VolumeUnit.ounces.toMillilitres }
        case .millilitres:
            [250, 350, 500, 750, 1_000]
        }
    }
}
