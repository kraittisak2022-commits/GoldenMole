import Charts
import SwiftUI

/// Weekly / monthly growth analytics for a locked focus (combined, trip, or sand).
struct OpsTrendAnalyticsHubView: View {
    let focus: OpsTrendFocus

    @Environment(AppState.self) private var appState
    @State private var period: OpsTrendPeriod = .week
    @State private var report: OpsTrendReport = .empty(period: .week)
    @State private var isBuilding = false
    @State private var buildToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                periodPicker
                if isBuilding && report.points.isEmpty {
                    ProgressView("กำลังวิเคราะห์…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    scoreHero
                    actionPlanCard
                    pillarBreakdown
                    growthScoreboard
                    bucketScoreCard
                    comparisonChartCard
                    cumulativeChartCard
                    periodCompareCard
                    if focus == .both {
                        dualBarsCard
                    }
                    if focus == .trip || focus == .both {
                        sessionSplitCard
                    }
                    advancedSection
                    detailCards
                    insightsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(DashboardBackground())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rebuildKey) {
            await rebuild()
        }
    }

    private var navigationTitle: String {
        switch focus {
        case .both: return "วิเคราะห์รวม"
        case .trip: return "วิเคราะห์เที่ยวรถ"
        case .sand: return "วิเคราะห์ร่อนทราย"
        }
    }

    private var rebuildKey: String {
        "\(period.rawValue)|\(appState.transactionsRevision)|\(appState.employees.count)"
    }

    // MARK: - Header / pickers

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(headerSubtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private var headerTitle: String {
        switch focus {
        case .both: return "ศูนย์วัดผลปฏิบัติการ"
        case .trip: return "วัดผลเที่ยวรถ"
        case .sand: return "วัดผลร่อนทราย"
        }
    }

    private var headerSubtitle: String {
        switch focus {
        case .both:
            return "จับจุดผิดปกติเร็ว · แนะทางเร่งยอด · \(rangeCaption)"
        case .trip:
            return "โฟกัสเฉพาะเที่ยวรถ · \(rangeCaption)"
        case .sand:
            return "โฟกัสเฉพาะร่อนทราย · \(rangeCaption)"
        }
    }

    private var rangeCaption: String {
        let cur = "\(shortDate(report.filter.start)) – \(shortDate(report.filter.end))"
        let prev = "\(shortDate(report.prevFilter.start)) – \(shortDate(report.prevFilter.end))"
        return "ช่วงนี้ \(cur)  ·  เทียบ \(prev)"
    }

    private func shortDate(_ ymd: String) -> String {
        DashboardAggregations.dayLabel(ymd)
    }

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

    // MARK: - Score hero

    @ViewBuilder
    private var scoreHero: some View {
        switch focus {
        case .both:
            combinedScoreHero
        case .trip:
            modeScoreHero(card: report.trip, mode: report.tripAdvanced, accent: AppTheme.info)
        case .sand:
            modeScoreHero(card: report.sand, mode: report.sandAdvanced, accent: AppTheme.brand)
        }
    }

    private var combinedScoreHero: some View {
        let sc = report.scorecard
        let accent = gradeColor(sc.grade)
        return HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceSoft, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(sc.score) / 100)
                    .stroke(
                        AngularGradient(colors: [accent.opacity(0.55), accent], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.45), value: sc.score)
                VStack(spacing: 2) {
                    Text("\(sc.score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                    Text(sc.grade.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                Text(sc.headline)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sc.subheadline)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        "\(OpsTrendAnalytics.formatSignedInt(sc.scoreDelta)) vs \(period.shortLabel)ก่อน",
                        systemImage: sc.scoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(sc.scoreDelta >= 0 ? Color(hex: "#16a34a") : Color(hex: "#dc2626"))

                    Text("\(report.activeDays)/\(report.coverageDays) วัน")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.surfaceSoft))
                }

