import Foundation
import SwiftUI

// MARK: - Log weight

/// Logs a body weight sample to Apple Health, in the user's unit.
/// BMI is derived and saved automatically when Health knows your height.
struct LogWeightSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful save so the dashboard can refresh.
    let onSaved: () -> Void

    @State private var weight: Double = 0
    @State private var date: Date = .now
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Weight", value: $weight, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .font(.title2.weight(.semibold))
                        Text(settings.weightUnit.label)
                            .foregroundStyle(.secondary)
                    }

                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .disabled(weight <= 0)
                    }
                }
            }
            .task {
                // Prefill with the most recent weight on file.
                if weight == 0,
                   let kg = try? await HealthKitService.shared.latestBodyMassKg() {
                    weight = settings.displayWeight(fromKilograms: kg)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await HealthKitService.shared.saveBodyWeight(
                    kilograms: settings.kilograms(fromDisplayWeight: weight),
                    at: date
                )
                onSaved()
                dismiss()
            } catch {
                errorMessage = "Couldn't save to Apple Health: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

// MARK: - Body fat calculator

/// U.S. Navy circumference-method body fat estimate, saved to Apple Health.
/// Lean body mass is derived and saved automatically when Health has a recent
/// weight.
struct BodyFatCalculatorView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let onSaved: () -> Void

    enum Sex: String, CaseIterable, Identifiable {
        case male = "Male"
        case female = "Female"
        var id: String { rawValue }
    }

    enum MeasureUnit: String, CaseIterable, Identifiable {
        case centimetres = "cm"
        case inches = "in"

        var id: String { rawValue }
        var toCentimetres: Double { self == .inches ? 2.54 : 1 }
    }

    @State private var sex: Sex = .male
    @State private var unit: MeasureUnit = .centimetres
    @State private var height: Double = 0
    @State private var neck: Double = 0
    @State private var waist: Double = 0
    @State private var hip: Double = 0
    @State private var isSaving = false
    @State private var errorMessage: String?

    // MARK: Calculation

    private var heightCm: Double { height * unit.toCentimetres }
    private var neckCm: Double { neck * unit.toCentimetres }
    private var waistCm: Double { waist * unit.toCentimetres }
    private var hipCm: Double { hip * unit.toCentimetres }

    /// U.S. Navy formula (metric). Requires waist > neck (plus hip for women);
    /// returns nil until the inputs make sense.
    private var bodyFatPercent: Double? {
        guard heightCm > 0, neckCm > 0, waistCm > 0 else { return nil }

        let result: Double
        switch sex {
        case .male:
            guard waistCm > neckCm else { return nil }
            result = 495.0 / (
                1.0324
                - 0.19077 * log10(waistCm - neckCm)
                + 0.15456 * log10(heightCm)
            ) - 450.0
        case .female:
            guard hipCm > 0, waistCm + hipCm > neckCm else { return nil }
            result = 495.0 / (
                1.29579
                - 0.35004 * log10(waistCm + hipCm - neckCm)
                + 0.22100 * log10(heightCm)
            ) - 450.0
        }

        guard result.isFinite, result > 1, result < 75 else { return nil }
        return result
    }

    private var category: String? {
        guard let bodyFat = bodyFatPercent else { return nil }
        // American Council on Exercise style bands.
        let bands: [(upper: Double, label: String)] = sex == .male
            ? [(5, "Essential"), (13, "Athlete"), (17, "Fit"), (24, "Average"), (100, "Above average")]
            : [(13, "Essential"), (20, "Athlete"), (24, "Fit"), (31, "Average"), (100, "Above average")]
        return bands.first { bodyFat <= $0.upper }?.label
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Units", selection: $unit) {
                        ForEach(MeasureUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Measurements") {
                    measurementField("Height", value: $height)
                    measurementField("Neck", value: $neck)
                    measurementField("Waist", value: $waist)
                    if sex == .female {
                        measurementField("Hip", value: $hip)
                    }
                }

                Section {
                    if let bodyFat = bodyFatPercent {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(bodyFat.formatted(.number.precision(.fractionLength(1))))
                                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                                    .contentTransition(.numericText())
                                Text("%")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            if let category {
                                Text(category)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            save(bodyFat)
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save to Apple Health")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } else {
                        Text("Fill in the measurements above and the estimate appears here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Estimate")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Body Fat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                // Prefill height from Health, converted to the chosen unit.
                if height == 0,
                   let metres = try? await HealthKitService.shared.latestHeightMeters() {
                    height = (metres * 100) / unit.toCentimetres
                }
            }
            .onChange(of: unit) { old, new in
                // Re-express entered values instead of silently changing meaning.
                let factor = old.toCentimetres / new.toCentimetres
                height *= factor
                neck *= factor
                waist *= factor
                hip *= factor
            }
        }
    }

    private func measurementField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit.rawValue)
                .foregroundStyle(.secondary)
        }
    }

    private func save(_ percent: Double) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await HealthKitService.shared.saveBodyFat(percent: percent)
                onSaved()
                dismiss()
            } catch {
                errorMessage = "Couldn't save to Apple Health: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

#Preview("Log Weight") {
    LogWeightSheet {}
        .environment(AppSettings())
}

#Preview("Body Fat") {
    BodyFatCalculatorView {}
        .environment(AppSettings())
}
