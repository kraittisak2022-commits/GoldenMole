import Foundation
import Observation

struct CountRecordTripDraft: Identifiable, Equatable {
    var id: String
    var vehicleId: String
    var driverId: String
    var rounds: Int
    var lapTimes: [String]
    var workDetails: String
    var persisted: Bool
    var busy: Bool = false
    var dirty: Bool = false
    var cooldownUntil: Date?
    var comboCount: Int = 0
    var lastRecordAt: Date?

    var workKind: CountRecordWorkKind { CountRecordWorkKind.from(workDetails: workDetails) }
    var isSupport: Bool { workKind == .support }
    var isBroken: Bool { CountRecordLogic.isWorkDetailsBroken(workDetails) }
    var canRecord: Bool { !isSupport && !isBroken && !busy && !isCoolingDown }

    var isCoolingDown: Bool {
        guard let until = cooldownUntil else { return false }
        return until > Date()
    }

    var periodSplit: (morning: Int, afternoon: Int, ot: Int) {
        var morning = 0, afternoon = 0, ot = 0
        for lap in lapTimes {
            guard let h = CountRecordLogic.lapHour(lap) else {
                morning += 1
                continue
            }
            if h < 12 { morning += 1 }
            else {
                afternoon += 1
                if h >= CountRecordLogic.otStartHour { ot += 1 }
            }
        }
        return (morning, afternoon, ot)
    }
}

struct CountRecordSandDraft: Identifiable, Equatable {
    var id: String
    var rounds: Int
    var lapTimes: [String]
    var persisted: Bool
    var busy: Bool = false
    var dirty: Bool = false
    var cooldownUntil: Date?
    var comboCount: Int = 0
    var lastRecordAt: Date?

    var isCoolingDown: Bool {
        guard let until = cooldownUntil else { return false }
        return until > Date()
    }

    var recentLaps: [String] {
        Array(lapTimes.suffix(CountRecordLogic.sandRecentLaps).reversed())
    }
}

struct CountRecordUndoAction: Equatable {
    enum Kind: Equatable { case trip(unitId: String); case sand }
    let kind: Kind
    let message: String
    let stamp: String
}

@MainActor
@Observable
final class CountRecordSession {
    var mode: CountRecordWorkMode? {
        didSet {
            if let mode {
                CountRecordPrefs.setWorkMode(mode, for: dayKey)
            }
        }
    }
    var tripUnits: [CountRecordTripDraft] = []
    var sandUnit: CountRecordSandDraft?
    var statusMessage: String?
    var isErrorStatus = false
    var showAddVehicle = false
    var showSettings = false
    var showTutorial = false
    var showFailedQueue = false
    var showShare = false
    var pendingUndo: CountRecordUndoAction?
    var editUnitId: String?

    private(set) var dayKey: String
    private var skipExternalReload = 0

    init() {
        let today = DashboardAggregations.todayYMD()
        dayKey = today
        mode = CountRecordPrefs.workMode(for: today)
    }

    func ensureToday() -> Bool {
        let today = DashboardAggregations.todayYMD()
        if dayKey != today {
            dayKey = today
            flash("บันทึกได้เฉพาะวันปัจจุบัน — เปลี่ยนเป็นวันนี้แล้ว กดนับอีกครั้ง")
            return false
        }
        return true
    }

    func bootstrap(appState: AppState) {
        dayKey = DashboardAggregations.todayYMD()
        if mode == nil, let saved = CountRecordPrefs.workMode(for: dayKey) {
            mode = saved
        }
        loadFromAppState(appState, force: true)
        if !CountRecordPrefs.tutorialCompleted {
            showTutorial = true
        }
    }

    func loadFromAppState(_ appState: AppState, force: Bool = false) {
        if !force && skipExternalReload > 0 {
            skipExternalReload -= 1
            return
        }
        // Don't clobber in-flight local edits / saves (Flutter preserve-local parity).
        if !force {
            let hasLocalTrip = tripUnits.contains { $0.dirty || $0.busy }
            let hasLocalSand = sandUnit.map { $0.dirty || $0.busy } ?? false
            if hasLocalTrip || hasLocalSand { return }
        }
        dayKey = DashboardAggregations.todayYMD()
        let dayTx = appState.transactions.filter { String($0.date.prefix(10)) == dayKey }

        let protectedVehicles = Set(tripUnits.filter { $0.dirty || $0.busy }.map(\.vehicleId))
        let built = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: dayTx,
            employees: appState.employees
        )

