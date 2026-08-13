import SwiftUI

enum CategoryReportType: CaseIterable, Identifiable {
    case labor, vehicle, sand, fuel, land, income

    var id: String { title }

    var title: String {
        switch self {
        case .labor: return "ค่าแรง"
        case .vehicle: return "การใช้รถ"
        case .sand: return "ล้างทราย"
        case .fuel: return "น้ำมัน"
        case .land: return "ที่ดิน"
        case .income: return "รายรับ"
        }
    }

    var systemImage: String {
        switch self {
        case .labor: return "person.2.fill"
        case .vehicle: return "truck.box.fill"
        case .sand: return "drop.fill"
        case .fuel: return "fuelpump.fill"
        case .land: return "map.fill"
        case .income: return "banknote.fill"
        }
    }

    var accent: Color {
        switch self {
        case .labor: return AppTheme.labor
        case .vehicle: return AppTheme.vehicle
        case .sand: return AppTheme.sand
        case .fuel: return AppTheme.fuel
        case .land: return AppTheme.land
        case .income: return AppTheme.income
        }
    }

    /// Rows this report draws from — used to tell "no data on this day" apart from an empty report.
    func matches(_ t: Transaction) -> Bool {
        switch self {
        case .labor: return t.category == "Labor"
        case .vehicle: return t.category == "Vehicle" || (t.category == "DailyLog" && t.subCategory == "VehicleTrip")
        case .sand: return t.category == "DailyLog" && t.subCategory == "Sand"
        case .fuel: return t.category == "Fuel"
        case .land: return t.category == "Land"
        case .income: return t.type == .income
        }
    }

    /// Compact hub card values for a single day (shown on the Reports tab before drilling in).
    func hubSummary(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        settings: AppSettings
    ) -> CategoryHubSummary {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey && matches($0) }
        switch self {
        case .labor:
            let total = dayTx.reduce(0.0) {
                $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
            }
            let people = Set(dayTx.flatMap { $0.employeeIds ?? [] }.filter { !$0.isEmpty }).count
            return CategoryHubSummary(
                primary: total > 0 ? DashboardAggregations.formatCurrency(total) : "฿0",
                secondary: people > 0 ? "\(people) คนที่เกี่ยวข้อง" : "ยังไม่มีบันทึกวันนี้",
                hasData: total > 0 || !dayTx.isEmpty
            )
        case .vehicle:
            let total = dayTx.reduce(0.0) {
                $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
            }
            let trips = dayTx.reduce(0) { $0 + CountRecordLogic.tripRounds(from: $1) }
            let cars = Set(dayTx.compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }).count
            let secondary: String
            if trips > 0 || cars > 0 {
                secondary = "\(cars) คัน · \(trips) เที่ยว"
            } else {
                secondary = total > 0 ? "ค่าใช้จ่ายยานพาหนะ" : "ยังไม่มีบันทึกวันนี้"
            }
            return CategoryHubSummary(
                primary: total > 0 ? DashboardAggregations.formatCurrency(total) : "฿0",
                secondary: secondary,
                hasData: total > 0 || trips > 0 || !dayTx.isEmpty
            )
        case .sand:
            let obtained = dayTx.compactMap(\.drumsObtained).max() ?? 0
            let home = DashboardAggregations.persistedSandHomeDrums(dayTx)
            let washed = dayTx.reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
            let hasData = obtained > 0 || home > 0 || washed > 0 || !dayTx.isEmpty
            return CategoryHubSummary(
                primary: washed > 0
                    ? "\(DashboardAggregations.formatNumber(washed)) คิว"
                    : (obtained > 0 ? "\(DashboardAggregations.formatNumber(obtained)) ถัง" : "—"),
                secondary: hasData
                    ? "ได้ \(DashboardAggregations.formatNumber(obtained)) · บ้าน \(DashboardAggregations.formatNumber(home))"
                    : "ยังไม่มีบันทึกวันนี้",
                hasData: hasData
            )
        case .fuel:
            let usedRows = dayTx
                .filter { FuelLogic.isFuelExpense($0) && !FuelLogic.isStockIn($0) }
                .reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) }
            let used = usedRows + FuelLogic.inferredSandSieveLiters(on: dayKey, transactions: transactions)
            let inbound = dayTx
                .filter { FuelLogic.isStockIn($0) }
                .reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) }
            let throughDay = transactions.filter { String($0.date.prefix(10)) <= dayKey }
            let bal = FuelLogic.computeBalance(
                transactions: throughDay,
                opening: settings.fuelOpeningStockLiters
            )
            return CategoryHubSummary(
                primary: "หลัก \(DashboardAggregations.formatNumber(bal.mainDiesel)) · สำรอง \(DashboardAggregations.formatNumber(bal.reserveDiesel)) L",
                secondary: used > 0 || inbound > 0
                    ? "ใช้ \(DashboardAggregations.formatNumber(used)) L · เข้า \(DashboardAggregations.formatNumber(inbound)) L"
                    : (dayTx.isEmpty ? "ยังไม่มีบันทึกวันนี้" : "มีการเคลื่อนไหวสต็อก"),
                hasData: bal.mainDiesel != 0 || bal.reserveDiesel != 0 || used != 0 || inbound != 0 || !dayTx.isEmpty
            )
        case .land:
            let total = dayTx.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
            let groups = Set(dayTx.compactMap { t -> String? in
                if let sc = t.subCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !sc.isEmpty {
                    return sc
                }
                return settings.landGroups.first { t.description.contains($0) }
            })
            return CategoryHubSummary(
                primary: total > 0 ? DashboardAggregations.formatCurrency(total) : "฿0",
                secondary: groups.isEmpty
                    ? (dayTx.isEmpty ? "ยังไม่มีบันทึกวันนี้" : "\(dayTx.count) รายการ")
                    : "\(groups.count) โครงการ",
                hasData: total > 0 || !dayTx.isEmpty
            )
        case .income:
            let total = dayTx.reduce(0.0) { $0 + $1.amount }
            return CategoryHubSummary(
                primary: total > 0 ? DashboardAggregations.formatCurrency(total) : "฿0",
                secondary: dayTx.isEmpty ? "ยังไม่มีรายรับวันนี้" : "\(dayTx.count) รายการ",
                hasData: total > 0 || !dayTx.isEmpty
            )
        }
    }
}

