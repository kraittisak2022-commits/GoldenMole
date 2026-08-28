import Foundation

enum DashboardAggregations {
    // MARK: - Date helpers

    /// Always Gregorian + Bangkok — avoids Buddhist-era year keys (2569) that never match DB (2026).
    static let gregorian: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current
        return cal
    }()

    static func todayYMD() -> String {
        formatYMD(Date())
    }

    static func formatYMD(_ date: Date) -> String {
        let cal = gregorian
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func dateFilter(preset: DateRangePreset, customStart: Date?, customEnd: Date?) -> DateFilter {
        let end = Date()
        if preset == .custom, let start = customStart, let customEnd {
            return DateFilter(start: formatYMD(start), end: formatYMD(customEnd))
        }
        if preset == .today {
            let today = formatYMD(end)
            return DateFilter(start: today, end: today)
        }
        if preset == .yesterday {
            let yesterday = gregorian.date(byAdding: .day, value: -1, to: end) ?? end
            let ymd = formatYMD(yesterday)
            return DateFilter(start: ymd, end: ymd)
        }
        let days = Int(preset.rawValue) ?? 7
        let start = gregorian.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return DateFilter(start: formatYMD(start), end: formatYMD(end))
    }

    /// Single-day focus for home “สรุปวันนี้” — custom single day, else end of range.
    static func focusDayKey(from filter: DateFilter) -> String {
        if filter.start == filter.end, !filter.start.isEmpty { return filter.start }
        if !filter.end.isEmpty { return filter.end }
        return todayYMD()
    }

    static func countInclusiveDays(_ start: String, _ end: String) -> Int {
        guard let a = parseYMD(start), let b = parseYMD(end) else { return 1 }
        let diff = gregorian.dateComponents([.day], from: a, to: b).day ?? 0
        return max(1, diff + 1)
    }

    static func shiftDateStr(_ dateStr: String, deltaDays: Int) -> String {
        guard let d = parseYMD(dateStr) else { return dateStr }
        let shifted = gregorian.date(byAdding: .day, value: deltaDays, to: d) ?? d
        return formatYMD(shifted)
    }

    static func previousPeriodFilter(_ filter: DateFilter) -> DateFilter {
        let n = countInclusiveDays(filter.start, filter.end)
        let prevEnd = shiftDateStr(filter.start, deltaDays: -1)
        let prevStart = shiftDateStr(prevEnd, deltaDays: -(n - 1))
        return DateFilter(start: prevStart, end: prevEnd)
    }

    static func filterByRange(_ transactions: [Transaction], range: DateFilter) -> [Transaction] {
        transactions.filter { tx in
            let d = String(tx.date.prefix(10))
            return d >= range.start && d <= range.end
        }
    }

    static func enumerateDates(in filter: DateFilter) -> [String] {
        let n = countInclusiveDays(filter.start, filter.end)
        return (0..<n).map { shiftDateStr(filter.start, deltaDays: $0) }.filter { $0 <= filter.end }
    }

    static func dayLabel(_ dateStr: String) -> String {
        guard let d = parseYMD(dateStr) else { return dateStr }
        let day = gregorian.component(.day, from: d)
        let month = gregorian.component(.month, from: d)
        return "\(day)/\(month)"
    }

    static func thaiDateLong(_ dateStr: String) -> String {
        guard let d = parseYMD(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        // Display-only Buddhist era (พ.ศ.); keys always use gregorian above.
        formatter.calendar = Calendar(identifier: .buddhist)
        formatter.locale = Locale(identifier: "th_TH")
        formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
        formatter.dateFormat = "EEEE d MMM yyyy"
        return formatter.string(from: d)
    }

    // MARK: - Financial

    static func totalExpense(_ transactions: [Transaction]) -> Double {
        transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    static func expenseByCategory(_ transactions: [Transaction]) -> [String: Double] {
        var map: [String: Double] = [:]
        for t in transactions where t.type == .expense {
            map[t.category, default: 0] += t.amount
        }
        return map
    }

    static func categoryExpense(_ transactions: [Transaction], category: String, date: String? = nil) -> Double {
        transactions.filter { t in
            guard t.type == .expense, t.category == category else { return false }
            if let date { return String(t.date.prefix(10)) == date }
            return true
        }.reduce(0) { $0 + $1.amount }
    }

    static func vehicleExpense(_ transactions: [Transaction], date: String? = nil) -> Double {
        transactions.filter { t in
            guard t.type == .expense else { return false }
            let isVehicle = t.category == "Vehicle" || (t.category == "DailyLog" && t.subCategory == "VehicleTrip")
            guard isVehicle else { return false }
            if let date { return String(t.date.prefix(10)) == date }
            return true
        }.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Sand

    static func persistedSandHomeDrums(_ txs: [Transaction]) -> Double {
        txs.reduce(0) { sum, t in
            sum + (t.drumsWashedAtHome ?? 0)
        }
    }

    static func sandWashedCubic(_ t: Transaction) -> Double {
        (t.sandMorning ?? 0) + (t.sandAfternoon ?? 0)
    }

    static func sandTransportedCubic(_ transactions: [Transaction], date: String) -> Double {
        SandStockLogic.cubicIn(on: date, transactions: transactions)
    }

    static func buildDailySandSeries(filter: DateFilter, transactions: [Transaction]) -> (washed: [Double], transported: [Double], labels: [String], dates: [String]) {
        let dates = enumerateDates(in: filter)
        var washed: [Double] = []
        var transported: [Double] = []
        var labels: [String] = []
        for date in dates {
            let dayTx = transactions.filter { String($0.date.prefix(10)) == date }
            let w = dayTx.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
                .reduce(0.0) { $0 + sandWashedCubic($1) }
            let t = sandTransportedCubic(transactions, date: date)
            washed.append(w)
            transported.append(t)
            labels.append(dayLabel(date))
        }
        return (washed, transported, labels, dates)
    }

    // MARK: - V5 period compare helpers

    static func pctChangeVsPrev(cur: Double, prev: Double) -> Double? {
        if prev == 0 && cur == 0 { return 0 }
        if prev == 0 { return nil }
        return ((cur - prev) / abs(prev)) * 100
    }

    // MARK: - Overview hub aggregations

    static func dailyExpenseBreakdown(filter: DateFilter, transactions: [Transaction]) -> [DailyExpenseBreakdown] {
        enumerateDates(in: filter).map { date in
            let day = transactions.filter { String($0.date.prefix(10)) == date && $0.type == .expense }
            let labor = day.filter { $0.category == "Labor" }.reduce(0) { $0 + $1.amount }
            let fuel = day.filter { $0.category == "Fuel" }.reduce(0) { $0 + $1.amount }
            let vehicle = day.filter {
                $0.category == "Vehicle" || ($0.category == "DailyLog" && $0.subCategory == "VehicleTrip")
            }.reduce(0) { $0 + $1.amount }
            let maintenance = day.filter { $0.category == "Maintenance" }.reduce(0) { $0 + $1.amount }
            let land = day.filter { $0.category == "Land" }.reduce(0) { $0 + $1.amount }
            let total = day.reduce(0) { $0 + $1.amount }
            return DailyExpenseBreakdown(
                date: date, label: dayLabel(date),
                labor: labor, fuel: fuel, vehicle: vehicle,
                maintenance: maintenance, land: land, total: total
            )
        }
    }

    static func weeklyExpenseBuckets(filter: DateFilter, transactions: [Transaction]) -> [WeeklyExpenseBucket] {
        let daily = dailyExpenseBreakdown(filter: filter, transactions: transactions)
        guard !daily.isEmpty else { return [] }
        var buckets: [WeeklyExpenseBucket] = []
        var i = 0
        var week = 1
        while i < daily.count {
            let slice = Array(daily[i..<min(i + 7, daily.count)])
            buckets.append(WeeklyExpenseBucket(
                label: "สัปดาห์ \(week)",
                total: slice.reduce(0) { $0 + $1.total },
                labor: slice.reduce(0) { $0 + $1.labor },
                fuel: slice.reduce(0) { $0 + $1.fuel },
                vehicle: slice.reduce(0) { $0 + $1.vehicle },
                land: slice.reduce(0) { $0 + $1.land }
            ))
            i += 7
            week += 1
        }
        return buckets
    }

    /// Per-car fuel + maintenance (top 5 by total). Matches web: description contains car name.
    static func vehicleCostBreakdown(transactions: [Transaction], cars: [String]) -> [VehicleCostRow] {
        let expenses = transactions.filter { $0.type == .expense }
        let rows: [VehicleCostRow] = cars.compactMap { car in
            let fuel = expenses.filter { $0.category == "Fuel" && $0.description.contains(car) }
                .reduce(0) { $0 + $1.amount }
            let maintenance = expenses.filter { $0.category == "Maintenance" && $0.description.contains(car) }
                .reduce(0) { $0 + $1.amount }
            guard fuel + maintenance > 0 else { return nil }
            return VehicleCostRow(name: car, fuel: fuel, maintenance: maintenance)
        }
        return Array(rows.sorted { $0.total > $1.total }.prefix(5))
    }

    static func cumulative(_ values: [Double]) -> [Double] {
        var run = 0.0
        return values.map { v in run += v; return run }
    }

    /// Per-day drums obtained (max of sand rows), home wash, and cumulative remaining.
    static func sandDrumsSeries(filter: DateFilter, transactions: [Transaction]) -> SandDrumsSeries {
        let dates = enumerateDates(in: filter)
        var obtained: [Double] = []
        var home: [Double] = []
        var remainingCum: [Double] = []
        var run = 0.0
        var totalObtained = 0.0
        var totalHome = 0.0
        for date in dates {
            let sand = transactions.filter {
                String($0.date.prefix(10)) == date && $0.category == "DailyLog" && $0.subCategory == "Sand"
            }
            let dayObtained = sand.compactMap(\.drumsObtained).max() ?? 0
            let dayHome = persistedSandHomeDrums(sand)
            obtained.append(dayObtained)
            home.append(dayHome)
            totalObtained += dayObtained
            totalHome += dayHome
            run += max(0, dayObtained - dayHome)
            remainingCum.append(run)
        }
        return SandDrumsSeries(
            obtained: obtained,
            home: home,
            remainingCumulative: remainingCum,
            labels: dates.map { dayLabel($0) },
            dates: dates,
            totalObtained: totalObtained,
            totalHome: totalHome
        )
    }

    static func sandOverviewKPIs(filter: DateFilter, transactions: [Transaction]) -> SandOverviewKPIs {
        let series = buildDailySandSeries(filter: filter, transactions: transactions)
        let drums = sandDrumsSeries(filter: filter, transactions: transactions)
        let numDays = max(1, Double(series.washed.count))
        let washed = series.washed.reduce(0, +)
        let transported = series.transported.reduce(0, +)
        let remaining = washed - transported
        let avgW = washed / numDays
        let avgT = transported / numDays
        let netPerDay = avgW - avgT
        let forecast: String
        if netPerDay > 0 {
            forecast = "∞ (ผลิตเกินขน)"
        } else if abs(netPerDay) < 1e-9 {
            forecast = "0 (สมดุล)"
        } else {
            let days = max(0, Int(ceil(abs(remaining) / abs(netPerDay))))
            forecast = "\(days) วัน"
        }
        return SandOverviewKPIs(
            washed: washed,
            transported: transported,
            remaining: remaining,
            forecastLabel: forecast,
            avgWashedPerDay: avgW,
            avgTransportedPerDay: avgT,
            drumsObtained: drums.totalObtained,
            drumsHome: drums.totalHome,
            drumsRemaining: drums.drumsRemaining
        )
    }

    static func sandTotals(_ txs: [Transaction]) -> (washed: Double, transported: Double) {
        let washed = txs.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
            .reduce(0.0) { $0 + sandWashedCubic($1) }
        let dates = Set(txs.map { String($0.date.prefix(10)) })
        let transported = dates.reduce(0.0) { $0 + sandTransportedCubic(txs, date: $1) }
        return (washed, transported)
    }

    static func dataQuality(filter: DateFilter, transactions: [Transaction]) -> DataQualitySummary {
        let dates = enumerateDates(in: filter)
        let total = max(1, dates.count)
        var withRecords = 0
        var withSand = 0
        for date in dates {
            let day = transactions.filter { String($0.date.prefix(10)) == date }
            if !day.isEmpty { withRecords += 1 }
            if day.contains(where: { $0.category == "DailyLog" && $0.subCategory == "Sand" }) {
                withSand += 1
            }
        }
        return DataQualitySummary(
            totalDays: dates.count,
            daysWithRecords: withRecords,
            coveragePct: Double(withRecords) / Double(total) * 100,
            daysWithSand: withSand,
            sandCoveragePct: Double(withSand) / Double(total) * 100
        )
    }

    static func buildOverviewAlerts(
        curExpense: Double,
        prevExpense: Double,
        quality: DataQualitySummary
    ) -> [OverviewAlert] {
        var alerts: [OverviewAlert] = []
        if let expDelta = pctChangeVsPrev(cur: curExpense, prev: prevExpense), expDelta >= 15 {
            alerts.append(OverviewAlert(id: "expense_spike", label: "รายจ่ายพุ่ง", severity: .red))
        }
        let sev: OverviewAlert.Severity = quality.coveragePct < 60 ? .red : (quality.coveragePct < 80 ? .amber : .green)
        alerts.append(OverviewAlert(
            id: "coverage",
            label: "ความครบถ้วนข้อมูล \(Int(round(quality.coveragePct)))%",
            severity: sev
        ))
        return alerts
    }

    static func buildOverviewInsights(
        curExpense: Double,
        prevExpense: Double,
        sandWashed: Double,
        sandTransported: Double,
        quality: DataQualitySummary,
        mobileCur: MobileOpsMetrics = .empty,
        mobilePrev: MobileOpsMetrics = .empty
    ) -> [String] {
        var insights: [String] = []
        if let expDelta = pctChangeVsPrev(cur: curExpense, prev: prevExpense), expDelta >= 15 {
            insights.append("รายจ่ายเพิ่มขึ้น \(Int(round(expDelta)))% เทียบช่วงก่อน — ควรตรวจหมวดน้ำมัน/ค่าแรง")
        }
        if let tripDelta = pctChangeVsPrev(cur: Double(mobileCur.tripRounds), prev: Double(mobilePrev.tripRounds)),
           tripDelta <= -15, mobilePrev.tripRounds > 0 {
            insights.append("เที่ยวรถลดลง \(Int(round(abs(tripDelta))))% เทียบช่วงก่อน (\(mobileCur.tripRounds) vs \(mobilePrev.tripRounds) เที่ยว)")
        }
        if let sandDelta = pctChangeVsPrev(cur: Double(mobileCur.sandRounds), prev: Double(mobilePrev.sandRounds)),
           sandDelta <= -15, mobilePrev.sandRounds > 0 {
            insights.append("รอบร่อนทรายลดลง \(Int(round(abs(sandDelta))))% เทียบช่วงก่อน")
        }
        let sandTotal = sandWashed + sandTransported
        if sandTotal > 0 {
            let imbalance = abs(sandWashed - sandTransported) / max(sandWashed, sandTransported, 1) * 100
            if imbalance >= 25 {
                if sandWashed > sandTransported {
                    insights.append("ล้างทรายมากกว่าขน \(Int(round(sandWashed - sandTransported))) คิว — มีทรายค้างกอง")
                } else {
                    insights.append("ขนทรายมากกว่าล้าง \(Int(round(sandTransported - sandWashed))) คิว — อาจขาดทรายล้าง")
                }
            }
        }
        if quality.coveragePct < 60 {
            insights.append("ข้อมูลไม่ครบ (\(Int(round(quality.coveragePct)))% ของวันมีธุรกรรม) — สรุปอาจคลาดเคลื่อน")
        }
        if insights.isEmpty {
            insights.append("แนวโน้มช่วงนี้ค่อนข้างเสถียรเทียบช่วงก่อน — ไม่มีสัญญาณผิดปกติชัดเจน")
        }
        return Array(insights.prefix(5))
    }

    static func costStructureSlices(_ transactions: [Transaction]) -> [ChartSlice] {
        let map = expenseByCategory(transactions)
        let defs: [(String, String, String)] = [
            ("Labor", "ค่าแรง", "#10b981"),
            ("Vehicle", "การใช้รถ", "#f59e0b"),
            ("Fuel", "น้ำมัน", "#ea580c"),
            ("Maintenance", "ซ่อมบำรุง", "#64748b"),
            ("Land", "ที่ดิน", "#8b5cf6"),
            ("DailyLog", "งานประจำวัน", "#0ea5e9")
        ]
        return defs.compactMap { key, label, color in
            let v = map[key] ?? 0
            guard v > 0 else { return nil }
            return ChartSlice(label: label, value: v, colorHex: color)
        }
    }

    static func overviewCSV(
        curExpense: Double,
        prevExpense: Double,
        sandCur: (washed: Double, transported: Double),
        sandPrev: (washed: Double, transported: Double),
        mobileCur: MobileOpsMetrics,
        mobilePrev: MobileOpsMetrics
    ) -> String {
        var lines = ["metric,current,previous"]
        lines.append("expense,\(curExpense),\(prevExpense)")
        lines.append("sand_washed,\(sandCur.washed),\(sandPrev.washed)")
        lines.append("sand_transported,\(sandCur.transported),\(sandPrev.transported)")
        lines.append("trip_rounds,\(mobileCur.tripRounds),\(mobilePrev.tripRounds)")
        lines.append("sand_rounds,\(mobileCur.sandRounds),\(mobilePrev.sandRounds)")
        lines.append("fuel_out,\(mobileCur.fuelOutLiters),\(mobilePrev.fuelOutLiters)")
        lines.append("attendance_days,\(mobileCur.attendanceDays),\(mobilePrev.attendanceDays)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Count record (V4) — see CountRecordLogic

    static func isCountRecordVehicleRow(_ t: Transaction) -> Bool {
        CountRecordLogic.isCountRecordVehicleRow(t)
    }

    static func isCountRecordSandTapRow(_ t: Transaction) -> Bool {
        CountRecordLogic.isCountRecordSandTapRow(t)
    }

    static func driverDisplayName(_ driverId: String, employees: [Employee]) -> String {
        CountRecordLogic.driverDisplayName(driverId, employees: employees)
    }

    // MARK: - Thai holidays (simplified fixed dates)

    static func thaiPublicHolidayMap(year: Int) -> [String: String] {
        let fixed: [(String, String)] = [
            ("01-01", "วันขึ้นปีใหม่"),
            ("04-06", "วันจักรี"),
            ("04-13", "วันสงกรานต์"),
            ("04-14", "วันสงกรานต์"),
            ("04-15", "วันสงกรานต์"),
            ("05-01", "วันแรงงาน"),
            ("05-04", "วันฉัตรมงคล"),
            ("06-03", "วันเฉลิมพระชนมพรรษาสมเด็จพระนางเจ้าสุทิดา"),
            ("07-28", "วันเฉลิมพระชนมพรรษาพระบาทสมเด็จพระเจ้าอยู่หัว"),
            ("08-12", "วันแม่แห่งชาติ"),
            ("10-13", "วันคล้ายวันสวรรคต ร.9"),
            ("10-23", "วันปิยมหาราช"),
            ("12-05", "วันพ่อแห่งชาติ"),
            ("12-10", "วันรัฐธรรมนูญ"),
            ("12-31", "วันสิ้นปี")
        ]
        var map: [String: String] = [:]
        for (md, name) in fixed {
            map["\(year)-\(md)"] = name
        }
        return map
    }

    // MARK: - Formatting

    static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " ฿"
    }

    static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func parseYMD(_ s: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(s.prefix(10)))
    }
}
