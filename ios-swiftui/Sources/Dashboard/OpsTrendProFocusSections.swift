import Charts
import SwiftUI

/// Pro analytics sections inlined on the unified analytics hub (trip / sand focus).
struct OpsTrendProFocusSections: View {
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
        VStack(alignment: .leading, spacing: 16) {
            performanceMatrix
            if !proBundle.dayPerformance.isEmpty {
                dailyPerformanceCard
            }
            if !proBundle.hourlyBuckets.isEmpty {
                hourlyDistributionCard
            }
            if focus == .trip, !proBundle.vehicleRanks.isEmpty {
                vehicleLeaderboardCard
            }
            if !proBundle.proInsights.isEmpty {
                proInsightsCard
            }
        }
    }

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

    private var hourlyDistributionCard: some View {
        SectionCard("การกระจายตามชั่วโมง", systemImage: "clock.badge", subtitle: "แตะแท่งเพื่อดูจำนวนรอบ") {
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

    private var proInsightsCard: some View {
        SectionCard("สรุปเชิงลึก", systemImage: "text.book.closed.fill") {
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

    private func matchingPoint(for day: OpsTrendDayPerformance) -> OpsTrendPoint? {
        report.dailyPoints.first { $0.id == day.id || $0.startKey == day.dateKey || $0.label == day.label }
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
