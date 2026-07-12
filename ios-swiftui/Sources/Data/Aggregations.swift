import Foundation

enum DashboardAggregations {
    // MARK: - Date helpers

    static func todayYMD() -> String {
        formatYMD(Date())
    }

    static func formatYMD(_ date: Date) -> String {
        let cal = Calendar.current
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
        let days = Int(preset.rawValue) ?? 7
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return DateFilter(start: formatYMD(start), end: formatYMD(end))
    }

    static func countInclusiveDays(_ start: String, _ end: String) -> Int {
        guard let a = parseYMD(start), let b = parseYMD(end) else { return 1 }
        let diff = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        return max(1, diff + 1)
    }

    static func shiftDateStr(_ dateStr: String, deltaDays: Int) -> String {
        guard let d = parseYMD(dateStr) else { return dateStr }
        let shifted = Calendar.current.date(byAdding: .day, value: deltaDays, to: d) ?? d
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
        let day = Calendar.current.component(.day, from: d)
        let month = Calendar.current.component(.month, from: d)
        return "\(day)/\(month)"
    }

    static func thaiDateLong(_ dateStr: String) -> String {
        guard let d = parseYMD(dateStr) else { return dateStr }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "th_TH")
        formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
        formatter.dateFormat = "EEEE d MMM yyyy"
        return formatter.string(from: d)
    }

    // MARK: - Financial

    static func aggregateFinancial(_ transactions: [Transaction]) -> FinancialSummary {
        let income = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expense = transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        return FinancialSummary(income: income, expense: expense)
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
        transactions.filter { t in
            String(t.date.prefix(10)) == date &&
            ((t.category == "DailyLog" && t.subCategory == "VehicleTrip") || t.category == "Vehicle")
        }.reduce(0) { acc, _ in acc + 3 }
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

    // MARK: - V5 composite score

    static func pctChangeVsPrev(cur: Double, prev: Double) -> Double? {
        if prev == 0 && cur == 0 { return 0 }
        if prev == 0 { return nil }
        return ((cur - prev) / abs(prev)) * 100
    }

    static func computeCompositeScore(
        cur: FinancialSummary,
        prev: FinancialSummary,
        sandWashed: Double,
        sandTransported: Double,
        prevSandWashed: Double,
        prevSandTransported: Double
    ) -> CompositeScoreResult {
        let marginScore: Double = cur.income > 0
            ? max(0, min(100, (cur.profit / cur.income) * 100))
            : (cur.profit > 0 ? 100 : 0)

        var growthScore = 50.0
        if prev.profit != 0 {
            growthScore = max(0, min(100, 50 + ((cur.profit - prev.profit) / abs(prev.profit)) * 50))
        } else if cur.profit > 0 {
            growthScore = 85
        }

        let expenseRatio = cur.income > 0 ? (cur.expense / cur.income) * 100 : (cur.expense > 0 ? 100 : 0)
        let costControlScore = max(0, min(100, 100 - expenseRatio * 0.6))

        let sandTotal = sandWashed + sandTransported
        let sandScore = sandTotal <= 0 ? 70 : max(0, min(100, (sandWashed / max(sandWashed, sandTransported)) * 100))

        let score = Int(round(marginScore * 0.35 + growthScore * 0.25 + costControlScore * 0.25 + sandScore * 0.15))

        let profitDelta = pctChangeVsPrev(cur: cur.profit, prev: prev.profit)
        let costDelta = pctChangeVsPrev(
            cur: cur.income > 0 ? (cur.expense / cur.income) * 100 : (cur.expense > 0 ? 100 : 0),
            prev: prev.income > 0 ? (prev.expense / prev.income) * 100 : (prev.expense > 0 ? 100 : 0)
        )

        return CompositeScoreResult(
            score: max(0, min(100, score)),
            breakdown: [
                ScoreBreakdownItem(label: "ความคุ้มทุน", weight: "35%", scorePart: Int(marginScore), changeLabel: fmtSignedPct(profitDelta), trend: trendFrom(profitDelta)),
                ScoreBreakdownItem(label: "การเติบโตกำไร", weight: "25%", scorePart: Int(growthScore), changeLabel: fmtSignedPct(profitDelta), trend: trendFrom(profitDelta)),
                ScoreBreakdownItem(label: "ควบคุมต้นทุน", weight: "25%", scorePart: Int(costControlScore), changeLabel: fmtSignedPct(costDelta, invert: true), trend: trendFrom(costDelta, invert: true)),
                ScoreBreakdownItem(label: "สมดุลทราย", weight: "15%", scorePart: Int(sandScore), changeLabel: "ล้าง \(Int(sandWashed)) / ขน \(Int(sandTransported))", trend: .neutral)
            ]
        )
    }

    private static func fmtSignedPct(_ n: Double?, invert: Bool = false) -> String {
        guard let n else { return "ไม่มีฐานเทียบ" }
        let rounded = abs(n) >= 10 ? round(n) : (round(n * 10) / 10)
        let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : ""
        return "\(sign)\(abs(rounded))% เทียบช่วงก่อน"
    }

    private static func trendFrom(_ n: Double?, invert: Bool = false) -> ScoreTrend {
        guard let n else { return .neutral }
        if n == 0 { return .flat }
        let good = invert ? n < 0 : n > 0
        return good ? .up : .down
    }

    // MARK: - Count record (V4)

    static func isCountRecordVehicleRow(_ t: Transaction) -> Bool {
        guard t.category == "DailyLog", t.subCategory?.lowercased() == "vehicletrip" else { return false }
        return !(t.description).contains("ทรายที่ล้างที่บ้าน")
    }

    static func isCountRecordSandTapRow(_ t: Transaction) -> Bool {
        guard t.category == "DailyLog", t.subCategory?.lowercased() == "sand" else { return false }
        let desc = t.description
        if desc.contains("เครื่องร่อน") || desc.contains("จำนวนถัง") || desc.contains("ทรายที่ล้างที่บ้าน") { return false }
        return desc.contains("ร่อนทราย")
    }

    static func driverDisplayName(_ driverId: String, employees: [Employee]) -> String {
        let id = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "ยังไม่ระบุ" }
        if let emp = employees.first(where: { $0.id == id }) { return emp.displayName }
        return id
    }

    static func countRecordRows(for date: String, transactions: [Transaction], employees: [Employee]) -> (vehicles: [CountRecordVehicleRow], sand: [CountRecordSandRow], tripTotal: Int, sandTotal: Int) {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == date }
        let vehicleRows = dayTx.filter(isCountRecordVehicleRow).map { t -> CountRecordVehicleRow in
            let morning = Int(t.tripMorning ?? 0)
            let afternoon = Int(t.tripAfternoon ?? 0)
            let total = Int(t.perCarTrips ?? t.tripCount ?? 0)
            let m = morning != 0 || afternoon != 0 ? morning : total
            let a = morning != 0 || afternoon != 0 ? afternoon : 0
            return CountRecordVehicleRow(
                id: t.id,
                vehicleName: t.description,
                driverName: driverDisplayName(t.driverId ?? "", employees: employees),
                morningTrips: m,
                afternoonTrips: a,
                totalTrips: max(total, m + a),
                isBroken: (t.workDetails ?? "").contains("รถเสีย")
            )
        }
        let sandRows = dayTx.filter(isCountRecordSandTapRow).map { t -> CountRecordSandRow in
            CountRecordSandRow(
                id: t.id,
                drums: Int(t.drumsObtained ?? 0),
                morningDrums: Int(t.sandMorning ?? 0),
                afternoonDrums: Int(t.sandAfternoon ?? 0),
                lapCount: (t.workAssignments?["lapTimes"] ?? []).count
            )
        }
        let tripTotal = vehicleRows.reduce(0) { $0 + $1.totalTrips }
        let sandTotal = sandRows.reduce(0) { $0 + $1.drums }
        return (vehicleRows, sandRows, tripTotal, sandTotal)
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
