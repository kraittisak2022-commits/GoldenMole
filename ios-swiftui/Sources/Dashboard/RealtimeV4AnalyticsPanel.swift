import Charts
import SwiftUI

struct RealtimeV4AnalyticsPanel: View {
    let analytics: CountRecordAnalytics.ModeAnalytics
    var accent: Color = AppTheme.info
    @State private var showDetail = false
    /// Charts stay off-screen by default — mounting 6–8 Chart views while scrolling caused freezes.
    @State private var showCharts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                guard analytics.rounds > 0 else { return }
                showDetail = true
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("วิเคราะห์จังหวะ")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text("หักพักเที่ยง 12:00–13:00 น.")
                            .font(.caption2)
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    }
                    Spacer()
                    PillBadge(text: analytics.unitLabel, color: accent)
                    if analytics.rounds > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.inkFaint)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(analytics.rounds > 0 ? "แตะเพื่อดูรายละเอียดจังหวะ" : "")

            if analytics.rounds == 0 {
                Text("ยังไม่มีข้อมูลวิเคราะห์")
                    .font(.caption)
                    .foregroundStyle(RealtimeV4Palette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                statTiles
                // Charts are expensive during scroll — keep collapsed until the user expands
                // or opens the detail sheet (full charts live there via PaceDetailSheet).
                if showCharts {
                    bentoGrid
                }
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        showCharts.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCharts ? "chevron.up" : "chart.xyaxis.line")
                            .font(.caption.weight(.bold))
                        Text(showCharts ? "ซ่อนกราฟวิเคราะห์" : "แสดงกราฟวิเคราะห์")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RealtimeV4Palette.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(RealtimeV4Palette.border)
        )
        .sheet(isPresented: $showDetail) {
            PaceDetailSheet(analytics: analytics, accent: accent)
        }
    }

    // MARK: - Stat tiles

    private var priorLabel: String {
        analytics.comparison.priorLabel.isEmpty ? "วันก่อน" : analytics.comparison.priorLabel
    }

    private var statTiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("สรุปจังหวะการทำงาน")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(RealtimeV4Palette.inkFaint)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                avgPaceTile
                paceDeltaTile
                totalRoundsTile
                workTimeTile
            }
        }
    }

    private var avgPaceTile: some View {
        statTileShell(gradient: [accent, Color(hex: "#0F172A")]) {
            VStack(alignment: .leading, spacing: 6) {
                tileLabel("จังหวะเฉลี่ย", icon: "timer")
                Text(CountRecordAnalytics.formatPace(analytics.stats.avg))
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                sparkline
                if let last = analytics.stats.last {
                    Text("ล่าสุด \(CountRecordAnalytics.formatPace(last))")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
        }
    }

    private var paceDeltaTile: some View {
        statTileShell(gradient: [Color(hex: "#1E293B"), Color(hex: "#020617")]) {
            VStack(spacing: 4) {
                tileLabel("Pace vs \(priorLabel)", icon: "chart.line.downtrend.xyaxis")
                    .frame(maxWidth: .infinity, alignment: .leading)
                PaceGaugeView(pct: analytics.comparison.paceDeltaPct)
                Text(paceHint)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var totalRoundsTile: some View {
        statTileShell(gradient: [Color(hex: "#312E81"), Color(hex: "#020617")]) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    tileLabel("ยอดรวม", icon: "chart.bar.fill")
                    Spacer(minLength: 0)
                    if let d = analytics.comparison.roundsDeltaPct {
                        let r = Int(d.rounded())
                        Text("\(r > 0 ? "+" : "")\(r)%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(r > 0 ? Color(hex: "#6EE7B7") : (r < 0 ? Color(hex: "#FDA4AF") : .white.opacity(0.6)))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill((r > 0 ? Color(hex: "#10B981") : (r < 0 ? Color(hex: "#F43F5E") : Color.white)).opacity(0.18))
                            )
                    }
                }
                CompareBarsView(
                    today: analytics.comparison.todayRounds,
                    prior: analytics.comparison.yesterdayRounds,
                    accent: accent,
                    priorLabel: priorLabel
                )
            }
        }
    }

    private var workTimeTile: some View {
        let hours = analytics.workDuration?.totalActiveHours ?? 0
        let progress = min(hours / CountRecordAnalytics.workHoursTarget, 1)
        let ringColor = analytics.mode == .sand ? Color(hex: "#F9A8D4") : Color(hex: "#93C5FD")
        return statTileShell(
            gradient: analytics.mode == .sand
                ? [Color(hex: "#BE185D"), Color(hex: "#0F172A")]
                : [accent, Color(hex: "#0F172A")]
        ) {
            VStack(alignment: .leading, spacing: 6) {
                tileLabel("เวลาทำงาน", icon: "clock.fill")
                HStack(spacing: 8) {
                    WorkRingView(progress: progress, color: ringColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CountRecordAnalytics.formatDurationHours(hours))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("เป้า 8 ชม.")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                        if let s = analytics.workDuration?.startClock, let e = analytics.workDuration?.endClock {
                            Text("\(s) – \(e)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var paceHint: String {
        guard let pct = analytics.comparison.paceDeltaPct else {
            return analytics.comparison.hasYesterdayData ? "ไม่มีข้อมูลจังหวะ" : "ไม่มีข้อมูลเปรียบเทียบ"
        }
        if abs(pct) < 1 { return "เท่า\(priorLabel)" }
        return pct < 0 ? "เร็วกว่า\(priorLabel)" : "ช้ากว่า\(priorLabel)"
    }

    private func statTileShell<Content: View>(
        gradient: [Color],
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func tileLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
        }
        .foregroundStyle(.white.opacity(0.7))
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    @ViewBuilder
    private var sparkline: some View {
        if analytics.sparkline.count >= 2 {
            // Lightweight bars — avoid Swift Charts on the scroll path (Charts caused scroll freezes).
            GeometryReader { geo in
                let values = analytics.sparkline
                let maxV = max(values.max() ?? 1, 1)
                let barW = max(2, (geo.size.width - CGFloat(values.count - 1) * 2) / CGFloat(values.count))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(hex: "#FDE047").opacity(0.85))
                            .frame(width: barW, height: max(2, geo.size.height * CGFloat(v / maxV)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 26)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.08))
                .frame(height: 26)
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
        let split = analytics.periodSplit
        return bentoShell(title: "สัดส่วนเช้า / บ่าย") {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color(hex: "#FBBF24"), Color(hex: "#F59E0B")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * split.morningPct / 100, split.morning > 0 ? 8 : 0))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color(hex: "#6366F1"), Color(hex: "#7C3AED")], startPoint: .leading, endPoint: .trailing))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 28)

            HStack(spacing: 8) {
                periodSplitStat(
                    label: "เช้า",
                    value: split.morning,
                    pct: split.morningPct,
                    fg: Color(light: Color(hex: "#B45309"), dark: Color(hex: "#FCD34D")),
                    bg: Color(hex: "#F59E0B").opacity(0.14)
                )
                periodSplitStat(
                    label: "บ่าย",
                    value: split.afternoon,
                    pct: split.afternoonPct,
                    fg: Color(light: Color(hex: "#4338CA"), dark: Color(hex: "#C7D2FE")),
                    bg: Color(hex: "#6366F1").opacity(0.16)
                )
            }
        }
    }

    private func periodSplitStat(label: String, value: Int, pct: Double, fg: Color, bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(fg.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Text(analytics.unitLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
            }
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(fg.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(bg))
    }

    private func peakCard(_ peak: CountRecordAnalytics.PeakHourInfo) -> some View {
        bentoShell(title: "ช่วงพีค (รายชั่วโมง)") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(peak.label)
                        .font(.title3.bold())
                        .foregroundStyle(RealtimeV4Palette.ink)
                    Text("\(peak.count) \(analytics.unitLabel)")
                        .font(.caption)
                        .foregroundStyle(RealtimeV4Palette.inkSecondary)
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
                              ? RealtimeV4Palette.cardSoft
                              : accent.opacity(0.15 + cell.intensity * 0.85))
                        .frame(height: 22)
                        .overlay {
                            if cell.isLunch {
                                Text("/")
                                    .font(.system(size: 7))
                                    .foregroundStyle(RealtimeV4Palette.inkFaint)
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
            .foregroundStyle(RealtimeV4Palette.inkFaint)
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
                    AxisValueLabel().foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(RealtimeV4Palette.inkFaint)
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
                    AxisValueLabel().foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(RealtimeV4Palette.inkFaint)
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
                                .foregroundStyle(RealtimeV4Palette.ink)
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
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eta.reached ? "ถึงเป้าแล้ว" : "เหลืออีก \(CountRecordLogic.formatMetric(eta.remaining)) รอบ")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(CountRecordLogic.formatMetric(eta.rounds))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(RealtimeV4Palette.ink)
                            Text("/ \(CountRecordLogic.formatMetric(eta.target))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                        }
                    }
                    Spacer()
                    Text("\(Int(eta.progressPct.rounded()))%")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(eta.reached ? AppTheme.income : Color(hex: "#F472B6"))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(RealtimeV4Palette.cardSoft)
                        Capsule()
                            .fill(eta.reached ? AppTheme.income : Color(hex: "#EC4899"))
                            .frame(width: geo.size.width * CGFloat(min(eta.progressPct / 100, 1)))
                    }
                }
                .frame(height: 8)
                if eta.reached {
                    Text("ถึงเป้าแล้ว")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.income)
                } else if let clock = eta.etaClock {
                    Text("คาดถึงเป้าเวลา \(clock)" + (eta.hoursLeft.map { " · ~\(CountRecordAnalytics.formatDurationHours($0))" } ?? ""))
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                } else {
                    Text("ต้องมีอย่างน้อย 2 รอบเพื่อคำนวณ")
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
        }
    }

    private func consistencyCard(_ c: CountRecordAnalytics.PaceConsistency) -> some View {
        bentoShell(title: "ความสม่ำเสมอของจังหวะ") {
            HStack {
                Text("\(Int(c.pctInBand.rounded()))%")
                    .font(.title2.bold())
                    .foregroundStyle(RealtimeV4Palette.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("อยู่ในช่วง ±25% ของค่ามัธยฐาน")
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                    Text("มัธยฐาน \(CountRecordAnalytics.formatPace(c.medianSec)) · \(c.sampleSize) ช่วง")
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
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
                    AxisValueLabel().foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
            .frame(height: 90)
        }
    }

    private func bentoShell<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.inkSecondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(RealtimeV4Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RealtimeV4Palette.border, lineWidth: 1)
        )
    }
}

