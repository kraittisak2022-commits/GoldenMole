import Foundation
import SwiftUI

/// Flutter «ลางาน» helpers (`_saveLaborLeaveEntry` / `_buildLaborLeaveFormCard`).
enum LeaveLogic {
    static let halfMorningMeta = "leave_half:morning"
    static let halfAfternoonMeta = "leave_half:afternoon"

    enum LeaveType: String, CaseIterable, Identifiable, Sendable {
        case personal = "Personal"
        case sick = "Sick"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .personal: return "ลากิจ"
            case .sick: return "ลาป่วย"
            }
        }

        var shortTh: String {
            switch self {
            case .personal: return "กิจ"
            case .sick: return "ป่วย"
            }
        }

        static func from(subCategory: String?) -> LeaveType {
            (subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Sick") == .orderedSame
                ? .sick
                : .personal
        }
    }

    enum HalfPart: String, CaseIterable, Identifiable, Sendable {
        case morning
        case afternoon

        var id: String { rawValue }

        var label: String {
            switch self {
            case .morning: return "ครึ่งเช้า"
            case .afternoon: return "ครึ่งบ่าย"
            }
        }

        var workDetailsMeta: String {
            switch self {
            case .morning: return LeaveLogic.halfMorningMeta
            case .afternoon: return LeaveLogic.halfAfternoonMeta
            }
        }

        static func from(workDetails: String?) -> HalfPart {
            let wd = (workDetails ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return wd == LeaveLogic.halfAfternoonMeta ? .afternoon : .morning
        }
    }

    /// Same whitelist as Flutter `employeeEligibleForLeavePicker`.
    static func eligibleEmployees(from employees: [Employee]) -> [Employee] {
        employees
            .filter(\.isHomeAttendancePool)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func isMenuLeaveRecord(_ t: Transaction) -> Bool {
        CalendarV3Logic.isLaborLeaveRecord(t)
    }

    /// Leave rows covering the selected calendar day (Flutter `laborLeaveCoversCalendarDay`).
    static func leavesCovering(dayKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { CalendarV3Logic.leaveRecordCoversDay($0, day: dayKey) }
            .sorted { ($0.createdAt ?? $0.date) > ($1.createdAt ?? $1.date) }
    }

    static func inclusiveDayCount(startYmd: String, endYmd: String) -> Int {
        guard let start = date(fromYmd: startYmd), let end = date(fromYmd: endYmd) else { return 1 }
        let days = DashboardAggregations.gregorian.dateComponents([.day], from: start, to: end).day ?? 0
        return max(1, days + 1)
    }

    static func endYmd(startYmd: String, leaveDays: Double, isHalfDay: Bool) -> String {
        if isHalfDay { return startYmd }
        let savedDays = max(1, Int((leaveDays > 0 ? leaveDays : 1).rounded()))
        return DashboardAggregations.shiftDateStr(startYmd, deltaDays: savedDays - 1)
    }

    static func isHalfDay(transaction t: Transaction) -> Bool {
        let wd = (t.workDetails ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let halfFromMeta = wd == halfMorningMeta || wd == halfAfternoonMeta
        let halfFromDays = abs((t.leaveDays ?? 0) - 0.5) < 1e-6
        return halfFromMeta || halfFromDays
    }

    /// Flutter `resolvedLeaveReason`.
    static func resolvedReason(_ t: Transaction) -> String {
        let direct = (t.leaveReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }

        let desc = t.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = try? NSRegularExpression(pattern: #"ลา(?:กิจ|ป่วย|งาน)?\s*:\s*(.+)"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)),
           match.numberOfRanges > 1,
           let r = Range(match.range(at: 1), in: desc) {
            var tail = String(desc[r]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let half = try? NSRegularExpression(pattern: #"\s*\(ครึ่งวัน[^)]*\)\s*$"#),
               let m = half.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
               let rr = Range(m.range, in: tail) {
                tail.removeSubrange(rr)
                tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !tail.isEmpty { return tail }
        }

        let note = (t.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty && !note.contains("signedBy") { return note }
        if !desc.isEmpty && desc != "ลางาน" { return desc }
        return ""
    }

    static func durationLabel(_ t: Transaction) -> String {
        let days = t.leaveDays ?? 0
        if days <= 0 { return "" }
        if abs(days - 0.5) < 1e-6 {
            let wd = (t.workDetails ?? "").lowercased()
            if wd.contains("morning") { return "ครึ่งวัน (เช้า)" }
            if wd.contains("afternoon") { return "ครึ่งวัน (บ่าย)" }
            return "ครึ่งวัน"
        }
        if days == days.rounded() { return "\(Int(days.rounded())) วัน" }
        return "\(days) วัน"
    }

    static func typeLabel(_ t: Transaction) -> String {
        switch LeaveType.from(subCategory: t.subCategory) {
        case .sick: return "ลาป่วย"
        case .personal: return "ลากิจ"
        }
    }

    static func formatThaiYmd(_ ymd: String) -> String {
        let parts = String(ymd.prefix(10)).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return ymd
        }
        return String(format: "%02d/%02d/%d", d, m, y + 543)
    }

    static func date(fromYmd s: String) -> Date? {
        let parts = String(s.prefix(10)).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return DashboardAggregations.gregorian.date(from: comps)
    }

    static func employeeNames(ids: [String], employees: [Employee]) -> String {
        let map = Dictionary(uniqueKeysWithValues: employees.map { ($0.id, $0.displayName) })
        let names = ids.map { map[$0] ?? $0 }
        return names.joined(separator: ", ")
    }
}
