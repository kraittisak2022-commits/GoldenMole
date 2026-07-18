import SwiftUI

struct AnalyticsV2View: View {
    let transactions: [Transaction]
    let settings: AppSettings
    let dateFilter: DateFilter

    private var expenses: [Transaction] { transactions.filter { $0.type == .expense } }
    private var incomes: [Transaction] { transactions.filter { $0.type == .income } }
    private var totalExpense: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var totalIncome: Double { incomes.reduce(0) { $0 + $1.amount } }
    private var numDays: Int { DashboardAggregations.countInclusiveDays(dateFilter.start, dateFilter.end) }

    private var dailyExpenses: [(date: String, label: String, total: Double)] {
        DashboardAggregations.enumerateDates(in: dateFilter).map { date in
            let total = expenses.filter { String($0.date.prefix(10)) == date }.reduce(0) { $0 + $1.amount }
            return (date, DashboardAggregations.dayLabel(date), total)
        }
    }

    private var catSlices: [ChartSlice] {
        let cats: [(String, String, String)] = [
            ("Labor", "ค่าแรง", "#10b981"),
            ("Fuel", "น้ำมัน", "#ea580c"),
            ("Vehicle", "การใช้รถ", "#f59e0b"),
            ("Maintenance", "ซ่อมบำรุง", "#64748b"),
            ("Land", "ที่ดิน", "#8b5cf6")
        ]
        return cats.compactMap { key, label, color in
            let v = expenses.filter { $0.category == key }.reduce(0) { $0 + $1.amount }
            guard v > 0 else { return nil }
            return ChartSlice(label: label, value: v, colorHex: color)
        }
    }

    private var vehicleCosts: [(name: String, total: Double)] {
        settings.cars.compactMap { car in
            let total = expenses.filter {
                ($0.category == "Fuel" || $0.category == "Maintenance" || $0.category == "Vehicle") && $0.description.contains(car)
            }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { return nil }
            return (car, total)
        }
    }

    private var dayChange: Int {
        let daily = dailyExpenses
        guard daily.count >= 2 else { return 0 }
        let today = daily.last?.total ?? 0
        let yesterday = daily[daily.count - 2].total
        guard yesterday > 0 else { return 0 }
        return Int(round(((today - yesterday) / yesterday) * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
            SectionHeader(
                title: "วิเคราะห์ (V.2)",
                systemImage: "chart.bar.xaxis",
                subtitle: "รายจ่ายและแนวโน้ม"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(title: "รายจ่ายรวม", value: DashboardAggregations.formatCurrency(totalExpense), subtitle: "\(numDays) วัน", accent: AppTheme.expense, systemImage: "arrow.down.circle")
                KPITile(title: "เฉลี่ย/วัน", value: DashboardAggregations.formatCurrency(numDays > 0 ? totalExpense / Double(numDays) : 0), subtitle: "vs เมื่อวาน \(dayChange)%", accent: AppTheme.info, systemImage: "calendar")
                KPITile(title: "เฉลี่ย/สัปดาห์", value: DashboardAggregations.formatCurrency(totalExpense / max(1, Double(numDays) / 7)), accent: AppTheme.warning, systemImage: "chart.bar")
                KPITile(title: "กำไรสุทธิ", value: DashboardAggregations.formatCurrency(totalIncome - totalExpense), subtitle: "รายรับ − รายจ่าย", accent: (totalIncome - totalExpense) >= 0 ? AppTheme.income : AppTheme.expense, systemImage: "scalemass")
            }

            SectionCard("รายจ่ายรายวัน", systemImage: "chart.bar.fill") {
                BarChartView(
                    labels: dailyExpenses.map(\.label),
                    values: dailyExpenses.map(\.total),
                    barColor: AppTheme.expense
                )
            }

            SectionCard("สัดส่วนตามหมวด", systemImage: "chart.pie.fill") {
                if catSlices.isEmpty {
                    EmptyStateView(title: "ไม่มีข้อมูล", systemImage: "chart.pie")
                } else {
                    DonutChartView(slices: catSlices)
                        .frame(height: 180)
                }
            }

            if !vehicleCosts.isEmpty {
                SectionCard("ต้นทุนต่อรถ", systemImage: "car.fill") {
                    ForEach(vehicleCosts, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(DashboardAggregations.formatCurrency(item.total)).bold()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                }
            }

            SectionCard("แนวโน้มรายจ่าย", systemImage: "chart.line.uptrend.xyaxis") {
                LineChartView(
                    labels: dailyExpenses.map(\.label),
                    values: dailyExpenses.map(\.total),
                    lineColor: AppTheme.expense
                )
            }
        }
    }
}
