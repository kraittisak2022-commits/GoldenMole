import Foundation

// MARK: - Calendar V.3 domain model
//
// Mirrors the web source of truth in `src/modules/Dashboard/CalendarView.tsx`
// (menu: ภาพรวม > หน้าแดชบอร์ด > ปฏิทินการทำงาน (V.3)).
// All date-key math uses `DashboardAggregations.gregorian`; Buddhist era is
// used only for display strings in the view layer.

/// A single calendar entry (วันหยุด / นัดหมาย / เหตุการณ์) shown for a day.
/// Matches the web `Calendar`-category transactions plus the auto-injected
/// public-holiday row.
struct CalendarEntry: Identifiable, Sendable {
    let id: String
    /// "Holiday" | "Appointment" | "Reminder"
    let subCategory: String
    let title: String
    let eventTime: String?
    let note: String?
    let isAuto: Bool

    var kindLabel: String { CalendarV3Logic.kindLabel(subCategory) }
}

/// Per-day aggregation matching the web `daysInMonth` memo.
struct CalendarDayModel: Identifiable, Sendable {
    /// yyyy-MM-dd (also the stable id).
    let id: String
    let day: Int
    let date: String
    let income: Double
    let expense: Double
    let presentCount: Int
    let leaveCount: Int
    let missingCount: Int
    let leaveNames: [String]
    let calendarRows: [CalendarEntry]
    let financeTransactions: [Transaction]
    let machineLogs: [Transaction]
    let sandLogs: [Transaction]
    let eventLogs: [Transaction]
    /// Count-record activity for the day (same marks as Realtime focus calendar).
    let opsMark: CountRecordLogic.DayOpsMark

    var net: Double { income - expense }
    var hasFinance: Bool { income > 0 || expense > 0 }
    var hasHoliday: Bool { calendarRows.contains { $0.subCategory == "Holiday" } }
    var hasAppointment: Bool { calendarRows.contains { $0.subCategory == "Appointment" } }
    var hasReminder: Bool { calendarRows.contains { $0.subCategory == "Reminder" } }
    var hasTripOps: Bool { opsMark == .tripOnly || opsMark == .both }
    var hasSandOps: Bool { opsMark == .sandOnly || opsMark == .both }
}

enum CalendarV3Logic {
    static let calendarCategory = "Calendar"

    struct PublicHoliday: Sendable {
        let id: String
        let date: String
        let name: String
    }

    static func kindLabel(_ sub: String?) -> String {
        switch sub {
        case "Holiday": return "วันหยุด"
        case "Appointment": return "นัดหมาย"
        case "Reminder": return "เหตุการณ์ / อื่นๆ"
        default: return sub?.isEmpty == false ? (sub ?? "ปฏิทิน") : "ปฏิทิน"
        }
    }

    static func isCalendarTx(_ t: Transaction) -> Bool {
        t.category == calendarCategory
    }

    /// Thai public holidays — identical list/order to the web
    /// `getThaiPublicHolidays` in `src/utils/index.ts`.
    static func publicHolidayMap(year: Int) -> [String: PublicHoliday] {
        let rows: [(String, String)] = [
            ("01-01", "วันขึ้นปีใหม่"),
            ("02-12", "วันมาฆบูชา"),
            ("04-06", "วันจักรี"),
            ("04-13", "วันสงกรานต์"),
            ("04-14", "วันสงกรานต์"),
            ("04-15", "วันสงกรานต์"),
            ("05-01", "วันแรงงานแห่งชาติ"),
            ("05-04", "วันฉัตรมงคล"),
            ("05-11", "วันพืชมงคล (ประมาณการ)"),
            ("06-03", "วันเฉลิมพระชนมพรรษา สมเด็จพระราชินี"),
            ("07-10", "วันอาสาฬหบูชา (ประมาณการ)"),
            ("07-11", "วันเข้าพรรษา (ประมาณการ)"),
            ("07-28", "วันเฉลิมพระชนมพรรษา ร.10"),
            ("08-12", "วันแม่แห่งชาติ"),
            ("10-13", "วันนวมินทรมหาราช"),
            ("10-23", "วันปิยมหาราช"),
            ("12-05", "วันพ่อแห่งชาติ"),
            ("12-10", "วันรัฐธรรมนูญ"),
            ("12-31", "วันสิ้นปี")
        ]
        var map: [String: PublicHoliday] = [:]
        for (md, name) in rows {
            let date = "\(year)-\(md)"
            map[date] = PublicHoliday(id: "holiday_\(year)_\(md)", date: date, name: name)
        }
        return map
    }

