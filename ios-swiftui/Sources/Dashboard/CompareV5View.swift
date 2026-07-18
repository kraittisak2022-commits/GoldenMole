import SwiftUI
import UIKit

struct CompareV5View: View {
    let transactions: [Transaction]
    let dateFilter: DateFilter

    @State private var showShare = false
    @State private var csvText = ""

    private var curTx: [Transaction] { DashboardAggregations.filterByRange(transactions, range: dateFilter) }
    private var prevFilter: DateFilter { DashboardAggregations.previousPeriodFilter(dateFilter) }
    private var prevTx: [Transaction] { DashboardAggregations.filterByRange(transactions, range: prevFilter) }

    private var curFin: FinancialSummary { DashboardAggregations.aggregateFinancial(curTx) }
    private var prevFin: FinancialSummary { DashboardAggregations.aggregateFinancial(prevTx) }

    private var sandCur: (washed: Double, transported: Double) { sandTotals(curTx) }
    private var sandPrev: (washed: Double, transported: Double) { sandTotals(prevTx) }

    private var composite: CompositeScoreResult {
        DashboardAggregations.computeCompositeScore(
            cur: curFin, prev: prevFin,
            sandWashed: sandCur.washed, sandTransported: sandCur.transported,
            prevSandWashed: sandPrev.washed, prevSandTransported: sandPrev.transported
        )
    }

    private var dailyPoints: [(label: String, income: Double, expense: Double)] {
        DashboardAggregations.enumerateDates(in: dateFilter).map { date in
            let day = curTx.filter { String($0.date.prefix(10)) == date }
            let income = day.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
            let expense = day.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
            return (DashboardAggregations.dayLabel(date), income, expense)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "ภาพรวม (V.5)",
                    systemImage: "speedometer",
                    subtitle: "เทียบช่วงก่อนหน้า"
                )
                Spacer()
                Button {
                    exportCSV()
                } label: {
                    Label("ส่งออก CSV", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.brand)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "กำไรสุทธิ",
                    value: DashboardAggregations.formatCurrency(curFin.profit),
                    subtitle: deltaText(curFin.profit, prevFin.profit),
                    accent: curFin.profit >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                KPITile(
                    title: "อัตรากำไร",
                    value: marginText(curFin),
                    accent: AppTheme.info,
                    systemImage: "percent"
                )
                scoreTile
                KPITile(
                    title: "รายรับ",
                    value: DashboardAggregations.formatCurrency(curFin.income),
                    subtitle: deltaText(curFin.income, prevFin.income),
                    accent: AppTheme.income,
                    systemImage: "banknote"
                )
            }

            SectionCard("เทียบช่วงก่อน", systemImage: "arrow.left.arrow.right") {
                comparisonRow("รายรับ", curFin.income, prevFin.income)
                comparisonRow("รายจ่าย", curFin.expense, prevFin.expense)
                comparisonRow("กำไร", curFin.profit, prevFin.profit)
                comparisonRow("ล้างทราย (คิว)", sandCur.washed, sandPrev.washed)
                comparisonRow("ขนทราย (คิว)", sandCur.transported, sandPrev.transported)
            }

            SectionCard("รายละเอียดคะแนน", systemImage: "star.fill") {
                ForEach(composite.breakdown) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.label).font(.subheadline.bold())
                            Spacer()
                            Text("\(item.scorePart)").font(.subheadline)
                            Text("(\(item.weight))").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(item.changeLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            SectionCard("จุดคุ้มทุนรายวัน", systemImage: "chart.dots.scatter", subtitle: "รายรับ vs รายจ่าย") {
                BreakEvenScatterView(points: dailyPoints.map { ($0.income, $0.expense, $0.label) })
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [csvText])
        }
    }

    private var scoreTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("คะแนนรวม")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemFill), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(composite.score) / 100)
                        .stroke(AppTheme.purple, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(composite.score)")
                        .font(.headline.bold())
                }
                .frame(width: 52, height: 52)
                Text("/ 100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(AppTheme.purple)
                .frame(height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func comparisonRow(_ title: String, _ cur: Double, _ prev: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(DashboardAggregations.formatNumber(cur))
            Text(deltaText(cur, prev))
                .font(.caption)
                .foregroundStyle(cur >= prev ? AppTheme.income : AppTheme.expense)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    private func marginText(_ fin: FinancialSummary) -> String {
        guard fin.income > 0 else { return fin.profit > 0 ? "100%" : "0%" }
        return String(format: "%.1f%%", (fin.profit / fin.income) * 100)
    }

    private func deltaText(_ cur: Double, _ prev: Double) -> String {
        guard let pct = DashboardAggregations.pctChangeVsPrev(cur: cur, prev: prev) else { return "ไม่มีฐานเทียบ" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(round(pct)))% vs ช่วงก่อน"
    }

    private func sandTotals(_ txs: [Transaction]) -> (washed: Double, transported: Double) {
        let washed = txs.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
            .reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
        let dates = Set(txs.map { String($0.date.prefix(10)) })
        let transported = dates.reduce(0.0) { $0 + DashboardAggregations.sandTransportedCubic(txs, date: $1) }
        return (washed, transported)
    }

    private func exportCSV() {
        var lines = ["metric,current,previous"]
        lines.append("income,\(curFin.income),\(prevFin.income)")
        lines.append("expense,\(curFin.expense),\(prevFin.expense)")
        lines.append("profit,\(curFin.profit),\(prevFin.profit)")
        lines.append("score,\(composite.score),")
        csvText = lines.joined(separator: "\n")
        showShare = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
