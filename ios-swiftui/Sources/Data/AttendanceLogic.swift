import Foundation
import SwiftUI

/// Bucket IDs and hydrate/classify helpers matching Flutter attendance board.
enum AttendanceBucket: String, CaseIterable, Identifiable, Sendable {
    case work = "att_work"
    case halfMorning = "att_half_morning"
    case halfAfternoon = "att_half_afternoon"
    case leave = "att_leave"
    case drvMacro = "att_drv_macro"
    case drvDrum = "att_drv_drum"
    case drvLeave = "att_drv_leave"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: return "ทำงาน (เต็มวัน)"
        case .halfMorning: return "ครึ่งวัน • ช่วงเช้า"
        case .halfAfternoon: return "ครึ่งวัน • ช่วงบ่าย"
        case .leave, .drvLeave: return "ลางาน"
        case .drvMacro: return "ขับรถแม็คโคร"
        case .drvDrum: return "ขับรถดรัม"
        }
    }

    var shortTitle: String {
        switch self {
        case .work: return "ทำงาน"
        case .halfMorning: return "ครึ่งวัน · เช้า"
        case .halfAfternoon: return "ครึ่งวัน · บ่าย"
        case .leave, .drvLeave: return "ลางาน"
        case .drvMacro: return "แม็คโคร"
        case .drvDrum: return "ดรัม"
        }
    }

    var isSandYard: Bool {
        switch self {
        case .work, .halfMorning, .halfAfternoon, .leave: return true
        default: return false
        }
    }

    var isDriver: Bool {
        switch self {
        case .drvMacro, .drvDrum, .drvLeave: return true
        default: return false
        }
    }

    var isLeave: Bool {
        self == .leave || self == .drvLeave
    }

    var accent: Color {
        switch self {
        case .work: return Color(red: 0.184, green: 0.714, blue: 0.651)
        case .halfMorning: return Color(red: 0.231, green: 0.604, blue: 0.882)
        case .halfAfternoon: return Color(red: 0.424, green: 0.435, blue: 0.902)
        case .leave, .drvLeave: return Color(red: 0.937, green: 0.365, blue: 0.431)
        case .drvMacro: return Color(red: 0.937, green: 0.424, blue: 0)
        case .drvDrum: return Color(red: 0.424, green: 0.435, blue: 0.902)
        }
    }

    static var sandYardBuckets: [AttendanceBucket] {
        [.work, .halfMorning, .halfAfternoon, .leave]
    }

    static var driverBuckets: [AttendanceBucket] {
        [.drvMacro, .drvDrum, .drvLeave]
    }

    /// Flutter `workAssignments` key for this bucket (nil for leave).
    var workAssignmentKey: String? {
        switch self {
        case .work: return "work"
        case .halfMorning: return "half:morning"
        case .halfAfternoon: return "half:afternoon"
        case .drvMacro: return "macro_driver"
        case .drvDrum: return "drum"
        case .leave, .drvLeave: return nil
        }
    }
}

enum AttendanceSection: String, CaseIterable, Identifiable, Sendable {
    case sandYard
    case driver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sandYard: return "เช็คชื่อพนักงานท่าทราย"
        case .driver: return "เช็คชื่อคนขับรถ"
        }
    }

    var subtitle: String {
        switch self {
        case .sandYard: return "ทำงาน · ครึ่งวัน · ลางาน"
        case .driver: return "แม็คโคร · ดรัม · ลางาน"
        }
    }

    var buckets: [AttendanceBucket] {
        switch self {
        case .sandYard: return AttendanceBucket.sandYardBuckets
        case .driver: return AttendanceBucket.driverBuckets
        }
    }
}

enum AttendanceLogic {
    static let leaveReasonSand = "เช็คชื่อ: ลางาน (พนักงานท่าทราย)"
    static let leaveReasonDriver = "เช็คชื่อ: ลางาน (คนขับรถ)"
    static let leaveReasonLegacy = "เช็คชื่อ: ลางาน"

    private static let sandWaKeys: Set<String> = ["work", "half:morning", "half:afternoon"]
    private static let driverWaKeys: Set<String> = [
        "macro_driver", "drum", "drum:morning", "drum:afternoon",
    ]

    struct HydratedBoard: Equatable, Sendable {
        var assignments: [AttendanceBucket: Set<String>]
        var sandLaborTxId: String?
        var sandLeaveTxId: String?
        var driverLaborTxId: String?
        var driverLeaveTxId: String?
        var legacyLaborTxId: String?
        var legacyLeaveTxId: String?