        var nextTrips: [CountRecordTripDraft] = []
        for u in built {
            if protectedVehicles.contains(u.vehicleId),
               let local = tripUnits.first(where: { $0.vehicleId == u.vehicleId }) {
                nextTrips.append(local)
                continue
            }
            let tx = dayTx.first(where: { $0.id == u.id })
            nextTrips.append(
                CountRecordTripDraft(
                    id: u.id,
                    vehicleId: u.vehicleId,
                    driverId: u.driverId,
                    rounds: u.rounds,
                    lapTimes: u.lapTimes,
                    workDetails: tx?.workDetails ?? "",
                    persisted: true
                )
            )
        }
        // Keep local-only units not yet mirrored from server rows
        for local in tripUnits where (local.dirty || local.busy || !local.persisted)
            && !nextTrips.contains(where: { $0.vehicleId == local.vehicleId }) {
            nextTrips.append(local)
        }
        tripUnits = nextTrips.sorted {
            if $0.rounds != $1.rounds { return $0.rounds > $1.rounds }
            return $0.vehicleId.localizedStandardCompare($1.vehicleId) == .orderedAscending
        }

        let protectSand = sandUnit.map { $0.dirty || $0.busy || ($0.rounds > 0 && !$0.persisted) } ?? false
        if !protectSand {
            if let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx) {
                sandUnit = CountRecordSandDraft(
                    id: sand.id,
                    rounds: sand.rounds,
                    lapTimes: sand.lapTimes,
                    persisted: true
                )
            } else if sandUnit == nil {
                sandUnit = CountRecordSandDraft(
                    id: CountRecordWriter.newTransactionId(suffix: "sand"),
                    rounds: 0,
                    lapTimes: [],
                    persisted: false
                )
            }
        }
    }

    func availableCars(settings: AppSettings) -> [String] {
        let added = Set(tripUnits.map(\.vehicleId))
        return settings.cars
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && CountRecordLogic.isDrumTripVehicleId($0) && !added.contains($0) }
    }

    func drivers(from employees: [Employee]) -> [Employee] {
        let active = employees.filter(\.isActive)
        let drivers = active.filter { emp in
            emp.positionTokens.contains { token in
                let t = token.replacingOccurrences(of: " ", with: "")
                return t.contains("คนขับรถ") && !t.contains("แม็คโคร") && !t.contains("แมคโคร")
            }
        }
        return drivers.isEmpty ? active : drivers
    }

    func defaultDriverId(for vehicleId: String, appState: AppState) -> String {
        CountRecordVehicleDefaults.resolveDriverId(
            vehicleId: vehicleId,
            drivers: drivers(from: appState.employees),
            tripHistory: appState.transactions,
            vehicleDefaultDrivers: appState.settings.vehicleDefaultDrivers
        ) ?? ""
    }

    struct VehiclePick: Identifiable, Equatable {
        var id: String { vehicleId }
        var vehicleId: String
        var driverId: String
        var workKind: CountRecordWorkKind
    }

    func addVehicles(_ picks: [VehiclePick], appState: AppState, adminName: String) async {
        for pick in picks {
            let vid = pick.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vid.isEmpty else { continue }
            guard !tripUnits.contains(where: { $0.vehicleId == vid }) else { continue }
            var unit = CountRecordTripDraft(
                id: CountRecordWriter.newTransactionId(suffix: vid),
                vehicleId: vid,
                driverId: pick.driverId.trimmingCharacters(in: .whitespacesAndNewlines),
                rounds: 0,
                lapTimes: [],
                workDetails: CountRecordWorkKind.appendTag(to: "", kind: pick.workKind),
                persisted: false,
                dirty: true
            )
            tripUnits.append(unit)
            if unit.isSupport {
                skipExternalReload += 1
                let result = await CountRecordWriter.saveTrip(
                    id: unit.id,
                    dateYmd: dayKey,
                    vehicleId: unit.vehicleId,
                    driverId: unit.driverId,
                    rounds: 0,
                    lapTimes: [],
                    adminName: adminName,
                    wasPersisted: false,
                    workDetails: unit.workDetails,
                    isSupport: true
                )
                if let i = tripUnits.firstIndex(where: { $0.vehicleId == vid }) {
                    tripUnits[i].persisted = true
                    tripUnits[i].dirty = false
                    if result.queued {
                        flash("ชัพพอต \(vid) · บันทึกในเครื่อง — จะอัปโหลดเมื่อมีเน็ต")
                    }
                }
            }
        }
    }

    func removeVehicle(unitId: String, appState: AppState, adminName: String) async {
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        let unit = tripUnits[idx]
        tripUnits.remove(at: idx)
        if unit.persisted {
            skipExternalReload += 1
            let queued = await CountRecordOfflineSync.shared.delete(id: unit.id)
            flash(queued ? "ลบ \(unit.vehicleId) (รอซิงค์)" : "ลบ \(unit.vehicleId) แล้ว")
        }
    }

    func updateDriver(unitId: String, driverId: String, appState: AppState, adminName: String) async {
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        tripUnits[idx].driverId = driverId
        tripUnits[idx].dirty = true
        await persistTrip(at: idx, adminName: adminName, clearDirty: true)
    }

    func toggleWorkKind(unitId: String, appState: AppState, adminName: String) async {
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        let current = tripUnits[idx].workKind
        let next: CountRecordWorkKind = current == .support ? .sandTransport : .support
        tripUnits[idx].workDetails = CountRecordWorkKind.appendTag(to: tripUnits[idx].workDetails, kind: next)
        tripUnits[idx].dirty = true
        await persistTrip(at: idx, adminName: adminName, clearDirty: true)
        flash(next == .support ? "เปลี่ยนเป็นชัพพอตแล้ว" : "เปลี่ยนเป็นขนทรายแล้ว")
    }

    func reportBroken(unitId: String, appState: AppState, adminName: String, employees: [Employee]) async {
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        let stamp = CountRecordLogic.formatLapStamp()
        let tag = "รถเสีย \(stamp)"
        let prev = tripUnits[idx].workDetails
        tripUnits[idx].workDetails = prev.isEmpty ? tag : "\(prev), \(tag)"
        tripUnits[idx].dirty = true
        await persistTrip(at: idx, adminName: adminName, clearDirty: true)
        let driverLabel = CountRecordLogic.driverDisplayName(tripUnits[idx].driverId, employees: employees)
        let event = CountRecordWriter.vehicleStatusEventPayload(
            dateYmd: dayKey,
            vehicleId: tripUnits[idx].vehicleId,
            driverLabel: driverLabel,
            adminName: adminName,
            broken: true,
            stamp: stamp
        )
        _ = await CountRecordOfflineSync.shared.persist(payload: event, wasPersisted: false)
        flash("แจ้งรถเสีย \(tripUnits[idx].vehicleId) แล้ว")
    }

    func restoreNormal(unitId: String, appState: AppState, adminName: String, employees: [Employee]) async {
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        let stamp = CountRecordLogic.formatLapStamp()
        let tag = "รถปกติ \(stamp)"
        let prev = tripUnits[idx].workDetails
        tripUnits[idx].workDetails = prev.isEmpty ? tag : "\(prev), \(tag)"
        tripUnits[idx].dirty = true
        await persistTrip(at: idx, adminName: adminName, clearDirty: true)
        let driverLabel = CountRecordLogic.driverDisplayName(tripUnits[idx].driverId, employees: employees)
        let event = CountRecordWriter.vehicleStatusEventPayload(
            dateYmd: dayKey,
            vehicleId: tripUnits[idx].vehicleId,
            driverLabel: driverLabel,
            adminName: adminName,
            broken: false,
            stamp: stamp
        )
        _ = await CountRecordOfflineSync.shared.persist(payload: event, wasPersisted: false)
        flash("ปรับ \(tripUnits[idx].vehicleId) เป็นรถปกติแล้ว")
    }

    func recordTrip(unitId: String, appState: AppState, adminName: String) async {
        guard ensureToday() else { return }
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        var unit = tripUnits[idx]
        guard unit.canRecord else {
            if unit.isSupport { flash("ชัพพอต — ไม่บันทึกเที่ยว", error: true) }
            else if unit.isBroken { flash("รถเสีย — ยังบันทึกเที่ยวไม่ได้", error: true) }
            else if unit.isCoolingDown { flash("รอสักครู่…", error: true) }
            return
        }

        let prevRounds = unit.rounds
        let prevLaps = unit.lapTimes
        let prevCombo = unit.comboCount
        let prevLast = unit.lastRecordAt
        let now = Date()
        let stamp = CountRecordLogic.formatLapStamp(now)
        let keepsCombo = prevLast.map { now.timeIntervalSince($0) <= 10 } ?? false

        unit.busy = true
        unit.dirty = true
        unit.lapTimes.append(stamp)
        unit.rounds = max(unit.lapTimes.count, unit.rounds + 1)
        unit.comboCount = keepsCombo ? unit.comboCount + 1 : 1
        unit.lastRecordAt = now
        unit.cooldownUntil = now.addingTimeInterval(3)
        tripUnits[idx] = unit
        skipExternalReload += 1

        let result = await CountRecordWriter.saveTrip(
            id: unit.id,
            dateYmd: dayKey,
            vehicleId: unit.vehicleId,
            driverId: unit.driverId,
            rounds: unit.rounds,
            lapTimes: unit.lapTimes,
            adminName: adminName,
            wasPersisted: unit.persisted,
            workDetails: unit.workDetails,
            isSupport: false
        )

        if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
            // Success path — writer always updates AppState; treat as success unless we need rollback
            tripUnits[i].persisted = !result.deleted
            tripUnits[i].dirty = false
            tripUnits[i].busy = false
            let goal = CountRecordPrefs.tripGoal
            if goal > 0 && tripUnits[i].rounds == goal {
                flash("\(unit.vehicleId) ครบเป้า \(goal) เที่ยวแล้ว!")
            } else {
                let combo = tripUnits[i].comboCount
                let base = result.queued
                    ? "+\(unit.vehicleId) · \(stamp) (รอซิงค์)"
                    : "+\(unit.vehicleId) · \(stamp)"
                flash(combo > 1 ? "\(base) · ×\(combo)" : base)
            }
            pendingUndo = CountRecordUndoAction(
                kind: .trip(unitId: tripUnits[i].id),
                message: "เลิกทำเที่ยวล่าสุด",
                stamp: stamp
            )
        } else {
            // rollback
            unit.rounds = prevRounds
            unit.lapTimes = prevLaps
            unit.comboCount = prevCombo
            unit.lastRecordAt = prevLast
            unit.busy = false
            unit.dirty = false
            if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
                tripUnits[i] = unit
            }
            flash("บันทึกไม่สำเร็จ", error: true)
        }
    }

    func undoTrip(unitId: String, appState: AppState, adminName: String, confirmStamp: String? = nil) async {
        guard ensureToday() else { return }
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        var unit = tripUnits[idx]
        guard !unit.busy, !unit.lapTimes.isEmpty else {
            flash("ยังไม่มีเที่ยวให้ลบ", error: true)
            return
        }
        if let confirmStamp, unit.lapTimes.last != confirmStamp {
            // still allow last if stamp drifted
        }

        let removed = unit.lapTimes.removeLast()
        unit.rounds = max(0, unit.rounds - 1)
        if unit.rounds < unit.lapTimes.count { unit.rounds = unit.lapTimes.count }
        unit.busy = true
        unit.dirty = true
        tripUnits[idx] = unit
        skipExternalReload += 1

        let result = await CountRecordWriter.saveTrip(
            id: unit.id,
            dateYmd: dayKey,
            vehicleId: unit.vehicleId,
            driverId: unit.driverId,
            rounds: unit.rounds,
            lapTimes: unit.lapTimes,
            adminName: adminName,
            wasPersisted: unit.persisted,
            workDetails: unit.workDetails,
            isSupport: unit.isSupport
        )
        if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
            if result.deleted {
                tripUnits[i].persisted = unit.isSupport
            } else {
                tripUnits[i].persisted = true
            }
            tripUnits[i].busy = false
            tripUnits[i].dirty = false
            flash("ลบเที่ยว \(removed)")
        }
        if pendingUndo?.stamp == removed { pendingUndo = nil }
    }

    func recordSand(appState: AppState, adminName: String) async {
        guard ensureToday() else { return }
        guard var unit = sandUnit, !unit.busy, !unit.isCoolingDown else { return }

        let now = Date()
        let stamp = CountRecordLogic.formatLapStamp(now)
        let keepsCombo = unit.lastRecordAt.map { now.timeIntervalSince($0) <= 10 } ?? false
        unit.busy = true
        unit.dirty = true
        unit.lapTimes.append(stamp)
        unit.rounds = max(unit.lapTimes.count, unit.rounds + 1)
        unit.comboCount = keepsCombo ? unit.comboCount + 1 : 1
        unit.lastRecordAt = now
        unit.cooldownUntil = now.addingTimeInterval(3)
        sandUnit = unit
        skipExternalReload += 1

        let result = await CountRecordWriter.saveSand(
            id: unit.id,
            dateYmd: dayKey,
            rounds: unit.rounds,
            lapTimes: unit.lapTimes,
            adminName: adminName,
            wasPersisted: unit.persisted
        )
        unit.persisted = !result.deleted
        unit.busy = false
        unit.dirty = false
        sandUnit = unit
        let msg = result.queued ? "ร่อน +\(unit.rounds) · \(stamp) (รอซิงค์)" : "ร่อน +\(unit.rounds) · \(stamp)"
        flash(unit.comboCount > 1 ? "\(msg) · ×\(unit.comboCount)" : msg)
        pendingUndo = CountRecordUndoAction(kind: .sand, message: "เลิกทำรอบล่าสุด", stamp: stamp)
    }

    func undoSand(appState: AppState, adminName: String, removeStamp: String? = nil) async {
        guard ensureToday() else { return }
        guard var unit = sandUnit, !unit.busy, !unit.lapTimes.isEmpty else {
            flash("ยังไม่มีรอบให้ลบ", error: true)
            return
        }

        let removed: String
        if let stamp = removeStamp, let i = unit.lapTimes.lastIndex(of: stamp) {
            removed = unit.lapTimes.remove(at: i)
        } else {
            removed = unit.lapTimes.removeLast()
        }
        unit.rounds = max(unit.lapTimes.count, unit.rounds - 1)
        if unit.rounds > unit.lapTimes.count { unit.rounds = unit.lapTimes.count }
        unit.busy = true
        unit.dirty = true
        sandUnit = unit
        skipExternalReload += 1

        let result = await CountRecordWriter.saveSand(
            id: unit.id,
            dateYmd: dayKey,
            rounds: unit.rounds,
            lapTimes: unit.lapTimes,
            adminName: adminName,
            wasPersisted: unit.persisted
        )
        if result.deleted {
            unit.persisted = false
            unit.id = CountRecordWriter.newTransactionId(suffix: "sand")
        } else {
            unit.persisted = true
        }
        unit.busy = false
        unit.dirty = false
        sandUnit = unit
        flash("ลบรอบ \(removed)")
        if pendingUndo?.stamp == removed { pendingUndo = nil }
    }

    func performPendingUndo(appState: AppState, adminName: String) async {
        guard let action = pendingUndo else { return }
        switch action.kind {
        case .trip(let id):
            await undoTrip(unitId: id, appState: appState, adminName: adminName, confirmStamp: action.stamp)
        case .sand:
            await undoSand(appState: appState, adminName: adminName, removeStamp: action.stamp)
        }
    }

    func resyncCubic(appState: AppState, adminName: String) async {
        for idx in tripUnits.indices where !tripUnits[idx].isSupport && tripUnits[idx].persisted {
            tripUnits[idx].dirty = true
            await persistTrip(at: idx, adminName: adminName, clearDirty: true)
        }
        flash("อัปเดตคิว/เที่ยวแล้ว")
    }

    private func persistTrip(at idx: Int, adminName: String, clearDirty: Bool) async {
        guard tripUnits.indices.contains(idx) else { return }
        var unit = tripUnits[idx]
        unit.busy = true
        tripUnits[idx] = unit
        skipExternalReload += 1
        let result = await CountRecordWriter.saveTrip(
            id: unit.id,
            dateYmd: dayKey,
            vehicleId: unit.vehicleId,
            driverId: unit.driverId,
            rounds: unit.rounds,
            lapTimes: unit.lapTimes,
            adminName: adminName,
            wasPersisted: unit.persisted,
            workDetails: unit.workDetails,
            isSupport: unit.isSupport
        )
        if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
            tripUnits[i].persisted = !result.deleted || unit.isSupport
            tripUnits[i].busy = false
            if clearDirty { tripUnits[i].dirty = false }
        }
    }

    func flash(_ message: String, error: Bool = false) {
        statusMessage = message
        isErrorStatus = error
    }
}
