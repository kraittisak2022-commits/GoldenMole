import Foundation

/// Home-tab “วันนี้” ops snapshot — fuel stock, labor, vehicle, attendance.
struct TodayOpsSnapshot: Sendable {
    struct StaffRow: Identifiable, Sendable {
        let id: String
        let name: String
        let status: Status
        let workLabels: [String]
        let wage: Double

        enum Status: String, Sendable {
            case work = "มาทำงาน"
            case leave = "ลา"
            case absent = "ขาด"
        }
    }

    let dayKey: String
    /// Alias for main tank diesel (legacy single-tank home chips).
    let dieselLiters: Double
    let mainDieselLiters: Double
    let reserveDieselLiters: Double
    let benzineLiters: Double
    let laborBaht: Double
    let vehicleBaht: Double
    let presentCount: Int
    let leaveCount: Int
    let absentCount: Int
    let staffRows: [StaffRow]

    static let empty = TodayOpsSnapshot(
        dayKey: "",
        dieselLiters: 0,
        mainDieselLiters: 0,
        reserveDieselLiters: 0,
        benzineLiters: 0,
        laborBaht: 0,
        vehicleBaht: 0,
        presentCount: 0,
        leaveCount: 0,
        absentCount: 0,
        staffRows: []
    )

    nonisolated static func build(
        transactions: [Transaction],
        employees: [Employee],
        settings: AppSettings,
        dayKey: String = DashboardAggregations.todayYMD()
    ) -> TodayOpsSnapshot {
        let stock = FuelUsageReportLogic.stockBalancesThrough(
            endDate: dayKey,
            transactions: transactions,
            opening: settings.fuelOpeningStockLiters
        )
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }

        /// Home attendance / wage roster: sand-yard staff + macro drivers only.
        let roster = employees.filter(\.isHomeAttendancePool)
        let rosterIds = Set(roster.map(\.id))

        let vehicleBaht = dayTx.reduce(0.0) { sum, t in
            let isVehicle = t.category == "Vehicle"
                || (t.category == "DailyLog" && t.subCategory == "VehicleTrip")
            guard isVehicle else { return sum }
            return sum + DashboardAggregations.wizardMonetaryAmount(t, employees: employees)
        }

        var workingIds = Set<String>()
        var leaveIds = Set<String>()
        var wageByEmployee: [String: Double] = [:]
        var workLabelsByEmployee: [String: [String]] = [:]

        for t in dayTx where t.category == "Labor" && (t.laborStatus == "Work" || t.laborStatus == "OT") {
            let allIds = (t.employeeIds ?? []).filter { !$0.isEmpty }
            let ids = allIds.filter { rosterIds.contains($0) }
            guard !ids.isEmpty else { continue }

            for id in ids { workingIds.insert(id) }

            // Per-employee wage from employees.base_wage (web พนักงาน > ค่าแรง), not equal-split of amount.
            for id in ids {
                wageByEmployee[id, default: 0] += DashboardAggregations.laborWageForEmployee(
                    t,
                    employeeId: id,
                    employees: employees
                )
            }

            if let assignments = t.workAssignments {
                for (catId, empIds) in assignments {
                    let label = DashboardAggregations.workCategoryLabel(catId)
                    for eid in empIds where rosterIds.contains(eid) {
                        var labels = workLabelsByEmployee[eid] ?? []
                        if !labels.contains(label) { labels.append(label) }
                        workLabelsByEmployee[eid] = labels
                    }
                }
            }
            if let wte = t.workTypeByEmployee {
                for (eid, wt) in wte where wt == "HalfDay" && rosterIds.contains(eid) {
                    var labels = workLabelsByEmployee[eid] ?? []
                    if !labels.contains("ครึ่งวัน") { labels.append("ครึ่งวัน") }
                    workLabelsByEmployee[eid] = labels
                }
            }
            if t.laborStatus == "OT" {
                for id in ids {
                    var labels = workLabelsByEmployee[id] ?? []
                    if !labels.contains("OT") { labels.append("OT") }
                    workLabelsByEmployee[id] = labels
                }
            }
        }