struct CategoryHubSummary: Sendable {
    let primary: String
    let secondary: String
    let hasData: Bool
}

struct CategoryReportView: View {
    let type: CategoryReportType
    let transactions: [Transaction]
    let settings: AppSettings
    let employees: [Employee]
    let dateFilter: DateFilter
    var scopeTitle: String = "ช่วงวันที่ที่เลือก"
    /// Full ledger for fuel stock remaining (defaults to `transactions` when omitted).
    var stockTransactions: [Transaction]? = nil

    @State private var expandedDate: String?
    @State private var sandPeriod: SandPeriod = .week

    /// A one-bar chart says nothing, so the daily breakdown is dropped in single-day mode.
    private var isSingleDay: Bool { dateFilter.start == dateFilter.end }

    private var fuelStockSource: [Transaction] { stockTransactions ?? transactions }

    enum SandPeriod: String, CaseIterable {
        case week, month, year
        var label: String {
            switch self {
            case .week: return "สัปดาห์"
            case .month: return "เดือน"
            case .year: return "ปี"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
            reportHeroBanner

            switch type {
            case .sand: sandView
            case .labor: laborView
            case .vehicle: vehicleView
            case .fuel: fuelView
            case .land: landView
            case .income: incomeView
            }
        }
    }

    private var reportHeroBanner: some View {
        let banner: CategoryHubSummary
        if type == .fuel {
            banner = fuelBannerSummary(scopePrefix: scopeTitle)
        } else {
            let summary = type.hubSummary(
                dayKey: dateFilter.end,
                transactions: transactions,
                employees: employees,
                settings: settings
            )
            banner = rangeBannerValues(fallback: summary)
        }

        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: type.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))
                Text(banner.primary)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(banner.secondary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [type.accent.opacity(0.95), type.accent.opacity(0.7), AppTheme.brandDark.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: type.accent.opacity(0.3), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(type.title) \(banner.primary) \(banner.secondary)")
    }

    private func rangeBannerValues(fallback: CategoryHubSummary) -> CategoryHubSummary {
        guard !isSingleDay else {
            return CategoryHubSummary(
                primary: fallback.primary,
                secondary: "\(scopeTitle) · \(fallback.secondary)",
                hasData: fallback.hasData
            )
        }
        switch type {
        case .labor:
            let total = transactions.reduce(0.0) {
                $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
            }
            return CategoryHubSummary(
                primary: DashboardAggregations.formatCurrency(total),
                secondary: "\(scopeTitle) · \(transactions.count) รายการ",
                hasData: total > 0 || !transactions.isEmpty
            )
        case .vehicle:
            let total = transactions.reduce(0.0) {
                $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
            }
            return CategoryHubSummary(
                primary: DashboardAggregations.formatCurrency(total),
                secondary: "\(scopeTitle) · \(transactions.count) รายการ",
                hasData: total > 0 || !transactions.isEmpty
            )
        case .fuel:
            return fuelBannerSummary(scopePrefix: scopeTitle)
        case .land:
            let total = transactions.filter { $0.type == .expense }.reduce(0.0) { $0 + $1.amount }
            return CategoryHubSummary(
                primary: DashboardAggregations.formatCurrency(total),
                secondary: scopeTitle,
                hasData: total > 0
            )
        case .income:
            let total = transactions.reduce(0.0) { $0 + $1.amount }
            return CategoryHubSummary(
                primary: DashboardAggregations.formatCurrency(total),
                secondary: scopeTitle,
                hasData: total > 0
            )
        case .sand:
            let obtained = Dictionary(grouping: transactions) { String($0.date.prefix(10)) }
                .values
                .reduce(0.0) { $0 + ($1.compactMap(\.drumsObtained).max() ?? 0) }
            let home = DashboardAggregations.persistedSandHomeDrums(transactions)
            let washed = transactions.reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
            return CategoryHubSummary(
                primary: "\(DashboardAggregations.formatNumber(washed)) คิว",
                secondary: "\(scopeTitle) · ได้ \(DashboardAggregations.formatNumber(obtained)) · บ้าน \(DashboardAggregations.formatNumber(home))",
                hasData: washed > 0 || obtained > 0 || home > 0
            )
        }
    }

    // MARK: - Sand

    private var sandView: some View {
        let rows = sandGroupedRows()
        return VStack(alignment: .leading, spacing: 12) {
            Picker("ช่วง", selection: $sandPeriod) {
                ForEach(SandPeriod.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if rows.isEmpty {
                Text("ยังไม่มีข้อมูลล้างทรายในช่วงที่เลือก").foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.key) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.label).font(.subheadline.bold())
                        HStack {
                            sandPill("ได้", row.obtained, .blue)
                            sandPill("ล้างบ้าน", row.home, .pink)
                            sandPill("คงเหลือ", row.remaining, .green)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                }
            }
        }
    }

    private struct SandRow { let key: String; let label: String; let obtained: Double; let home: Double; let remaining: Double }

    private func sandGroupedRows() -> [SandRow] {
        var perDay: [String: (obtained: Double, home: Double)] = [:]
        let sandTx = transactions.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
        let byDay = Dictionary(grouping: sandTx) { String($0.date.prefix(10)) }
        for (day, txs) in byDay {
            let obtained = txs.map { $0.drumsObtained ?? 0 }.max() ?? 0
            let home = DashboardAggregations.persistedSandHomeDrums(txs)
            perDay[day] = (obtained, home)
        }
        var grouped: [String: SandRow] = [:]
        for (dateStr, stat) in perDay {
            let (key, label) = sandGroupKey(dateStr)
            let prev = grouped[key]
            let obtained = (prev?.obtained ?? 0) + stat.obtained
            let home = (prev?.home ?? 0) + stat.home
            grouped[key] = SandRow(key: key, label: label, obtained: obtained, home: home, remaining: max(0, obtained - home))
        }
        return grouped.values.sorted { $0.key > $1.key }
    }

    private func sandGroupKey(_ dateStr: String) -> (String, String) {
        guard let d = parseDate(dateStr) else { return (dateStr, dateStr) }
        let cal = DashboardAggregations.gregorian
        switch sandPeriod {
        case .week:
            var comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
            comp.weekday = 2
            let start = cal.date(from: comp) ?? d
            let key = DashboardAggregations.formatYMD(start)
            return (key, "สัปดาห์ \(DashboardAggregations.dayLabel(key))")
        case .month:
            let key = String(format: "%04d-%02d", cal.component(.year, from: d), cal.component(.month, from: d))
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .buddhist)
            formatter.locale = Locale(identifier: "th_TH")
            formatter.timeZone = TimeZone(identifier: "Asia/Bangkok")
            formatter.dateFormat = "MMMM yyyy"
            return (key, formatter.string(from: d))
        case .year:
            let y = cal.component(.year, from: d)
            return ("\(y)", "ปี \(y + 543)")
        }
    }

