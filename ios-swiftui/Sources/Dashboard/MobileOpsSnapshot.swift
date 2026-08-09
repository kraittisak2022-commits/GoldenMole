import Foundation

/// Metrics summarizing mobile-app daily work for Home overview.
struct MobileOpsMetrics: Sendable {
    var tripRounds: Int = 0
    var tripVehicles: Int = 0
    var tripCubic: Double = 0
    /// Morning / afternoon trip counts for drum / dump / 6–10 wheel vehicles only.
    var tripMorning: Int = 0
    var tripAfternoon: Int = 0
    /// Distinct drum-trip vehicles with at least one round (today or unique in range).
    var drumVehicles: Int = 0
    var sandRounds: Int = 0
    var sandWashedCubic: Double = 0
    var drumsObtained: Double = 0
    var drumsHome: Double = 0
    var presentCount: Int = 0
    var leaveCount: Int = 0
    var absentCount: Int = 0
    /// Days in the range that had an attendance check-in (range scope only; 0 or 1 for a single day).
    var attendanceDays: Int = 0
    var macroUsageCount: Int = 0
    var macroVehicles: Int = 0
    var fuelInLiters: Double = 0
    var fuelOutLiters: Double = 0
    /// Stock-out withdraws (เบิกน้ำมัน) — liters today / range.
    var fuelWithdrawLiters: Double = 0
    var fuelWithdrawCount: Int = 0
    /// Macro vehicle fuel usage (การใช้น้ำมันรถแม็คโคร).
    var fuelMacroUsageLiters: Double = 0
    var fuelMacroVehicles: Int = 0
    /// Car fill (เติมน้ำมันรถยนต์) — liters / count today.
    var fuelCarFillLiters: Double = 0
    var fuelCarFillCount: Int = 0
    var recordCount: Int = 0

    static let empty = MobileOpsMetrics()
}

/// Off-main builder for mobile-app ops summaries (today + selected range).
enum MobileOpsSnapshot {
    struct Bundle: Sendable {
        let today: MobileOpsMetrics
        let range: MobileOpsMetrics
        let prevRange: MobileOpsMetrics
    }

    nonisolated static func build(
        filter: DateFilter,
        allTransactions: [Transaction],
        employees: [Employee],
        todayKey: String = DashboardAggregations.todayYMD()
    ) -> Bundle {
        let prevFilter = DashboardAggregations.previousPeriodFilter(filter)
        let today = metricsForDay(
            dayKey: todayKey,
            transactions: allTransactions,
            employees: employees
        )
        let range = metricsForRange(
            filter: filter,
            transactions: allTransactions,
            employees: employees
        )
        let prevRange = metricsForRange(
            filter: prevFilter,
            transactions: allTransactions,
            employees: employees
        )
        return Bundle(today: today, range: range, prevRange: prevRange)
    }

    // MARK: - Single day

