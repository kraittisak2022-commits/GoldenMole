import Foundation
import Observation

struct LeaveDraft: Equatable, Sendable {
    var txId: String?
    var leaveType: LeaveLogic.LeaveType = .personal
    var isHalfDay = false
    var halfPart: LeaveLogic.HalfPart = .morning
    var startYmd: String
    var endYmd: String
    var employeeIds: Set<String> = []
    var reason: String = ""

    var isPersisted: Bool {
        !(txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var rangeDayCount: Int {
        LeaveLogic.inclusiveDayCount(startYmd: startYmd, endYmd: endYmd)
    }

    var effectiveDays: Double {
        isHalfDay ? 0.5 : Double(rangeDayCount)
    }

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        startYmd = dayKey
        endYmd = dayKey
    }

    static func fromTransaction(_ t: Transaction, fallbackDay: String) -> LeaveDraft {
        let start = String(t.date.prefix(10))
        let isHalf = LeaveLogic.isHalfDay(transaction: t)
        let days = t.leaveDays ?? 1
        var draft = LeaveDraft(dayKey: start.isEmpty ? fallbackDay : start)
        draft.txId = t.id
        draft.leaveType = LeaveLogic.LeaveType.from(subCategory: t.subCategory)
        draft.isHalfDay = isHalf
        draft.halfPart = LeaveLogic.HalfPart.from(workDetails: t.workDetails)
        draft.startYmd = start.isEmpty ? fallbackDay : start
        draft.endYmd = LeaveLogic.endYmd(startYmd: draft.startYmd, leaveDays: days, isHalfDay: isHalf)
        draft.employeeIds = Set(t.employeeIds ?? [])
        draft.reason = LeaveLogic.resolvedReason(t)
        return draft
    }
}

enum LeaveSaveError: LocalizedError {
    case noEmployees
    case blockedEmployees
    case invalidRange
    case invalidHalfPart

    var errorDescription: String? {
        switch self {
        case .noEmployees: return "กรุณาเลือกพนักงาน"
        case .blockedEmployees: return "ไม่สามารถบันทึกลาให้คนขับรถหรือรับจ้างรายวันได้"
        case .invalidRange: return "กรุณาเลือกช่วงวันลาให้ถูกต้อง"
        case .invalidHalfPart: return "กรุณาเลือกลาครึ่งเช้าหรือครึ่งบ่าย"
        }
    }
}

@MainActor
@Observable
final class LeaveSession {
    var draft: LeaveDraft
    var coveringLeaves: [Transaction] = []
    var eligibleEmployees: [Employee] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var showDateRangeSheet = false
    var confirmDeleteId: String?

    private(set) var dayKey: String
    private var skipExternalReload = 0

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
        self.draft = LeaveDraft(dayKey: dayKey)
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(appState: AppState, force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        eligibleEmployees = LeaveLogic.eligibleEmployees(from: appState.employees)
        coveringLeaves = LeaveLogic.leavesCovering(dayKey: dayKey, transactions: appState.transactions)
    }

    func clearDraft() {
        draft = LeaveDraft(dayKey: dayKey)
        clearStatus()
    }

    func loadForEdit(_ t: Transaction) {
        draft = LeaveDraft.fromTransaction(t, fallbackDay: dayKey)
        statusMessage = "โหลดรายการเพื่อแก้ไข — กดบันทึกการแก้ไขเมื่อเสร็จ"
        isErrorStatus = false
    }

    func toggleEmployee(_ id: String) {
        if draft.employeeIds.contains(id) {
            draft.employeeIds.remove(id)
        } else {
            draft.employeeIds.insert(id)
        }
        clearStatus()
    }

    func setHalfDay(_ half: Bool) {
        draft.isHalfDay = half
        if half {
            draft.endYmd = draft.startYmd
            draft.halfPart = .morning
        }
        clearStatus()
    }

    func applyDateRange(start: Date, end: Date) {
        let startY = DashboardAggregations.formatYMD(start)
        var endY = DashboardAggregations.formatYMD(end)
        if endY < startY { endY = startY }
        draft.startYmd = startY
        if draft.isHalfDay {
            draft.endYmd = startY
        } else {
            draft.endYmd = endY
        }
        clearStatus()
    }

    func save(appState: AppState) async {
        guard !isSaving else { return }

        let ids = Array(draft.employeeIds)
        guard !ids.isEmpty else {
            setError(LeaveSaveError.noEmployees.localizedDescription)
            return
        }

        let eligibleIds = Set(eligibleEmployees.map(\.id))
        if ids.contains(where: { !eligibleIds.contains($0) }) {
            setError(LeaveSaveError.blockedEmployees.localizedDescription)
            return
        }

        if draft.isHalfDay {
            // halfPart always valid via enum
        } else if draft.rangeDayCount <= 0 {
            setError(LeaveSaveError.invalidRange.localizedDescription)
            return
        }

        isSaving = true
        defer { isSaving = false }

        let existing = (draft.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = existing.isEmpty ? LeaveWriter.newId() : existing
        let payload = LeaveWriter.payload(
            id: id,
            startYmd: draft.startYmd,
            leaveType: draft.leaveType,
            employeeIds: ids,
            reason: draft.reason,
            effectiveDays: draft.effectiveDays,
            isHalfDay: draft.isHalfDay,
            halfPart: draft.halfPart,
            endYmd: draft.endYmd,
            omitCreatedAt: !existing.isEmpty
        )

        skipExternalReload += 1
        _ = await LeaveWriter.persist(payload: payload, wasPersisted: !existing.isEmpty)
        clearDraft()
        setOk(existing.isEmpty ? "บันทึกลางานสำเร็จ" : "บันทึกการแก้ไขลางานแล้ว")
        reload(appState: appState, force: true)
    }

    func delete(id: String, appState: AppState) async {
        skipExternalReload += 1
        _ = await LeaveWriter.delete(id: id)
        if draft.txId == id { clearDraft() }
        setOk("ลบรายการลางานแล้ว")
        reload(appState: appState, force: true)
    }

    private func setOk(_ message: String) {
        statusMessage = message
        isErrorStatus = false
    }

    private func setError(_ message: String) {
        statusMessage = message
        isErrorStatus = true
    }

    private func clearStatus() {
        statusMessage = nil
        isErrorStatus = false
    }
}
