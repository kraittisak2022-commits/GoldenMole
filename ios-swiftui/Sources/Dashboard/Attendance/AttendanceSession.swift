import Foundation
import Observation

@MainActor
@Observable
final class AttendanceSession {
    var section: AttendanceSection?
    var assignments: [AttendanceBucket: Set<String>] = AttendanceLogic.emptyAssignments()
    var pickedIds: Set<String> = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false

    private(set) var dayKey: String
    private var sandLaborTxId: String?
    private var sandLeaveTxId: String?
    private var driverLaborTxId: String?
    private var driverLeaveTxId: String?
    private var legacyLaborTxId: String?
    private var legacyLeaveTxId: String?
    private var daysWorked: [String: Int] = [:]
    private var skipExternalReload = 0

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(
        transactions: [Transaction],
        employees: [Employee],
        force: Bool = false
    ) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }
        let byId = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0) })
        let board = AttendanceLogic.hydrate(dayTransactions: dayTx, employeesById: byId)
        assignments = board.assignments
        sandLaborTxId = board.sandLaborTxId
        sandLeaveTxId = board.sandLeaveTxId
        driverLaborTxId = board.driverLaborTxId
        driverLeaveTxId = board.driverLeaveTxId
        legacyLaborTxId = board.legacyLaborTxId
        legacyLeaveTxId = board.legacyLeaveTxId
        daysWorked = AttendanceLogic.daysWorkedByEmployee(transactions: transactions)
        pickedIds.removeAll()
    }

    func summary(for section: AttendanceSection) -> String {
        AttendanceLogic.sectionSummary(section: section, assignments: assignments)
    }

    func pool(employees: [Employee]) -> [Employee] {
        guard let section else { return [] }
        return AttendanceLogic.poolEmployees(
            section: section,
            employees: employees,
            assignments: assignments,
            daysWorked: daysWorked
        )
    }

    func placedBucket(for employeeId: String) -> AttendanceBucket? {
        guard let section else { return nil }
        return AttendanceLogic.assignedBucket(
            employeeId: employeeId,
            section: section,
            assignments: assignments
        )
    }

    func togglePick(_ employeeId: String) {
        if pickedIds.contains(employeeId) {
            pickedIds.remove(employeeId)
        } else {
            pickedIds.insert(employeeId)
        }
    }

    /// Assign selected (or single) employees to a bucket; empty pick + employeeId assigns that one.
    func assignToBucket(_ bucket: AttendanceBucket, employeeId: String? = nil) {
        guard let section, section.buckets.contains(bucket) else { return }
        var targets = pickedIds
        if let employeeId {
            if targets.isEmpty {
                targets = [employeeId]
            } else if !targets.contains(employeeId) {
                targets.insert(employeeId)
            }
        }
        guard !targets.isEmpty else { return }

        for b in section.buckets {
            guard var set = assignments[b], !set.isEmpty else { continue }
            set.subtract(targets)
            assignments[b] = set
        }
        var dest = assignments[bucket] ?? []
        dest.formUnion(targets)
        assignments[bucket] = dest
        pickedIds.removeAll()
        clearStatus()
    }

    func removeFromBuckets(_ employeeId: String) {
        guard let section else { return }
        for b in section.buckets {
            guard var set = assignments[b], set.contains(employeeId) else { continue }
            set.remove(employeeId)
            assignments[b] = set
        }
        pickedIds.remove(employeeId)
        clearStatus()
    }

    /// Tap pool employee: if picked set non-empty and tapping a bucket elsewhere — handled separately.
    /// Pool tap toggles pick; double-tap style: if already in a bucket and no multi-pick, remove.
    func poolTap(_ employeeId: String) {
        if placedBucket(for: employeeId) != nil, pickedIds.isEmpty {
            // Toggle pick while placed (to move later), or remove via × on chip.
            togglePick(employeeId)
            return
        }
        togglePick(employeeId)
    }

    func saveCurrentSection() async {
        guard let section else { return }
        guard !isSaving else { return }

        let present: Set<String>
        let leave: Set<String>
        switch section {
        case .sandYard:
            present = (assignments[.work] ?? [])
                .union(assignments[.halfMorning] ?? [])
                .union(assignments[.halfAfternoon] ?? [])
            leave = assignments[.leave] ?? []
        case .driver:
            present = (assignments[.drvMacro] ?? []).union(assignments[.drvDrum] ?? [])
            leave = assignments[.drvLeave] ?? []
        }

        if present.isEmpty && leave.isEmpty {
            setError("กรุณาจัดรายชื่อลงกล่องอย่างน้อย 1 คน")
            return
        }

        isSaving = true
        defer { isSaving = false }

        skipExternalReload += 1
        do {
            switch section {
            case .sandYard:
                try await saveSandYard(present: present, leave: leave)
            case .driver:
                try await saveDriver(present: present, leave: leave)
            }
            setOk(section == .sandYard
                ? "บันทึกเช็คชื่อพนักงานท่าทรายสำเร็จ"
                : "บันทึกเช็คชื่อคนขับรถสำเร็จ")
        } catch {
            skipExternalReload = max(0, skipExternalReload - 1)
            setError(error.localizedDescription)
        }
    }

    private func saveSandYard(present: Set<String>, leave: Set<String>) async throws {
        if !present.isEmpty {
            let reuse = sandLaborTxId ?? legacyLaborTxId
            let id = reuse ?? AttendanceWriter.newId(suffix: "att_sand")
            let wasPersisted = reuse != nil
            let payload = AttendanceWriter.sandWorkPayload(
                id: id,
                dateYmd: dayKey,
                work: assignments[.work] ?? [],
                halfMorning: assignments[.halfMorning] ?? [],
                halfAfternoon: assignments[.halfAfternoon] ?? [],
                omitCreatedAt: wasPersisted
            )
            _ = await AttendanceWriter.persist(payload: payload, wasPersisted: wasPersisted)
            sandLaborTxId = id
            if legacyLaborTxId == id { legacyLaborTxId = nil }
        } else {
            await AttendanceWriter.deleteIfNeeded(id: sandLaborTxId)
            sandLaborTxId = nil
        }

        if !leave.isEmpty {
            let reuse = sandLeaveTxId ?? legacyLeaveTxId
            let id = reuse ?? AttendanceWriter.newId(suffix: "att_sand_leave")
            let wasPersisted = reuse != nil
            let payload = AttendanceWriter.sandLeavePayload(
                id: id,
                dateYmd: dayKey,
                employeeIds: leave,
                omitCreatedAt: wasPersisted
            )
            _ = await AttendanceWriter.persist(payload: payload, wasPersisted: wasPersisted)
            sandLeaveTxId = id
            if legacyLeaveTxId == id { legacyLeaveTxId = nil }
        } else {
            await AttendanceWriter.deleteIfNeeded(id: sandLeaveTxId)
            sandLeaveTxId = nil
        }
    }

    private func saveDriver(present: Set<String>, leave: Set<String>) async throws {
        if !present.isEmpty {
            let reuse = driverLaborTxId ?? legacyLaborTxId
            let id = reuse ?? AttendanceWriter.newId(suffix: "att_drv")
            let wasPersisted = reuse != nil
            // Prefer dedicated driver id; only fall back to legacy when no sand labor claimed it.
            let payload = AttendanceWriter.driverWorkPayload(
                id: id,
                dateYmd: dayKey,
                macro: assignments[.drvMacro] ?? [],
                drum: assignments[.drvDrum] ?? [],
                omitCreatedAt: wasPersisted
            )
            _ = await AttendanceWriter.persist(payload: payload, wasPersisted: wasPersisted)
            driverLaborTxId = id
            if legacyLaborTxId == id { legacyLaborTxId = nil }
        } else {
            await AttendanceWriter.deleteIfNeeded(id: driverLaborTxId)
            driverLaborTxId = nil
        }

        if !leave.isEmpty {
            let reuse = driverLeaveTxId ?? legacyLeaveTxId
            let id = reuse ?? AttendanceWriter.newId(suffix: "att_drv_leave")
            let wasPersisted = reuse != nil
            let payload = AttendanceWriter.driverLeavePayload(
                id: id,
                dateYmd: dayKey,
                employeeIds: leave,
                omitCreatedAt: wasPersisted
            )
            _ = await AttendanceWriter.persist(payload: payload, wasPersisted: wasPersisted)
            driverLeaveTxId = id
            if legacyLeaveTxId == id { legacyLeaveTxId = nil }
        } else {
            await AttendanceWriter.deleteIfNeeded(id: driverLeaveTxId)
            driverLeaveTxId = nil
        }
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
