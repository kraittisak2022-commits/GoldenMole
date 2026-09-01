import Charts
import SwiftUI

// MARK: - Combined score detail

struct OpsTrendScoreDetailView: View {
    let report: OpsTrendReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let sc = report.scorecard
                let accent = gradeColor(sc.grade)

                SectionCard("คะแนนรวม", systemImage: "rosette", subtitle: sc.headline) {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(AppTheme.surfaceSoft, lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(sc.score) / 100)
                                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack {
                                Text("\(sc.score)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                Text(sc.grade.rawValue)
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(width: 120, height: 120)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(sc.subheadline)
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                            Label(
                                "\(OpsTrendAnalytics.formatSignedInt(sc.scoreDelta)) เทียบ \(report.period.shortLabel)ก่อน",
                                systemImage: sc.scoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(sc.scoreDelta >= 0 ? Color(hex: "#16a34a") : Color(hex: "#dc2626"))
                            Text("\(report.activeDays)/\(report.coverageDays) วันมีงาน · สตรีค \(report.streakDays)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                }

                SectionCard("องค์ประกอบคะแนน", systemImage: "chart.bar.doc.horizontal") {
                    pillarRow("ปริมาณ", sc.volumeScore, AppTheme.info)
                    pillarRow("เติบโต", sc.growthScore, Color(hex: "#16a34a"))
                    pillarRow("ความนิ่ง", sc.consistencyScore, AppTheme.brand)
                    pillarRow("ครอบคลุม", sc.coverageScore, AppTheme.warning)
                    pillarRow("สมดุล", sc.balanceScore, Color(hex: "#7c3aed"))
                }

                SectionCard("เที่ยวรถ × ร่อนทราย", systemImage: "arrow.left.arrow.right") {
                    detailMetricRow("เที่ยวรถ", report.trip)
                    Divider().opacity(0.3)
                    detailMetricRow("ร่อนทราย", report.sand)
                    if let ratio = report.tripSandRatio {
                        Text(String(format: "อัตราเที่ยว/รอบร่อน %.1f", ratio))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 6)
                    }
                }

                if !report.insights.isEmpty {
                    SectionCard("สรุปจังหวะ", systemImage: "text.badge.checkmark") {
                        ForEach(Array(report.insights.enumerated()), id: \.offset) { _, line in
                            Text("· \(line)")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("รายละเอียดคะแนน")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pillarRow(_ title: String, _ score: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Text("\(score)").font(.caption.weight(.bold)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.surfaceSoft)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    private func detailMetricRow(_ title: String, _ card: OpsTrendMetricCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline.weight(.bold))
            Text("รวม \(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) · เฉลี่ย \(OpsTrendAnalytics.formatCompact(card.average))/วัน")
                .font(.caption).foregroundStyle(AppTheme.inkMuted)
            Text("เทียบก่อน \(OpsTrendAnalytics.formatSignedPct(card.changePct)) · สูงสุด \(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))")
                .font(.caption2).foregroundStyle(AppTheme.inkMuted)
        }
    }

    private func gradeColor(_ grade: OpsTrendGrade) -> Color {
        switch grade {
        case .aPlus, .a: return Color(hex: "#16a34a")
        case .b: return AppTheme.brand
        case .c: return AppTheme.warning
        case .d: return Color(hex: "#dc2626")
        }
    }
}

// MARK: - Metric detail

struct OpsTrendMetricDetailView: View {
    let card: OpsTrendMetricCard
    let advanced: OpsTrendAdvancedMode
    let period: OpsTrendPeriod
    let accent: Color

    @State private var selectedTrendPoint: TrendLabelSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard("\(card.title) · สรุป", systemImage: "chart.bar.fill") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        stat("รวมช่วงนี้", OpsTrendAnalytics.formatCompact(card.total), card.unit)
                        stat("รวมช่วงก่อน", OpsTrendAnalytics.formatCompact(card.prevTotal), card.unit)
                        stat("เฉลี่ย/วัน", OpsTrendAnalytics.formatCompact(card.average), card.unit)
                        stat("เติบโต", OpsTrendAnalytics.formatSignedPct(card.changePct), "")
                        stat("สูงสุด", "\(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))", card.unit)
                        stat("ต่ำสุด", "\(card.worstLabel) \(OpsTrendAnalytics.formatCompact(card.worstValue))", card.unit)
                        stat("ความนิ่ง", "\(card.consistencyScore)", "คะแนน")
                        stat("ส่วนเบี่ยงเบน", OpsTrendAnalytics.formatCompact(card.stdDev), card.unit)
                    }
                }

                SectionCard("มืออาชีพ · \(card.title)", systemImage: "speedometer") {
                    HStack(spacing: 10) {
                        proPill("รวม", advanced.combinedScore, accent)
                        proPill("เร็ว", advanced.speedScore, Color(hex: "#16a34a"))
                        proPill("ปริมาณ", advanced.volumeScore, AppTheme.warning)
                    }
                    stat("อัตราผลิต", OpsTrendAnalytics.formatPerHour(advanced.throughputPerHour), "")
                    stat("จังหวะเฉลี่ย", OpsTrendAnalytics.formatIntervalSec(advanced.avgIntervalSec), "")
                }

                if !card.labels.isEmpty {
                    SectionCard("แนวโน้ม", systemImage: "chart.xyaxis.line", subtitle: "แตะจุดบนกราฟเพื่อดูค่า · เทียบ \(period.shortLabel)ก่อน") {
                        trendChart
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("\(card.title) · ละเอียด")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTrendPoint) { selection in
            trendPointSheet(label: selection.label)
        }
    }

    private var trendChart: some View {
        let labels = card.labels
        let cur = zip(labels, card.series).enumerated().map {
            TrendChartPoint(id: "c-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงนี้")
        }
        let prev = zip(labels, card.prevSeries).enumerated().map {
            TrendChartPoint(id: "p-\($0.offset)", label: $0.element.0, value: $0.element.1, series: "ช่วงก่อน")
        }

        return Chart(cur + prev) { p in
            if p.series == "ช่วงนี้" {
                LineMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value), series: .value("s", p.series))
                    .foregroundStyle(accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value))
                    .foregroundStyle(accent)
            } else {
                LineMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value), series: .value("s", p.series))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.7))
                    .lineStyle(StrokeStyle(dash: [4, 3]))
                PointMark(x: .value("ช่วง", p.label), y: .value("ค่า", p.value))
                    .foregroundStyle(AppTheme.inkMuted.opacity(0.5))
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartXSelection(value: Binding(
            get: { selectedTrendPoint?.label },
            set: { newLabel in
                if let newLabel {
                    selectedTrendPoint = TrendLabelSelection(label: newLabel)
                }
            }
        ))
        .frame(height: 200)
    }

    @ViewBuilder
    private func trendPointSheet(label: String) -> some View {
        let idx = card.labels.firstIndex(of: label)
        let current = idx.map { card.series[$0] } ?? 0
        let previous = idx.map { card.prevSeries[$0] } ?? 0
        NavigationStack {
            OpsTrendChartPointSheet(
                title: label,
                subtitle: card.title,
                rows: [
                    ("ช่วงนี้", "\(OpsTrendAnalytics.formatCompact(current)) \(card.unit)"),
                    ("ช่วงก่อน", "\(OpsTrendAnalytics.formatCompact(previous)) \(card.unit)"),
                    ("ต่าง", OpsTrendAnalytics.formatSignedPct(previous > 0 ? ((current - previous) / previous) * 100 : nil)),
                ]
            )
        }
        .presentationDetents([.medium])
    }

    private func stat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline.weight(.bold))
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(AppTheme.inkMuted)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.surfaceSoft))
    }

    private func proPill(_ title: String, _ score: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(score)").font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
    }
}

