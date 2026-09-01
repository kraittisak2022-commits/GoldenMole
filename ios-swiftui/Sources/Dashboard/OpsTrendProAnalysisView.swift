import Charts
import SwiftUI

/// Full-screen professional analytics for trip or sand (weekly / monthly).
struct OpsTrendProAnalysisView: View {
    let focus: OpsTrendFocus
    let report: OpsTrendReport
    let proBundle: OpsTrendProBundle

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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(DashboardBackground())
        .navigationTitle("Pro · \(focus.label)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var proHero: some View {
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
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var rangeCaption: String {
        let cur = "\(DashboardAggregations.dayLabel(report.filter.start)) – \(DashboardAggregations.dayLabel(report.filter.end))"
        let prev = "\(DashboardAggregations.dayLabel(report.prevFilter.start)) – \(DashboardAggregations.dayLabel(report.prevFilter.end))"
        return "ช่วง \(cur) · เทียบ \(prev)"
    }

    // MARK: - KPIs

    private var executiveKPIs: some View {
        SectionCard("ตัวชี้วัดหลัก", systemImage: "gauge.with.dots.needle.67percent", subtitle: "สรุปผล Pro") {
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
            report.period == .week ? "ผลรายวัน" : "ผลรายสัปดาห์ย่อย",
            systemImage: "calendar",
            subtitle: "เรียงตามคะแนน Pro"
        ) {
            let sorted = proBundle.dayPerformance.sorted { $0.score > $1.score }
            ForEach(sorted) { day in
                HStack(spacing: 10) {
                    Text(day.label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 36, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(day.rounds) \(mode.unit)")
                            .font(.subheadline.weight(.semibold))
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
                }
                .padding(.vertical, 6)
                if day.id != sorted.last?.id {
                    Divider().opacity(0.3)
                }
            }
        }
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
        SectionCard("อันดับรถในช่วง", systemImage: "truck.box.fill", subtitle: "จากเที่ยวจริง") {
            ForEach(proBundle.vehicleRanks) { row in
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
                }
                .padding(.vertical, 4)
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
