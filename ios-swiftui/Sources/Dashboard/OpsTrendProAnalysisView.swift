import Charts
import SwiftUI

/// Full-screen professional analytics for trip or sand (day / week / month).
/// Self-contained: supports period picker, swipe between periods, and drill-down details.
struct OpsTrendProAnalysisView: View {
    let focus: OpsTrendFocus

    @Environment(AppState.self) private var appState
    @State private var period: OpsTrendPeriod = .day
    @State private var periodOffset = 0
    @State private var report: OpsTrendReport = .empty(period: .day)
    @State private var proBundle: OpsTrendProBundle = .empty
    @State private var isBuilding = false
    @State private var buildToken = 0

    private var maxPeriodOffset: Int {
        switch period {
        case .day: return 60
        case .week: return 26
        case .month: return 12
        }
    }

    private var mode: OpsTrendAdvancedMode {
        focus == .sand ? report.sandAdvanced : report.tripAdvanced
    }

    private var card: OpsTrendMetricCard {
        focus == .sand ? report.sand : report.trip
    }

    private var accent: Color {
        focus == .sand ? AppTheme.brand : AppTheme.info
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                periodPicker
                periodNavigator
                modeDetailLink

                if isBuilding && report.points.isEmpty {
                    ProgressView("กำลังวิเคราะห์…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    proHero
                    executiveKPIs
                    performanceMatrix
                    if !proBundle.dayPerformance.isEmpty {
                        dailyPerformanceCard
                    }
                    throughputAndIntervalCharts
                    if !proBundle.hourlyBuckets.isEmpty {
                        hourlyDistributionCard
                    }
                    if focus == .trip, !proBundle.vehicleRanks.isEmpty {
                        vehicleLeaderboardCard
                    }
                    proInsightsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(DashboardBackground())
        .navigationTitle("Pro · \(focus.label)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rebuildKey) {
            await rebuild()
        }
    }

    private var rebuildKey: String {
        "\(focus.rawValue)|\(period.rawValue)|\(periodOffset)|\(appState.transactionsRevision)|\(appState.employees.count)"
    }

    // MARK: - Period controls

    private var periodPicker: some View {
        Picker("ช่วง", selection: $period) {
            ForEach(OpsTrendPeriod.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: period) { _, _ in
            periodOffset = 0
            report = .empty(period: period)
        }
    }

    private var periodNavigator: some View {
        HStack(spacing: 12) {
            Button {
                periodOffset = min(maxPeriodOffset, periodOffset + 1)
                report = .empty(period: period)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(periodOffset >= maxPeriodOffset)
            .opacity(periodOffset >= maxPeriodOffset ? 0.35 : 1)

            VStack(spacing: 3) {
                Text(periodOffsetLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(shortDate(report.filter.start)) – \(shortDate(report.filter.end))")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                Text("ปัดซ้าย/ขวาเพื่อเปลี่ยน\(period.shortLabel)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .frame(maxWidth: .infinity)

            Button {
                periodOffset = max(0, periodOffset - 1)
                report = .empty(period: period)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(periodOffset == 0)
            .opacity(periodOffset == 0 ? 0.35 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .gesture(periodSwipeGesture)
    }

    private var periodOffsetLabel: String {
        if periodOffset == 0 {
            switch period {
            case .day: return "วันนี้"
            case .week: return "สัปดาห์ล่าสุด"
            case .month: return "เดือนล่าสุด"
            }
        }
        switch period {
        case .day:
            return periodOffset == 1 ? "เมื่อวาน" : "ย้อนหลัง \(periodOffset) วัน"
        case .week:
            return "สัปดาห์ย้อนหลัง \(periodOffset)"
        case .month:
            return "เดือนย้อนหลัง \(periodOffset)"
        }
    }

    private var periodSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onEnded { value in
                if value.translation.width < -36, periodOffset < maxPeriodOffset {
                    periodOffset += 1
                    report = .empty(period: period)
                } else if value.translation.width > 36, periodOffset > 0 {
                    periodOffset -= 1
                    report = .empty(period: period)
                }
            }
    }

    private func shortDate(_ ymd: String) -> String {
        DashboardAggregations.dayLabel(ymd)
    }

    private var modeDetailLink: some View {
        NavigationLink {
            OpsTrendModeDetailView(focus: focus, report: report, proBundle: proBundle)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ดูรายละเอียดทั้งหมด")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Text("สถิติ · ราย\(period.usesDailyBuckets ? "วัน" : "สัปดาห์") · \(focus == .trip ? "อันดับรถ" : "ชั่วโมงพีค")")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .fill(AppTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero

    private var proHero: some View {
        NavigationLink {
            OpsTrendProScoreDetailView(focus: focus, report: report, mode: mode, card: card, accent: accent)
        } label: {
            proHeroContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("แตะเพื่อดูรายละเอียดคะแนน Pro")
    }

    private var proHeroContent: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(AppTheme.surfaceSoft, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(mode.combinedScore) / 100)
                    .stroke(
                        AngularGradient(colors: [accent.opacity(0.5), accent], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(mode.combinedScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Pro")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                Text("วิเคราะห์มืออาชีพ · \(report.period.label)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(rangeCaption)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                HStack(spacing: 8) {
                    proMiniBadge("เร็ว", mode.speedScore, Color(hex: "#16a34a"))
                    proMiniBadge("ปริมาณ", mode.volumeScore, AppTheme.warning)
                    paceChip(mode.pace, accent: accent)
                }
                Text("แตะดูรายละเอียดคะแนน Pro")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var rangeCaption: String {
        let cur = "\(shortDate(report.filter.start)) – \(shortDate(report.filter.end))"
        let prev = "\(shortDate(report.prevFilter.start)) – \(shortDate(report.prevFilter.end))"
        return "ช่วง \(cur) · เทียบ \(prev)"
    }

    // MARK: - KPIs

    private var executiveKPIs: some View {
        NavigationLink {
            OpsTrendMetricDetailView(card: card, advanced: mode, period: report.period, accent: accent)
        } label: {
            SectionCard("ตัวชี้วัดหลัก", systemImage: "gauge.with.dots.needle.67percent", subtitle: "แตะดูรายละเอียด") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    kpiTile("ปริมาณรวม", OpsTrendAnalytics.formatCompact(mode.volumeTotal), mode.unit)
                    kpiTile("เฉลี่ย/วัน", OpsTrendAnalytics.formatCompact(mode.volumeAvgPerDay), mode.unit)
                    kpiTile("อัตราผลิต", OpsTrendAnalytics.formatPerHour(mode.throughputPerHour), "")
                    kpiTile("จังหวะเฉลี่ย", OpsTrendAnalytics.formatIntervalSec(mode.avgIntervalSec), "")
                    kpiTile("ชม.ทำงาน", CountRecordAnalytics.formatDurationHours(mode.activeHoursTotal), "")
                    kpiTile(
                        "คิวรวม",
                        mode.cubicTotal > 0 ? OpsTrendAnalytics.formatCompact(mode.cubicTotal) : "—",
                        "คิว"
                    )
                    kpiTile("สูงสุด", OpsTrendAnalytics.formatCompact(mode.volumePeak), mode.volumePeakLabel)
                    kpiTile("เติบโต", OpsTrendAnalytics.formatSignedPct(card.changePct), "vs ก่อน")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func kpiTile(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.surfaceSoft))
    }

    // MARK: - Matrix

    private var performanceMatrix: some View {
        SectionCard("เมทริกซ์ประสิทธิภาพ", systemImage: "square.grid.3x3", subtitle: matrixLabel) {
            HStack(spacing: 12) {
                matrixQuadrant(title: "ความเร็ว", score: mode.speedScore, color: Color(hex: "#16a34a"))
                matrixQuadrant(title: "ปริมาณ", score: mode.volumeScore, color: AppTheme.warning)
            }
            HStack(spacing: 12) {
                deltaPill("ปริมาณ", mode.volumeChangePct)
                deltaPill("ความเร็ว", mode.speedChangePct)
                deltaPill("อัตรา/ชม.", mode.throughputChangePct)
            }
            if let peak = mode.peakHourLabel, !peak.isEmpty {
                Label("ชั่วโมงพีค \(peak)", systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    private var matrixLabel: String {
        if mode.speedScore >= 70 && mode.volumeScore >= 70 { return "จังหวะดี + ปริมาณแข็ง — รักษาระดับ" }
        if mode.speedScore < 55 && mode.volumeScore >= 70 { return "ปริมาณดีแต่จังหวะช้า — ไล่รอบห่าง" }
        if mode.speedScore >= 70 && mode.volumeScore < 55 { return "เร็วแต่ปริมาณยังไม่ถึง — อัดชั่วโมงพีค" }
        return "ต้องเร่งทั้งความเร็วและปริมาณ"
    }

    private func matrixQuadrant(title: String, score: Int, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(score)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.surfaceSoft)
                    Capsule().fill(color.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
    }

    // MARK: - Daily table

    private var dailyPerformanceCard: some View {
        SectionCard(
            report.period.usesDailyBuckets ? "ผลรายวัน" : "ผลรายสัปดาห์ย่อย",
            systemImage: "calendar",
            subtitle: "แตะวันเพื่อดูรายละเอียด"
        ) {
            let sorted = proBundle.dayPerformance.sorted { $0.score > $1.score }
            ForEach(sorted) { day in
                NavigationLink {
                    OpsTrendProDayDetailView(
                        day: day,
                        focus: focus,
                        mode: mode,
                        point: matchingPoint(for: day)
                    )
                } label: {
                    HStack(spacing: 10) {
                        Text(day.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 36, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(day.rounds) \(mode.unit)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            HStack(spacing: 8) {
                                Text(OpsTrendAnalytics.formatPerHour(day.perHour))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                                if let sec = day.intervalSec {
                                    Text(OpsTrendAnalytics.formatIntervalSec(sec))
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.inkMuted)
                                }
                            }
                        }
                        Spacer()
                        Text("\(day.score)")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(dayScoreColor(day.score))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                if day.id != sorted.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func matchingPoint(for day: OpsTrendDayPerformance) -> OpsTrendPoint? {
        report.dailyPoints.first { $0.id == day.id || $0.startKey == day.dateKey || $0.label == day.label }
    }

    // MARK: - Charts

    private var throughputAndIntervalCharts: some View {
        SectionCard("\(mode.title) · กราฟ Pro", systemImage: "chart.xyaxis.line") {
            if !mode.seriesLabels.isEmpty {
                Text("อัตราผลิตต่อช่วง")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Chart {
                    ForEach(Array(mode.seriesLabels.enumerated()), id: \.offset) { i, label in
                        let v = i < mode.throughputSeries.count ? mode.throughputSeries[i] : 0
                        BarMark(x: .value("ช่วง", label), y: .value("ต่อชม.", v))
                            .foregroundStyle(accent.opacity(0.9))
                            .cornerRadius(3)
                    }
                }
                .frame(height: 140)

                Text("ปริมาณต่อช่วง")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 8)
                Chart {
                    ForEach(Array(mode.seriesLabels.enumerated()), id: \.offset) { i, label in
                        let v = i < mode.volumeSeries.count ? mode.volumeSeries[i] : 0
                        LineMark(x: .value("ช่วง", label), y: .value(mode.unit, v))
                            .foregroundStyle(accent)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("ช่วง", label), y: .value(mode.unit, v))
                            .foregroundStyle(accent.opacity(0.14))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 130)

                Text("จังหวะเฉลี่ย (วินาที)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 8)
                Chart {
                    ForEach(Array(mode.seriesLabels.enumerated()), id: \.offset) { i, label in
                        let v = i < mode.intervalSeries.count ? mode.intervalSeries[i] : 0
                        if v > 0 {
                            LineMark(x: .value("ช่วง", label), y: .value("วินาที", v))
                                .foregroundStyle(Color(hex: "#16a34a"))
                            PointMark(x: .value("ช่วง", label), y: .value("วินาที", v))
                                .foregroundStyle(Color(hex: "#16a34a"))
                        }
                    }
                }
                .frame(height: 120)
            } else {
                Text("ยังไม่มีข้อมูลกราฟในช่วงนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private var hourlyDistributionCard: some View {
        SectionCard("การกระจายตามชั่วโมง", systemImage: "clock.badge", subtitle: "รวมทุกวันในช่วง") {
            Chart(proBundle.hourlyBuckets) { bucket in
                BarMark(x: .value("ชม.", bucket.label), y: .value("รอบ", bucket.count))
                    .foregroundStyle(accent.opacity(0.85))
                    .cornerRadius(2)
            }
            .frame(height: 160)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                    AxisValueLabel().foregroundStyle(AppTheme.inkMuted)
                }
            }
        }
    }

    // MARK: - Vehicles

    private var vehicleLeaderboardCard: some View {
        SectionCard("อันดับรถในช่วง", systemImage: "truck.box.fill", subtitle: "แตะดูรายละเอียดรถ") {
            ForEach(proBundle.vehicleRanks) { row in
                NavigationLink {
                    OpsTrendProVehicleDetailView(vehicle: row, period: report.period)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            Text("\(row.rounds) เที่ยว · \(Int(row.sharePct.rounded()))%")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(OpsTrendAnalytics.formatPerHour(row.perHour))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.info)
                            if let sec = row.avgIntervalSec {
                                Text(OpsTrendAnalytics.formatIntervalSec(sec))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Insights

    private var proInsightsCard: some View {
        SectionCard("สรุปเชิงลึก Pro", systemImage: "text.book.closed.fill") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(proBundle.proInsights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.caption)
                            .foregroundStyle(accent)
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

    // MARK: - Data

    @MainActor
    private func rebuild() async {
        buildToken += 1
        let token = buildToken
        isBuilding = true
        let period = self.period
        let periodOffset = self.periodOffset
        let focus = self.focus
        let txs = appState.transactions
        let byDay = appState.transactionsByDay
        let emps = appState.employees

        let built = await Task.detached(priority: .userInitiated) {
            OpsTrendAnalytics.build(
                period: period,
                periodOffset: periodOffset,
                transactions: txs,
                employees: emps,
                byDay: byDay
            )
        }.value

        let bundle = await Task.detached(priority: .userInitiated) {
            let mode = focus == .sand ? built.sandAdvanced : built.tripAdvanced
            return OpsTrendAnalytics.buildProBundle(
                focus: focus,
                period: period,
                filter: built.filter,
                pacePoints: built.pacePoints,
                daily: built.dailyPoints,
                mode: mode,
                transactions: txs,
                employees: emps,
                byDay: byDay
            )
        }.value

        guard token == buildToken else { return }
        withAnimation(.snappy(duration: 0.25)) {
            report = built
            proBundle = bundle
            isBuilding = false
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
            .fill(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
    }

    private func proMiniBadge(_ title: String, _ score: Int, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(score)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }

    private func paceChip(_ pace: OpsTrendPace, accent: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: pace.systemImage).font(.caption2.weight(.bold))
            Text(pace.label).font(.caption2.weight(.bold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(accent.opacity(0.12)))
    }

    private func deltaPill(_ title: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.inkMuted)
            Text(OpsTrendAnalytics.formatSignedPct(pct))
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor(pct))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.surfaceSoft))
    }

    private func deltaColor(_ pct: Double?) -> Color {
        guard let pct else { return AppTheme.inkMuted }
        if pct > 1 { return Color(hex: "#16a34a") }
        if pct < -1 { return Color(hex: "#dc2626") }
        return AppTheme.inkMuted
    }

    private func dayScoreColor(_ score: Int) -> Color {
        if score >= 80 { return Color(hex: "#16a34a") }
        if score >= 60 { return AppTheme.brand }
        if score >= 45 { return AppTheme.warning }
        return Color(hex: "#dc2626")
    }
}
