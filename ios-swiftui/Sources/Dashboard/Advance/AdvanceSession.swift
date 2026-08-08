import Foundation
import Observation

struct AdvanceDraft: Equatable, Sendable {
    var txId: String?
    var employeeIds: Set<String> = []
    var amountPerPerson: Double = 0
    var meta = AdvanceLogic.Meta()

    var isPersisted: Bool {
        !(txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var estimatedTotal: Double? {
        let n = employeeIds.count
        guard n > 0, amountPerPerson > 0 else { return nil }
        return Double(n) * amountPerPerson
    }

    static func fromTransaction(_ t: Transaction) -> AdvanceDraft {
        AdvanceDraft(
            txId: t.id,
            employeeIds: Set(t.employeeIds ?? []),
            amountPerPerson: AdvanceLogic.amount(of: t),
            meta: AdvanceLogic.Meta.decode(workDetails: t.workDetails)
        )
    }
}

enum AdvanceSaveError: LocalizedError {
    case noEmployees
    case blockedEmployees
    case invalidAmount
    case missingBank
    case missingAccount

    var errorDescription: String? {
        switch self {
        case .noEmployees: return "กรุณาเลือกพนักงาน"
        case .blockedEmployees: return "ไม่สามารถเบิกให้คนขับรถหรือรับจ้างรายวันได้"
        case .invalidAmount: return "กรุณากรอกจำนวนเงินที่ขอเบิกต่อคนให้มากกว่า 0"
        case .missingBank: return "กรุณาเลือกธนาคาร"
        case .missingAccount: return "กรุณากรอกเลขบัญชี"
        }
    }
}

@MainActor
@Observable
final class AdvanceSession {
    var draft = AdvanceDraft()
    var todayAdvances: [Transaction] = []
    var eligibleEmployees: [Employee] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var confirmDeleteId: String?
    /// Keeps prior `work_details` JSON when editing / chaining batch creates.
    var workDetailsSeed: String?

    private(set) var dayKey: String
    private var skipExternalReload = 0

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(appState: AppState, force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        eligibleEmployees = AdvanceLogic.eligibleEmployees(from: appState.employees)
        todayAdvances = AdvanceLogic.dayAdvances(dayKey: dayKey, transactions: appState.transactions)
    }

    func clearDraft() {
        draft = AdvanceDraft()
        workDetailsSeed = nil
        clearStatus()
    }

    func loadForEdit(_ t: Transaction) {
        draft = AdvanceDraft.fromTransaction(t)
        workDetailsSeed = t.workDetails
        statusMessage = "โหลดคำขอเบิกเงินมาแก้ไข"
        isErrorStatus = false
    }

    func toggleEmployee(_ id: String) {
        if draft.isPersisted {
            // Edit mode keeps a single employee row.
            draft.employeeIds = [id]
        } else if draft.employeeIds.contains(id) {
            draft.employeeIds.remove(id)
        } else {
            draft.employeeIds.insert(id)
        }
        clearStatus()
    }

    func save(appState: AppState) async {
        guard !isSaving else { return }

        let ids = Array(draft.employeeIds).sorted()
        guard !ids.isEmpty else {
            setError(AdvanceSaveError.noEmployees.localizedDescription)
            return
        }

        let eligibleIds = Set(eligibleEmployees.map(\.id))
        if ids.contains(where: { !eligibleIds.contains($0) }) {
            setError(AdvanceSaveError.blockedEmployees.localizedDescription)
            return
        }

        let per = draft.amountPerPerson
        guard per > 0 else {
            setError(AdvanceSaveError.invalidAmount.localizedDescription)
            return
        }

        var meta = draft.meta
        meta.bank = meta.bank.trimmingCharacters(in: .whitespacesAndNewlines)
        meta.accountNumber = meta.accountNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if meta.paymentMethod == .transfer {
            if meta.bank.isEmpty {
                setError(AdvanceSaveError.missingBank.localizedDescription)
                return
            }
            if meta.accountNumber.isEmpty {
                setError(AdvanceSaveError.missingAccount.localizedDescription)
                return
            }
        } else {
            meta.bank = ""
            meta.accountNumber = ""
        }

        isSaving = true
        defer { isSaving = false }

        skipExternalReload += 1

        let existing = (draft.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty {
            // Update single existing row (edit).
            let empId = ids[0]
            let name = AdvanceLogic.employeeName(id: empId, employees: eligibleEmployees + appState.employees)
            let payload = AdvanceWriter.payload(
                id: existing,
                dateYmd: dayKey,
                employeeId: empId,
                employeeName: name,
                amountPerPerson: per,
                meta: meta,
                existingWorkDetails: workDetailsSeed,
                omitCreatedAt: true
            )
            _ = await AdvanceWriter.persist(payload: payload, wasPersisted: true)
            clearDraft()
            setOk("บันทึกการแก้ไขคำขอเบิกเงินแล้ว")
            reload(appState: appState, force: true)
            return
        }

        // Create one transaction per employee (Flutter parity).
        var seed = workDetailsSeed
        for (i, empId) in ids.enumerated() {
            let name = AdvanceLogic.employeeName(id: empId, employees: eligibleEmployees + appState.employees)
            let id = AdvanceWriter.newId(index: i, employeeId: empId)
            let payload = AdvanceWriter.payload(
                id: id,
                dateYmd: dayKey,
                employeeId: empId,
                employeeName: name,
                amountPerPerson: per,
                meta: meta,
                existingWorkDetails: i == 0 ? seed : nil,
                omitCreatedAt: false
            )
            _ = await AdvanceWriter.persist(payload: payload, wasPersisted: false)
            seed = payload.workDetails
        }
        // Keep last work_details JSON for the next batch (Flutter `_advanceWorkDetailsSeed`).
        let keptSeed = seed
        draft = AdvanceDraft()
        workDetailsSeed = keptSeed
        setOk("ส่งคำขอเบิกเงินแล้ว (\(ids.count) รายการ)")
        reload(appState: appState, force: true)
    }

    func delete(id: String, appState: AppState) async {
        skipExternalReload += 1
        _ = await AdvanceWriter.delete(id: id)
        if draft.txId == id { clearDraft() }
        setOk("ลบคำขอเบิกเงินแล้ว")
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
