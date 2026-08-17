import Foundation
import UserNotifications

/// Schedules the repeating "drink water" nudges.
///
/// Reminders are modelled as one repeating daily calendar notification per slot
/// in the window, which means they keep firing without the app ever running.
enum NotificationService {
    private static let waterPrefix = "vitals.water.reminder."

    static var center: UNUserNotificationCenter { .current() }

    /// Returns `true` if the user allowed notifications.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Wipes and rebuilds the water reminder schedule from current settings.
    static func rescheduleWaterReminders(using settings: AppSettings) async {
        await cancelWaterReminders()

        guard settings.waterRemindersEnabled else { return }
        guard await requestAuthorization() else { return }

        let slots = reminderSlots(
            startHour: settings.reminderStartHour,
            endHour: settings.reminderEndHour,
            intervalMinutes: settings.reminderIntervalMinutes
        )

        let goalText = settings.formattedVolume(fromMillilitres: settings.dailyWaterGoalML)

        for (index, slot) in slots.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time for water"
            content.body = "Log a glass to stay on track for \(goalText) today."
            content.sound = .default
            content.interruptionLevel = .active

            var components = DateComponents()
            components.hour = slot.hour
            components.minute = slot.minute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: "\(waterPrefix)\(index)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func cancelWaterReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(waterPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Every reminder time between `startHour` and `endHour`, inclusive of the
    /// start and capped at 32 notifications to stay well under the iOS limit.
    static func reminderSlots(
        startHour: Int,
        endHour: Int,
        intervalMinutes: Int
    ) -> [(hour: Int, minute: Int)] {
        guard intervalMinutes > 0, endHour > startHour else { return [] }

        var slots: [(hour: Int, minute: Int)] = []
        var minutesFromMidnight = startHour * 60
        let endMinutes = endHour * 60

        while minutesFromMidnight <= endMinutes && slots.count < 32 {
            slots.append((minutesFromMidnight / 60, minutesFromMidnight % 60))
            minutesFromMidnight += intervalMinutes
        }
        return slots
    }
}
