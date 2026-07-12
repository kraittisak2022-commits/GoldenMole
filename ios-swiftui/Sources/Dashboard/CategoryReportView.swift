import SwiftUI

enum CategoryReportType {
    case labor, vehicle, sand, fuel, land, income

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
}

struct CategoryReportView: View {
    let type: CategoryReportType
    let transactions: [Transaction]
    let settings: AppSettings
    let employees: [Employee]
    let dateFilter: DateFilter

    @State private var expandedDate: String?
    @State private var sandPeriod: SandPeriod = .week

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
        VStack(alignment: .leading, spacing: 16) {
            Text("รายงาน: \(type.title)")
                .font(.title2.bold())

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
        let cal = Calendar.current
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
            formatter.locale = Locale(identifier: "th_TH")
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
            dailyAmount: { date in DashboardAggregations.categoryExpense(transactions, category: "Labor", date: date) }
        )
    }

    private var laborTotal: Double { transactions.filter { $0.category == "Labor" && $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    private var laborBase: Double { transactions.filter { $0.category == "Labor" }.reduce(0) { $0 + ($1.amount - ($1.otAmount ?? 0) - ($1.advanceAmount ?? 0)) } }
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
            dailyAmount: { date in DashboardAggregations.vehicleExpense(transactions, date: date) }
        )
    }

    private var vehicleTotal: Double { transactions.filter { $0.type == .expense }.filter { $0.category == "Vehicle" || ($0.category == "DailyLog" && $0.subCategory == "VehicleTrip") }.reduce(0) { $0 + $1.amount } }
    private var vehicleOnly: Double { transactions.filter { $0.category == "Vehicle" && $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    private var tripOnly: Double { transactions.filter { $0.category == "DailyLog" && $0.subCategory == "VehicleTrip" && $0.type == .expense }.reduce(0) { $0 + $1.amount } }

    // MARK: - Fuel

    private var fuelView: some View {
        categoryExpenseView(
            category: "Fuel",
            total: fuelTotal,
            slices: [
                ("ดีเซล", fuelDiesel, "#ea580c"),
                ("เบนซิน", fuelBenzine, "#f59e0b")
            ],
            dailyAmount: { date in DashboardAggregations.categoryExpense(transactions, category: "Fuel", date: date) },
            extra: {
                Text("รวม \(DashboardAggregations.formatNumber(fuelLiters)) ลิตร")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        )
    }

    private var fuelTotal: Double { transactions.filter { $0.category == "Fuel" && $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    private var fuelDiesel: Double { transactions.filter { $0.category == "Fuel" && $0.fuelType == "Diesel" }.reduce(0) { $0 + $1.amount } }
    private var fuelBenzine: Double { transactions.filter { $0.category == "Fuel" && $0.fuelType == "Benzine" }.reduce(0) { $0 + $1.amount } }
    private var fuelLiters: Double { transactions.filter { $0.category == "Fuel" }.reduce(0) { $0 + ($1.quantity ?? 0) } }

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
            StatCardView(title: "รวม", value: DashboardAggregations.formatCurrency(total), subtitle: nil, accent: Color(hex: "#ef4444"), systemImage: "chart.bar")
            extra()
            let chartSlices = slices.compactMap { label, value, color -> ChartSlice? in
                guard value > 0 else { return nil }
                return ChartSlice(label: label, value: value, colorHex: color)
            }
            if !chartSlices.isEmpty {
                DonutChartView(slices: chartSlices).frame(height: 160)
            }
            dailyBarSection(amountForDate: dailyAmount)
            detailByDate(category: category)
        }
    }

    private func dailyBarSection(amountForDate: @escaping (String) -> Double) -> some View {
        let dates = DashboardAggregations.enumerateDates(in: dateFilter)
        let labels = dates.map { DashboardAggregations.dayLabel($0) }
        let values = dates.map(amountForDate)
        return GroupBox("รายวัน") {
            BarChartView(labels: labels, values: values)
        }
    }

    private func detailByDate(category: String) -> some View {
        let grouped = Dictionary(grouping: transactions.filter { $0.category == category }) { String($0.date.prefix(10)) }
            .sorted { $0.key > $1.key }
        return GroupBox("รายละเอียดรายวัน") {
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
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        return f.date(from: String(s.prefix(10)))
    }
}
