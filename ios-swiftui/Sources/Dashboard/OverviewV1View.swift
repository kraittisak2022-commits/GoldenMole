import SwiftUI

struct OverviewV1View: View {
    let transactions: [Transaction]
    let dateFilter: DateFilter

    private var financial: FinancialSummary { DashboardAggregations.aggregateFinancial(transactions) }
    private var expenseByCat: [String: Double] { DashboardAggregations.expenseByCategory(transactions) }

    private var costSlices: [ChartSlice] {
        let defs: [(String, String, String)] = [
            ("Labor", "ค่าแรง", "#10b981"),
            ("Vehicle", "การใช้รถ", "#f59e0b"),
            ("Fuel", "น้ำมัน", "#ea580c"),
            ("Maintenance", "ซ่อมบำรุง", "#64748b"),
            ("Land", "ที่ดิน", "#8b5cf6"),
            ("DailyLog", "งานประจำวัน", "#06b6d4")
        ]
        return defs.compactMap { key, label, color in
            let v = expenseByCat[key] ?? 0
            guard v > 0 else { return nil }
            return ChartSlice(label: label, value: v, colorHex: color)
        }
    }

    private var dailyExpenseBars: (labels: [String], values: [Double]) {
        let dates = DashboardAggregations.enumerateDates(in: dateFilter)
        let labels = dates.map { DashboardAggregations.dayLabel($0) }
        let values = dates.map { date in
            transactions.filter { String($0.date.prefix(10)) == date && $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
        }
        return (labels, values)
    }

    private var sandSeries: (washed: [Double], transported: [Double], labels: [String]) {
        let s = DashboardAggregations.buildDailySandSeries(filter: dateFilter, transactions: transactions)
        return (s.washed, s.transported, s.labels)
    }

    private var sandKPIs: (washTotal: Double, transportTotal: Double, drumsObtained: Double, drumsHome: Double) {
        let sandTx = transactions.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
        let wash = sandTx.reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
        let transport = DashboardAggregations.enumerateDates(in: dateFilter)
            .reduce(0.0) { $0 + DashboardAggregations.sandTransportedCubic(transactions, date: $1) }
        let obtained = sandTx.reduce(0.0) { $0 + ($1.drumsObtained ?? 0) }
        let home = DashboardAggregations.persistedSandHomeDrums(sandTx)
        return (wash, transport, obtained, home)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
            SectionHeader(
                title: "ภาพรวม (V.1)",
                systemImage: "chart.pie.fill",
                subtitle: "สรุปการเงินและทรายในช่วงที่เลือก"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "กำไรสุทธิ",
                    value: DashboardAggregations.formatCurrency(financial.profit),
                    subtitle: "รายรับ − รายจ่าย",
                    accent: financial.profit >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                KPITile(
                    title: "รายรับรวม",
                    value: DashboardAggregations.formatCurrency(financial.income),
                    accent: AppTheme.income,
                    systemImage: "banknote"
                )
                KPITile(
                    title: "รายจ่ายรวม",
                    value: DashboardAggregations.formatCurrency(financial.expense),
                    accent: AppTheme.expense,
                    systemImage: "creditcard"
                )
            }

            SectionCard("โครงสร้างต้นทุน", systemImage: "circle.grid.cross.fill") {
                if costSlices.isEmpty {
                    EmptyStateView(title: "ไม่มีรายจ่ายในช่วงนี้", systemImage: "tray")
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        DonutChartView(slices: costSlices)
                            .frame(width: 140, height: 140)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(costSlices) { slice in
                                HStack {
                                    Circle().fill(Color(hex: slice.colorHex)).frame(width: 8, height: 8)
                                    Text(slice.label).font(.caption)
                                    Spacer()
                                    Text(DashboardAggregations.formatCurrency(slice.value))
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }
            }

            SectionCard("รายจ่ายรายวัน", systemImage: "chart.bar.fill") {
                let bars = dailyExpenseBars
                BarChartView(labels: bars.labels, values: bars.values, barColor: AppTheme.expense)
            }

            SectionCard("วิเคราะห์ทราย", systemImage: "drop.fill", subtitle: "ล้าง vs ขนทราย") {
                let kpi = sandKPIs
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    KPITile(title: "ล้างทราย", value: "\(DashboardAggregations.formatNumber(kpi.washTotal)) คิว", accent: AppTheme.info, systemImage: "drop")
                    KPITile(title: "ขนทราย", value: "\(DashboardAggregations.formatNumber(kpi.transportTotal)) คิว", accent: AppTheme.warning, systemImage: "truck.box")
                    KPITile(title: "ถังที่ได้", value: "\(DashboardAggregations.formatNumber(kpi.drumsObtained)) ถัง", accent: AppTheme.sand, systemImage: "archivebox.fill")
                    KPITile(title: "ล้างที่บ้าน", value: "\(DashboardAggregations.formatNumber(kpi.drumsHome)) ถัง", accent: AppTheme.purple, systemImage: "house")
                }
                let series = sandSeries
                SandDualLineChart(labels: series.labels, washed: series.washed, transported: series.transported)
                    .frame(height: 200)
            }
        }
    }
}

private struct SandDualLineChart: View {
    let labels: [String]
    let washed: [Double]
    let transported: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max((washed + transported).max() ?? 1, 1)
            let w = geo.size.width
            let h = geo.size.height
            let count = max(labels.count, 1)
            ZStack(alignment: .topLeading) {
                path(values: washed, color: AppTheme.info, maxV: maxV, w: w, h: h, count: count)
                path(values: transported, color: AppTheme.warning, maxV: maxV, w: w, h: h, count: count)
                HStack(spacing: 12) {
                    Label("ล้าง", systemImage: "circle.fill").font(.caption2).foregroundStyle(AppTheme.info)
                    Label("ขน", systemImage: "circle.fill").font(.caption2).foregroundStyle(AppTheme.warning)
                }
                .padding(.top, 4)
            }
        }
    }

    private func path(values: [Double], color: Color, maxV: Double, w: CGFloat, h: CGFloat, count: Int) -> some View {
        Path { p in
            for (i, v) in values.enumerated() {
                let x = count <= 1 ? w / 2 : CGFloat(i) / CGFloat(count - 1) * w
                let y = h - CGFloat(v / maxV) * (h - 20) - 10
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(color, lineWidth: 2.5)
    }
}
