import SwiftUI
import UIKit
import UserNotifications

/// Daily goal and reminder schedule for the Water tab.
struct WaterSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private static let intervalOptions = [30, 45, 60, 90, 120, 180]

    /// Changing any of these rebuilds the notification schedule.
    private var scheduleSignature: String {
        [
            settings.waterRemindersEnabled ? "1" : "0",
            "\(settings.reminderStartHour)",
            "\(settings.reminderEndHour)",
            "\(settings.reminderIntervalMinutes)",
            "\(Int(settings.dailyWaterGoalML))",
        ].joined(separator: "-")
    }

    private var slots: [(hour: Int, minute: Int)] {
        NotificationService.reminderSlots(
            startHour: settings.reminderStartHour,
            endHour: settings.reminderEndHour,
            intervalMinutes: settings.reminderIntervalMinutes
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                goalSection
                reminderSection
                if settings.waterRemindersEnabled { scheduleSection }
                if authorizationStatus == .denied { deniedSection }
            }
            .navigationTitle("Water")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                authorizationStatus = await NotificationService.authorizationStatus()
            }
            .onChange(of: scheduleSignature) {
                Task {
                    await NotificationService.rescheduleWaterReminders(using: settings)
                    authorizationStatus = await NotificationService.authorizationStatus()
                }
            }
        }
    }

    // MARK: - Sections

    private var goalSection: some View {
        Section {
            Stepper(
                value: Binding(
                    get: { settings.dailyWaterGoalML },
                    set: { settings.dailyWaterGoalML = max(250, $0) }
                ),
                in: 250...8_000,
                step: settings.volumeUnit == .ounces ? 236.588 : 250
            ) {
                HStack {
                    Text("Daily goal")
                    Spacer()
                    Text(settings.formattedVolume(fromMillilitres: settings.dailyWaterGoalML))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            Text("A common starting point is about half your bodyweight in pounds, in fluid ounces.")
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle("Remind me to drink", isOn: Binding(
                get: { settings.waterRemindersEnabled },
                set: { settings.waterRemindersEnabled = $0 }
            ))

            if settings.waterRemindersEnabled {
                Picker("Start", selection: Binding(
                    get: { settings.reminderStartHour },
                    set: { settings.reminderStartHour = min($0, settings.reminderEndHour - 1) }
                )) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }

                Picker("End", selection: Binding(
                    get: { settings.reminderEndHour },
                    set: { settings.reminderEndHour = max($0, settings.reminderStartHour + 1) }
                )) {
                    ForEach(1..<24, id: \.self) { hour in
                        Text(Self.hourLabel(hour)).tag(hour)
                    }
                }

                Picker("Every", selection: Binding(
                    get: { settings.reminderIntervalMinutes },
                    set: { settings.reminderIntervalMinutes = $0 }
                )) {
                    ForEach(Self.intervalOptions, id: \.self) { minutes in
                        Text(Self.intervalLabel(minutes)).tag(minutes)
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Reminders repeat daily and keep working whether or not the app is open.")
        }
    }

    private var scheduleSection: some View {
        Section {
            Text(slots.map { Self.timeLabel(hour: $0.hour, minute: $0.minute) }
                .joined(separator: "  ·  "))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("\(slots.count) reminders per day")
        }
    }

    private var deniedSection: some View {
        Section {
            Label("Notifications are turned off for Vitals", systemImage: "bell.slash")
                .foregroundStyle(.orange)
                .font(.footnote)

            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
        }
    }

    // MARK: - Formatting

    private static func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }

    private static func hourLabel(_ hour: Int) -> String {
        timeLabel(hour: hour, minute: 0)
    }

    private static func timeLabel(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        guard let date = Calendar.current.date(from: components) else {
            return "\(hour):\(String(format: "%02d", minute))"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    WaterSettingsView()
        .environment(AppSettings())
}
