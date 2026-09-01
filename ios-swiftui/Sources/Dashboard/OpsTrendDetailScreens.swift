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
                                "\(OpsTrendAnalytics.formatSignedInt(sc.scoreDelta)) vs \(report.period.shortLabel)ก่อน",
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

                SectionCard("Pro · \(card.title)", systemImage: "speedometer") {
                    HStack(spacing: 10) {
                        proPill("รวม", advanced.combinedScore, accent)
                        proPill("เร็ว", advanced.speedScore, Color(hex: "#16a34a"))
                        proPill("ปริมาณ", advanced.volumeScore, AppTheme.warning)
                    }
                    stat("อัตราผลิต", OpsTrendAnalytics.formatPerHour(advanced.throughputPerHour), "")
                    stat("จังหวะเฉลี่ย", OpsTrendAnalytics.formatIntervalSec(advanced.avgIntervalSec), "")
                }

                if !card.labels.isEmpty {
                    SectionCard("แนวโน้ม", systemImage: "chart.xyaxis.line", subtitle: "เทียบ \(period.shortLabel)ก่อน") {
                        Chart {
                            ForEach(Array(zip(card.labels, card.series).enumerated()), id: \.offset) { _, pair in
                                LineMark(x: .value("ช่วง", pair.0), y: .value("ค่า", pair.1))
                                    .foregroundStyle(accent)
                                    .interpolationMethod(.catmullRom)
                            }
                            ForEach(Array(zip(card.labels, card.prevSeries).enumerated()), id: \.offset) { _, pair in
                                LineMark(x: .value("ช่วง", pair.0), y: .value("ค่า", pair.1))
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
        .navigationTitle("\(card.title) · ละเอียด")
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
                        Text("W\(bucket.label) รวม \(OpsTrendAnalytics.formatCompact(bucket.tripTotal)) เที่ยว · \(OpsTrendAnalytics.formatCompact(bucket.sandTotal)) รอบ")
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
