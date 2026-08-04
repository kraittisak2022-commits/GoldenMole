import Foundation
import SwiftUI

/// Fill state of one Android daily-menu card, matching Flutter `DailyModuleFillStatus`.
enum MobileDailyFillStatus: String, Sendable {
    /// No related data for the day.
    case pending
    /// Something was started but the menu's completion rule is not met yet.
    case incomplete
    /// Meets the Android dashboard "ครบแล้ว" rule.
    case complete

    var label: String {
        switch self {
        case .pending: return "ยังไม่กรอก"
        case .incomplete: return "กรอกไม่ครบ"
        case .complete: return "ครบแล้ว"
        }
    }

    var color: Color {
        switch self {
        case .pending: return AppTheme.inkMuted
        case .incomplete: return AppTheme.warning
        case .complete: return AppTheme.income
        }
    }

    var systemImage: String {
        switch self {
        case .pending: return "circle"
        case .incomplete: return "exclamationmark.circle.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

/// One of the four Android menus this audit watches.
enum MobileDailyAuditKind: String, CaseIterable, Identifiable, Sendable {
    case countRecord
    case attendance
    case macro
    case fuel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .countRecord: return "บันทึกและนับจำนวน"
        case .attendance: return "เช็คชื่อ"
        case .macro: return "การใช้รถแม็คโคร"
        case .fuel: return "น้ำมัน"
        }
    }

    var systemImage: String {
        switch self {
        case .countRecord: return "plusminus.circle.fill"
        case .attendance: return "person.crop.circle.badge.checkmark"
        case .macro: return "excavator.fill"
        case .fuel: return "fuelpump.fill"
        }
    }

    var accent: Color {
        switch self {
        case .countRecord: return AppTheme.info
        case .attendance: return AppTheme.labor
        case .macro: return AppTheme.vehicle
        case .fuel: return AppTheme.fuel
        }
    }
}

struct MobileDailyAuditItem: Identifiable, Sendable {
    let kind: MobileDailyAuditKind
    let status: MobileDailyFillStatus
    /// Short numbers for the tile, e.g. "3 คัน · 12 เที่ยว".
    let headline: String
    /// Extra line under the headline.
    let detail: String?

    var id: String { kind.id }
    var isOk: Bool { status == .complete }
}

struct MobileDailyAuditDay: Sendable {
    let dayKey: String
    let items: [MobileDailyAuditItem]

    var completedCount: Int { items.filter(\.isOk).count }
    var itemCount: Int { items.count }
    var completion: Double {
        guard itemCount > 0 else { return 0 }
        return Double(completedCount) / Double(itemCount)
    }

    var missingTitles: [String] {
        items.filter { $0.status != .complete }.map(\.kind.title)
    }

    /// True when every watched menu is still `pending` — no mobile daily work that day.
    var isEmpty: Bool {
        items.allSatisfy { $0.status == .pending }
    }