// MARK: - Stat tile visualizations

/// Semicircular gauge for pace-vs-prior-day delta (matches web PaceGauge).
private struct PaceGaugeView: View {
    let pct: Double?

    var body: some View {
        let faster: Bool? = {
            guard let pct else { return nil }
            if pct < -0.5 { return true }
            if pct > 0.5 { return false }
            return nil
        }()
        let color = faster == true ? Color(hex: "#34D399") : (faster == false ? Color(hex: "#FBBF24") : Color(hex: "#94A3B8"))
        let absPct = pct != nil ? min(Int(abs(pct!).rounded()), 100) : 0
        let trim = Double(absPct) / 100.0
        let icon = faster == true ? "arrow.down.right" : (faster == false ? "arrow.up.right" : "minus")

        return VStack(spacing: 2) {
            // Top-dome arc: Circle trim 0.5→1.0 spans left → top → right.
            ZStack {
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0.5, to: 0.5 + 0.5 * trim)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            .frame(width: 58, height: 58)
            .frame(height: 32, alignment: .top)
            .clipped()

            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(pct != nil ? "\(absPct)%" : "—")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            .foregroundStyle(color)
        }
    }
}

/// Circular progress ring showing % toward the 8h work target.
private struct WorkRingView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((max(0, min(progress, 1)) * 100).rounded()))%")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 44, height: 44)
    }
}