        let laborBaht = wageByEmployee.values.reduce(0.0, +)

        let attendance = DashboardAggregations.attendanceCounts(
            dayTx: dayTx,
            allTransactions: transactions,
            employees: roster,
            dayKey: dayKey,
            workingIdsSeed: workingIds
        )
        workingIds = attendance.workingIds
        leaveIds = attendance.leaveIds
        let absentIds = attendance.absentIds

        let empById = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })

        var rows: [StaffRow] = []
        for id in workingIds.sorted() {
            let name = empById[id]?.displayName ?? id
            rows.append(StaffRow(
                id: id,
                name: name,
                status: .work,
                workLabels: workLabelsByEmployee[id] ?? [],
                wage: wageByEmployee[id] ?? 0
            ))
        }
        for id in leaveIds.sorted() {
            let name = empById[id]?.displayName ?? id
            rows.append(StaffRow(
                id: "leave-\(id)",
                name: name,
                status: .leave,
                workLabels: [],
                wage: 0
            ))
        }
        for id in absentIds.sorted() {
            let name = empById[id]?.displayName ?? id
            rows.append(StaffRow(
                id: "absent-\(id)",
                name: name,
                status: .absent,
                workLabels: [],
                wage: 0
            ))
        }

        return TodayOpsSnapshot(
            dayKey: dayKey,
            dieselLiters: stock.diesel,
            mainDieselLiters: stock.diesel,
            reserveDieselLiters: stock.dieselReserve,
            benzineLiters: stock.benzine,
            laborBaht: laborBaht,
            vehicleBaht: vehicleBaht,
            presentCount: workingIds.count,
            leaveCount: leaveIds.count,
            absentCount: absentIds.count,
            staffRows: rows
        )
    }
}

extension DashboardAggregations {
    // MARK: - Fuel stock (web parity: computeFuelStockBalances)

    struct FuelBalances: Sendable {
        var diesel: Double
        var benzine: Double
    }

    struct AttendanceCounts: Sendable {
        var present: Int
        var leave: Int
        var absent: Int
        var workingIds: Set<String>
        var leaveIds: Set<String>
        var absentIds: Set<String>
    }

    static func isMacroUsageRow(_ t: Transaction) -> Bool {
        MacroVehicleLogic.isMacroUsageRow(t)
    }

    /// Shared attendance headcounts for a single day (used by TodayOps + MobileOps).
    static func attendanceCounts(
        dayTx: [Transaction],
        allTransactions: [Transaction],
        employees: [Employee],
        dayKey: String,
        workingIdsSeed: Set<String>? = nil
    ) -> AttendanceCounts {
        var workingIds = workingIdsSeed ?? Set<String>()
        if workingIdsSeed == nil {
            for t in dayTx where t.category == "Labor" && (t.laborStatus == "Work" || t.laborStatus == "OT") {
                for id in (t.employeeIds ?? []) where !id.isEmpty {
                    workingIds.insert(id)
                }
            }
        }

        var leaveIds = Set<String>()
        for t in allTransactions where CalendarV3Logic.leaveRecordCoversDay(t, day: dayKey) {
            for id in (t.employeeIds ?? []) where !id.isEmpty {
                leaveIds.insert(id)
                workingIds.remove(id)
            }
        }

        let allIds = Set(employees.map(\.id))
        // Keep present / leave within the provided employee pool (e.g. home sand-yard + macro).
        workingIds = workingIds.intersection(allIds)
        leaveIds = leaveIds.intersection(allIds)
        let absentIds = allIds.subtracting(workingIds).subtracting(leaveIds)
        return AttendanceCounts(
            present: workingIds.count,
            leave: leaveIds.count,
            absent: absentIds.count,
            workingIds: workingIds,
            leaveIds: leaveIds,
            absentIds: absentIds
        )
    }