    static func empty(dayKey: String) -> MobileDailyAuditDay {
        MobileDailyAuditDay(
            dayKey: dayKey,
            items: MobileDailyAuditKind.allCases.map {
                MobileDailyAuditItem(kind: $0, status: .pending, headline: "—", detail: nil)
            }
        )
    }
}

/// Off-main builder that ports the Android dashboard fill rules for the four
/// menus the Reports tab watches: count-record, attendance, macro excavator, fuel.
enum MobileDailyAuditSnapshot {
    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee]
    ) -> MobileDailyAuditDay {
        guard !dayKey.isEmpty else { return .empty(dayKey: dayKey) }
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }

        return MobileDailyAuditDay(
            dayKey: dayKey,
            items: [
                countRecordItem(dayKey: dayKey, dayTx: dayTx, all: transactions, employees: employees),
                attendanceItem(dayKey: dayKey, dayTx: dayTx, all: transactions, employees: employees),
                macroItem(dayTx: dayTx),
                fuelItem(dayTx: dayTx)
            ]
        )
    }

    /// Newest day (within the fetch window) that has any of the four menus filled at all.
    nonisolated static func latestDayWithRecords(
        in transactions: [Transaction],
        onOrBefore dayKey: String = DashboardAggregations.todayYMD()
    ) -> String? {
        let candidates = Set(
            transactions
                .map { String($0.date.prefix(10)) }
                .filter { $0 <= dayKey && !$0.isEmpty }
        )
        for day in candidates.sorted(by: >) {
            let audit = build(dayKey: day, transactions: transactions, employees: [])
            if !audit.isEmpty { return day }
        }
        return nil
    }

    // MARK: - บันทึกและนับจำนวน

    nonisolated private static func countRecordItem(
        dayKey: String,
        dayTx: [Transaction],
        all: [Transaction],
        employees: [Employee]
    ) -> MobileDailyAuditItem {
        var complete = false
        var touch = false
        for t in dayTx {
            if countRecordRowHasSavedData(t) {
                complete = true
                break
            }
            if countRecordRowTouches(t) { touch = true }
        }
        let status: MobileDailyFillStatus = complete ? .complete : (touch ? .incomplete : .pending)

        let ops = MobileOpsSnapshot.metricsForDay(
            dayKey: dayKey,
            transactions: all,
            employees: employees
        )
        var parts: [String] = []
        if ops.tripRounds > 0 || ops.tripVehicles > 0 {
            parts.append("\(ops.tripVehicles) คัน · \(ops.tripRounds) เที่ยว")
        }
        if ops.sandRounds > 0 {
            parts.append("ร่อน \(ops.sandRounds) รอบ")
        }
        let headline = parts.isEmpty ? (status == .pending ? "—" : "มีแถวแต่ยังไม่มีตัวเลข") : parts.joined(separator: " · ")
        let detail: String? = ops.tripCubic > 0
            ? "\(DashboardAggregations.formatNumber(ops.tripCubic)) คิว"
            : nil
        return MobileDailyAuditItem(kind: .countRecord, status: status, headline: headline, detail: detail)
    }

    nonisolated private static func countRecordRowHasSavedData(_ t: Transaction) -> Bool {
        if CountRecordLogic.isCountRecordVehicleRow(t) {
            let trips = t.perCarTrips ?? t.tripCount ?? 0
            return trips > 0 || !CountRecordLogic.getLapTimes(t).isEmpty
        }
        if isCountRecordSandMenuRow(t) {
            let drums = t.drumsObtained ?? 0
            return drums > 0 || !CountRecordLogic.getLapTimes(t).isEmpty
        }
        return false
    }

    nonisolated private static func countRecordRowTouches(_ t: Transaction) -> Bool {
        if CountRecordLogic.isCountRecordVehicleRow(t) {
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let did = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !vid.isEmpty || !did.isEmpty
        }
        return isCountRecordSandMenuRow(t)
    }

    /// Broader than the tap-counter sand filter — any DailyLog/Sand row that is not home-wash.
    nonisolated private static func isCountRecordSandMenuRow(_ t: Transaction) -> Bool {
        guard t.category == "DailyLog",
              (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sand"
        else { return false }
        return !t.description.contains("ทรายที่ล้างที่บ้าน")
    }

    // MARK: - เช็คชื่อ

    nonisolated private static func attendanceItem(
        dayKey: String,
        dayTx: [Transaction],
        all: [Transaction],
        employees: [Employee]
    ) -> MobileDailyAuditItem {
        let roster = employees.filter(\.isHomeAttendancePool)
        let rosterIds = Set(roster.map(\.id))

        func touchesRoster(_ t: Transaction) -> Bool {
            (t.employeeIds ?? []).contains { rosterIds.contains($0) }
        }

        let hasWork = dayTx.contains { isAttendanceWorkRow($0) && touchesRoster($0) }
        let hasLeave = all.contains {
            CalendarV3Logic.leaveRecordCoversDay($0, day: dayKey) && touchesRoster($0)
        }
        let hasOT = dayTx.contains { isAttendanceOTRow($0) && touchesRoster($0) }
        let status: MobileDailyFillStatus = (hasWork || hasLeave || hasOT) ? .complete : .pending

        let counts = DashboardAggregations.attendanceCounts(
            dayTx: dayTx,
            allTransactions: all,
            employees: roster,
            dayKey: dayKey
        )
        let headline: String
        if status == .pending {
            headline = "—"
        } else {
            headline = "มา \(counts.present) · ลา \(counts.leave) · ขาด \(counts.absent)"
        }
        return MobileDailyAuditItem(
            kind: .attendance,
            status: status,
            headline: headline,
            detail: roster.isEmpty
                ? nil
                : "ท่าทราย + แม็คโคร \(roster.count) คน"
        )
    }

    nonisolated private static func isAttendanceWorkRow(_ t: Transaction) -> Bool {
        guard t.category == "Labor" else { return false }
        let ls = (t.laborStatus ?? "").lowercased()
        let sc = (t.subCategory ?? "").lowercased()
        if sc == "ot" || ls == "ot" { return false }
        if sc == "advance" || ls == "advance" { return false }
        if ls == "leave" || ls == "sick" || ls == "personal" { return false }
        return true
    }

    nonisolated private static func isAttendanceOTRow(_ t: Transaction) -> Bool {
        guard t.category == "Labor" else { return false }
        let ls = (t.laborStatus ?? "").uppercased()
        let sc = (t.subCategory ?? "").lowercased()
        return ls == "OT" || sc == "ot"
    }

    // MARK: - การใช้รถแม็คโคร

    nonisolated private static func macroItem(dayTx: [Transaction]) -> MobileDailyAuditItem {
        var complete = false
        var touch = false
        var vehicleIds = Set<String>()
        var driverIds = Set<String>()

        for t in dayTx where t.category == "Vehicle" && CountRecordLogic.isMacroVehicleId(t.vehicleId) {
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let did = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let details = (t.workDetails ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !vid.isEmpty { vehicleIds.insert(vid) }
            if !did.isEmpty { driverIds.insert(did) }
            if !vid.isEmpty && !did.isEmpty {
                complete = true
            } else if !vid.isEmpty || !did.isEmpty || !details.isEmpty {
                touch = true
            }
        }

        let status: MobileDailyFillStatus = complete ? .complete : (touch ? .incomplete : .pending)
        let headline: String
        switch status {
        case .pending:
            headline = "—"
        case .incomplete:
            headline = "มีแถวแต่ยังไม่ครบคนขับ"
        case .complete:
            headline = "ใช้แม็คโคร \(vehicleIds.count) คัน"
        }
        let detail = driverIds.isEmpty ? nil : "คนขับ \(driverIds.count) คน"
        return MobileDailyAuditItem(kind: .macro, status: status, headline: headline, detail: detail)
    }

    // MARK: - น้ำมัน

    nonisolated private static func fuelItem(dayTx: [Transaction]) -> MobileDailyAuditItem {
        let used = Set(
            dayTx
                .filter { DashboardAggregations.isMacroUsageRow($0) }
                .compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let fueled = Set(
            dayTx
                .filter { isFuelVehicleUsageRow($0) }
                .compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let liters = dayTx
            .filter { isFuelVehicleUsageRow($0) }
            .reduce(0.0) { $0 + ($1.quantity ?? 0) }
        let anyFuelTouch = dayTx.contains { $0.category == "Fuel" }

        let status: MobileDailyFillStatus
        if !used.isEmpty {
            status = used.isSubset(of: fueled) ? .complete : .incomplete
        } else if !fueled.isEmpty || liters > 0 {
            status = .complete
        } else if anyFuelTouch {
            status = .incomplete
        } else {
            status = .pending
        }

        let headline: String
        if status == .pending {
            headline = "—"
        } else if !used.isEmpty {
            headline = "แจ้ง \(fueled.intersection(used).count)/\(used.count) คันที่ใช้"
        } else if !fueled.isEmpty {
            headline = "แจ้ง \(fueled.count) คัน"
        } else {
            headline = "มีบันทึกน้ำมัน"
        }
        let detail = liters > 0
            ? "\(DashboardAggregations.formatNumber(liters)) ลิตร"
            : nil
        return MobileDailyAuditItem(kind: .fuel, status: status, headline: headline, detail: detail)
    }

    /// Flutter `isFuelVehicleUsageRow` — stock-out row with a vehicle and liters.
    nonisolated private static func isFuelVehicleUsageRow(_ t: Transaction) -> Bool {
        guard t.category == "Fuel" else { return false }
        if DashboardAggregations.inferFuelMovement(t) == "stock_in" { return false }
        let vehicle = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicle.isEmpty else { return false }
        return (t.quantity ?? 0) > 0
    }
}