/// Today-vs-prior-day comparison bars (matches web CompareBars).
private struct CompareBarsView: View {
    let today: Int
    let prior: Int
    let accent: Color
    let priorLabel: String

    var body: some View {
        let maxV = Double(max(today, prior, 1))
        return VStack(spacing: 6) {
            bar(label: "วันนี้", value: today, frac: Double(today) / maxV, fill: accent, valueColor: .white)
            bar(label: priorLabel, value: prior, frac: Double(prior) / maxV, fill: Color.white.opacity(0.3), valueColor: .white.opacity(0.6))
        }
    }

    private func bar(label: String, value: Int, frac: Double, fill: Color, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(value)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.25))
                    Capsule().fill(fill).frame(width: geo.size.width * CGFloat(max(0, min(frac, 1))))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Activity feed

struct RealtimeV4ActivityFeed: View {
    let events: [CountRecordAnalytics.ActivityEvent]
    @State private var showAll = false

    private var previewEvents: [CountRecordAnalytics.ActivityEvent] {
        Array(events.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(AppTheme.warning)
                Text("อัปเดตล่าสุดจากมือถือ")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Spacer()
                Text("\(events.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.inkMuted)
            }

            if events.isEmpty {
                Text("ยังไม่มีเหตุการณ์วันนี้")
                    .font(.caption)
                    .foregroundStyle(RealtimeV4Palette.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(previewEvents) { event in
                    activityRow(event)
                }
                if events.count > 4 {
                    Button {
                        showAll = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("ดูเพิ่มเติม (\(events.count - 4))")
                                .font(.caption.weight(.bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(AppTheme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.brand.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RealtimeV4Palette.cardSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(RealtimeV4Palette.border)
        )
        .sheet(isPresented: $showAll) {
            ActivityFeedSheet(events: events)
        }
    }

    @ViewBuilder
    private func activityRow(_ event: CountRecordAnalytics.ActivityEvent) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.kind == .trip ? AppTheme.info : AppTheme.sand)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Text(event.stamp)
                    .font(.caption2)
                    .foregroundStyle(RealtimeV4Palette.inkFaint)
            }
            Spacer()
            Text(event.kind == .trip ? "เที่ยว" : "ทราย")
                .font(.caption2.weight(.bold))
                .foregroundStyle(event.kind == .trip ? AppTheme.info : AppTheme.sand)
        }
        .padding(.vertical, 4)
    }
}

private struct ActivityFeedSheet: View {
    let events: [CountRecordAnalytics.ActivityEvent]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(event.kind == .trip ? AppTheme.info : AppTheme.sand)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RealtimeV4Palette.ink)
                                Text(event.stamp)
                                    .font(.caption)
                                    .foregroundStyle(RealtimeV4Palette.inkFaint)
                            }
                            Spacer()
                            Text(event.kind == .trip ? "เที่ยว" : "ทราย")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(event.kind == .trip ? AppTheme.info : AppTheme.sand)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                        Divider().overlay(RealtimeV4Palette.border)
                    }
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("อัปเดตล่าสุดจากมือถือ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Pace detail sheet

private struct PaceDetailSheet: View {
    let analytics: CountRecordAnalytics.ModeAnalytics
    var accent: Color = AppTheme.info
    @Environment(\.dismiss) private var dismiss

    private var priorLabel: String {
        analytics.comparison.priorLabel.isEmpty ? "วันก่อน" : analytics.comparison.priorLabel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(analytics.rounds)")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text(analytics.unitLabel)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.inkSecondary)
                        Spacer()
                        PillBadge(text: analytics.mode == .trip ? "เที่ยวรถ" : "ร่อนทราย", color: accent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("สถิติจังหวะ")
                        DetailStatRow(items: [
                            ("เฉลี่ย", CountRecordAnalytics.formatPace(analytics.stats.avg)),
                            ("มัธยฐาน", CountRecordAnalytics.formatPace(analytics.stats.median)),
                            ("ล่าสุด", CountRecordAnalytics.formatPace(analytics.stats.last))
                        ])
                        DetailStatRow(items: [
                            ("เร็วสุด", CountRecordAnalytics.formatPace(analytics.stats.min)),
                            ("ช้าสุด", CountRecordAnalytics.formatPace(analytics.stats.max)),
                            ("รอบ", "\(analytics.rounds)")
                        ])
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("เทียบ\(priorLabel)")
                        DetailStatRow(items: [
                            ("วันนี้", "\(analytics.comparison.todayRounds)"),
                            (priorLabel, "\(analytics.comparison.yesterdayRounds)"),
                            ("ยอด", CountRecordAnalytics.formatDeltaPct(analytics.comparison.roundsDeltaPct))
                        ])
                        DetailStatRow(items: [
                            ("จังหวะวันนี้", CountRecordAnalytics.formatPace(analytics.comparison.todayAvgSec)),
                            ("จังหวะ\(priorLabel)", CountRecordAnalytics.formatPace(analytics.comparison.yesterdayAvgSec)),
                            ("Pace", CountRecordAnalytics.formatDeltaPct(analytics.comparison.paceDeltaPct))
                        ])
                    }

                    if let work = analytics.workDuration {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("เวลาทำงาน")
                            DetailStatRow(items: [
                                ("เริ่ม", work.startClock ?? "—"),
                                ("เลิก", work.endClock ?? "—"),
                                ("สุทธิ", CountRecordAnalytics.formatDurationHours(work.totalActiveHours))
                            ])
                            if work.lunchDeductedHours > 0 {
                                Text("หักพักเที่ยง \(CountRecordAnalytics.formatDurationHours(work.lunchDeductedHours))")
                                    .font(.caption)
                                    .foregroundStyle(RealtimeV4Palette.inkMuted)
                            }
                        }
                    }

                    if let consistency = analytics.consistency {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("ความสม่ำเสมอ")
                            DetailStatRow(items: [
                                ("ในแบนด์", String(format: "%.0f%%", consistency.pctInBand)),
                                ("มัธยฐาน", CountRecordAnalytics.formatPace(consistency.medianSec)),
                                ("ตัวอย่าง", "\(consistency.sampleSize)")
                            ])
                        }
                    }

                    if let peak = analytics.peak {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("ช่วงพีค")
                            DetailStatRow(items: [
                                ("ชั่วโมง", peak.label),
                                ("จำนวน", "\(peak.count)"),
                                ("หน่วย", analytics.unitLabel)
                            ])
                        }
                    }

                    LapTimeList(title: "เวลาประทับทุกรอบ", lapTimes: analytics.lapTimes)
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("รายละเอียดจังหวะ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(RealtimeV4Palette.inkMuted)
    }
}