    private func sandPill(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack {
            Text(title).font(.caption2)
            Text(DashboardAggregations.formatNumber(value)).font(.caption.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.12)))
    }

    // MARK: - Labor

    private var laborView: some View {
        categoryExpenseView(
            category: "Labor",
            total: laborTotal,
            slices: [
                ("ค่าแรงพื้นฐาน", laborBase, "#10b981"),
                ("OT", laborOT, "#3b82f6"),
                ("เบิกล่วงหน้า", laborAdvance, "#f59e0b")
            ],
            dailyAmount: { date in
                let dayTx = transactions.filter {
                    String($0.date.prefix(10)) == date && $0.category == "Labor"
                }
                return dayTx.reduce(0.0) {
                    $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
                }
            }
        )
    }

    private var laborTotal: Double {
        transactions
            .filter { $0.category == "Labor" }
            .reduce(0.0) { $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees) }
    }
    private var laborBase: Double {
        max(0, laborTotal - laborOT - laborAdvance)
    }
    private var laborOT: Double { transactions.filter { $0.category == "Labor" }.reduce(0) { $0 + ($1.otAmount ?? 0) } }
    private var laborAdvance: Double { transactions.filter { $0.category == "Labor" }.reduce(0) { $0 + ($1.advanceAmount ?? 0) } }

    // MARK: - Vehicle

    private var vehicleView: some View {
        categoryExpenseView(
            category: "Vehicle",
            total: vehicleTotal,
            slices: [
                ("รถ", vehicleOnly, "#f59e0b"),
                ("เที่ยว", tripOnly, "#3b82f6")
            ],
            dailyAmount: { date in
                let dayTx = transactions.filter {
                    String($0.date.prefix(10)) == date
                        && ($0.category == "Vehicle" || ($0.category == "DailyLog" && $0.subCategory == "VehicleTrip"))
                }
                return dayTx.reduce(0.0) {
                    $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees)
                }
            }
        )
    }

    private var vehicleTotal: Double {
        transactions
            .filter { $0.category == "Vehicle" || ($0.category == "DailyLog" && $0.subCategory == "VehicleTrip") }
            .reduce(0.0) { $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees) }
    }
    private var vehicleOnly: Double {
        transactions
            .filter { $0.category == "Vehicle" }
            .reduce(0.0) { $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees) }
    }
    private var tripOnly: Double {
        transactions
            .filter { $0.category == "DailyLog" && $0.subCategory == "VehicleTrip" }
            .reduce(0.0) { $0 + DashboardAggregations.wizardMonetaryAmount($1, employees: employees) }
    }

    // MARK: - Fuel (liters only — no baht)

    private var fuelView: some View {
        let dates = DashboardAggregations.enumerateDates(in: dateFilter)
        let inbound = fuelLitersWhere { FuelLogic.isStockIn($0) }
        let withdraw = fuelLitersWhere { FuelLogic.isWithdraw($0) && !FuelLogic.isCarFill($0) }
        let usage = fuelLitersWhere { FuelLogic.isVehicleUsage($0) && !FuelLogic.isCarFill($0) }
        let carFill = fuelLitersWhere { FuelLogic.isCarFill($0) }
        let sieve = FuelLogic.sandSieveLiters(in: fuelStockSource, dates: dates)
        let used = withdraw + usage + carFill + sieve
        let bal = fuelRemainingBalance
        let slices: [(String, Double, String)] = [
            ("รับเข้า", inbound, "#0d9488"),
            ("เบิก", withdraw, "#ea580c"),
            ("ใช้รถแม็คโคร", usage, "#0F766E"),
            ("เครื่องร่อน", sieve, "#DB2777"),
        ]

        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                fuelStatChip(title: "ถังหลักคงเหลือ", value: bal.mainDiesel, unit: "L", accent: AppTheme.fuel)
                fuelStatChip(title: "ถังสำรองคงเหลือ", value: bal.reserveDiesel, unit: "L", accent: Color(hex: "#0F766E"))
                fuelStatChip(title: isSingleDay ? "ใช้ไปวันนี้" : "ใช้ในช่วง", value: used, unit: "L", accent: AppTheme.expense)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    fuelStatChip(title: slice.0, value: slice.1, unit: "L", accent: Color(hex: slice.2))
                }
            }

            let chartSlices = slices.compactMap { label, value, color -> ChartSlice? in
                guard value > 0 else { return nil }
                return ChartSlice(label: label, value: value, colorHex: color)
            }
            if !chartSlices.isEmpty {
                SectionCard("สัดส่วน (ลิตร)", systemImage: "chart.pie.fill") {
                    DonutChartView(slices: chartSlices).frame(height: 160)
                }
            }

            dailyBarSection(amountForDate: { date in
                let rows = transactions
                    .filter {
                        String($0.date.prefix(10)) == date
                            && FuelLogic.isFuelExpense($0)
                            && !FuelLogic.isStockIn($0)
                    }
                    .reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) }
                return rows + FuelLogic.inferredSandSieveLiters(on: date, transactions: fuelStockSource)
            })

            fuelDetailByDate()
        }
    }

    private var fuelRemainingBalance: FuelLogic.Balance {
        let end = dateFilter.end
        let throughEnd = fuelStockSource.filter { String($0.date.prefix(10)) <= end }
        return FuelLogic.computeBalance(
            transactions: throughEnd,
            opening: settings.fuelOpeningStockLiters
        )
    }

    private var fuelRemainingDiesel: Double { fuelRemainingBalance.mainDiesel }

    private func fuelLitersWhere(_ pred: (Transaction) -> Bool) -> Double {
        transactions
            .filter { FuelLogic.isFuelExpense($0) && pred($0) }
            .reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) }
    }

    private func fuelBannerSummary(scopePrefix: String?) -> CategoryHubSummary {
        let used = fuelLitersWhere { !FuelLogic.isStockIn($0) }
            + DashboardAggregations.enumerateDates(in: dateFilter).reduce(0.0) {
                $0 + FuelLogic.inferredSandSieveLiters(on: $1, transactions: fuelStockSource)
            }
        let inbound = fuelLitersWhere { FuelLogic.isStockIn($0) }
        let bal = fuelRemainingBalance
        let secondaryCore =
            "ใช้ \(DashboardAggregations.formatNumber(used)) L · เข้า \(DashboardAggregations.formatNumber(inbound)) L"
        let secondary = scopePrefix.map { "\($0) · \(secondaryCore)" } ?? secondaryCore
        return CategoryHubSummary(
            primary: "หลัก \(DashboardAggregations.formatNumber(bal.mainDiesel)) · สำรอง \(DashboardAggregations.formatNumber(bal.reserveDiesel)) L",
            secondary: secondary,
            hasData: bal.mainDiesel != 0 || bal.reserveDiesel != 0 || used != 0 || inbound != 0 || !transactions.isEmpty
        )
    }

    private func fuelStatChip(title: String, value: Double, unit: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
            Text("\(DashboardAggregations.formatNumber(value)) \(unit)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.1))
        )
    }

    private func fuelDetailByDate() -> some View {
        let fuelRows = transactions.filter { FuelLogic.isFuelExpense($0) }
        var grouped = Dictionary(grouping: fuelRows) { String($0.date.prefix(10)) }
        for date in DashboardAggregations.enumerateDates(in: dateFilter) {
            if FuelLogic.inferredSandSieveLiters(on: date, transactions: fuelStockSource) > 0 {
                grouped[date] = grouped[date] ?? []
            }
        }
        let days = grouped.sorted { $0.key > $1.key }
        return SectionCard(isSingleDay ? "รายละเอียด" : "รายละเอียดรายวัน", systemImage: "list.bullet") {
            if days.isEmpty {
                Text("ยังไม่มีรายการน้ำมันในช่วงนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                ForEach(days, id: \.0) { date, txs in
                    let inferred = FuelLogic.inferredSandSieveLiters(on: date, transactions: fuelStockSource)
                    let dayLiters = txs.reduce(0.0) { $0 + DashboardAggregations.fuelTxToLiters($1) } + inferred
                    DisclosureGroup(isExpanded: Binding(
                        get: { expandedDate == date },
                        set: { expandedDate = $0 ? date : nil }
                    )) {
                        ForEach(txs.sorted(by: { ($0.createdAt ?? "") > ($1.createdAt ?? "") })) { t in
                            fuelDetailRow(
                                title: fuelRowTitle(t),
                                subtitle: fuelRowSubtitle(t),
                                liters: DashboardAggregations.fuelTxToLiters(t)
                            )
                        }
                        if inferred > 0, let usage = FuelLogic.sandSieveUsage(on: date, transactions: fuelStockSource) {
                            fuelDetailRow(
                                title: "เครื่องร่อน",
                                subtitle: "\(FuelLogic.formatLiters(usage.hours)) ชม. × \(FuelLogic.formatLiters(FuelLogic.sandSieveLitersPerHour)) L (ถังสำรอง)",
                                liters: inferred
                            )
                        }
                    } label: {
                        HStack {
                            Text(DashboardAggregations.thaiDateLong(date)).font(.subheadline)
                            Spacer()
                            Text("\(DashboardAggregations.formatNumber(dayLiters)) L")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.fuel)
                        }
                    }
                }
            }
        }
    }

    private func fuelDetailRow(title: String, subtitle: String, liters: Double) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text("\(DashboardAggregations.formatNumber(liters)) L")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.fuel)
        }
        .padding(.vertical, 4)
    }

    private func fuelRowTitle(_ t: Transaction) -> String {
        if FuelLogic.isSandSieve(t) {
            return "เครื่องร่อน"
        }
        if FuelLogic.isVehicleUsage(t) {
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return vid.isEmpty ? "ใช้รถแม็คโคร" : vid
        }
        if FuelLogic.isWithdraw(t) {
            let purpose = (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if purpose == "machine" { return "เบิก · เติมเครื่องจักร" }
            if purpose == "car" { return "เบิก · รถยนต์" }
            if purpose == "generator" { return "เบิก · ปั่นไฟ" }
            if !purpose.isEmpty { return "เบิก · \(purpose)" }
            return "เบิกน้ำมัน"
        }
        if FuelLogic.isStockIn(t) {
            return "รับเข้าถัง"
        }
        let desc = t.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return desc.isEmpty ? "น้ำมัน" : desc
    }

    private func fuelRowSubtitle(_ t: Transaction) -> String {
        var parts: [String] = []
        if FuelLogic.isStockIn(t) {
            parts.append("รับเข้า")
        } else if FuelLogic.isSandSieve(t) {
            parts.append("เครื่องร่อน · ถังสำรอง")
        } else if FuelLogic.isWithdraw(t) {
            parts.append("เบิก")
        } else if FuelLogic.isVehicleUsage(t) {
            parts.append("ใช้แม็คโคร")
        }
        let desc = FuelLogic.stripRecorder(t.description)
        if !desc.isEmpty, desc != fuelRowTitle(t) {
            parts.append(desc)
        }
        if let details = t.workDetails?.trimmingCharacters(in: .whitespacesAndNewlines), !details.isEmpty {
            parts.append(FuelLogic.stripRecorder(details))
        }
        if let time = t.createdAt?.prefix(16), !time.isEmpty {
            parts.append(String(time).replacingOccurrences(of: "T", with: " "))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    // MARK: - Land

    private var landView: some View {
        categoryExpenseView(
            category: "Land",
            total: landTotal,
            slices: settings.landGroups.compactMap { group in
                let v = transactions.filter { $0.category == "Land" && ($0.description.contains(group) || $0.subCategory == group) }.reduce(0) { $0 + $1.amount }
                guard v > 0 else { return nil }
                return (group, v, "#8b5cf6")
            },
            dailyAmount: { date in DashboardAggregations.categoryExpense(transactions, category: "Land", date: date) }
        )
    }

    private var landTotal: Double { transactions.filter { $0.category == "Land" && $0.type == .expense }.reduce(0) { $0 + $1.amount } }

    // MARK: - Income

    private var incomeView: some View {
        let types = IncomeTypes.visible(settings.incomeTypes)
        let total = transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let daysWithIncome = Set(transactions.filter { $0.type == .income }.map { String($0.date.prefix(10)) }).count
        return VStack(alignment: .leading, spacing: 12) {
            StatCardView(title: "รายรับรวม", value: DashboardAggregations.formatCurrency(total), subtitle: "\(daysWithIncome) วันที่มีรายรับ", accent: .green, systemImage: "banknote")
            let slices = types.compactMap { type -> ChartSlice? in
                let v = transactions.filter { $0.type == .income && ($0.subCategory == type || $0.description.contains(type)) }.reduce(0) { $0 + $1.amount }
                guard v > 0 else { return nil }
                return ChartSlice(label: type, value: v, colorHex: "#10b981")
            }
            if !slices.isEmpty {
                DonutChartView(slices: slices).frame(height: 180)
            }
            dailyBarSection(amountForDate: { date in
                transactions.filter { String($0.date.prefix(10)) == date && $0.type == .income }.reduce(0) { $0 + $1.amount }
            })
        }
    }

    // MARK: - Shared

    private func categoryExpenseView<Extra: View>(
        category: String,
        total: Double,
        slices: [(String, Double, String)],
        dailyAmount: @escaping (String) -> Double,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Breakdown chips — the hero banner already shows the headline total.
            if slices.contains(where: { $0.1 > 0 }) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        let (label, value, hex) = slice
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.inkMuted)
                            Text(DashboardAggregations.formatCurrency(value))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color(hex: hex))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: hex).opacity(0.1))
                        )
                    }
                }
            } else {
                StatCardView(
                    title: "รวม",
                    value: DashboardAggregations.formatCurrency(total),
                    subtitle: scopeTitle,
                    accent: type.accent,
                    systemImage: type.systemImage
                )
            }
            extra()
            let chartSlices = slices.compactMap { label, value, color -> ChartSlice? in
                guard value > 0 else { return nil }
                return ChartSlice(label: label, value: value, colorHex: color)
            }
            if !chartSlices.isEmpty {
                SectionCard("สัดส่วน", systemImage: "chart.pie.fill") {
                    DonutChartView(slices: chartSlices).frame(height: 160)
                }
            }
            dailyBarSection(amountForDate: dailyAmount)
            detailByDate(category: category)
        }
    }

    @ViewBuilder
    private func dailyBarSection(amountForDate: @escaping (String) -> Double) -> some View {
        if !isSingleDay {
            let dates = DashboardAggregations.enumerateDates(in: dateFilter)
            SectionCard("รายวัน", systemImage: "calendar") {
                BarChartView(
                    labels: dates.map { DashboardAggregations.dayLabel($0) },
                    values: dates.map(amountForDate)
                )
            }
        }
    }

    private func detailByDate(category: String) -> some View {
        let grouped = Dictionary(grouping: transactions.filter { $0.category == category }) { String($0.date.prefix(10)) }
            .sorted { $0.key > $1.key }
        return SectionCard(isSingleDay ? "รายละเอียด" : "รายละเอียดรายวัน", systemImage: "list.bullet") {
            ForEach(grouped, id: \.0) { date, txs in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedDate == date },
                    set: { expandedDate = $0 ? date : nil }
                )) {
                    ForEach(txs) { t in
                        HStack {
                            Text(t.description).font(.caption).lineLimit(1)
                            Spacer()
                            Text(DashboardAggregations.formatCurrency(t.amount)).font(.caption.bold())
                        }
                    }
                } label: {
                    HStack {
                        Text(DashboardAggregations.thaiDateLong(date)).font(.subheadline)
                        Spacer()
                        Text(DashboardAggregations.formatCurrency(txs.reduce(0) { $0 + $1.amount }))
                            .font(.subheadline.bold())
                    }
                }
            }
        }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = DashboardAggregations.gregorian
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: String(s.prefix(10)))
    }
}
