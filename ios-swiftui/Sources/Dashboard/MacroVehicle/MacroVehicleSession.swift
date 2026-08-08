import Foundation
import Observation

struct MacroVehicleDraft: Identifiable, Equatable, Sendable {
    var id: String { vehicleId }
    var txId: String?
    var vehicleId: String
    var driverId: String = ""
    var workType: MacroVehicleLogic.WorkType = .fullDay
    var workDetails: String = ""
    var busy: Bool = false

    var isPersisted: Bool {
        !(txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var workTags: [String] {
        MacroVehicleLogic.parseWorkTags(workDetails)
    }

    var hasDriver: Bool {
        !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasDetails: Bool { !workTags.isEmpty }

    var isActiveForSave: Bool {
        hasDriver || isPersisted || hasDetails
    }

    mutating func setWorkTags(_ tags: [String]) {
        workDetails = MacroVehicleLogic.joinWorkTags(tags)
    }

    mutating func toggleWorkTag(_ tag: String) {
        var tags = workTags
        if let idx = tags.firstIndex(of: tag) {
            tags.remove(at: idx)
        } else {
            tags.append(tag)
        }
        setWorkTags(tags)
    }

    mutating func removeWorkTag(_ tag: String) {
        setWorkTags(workTags.filter { $0 != tag })
    }

    mutating func addCustomWorkTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        var tags = workTags
        guard !tags.contains(tag) else { return }
        tags.append(tag)
        setWorkTags(tags)
    }

    static func empty(vehicleId: String) -> MacroVehicleDraft {
        MacroVehicleDraft(vehicleId: vehicleId)
    }

    static func fromTransaction(_ t: Transaction, vehicleId: String) -> MacroVehicleDraft {
        var d = MacroVehicleDraft(vehicleId: vehicleId)
        d.txId = t.id
        let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !vid.isEmpty { d.vehicleId = vid }
        d.driverId = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        d.workType = MacroVehicleLogic.WorkType.from(raw: t.workType)
        d.workDetails = MacroVehicleLogic.stripRecorderSuffix(t.workDetails ?? "")
        return d
    }
}

enum MacroVehicleSaveError: LocalizedError {
    case noCars
    case noDriversConfigured
    case empty
    case missingDriver(String)
    case invalidDriver(String)

    var errorDescription: String? {
        switch self {
        case .noCars: return "ยังไม่พบรถแม็คโครในตั้งค่าแอพ"
        case .noDriversConfigured: return "ยังไม่พบพนักงานที่ตำแหน่งเป็น «คนขับรถแม็คโคร»"
        case .empty: return "กรุณาระบุคนขับอย่างน้อย 1 คัน"
        case .missingDriver(let v): return "กรุณาเลือกคนขับสำหรับ \(v)"
        case .invalidDriver(let v): return "เลือกคนขับจากรายชื่อตำแหน่ง «คนขับรถแม็คโคร» เท่านั้น (\(v))"
        }
    }
}

@MainActor
@Observable
final class MacroVehicleSession {
    var drafts: [MacroVehicleDraft] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var confirmDeleteVehicleId: String?
    var customWorkPromptVehicleId: String?
    var customWorkText = ""
    var extraExpanded = false

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
        let cars = MacroVehicleLogic.macroCars(from: appState.settings)
        let byVehicle = MacroVehicleLogic.dayRowsByVehicle(
            dayKey: dayKey,
            transactions: appState.transactions
        )
        let drivers = MacroVehicleLogic.macroDrivers(from: appState.employees)
        let driverIds = Set(drivers.map(\.id))

        var next: [MacroVehicleDraft] = []
        let previous = Dictionary(uniqueKeysWithValues: drafts.map { ($0.vehicleId, $0) })

        for car in cars {
            var row = previous[car] ?? MacroVehicleDraft.empty(vehicleId: car)
            row.vehicleId = car
            let typed = row.hasDriver || row.hasDetails
            if force || !typed {
                if let tx = byVehicle[car] {
                    row = MacroVehicleDraft.fromTransaction(tx, vehicleId: car)
                } else if force {
                    row.txId = nil
                    row.driverId = ""
                    row.workType = .fullDay
                    row.workDetails = ""
                }
            } else if let tx = byVehicle[car], row.txId == nil {
                row = MacroVehicleDraft.fromTransaction(tx, vehicleId: car)
            }

            if !row.isPersisted, row.driverId.isEmpty {
                if let def = CountRecordVehicleDefaults.resolveDriverId(
                    vehicleId: car,
                    drivers: drivers,
                    tripHistory: appState.transactions,
                    vehicleDefaultDrivers: appState.settings.vehicleDefaultDrivers
                ), driverIds.contains(def) {
                    row.driverId = def
                }
            }
            next.append(row)
        }
        drafts = next
    }

    func draftIndex(for vehicleId: String) -> Int? {
        drafts.firstIndex { $0.vehicleId == vehicleId }
    }

    func updateDraft(_ vehicleId: String, mutate: (inout MacroVehicleDraft) -> Void) {
        guard let i = draftIndex(for: vehicleId) else { return }
        mutate(&drafts[i])
        clearStatus()
    }

    func saveAll(appState: AppState) async {
        guard !isSaving else { return }
        do {
            let active = try validatedActiveRows(appState: appState)
            isSaving = true
            defer { isSaving = false }
            skipExternalReload += 1
            for (index, row) in active.enumerated() {
                try await persistRow(row, index: index, appState: appState)
            }
            setOk("บันทึกการใช้รถแม็คโครสำเร็จ")
            reload(appState: appState, force: true)
        } catch {
            skipExternalReload = max(0, skipExternalReload - 1)
            setError(error.localizedDescription)
        }
    }

    func saveSingle(vehicleId: String, appState: AppState) async {
        guard !isSaving, let row = drafts.first(where: { $0.vehicleId == vehicleId }) else { return }
        do {
            let cars = MacroVehicleLogic.macroCars(from: appState.settings)
            guard !cars.isEmpty else { throw MacroVehicleSaveError.noCars }
            try validateRow(row, drivers: MacroVehicleLogic.macroDrivers(from: appState.employees))
            isSaving = true
            defer { isSaving = false }
            skipExternalReload += 1
            try await persistRow(row, index: 0, appState: appState)
            setOk("อัปเดต \(vehicleId) แล้ว")
            reload(appState: appState, force: true)
        } catch {
            skipExternalReload = max(0, skipExternalReload - 1)
            setError(error.localizedDescription)
        }
    }

    func deleteRow(vehicleId: String, appState: AppState) async {
        guard let i = draftIndex(for: vehicleId) else { return }
        let persistedId = drafts[i].txId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let persistedId, !persistedId.isEmpty {
            skipExternalReload += 1
            _ = await MacroVehicleWriter.delete(id: persistedId)
            setOk("ลบรายการจากฐานข้อมูลแล้ว")
            reload(appState: appState, force: true)
            return
        }
        drafts[i].txId = nil
        drafts[i].driverId = ""
        drafts[i].workType = .fullDay
        drafts[i].workDetails = ""
        setOk("ล้างแถวแล้ว")
    }

    private func validatedActiveRows(appState: AppState) throws -> [MacroVehicleDraft] {
        let cars = MacroVehicleLogic.macroCars(from: appState.settings)
        guard !cars.isEmpty else { throw MacroVehicleSaveError.noCars }
        let drivers = MacroVehicleLogic.macroDrivers(from: appState.employees)
        let active = drafts.filter(\.isActiveForSave)
        guard !active.isEmpty else { throw MacroVehicleSaveError.empty }
        for row in active {
            try validateRow(row, drivers: drivers)
        }
        return active
    }

    private func validateRow(_ row: MacroVehicleDraft, drivers: [Employee]) throws {
        let vehicle = row.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let driver = row.driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !driver.isEmpty else { throw MacroVehicleSaveError.missingDriver(vehicle) }
        guard drivers.contains(where: { $0.id == driver }) else {
            throw MacroVehicleSaveError.invalidDriver(vehicle)
        }
    }

    private func persistRow(_ row: MacroVehicleDraft, index: Int, appState: AppState) async throws {
        let vehicle = row.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let driver = row.driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingId = (row.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = existingId.isEmpty ? MacroVehicleWriter.newId(index: index) : existingId
        let wasPersisted = !existingId.isEmpty
        let payload = MacroVehicleWriter.payload(
            id: id,
            dateYmd: dayKey,
            vehicleId: vehicle,
            driverId: driver,
            workDetails: row.workDetails,
            workType: row.workType,
            omitCreatedAt: wasPersisted
        )
        _ = await MacroVehicleWriter.persist(payload: payload, wasPersisted: wasPersisted)
        if let i = draftIndex(for: vehicle) {
            drafts[i].txId = id
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
