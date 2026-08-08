import Foundation
import Observation

/// Mutable in-memory unit for the trip counter panel.
struct CountRecordTripDraft: Identifiable, Equatable {
    var id: String
    var vehicleId: String
    var driverId: String
    var rounds: Int
    var lapTimes: [String]
    var persisted: Bool
    var busy: Bool = false

    var periodSplit: (morning: Int, afternoon: Int, ot: Int) {
        var morning = 0, afternoon = 0, ot = 0
        for lap in lapTimes {
            guard let h = CountRecordLogic.lapHour(lap) else {
                morning += 1
                continue
            }
            if h < 12 {
                morning += 1
            } else {
                afternoon += 1
                if h >= CountRecordLogic.otStartHour { ot += 1 }
            }
        }
        return (morning, afternoon, ot)
    }
}

/// Mutable sand counter draft.
struct CountRecordSandDraft: Identifiable, Equatable {
    var id: String
    var rounds: Int
    var lapTimes: [String]
    var persisted: Bool
    var busy: Bool = false

    var recentLaps: [String] {
        Array(lapTimes.suffix(CountRecordLogic.sandRecentLaps).reversed())
    }
}

/// Session state for count-record editing (today only).
@MainActor
@Observable
final class CountRecordSession {
    var mode: CountRecordWorkMode?
    var tripUnits: [CountRecordTripDraft] = []
    var sandUnit: CountRecordSandDraft?
    var statusMessage: String?
    var isErrorStatus = false
    var showAddVehicle = false

    private(set) var dayKey: String = DashboardAggregations.todayYMD()

    func ensureToday() -> Bool {
        let today = DashboardAggregations.todayYMD()
        if dayKey != today {
            dayKey = today
            statusMessage = "บันทึกได้เฉพาะวันปัจจุบัน — เปลี่ยนเป็นวันนี้แล้ว กดนับอีกครั้ง"
            isErrorStatus = false
            return false
        }
        return true
    }

