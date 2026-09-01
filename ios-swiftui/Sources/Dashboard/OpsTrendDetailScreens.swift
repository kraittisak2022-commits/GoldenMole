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

                SectionCard("เธเธฐเนเธเธเธฃเธงเธก", systemImage: "rosette", subtitle: sc.headline) {
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
                                "\(OpsTrendAnalytics.formatSignedInt(sc.scoreDelta)) vs \(report.period.shortLabel)เธเนเธญเธ",
                                systemImage: sc.scoreDelta >= 0 ? "arrow.up.right" : "arrow.down.right"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(sc.scoreDelta >= 0 ? Color(hex: "#16a34a") : Color(hex: "#dc2626"))
                            Text("\(report.activeDays)/\(report.coverageDays) เธงเธฑเธเธกเธตเธเธฒเธ ยท เธชเธ•เธฃเธตเธ \(report.streakDays)")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                    }
                }

                SectionCard("เธญเธเธเนเธเธฃเธฐเธเธญเธเธเธฐเนเธเธ", systemImage: "chart.bar.doc.horizontal") {
                    pillarRow("เธเธฃเธดเธกเธฒเธ“", sc.volumeScore, AppTheme.info)
                    pillarRow("เน€เธ•เธดเธเนเธ•", sc.growthScore, Color(hex: "#16a34a"))
                    pillarRow("เธเธงเธฒเธกเธเธดเนเธ", sc.consistencyScore, AppTheme.brand)
                    pillarRow("เธเธฃเธญเธเธเธฅเธธเธก", sc.coverageScore, AppTheme.warning)
                    pillarRow("เธชเธกเธ”เธธเธฅ", sc.balanceScore, Color(hex: "#7c3aed"))
                }

                SectionCard("เน€เธ—เธตเนเธขเธงเธฃเธ– ร— เธฃเนเธญเธเธ—เธฃเธฒเธข", systemImage: "arrow.left.arrow.right") {
                    detailMetricRow("เน€เธ—เธตเนเธขเธงเธฃเธ–", report.trip)
                    Divider().opacity(0.3)
                    detailMetricRow("เธฃเนเธญเธเธ—เธฃเธฒเธข", report.sand)
                    if let ratio = report.tripSandRatio {
                        Text(String(format: "เธญเธฑเธ•เธฃเธฒเน€เธ—เธตเนเธขเธง/เธฃเธญเธเธฃเนเธญเธ %.1f", ratio))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 6)
                    }
                }

                if !report.insights.isEmpty {
                    SectionCard("เธชเธฃเธธเธเธเธฑเธเธซเธงเธฐ", systemImage: "text.badge.checkmark") {
                        ForEach(Array(report.insights.enumerated()), id: \.offset) { _, line in
                            Text("ยท \(line)")
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
        .navigationTitle("เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธเธฐเนเธเธ")
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
            Text("เธฃเธงเธก \(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) ยท เน€เธเธฅเธตเนเธข \(OpsTrendAnalytics.formatCompact(card.average))/เธงเธฑเธ")
                .font(.caption).foregroundStyle(AppTheme.inkMuted)
            Text("เน€เธ—เธตเธขเธเธเนเธญเธ \(OpsTrendAnalytics.formatSignedPct(card.changePct)) ยท เธชเธนเธเธชเธธเธ” \(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard("\(card.title) ยท เธชเธฃเธธเธ", systemImage: "chart.bar.fill") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        stat("เธฃเธงเธกเธเนเธงเธเธเธตเน", OpsTrendAnalytics.formatCompact(card.total), card.unit)
                        stat("เธฃเธงเธกเธเนเธงเธเธเนเธญเธ", OpsTrendAnalytics.formatCompact(card.prevTotal), card.unit)
                        stat("เน€เธเธฅเธตเนเธข/เธงเธฑเธ", OpsTrendAnalytics.formatCompact(card.average), card.unit)
                        stat("เน€เธ•เธดเธเนเธ•", OpsTrendAnalytics.formatSignedPct(card.changePct), "")
                        stat("เธชเธนเธเธชเธธเธ”", "\(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))", card.unit)
                        stat("เธ•เนเธณเธชเธธเธ”", "\(card.worstLabel) \(OpsTrendAnalytics.formatCompact(card.worstValue))", card.unit)
                        stat("เธเธงเธฒเธกเธเธดเนเธ", "\(card.consistencyScore)", "เธเธฐเนเธเธ")
                        stat("เธชเนเธงเธเน€เธเธตเนเธขเธเน€เธเธ", OpsTrendAnalytics.formatCompact(card.stdDev), card.unit)
                    }
                }

                SectionCard("Pro ยท \(card.title)", systemImage: "speedometer") {
                    HStack(spacing: 10) {
                        proPill("เธฃเธงเธก", advanced.combinedScore, accent)
                        proPill("เน€เธฃเนเธง", advanced.speedScore, Color(hex: "#16a34a"))
                        proPill("เธเธฃเธดเธกเธฒเธ“", advanced.volumeScore, AppTheme.warning)
                    }
                    stat("เธญเธฑเธ•เธฃเธฒเธเธฅเธดเธ•", OpsTrendAnalytics.formatPerHour(advanced.throughputPerHour), "")
                    stat("เธเธฑเธเธซเธงเธฐเน€เธเธฅเธตเนเธข", OpsTrendAnalytics.formatIntervalSec(advanced.avgIntervalSec), "")
                }

                if !card.labels.isEmpty {
                    SectionCard("เนเธเธงเนเธเนเธก", systemImage: "chart.xyaxis.line", subtitle: "เน€เธ—เธตเธขเธ \(period.shortLabel)เธเนเธญเธ") {
                        Chart {
                            ForEach(Array(zip(card.labels, card.series).enumerated()), id: \.offset) { _, pair in
                                LineMark(x: .value("เธเนเธงเธ", pair.0), y: .value("เธเนเธฒ", pair.1))
                                    .foregroundStyle(accent)
                                    .interpolationMethod(.catmullRom)
                            }
                            ForEach(Array(zip(card.labels, card.prevSeries).enumerated()), id: \.offset) { _, pair in
                                LineMark(x: .value("เธเนเธงเธ", pair.0), y: .value("เธเนเธฒ", pair.1))
                                    .foregroundStyle(AppTheme.inkMuted.opacity(0.6))
                                    .lineStyle(StrokeStyle(dash: [4, 3]))
                            }
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("\(card.title) ยท เธฅเธฐเน€เธญเธตเธขเธ”")
        .navigationBarTitleDisplayMode(.inline)
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
                SectionCard(bucket.label, systemImage: "calendar.badge.clock", subtitle: period == .week ? "เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธงเธฑเธ" : "เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธชเธฑเธเธ”เธฒเธซเนเธขเนเธญเธข") {
                    HStack(spacing: 16) {
                        VStack {
                            Text("\(bucket.score)")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                            Text("เธเธฐเนเธเธ").font(.caption).foregroundStyle(AppTheme.inkMuted)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("เน€เธ—เธตเนเธขเธงเธฃเธ– \(OpsTrendAnalytics.formatCompact(bucket.tripTotal))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.info)
                            Text("เธฃเนเธญเธเธ—เธฃเธฒเธข \(OpsTrendAnalytics.formatCompact(bucket.sandTotal))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.brand)
                        }
                        Spacer()
                    }
                }

                if let day = matchingDay {
                    SectionCard("เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธงเธฑเธ", systemImage: "list.bullet") {
                        statRow("เน€เธ—เธตเนเธขเธงเธฃเธ–", "\(day.tripRounds)", "เน€เธ—เธตเนเธขเธง")
                        statRow("เธฃเนเธญเธเธ—เธฃเธฒเธข", "\(day.sandRounds)", "เธฃเธญเธ")
                        statRow("เน€เธเนเธฒ", "\(day.tripMorning)", "เน€เธ—เธตเนเธขเธง")
                        statRow("เธเนเธฒเธข", "\(day.tripAfternoon)", "เน€เธ—เธตเนเธขเธง")
                        if day.tripCubic > 0 {
                            statRow("เธเธดเธงเธฃเธ–", OpsTrendAnalytics.formatCompact(day.tripCubic), "เธเธดเธง")
                        }
                    }
                }

                if period == .month {
                    SectionCard("เธชเธฃเธธเธเธเนเธงเธ", systemImage: "chart.bar") {
                        Text("W\(bucket.label) เธฃเธงเธก \(OpsTrendAnalytics.formatCompact(bucket.tripTotal)) เน€เธ—เธตเนเธขเธง ยท \(OpsTrendAnalytics.formatCompact(bucket.sandTotal)) เธฃเธญเธ")
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
                    detailLinkRow("เธเธฐเนเธเธเธฃเธงเธก", "\(report.scorecard.score) \(report.scorecard.grade.rawValue)", "rosette")
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
                    detailLinkRow("เน€เธ—เธตเนเธขเธงเธฃเธ–", "\(OpsTrendAnalytics.formatCompact(report.trip.total)) เน€เธ—เธตเนเธขเธง", "truck.box.fill")
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
                    detailLinkRow("เธฃเนเธญเธเธ—เธฃเธฒเธข", "\(OpsTrendAnalytics.formatCompact(report.sand.total)) เธฃเธญเธ", "drop.fill")
                }
                .buttonStyle(.plain)

                SectionCard("เธเธฐเนเธเธเธฃเธฒเธข\(report.period == .week ? "เธงเธฑเธ" : "เธชเธฑเธเธ”เธฒเธซเน")", systemImage: "calendar") {
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
                    SectionCard("เธชเธฑเธเธเธฒเธ“เธ—เธตเนเธเธงเธฃเธฅเธเธกเธทเธญ", systemImage: "bell.badge") {
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
        .navigationTitle("เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธ—เธฑเนเธเธซเธกเธ”")
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
                        "เธเธฐเนเธเธ Pro",
                        "\(mode.combinedScore) ยท เน€เธฃเนเธง \(mode.speedScore) ยท เธเธฃเธดเธกเธฒเธ“ \(mode.volumeScore)",
                        "speedometer"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    OpsTrendMetricDetailView(card: card, advanced: mode, period: report.period, accent: accent)
                } label: {
                    modeDetailLinkRow(
                        card.title,
                        "\(OpsTrendAnalytics.formatCompact(card.total)) \(card.unit) ยท เน€เธเธฅเธตเนเธข \(OpsTrendAnalytics.formatCompact(card.average))/เธงเธฑเธ",
                        focus == .trip ? "truck.box.fill" : "drop.fill"
                    )
                }
                .buttonStyle(.plain)

                SectionCard("เธเธฅเธฃเธฒเธข\(report.period == .week ? "เธงเธฑเธ" : "เธชเธฑเธเธ”เธฒเธซเน")", systemImage: "calendar") {
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
                    SectionCard("เธญเธฑเธเธ”เธฑเธเธฃเธ–", systemImage: "truck.box.fill") {
                        ForEach(proBundle.vehicleRanks) { row in
                            NavigationLink {
                                OpsTrendProVehicleDetailView(vehicle: row, period: report.period)
                            } label: {
                                HStack {
                                    Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(row.rounds) เน€เธ—เธตเนเธขเธง")
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
                    SectionCard("เธชเธฑเธเธเธฒเธ“เธ—เธตเนเธเธงเธฃเธฅเธเธกเธทเธญ", systemImage: "bell.badge") {
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
        .navigationTitle("เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ” ยท \(focus.label)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var focusedAlerts: [OpsTrendAlert] {
        switch focus {
        case .trip: return report.actionPlan.alerts.filter { $0.area != "เธฃเนเธญเธเธ—เธฃเธฒเธข" }
        case .sand: return report.actionPlan.alerts.filter { $0.area != "เน€เธ—เธตเนเธขเธงเธฃเธ–" }
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
                SectionCard("เธเธฐเนเธเธ Pro", systemImage: "speedometer", subtitle: "\(focus.label) ยท \(report.period.label)") {
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
                                Text("Pro")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(width: 120, height: 120)

                        VStack(alignment: .leading, spacing: 8) {
                            scoreRow("เธเธงเธฒเธกเน€เธฃเนเธง", mode.speedScore, Color(hex: "#16a34a"))
                            scoreRow("เธเธฃเธดเธกเธฒเธ“", mode.volumeScore, AppTheme.warning)
                            Label(mode.pace.label, systemImage: mode.pace.systemImage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(accent)
                        }
                    }
                }

                SectionCard("เน€เธเธฃเธตเธขเธเน€เธ—เธตเธขเธเธเนเธงเธ", systemImage: "arrow.left.arrow.right") {
                    compareRow("เธเธฃเธดเธกเธฒเธ“เธฃเธงเธก", OpsTrendAnalytics.formatCompact(mode.volumeTotal), OpsTrendAnalytics.formatSignedPct(mode.volumeChangePct))
                    compareRow("เธญเธฑเธ•เธฃเธฒเธเธฅเธดเธ•", OpsTrendAnalytics.formatPerHour(mode.throughputPerHour), OpsTrendAnalytics.formatSignedPct(mode.throughputChangePct))
                    compareRow("เธเธฑเธเธซเธงเธฐเน€เธเธฅเธตเนเธข", OpsTrendAnalytics.formatIntervalSec(mode.avgIntervalSec), OpsTrendAnalytics.formatSignedPct(mode.speedChangePct))
                    compareRow("เธเธก.เธ—เธณเธเธฒเธ", CountRecordAnalytics.formatDurationHours(mode.activeHoursTotal), "")
                    if mode.cubicTotal > 0 {
                        compareRow("เธเธดเธงเธฃเธงเธก", OpsTrendAnalytics.formatCompact(mode.cubicTotal), "เธเธดเธง")
                    }
                }

                SectionCard("เธชเธ–เธดเธ•เธด\(card.title)", systemImage: "chart.bar") {
                    compareRow("เธฃเธงเธกเธเนเธงเธเธเธตเน", OpsTrendAnalytics.formatCompact(card.total), card.unit)
                    compareRow("เธฃเธงเธกเธเนเธงเธเธเนเธญเธ", OpsTrendAnalytics.formatCompact(card.prevTotal), card.unit)
                    compareRow("เน€เธเธฅเธตเนเธข/เธงเธฑเธ", OpsTrendAnalytics.formatCompact(card.average), card.unit)
                    compareRow("เธชเธนเธเธชเธธเธ”", "\(card.bestLabel) \(OpsTrendAnalytics.formatCompact(card.bestValue))", card.unit)
                    compareRow("เธ•เนเธณเธชเธธเธ”", "\(card.worstLabel) \(OpsTrendAnalytics.formatCompact(card.worstValue))", card.unit)
                    compareRow("เธเธงเธฒเธกเธเธดเนเธ", "\(card.consistencyScore)", "เธเธฐเนเธเธ")
                }
            }
            .padding(16)
        }
        .background(DashboardBackground())
        .navigationTitle("เธเธฐเนเธเธ Pro ยท \(focus.label)")
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
                SectionCard(day.label, systemImage: "calendar", subtitle: "เธเธฐเนเธเธ Pro \(day.score)") {
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
                                Text("เธเธฑเธเธซเธงเธฐ \(OpsTrendAnalytics.formatIntervalSec(sec))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                        }
                        Spacer()
                    }
                }

                if let point {
                    SectionCard("เธฃเธฒเธขเธฅเธฐเน€เธญเธตเธขเธ”เธงเธฑเธ", systemImage: "list.bullet") {
                        if focus == .trip {
                            statRow("เน€เธ—เธตเนเธขเธงเธฃเธ–", "\(point.tripRounds)", "เน€เธ—เธตเนเธขเธง")
                            statRow("เน€เธเนเธฒ", "\(point.tripMorning)", "เน€เธ—เธตเนเธขเธง")
                            statRow("เธเนเธฒเธข", "\(point.tripAfternoon)", "เน€เธ—เธตเนเธขเธง")
                            if point.tripCubic > 0 {
                                statRow("เธเธดเธง", OpsTrendAnalytics.formatCompact(point.tripCubic), "เธเธดเธง")
                            }
                        } else {
                            statRow("เธฃเนเธญเธเธ—เธฃเธฒเธข", "\(point.sandRounds)", "เธฃเธญเธ")
                            if point.sandWashedCubic > 0 {
                                statRow("เธเธดเธงเธฃเนเธญเธ", OpsTrendAnalytics.formatCompact(point.sandWashedCubic), "เธเธดเธง")
                            }
                        }
                    }
                }

                if day.cubic > 0 {
                    SectionCard("เธเธฃเธดเธกเธฒเธ“", systemImage: "cube") {
                        Text("\(OpsTrendAnalytics.formatCompact(day.cubic)) เธเธดเธง")
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
                        vehicleStat("เน€เธ—เธตเนเธขเธงเธฃเธงเธก", "\(vehicle.rounds)", "เน€เธ—เธตเนเธขเธง")
                        vehicleStat("เธชเธฑเธ”เธชเนเธงเธ", "\(Int(vehicle.sharePct.rounded()))", "%")
                        vehicleStat("เธญเธฑเธ•เธฃเธฒเธเธฅเธดเธ•", OpsTrendAnalytics.formatPerHour(vehicle.perHour), "")
                        vehicleStat(
                            "เธเธฑเธเธซเธงเธฐเน€เธเธฅเธตเนเธข",
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
