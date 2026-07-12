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

    private var sandCur: (washed: Double, transported: Double) {
        sandTotals(curTx)
    }

    private var sandPrev: (washed: Double, transported: Double) {
        sandTotals(prevTx)
    }

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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ภาพรวม (V.5)")
                    .font(.title2.bold())
                Spacer()
                Button("Export CSV") { exportCSV() }
                    .font(.caption)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCardView(title: "กำไรสุทธิ", value: DashboardAggregations.formatCurrency(curFin.profit), subtitle: deltaText(curFin.profit, prevFin.profit), accent: curFin.profit >= 0 ? .green : .red, systemImage: "chart.line.uptrend.xyaxis")
                StatCardView(title: "อัตรากำไร", value: marginText(curFin), subtitle: nil, accent: .blue, systemImage: "percent")
                StatCardView(title: "คะแนนรวม", value: "\(composite.score)/100", subtitle: "composite score", accent: Color(hex: "#8b5cf6"), systemImage: "star.fill")
                StatCardView(title: "รายรับ", value: DashboardAggregations.formatCurrency(curFin.income), subtitle: deltaText(curFin.income, prevFin.income), accent: .green, systemImage: "banknote")
            }

            GroupBox("เทียบช่วงก่อน") {
                comparisonRow("รายรับ", curFin.income, prevFin.income)
                comparisonRow("รายจ่าย", curFin.expense, prevFin.expense)
                comparisonRow("กำไร", curFin.profit, prevFin.profit)
                comparisonRow("ล้างทราย (คิว)", sandCur.washed, sandPrev.washed)
                comparisonRow("ขนทราย (คิว)", sandCur.transported, sandPrev.transported)
            }

            GroupBox("รายละเอียดคะแนน") {
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

            GroupBox("Break-even scatter") {
                BreakEvenScatterView(points: dailyPoints.map { ($0.income, $0.expense, $0.label) })
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [csvText])
        }
    }

    private func comparisonRow(_ title: String, _ cur: Double, _ prev: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(DashboardAggregations.formatNumber(cur))
            Text(deltaText(cur, prev))
                .font(.caption)
                .foregroundStyle(cur >= prev ? .green : .red)
        }
        .font(.subheadline)
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