// MARK: - Bucket detail

struct OpsTrendBucketDetailView: View {
    let bucket: OpsTrendBucketScore
    let period: OpsTrendPeriod
    let dailyPoints: [OpsTrendPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(bucket.label, systemImage: "calendar.badge.clock", subtitle: period == .week ? "รายละเอียดวัน" : "รายละเอียดสัปดาห์ย่อย") {
                    HStack(spacing: 16) {
                        VStack {
                            Text("\(bucket.score)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("คะแนน").font(.caption).foregroundStyle(AppTheme.inkMuted)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("เที่ยวรถ \(OpsTrendAnalytics.formatCompact(bucket.tripTotal))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.info)
                            Text("ร่อนทราย \(OpsTrendAnalytics.formatCompact(bucket.sandTotal))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.brand)
                        }
                        Spacer()
                    }
                }

                if let day = matchingDay {
                    SectionCard("รายละเอียดวัน", systemImage: "list.bullet") {
                        statRow("เที่ยวรถ", "\(day.tripRounds)", "เที่ยว")
                        statRow("ร่อนทราย", "\(day.sandRounds)", "รอบ")
                        statRow("เช้า", "\(day.tripMorning)", "เที่ยว")
                        statRow("บ่าย", "\(day.tripAfternoon)", "เที่ยว")
                        if day.tripCubic > 0 {
                            statRow("คิวรถ", OpsTrendAnalytics.formatCompact(day.tripCubic), "คิว")
                        }
                    }
                }

                if period == .month {
                    SectionCard("สรุปช่วง", systemImage: "chart.bar") {
                        Text("\(bucket.label) รวม \(OpsTrendAnalytics.formatCompact(bucket.tripTotal)) เที่ยว · \(OpsTrendAnalytics.formatCompact(bucket.sandTotal)) รอบ")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle(bucket.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var matchingDay: OpsTrendPoint? {
        dailyPoints.first { $0.id == bucket.id || $0.label == bucket.label }
    }

    private func statRow(_ title: String, _ value: String, _ unit: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(AppTheme.inkMuted)
            Spacer()
            Text("\(value) \(unit)").font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Combined full detail

struct OpsTrendCombinedDetailView: View {
    let report: OpsTrendReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    OpsTrendScoreDetailView(report: report)
                } label: {
                    detailLinkRow("คะแนนรวม", "\(report.scorecard.score) \(report.scorecard.grade.rawValue)", "rosette")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OpsTrendMetricDetailView(
                        card: report.trip,
                        advanced: report.tripAdvanced,
                        period: report.period,
                        accent: AppTheme.info
                    )
                } label: {
                    detailLinkRow("เที่ยวรถ", "\(OpsTrendAnalytics.formatCompact(report.trip.total)) เที่ยว", "truck.box.fill")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OpsTrendMetricDetailView(
                        card: report.sand,
                        advanced: report.sandAdvanced,
                        period: report.period,
                        accent: AppTheme.brand
                    )
                } label: {
                    detailLinkRow("ร่อนทราย", "\(OpsTrendAnalytics.formatCompact(report.sand.total)) รอบ", "drop.fill")
                }
                .buttonStyle(.plain)

                SectionCard("คะแนนราย\(report.period == .week ? "วัน" : "สัปดาห์")", systemImage: "calendar") {
                    ForEach(report.bucketScores) { bucket in
                        NavigationLink {
                            OpsTrendBucketDetailView(
                                bucket: bucket,
                                period: report.period,
                                dailyPoints: report.dailyPoints
                            )
                        } label: {
                            HStack {
                                Text(bucket.label).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(bucket.score)")
                                    .font(.headline.weight(.bold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !report.actionPlan.alerts.isEmpty {
                    SectionCard("สัญญาณที่ควรลงมือ", systemImage: "bell.badge") {
                        ForEach(report.actionPlan.alerts.prefix(5)) { alert in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.title).font(.subheadline.weight(.semibold))
                                Text(alert.detail).font(.caption).foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("รายละเอียดทั้งหมด")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailLinkRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.bold))
                Text(value).font(.caption).foregroundStyle(AppTheme.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.inkMuted)
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
}

// MARK: - Mode (trip/sand) full detail

struct OpsTrendModeDetailView: View {
    let focus: OpsTrendFocus
    let report: OpsTrendReport
    let proBundle: OpsTrendProBundle

    private var card: OpsTrendMetricCard { focus == .sand ? report.sand : report.trip }
    private var mode: OpsTrendAdvancedMode { focus == .sand ? report.sandAdvanced : report.tripAdvanced }
    private var accent: Color { focus == .sand ? AppTheme.brand : AppTheme.info }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink {
                    OpsTrendProScoreDetailView(focus: focus, report: report, mode: mode, card: card, accent: accent)
                } label: {
                    modeDetailLinkRow(
                        "คะแนนมืออาชีพ",
                        "\(mode.combinedScore) · เร็ว \(mode.speedScore) · ปริมาณ \(mode.volumeScore)",
                        "speedometer"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OpsTrendMetricDetailView(card: card, advanced: mode, period: report.period, accent: accent)
                } label: {
                    modeDetailLinkRow(
                        card.title,
                        "\(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) · เฉลี่ย \(OpsTrendAnalytics.formatCompact(card.average))/วัน",
                        focus == .trip ? "truck.box.fill" : "drop.fill"
                    )
                }
                .buttonStyle(.plain)

                SectionCard("ผลราย\(report.period == .week ? "วัน" : "สัปดาห์")", systemImage: "calendar") {
                    ForEach(proBundle.dayPerformance.sorted { $0.score > $1.score }) { day in
                        NavigationLink {
                            OpsTrendProDayDetailView(
                                day: day,
                                focus: focus,
                                mode: mode,
                                point: report.dailyPoints.first {
                                    $0.id == day.id || $0.startKey == day.dateKey || $0.label == day.label
                                }
                            )
                        } label: {
                            HStack {
                                Text(day.label).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(day.rounds) \(mode.unit)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text("\(day.score)")
                                    .font(.headline.weight(.bold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if focus == .trip, !proBundle.vehicleRanks.isEmpty {
                    SectionCard("อันดับรถ", systemImage: "truck.box.fill") {
                        ForEach(proBundle.vehicleRanks) { row in
                            NavigationLink {
                                OpsTrendProVehicleDetailView(vehicle: row, period: report.period)
                            } label: {
                                HStack {
                                    Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(row.rounds) เที่ยว")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(AppTheme.inkMuted)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let alerts = focusedAlerts
                if !alerts.isEmpty {
                    SectionCard("สัญญาณที่ควรลงมือ", systemImage: "bell.badge") {
                        ForEach(alerts.prefix(5)) { alert in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.title).font(.subheadline.weight(.semibold))
                                Text(alert.detail).font(.caption).foregroundStyle(AppTheme.inkMuted)
                                Text(alert.action).font(.caption.weight(.semibold)).foregroundStyle(accent)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("รายละเอียด · \(focus.label)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var focusedAlerts: [OpsTrendAlert] {
        switch focus {
        case .trip: return report.actionPlan.alerts.filter { $0.area != "ร่อนทราย" }
        case .sand: return report.actionPlan.alerts.filter { $0.area != "เที่ยวรถ" }
        case .both: return report.actionPlan.alerts
        }
    }

    private func modeDetailLinkRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline.weight(.bold))
                Text(value).font(.caption).foregroundStyle(AppTheme.inkMuted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.inkMuted)
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
}

// MARK: - Pro score detail

struct OpsTrendProScoreDetailView: View {
    let focus: OpsTrendFocus
    let report: OpsTrendReport
    let mode: OpsTrendAdvancedMode
    let card: OpsTrendMetricCard
    let accent: Color

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard("คะแนนมืออาชีพ", systemImage: "speedometer", subtitle: "\(focus.label) · \(report.period.label)") {
                    HStack(spacing: 20) {
                        ZStack {
                            Circle().stroke(AppTheme.surfaceSoft, lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: CGFloat(mode.combinedScore) / 100)
                                .stroke(accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack {
                                Text("\(mode.combinedScore)")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                Text("มืออาชีพ")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(width: 120, height: 120)

                        VStack(alignment: .leading, spacing: 8) {
                            scoreRow("ความเร็ว", mode.speedScore, Color(hex: "#16a34a"))
                            scoreRow("ปริมาณ", mode.volumeScore, AppTheme.warning)
                            Label(mode.pace.label, systemImage: mode.pace.systemImage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                        }
                    }
                }

                SectionCard("เปรียบเทียบช่วง", systemImage: "arrow.left.arrow.right") {
                    compareRow("ปริมาณรวม", OpsTrendAnalytics.formatCompact(mode.volumeTotal), OpsTrendAnalytics.formatSignedPct(mode.volumeChangePct))
                    compareRow("อัตราผลิต", OpsTrendAnalytics.formatPerHour(mode.throughputPerHour), OpsTrendAnalytics.formatSignedPct(mode.throughputChangePct))
                    compareRow("จังหวะเฉลี่ย", OpsTrendAnalytics.formatIntervalSec(mode.avgIntervalSec), OpsTrendAnalytics.formatSignedPct(mode.speedChangePct))
                    compareRow("ชม.ทำงาน", CountRecordAnalytics.formatDurationHours(mode.activeHoursTotal), "")
                    if mode.cubicTotal > 0 {
                        compareRow("คิวรวม", OpsTrendAnalytics.formatCompact(mode.cubicTotal), "คิว")
                    }
                }

                SectionCard("สถิติ\(card.title)", systemImage: "chart.bar") {
                    compareRow("รวมช่วงนี้", OpsTrendAnalytics.formatCompact(card.total), card.unit)
                    compareRow("รวมช่วงก่อน", OpsTrendAnalytics.formatCompact(card.prevTotal), card.unit)
                    compareRow("เฉลี่ย/วัน", OpsTrendAnalytics.formatCompact(card.average), card.unit)
                    compareRow("สูงสุด", "\(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))", card.unit)
                    compareRow("ต่ำสุด", "\(card.worstLabel) \(OpsTrendAnalytics.formatCompact(card.worstValue))", card.unit)
                    compareRow("ความนิ่ง", "\(card.consistencyScore)", "คะแนน")
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("คะแนนมืออาชีพ · \(focus.label)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scoreRow(_ title: String, _ score: Int, _ color: Color) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(AppTheme.inkMuted)
            Spacer()
            Text("\(score)").font(.subheadline.weight(.bold)).foregroundStyle(color)
        }
    }

    private func compareRow(_ title: String, _ value: String, _ suffix: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(AppTheme.inkMuted)
            Spacer()
            Text(suffix.isEmpty ? value : "\(value) \(suffix)")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pro day detail

struct OpsTrendProDayDetailView: View {
    let day: OpsTrendDayPerformance
    let focus: OpsTrendFocus
    let mode: OpsTrendAdvancedMode
    let point: OpsTrendPoint?

    private var accent: Color { focus == .sand ? AppTheme.brand : AppTheme.info }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(day.label, systemImage: "calendar", subtitle: "คะแนนมืออาชีพ \(day.score)") {
                    HStack(spacing: 16) {
                        Text("\(day.score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(day.rounds) \(mode.unit)")
                                .font(.headline.weight(.bold))
                            Text(OpsTrendAnalytics.formatPerHour(day.perHour))
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                            if let sec = day.intervalSec {
                                Text("จังหวะ \(OpsTrendAnalytics.formatIntervalSec(sec))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                        }
                        Spacer()
                    }
                }

                if let point {
                    SectionCard("รายละเอียดวัน", systemImage: "list.bullet") {
                        if focus == .trip {
                            statRow("เที่ยวรถ", "\(point.tripRounds)", "เที่ยว")
                            statRow("เช้า", "\(point.tripMorning)", "เที่ยว")
                            statRow("บ่าย", "\(point.tripAfternoon)", "เที่ยว")
                            if point.tripCubic > 0 {
                                statRow("คิว", OpsTrendAnalytics.formatCompact(point.tripCubic), "คิว")
                            }
                        } else {
                            statRow("ร่อนทราย", "\(point.sandRounds)", "รอบ")
                            if point.sandWashedCubic > 0 {
                                statRow("คิวร่อน", OpsTrendAnalytics.formatCompact(point.sandWashedCubic), "คิว")
                            }
                        }
                    }
                }

                if day.cubic > 0 {
                    SectionCard("ปริมาณ", systemImage: "cube") {
                        Text("\(OpsTrendAnalytics.formatCompact(day.cubic)) คิว")
                            .font(.headline.weight(.bold))
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle(day.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ title: String, _ value: String, _ unit: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(AppTheme.inkMuted)
            Spacer()
            Text("\(value) \(unit)").font(.subheadline.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pro vehicle detail

struct OpsTrendProVehicleDetailView: View {
    let vehicle: OpsTrendVehicleRank
    let period: OpsTrendPeriod

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(vehicle.name, systemImage: "truck.box.fill", subtitle: period.label) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        vehicleStat("เที่ยวรวม", "\(vehicle.rounds)", "เที่ยว")
                        vehicleStat("สัดส่วน", "\(Int(vehicle.sharePct.rounded()))", "%")
                        vehicleStat("อัตราผลิต", OpsTrendAnalytics.formatPerHour(vehicle.perHour), "")
                        vehicleStat(
                            "จังหวะเฉลี่ย",
                            OpsTrendAnalytics.formatIntervalSec(vehicle.avgIntervalSec),
                            ""
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func vehicleStat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(AppTheme.inkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.headline.weight(.bold))
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(AppTheme.inkMuted)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTheme.surfaceSoft))
    }
}

// MARK: - Chart point sheet

struct OpsTrendChartPointSheet: View {
    let title: String
    let subtitle: String?
    let rows: [(String, String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let subtitle {
                Section {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            Section {
                ForEach(rows, id: \.0) { row in
                    HStack {
                        Text(row.0)
                            .foregroundStyle(AppTheme.inkMuted)
                        Spacer()
                        Text(row.1)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.ink)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("ปิด") { dismiss() }
            }
        }
    }
}

private struct TrendChartPoint: Identifiable {
    let id: String
    let label: String
    let value: Double
    let series: String
}

private struct TrendLabelSelection: Identifiable {
    let label: String
    var id: String { label }
}
