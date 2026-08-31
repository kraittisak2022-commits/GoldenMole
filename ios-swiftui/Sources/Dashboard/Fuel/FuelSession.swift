import Foundation
import Observation

struct FuelVehicleDraft: Identifiable, Equatable, Sendable {
    var id: String { vehicleId }
    var txId: String?
    var vehicleId: String
    var liters: Double = 0
    var time: String = ""
    /// Default ถังสำรอง (ปั่นไฟ); legacy แถวไม่มี fuel_tank = main ตอน hydrate
    var fuelTank: String = FuelLogic.tankReserve

    var isPersisted: Bool {
        !(txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isActive: Bool {
        liters > 0 || !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPersisted
    }
}

struct FuelStockInDraft: Equatable, Sendable {
    var txId: String?
    var liters: Double = 0
    var unitPrice: Double = 0
    var amount: Double = 0
    var time: String = FuelLogic.nowTimeHHmm()

    var isPersisted: Bool { !(txId ?? "").isEmpty }

    mutating func syncAmountFromPrice() {
        if unitPrice > 0, liters > 0 {
            amount = (liters * unitPrice * 100).rounded() / 100
        }
    }
}

struct FuelWithdrawDraft: Equatable, Sendable {
    var txId: String?
    var liters: Double = 0
    var time: String = FuelLogic.nowTimeHHmm()
    var purpose: FuelLogic.WithdrawPurpose = .machine
    var otherText: String = ""

    var isPersisted: Bool { !(txId ?? "").isEmpty }
}

struct FuelCarFillDraft: Equatable, Sendable {
    var liters: Double = 0
    var time: String = FuelLogic.nowTimeHHmm()
    var vehicle: FuelLogic.CarFillVehicle?
    var otherText: String = ""
}

enum FuelSaveError: LocalizedError {
    case liters
    case time
    case otherDetail
    case pickVehicle
    case vehicleName
    case mainTankShort
    case reserveTankShort
    case noCars
    case emptyUsage
    case usageLiters(String)
    case usageTime(String)

    var errorDescription: String? {
        switch self {
        case .liters: return "กรุณาระบุจำนวนลิตรให้มากกว่า 0"
        case .time: return "กรุณาระบุเวลา"
        case .otherDetail: return "กรุณาระบุรายละเอียดการเบิก"
        case .pickVehicle: return "กรุณาเลือกรถยนต์"
        case .vehicleName: return "กรุณาระบุชื่อรถ"
        case .mainTankShort: return "ถังหลักมีน้ำมันไม่พอ"
        case .reserveTankShort: return "ถังสำรองมีน้ำมันไม่พอ"
        case .noCars: return "ยังไม่พบรถแม็คโครในตั้งค่าแอพ"
        case .emptyUsage: return "กรุณาระบุปริมาณน้ำมันอย่างน้อย 1 คัน"
        case .usageLiters(let v): return "กรุณาระบุปริมาณน้ำมันให้มากกว่า 0 (\(v))"
        case .usageTime(let v): return "กรุณาระบุเวลาเติมน้ำมัน (\(v))"
        }
    }
}

@MainActor
@Observable
final class FuelSession {
    var subMode: FuelLogic.SubMode?
    var stockIn = FuelStockInDraft()
    var withdraw = FuelWithdrawDraft()
    var carFill = FuelCarFillDraft()
    var vehicleDrafts: [FuelVehicleDraft] = []
    var dieselBalance: Double = 0
    var reserveDieselBalance: Double = 0
    var dayStockInRows: [Transaction] = []
    var dayWithdrawRows: [Transaction] = []
    var statusMessage: String?
    var isErrorStatus = false
    var isSaving = false
    var showFailedQueue = false
    var confirmDeleteId: String?
    var extraExpanded = false

    private(set) var dayKey: String
    private var skipExternalReload = 0
    /// กันคำนวณยอดถังซ้ำเมื่อ transactionsRevision ยังไม่เปลี่ยน
    private var lastBalanceRevision: Int = -1

    private static let kCachedMainDiesel = "fuel_snapshot_main_diesel"
    private static let kCachedReserveDiesel = "fuel_snapshot_reserve_diesel"

    init(dayKey: String = DashboardAggregations.todayYMD()) {
        self.dayKey = dayKey
        let ud = UserDefaults.standard
        dieselBalance = ud.double(forKey: Self.kCachedMainDiesel)
        reserveDieselBalance = ud.double(forKey: Self.kCachedReserveDiesel)
    }

    private func persistBalanceSnapshot() {
        let ud = UserDefaults.standard
        ud.set(dieselBalance, forKey: Self.kCachedMainDiesel)
        ud.set(reserveDieselBalance, forKey: Self.kCachedReserveDiesel)
    }

    func configureOffline(service: SupabaseService, appState: AppState) {
        CountRecordOfflineSync.shared.configure(service: service, appState: appState)
    }

    func reload(appState: AppState, force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        let rev = appState.transactionsRevision
        let needsBalance = force || rev != lastBalanceRevision
        if needsBalance {
            let balance = FuelLogic.computeBalance(
                transactions: appState.transactions,
                opening: appState.settings.fuelOpeningStockLiters,
                asOfYmd: dayKey.isEmpty ? DashboardAggregations.todayYMD() : dayKey
            )
            dieselBalance = balance.mainDiesel
            reserveDieselBalance = balance.reserveDiesel
            lastBalanceRevision = rev
            persistBalanceSnapshot()
        }

        let dayRows = FuelLogic.dayFuelRows(dayKey: dayKey, transactions: appState.transactions)
        dayStockInRows = dayRows.filter(FuelLogic.isStockIn).sorted {
            ($0.createdAt ?? "") > ($1.createdAt ?? "")
        }
        // รวมโอนเครื่องจักรหลัก→สำรอง ในประวัติเบิก (คู่แถว Transfer); แยกเติมรถยนต์ไปเมนู carFill
        dayWithdrawRows = dayRows.filter { t in
            if FuelLogic.isWithdraw(t) { return !FuelLogic.isCarFill(t) }
            let mov = (t.fuelMovement ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return FuelLogic.isTransfer(t)
                && mov == "stock_out"
                && FuelLogic.normalizeTank(t.fuelTank) == FuelLogic.tankMain
                && (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "machine"
        }.sorted {
            ($0.createdAt ?? "") > ($1.createdAt ?? "")
        }

        syncVehicleDrafts(appState: appState, dayRows: dayRows, force: force)
    }

    /// โหลดรายการรับเข้าล่าสุดของวันเข้าฟอร์มเมื่อยังไม่ได้แก้/กรอกใหม่
    func autoHydrateStockInIfNeeded() {
        guard stockIn.txId == nil else { return }
        // มีการพิมพ์ลิตรแล้ว = กำลังกรอกใหม่ — ไม่ทับ
        if stockIn.liters > 0 { return }
        guard let latest = dayStockInRows.first else { return }
        applyStockInFields(from: latest)
    }

    private func applyStockInFields(from t: Transaction) {
        stockIn.txId = t.id
        stockIn.liters = t.quantity ?? 0
        stockIn.unitPrice = t.unitPrice ?? 0
        stockIn.amount = t.amount
        stockIn.time = FuelLogic.stripRecorder(t.workDetails ?? "")
        if stockIn.time.isEmpty { stockIn.time = FuelLogic.nowTimeHHmm() }
    }

    private func syncVehicleDrafts(appState: AppState, dayRows: [Transaction], force: Bool) {
        let cars = MacroVehicleLogic.macroCars(from: appState.settings)
        var byVehicle: [String: Transaction] = [:]
        for t in dayRows where FuelLogic.isVehicleUsage(t) {
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vid.isEmpty else { continue }
            if let existing = byVehicle[vid] {
                if (t.createdAt ?? "") >= (existing.createdAt ?? "") {
                    byVehicle[vid] = t
                }
            } else {
                byVehicle[vid] = t
            }
        }

        let previous = Dictionary(uniqueKeysWithValues: vehicleDrafts.map { ($0.vehicleId, $0) })
        var next: [FuelVehicleDraft] = []
        for car in cars {
            var row = previous[car] ?? FuelVehicleDraft(vehicleId: car)
            row.vehicleId = car
            let typed = row.liters > 0 || !row.time.isEmpty
            if force || !typed {
                if let tx = byVehicle[car] {
                    row.txId = tx.id
                    row.liters = tx.quantity ?? 0
                    row.time = FuelLogic.stripRecorder(tx.workDetails ?? "")
                    let rawTank = (tx.fuelTank ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    row.fuelTank = rawTank.isEmpty ? FuelLogic.tankMain : FuelLogic.normalizeTank(tx.fuelTank)
                } else if force {
                    row.txId = nil
                    row.liters = 0
                    row.time = ""
                    row.fuelTank = FuelLogic.tankReserve
                }
            } else if let tx = byVehicle[car], row.txId == nil {
                row.txId = tx.id
                row.liters = tx.quantity ?? 0
                row.time = FuelLogic.stripRecorder(tx.workDetails ?? "")
                let rawTank = (tx.fuelTank ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                row.fuelTank = rawTank.isEmpty ? FuelLogic.tankMain : FuelLogic.normalizeTank(tx.fuelTank)
            }
            next.append(row)
        }
        vehicleDrafts = next
    }

    func updateVehicle(_ vehicleId: String, mutate: (inout FuelVehicleDraft) -> Void) {
        guard let i = vehicleDrafts.firstIndex(where: { $0.vehicleId == vehicleId }) else { return }
        mutate(&vehicleDrafts[i])
        clearStatus()
    }

    func loadStockIn(_ t: Transaction) {
        applyStockInFields(from: t)
        subMode = .stockIn
        statusMessage = "โหลดรายการเพิ่มน้ำมันมาแก้ไข"
        isErrorStatus = false
    }

    func loadWithdraw(_ t: Transaction) {
        // Machine transfers are create-only pairs — don't load into the withdraw editor.
        if FuelLogic.isTransfer(t) {
            statusMessage = "รายการโอนเข้าสำรอง — ลบแล้วบันทึกใหม่ได้"
            isErrorStatus = false
            return
        }
        withdraw.txId = t.id
        withdraw.liters = t.quantity ?? 0
        withdraw.time = FuelLogic.stripRecorder(t.workDetails ?? "")
        if withdraw.time.isEmpty { withdraw.time = FuelLogic.nowTimeHHmm() }
        withdraw.purpose = FuelLogic.WithdrawPurpose.from(code: t.workType)
        if withdraw.purpose == .other {
            // description: เบิกน้ำมัน: อื่นๆ — {text} ...
            let desc = t.description
            if let range = desc.range(of: "อื่นๆ — ") {
                var rest = String(desc[range.upperBound...])
                if let lit = rest.range(of: " ลิตร") {
                    rest = String(rest[..<lit.lowerBound])
                }
                withdraw.otherText = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            withdraw.otherText = ""
        }
        subMode = .withdraw
        statusMessage = "โหลดรายการเบิกน้ำมันมาแก้ไข"
        isErrorStatus = false
    }

    func clearStockInForm() {
        stockIn = FuelStockInDraft()
    }

    func clearWithdrawForm() {
        withdraw = FuelWithdrawDraft()
    }

    func clearCarFillForm() {
        carFill = FuelCarFillDraft()
    }

    func saveStockIn(appState: AppState) async {
        guard !isSaving else { return }
        do {
            if stockIn.liters <= 0 { throw FuelSaveError.liters }
            if stockIn.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw FuelSaveError.time }
            isSaving = true
            defer { isSaving = false }
            let existing = (stockIn.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let id = existing.isEmpty ? FuelWriter.newId(suffix: "fuel_in") : existing
            var amount = stockIn.amount
            if amount <= 0, stockIn.unitPrice > 0 {
                amount = stockIn.liters * stockIn.unitPrice
            }
            let payload = FuelWriter.stockInPayload(
                id: id,
                dateYmd: dayKey,
                liters: stockIn.liters,
                unitPrice: stockIn.unitPrice > 0 ? stockIn.unitPrice : nil,
                amount: amount,
                time: stockIn.time.trimmingCharacters(in: .whitespacesAndNewlines),
                omitCreatedAt: !existing.isEmpty
            )
            skipExternalReload += 1
            _ = await FuelWriter.persist(payload: payload, wasPersisted: !existing.isEmpty)
            stockIn.txId = id
            stockIn.amount = amount
            setOk(existing.isEmpty ? "บันทึกเพิ่มน้ำมันเข้าถังสำเร็จ" : "อัปเดตเพิ่มน้ำมันเข้าถังสำเร็จ")
            reload(appState: appState, force: true)
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveWithdraw(appState: AppState) async {
        guard !isSaving else { return }
        do {
            if withdraw.liters <= 0 { throw FuelSaveError.liters }
            if withdraw.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw FuelSaveError.time }
            if withdraw.purpose == .other,
               withdraw.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FuelSaveError.otherDetail
            }
            isSaving = true
            defer { isSaving = false }
            let time = withdraw.time.trimmingCharacters(in: .whitespacesAndNewlines)
            let liters = withdraw.liters
            skipExternalReload += 1
            if withdraw.purpose == .machine {
                if liters > dieselBalance + 1e-9 {
                    throw FuelSaveError.liters
                }
                let reserveRoom = FuelLogic.tankCapacityReserveLiters - reserveDieselBalance
                if liters > reserveRoom + 1e-9 {
                    throw FuelSaveError.liters
                }
                let pair = FuelWriter.transferToReservePayloads(
                    dateYmd: dayKey,
                    liters: liters,
                    time: time,
                    omitCreatedAt: false
                )
                _ = await FuelWriter.persist(payload: pair.out, wasPersisted: false)
                _ = await FuelWriter.persist(payload: pair.in, wasPersisted: false)
                clearWithdrawForm()
                setOk("เติมถังสำรองสำเร็จ")
            } else {
                let existing = (withdraw.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let id = existing.isEmpty ? FuelWriter.newId(suffix: "fuel_wd") : existing
                let payload = FuelWriter.withdrawPayload(
                    id: id,
                    dateYmd: dayKey,
                    liters: liters,
                    purpose: withdraw.purpose,
                    otherText: withdraw.otherText.trimmingCharacters(in: .whitespacesAndNewlines),
                    time: time,
                    omitCreatedAt: !existing.isEmpty,
                    fuelTank: FuelLogic.tankMain
                )
                _ = await FuelWriter.persist(payload: payload, wasPersisted: !existing.isEmpty)
                clearWithdrawForm()
                setOk("บันทึกเบิกน้ำมันสำเร็จ")
            }
            reload(appState: appState, force: true)
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveCarFill(appState: AppState) async {
        guard !isSaving else { return }
        do {
            guard let vehicle = carFill.vehicle else { throw FuelSaveError.pickVehicle }
            if carFill.liters <= 0 { throw FuelSaveError.liters }
            if carFill.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FuelSaveError.time
            }
            if vehicle == .other,
               carFill.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw FuelSaveError.vehicleName
            }
            if carFill.liters > dieselBalance + 1e-9 {
                throw FuelSaveError.mainTankShort
            }
            isSaving = true
            defer { isSaving = false }
            let payload = FuelWriter.carFillPayload(
                id: FuelWriter.newId(suffix: "fuel_car"),
                dateYmd: dayKey,
                liters: carFill.liters,
                vehicle: vehicle,
                otherText: carFill.otherText,
                time: carFill.time.trimmingCharacters(in: .whitespacesAndNewlines),
                omitCreatedAt: false
            )
            skipExternalReload += 1
            _ = await FuelWriter.persist(payload: payload, wasPersisted: false)
            clearCarFillForm()
            setOk("บันทึกเติมน้ำมันรถยนต์สำเร็จ")
            reload(appState: appState, force: true)
        } catch {
            setError(error.localizedDescription)
        }
    }

    func saveVehicleUsage(appState: AppState) async {
        guard !isSaving else { return }
        do {
            let cars = MacroVehicleLogic.macroCars(from: appState.settings)
            guard !cars.isEmpty else { throw FuelSaveError.noCars }
            let active = vehicleDrafts.filter(\.isActive)
            guard !active.isEmpty else { throw FuelSaveError.emptyUsage }
            for row in active {
                if row.liters <= 0 { throw FuelSaveError.usageLiters(row.vehicleId) }
                if row.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw FuelSaveError.usageTime(row.vehicleId)
                }
            }
            var extraMain = 0.0
            var extraReserve = 0.0
            for row in active {
                let tank = FuelLogic.normalizeTank(row.fuelTank)
                let previousId = (row.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let previous = previousId.isEmpty
                    ? nil
                    : appState.transactions.first(where: { $0.id == previousId })
                if let previous {
                    if FuelLogic.normalizeTank(previous.fuelTank) == FuelLogic.tankReserve {
                        extraReserve -= FuelLogic.liters(of: previous)
                    } else {
                        extraMain -= FuelLogic.liters(of: previous)
                    }
                }
                if tank == FuelLogic.tankReserve {
                    extraReserve += row.liters
                } else {
                    extraMain += row.liters
                }
            }
            if extraMain > dieselBalance + 1e-9 { throw FuelSaveError.mainTankShort }
            if extraReserve > reserveDieselBalance + 1e-9 { throw FuelSaveError.reserveTankShort }
            isSaving = true
            defer { isSaving = false }
            skipExternalReload += 1
            for (i, row) in active.enumerated() {
                let existing = (row.txId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let id = existing.isEmpty ? FuelWriter.newId(suffix: "fuel_out_\(i)") : existing
                let payload = FuelWriter.vehicleUsagePayload(
                    id: id,
                    dateYmd: dayKey,
                    vehicleId: row.vehicleId,
                    liters: row.liters,
                    time: row.time.trimmingCharacters(in: .whitespacesAndNewlines),
                    omitCreatedAt: !existing.isEmpty,
                    fuelTank: FuelLogic.normalizeTank(row.fuelTank)
                )
                _ = await FuelWriter.persist(payload: payload, wasPersisted: !existing.isEmpty)
            }
            setOk("บันทึกการใช้น้ำมันรายรถสำเร็จ")
            reload(appState: appState, force: true)
        } catch {
            skipExternalReload = max(0, skipExternalReload - 1)
            setError(error.localizedDescription)
        }
    }

    func deleteTransaction(id: String, appState: AppState) async {
        skipExternalReload += 1
        // Delete paired transfer (main out + reserve in) by shared note.
        if let row = appState.transactions.first(where: { $0.id == id }),
           FuelLogic.isTransfer(row),
           let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            let siblings = appState.transactions.filter {
                FuelLogic.isTransfer($0)
                    && ($0.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == note
            }
            for sib in siblings {
                _ = await FuelWriter.delete(id: sib.id)
            }
        } else {
            _ = await FuelWriter.delete(id: id)
        }
        if stockIn.txId == id { clearStockInForm() }
        if withdraw.txId == id { clearWithdrawForm() }
        if let i = vehicleDrafts.firstIndex(where: { $0.txId == id }) {
            vehicleDrafts[i].txId = nil
            vehicleDrafts[i].liters = 0
            vehicleDrafts[i].time = ""
        }
        setOk("ลบรายการแล้ว")
        reload(appState: appState, force: true)
    }

    func clearVehicleDraft(_ vehicleId: String) {
        updateVehicle(vehicleId) {
            $0.txId = nil
            $0.liters = 0
            $0.time = ""
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