        static var empty: HydratedBoard {
            HydratedBoard(
                assignments: Dictionary(uniqueKeysWithValues: AttendanceBucket.allCases.map { ($0, []) }),
                sandLaborTxId: nil,
                sandLeaveTxId: nil,
                driverLaborTxId: nil,
                driverLeaveTxId: nil,
                legacyLaborTxId: nil,
                legacyLeaveTxId: nil
            )
        }
    }

    static func emptyAssignments() -> [AttendanceBucket: Set<String>] {
        Dictionary(uniqueKeysWithValues: AttendanceBucket.allCases.map { ($0, []) })
    }

    static func isAttendanceDriver(_ employee: Employee) -> Bool {
        employee.isMacroDriver
    }

    /// Days-worked ranking (unique dates with labor work attendance, excluding OT/leave/advance).
    static func daysWorkedByEmployee(transactions: [Transaction]) -> [String: Int] {
        var datesByEmp: [String: Set<String>] = [:]
        for t in transactions where isLaborWorkAttendanceRow(t) {
            let day = String(t.date.prefix(10))
            guard day.count == 10 else { continue }
            for id in t.employeeIds ?? [] {
                datesByEmp[id, default: []].insert(day)
            }
        }
        return datesByEmp.mapValues(\.count)
    }

    static func isLaborWorkAttendanceRow(_ t: Transaction) -> Bool {
        guard t.category == "Labor" else { return false }
        let ls = (t.laborStatus ?? "").lowercased()
        let sc = (t.subCategory ?? "").lowercased()
        if ls == "ot" || sc == "ot" { return false }
        if ls == "leave" || ls == "sick" || ls == "personal" { return false }
        if sc == "advance" || ls == "advance" { return false }
        if t.type == .leave || t.category == "Leave" { return false }
        return sc == "attendance" || ls == "work" || sc.isEmpty
    }

