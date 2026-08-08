import Foundation
import Observation

struct DrumTripDraft: Equatable, Sendable {
    var tripTxId: String?
    var vehicleId: String = ""
    var driverId: String = ""
    var tripMorning: Double = 0
    var tripAfternoon: Double = 0
    var cubicPerTrip: Double = 3
    var lumpSumTotalCubic: Double = 0
    var billingMode: DrumTripLogic.BillingMode = .perTrip
    var workType: DrumTripLogic.WorkType = .fullDay
    var hourlyHours: Double = 0
    var workDetails: String = ""

    var isPersisted: Bool { tripTxId != nil }

    var hasAnyInput: Bool {
        !vehicleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !driverId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !workDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || tripMorning > 0
            || tripAfternoon > 0
            || (billingMode == .lumpSum && lumpSumTotalCubic > 0)
            || (billingMode == .perTrip && cubicPerTrip > 0 && cubicPerTrip != 3)
            || (workType == .hourly && hourlyHours > 0)
    }

    static func empty(defaultCubic: Double = 3) -> DrumTripDraft {
        var d = DrumTripDraft()
        d.cubicPerTrip = defaultCubic
        return d
    }

    static func fromTransaction(_ t: Transaction) -> DrumTripDraft {
        var d = DrumTripDraft()
        d.tripTxId = t.id
        d.vehicleId = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        d.driverId = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        d.workType = DrumTripLogic.WorkType.from(raw: t.workType)
        d.billingMode = DrumTripLogic.BillingMode.from(raw: t.tripBillingMode)

        // Infer lump if billing missing but cubic is 0 and total cubic > 0.
        if t.tripBillingMode == nil {
            let cpt = t.cubicPerTrip ?? 0
            let lump = t.perCarCubic ?? t.totalCubic ?? 0
            if cpt <= 0, lump > 0 {
                d.billingMode = .lumpSum
            }
        }

        let split = DrumTripLogic.periodSplit(t)
        d.tripMorning = split.morning
        d.tripAfternoon = split.afternoon

        let lumpVal = t.perCarCubic ?? t.totalCubic ?? 0
        if d.billingMode == .lumpSum {
            d.lumpSumTotalCubic = max(0, lumpVal)
            d.cubicPerTrip = 0
        } else {
            d.lumpSumTotalCubic = 0
            let cptVal = t.cubicPerTrip ?? 0
            d.cubicPerTrip = cptVal > 0
                ? cptVal
                : DrumTripLogic.defaultCubicPerTrip(for: d.vehicleId)
        }

        d.workDetails = DrumTripLogic.stripRecorderSuffix(t.workDetails ?? "")
        if d.workType == .hourly, let oh = t.otHours, oh > 0 {
            d.hourlyHours = oh
        }
        return d
    }
}

enum DrumTripSaveError: LocalizedError {
    case empty
    case missingVehicleOrDriver
    case duplicateVehicle(String)
    case needTrips
    case needCubic
    case needLumpCubic
    case needHourlyHours

    var errorDescription: String? {
        switch self {
        case .empty: return "กรุณาระบุข้อมูลรถอย่างน้อย 1 คัน"
        case .missingVehicleOrDriver: return "กรุณาระบุรถและคนขับให้ครบ"
        case .duplicateVehicle(let v): return "มีบันทึกรถ \"\(v)\" ในวันนี้แล้ว — เลือกรถจากรายการด้านล่างเพื่อแก้ไข"
        case .needTrips: return "กรุณาระบุจำนวนเที่ยวรวม (เช้า+บ่าย) ให้มากกว่า 0"
        case .needCubic: return "กรุณาระบุคิวต่อเที่ยวให้มากกว่า 0"
        case .needLumpCubic: return "กรุณาระบุรวมคิว (เหมา) ให้มากกว่า 0"
        case .needHourlyHours: return "กรุณาระบุชั่วโมงทำงานสำหรับรายการรายชั่วโมง"
        }
    }
}

@MainActor
@Observable
final class DrumTripSession {
    var draft = DrumTripDraft.empty()
    var savedToday: [Transaction] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var confirmDeleteId: String?

    private(set) var dayKey: String
    private var skipExternalReload = 0

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(transactions: [Transaction], force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        savedToday = DrumTripLogic.dayRows(dayKey: dayKey, transactions: transactions)
    }

    func clearDraft(keepVehicleDefaults: Bool = false) {
        let cubic = keepVehicleDefaults
            ? DrumTripLogic.defaultCubicPerTrip(for: draft.vehicleId)
            : 3
        draft = DrumTripDraft.empty(defaultCubic: cubic)
        clearStatus()
    }

    func loadTransaction(_ t: Transaction, settings: AppSettings, appState: AppState) {
        draft = DrumTripDraft.fromTransaction(t)
        if draft.driverId.isEmpty {
            draft.driverId = defaultDriverId(for: draft.vehicleId, appState: appState) ?? ""
        }
        if draft.billingMode == .perTrip, draft.cubicPerTrip <= 0 {
            draft.cubicPerTrip = DrumTripLogic.defaultCubicPerTrip(for: draft.vehicleId)
        }
        statusMessage = "โหลดรถ \"\(draft.vehicleId)\" มาแก้ไข"
        isErrorStatus = false
    }

