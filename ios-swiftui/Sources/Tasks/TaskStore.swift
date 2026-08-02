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
    /// Signed-in admin, used to build the assignment inbox without threading the id everywhere.
    var currentAdminId = ""

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
            let knownInbox = Set(inboxTasks().map(\.id))
            if tasks != rows { tasks = rows }
            errorMessage = nil
            lastLoadedAt = Date()
            await announceNewAssignments(excluding: knownInbox)
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

    /// Unfinished tasks whose own scope ended before `day` — shown as carry-overs without rewriting `due_date`.
    func carryOverTasks(to day: String, adminId: String) -> [WorkTask] {
        Self.sorted(visible(to: adminId).filter { !$0.isDone && $0.scopeEndDate < day })
    }

    // MARK: - Assignment inbox

    /// Tasks handed to the signed-in admin by someone else and not acknowledged yet, newest first.
    func inboxTasks() -> [WorkTask] {
        tasks
            .filter { $0.isNewAssignment(for: currentAdminId) }
            .sorted { ($0.assignedAt ?? $0.createdAt ?? "") > ($1.assignedAt ?? $1.createdAt ?? "") }
    }

    var inboxCount: Int { inboxTasks().count }

    /// Clears the inbox badge for these tasks by stamping `assignee_seen_at`.
    func markAssignmentSeen(_ items: [WorkTask]) async {
        let stamp = TaskDates.nowISO()
        for task in items where task.assigneeSeenAt == nil {
            var updated = task
            updated.assigneeSeenAt = stamp
            updated.updatedAt = stamp
            applyLocally(updated)
            await write(updated)
        }
    }

    /// Fires one local alert per assignment that appeared since the previous load.
    private func announceNewAssignments(excluding known: Set<String>) async {
        guard !currentAdminId.isEmpty else { return }
        for task in inboxTasks() where !known.contains(task.id) {
            await TaskReminderScheduler.shared.notifyAssignment(task)
        }
    }

    static func sorted(_ items: [WorkTask]) -> [WorkTask] {
        items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if a.isFocus != b.isFocus { return a.isFocus }
            if a.isFocus, b.isFocus, a.focusOrder != b.focusOrder {
                return (a.focusOrder ?? Int.max) < (b.focusOrder ?? Int.max)
            }
            if a.priority != b.priority { return a.priority.sortRank < b.priority.sortRank }
            // Earlier deadlines first; past-deadline work floats above open-ended tasks.
            switch (a.deadlineDate, b.deadlineDate) {
            case let (da?, db?) where da != db: return da < db
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
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
        updated = stampAssignment(updated)

        applyLocally(updated)
        await TaskReminderScheduler.shared.sync(updated)
        await write(updated)
    }

    /// Saves many tasks, respecting the per-day focus quota. Surplus focus pins become normal tasks
    /// and `noticeMessage` explains how many were pinned.
    func saveAll(_ tasks: [WorkTask], adminId: String) async {
        guard !tasks.isEmpty else { return }

        var prepared = tasks.map { task -> WorkTask in
            var t = task
            t.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            t.updatedAt = TaskDates.nowISO()
            if t.createdAt == nil { t.createdAt = t.updatedAt }
            t.completedAt = t.status == .done ? (task.completedAt ?? TaskDates.nowISO()) : nil
            if !t.isFocus { t.focusOrder = nil }
            return stampAssignment(t)
        }

        let focusCandidates = prepared.filter(\.isFocus)
        if !focusCandidates.isEmpty {
            // Batch create usually shares one due date; allocate slots per distinct day.
            var slotsByDay: [String: Int] = [:]
            var nextOrderByDay: [String: Int] = [:]
            for day in Set(prepared.map(\.dueDate)) {
                let current = focusTasks(on: day, adminId: adminId)
                // Exclude tasks we are about to overwrite so re-saving an already-focused row
                // does not consume an extra slot against itself.
                let rewriting = Set(prepared.filter { $0.dueDate == day }.map(\.id))
                let occupied = current.filter { !rewriting.contains($0.id) }.count
                slotsByDay[day] = max(0, Self.focusLimit - occupied)
                nextOrderByDay[day] = (current
                    .filter { !rewriting.contains($0.id) }
                    .compactMap(\.focusOrder)
                    .max() ?? 0) + 1
            }

            var pinned = 0
            prepared = prepared.map { task in
                guard task.isFocus else { return task }
                var t = task
                let day = t.dueDate
                let slots = slotsByDay[day, default: 0]
                if slots > 0 {
                    t.focusOrder = nextOrderByDay[day, default: 1]
                    nextOrderByDay[day, default: 1] += 1
                    slotsByDay[day] = slots - 1
                    pinned += 1
                } else {
                    t.isFocus = false
                    t.focusOrder = nil
                }
                return t
            }

            let requested = focusCandidates.count
            if pinned < requested {
                noticeMessage = pinned == 0
                    ? "โฟกัสเต็มแล้ว (\(Self.focusLimit) งาน) — บันทึกเป็นงานปกติทั้งหมด"
                    : "ปักโฟกัสได้ \(pinned) จาก \(requested) งาน (เพดาน \(Self.focusLimit)/วัน)"
            }
        }

        for task in prepared {
            applyLocally(task)
            await TaskReminderScheduler.shared.sync(task)
            await write(task)
        }
    }

    func setStatus(_ task: WorkTask, to status: TaskStatus) async {
        guard task.status != status else { return }
        var updated = task
        updated.status = status
        updated.completedAt = status == .done ? (task.completedAt ?? TaskDates.nowISO()) : nil
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

    /// Marks a hand-off so the new assignee gets an inbox entry, and keeps the stamps untouched
    /// when the assignee did not change. Self-assigned and unassigned tasks never enter an inbox.
    private func stampAssignment(_ task: WorkTask) -> WorkTask {
        var t = task
        let previous = tasks.first { $0.id == t.id }
        let newAssignee = (t.assigneeAdminId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let oldAssignee = (previous?.assigneeAdminId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if newAssignee.isEmpty {
            t.assignedAt = nil
            t.assigneeSeenAt = nil
            return t
        }
        if newAssignee != oldAssignee {
            t.assignedAt = TaskDates.nowISO()
            t.assigneeSeenAt = newAssignee == t.ownerAdminId ? TaskDates.nowISO() : nil
        } else {
            t.assignedAt = previous?.assignedAt ?? t.assignedAt
            t.assigneeSeenAt = previous?.assigneeSeenAt ?? t.assigneeSeenAt
        }
        return t
    }

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
