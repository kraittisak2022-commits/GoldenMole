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
        VStack(alignment: .leading, spacing: 16) {
            Text("วิเคราะห์ (V.2)")
                .font(.title2.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCardView(title: "รายจ่ายรวม", value: DashboardAggregations.formatCurrency(totalExpense), subtitle: "\(numDays) วัน", accent: .red, systemImage: "arrow.down.circle")
                StatCardView(title: "เฉลี่ย/วัน", value: DashboardAggregations.formatCurrency(numDays > 0 ? totalExpense / Double(numDays) : 0), subtitle: "vs เมื่อวาน \(dayChange)%", accent: .blue, systemImage: "calendar")
                StatCardView(title: "เฉลี่ย/สัปดาห์", value: DashboardAggregations.formatCurrency(totalExpense / max(1, Double(numDays) / 7)), subtitle: nil, accent: .orange, systemImage: "chart.bar")
                StatCardView(title: "กำไรสุทธิ", value: DashboardAggregations.formatCurrency(totalIncome - totalExpense), subtitle: "รายรับ − รายจ่าย", accent: (totalIncome - totalExpense) >= 0 ? .green : .red, systemImage: "scalemass")
            }

            GroupBox("รายจ่ายรายวัน") {
                BarChartView(
                    labels: dailyExpenses.map(\.label),
                    values: dailyExpenses.map(\.total),
                    barColor: Color(hex: "#ef4444")
                )
            }

            GroupBox("สัดส่วนตามหมวด") {
                if catSlices.isEmpty {
                    Text("ไม่มีข้อมูล").foregroundStyle(.secondary)
                } else {
                    DonutChartView(slices: catSlices)
                        .frame(height: 180)
                }
            }

            if !vehicleCosts.isEmpty {
                GroupBox("ต้นทุนต่อรถ") {
                    ForEach(vehicleCosts, id: \.name) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(DashboardAggregations.formatCurrency(item.total)).bold()
                        }
                        .font(.subheadline)
                    }
                }
            }

            GroupBox("แนวโน้มรายจ่าย") {
                LineChartView(
                    labels: dailyExpenses.map(\.label),
                    values: dailyExpenses.map(\.total),
                    lineColor: Color(hex: "#ef4444")
                )
            }
        }
    }
}