    /// Matches the web `isLaborLeaveRecord` in `src/utils/laborLeaveSpan.ts`.
    static func isLaborLeaveRecord(_ t: Transaction) -> Bool {
        let n = (t.employeeIds ?? []).filter { !$0.isEmpty }.count
        if n == 0 { return false }
        if t.category == "Leave" || t.type == .leave { return true }
        let ls = (t.laborStatus ?? "").lowercased()
        return t.category == "Labor" && (ls == "leave" || ls == "sick" || ls == "personal")
    }

    /// Matches the web `leaveRecordCoversDay` — inclusive multi-day span using
    /// ceil(leaveDays) (e.g. 1.5 days covers 2 calendar days).
    static func leaveRecordCoversDay(_ t: Transaction, day: String) -> Bool {
        guard isLaborLeaveRecord(t) else { return false }
        let start = String(t.date.prefix(10))
        let needle = String(day.prefix(10))
        let span = max(1, Int(ceil(t.leaveDays ?? 1)))
        let end = DashboardAggregations.shiftDateStr(start, deltaDays: span - 1)
        return needle >= start && needle <= end
    }

    /// Builds the per-day models for a whole month. `visibleMonth` is any date
    /// inside the target month.
    ///
    /// Indexes transactions once (O(n)) instead of re-scanning the full list per day.
    static func buildDays(
        visibleMonth: Date,
        transactions: [Transaction],
        employees: [Employee]
    ) -> [CalendarDayModel] {
        let cal = DashboardAggregations.gregorian
        let year = cal.component(.year, from: visibleMonth)
        let month = cal.component(.month, from: visibleMonth)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }

