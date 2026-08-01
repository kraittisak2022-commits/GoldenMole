import Foundation
import UserNotifications

/// Local notifications for task reminders.
///
/// These fire only on the device that scheduled them — assigning a task to someone else
/// does not notify their phone, which would need push infrastructure the app doesn't have.
@MainActor
final class TaskReminderScheduler {
    static let shared = TaskReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    /// nil until the first request; avoids re-prompting on every save.
    private var isAuthorized: Bool?

    private init() {}

    /// Asks once, then reuses the answer for the rest of the session.
    @discardableResult
    func ensureAuthorization() async -> Bool {
        if let isAuthorized { return isAuthorized }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        case .denied:
            isAuthorized = false
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            isAuthorized = false
        }
        return isAuthorized ?? false
    }

    /// Schedules (or reschedules) the reminder for a task. Finished, past, or reminder-less
    /// tasks simply get their pending notification cleared.
    func sync(_ task: WorkTask) async {
        cancel(taskId: task.id)

        guard !task.isDone,
              let fireDate = task.remindDate,
              fireDate > Date()
        else { return }

        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "เตือนงาน"
        content.body = task.title
        if let note = task.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            content.subtitle = note
        }
        content.sound = .default

        let components = DashboardAggregations.gregorian.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: task.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    func cancel(taskId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: taskId)])
    }

    private static func identifier(for taskId: String) -> String {
        "task.reminder.\(taskId)"
    }
}