    static func fuelTxToLiters(_ t: Transaction) -> Double {
        let q = t.quantity ?? 0
        guard q != 0 else { return 0 }
        let u = (t.unit ?? "L").lowercased()
        if u == "gallon" || u == "แกลลอน" { return q * 3.785411784 }
        return q
    }

    static func inferFuelMovement(_ t: Transaction) -> String {
        guard t.category == "Fuel" else { return "stock_out" }
        if t.fuelMovement == "stock_in" || t.fuelMovement == "stock_out" {
            return t.fuelMovement ?? "stock_out"
        }
        return (t.vehicleId?.isEmpty == false) ? "stock_out" : "stock_in"
    }

    /// Web/Flutter parity — delegates to `FuelLogic.computeBalance` (cutover + machine reconcile).
    static func fuelStockBalances(
        transactions: [Transaction],
        opening: FuelStock?
    ) -> FuelBalances {
        let bal = FuelLogic.computeBalance(
            transactions: transactions,
            opening: opening,
            asOfYmd: DashboardAggregations.todayYMD()
        )
        return FuelBalances(diesel: bal.diesel, benzine: bal.benzine)
    }

    // MARK: - Wizard monetary amount (web parity)

    static func isMonthlyEmployee(_ emp: Employee) -> Bool {
        let normalized = (emp.type ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "monthly" || normalized == "รายเดือน"
    }

    static func toDailyWage(emp: Employee, wage: Double) -> Double {
        isMonthlyEmployee(emp) ? wage / 30 : wage
    }

    static func dailyWageForWorkType(emp: Employee, wage: Double, workType: String) -> Double {
        let daily = toDailyWage(emp: emp, wage: wage)
        return workType == "HalfDay" ? daily / 2 : daily
    }

    /// Per-employee labor pay for one Labor tx — mirrors web LaborModule + `laborWage.ts`.
    /// Work: `dailyWageForWorkType(base_wage)` + `specialAmount` (per person).
    /// OT: `otAmount × otHours`, else equal share of `amount`.
    static func laborWageForEmployee(
        _ t: Transaction,
        employeeId: String,
        employees: [Employee]
    ) -> Double {
        guard t.category == "Labor" else { return 0 }
        guard (t.employeeIds ?? []).contains(employeeId) else { return 0 }
        guard let emp = employees.first(where: { $0.id == employeeId }) else { return 0 }

        let isOt = t.laborStatus == "OT" || t.subCategory == "OT"
        if isOt {
            let rate = t.otAmount ?? 0
            let hours = t.otHours ?? 0
            if rate > 0, hours > 0 {
                return rate * hours
            }
            let ids = (t.employeeIds ?? []).filter { !$0.isEmpty }
            guard t.amount > 0, !ids.isEmpty else { return 0 }
            return t.amount / Double(ids.count)
        }

        // Work / Attendance — use master base_wage from Employees > ค่าแรง.
        guard let base = emp.baseWage, base.isFinite, base > 0 else {
            // No master wage: fall back to equal share of recorded amount if present.
            let ids = (t.employeeIds ?? []).filter { !$0.isEmpty }
            guard t.amount > 0, !ids.isEmpty else { return 0 }
            return t.amount / Double(ids.count)
        }
        let wt: String
        if t.workTypeByEmployee?[employeeId] == "HalfDay" {
            wt = "HalfDay"
        } else if t.workType == "HalfDay" {
            wt = "HalfDay"
        } else {
            wt = "FullDay"
        }
        let special = max(0, t.specialAmount ?? 0)
        return dailyWageForWorkType(emp: emp, wage: base, workType: wt) + special
    }

    static func inferredLaborAttendanceTotal(_ t: Transaction, employees: [Employee]) -> Double {
        let ids = t.employeeIds ?? []
        guard !ids.isEmpty else { return 0 }
        let wte = t.workTypeByEmployee
        var sum = 0.0
        for id in ids {
            guard let emp = employees.first(where: { $0.id == id }) else { continue }
            guard let wage = emp.baseWage, wage.isFinite else { continue }
            let wt = wte?[id] == "HalfDay" ? "HalfDay" : "FullDay"
            sum += dailyWageForWorkType(emp: emp, wage: wage, workType: wt)
        }
        return sum
    }

    static func inferredVehicleSpend(_ t: Transaction) -> Double {
        if t.amount > 0 { return t.amount }
        return (t.driverWage ?? 0) + (t.vehicleWage ?? 0)
    }

    static func inferredOtSpend(_ t: Transaction) -> Double {
        if t.amount > 0 { return t.amount }
        guard let rate = t.otAmount, let hours = t.otHours, rate > 0, hours > 0 else { return 0 }
        let n = max(1, (t.employeeIds ?? []).count)
        return rate * hours * Double(n)
    }

    /// Matches web `wizardMonetaryAmount` — prefer amount, else infer from wage fields.
    static func wizardMonetaryAmount(_ t: Transaction, employees: [Employee]) -> Double {
        if t.amount > 0 { return t.amount }

        if t.category == "Labor" {
            if t.subCategory == "Attendance", t.laborStatus == "Work", !employees.isEmpty {
                let inferred = inferredLaborAttendanceTotal(t, employees: employees)
                if inferred > 0 { return inferred }
            }
            if t.laborStatus == "OT" || t.subCategory == "OT" {
                let ot = inferredOtSpend(t)
                if ot > 0 { return ot }
            }
            // Fallback: Work without Attendance subcategory still needs wage estimate
            if t.laborStatus == "Work", !employees.isEmpty {
                let inferred = inferredLaborAttendanceTotal(t, employees: employees)
                if inferred > 0 { return inferred }
            }
        }

        if t.category == "Vehicle" || (t.category == "DailyLog" && t.subCategory == "VehicleTrip") {
            let v = inferredVehicleSpend(t)
            if v > 0 { return v }
        }

        return 0
    }

    static func workCategoryLabel(_ rawId: String) -> String {
        let id = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("general:") {
            let rest = String(id.dropFirst("general:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            // อย่าโชว์คีย์เทคนิค (เช่น macro_driver) เป็นชื่องานทั่วไป
            if rest.isEmpty || looksLikeTechnicalLaborKey(rest) { return "งานทั่วไป" }
            return rest
        }
        switch id {
        case "wash1", "wash_old", "washSand", "wash_sand":
            return "เครื่องร่อนทราย"
        case "wash2", "wash_new":
            return "เครื่องร่อนทราย"
        case "washHome", "wash_home", "wash_yard_house", "sift_home":
            return "ล้างทรายที่บ้าน"
        case "pierWatch", "sand_watch":
            return "เฝ้าท่าทราย"
        case "macroDriver", "macro_driver":
            return "คนขับรถแม็คโคร"
        case "nightShift", "night_shift", "nightPatrol", "night_patrol":
            return "งานทั่วไป"
        case "digHaul", "dig_haul", "excavator_control":
            return "งานทั่วไป"
        case "generalWork", "general":
            return "งานทั่วไป"
        case "work":
            return "มาทำงาน"
        case "half:morning":
            return "ครึ่งวัน · เช้า"
        case "half:afternoon":
            return "ครึ่งวัน · บ่าย"
        case "drum", "drum:morning", "drum:afternoon":
            return "ขับรถดรัม"
        case "labor_menu_attendance":
            return "ลงเวลา (ค่าแรง/ลา)"
        case "other":
            return "อื่นๆ"
        default:
            if id.isEmpty { return "งาน" }
            if looksLikeTechnicalLaborKey(id) { return "งานทั่วไป" }
            return id
        }
    }

    /// คีย์ระบบ / รหัสกล่อง — ไม่ควรโชว์ให้ผู้ใช้เห็นดิบๆ
    private static func looksLikeTechnicalLaborKey(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return true }
        if v.contains("_") || v.contains(":") { return true }
        if v.range(of: #"^[a-zA-Z][a-zA-Z0-9]*$"#, options: .regularExpression) != nil {
            // camelCase / ascii id เช่น macroDriver, washSand
            return true
        }
        return false
    }
}
