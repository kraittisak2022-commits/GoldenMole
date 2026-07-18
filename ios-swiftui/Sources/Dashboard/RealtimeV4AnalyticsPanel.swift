import Charts
import SwiftUI

struct RealtimeV4AnalyticsPanel: View {
    let analytics: CountRecordAnalytics.ModeAnalytics
    var accent: Color = AppTheme.info

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("วิเคราะห์จังหวะ")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("หักพักเที่ยง 12:00–13:00 น.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                PillBadge(text: analytics.unitLabel, color: accent)
            }

            if analytics.rounds == 0 {
                Text("ยังไม่มีข้อมูลวิเคราะห์")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                statTiles
                bentoGrid
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }

    // MARK: - Stat tiles

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tileCard(title: "จังหวะเฉลี่ย", value: CountRecordAnalytics.formatPace(analytics.stats.avg)) {
                sparkline
            }
            tileCard(
                title: "Pace vs \(analytics.comparison.priorLabel.isEmpty ? "วันก่อน" : analytics.comparison.priorLabel)",
                value: CountRecordAnalytics.formatDeltaPct(analytics.comparison.paceDeltaPct)
            ) {
                Text(paceHint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            tileCard(
                title: "ยอดรวม",
                value: "\(analytics.rounds) \(analytics.unitLabel)"
            ) {
                Text(roundsHint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            tileCard(
                title: "เวลาทำงาน",
                value: CountRecordAnalytics.formatDurationHours(analytics.workDuration?.totalActiveHours ?? 0)
            ) {
                workRing
            }
        }
    }

    private var paceHint: String {
        guard let pct = analytics.comparison.paceDeltaPct else {
            return analytics.comparison.hasYesterdayData ? "ไม่มีข้อมูลจังหวะ" : "ไม่มีข้อมูลเปรียบเทียบ"
        }
        let label = analytics.comparison.priorLabel.isEmpty ? "วันก่อน" : analytics.comparison.priorLabel
        if abs(pct) < 1 { return "เท่า\(label)" }
        return pct < 0 ? "เร็วกว่า\(label)" : "ช้ากว่า\(label)"
    }

    private var roundsHint: String {
        guard analytics.comparison.hasYesterdayData else { return "เทียบวันก่อนไม่ได้" }
        let prior = analytics.comparison.yesterdayRounds
        let delta = CountRecordAnalytics.formatDeltaPct(analytics.comparison.roundsDeltaPct)
        return "\(analytics.comparison.priorLabel): \(prior) · \(delta)"
    }

    private func tileCard<Content: View>(
        title: String,
        value: String,
        @ViewBuilder footer: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            footer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }

    @ViewBuilder
    private var sparkline: some View {
        if analytics.sparkline.count >= 2 {
            Chart(Array(analytics.sparkline.enumerated()), id: \.offset) { item in
                LineMark(
                    x: .value("i", item.offset),
                    y: .value("sec", item.element)
                )
                .foregroundStyle(accent)
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 28)
        } else {
            Text("รอบล่าสุด: \(CountRecordAnalytics.formatPace(analytics.stats.last))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var workRing: some View {
        let hours = analytics.workDuration?.totalActiveHours ?? 0
        let progress = min(hours / CountRecordAnalytics.workHoursTarget, 1)
        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 28, height: 28)
            Text("เป้า 8 ชม.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - Bento

    private var bentoGrid: some View {
        VStack(spacing: 10) {
            periodSplitCard
            if let peak = analytics.peak {
                peakCard(peak)
            }
            heatmapCard
            if !analytics.cumulative.isEmpty {
                cumulativeCard
            }
            if !analytics.hourly.isEmpty {
                hourlyCard
            }
            if analytics.mode == .trip && !analytics.vehicleComparison.isEmpty {
                vehicleCompareCard
            }
            if analytics.mode == .sand {
                if let eta = analytics.eta {
                    etaCard(eta)
                }
                if let consistency = analytics.consistency {
                    consistencyCard(consistency)
                }
                if !analytics.minuteSpeed.isEmpty {
                    minuteSpeedCard
                }
            }
        }
    }

    private var periodSplitCard: some View {
        bentoShell(title: "สัดส่วนเช้า / บ่าย") {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#38BDF8"))
                        .frame(width: max(geo.size.width * analytics.periodSplit.morningPct / 100, analytics.periodSplit.morning > 0 ? 8 : 0))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "#F472B6"))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 14)
            HStack {
                Text("เช้า \(analytics.periodSplit.morning) (\(Int(analytics.periodSplit.morningPct.rounded()))%)")
                    .foregroundStyle(Color(hex: "#7DD3FC"))
                Spacer()
                Text("บ่าย \(analytics.periodSplit.afternoon) (\(Int(analytics.periodSplit.afternoonPct.rounded()))%)")
                    .foregroundStyle(Color(hex: "#F9A8D4"))
            }
            .font(.caption2.weight(.semibold))
        }
    }

    private func peakCard(_ peak: CountRecordAnalytics.PeakHourInfo) -> some View {
        bentoShell(title: "ช่วงพีค (รายชั่วโมง)") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(peak.label)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(peak.count) \(analytics.unitLabel)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private var heatmapCard: some View {
        bentoShell(title: "Heatmap รายชั่วโมง") {
            HStack(spacing: 2) {
                ForEach(analytics.heatmap) { cell in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cell.isLunch
                              ? Color.white.opacity(0.08)
                              : accent.opacity(0.15 + cell.intensity * 0.85))
                        .frame(height: 22)
                        .overlay {
                            if cell.isLunch {
                                Text("/")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                }
            }
            HStack {
                Text("00")
                Spacer()
                Text("12")
                Spacer()
                Text("23")
            }
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var cumulativeCard: some View {
        bentoShell(title: "ยอดสะสมตามเวลา") {
            Chart(analytics.cumulative) { p in
                LineMark(x: .value("เวลา", p.label), y: .value("ยอด", p.value))
                    .foregroundStyle(accent)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("เวลา", p.label), y: .value("ยอด", p.value))
                    .foregroundStyle(accent.opacity(0.18))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(height: 120)
        }
    }

    private var hourlyCard: some View {
        bentoShell(title: "จำนวนต่อชั่วโมง") {
            Chart(analytics.hourly) { b in
                BarMark(x: .value("ชม.", b.label), y: .value("จำนวน", b.count))
                    .foregroundStyle(accent.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(height: 120)
        }
    }

    private var vehicleCompareCard: some View {
        bentoShell(title: "เปรียบเทียบคัน") {
            VStack(spacing: 8) {
                ForEach(analytics.vehicleComparison.prefix(6)) { row in
                    let maxR = max(analytics.vehicleComparison.first?.rounds ?? 1, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.vehicleId)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(row.rounds)")
                                .font(.caption.bold())
                                .foregroundStyle(accent)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(accent.opacity(0.85))
                                .frame(width: geo.size.width * CGFloat(row.rounds) / CGFloat(maxR), height: 6)
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    private func etaCard(_ eta: CountRecordAnalytics.SandTargetEta) -> some View {
        bentoShell(title: "คาดการณ์ถึงเป้า") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: eta.progressPct, total: 100)
                    .tint(AppTheme.sand)
                HStack {
                    Text("\(eta.rounds) / \(eta.target) รอบ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if eta.reached {
                        Text("ถึงเป้าแล้ว")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.income)
                    } else if let clock = eta.etaClock {
                        Text("ETA \(clock)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.warning)
                    } else {
                        Text("คำนวณไม่ได้")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                if let hours = eta.hoursLeft, !eta.reached {
                    Text("เหลือ \(eta.remaining) รอบ · ~\(CountRecordAnalytics.formatDurationHours(hours))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private func consistencyCard(_ c: CountRecordAnalytics.PaceConsistency) -> some View {
        bentoShell(title: "ความสม่ำเสมอของจังหวะ") {
            HStack {
                Text("\(Int(c.pctInBand.rounded()))%")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("อยู่ในช่วง ±25% ของค่ามัธยฐาน")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("มัธยฐาน \(CountRecordAnalytics.formatPace(c.medianSec)) · \(c.sampleSize) ช่วง")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
        }
    }

    private var minuteSpeedCard: some View {
        let points = Array(analytics.minuteSpeed.suffix(40))
        return bentoShell(title: "Timeline ความเร็วร่อนต่อนาที") {
            Chart(Array(points.enumerated()), id: \.offset) { item in
                BarMark(
                    x: .value("นาที", item.element.label),
                    y: .value("รอบ", item.element.count)
                )
                .foregroundStyle(AppTheme.sand.opacity(0.85))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(height: 90)
        }
    }

    private func bentoShell<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.7))
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
    }
}

// MARK: - Activity feed

struct RealtimeV4ActivityFeed: View {
    let events: [CountRecordAnalytics.ActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AppTheme.warning)
                Text("อัปเดตล่าสุดจากมือถือ")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if events.isEmpty {
                Text("ยังไม่มีเหตุการณ์วันนี้")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(event.kind == .trip ? AppTheme.info : AppTheme.sand)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(event.stamp)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Text(event.kind == .trip ? "เที่ยว" : "ทราย")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(event.kind == .trip ? AppTheme.info : AppTheme.sand)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
    }
}