        let monthPrefix = String(format: "%04d-%02d-", year, month)
        let holidayMap = publicHolidayMap(year: year)
        let roster = employees.filter(\.isHomeAttendancePool)
        let rosterIds = Set(roster.map(\.id))
        let totalEmployees = roster.count
        let rosterById = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })

        var byDay: [String: [Transaction]] = [:]
        byDay.reserveCapacity(min(transactions.count, 64))
        var leaveCandidates: [Transaction] = []
        for t in transactions {
            let key = String(t.date.prefix(10))
            if key.hasPrefix(monthPrefix) {
                byDay[key, default: []].append(t)
            }
            if isLaborLeaveRecord(t) {
                leaveCandidates.append(t)
            }
        }

        return range.map { d in
            let dateStr = String(format: "%04d-%02d-%02d", year, month, d)
            let dayTrans = byDay[dateStr] ?? []
            let financeTrans = dayTrans.filter { !isCalendarTx($0) }

            var inc = 0.0
            var exp = 0.0
            var workingIds = Set<String>()
            var machineLogs: [Transaction] = []
            var sandLogs: [Transaction] = []
            var eventLogs: [Transaction] = []
            var hasTrip = false
            var hasSand = false

            for t in financeTrans {
                if t.type == .income { inc += t.amount }
                else if t.type == .expense { exp += t.amount }

                if t.category == "Labor", t.laborStatus == "Work" || t.laborStatus == "OT" {
                    for id in (t.employeeIds ?? []) where rosterIds.contains(id) {
                        workingIds.insert(id)
                    }
                }

                if t.category == "DailyLog" {
                    switch t.subCategory {
                    case "MachineWork", "VehicleTrip":
                        machineLogs.append(t)
                    case "Sand":
                        sandLogs.append(t)
                        hasSand = true
                    case "Event":
                        eventLogs.append(t)
                    default:
                        break
                    }
                }

                if !hasTrip,
                   CountRecordLogic.isCountRecordVehicleRow(t),
                   CountRecordLogic.tripRounds(from: t) > 0 {
                    hasTrip = true
                }
            }

            var leaveIds = Set<String>()
            for t in leaveCandidates where leaveRecordCoversDay(t, day: dateStr) {
                for id in (t.employeeIds ?? []) where rosterIds.contains(id) {
                    leaveIds.insert(id)
                }
            }
            workingIds.subtract(leaveIds)
            let leaveNames = leaveIds.sorted().map { rosterById[$0]?.displayName ?? "Unknown" }

            let calendarRows: [CalendarEntry] = dayTrans.filter(isCalendarTx).map { t in
                CalendarEntry(
                    id: t.id,
                    subCategory: t.subCategory ?? "Reminder",
                    title: t.description,
                    eventTime: t.eventTime,
                    note: t.note,
                    isAuto: false
                )
            }
            var allRows = calendarRows
            if let h = holidayMap[dateStr] {
                let auto = CalendarEntry(
                    id: "\(h.id)_auto",
                    subCategory: "Holiday",
                    title: h.name,
                    eventTime: nil,
                    note: "วันหยุดนักขัตฤกษ์ (ระบบ)",
                    isAuto: true
                )
                allRows = [auto] + calendarRows
            }

            let opsMark: CountRecordLogic.DayOpsMark
            switch (hasTrip, hasSand) {
            case (true, true): opsMark = .both
            case (true, false): opsMark = .tripOnly
            case (false, true): opsMark = .sandOnly
            case (false, false): opsMark = .none
            }

            return CalendarDayModel(
                id: dateStr,
                day: d,
                date: dateStr,
                income: inc,
                expense: exp,
                presentCount: workingIds.count,
                leaveCount: leaveIds.count,
                missingCount: max(0, totalEmployees - workingIds.count - leaveIds.count),
                leaveNames: leaveNames,
                calendarRows: allRows,
                financeTransactions: financeTrans,
                machineLogs: machineLogs,
                sandLogs: sandLogs,
                eventLogs: eventLogs,
                opsMark: opsMark
            )
        }
    }

    /// Day-number placeholders so the grid can paint before full aggregation finishes.
    static func skeletonDays(visibleMonth: Date) -> [CalendarDayModel] {
        let cal = DashboardAggregations.gregorian
        let year = cal.component(.year, from: visibleMonth)
        let month = cal.component(.month, from: visibleMonth)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first) else { return [] }
        let holidayMap = publicHolidayMap(year: year)

        return range.map { d in
            let dateStr = String(format: "%04d-%02d-%02d", year, month, d)
            var rows: [CalendarEntry] = []
            if let h = holidayMap[dateStr] {
                rows = [
                    CalendarEntry(
                        id: "\(h.id)_auto",
                        subCategory: "Holiday",
                        title: h.name,
                        eventTime: nil,
                        note: "วันหยุดนักขัตฤกษ์ (ระบบ)",
                        isAuto: true
                    )
                ]
            }
            return CalendarDayModel(
                id: dateStr,
                day: d,
                date: dateStr,
                income: 0,
                expense: 0,
                presentCount: 0,
                leaveCount: 0,
                missingCount: 0,
                leaveNames: [],
                calendarRows: rows,
                financeTransactions: [],
                machineLogs: [],
                sandLogs: [],
                eventLogs: [],
                opsMark: .none
            )
        }
    }

    /// Number of leading blank cells for a Sunday-first grid (matches web
    /// `new Date(year, month, 1).getDay()`).
    static func leadingBlankCount(visibleMonth: Date) -> Int {
        let cal = DashboardAggregations.gregorian
        let comps = cal.dateComponents([.year, .month], from: visibleMonth)
        guard let first = cal.date(from: comps) else { return 0 }
        // Calendar weekday: 1 = Sunday ... 7 = Saturday.
        return cal.component(.weekday, from: first) - 1
    }
}