                if report.streakDays > 0 {
                    Text("สตรีคทำงานต่อเนื่อง \(report.streakDays) วัน")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.brand)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func modeScoreHero(
        card: OpsTrendMetricCard,
        mode: OpsTrendAdvancedMode,
        accent: Color
    ) -> some View {
        let score = mode.combinedScore
        let delta = mode.throughputChangePct ?? mode.volumeChangePct
        return HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceSoft, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(
                        AngularGradient(colors: [accent.opacity(0.55), accent], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy(duration: 0.45), value: score)
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                    Text(card.title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 108, height: 108)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(card.title) · \(period.label)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(
                    "รวม \(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) · เฉลี่ย \(OpsTrendAnalytics.formatCompact(card.average))/วัน"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(
                        "\(OpsTrendAnalytics.formatSignedPct(delta)) vs \(period.shortLabel)ก่อน",
                        systemImage: (delta ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(deltaColor(delta))

                    Text("\(report.activeDays)/\(report.coverageDays) วัน")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.surfaceSoft))
                }

                if let attainment = card.targetAttainmentPct {
                    Text(String(format: "ถึงเป้า %.0f%%", attainment))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(attainment >= 100 ? Color(hex: "#16a34a") : AppTheme.warning)
                } else if mode.peakHourLabel != nil {
                    Text("ชั่วโมงพีค \(mode.peakHourLabel!)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLG, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Action plan / anomaly alerts

    private var actionPlanCard: some View {
        let plan = report.actionPlan
        let alerts = focusedAlerts(plan.alerts)
        let critical = alerts.filter { $0.severity == .critical }.count
        let warning = alerts.filter { $0.severity == .warning }.count
        let opportunity = alerts.filter { $0.severity == .opportunity }.count
        let health: String = {
            if focus == .both { return plan.healthLabel }
            if critical > 0 { return "ต้องเร่งแก้ \(critical) จุด" }
            if warning > 0 { return "เฝ้าระวัง \(warning) จุด" }
            if opportunity > 0 { return "พร้อมเร่งผลผลิต" }
            return plan.alerts.isEmpty ? plan.healthLabel : "จังหวะปกติสำหรับ\(focus.label)"
        }()

        return SectionCard(
            "สัญญาณที่ควรลงมือ",
            systemImage: "bell.badge.fill",
            subtitle: health
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    alertCountChip(count: critical, label: "เร่งแก้", color: Color(hex: "#dc2626"))
                    alertCountChip(count: warning, label: "เฝ้าระวัง", color: AppTheme.warning)
                    alertCountChip(count: opportunity, label: "โอกาส", color: Color(hex: "#16a34a"))
                    Spacer(minLength: 0)
                }

                if alerts.isEmpty {
                    Text("ยังไม่พบจุดผิดปกติในช่วงนี้ — รักษาระดับและดันเป้าต่อเนื่อง")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(alerts) { alert in
                        alertRow(alert)
                    }
                }

                if !plan.playbook.isEmpty, focus == .both {
                    Divider().opacity(0.35)
                    Text("คู่มือเร่งงาน")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    ForEach(Array(plan.playbook.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.brand)
                                .frame(width: 16, alignment: .leading)
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if focus != .both {
                    Divider().opacity(0.35)
                    Text("คู่มือเร่งงาน · \(focus.label)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    ForEach(Array(focusedPlaybook.enumerated()), id: \.offset) { idx, line in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.brand)
                                .frame(width: 16, alignment: .leading)
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private func focusedAlerts(_ alerts: [OpsTrendAlert]) -> [OpsTrendAlert] {
        switch focus {
        case .both:
            return alerts
        case .trip:
            return alerts.filter { $0.area != "ร่อนทราย" }
        case .sand:
            return alerts.filter { $0.area != "เที่ยวรถ" }
        }
    }

    private var focusedPlaybook: [String] {
        switch focus {
        case .both:
            return report.actionPlan.playbook
        case .trip:
            return [
                "เป้าเที่ยว \(OpsTrendAnalytics.formatCompact(period.tripDailyTarget))/วัน · เช้าให้แตะ ~\(OpsTrendAnalytics.formatCompact(period.tripDailyTarget * 0.45)) ก่อนเที่ยง",
                "ถ้าจังหวะช้า: ไล่รถที่รอบห่าง แล้วอัดชั่วโมงพีค",
                "รักษาสตรีควันทำงาน — วันว่างทำลายโมเมนตัมทั้ง\(period.shortLabel)",
                "ดันวันอ่อนให้ใกล้ค่าเฉลี่ย เพื่อลดความผันผวน",
            ]
        case .sand:
            return [
                "รักษาจังหวะร่อนต่อเนื่องหลังพักเที่ยง",
                "ถ้าอัตรา/ชม. ตก: เช็ควัตถุดิบเข้าเครื่องและความพร้อมคนประจำจุด",
                "ให้มีรอบร่อนคู่กับเที่ยวขนออก เพื่อไม่ให้กองค้าง",
                "รักษาสตรีควันทำงานทั้ง\(period.shortLabel)",
            ]
        }
    }

    private func alertCountChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private func alertRow(_ alert: OpsTrendAlert) -> some View {
        let color = severityColor(alert.severity)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: alert.severity.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(alert.severity.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                Text(alert.area)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppTheme.surfaceSoft))
                Spacer(minLength: 0)
            }
            Text(alert.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(alert.detail)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Label(alert.action, systemImage: "arrow.right.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.brand)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1)
        )
    }

    private func severityColor(_ severity: OpsTrendAlertSeverity) -> Color {
        switch severity {
        case .critical: return Color(hex: "#dc2626")
        case .warning: return AppTheme.warning
        case .opportunity: return Color(hex: "#16a34a")
        }
    }

    @ViewBuilder
    private var pillarBreakdown: some View {
        switch focus {
        case .both:
            combinedPillarBreakdown
        case .trip:
            modePillarBreakdown(card: report.trip, mode: report.tripAdvanced, accent: AppTheme.info)
        case .sand:
            modePillarBreakdown(card: report.sand, mode: report.sandAdvanced, accent: AppTheme.brand)
        }
    }

    private var combinedPillarBreakdown: some View {
        let sc = report.scorecard
        let pillars: [(String, Int, Color)] = [
            ("ปริมาณ", sc.volumeScore, AppTheme.info),
            ("เติบโต", sc.growthScore, Color(hex: "#16a34a")),
            ("ความนิ่ง", sc.consistencyScore, AppTheme.brand),
            ("ครอบคลุม", sc.coverageScore, AppTheme.warning),
            ("สมดุล", sc.balanceScore, Color(hex: "#7c3aed")),
        ]
        return SectionCard(
            "องค์ประกอบคะแนน",
            systemImage: "chart.bar.doc.horizontal",
            subtitle: "น้ำหนัก: ปริมาณ 30% · เติบโต 25% · นิ่ง 20% · ครอบคลุม 15% · สมดุล 10%"
        ) {
            VStack(spacing: 10) {
                ForEach(Array(pillars.enumerated()), id: \.offset) { _, item in
                    pillarRow(title: item.0, score: item.1, color: item.2)
                }
            }
        }
    }

    private func modePillarBreakdown(
        card: OpsTrendMetricCard,
        mode: OpsTrendAdvancedMode,
        accent: Color
    ) -> some View {
        let attainment = Int((card.targetAttainmentPct ?? Double(mode.volumeScore)).rounded())
        let pillars: [(String, Int, Color)] = [
            ("ความเร็ว", mode.speedScore, Color(hex: "#16a34a")),
            ("ปริมาณ", mode.volumeScore, AppTheme.warning),
            ("เติบโต", card.growthScore, accent),
            ("ความนิ่ง", card.consistencyScore, AppTheme.brand),
            ("ถึงเป้า", min(100, max(0, attainment)), AppTheme.info),
        ]
        return SectionCard(
            "องค์ประกอบคะแนน · \(card.title)",
            systemImage: "chart.bar.doc.horizontal",
            subtitle: "คะแนนเฉพาะ\(card.title)ในช่วงนี้"
        ) {
            VStack(spacing: 10) {
                ForEach(Array(pillars.enumerated()), id: \.offset) { _, item in
                    pillarRow(title: item.0, score: item.1, color: item.2)
                }
            }
        }
    }

    private func pillarRow(title: String, score: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("\(score)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.surfaceSoft)
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * CGFloat(score) / 100))
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: - Metric tiles

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
                Text("โต \(card.growthScore)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.14)))
            }

            if let attainment = card.targetAttainmentPct {
                Text(String(format: "ถึงเป้า %.0f%%", attainment))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(attainment >= 100 ? Color(hex: "#16a34a") : AppTheme.warning)
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

    // MARK: - Bucket scores (day or week)

    private var bucketScoreCard: some View {
        SectionCard(
            period == .week ? "คะแนนรายวัน" : "คะแนนรายสัปดาห์ย่อย",
            systemImage: "rosette",
            subtitle: period == .week ? "คะแนนแต่ละวันในสัปดาห์นี้" : "คะแนน W1–W4 ในรอบ 30 วัน"
        ) {
            if report.bucketScores.isEmpty {
                Text("ยังไม่มีคะแนนย่อย")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                Chart(report.bucketScores) { item in
                    BarMark(
                        x: .value("ช่วง", item.label),
                        y: .value("คะแนน", item.score)
                    )
                    .foregroundStyle(by: .value("s", "คะแนน"))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(["คะแนน": AppTheme.brand])
                .chartLegend(.hidden)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel().foregroundStyle(AppTheme.inkMuted)
                    }
                }
                .frame(height: 160)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(report.bucketScores) { item in
                            VStack(spacing: 4) {
                                Text(item.label)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text("\(item.score)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(AppTheme.ink)
                                switch focus {
                                case .both:
                                    Text("\(OpsTrendAnalytics.formatCompact(item.tripTotal))ท")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(AppTheme.info)
                                    Text("\(OpsTrendAnalytics.formatCompact(item.sandTotal))ร")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(AppTheme.brand)
                                case .trip:
                                    Text("\(OpsTrendAnalytics.formatCompact(item.tripTotal)) เที่ยว")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(AppTheme.info)
                                case .sand:
                                    Text("\(OpsTrendAnalytics.formatCompact(item.sandTotal)) รอบ")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(AppTheme.brand)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(AppTheme.surfaceSoft)
                            )
                        }
                    }
                }
            }
        }
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

    private var cumulativeChartCard: some View {
        let card = primaryCard
        let accent = accent(for: card)
        return SectionCard(
            focus == .both ? "ผลสะสมเที่ยวรถ" : "ผลสะสม \(card.title)",
            systemImage: "chart.line.uptrend.xyaxis",
            subtitle: "เส้นสะสมช่วงนี้เทียบช่วงก่อน"
        ) {
            if card.cumulative.isEmpty {
                Text("ยังไม่มีข้อมูลสะสม")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                let cur = zip(card.labels, card.cumulative).enumerated().map {
                    TrendPoint(id: "cc-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงนี้")
                }
                let prev = zip(card.labels, card.prevCumulative).enumerated().map {
                    TrendPoint(id: "cp-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงก่อน")
                }
                Chart(cur + prev) { p in
                    LineMark(x: .value("ช่วง", p.label), y: .value("สะสม", p.value), series: .value("s", p.series))
                        .foregroundStyle(p.series == "ช่วงนี้" ? accent : AppTheme.inkMuted.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: p.series == "ช่วงนี้" ? 2.6 : 1.6, dash: p.series == "ช่วงนี้" ? [] : [5, 4]))
                        .interpolationMethod(.linear)
                }
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private var periodCompareCard: some View {
        SectionCard(
            "เปรียบเทียบช่วงนี้ vs ก่อน",
            systemImage: "arrow.left.arrow.right",
            subtitle: "รวมทั้งช่วง · \(focus == .both ? "เที่ยวรถ × ร่อนทราย" : focus.label)"
        ) {
            switch focus {
            case .both:
                GroupedBarChartView(
                    labels: ["เที่ยวรถ", "ร่อนทราย"],
                    seriesA: [report.trip.total, report.sand.total],
                    seriesB: [report.trip.prevTotal, report.sand.prevTotal],
                    colorA: AppTheme.brand,
                    colorB: AppTheme.inkMuted.opacity(0.55),
                    labelA: "ช่วงนี้",
                    labelB: "ช่วงก่อน"
                )

                if let ratio = report.tripSandRatio {
                    HStack {
                        Text(String(format: "อัตราเที่ยว/รอบร่อน %.1f", ratio))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        if let prev = report.prevTripSandRatio {
                            Text(String(format: "(ก่อน %.1f)", prev))
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            case .trip, .sand:
                let card = primaryCard
                GroupedBarChartView(
                    labels: [card.title],
                    seriesA: [card.total],
                    seriesB: [card.prevTotal],
                    colorA: accent(for: card),
                    colorB: AppTheme.inkMuted.opacity(0.55),
                    labelA: "ช่วงนี้",
                    labelB: "ช่วงก่อน"
                )
                Text(
                    "ช่วงนี้ \(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) · ก่อน \(OpsTrendAnalytics.formatCompact(card.prevTotal)) (\(OpsTrendAnalytics.formatSignedPct(card.changePct)))"
                )
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .padding(.top, 4)
            }
        }
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

    private var sessionSplitCard: some View {
        let mornings = report.dailyPoints.map { Double($0.tripMorning) }
        let afternoons = report.dailyPoints.map { Double($0.tripAfternoon) }
        let labels = report.dailyPoints.map(\.label)
        let showDaily = period == .week || labels.count <= 14
        let morningTotal = mornings.reduce(0, +)
        let afternoonTotal = afternoons.reduce(0, +)
        return SectionCard(
            "จังหวะเช้า / บ่าย (เที่ยวรถ)",
            systemImage: "sun.horizon.fill",
            subtitle: showDaily ? "แยกช่วงเวลาทำงานรายวัน" : "สรุปรวมทั้งช่วง"
        ) {
            if showDaily, !labels.isEmpty {
                GroupedBarChartView(
                    labels: labels,
                    seriesA: mornings,
                    seriesB: afternoons,
                    colorA: Color(hex: "#f59e0b"),
                    colorB: AppTheme.info,
                    labelA: "เช้า",
                    labelB: "บ่าย"
                )
                Text("รวมเช้า \(OpsTrendAnalytics.formatCompact(morningTotal)) · บ่าย \(OpsTrendAnalytics.formatCompact(afternoonTotal)) เที่ยว")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    miniStat("เช้าทั้งช่วง", OpsTrendAnalytics.formatCompact(morningTotal), "เที่ยว")
                    miniStat("บ่ายทั้งช่วง", OpsTrendAnalytics.formatCompact(afternoonTotal), "เที่ยว")
                }
            }
        }
    }

    // MARK: - Advanced speed / volume

    private var advancedSection: some View {
        let modes: [OpsTrendAdvancedMode] = {
            switch focus {
            case .both: return [report.tripAdvanced, report.sandAdvanced]
            case .trip: return [report.tripAdvanced]
            case .sand: return [report.sandAdvanced]
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            Text("วิเคราะห์ขั้นสูง · ความเร็ว × ปริมาณ")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(period == .week ? "จากเวลาแตะรอบจริงรายวัน" : "รวมเป็นสัปดาห์ย่อยจากเวลาแตะรอบ")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)

            ForEach(Array(modes.enumerated()), id: \.offset) { _, mode in
                advancedModeCard(mode)
            }

            if focus == .both {
                advancedHeadToHead
            }
        }
    }

    private func advancedModeCard(_ mode: OpsTrendAdvancedMode) -> some View {
        let accent = mode.title.contains("ทราย") ? AppTheme.brand : AppTheme.info
        return SectionCard(
            "\(mode.title) · Pro",
            systemImage: "speedometer",
            subtitle: "คะแนนรวม \(mode.combinedScore) · ความเร็ว \(mode.speedScore) · ปริมาณ \(mode.volumeScore)"
        ) {
            HStack(spacing: 10) {
                advancedScorePill("รวม", mode.combinedScore, accent)
                advancedScorePill("เร็ว", mode.speedScore, Color(hex: "#16a34a"))
                advancedScorePill("ปริมาณ", mode.volumeScore, AppTheme.warning)
                Spacer(minLength: 0)
                paceChip(mode.pace, accent: accent)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                miniStat("ปริมาณรวม", OpsTrendAnalytics.formatCompact(mode.volumeTotal), mode.unit)
                miniStat("เฉลี่ย/วัน", OpsTrendAnalytics.formatCompact(mode.volumeAvgPerDay), mode.unit)
                miniStat("จังหวะเฉลี่ย", OpsTrendAnalytics.formatIntervalSec(mode.avgIntervalSec), "")
                miniStat("อัตราผลิต", OpsTrendAnalytics.formatPerHour(mode.throughputPerHour), "")
                miniStat("ชม.ทำงาน", CountRecordAnalytics.formatDurationHours(mode.activeHoursTotal), "")
                miniStat(
                    "คิวรวม",
                    mode.cubicTotal > 0 ? OpsTrendAnalytics.formatCompact(mode.cubicTotal) : "—",
                    "คิว"
                )
            }

            HStack(spacing: 12) {
                deltaBadge("ปริมาณ", mode.volumeChangePct)
                deltaBadge("ความเร็ว", mode.speedChangePct)
                deltaBadge("อัตรา/ชม.", mode.throughputChangePct)
            }

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
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(AppTheme.hairline)
                        AxisValueLabel().foregroundStyle(AppTheme.inkMuted)
                    }
                }

                Text("จังหวะเฉลี่ย (วินาที) — ยิ่งต่ำยิ่งเร็ว")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 4)
                Chart {
                    ForEach(Array(mode.seriesLabels.enumerated()), id: \.offset) { i, label in
                        let v = i < mode.intervalSeries.count ? mode.intervalSeries[i] : 0
                        if v > 0 {
                            LineMark(x: .value("ช่วง", label), y: .value("วินาที", v))
                                .foregroundStyle(accent)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("ช่วง", label), y: .value("วินาที", v))
                                .foregroundStyle(accent)
                        }
                    }
                }
                .frame(height: 130)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(mode.insights.prefix(4).enumerated()), id: \.offset) { _, line in
                    Text("· \(line)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
    }

    private func advancedScorePill(_ title: String, _ score: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private func deltaBadge(_ title: String, _ pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Text(OpsTrendAnalytics.formatSignedPct(pct))
                .font(.caption.weight(.bold))
                .foregroundStyle(deltaColor(pct))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
    }

    private var advancedHeadToHead: some View {
        SectionCard(
            "เทียบเที่ยวรถ × ร่อนทราย",
            systemImage: "flag.checkered",
            subtitle: "คะแนนขั้นสูงในช่วงนี้"
        ) {
            GroupedBarChartView(
                labels: ["ความเร็ว", "ปริมาณ", "รวม"],
                seriesA: [
                    Double(report.tripAdvanced.speedScore),
                    Double(report.tripAdvanced.volumeScore),
                    Double(report.tripAdvanced.combinedScore),
                ],
                seriesB: [
                    Double(report.sandAdvanced.speedScore),
                    Double(report.sandAdvanced.volumeScore),
                    Double(report.sandAdvanced.combinedScore),
                ],
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
                        miniStat("ความนิ่ง", "\(card.consistencyScore)", "คะแนน")
                        miniStat("ส่วนเบี่ยงเบน", OpsTrendAnalytics.formatCompact(card.stdDev), card.unit)
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
                .minimumScaleFactor(0.8)
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
        let lines = focusedInsights
        return SectionCard(
            "สรุปจังหวะ & คำแนะนำ",
            systemImage: "text.badge.checkmark",
            subtitle: "\(report.activeDays)/\(report.coverageDays) วันมีงาน · สตรีค \(report.streakDays)"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
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

    private var focusedInsights: [String] {
        switch focus {
        case .both:
            return report.insights
        case .trip:
            let fromReport = report.insights.filter {
                $0.contains("เที่ยว") || $0.contains("เป้า") || $0.contains("วันทำงาน") || $0.contains("สตรีค")
            }
            let advanced = Array(report.tripAdvanced.insights.prefix(3))
            return fromReport.isEmpty ? advanced : fromReport + advanced
        case .sand:
            let fromReport = report.insights.filter {
                $0.contains("ร่อน") || $0.contains("ทราย") || $0.contains("วันทำงาน") || $0.contains("สตรีค")
            }
            let advanced = Array(report.sandAdvanced.insights.prefix(3))
            return fromReport.isEmpty ? advanced : fromReport + advanced
        }
    }

    // MARK: - Helpers

    private func accent(for card: OpsTrendMetricCard) -> Color {
        card.title.contains("ทราย") ? AppTheme.brand : AppTheme.info
    }

    private func gradeColor(_ grade: OpsTrendGrade) -> Color {
        switch grade {
        case .aPlus, .a: return Color(hex: "#16a34a")
        case .b: return AppTheme.brand
        case .c: return AppTheme.warning
        case .d: return Color(hex: "#dc2626")
        }
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
