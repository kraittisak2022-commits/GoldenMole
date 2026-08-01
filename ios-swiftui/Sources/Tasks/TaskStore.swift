import Foundation
import Observation

/// Loads and mutates the `tasks` table. Mutations apply locally first so the UI stays
/// responsive, then write to Supabase; a failed write reloads to drop the optimistic change.
@MainActor
@Observable
final class TaskStore {
    /// Most "งานสำคัญ" a single day's focus card will hold.
    static let focusLimit = 5

    var tasks: [WorkTask] = []
    /// Admin accounts available in the assignee picker.
    var admins: [AdminUser] = []
    var isLoading = false
    var errorMessage: String?
    /// Set when a focus toggle is rejected for exceeding `focusLimit`.
    var noticeMessage: String?

    private(set) var lastLoadedAt: Date?

    @ObservationIgnored private var dataService: SupabaseService?

    func configure(dataService: SupabaseService) {
        self.dataService = dataService
    }

    // MARK: - Loading

    func load() async {
        guard let dataService else { return }
        if tasks.isEmpty { isLoading = true }
        do {
            let rows = try await dataService.fetchTasks()
            if tasks != rows { tasks = rows }
            errorMessage = nil
            lastLoadedAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Called when the tab appears. Refetches only when the cache is cold or a minute stale,
    /// so switching tabs repeatedly doesn't hammer the API.
    func loadIfNeeded() async {
        if let lastLoadedAt, Date().timeIntervalSince(lastLoadedAt) < 60 { return }
        await load()
        await loadAdmins()
    }

    /// Best-effort; an empty list just means the assignee picker offers "ไม่ระบุ" only.
    func loadAdmins() async {
        guard let dataService, admins.isEmpty else { return }
        admins = (try? await dataService.fetchAdmins()) ?? []
    }

    // MARK: - Visibility

    /// Public tasks plus the caller's own private ones. Privacy is enforced here rather than
    /// in RLS because the app authenticates against `admin_users`, not Supabase Auth.
    func visible(to adminId: String) -> [WorkTask] {
        tasks.filter { $0.visibility == .shared || $0.ownerAdminId == adminId }
    }

    /// Visible tasks whose scope window contains `day`, ordered for display.
    func dayTasks(on day: String, adminId: String) -> [WorkTask] {
        Self.sorted(visible(to: adminId).filter { $0.covers(day: day) })
    }

    func focusTasks(on day: String, adminId: String) -> [WorkTask] {
        visible(to: adminId)
            .filter { $0.isFocus && $0.dueDate == day }
            .sorted { ($0.focusOrder ?? Int.max, $0.title) < ($1.focusOrder ?? Int.max, $1.title) }
    }

    /// Unfinished tasks whose window closed before today.
    func overdueTasks(adminId: String, today: String = DashboardAggregations.todayYMD()) -> [WorkTask] {
        Self.sorted(visible(to: adminId).filter { $0.isOverdue(today: today) })
    }

    static func sorted(_ items: [WorkTask]) -> [WorkTask] {
        items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isFocus != b.isFocus { return a.isFocus }
            if a.isFocus, b.isFocus, a.focusOrder != b.focusOrder {
                return (a.focusOrder ?? Int.max) < (b.focusOrder ?? Int.max)
            }
            if a.priority != b.priority { return a.priority.sortRank < b.priority.sortRank }
            if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    // MARK: - Mutations

    func save(_ task: WorkTask) async {
        var updated = task
        updated.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = TaskDates.nowISO()
        if updated.createdAt == nil { updated.createdAt = updated.updatedAt }
        updated.completedAt = updated.status == .done ? (task.completedAt ?? TaskDates.nowISO()) : nil
        if !updated.isFocus { updated.focusOrder = nil }

        applyLocally(updated)
        await TaskReminderScheduler.shared.sync(updated)
        await write(updated)
    }

    func advanceStatus(_ task: WorkTask) async {
        var updated = task
        updated.status = task.status.next
        updated.completedAt = updated.status == .done ? TaskDates.nowISO() : nil
        updated.updatedAt = TaskDates.nowISO()

        applyLocally(updated)
        await TaskReminderScheduler.shared.sync(updated)
        await write(updated)
    }

    /// Pins or unpins a task on its own due date's focus list, capped at `focusLimit`.
    func toggleFocus(_ task: WorkTask, adminId: String) async {
        var updated = task

        if task.isFocus {
            updated.isFocus = false
            updated.focusOrder = nil
        } else {
            let current = focusTasks(on: task.dueDate, adminId: adminId)
            guard current.count < Self.focusLimit else {
                noticeMessage = "โฟกัสเต็มแล้ว (\(Self.focusLimit) งาน) — เอางานออกก่อน 1 อย่าง"
                return
            }
            updated.isFocus = true
            updated.focusOrder = (current.compactMap(\.focusOrder).max() ?? 0) + 1
        }
        updated.updatedAt = TaskDates.nowISO()

        applyLocally(updated)
        await write(updated)
    }

    func delete(_ task: WorkTask) async {
        guard let dataService else { return }
        let snapshot = tasks
        tasks.removeAll { $0.id == task.id }
        TaskReminderScheduler.shared.cancel(taskId: task.id)

        do {
            try await dataService.deleteTask(id: task.id)
        } catch {
            tasks = snapshot
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func applyLocally(_ task: WorkTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
        } else {
            tasks.insert(task, at: 0)
        }
    }

    private func write(_ task: WorkTask) async {
        guard let dataService else { return }
        do {
            try await dataService.upsertTask(task)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await load()
        }
    }
}
