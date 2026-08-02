import Foundation
import SwiftUI

// MARK: - Enums

enum TaskScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case yearly = "Yearly"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "รายวัน"
        case .weekly: return "รายสัปดาห์"
        case .monthly: return "รายเดือน"
        case .yearly: return "รายปี"
        }
    }

    var shortLabel: String {
        switch self {
        case .daily: return "วันนี้"
        case .weekly: return "สัปดาห์"
        case .monthly: return "เดือน"
        case .yearly: return "ปี"
        }
    }

    var systemImage: String {
        switch self {
        case .daily: return "sun.max.fill"
        case .weekly: return "calendar.day.timeline.left"
        case .monthly: return "calendar"
        case .yearly: return "calendar.badge.clock"
        }
    }

    /// How many days from a task's due date the scope still counts as active.
    var spanDays: Int {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .monthly: return 31
        case .yearly: return 366
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case todo = "Todo"
    case inProgress = "InProgress"
    case done = "Done"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: return "ยังไม่ทำ"
        case .inProgress: return "กำลังทำ"
        case .done: return "เสร็จแล้ว"
        }
    }

    var color: Color {
        switch self {
        case .todo: return AppTheme.inkMuted
        case .inProgress: return AppTheme.warning
        case .done: return AppTheme.income
        }
    }

    var detail: String {
        switch self {
        case .todo: return "ยังไม่ได้เริ่มลงมือ"
        case .inProgress: return "เริ่มแล้ว ยังไม่เสร็จ"
        case .done: return "ปิดงานเรียบร้อย"
        }
    }

    var systemImage: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .done: return "checkmark.circle.fill"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case urgent = "Urgent"
    case high = "High"
    case normal = "Normal"
    case low = "Low"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .urgent: return "ด่วนมาก"
        case .high: return "สำคัญ"
        case .normal: return "ปกติ"
        case .low: return "ไว้ทีหลัง"
        }
    }

    var color: Color {
        switch self {
        case .urgent: return AppTheme.expense
        case .high: return AppTheme.warning
        case .normal: return AppTheme.info
        case .low: return AppTheme.slate
        }
    }

    var systemImage: String {
        switch self {
        case .urgent: return "exclamationmark.2"
        case .high: return "exclamationmark"
        case .normal: return "equal"
        case .low: return "arrow.down"
        }
    }

    /// Lower sorts first.
    var sortRank: Int {
        switch self {
        case .urgent: return 0
        case .high: return 1
        case .normal: return 2
        case .low: return 3
        }
    }
}

enum TaskVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case shared = "public"
    case personal = "private"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shared: return "สาธารณะ"
        case .personal: return "ส่วนตัว"
        }
    }

    var systemImage: String {
        switch self {
        case .shared: return "person.2.fill"
        case .personal: return "lock.fill"
        }
    }
}

// MARK: - Task row

/// One row of `public.tasks`. Named `WorkTask` to avoid colliding with Swift Concurrency's `Task`.
struct WorkTask: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var note: String?
    var ownerAdminId: String
    var ownerName: String?
    var assigneeAdminId: String?
    var assigneeName: String?
    var visibility: TaskVisibility
    var scope: TaskScope
    /// Anchor day in `yyyy-MM-dd` (Bangkok), matching the rest of the app's date keys.
    var dueDate: String
    var remindAt: String?
    var status: TaskStatus
    var priority: TaskPriority
    var isFocus: Bool
    var focusOrder: Int?
    /// Optional hard deadline (`timestamptz`); independent of the soft `due_date` scope window.
    var deadline: String?
    /// When the task was handed to `assigneeAdminId`.
    var assignedAt: String?
    /// When the assignee acknowledged it; `nil` keeps it in their inbox.
    var assigneeSeenAt: String?
    var completedAt: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, note, visibility, scope, status, priority, deadline
        case ownerAdminId = "owner_admin_id"
        case ownerName = "owner_name"
        case assigneeAdminId = "assignee_admin_id"
        case assigneeName = "assignee_name"
        case dueDate = "due_date"
        case remindAt = "remind_at"
        case isFocus = "is_focus"
        case focusOrder = "focus_order"
        case assignedAt = "assigned_at"
        case assigneeSeenAt = "assignee_seen_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static func new(
        ownerAdminId: String,
        ownerName: String?,
        dueDate: String = DashboardAggregations.todayYMD()
    ) -> WorkTask {
        WorkTask(
            id: UUID().uuidString,
            title: "",
            note: nil,
            ownerAdminId: ownerAdminId,
            ownerName: ownerName,
            assigneeAdminId: nil,
            assigneeName: nil,
            visibility: .shared,
            scope: .daily,
            dueDate: dueDate,
            remindAt: nil,
            status: .todo,
            priority: .normal,
            isFocus: false,
            focusOrder: nil,
            deadline: nil,
            assignedAt: nil,
            assigneeSeenAt: nil,
            completedAt: nil,
            createdAt: TaskDates.nowISO(),
            updatedAt: TaskDates.nowISO()
        )
    }
}

