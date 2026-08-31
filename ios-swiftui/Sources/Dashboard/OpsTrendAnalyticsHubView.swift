import Charts
import SwiftUI

/// Bottom-tab hub: weekly / monthly growth analytics for trips + sand sieving.
struct OpsTrendAnalyticsHubView: View {
    @Environment(AppState.self) private var appState
    @State private var period: OpsTrendPeriod = .week
    @State private var focus: OpsTrendFocus = .both
    @State private var report: OpsTrendReport = .empty(period: .week)
    @State private var isBuilding = false
    @State private var buildToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                periodPicker
                focusPicker
                if isBuilding && report.points.isEmpty {
                    ProgressView("กำลังวิเคราะห์…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    growthScoreboard
                    comparisonChartCard
                    if focus == .both {
                        dualBarsCard
                    }
                    detailCards
                    insightsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(DashboardBackground())
        .navigationTitle("วิเคราะห์ข้อมูล")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rebuildKey) {
            await rebuild()
        }
    }

    private var rebuildKey: String {
        "\(period.rawValue)|\(appState.transactionsRevision)|\(appState.employees.count)"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("วัดผลการเติบโต")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(rangeCaption)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var rangeCaption: String {
        let cur = "\(shortDate(report.filter.start)) – \(shortDate(report.filter.end))"
        let prev = "\(shortDate(report.prevFilter.start)) – \(shortDate(report.prevFilter.end))"
        return "ช่วงนี้ \(cur)  ·  เทียบ \(prev)"
    }

    private func shortDate(_ ymd: String) -> String {
        DashboardAggregations.dayLabel(ymd)
    }

    // MARK: - Pickers

    private var periodPicker: some View {
        Picker("ช่วง", selection: $period) {
            ForEach(OpsTrendPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: period) { _, _ in
            report = .empty(period: period)
        }
    }

    private var focusPicker: some View {
        HStack(spacing: 8) {
            ForEach(OpsTrendFocus.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { focus = item }
                } label: {
                    Text(item.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(focus == item ? Color.white : AppTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(focus == item ? AppTheme.brand : AppTheme.surfaceSoft)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Scoreboard

    private var growthScoreboard: some View {
        let cards = visibleCards
        let columns: [GridItem] = cards.count == 1
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                growthTile(card)
            }
        }
    }

    private var visibleCards: [OpsTrendMetricCard] {
        switch focus {
        case .both: return [report.trip, report.sand]
        case .trip: return [report.trip]
        case .sand: return [report.sand]
        }
    }

    private func growthTile(_ card: OpsTrendMetricCard) -> some View {
        let accent = accent(for: card)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                paceChip(card.pace, accent: accent)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(OpsTrendAnalytics.formatCompact(card.total))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .contentTransition(.numericText())
                Text(card.unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            Label(
                "เฉลี่ย \(OpsTrendAnalytics.formatCompact(card.average))/วัน",
                systemImage: "chart.bar.fill"
            )
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.inkMuted)
            .lineLimit(1)

            HStack {
                Text(OpsTrendAnalytics.formatSignedPct(card.changePct))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(deltaColor(card.changePct))
                Text("vs \(period.shortLabel)ก่อน")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("คะแนน \(card.growthScore)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func paceChip(_ pace: OpsTrendPace, accent: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pace.systemImage)
                .font(.caption2.weight(.bold))
            Text(pace.label)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.12)))
    }

    // MARK: - Charts

    private var comparisonChartCard: some View {
        SectionCard(chartTitle, systemImage: "chart.xyaxis.line", subtitle: "เส้นทึบ = ช่วงนี้ · เส้นประ = ช่วงก่อน") {
            if primaryCard.series.isEmpty {
                Text("ยังไม่มีข้อมูลในช่วงนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 20)
            } else if focus == .both {
                LineChartView(
                    labels: report.trip.labels,
                    values: report.trip.series,
                    lineColor: AppTheme.info,
                    secondaryValues: report.sand.series,
                    secondaryColor: AppTheme.brand,
                    primaryLabel: "เที่ยวรถ",
                    secondaryLabel: "ร่อนทราย"
                )
            } else {
                trendVsPrevChart(card: primaryCard)
            }
        }
    }

    private var chartTitle: String {
        switch focus {
        case .both: return "แนวโน้มเที่ยวรถ × ร่อนทราย"
        case .trip: return "เที่ยวรถ เทียบช่วงก่อน"
        case .sand: return "ร่อนทราย เทียบช่วงก่อน"
        }
    }

    private var primaryCard: OpsTrendMetricCard {
        focus == .sand ? report.sand : report.trip
    }

    private func trendVsPrevChart(card: OpsTrendMetricCard) -> some View {
        let labels = card.labels
        let cur = zip(labels, card.series).enumerated().map {
            TrendPoint(id: "c-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงนี้")
        }
        let prevAligned = zip(labels, card.prevSeries).enumerated().map {
            TrendPoint(id: "p-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงก่อน")
        }
        let accent = accent(for: card)

        return Chart(cur + prevAligned) { p in
            if p.series == "ช่วงนี้" {
                LineMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value), series: .value("s", p.series))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                AreaMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value), series: .value("s", p.series))
                    .foregroundStyle(accent.opacity(0.16))
                    .interpolationMethod(.catmullRom)
            } else {
                LineMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value), series: .value("s", p.series))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.75))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, dash: [5, 4]))
            }
            PointMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value))
                .foregroundStyle(p.series == "ช่วงนี้" ? accent : AppTheme.inkMuted.opacity(0.5))
                .symbolSize(p.series == "ช่วงนี้" ? 36 : 20)
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(AppTheme.hairline)
                AxisValueLabel().foregroundStyle(AppTheme.inkMuted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: min(6, max(labels.count, 1)))) { _ in
                AxisValueLabel().foregroundStyle(AppTheme.inkMuted)
            }
        }
        .frame(height: 200)
    }

    private var dualBarsCard: some View {
        SectionCard(
            "เปรียบเทียบต่อช่วง",
            systemImage: "chart.bar.xaxis",
            subtitle: period == .week ? "รายวัน" : "รายสัปดาห์ย่อย"
        ) {
            GroupedBarChartView(
                labels: report.trip.labels,
                seriesA: report.trip.series,
                seriesB: report.sand.series,
                colorA: AppTheme.info,
                colorB: AppTheme.brand,
                labelA: "เที่ยวรถ",
                labelB: "ร่อนทราย"
            )
        }
    }

    // MARK: - Detail + insights

    private var detailCards: some View {
        VStack(spacing: 10) {
            ForEach(Array(visibleCards.enumerated()), id: \.offset) { _, card in
                SectionCard("\(card.title) · รายละเอียด", systemImage: "speedometer") {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        miniStat("รวมช่วงนี้", OpsTrendAnalytics.formatCompact(card.total), card.unit)
                        miniStat("รวมช่วงก่อน", OpsTrendAnalytics.formatCompact(card.prevTotal), card.unit)
                        miniStat("เฉลี่ย/วัน", OpsTrendAnalytics.formatCompact(card.average), card.unit)
                        miniStat("เฉลี่ยก่อน", OpsTrendAnalytics.formatCompact(card.prevAverage), card.unit)
                        miniStat("สูงสุด (\(card.bestLabel))", OpsTrendAnalytics.formatCompact(card.bestValue), card.unit)
                        miniStat("ต่ำสุด (\(card.worstLabel))", OpsTrendAnalytics.formatCompact(card.worstValue), card.unit)
                    }
                }
            }
        }
    }

    private func miniStat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    private var insightsCard: some View {
        SectionCard(
            "สรุปจังหวะ",
            systemImage: "text.badge.checkmark",
            subtitle: "\(report.activeDays)/\(report.coverageDays) วันมีงาน"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(report.insights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.brand)
                            .padding(.top, 2)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func accent(for card: OpsTrendMetricCard) -> Color {
        card.title.contains("ทราย") ? AppTheme.brand : AppTheme.info
    }

    private func deltaColor(_ pct: Double?) -> Color {
        guard let pct else { return AppTheme.inkMuted }
        if pct > 1 { return Color(hex: "#16a34a") }
        if pct < -1 { return Color(hex: "#dc2626") }
        return AppTheme.inkMuted
    }

    @MainActor
    private func rebuild() async {
        buildToken += 1
        let token = buildToken
        isBuilding = true
        let period = self.period
        let txs = appState.transactions
        let byDay = appState.transactionsByDay
        let emps = appState.employees

        let built = await Task.detached(priority: .userInitiated) {
            OpsTrendAnalytics.build(
                period: period,
                transactions: txs,
                employees: emps,
                byDay: byDay
            )
        }.value

        guard token == buildToken else { return }
        withAnimation(.snappy(duration: 0.25)) {
            report = built
            isBuilding = false
        }
    }
}

private struct TrendPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let series: String
}