    func onVehicleSelected(_ vehicleId: String, transactions: [Transaction], appState: AppState) {
        draft.vehicleId = vehicleId
        if draft.billingMode == .perTrip {
            draft.cubicPerTrip = DrumTripLogic.defaultCubicPerTrip(for: vehicleId)
        }
        if draft.driverId.isEmpty {
            draft.driverId = defaultDriverId(for: vehicleId, appState: appState) ?? ""
        }

        // Auto-load existing day row for this vehicle (unless editing same id).
        if let existing = savedToday.first(where: {
            ($0.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == vehicleId
        }) {
            if draft.tripTxId != existing.id {
                loadTransaction(existing, settings: appState.settings, appState: appState)
            }
            return
        }

        // Prefer count-record row for same vehicle today if not yet in saved list form shape.
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }
        if let cr = dayTx.first(where: {
            CountRecordLogic.isCountRecordVehicleRow($0)
                && ($0.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == vehicleId
        }) {
            loadTransaction(cr, settings: appState.settings, appState: appState)
        }
        clearStatus()
    }

    func defaultDriverId(for vehicleId: String, appState: AppState) -> String? {
        CountRecordVehicleDefaults.resolveDriverId(
            vehicleId: vehicleId,
            drivers: DrumTripLogic.drivers(from: appState.employees),
            tripHistory: appState.transactions,
            vehicleDefaultDrivers: appState.settings.vehicleDefaultDrivers
        )
    }

    func save(appState: AppState) async {
        guard !isSaving else { return }
        clearStatus()

        do {
            try validate(against: savedToday)
        } catch {
            setError(error.localizedDescription)
            return
        }

        isSaving = true
        defer { isSaving = false }

        let vehicle = draft.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let driver = draft.driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        var details = draft.workDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.workType == .hourly {
            let hs = DrumTripLogic.formatMetric(draft.hourlyHours)
            details = details.isEmpty ? "งานรายชั่วโมง \(hs) ชม." : "\(details) (\(hs) ชม.)"
        }

        let id = draft.tripTxId ?? DrumTripWriter.newId(suffix: "trip")
        let wasPersisted = draft.tripTxId != nil
        let workType: DrumTripLogic.WorkType = {
            switch draft.workType {
            case .halfDay, .hourly: return draft.workType
            case .fullDay: return .fullDay
            }
        }()

        let payload: TransactionWritePayload
        switch draft.billingMode {
        case .lumpSum:
            payload = DrumTripWriter.lumpSumPayload(
                id: id,
                dateYmd: dayKey,
                vehicleId: vehicle,
                driverId: driver,
                tripMorning: draft.tripMorning,
                tripAfternoon: draft.tripAfternoon,
                lumpCubic: draft.lumpSumTotalCubic,
                workDetails: details,
                workType: workType,
                omitCreatedAt: wasPersisted
            )
        case .perTrip:
            payload = DrumTripWriter.perTripPayload(
                id: id,
                dateYmd: dayKey,
                vehicleId: vehicle,
                driverId: driver,
                tripMorning: draft.tripMorning,
                tripAfternoon: draft.tripAfternoon,
                cubicPerTrip: draft.cubicPerTrip,
                workDetails: details,
                workType: workType,
                omitCreatedAt: wasPersisted
            )
        }

        skipExternalReload += 1
        _ = await DrumTripWriter.persist(payload: payload, wasPersisted: wasPersisted)
        draft.tripTxId = id
        setOk("บันทึกรถดรัมและจำนวนเที่ยวสำเร็จ")
        clearDraft()
        reload(transactions: appState.transactions, force: true)
    }

    func deleteSaved(id: String, appState: AppState) async {
        skipExternalReload += 1
        _ = await DrumTripWriter.delete(id: id)
        if draft.tripTxId == id {
            clearDraft()
        }
        reload(transactions: appState.transactions, force: true)
        setOk("ลบรายการแล้ว")
    }

    private func validate(against existing: [Transaction]) throws {
        guard draft.hasAnyInput else { throw DrumTripSaveError.empty }
        let vehicle = draft.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let driver = draft.driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicle.isEmpty, !driver.isEmpty else { throw DrumTripSaveError.missingVehicleOrDriver }

        let selfId = draft.tripTxId
        for t in existing {
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard vid == vehicle else { continue }
            if let selfId, t.id == selfId { continue }
            throw DrumTripSaveError.duplicateVehicle(vehicle)
        }

        if draft.workType == .hourly, draft.hourlyHours <= 0 {
            throw DrumTripSaveError.needHourlyHours
        }

        switch draft.billingMode {
        case .lumpSum:
            if draft.lumpSumTotalCubic <= 0 { throw DrumTripSaveError.needLumpCubic }
        case .perTrip:
            if draft.tripMorning + draft.tripAfternoon <= 0 { throw DrumTripSaveError.needTrips }
            if draft.cubicPerTrip <= 0 { throw DrumTripSaveError.needCubic }
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