extension WorkTask {
    var isDone: Bool { status == .done }

    var assigneeInitials: String {
        let name = (assigneeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    /// Last day this task still shows up under its scope, e.g. a weekly task spans 7 days.
    var scopeEndDate: String {
        DashboardAggregations.shiftDateStr(dueDate, deltaDays: scope.spanDays - 1)
    }

    func covers(day: String) -> Bool {
        day >= dueDate && day <= scopeEndDate
    }

    /// True when the task is unfinished and its whole window is already in the past.
    func isOverdue(today: String = DashboardAggregations.todayYMD()) -> Bool {
        !isDone && scopeEndDate < today
    }

    /// How many calendar days since `scopeEndDate` ended, for the carry-over badge.
    func carryOverDays(to day: String = DashboardAggregations.todayYMD()) -> Int? {
        guard isOverdue(today: day) else { return nil }
        return max(1, DashboardAggregations.countInclusiveDays(scopeEndDate, day) - 1)
    }

    var remindDate: Date? {
        guard let remindAt else { return nil }
        return TaskDates.parseISO(remindAt)
    }

    var deadlineDate: Date? {
        deadline.flatMap(TaskDates.parseISO)
    }

    /// Past the deadline and still unfinished.
    func isPastDeadline(now: Date = Date()) -> Bool {
        guard !isDone, let d = deadlineDate else { return false }
        return d < now
    }

    var assignedDate: Date? {
        assignedAt.flatMap(TaskDates.parseISO)
    }

    /// Someone else handed this task to `adminId` and they have not acknowledged it yet.
    func isNewAssignment(for adminId: String) -> Bool {
        guard !adminId.isEmpty, !isDone else { return false }
        return assigneeAdminId == adminId
            && ownerAdminId != adminId
            && assigneeSeenAt == nil
    }
}

// MARK: - Date helpers

/// ISO-8601 conversions for the timestamptz columns on `tasks`.
enum TaskDates {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func nowISO() -> String {
        iso.string(from: Date())
    }

    static func toISO(_ date: Date) -> String {
        iso.string(from: date)
    }

    static func parseISO(_ value: String) -> Date? {
        if let date = iso.date(from: value) { return date }
        if let date = isoFractional.date(from: value) { return date }
        guard let clamped = clampingFractionalSeconds(value) else { return nil }
        return isoFractional.date(from: clamped) ?? iso.date(from: clamped)
    }

    /// Postgres serializes `timestamptz` with microseconds (`...:46.825648+00:00`) but
    /// `ISO8601DateFormatter` only accepts milliseconds, so trim the extra digits.
    private static func clampingFractionalSeconds(_ value: String) -> String? {
        guard let dot = value.firstIndex(of: ".") else { return nil }
        let firstDigit = value.index(after: dot)
        var afterDigits = firstDigit
        while afterDigits < value.endIndex, value[afterDigits].isNumber {
            afterDigits = value.index(after: afterDigits)
        }
        guard value.distance(from: firstDigit, to: afterDigits) > 3 else { return nil }
        let keepEnd = value.index(dot, offsetBy: 4)
        return String(value[value.startIndex..<keepEnd]) + String(value[afterDigits...])
    }

    /// Midday on the given `yyyy-MM-dd`, used as the default reminder time for a new task.
    static func middayOf(_ ymd: String) -> Date {
        wallClockOf(ymd, hour: 12)
    }

    /// 17:00 on the given `yyyy-MM-dd`, used as the default deadline for a new task.
    static func eveningOf(_ ymd: String) -> Date {
        wallClockOf(ymd, hour: 17)
    }

    private static func wallClockOf(_ ymd: String, hour: Int) -> Date {
        let cal = DashboardAggregations.gregorian
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date() }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = hour
        return cal.date(from: comps) ?? Date()
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "d MMM HH:mm น."
        return f.string(from: date)
    }

    /// Clock-only label for deadline chips, e.g. "15:00".
    static func clockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
