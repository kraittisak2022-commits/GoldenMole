import Foundation
import UserNotifications

/// Local notifications for task reminders and assignment hand-offs.
///
/// Everything here fires on the device that schedules it. Assignment alerts therefore appear
/// when the assignee's own app loads the task, not the moment someone else assigns it — real
/// push delivery would need APNs infrastructure the app doesn't have.
@MainActor
final class TaskReminderScheduler {
    static let shared = TaskReminderScheduler()

    private let center = UNUserNotificationCenter.current()
    /// nil until the first request; avoids re-prompting on every save.
    private var isAuthorized: Bool?
    /// Assignment alerts already fired this session, so a refresh loop can't spam the same task.
    private var announcedAssignments: Set<String> = []

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

    /// Alerts the assignee once, right when their app first sees the hand-off.
    func notifyAssignment(_ task: WorkTask) async {
        guard !announcedAssignments.contains(task.id) else { return }
        announcedAssignments.insert(task.id)

        guard await ensureAuthorization() else { return }

        let content = UNMutableNotificationContent()
        content.title = "ได้รับมอบหมายงานใหม่"
        content.body = task.title
        if let owner = task.ownerName?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            content.subtitle = "จาก \(owner)"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: Self.assignmentIdentifier(for: task.id),
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func cancel(taskId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: taskId)])
    }

    private static func identifier(for taskId: String) -> String {
        "task.reminder.\(taskId)"
    }

    private static func assignmentIdentifier(for taskId: String) -> String {
        "task.assigned.\(taskId)"
    }
}