    static func hydrate(
        dayTransactions: [Transaction],
        employeesById: [String: Employee]
    ) -> HydratedBoard {
        var board = HydratedBoard.empty

        func assign(_ bucket: AttendanceBucket, _ empId: String) {
            var set = board.assignments[bucket] ?? []
            set.insert(empId)
            board.assignments[bucket] = set
        }

        func classifyWa(_ wa: [String: [String]]?) -> (sand: Bool, driver: Bool) {
            guard let wa, !wa.isEmpty else { return (false, false) }
            var sand = false
            var driver = false
            for (key, list) in wa where !list.isEmpty {
                if sandWaKeys.contains(key) { sand = true }
                if driverWaKeys.contains(key) { driver = true }
            }
            return (sand, driver)
        }

        for t in dayTransactions {
            let ls = (t.laborStatus ?? "").lowercased()
            let sc = (t.subCategory ?? "").lowercased()
            let isLeave = t.category == "Leave"
                || t.type == .leave
                || ls == "leave"
                || ls == "sick"
                || ls == "personal"
            let isOt = t.category == "Labor" && (ls == "ot" || sc == "ot")
            let isAttendance = t.category == "Labor"
                && !isOt
                && (sc == "attendance" || ls == "work" || (!isLeave && sc != "advance"))

            if isLeave {
                let reason = (t.leaveReason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let isSandLeave = reason.contains("พนักงานท่าทราย")
                let isDriverLeave = reason.contains("คนขับรถ")
                let isLegacyLeave = reason == leaveReasonLegacy
                    || reason == "เช็คชื่อ: ลางาน"
                    || (!isSandLeave && !isDriverLeave && reason.contains("เช็คชื่อ"))

                if isLegacyLeave && !isSandLeave && !isDriverLeave {
                    board.legacyLeaveTxId = t.id
                } else if isDriverLeave && !isSandLeave {
                    board.driverLeaveTxId = t.id
                } else if isSandLeave && !isDriverLeave {
                    board.sandLeaveTxId = t.id
                } else {
                    board.legacyLeaveTxId = board.legacyLeaveTxId ?? t.id
                }

                for id in t.employeeIds ?? [] {
                    if isSandLeave && !isDriverLeave {
                        assign(.leave, id)
                        continue
                    }
                    if isDriverLeave && !isSandLeave {
                        assign(.drvLeave, id)
                        continue
                    }
                    if let e = employeesById[id], isAttendanceDriver(e) {
                        assign(.drvLeave, id)
                    } else {
                        assign(.leave, id)
                    }
                }
                continue
            }

            if isOt { continue }

            if isAttendance {
                let wa = t.workAssignments
                let kind = classifyWa(wa)
                let hasWa = !(wa ?? [:]).isEmpty
                let isSandOnly = hasWa && kind.sand && !kind.driver
                let isDriverOnly = hasWa && kind.driver && !kind.sand
                let isLegacy = !hasWa || (kind.sand && kind.driver)

                if isLegacy {
                    board.legacyLaborTxId = t.id
                } else if isSandOnly {
                    board.sandLaborTxId = t.id
                } else if isDriverOnly {
                    board.driverLaborTxId = t.id
                }

                var assigned = Set<String>()
                func takeRole(_ role: String, _ bucket: AttendanceBucket) {
                    guard let list = wa?[role] else { return }
                    for id in list {
                        assign(bucket, id)
                        assigned.insert(id)
                    }
                }

                if wa != nil {
                    takeRole("work", .work)
                    takeRole("half:morning", .halfMorning)
                    takeRole("half:afternoon", .halfAfternoon)
                    takeRole("macro_driver", .drvMacro)
                    takeRole("drum", .drvDrum)
                    takeRole("drum:morning", .drvDrum)
                    takeRole("drum:afternoon", .drvDrum)
                }

                let wtByEmp = t.workTypeByEmployee ?? [:]
                for id in t.employeeIds ?? [] {
                    if assigned.contains(id) { continue }
                    let wt = (wtByEmp[id] ?? "").lowercased()
                    let isDriver = employeesById[id].map(isAttendanceDriver) ?? false
                    if isSandOnly {
                        assign(wt == "halfday" ? .halfMorning : .work, id)
                    } else if isDriverOnly {
                        assign(wt == "halfday" ? .drvDrum : .drvMacro, id)
                    } else if wt == "halfday" {
                        assign(isDriver ? .drvDrum : .halfMorning, id)
                    } else if isDriver {
                        assign(.drvMacro, id)
                    } else {
                        assign(.work, id)
                    }
                }
            }
        }

        return board
    }

    static func sectionSummary(
        section: AttendanceSection,
        assignments: [AttendanceBucket: Set<String>]
    ) -> String {
        switch section {
        case .sandYard:
            let work = assignments[.work]?.count ?? 0
            let half = (assignments[.halfMorning]?.count ?? 0) + (assignments[.halfAfternoon]?.count ?? 0)
            let leave = assignments[.leave]?.count ?? 0
            if work == 0 && half == 0 && leave == 0 {
                return "แตะเพื่อเช็คชื่อ"
            }
            return "ทำงาน \(work) · ครึ่งวัน \(half) · ลา \(leave)"
        case .driver:
            let macro = assignments[.drvMacro]?.count ?? 0
            let drum = assignments[.drvDrum]?.count ?? 0
            let leave = assignments[.drvLeave]?.count ?? 0
            if macro == 0 && drum == 0 && leave == 0 {
                return "แตะเพื่อเช็คชื่อ"
            }
            return "แม็คโคร \(macro) · ดรัม \(drum) · ลา \(leave)"
        }
    }

    static func poolEmployees(
        section: AttendanceSection,
        employees: [Employee],
        assignments: [AttendanceBucket: Set<String>],
        daysWorked: [String: Int]
    ) -> [Employee] {
        let assignedIds: Set<String> = {
            var s = Set<String>()
            for b in section.buckets {
                s.formUnion(assignments[b] ?? [])
            }
            return s
        }()

        let filtered = employees.filter { e in
            guard e.isActive else { return false }
            switch section {
            case .sandYard:
                return e.isSandYardStaff || assignedIds.contains(e.id)
            case .driver:
                return e.isMacroDriver || assignedIds.contains(e.id)
            }
        }

        return filtered.sorted { a, b in
            let na = daysWorked[a.id] ?? 0
            let nb = daysWorked[b.id] ?? 0
            if na != nb { return na > nb }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    static func assignedBucket(
        employeeId: String,
        section: AttendanceSection,
        assignments: [AttendanceBucket: Set<String>]
    ) -> AttendanceBucket? {
        for b in section.buckets {
            if assignments[b]?.contains(employeeId) == true { return b }
        }
        return nil
    }
}