    func loadFromAppState(_ appState: AppState) {
        dayKey = DashboardAggregations.todayYMD()
        let dayTx = appState.transactions.filter { String($0.date.prefix(10)) == dayKey }
        let built = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: dayTx,
            employees: appState.employees
        )
        tripUnits = built.map { u in
            CountRecordTripDraft(
                id: u.id,
                vehicleId: u.vehicleId,
                driverId: u.driverId,
                rounds: u.rounds,
                lapTimes: u.lapTimes,
                persisted: true
            )
        }
        if let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx) {
            sandUnit = CountRecordSandDraft(
                id: sand.id,
                rounds: sand.rounds,
                lapTimes: sand.lapTimes,
                persisted: true
            )
        } else {
            sandUnit = CountRecordSandDraft(
                id: CountRecordWriter.newTransactionId(suffix: "sand"),
                rounds: 0,
                lapTimes: [],
                persisted: false
            )
        }
    }

    func availableCars(settings: AppSettings) -> [String] {
        let added = Set(tripUnits.map(\.vehicleId))
        return settings.cars
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && CountRecordLogic.isDrumTripVehicleId($0) && !added.contains($0) }
    }

    func addVehicle(vehicleId: String, driverId: String) {
        let vid = vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vid.isEmpty else { return }
        guard !tripUnits.contains(where: { $0.vehicleId == vid }) else { return }
        tripUnits.append(
            CountRecordTripDraft(
                id: CountRecordWriter.newTransactionId(suffix: vid),
                vehicleId: vid,
                driverId: driverId.trimmingCharacters(in: .whitespacesAndNewlines),
                rounds: 0,
                lapTimes: [],
                persisted: false
            )
        )
    }

    func recordTrip(
        unitId: String,
        appState: AppState,
        adminName: String
    ) async {
        guard ensureToday() else { return }
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        guard !tripUnits[idx].busy else { return }
        guard let service = appState.supabaseService else {
            flash("ยังไม่ได้ตั้งค่า Supabase", error: true)
            return
        }

        var unit = tripUnits[idx]
        let prevRounds = unit.rounds
        let prevLaps = unit.lapTimes
        let stamp = CountRecordLogic.formatLapStamp()
        unit.busy = true
        unit.lapTimes.append(stamp)
        unit.rounds = max(unit.lapTimes.count, unit.rounds + 1)
        tripUnits[idx] = unit

        do {
            let saved = try await CountRecordWriter.saveTrip(
                service: service,
                appState: appState,
                id: unit.id,
                dateYmd: dayKey,
                vehicleId: unit.vehicleId,
                driverId: unit.driverId,
                rounds: unit.rounds,
                lapTimes: unit.lapTimes,
                adminName: adminName,
                wasPersisted: unit.persisted
            )
            if let saved {
                unit.id = saved.id
                unit.persisted = true
            }
            unit.busy = false
            if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
                tripUnits[i] = unit
            }
            flash("+\(unit.vehicleId) · \(stamp)")
        } catch {
            unit.rounds = prevRounds
            unit.lapTimes = prevLaps
            unit.busy = false
            if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
                tripUnits[i] = unit
            }
            flash("บันทึกไม่สำเร็จ: \(error.localizedDescription)", error: true)
        }
    }

    func undoTrip(
        unitId: String,
        appState: AppState,
        adminName: String
    ) async {
        guard ensureToday() else { return }
        guard let idx = tripUnits.firstIndex(where: { $0.id == unitId }) else { return }
        var unit = tripUnits[idx]
        guard !unit.busy, unit.rounds > 0, !unit.lapTimes.isEmpty else {
            flash("ยังไม่มีเที่ยวให้ลบ", error: true)
            return
        }
        guard let service = appState.supabaseService else {
            flash("ยังไม่ได้ตั้งค่า Supabase", error: true)
            return
        }

        let prevRounds = unit.rounds
        let prevLaps = unit.lapTimes
        let removed = unit.lapTimes.removeLast()
        unit.rounds = max(0, unit.rounds - 1)
        if unit.rounds < unit.lapTimes.count { unit.rounds = unit.lapTimes.count }
        unit.busy = true
        tripUnits[idx] = unit

        do {
            let saved = try await CountRecordWriter.saveTrip(
                service: service,
                appState: appState,
                id: unit.id,
                dateYmd: dayKey,
                vehicleId: unit.vehicleId,
                driverId: unit.driverId,
                rounds: unit.rounds,
                lapTimes: unit.lapTimes,
                adminName: adminName,
                wasPersisted: unit.persisted
            )
            if saved == nil {
                unit.persisted = false
            } else if let saved {
                unit.id = saved.id
                unit.persisted = true
            }
            unit.busy = false
            if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
                tripUnits[i] = unit
            }
            flash("ลบเที่ยว \(removed)")
        } catch {
            unit.rounds = prevRounds
            unit.lapTimes = prevLaps
            unit.busy = false
            if let i = tripUnits.firstIndex(where: { $0.vehicleId == unit.vehicleId }) {
                tripUnits[i] = unit
            }
            flash("ลบไม่สำเร็จ: \(error.localizedDescription)", error: true)
        }
    }

    func recordSand(appState: AppState, adminName: String) async {
        guard ensureToday() else { return }
        guard var unit = sandUnit, !unit.busy else { return }
        guard let service = appState.supabaseService else {
            flash("ยังไม่ได้ตั้งค่า Supabase", error: true)
            return
        }

        let prevRounds = unit.rounds
        let prevLaps = unit.lapTimes
        let stamp = CountRecordLogic.formatLapStamp()
        unit.busy = true
        unit.lapTimes.append(stamp)
        unit.rounds = max(unit.lapTimes.count, unit.rounds + 1)
        sandUnit = unit

        do {
            let saved = try await CountRecordWriter.saveSand(
                service: service,
                appState: appState,
                id: unit.id,
                dateYmd: dayKey,
                rounds: unit.rounds,
                lapTimes: unit.lapTimes,
                adminName: adminName,
                wasPersisted: unit.persisted
            )
            if let saved {
                unit.id = saved.id
                unit.persisted = true
            }
            unit.busy = false
            sandUnit = unit
            flash("ร่อน +\(unit.rounds) · \(stamp)")
        } catch {
            unit.rounds = prevRounds
            unit.lapTimes = prevLaps
            unit.busy = false
            sandUnit = unit
            flash("บันทึกไม่สำเร็จ: \(error.localizedDescription)", error: true)
        }
    }

    func undoSand(appState: AppState, adminName: String) async {
        guard ensureToday() else { return }
        guard var unit = sandUnit, !unit.busy, unit.rounds > 0, !unit.lapTimes.isEmpty else {
            flash("ยังไม่มีรอบให้ลบ", error: true)
            return
        }
        guard let service = appState.supabaseService else {
            flash("ยังไม่ได้ตั้งค่า Supabase", error: true)
            return
        }

        let prevRounds = unit.rounds
        let prevLaps = unit.lapTimes
        let removed = unit.lapTimes.removeLast()
        unit.rounds = max(0, unit.rounds - 1)
        if unit.rounds < unit.lapTimes.count { unit.rounds = unit.lapTimes.count }
        unit.busy = true
        sandUnit = unit

        do {
            let saved = try await CountRecordWriter.saveSand(
                service: service,
                appState: appState,
                id: unit.id,
                dateYmd: dayKey,
                rounds: unit.rounds,
                lapTimes: unit.lapTimes,
                adminName: adminName,
                wasPersisted: unit.persisted
            )
            if saved == nil {
                unit.persisted = false
                unit.id = CountRecordWriter.newTransactionId(suffix: "sand")
            } else if let saved {
                unit.id = saved.id
                unit.persisted = true
            }
            unit.busy = false
            sandUnit = unit
            flash("ลบรอบ \(removed)")
        } catch {
            unit.rounds = prevRounds
            unit.lapTimes = prevLaps
            unit.busy = false
            sandUnit = unit
            flash("ลบไม่สำเร็จ: \(error.localizedDescription)", error: true)
        }
    }

    private func flash(_ message: String, error: Bool = false) {
        statusMessage = message
        isErrorStatus = error
    }
}