    nonisolated static func metricsForDay(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee]
    ) -> MobileOpsMetrics {
        guard !dayKey.isEmpty else { return .empty }
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }
        var m = MobileOpsMetrics()

        let tripUnits = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: dayTx,
            employees: employees
        )
        let drumUnits = tripUnits.filter { CountRecordLogic.isDrumTripVehicleId($0.vehicleId) }
        m.tripRounds = tripUnits.reduce(0) { $0 + $1.rounds }
        m.tripVehicles = tripUnits.filter { $0.rounds > 0 }.count
        m.tripMorning = drumUnits.reduce(0) { $0 + $1.morning }
        m.tripAfternoon = drumUnits.reduce(0) { $0 + max(0, $1.afternoon - $1.ot) }
        m.drumVehicles = Set(drumUnits.filter { $0.rounds > 0 }.map(\.vehicleId)).count
        m.tripCubic = dayTx
            .filter { CountRecordLogic.isCountRecordVehicleRow($0) }
            .reduce(0.0) { $0 + ($1.totalCubic ?? $1.perCarCubic ?? 0) }

        let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx)
        m.sandRounds = sand?.rounds ?? 0
        let sandRows = dayTx.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
        m.sandWashedCubic = sandRows.reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
        m.drumsObtained = sandRows.compactMap(\.drumsObtained).max() ?? Double(m.sandRounds)
        m.drumsHome = DashboardAggregations.persistedSandHomeDrums(sandRows)

        let roster = employees.filter(\.isHomeAttendancePool)
        let attendance = DashboardAggregations.attendanceCounts(
            dayTx: dayTx,
            allTransactions: transactions,
            employees: roster,
            dayKey: dayKey
        )
        m.presentCount = attendance.present
        m.leaveCount = attendance.leave
        m.absentCount = attendance.absent
        m.attendanceDays = (attendance.present > 0 || attendance.leave > 0) ? 1 : 0

        let macroRows = dayTx.filter { DashboardAggregations.isMacroUsageRow($0) }
        m.macroUsageCount = macroRows.count
        m.macroVehicles = Set(macroRows.compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count

        let fuel = fuelBreakdown(dayTx)
        m.fuelInLiters = fuel.inLiters
        m.fuelOutLiters = fuel.outLiters
        m.fuelWithdrawLiters = fuel.withdrawLiters
        m.fuelWithdrawCount = fuel.withdrawCount
        m.fuelMacroUsageLiters = fuel.macroUsageLiters
        m.fuelMacroVehicles = fuel.macroVehicles
        m.fuelCarFillLiters = fuel.carFillLiters
        m.fuelCarFillCount = fuel.carFillCount

        m.recordCount = dayTx.filter { isMobileAppRecord($0) }.count
        return m
    }

    // MARK: - Date range

    nonisolated static func metricsForRange(
        filter: DateFilter,
        transactions: [Transaction],
        employees: [Employee]
    ) -> MobileOpsMetrics {
        let dates = DashboardAggregations.enumerateDates(in: filter)
        guard !dates.isEmpty else { return .empty }

        var total = MobileOpsMetrics()
        var presentSum = 0
        var presentDays = 0
        var leavePersonDays = 0
        var absentSum = 0

        for day in dates {
            let dayM = metricsForDay(dayKey: day, transactions: transactions, employees: employees)
            total.tripRounds += dayM.tripRounds
            total.tripCubic += dayM.tripCubic
            total.tripMorning += dayM.tripMorning
            total.tripAfternoon += dayM.tripAfternoon
            total.sandRounds += dayM.sandRounds
            total.sandWashedCubic += dayM.sandWashedCubic
            total.drumsObtained += dayM.drumsObtained
            total.drumsHome += dayM.drumsHome
            total.macroUsageCount += dayM.macroUsageCount
            total.fuelInLiters += dayM.fuelInLiters
            total.fuelOutLiters += dayM.fuelOutLiters
            total.fuelWithdrawLiters += dayM.fuelWithdrawLiters
            total.fuelWithdrawCount += dayM.fuelWithdrawCount
            total.fuelMacroUsageLiters += dayM.fuelMacroUsageLiters
            total.fuelCarFillLiters += dayM.fuelCarFillLiters
            total.fuelCarFillCount += dayM.fuelCarFillCount
            total.recordCount += dayM.recordCount

            if dayM.attendanceDays > 0 {
                presentSum += dayM.presentCount
                presentDays += 1
                leavePersonDays += dayM.leaveCount
                absentSum += dayM.absentCount
            }
            // Track unique trip vehicles / macro vehicles across range via re-scan below.
        }

        total.attendanceDays = presentDays
        total.presentCount = presentDays > 0 ? Int((Double(presentSum) / Double(presentDays)).rounded()) : 0
        total.leaveCount = leavePersonDays
        total.absentCount = presentDays > 0 ? Int((Double(absentSum) / Double(presentDays)).rounded()) : 0

        // Unique vehicles with trips / macro usage in range.
        let rangeTx = DashboardAggregations.filterByRange(transactions, range: filter)
        let tripUnitsAll = dates.flatMap { day in
            CountRecordLogic.buildTripUnits(dayKey: day, transactions: rangeTx, employees: employees)
        }
        total.tripVehicles = Set(tripUnitsAll.filter { $0.rounds > 0 }.map(\.vehicleId)).count
        total.drumVehicles = Set(
            tripUnitsAll
                .filter { $0.rounds > 0 && CountRecordLogic.isDrumTripVehicleId($0.vehicleId) }
                .map(\.vehicleId)
        ).count
        let macroRows = rangeTx.filter { DashboardAggregations.isMacroUsageRow($0) }
        total.macroVehicles = Set(
            macroRows.compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        ).count
        total.fuelMacroVehicles = Set(
            rangeTx
                .filter { FuelLogic.isVehicleUsage($0) }
                .compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count

        return total
    }

    // MARK: - Helpers

    nonisolated private static func isMobileAppRecord(_ t: Transaction) -> Bool {
        if CountRecordLogic.isCountRecordVehicleRow(t) { return true }
        if t.category == "DailyLog" && t.subCategory == "Sand" { return true }
        if t.category == "Labor" && (t.subCategory == "Attendance" || t.laborStatus == "Work" || t.laborStatus == "OT") {
            return true
        }
        if CalendarV3Logic.isLaborLeaveRecord(t) { return true }
        if DashboardAggregations.isMacroUsageRow(t) { return true }
        if t.category == "Fuel" { return true }
        return false
    }

    nonisolated private static func fuelBreakdown(_ txs: [Transaction]) -> (
        inLiters: Double,
        outLiters: Double,
        withdrawLiters: Double,
        withdrawCount: Int,
        macroUsageLiters: Double,
        macroVehicles: Int,
        carFillLiters: Double,
        carFillCount: Int
    ) {
        var inn = 0.0
        var out = 0.0
        var withdraw = 0.0
        var withdrawCount = 0
        var macroLiters = 0.0
        var macroVehicleIds = Set<String>()
        var carFill = 0.0
        var carFillCount = 0
        for t in txs where FuelLogic.isFuelExpense(t) {
            let liters = DashboardAggregations.fuelTxToLiters(t)
            guard liters != 0 else { continue }
            if FuelLogic.isStockIn(t) {
                inn += liters
                continue
            }
            out += liters
            if FuelLogic.isCarFill(t) {
                carFill += liters
                carFillCount += 1
            } else if FuelLogic.isWithdraw(t) {
                withdraw += liters
                withdrawCount += 1
            } else if FuelLogic.isVehicleUsage(t) {
                macroLiters += liters
                if let vid = t.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines), !vid.isEmpty {
                    macroVehicleIds.insert(vid)
                }
            }
        }
        return (inn, out, withdraw, withdrawCount, macroLiters, macroVehicleIds.count, carFill, carFillCount)
    }
}
