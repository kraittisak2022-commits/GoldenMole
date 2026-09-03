import SwiftUI

// MARK: - Accent

private enum SandProAccent {
    static let pink = Color(hex: "#DB2777")
    static let rose = Color(hex: "#E11D48")
    static let violet = Color(hex: "#A21CAF")
    static let trip = Color(hex: "#2563EB")
}

// MARK: - Command strip

struct SandProCommandStrip: View {
    let pro: SandProSnapshot
    var onOpenDetail: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                healthBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMMAND · ร่อนทราย")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(SandProAccent.pink)
                    Text(pro.paceHealth.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.ink)
                    if let eta = pro.etaClock, !pro.reached {
                        Text("เป้า ~\(eta)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    } else if pro.reached {
                        Text("ถึงเป้าแล้ว")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: "#059669"))
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(pro.progressPct.rounded()))%")
                        .font(.title3.weight(.black).monospacedDigit())
                        .foregroundStyle(SandProAccent.pink)
                    Text("\(CountRecordLogic.formatMetric(pro.rounds))/\(CountRecordLogic.formatMetric(pro.target))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(RealtimeV4Palette.sandTrack)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: pro.reached
                                    ? [Color(hex: "#10B981"), Color(hex: "#059669")]
                                    : [SandProAccent.pink, SandProAccent.rose],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(pro.progressPct / 100))
                }
            }
            .frame(height: 8)

            HStack(spacing: 8) {
                compareChip(
                    title: "vs \(pro.priorLabel)",
                    label: pctLabel(pro.roundsVsPriorPct),
                    isUp: (pro.roundsVsPriorPct ?? 0) >= 0
                )
                compareChip(
                    title: "จังหวะ",
                    label: paceLabel(pro.paceVsPriorPct),
                    isUp: (pro.paceVsPriorPct ?? 0) <= 0,
                    upIsGood: true
                )
                compareChip(
                    title: "vs เฉลี่ย 7 วัน",
                    label: pctLabel(pro.roundsVsAvg7Pct),
                    isUp: (pro.roundsVsAvg7Pct ?? 0) >= 0
                )
            }

            if let cta = pro.ctaTitle {
                NavigationLink {
                    CountRecordHubView(initialMode: .sand)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text(cta)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [SandProAccent.pink, SandProAccent.violet],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            } else if pro.hasSandData {
                Button {
                    onOpenDetail?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("งานร่อนถึงเป้า · ดูรายละเอียด")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#059669"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#059669").opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(SandProCardBackground())
    }

    private var healthBadge: some View {
        Image(systemName: pro.paceHealth.systemImage)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
                LinearGradient(
                    colors: healthColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
    }

    private var healthColors: [Color] {
        switch pro.paceHealth {
        case .steady: return [Color(hex: "#10B981"), Color(hex: "#059669")]
        case .moderate: return [SandProAccent.pink, SandProAccent.rose]
        case .uneven: return [Color(hex: "#F59E0B"), Color(hex: "#EA580C")]
        case .unknown: return [Color(hex: "#94A3B8"), Color(hex: "#64748B")]
        }
    }

    private func compareChip(title: String, label: String, isUp: Bool, upIsGood: Bool = true) -> some View {
        let good = upIsGood ? isUp : !isUp
        return VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(RealtimeV4Palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(label == "—" ? RealtimeV4Palette.inkMuted : (good ? Color(hex: "#15803D") : Color(hex: "#B91C1C")))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RealtimeV4Palette.cardSoft)
        )
    }

    private func pctLabel(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(pct.rounded()))%"
    }

    private func paceLabel(_ pct: Double?) -> String {
        guard let pct else { return "—" }
        // Positive pace delta = slower intervals.
        if pct > 0 { return "ช้า +\(Int(pct.rounded()))%" }
        if pct < 0 { return "เร็ว \(abs(Int(pct.rounded())))%" }
        return "เท่าเดิม"
    }
}

// MARK: - Quick actions

struct SandProQuickActionsRow: View {
    var body: some View {
        HStack(spacing: 8) {
            NavigationLink {
                CountRecordHubView(initialMode: .sand)
            } label: {
                actionLabel(title: "นับร่อน", systemImage: "drop.fill", accent: SandProAccent.pink)
            }
            .buttonStyle(.plain)

            NavigationLink {
                OpsTrendProAnalysisView(focus: .sand)
            } label: {
                actionLabel(title: "วิเคราะห์ Pro", systemImage: "chart.xyaxis.line", accent: SandProAccent.violet)
            }
            .buttonStyle(.plain)

            NavigationLink {
                FuelHubView()
            } label: {
                actionLabel(title: "น้ำมัน", systemImage: "fuelpump.fill", accent: AppTheme.fuel)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(title: String, systemImage: String, accent: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
        .accessibilityLabel(title)
    }
}

// MARK: - Insights

struct SandProInsightStrip: View {
    let insights: [String]

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("สัญญาณร่อน", systemImage: "lightbulb.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SandProAccent.pink)

                ForEach(Array(insights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(SandProAccent.pink)
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(RealtimeV4Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .background(SandProCardBackground())
        }
    }
}

// MARK: - Pace card

struct SandProPaceCard: View {
    let pro: SandProSnapshot
    let analytics: CountRecordAnalytics.ModeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("สถานะจังหวะ", systemImage: pro.paceHealth.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Spacer(minLength: 0)
                Text(pro.paceHealth.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SandProAccent.pink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(SandProAccent.pink.opacity(0.12)))
            }

            HStack(spacing: 8) {
                miniStat("คิว/ชม.", pro.perHour.map { String(format: "%.1f", $0) } ?? "—")
                miniStat(
                    "จังหวะเฉลี่ย",
                    CountRecordAnalytics.formatPace(analytics.stats.avg)
                )
                miniStat(
                    "นิ่งในแบนด์",
                    pro.consistencyPct.map { "\(Int($0.rounded()))%" } ?? "—"
                )
            }

            if pro.sparkline.count >= 2 {
                SandProSparkline(values: pro.sparkline, accent: SandProAccent.pink)
                    .frame(height: 36)
                    .accessibilityLabel("แนวโน้มจังหวะล่าสุด")
            }

            if analytics.rounds > 0 {
                RealtimeV4AnalyticsPanel(
                    analytics: analytics,
                    accent: Color(hex: "#F472B6"),
                    chartsAlwaysExpanded: false
                )
            }
        }
        .padding(14)
        .background(SandProCardBackground())
    }

    private func miniStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(RealtimeV4Palette.inkFaint)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(RealtimeV4Palette.cardSoft)
        )
    }
}

// MARK: - Trip balance

struct SandProTripBalanceCard: View {
    let pro: SandProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("คู่ขนานเที่ยวรถ", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.ink)

            HStack(spacing: 8) {
                balancePill(
                    title: "คิวร่อน",
                    value: CountRecordLogic.formatMetric(pro.rounds),
                    accent: SandProAccent.pink
                )
                balancePill(
                    title: "คิวจากเที่ยว",
                    value: CountRecordLogic.formatMetric(pro.tripQueueCubic),
                    accent: SandProAccent.trip
                )
            }

            Text(balanceMessage)
                .font(.caption)
                .foregroundStyle(RealtimeV4Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("อ้างอิง \(CountRecordLogic.queuePerTrip) คิว / 1 เที่ยว · \(CountRecordLogic.formatMetric(pro.tripRounds)) เที่ยว")
                .font(.caption2)
                .foregroundStyle(RealtimeV4Palette.inkFaint)
        }
        .padding(14)
        .background(SandProCardBackground())
    }

    private var balanceMessage: String {
        switch pro.balance {
        case .sandAhead:
            return "ร่อนนำอยู่ \(CountRecordLogic.formatMetric(pro.balanceDelta)) คิว — ทรายอาจค้างกอง"
        case .tripAhead:
            return "เที่ยวนำอยู่ \(CountRecordLogic.formatMetric(-pro.balanceDelta)) คิว — อาจขาดทรายล้าง"
        case .balanced:
            return "คิวร่อนกับคิวจากเที่ยวสมดุลกันดี"
        case .none:
            return "ยังไม่มีข้อมูลเที่ยวหรือร่อนเพียงพอสำหรับเทียบ"
        }
    }

    private func balancePill(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.title3.weight(.black).monospacedDigit())
                .foregroundStyle(RealtimeV4Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.1))
        )
    }
}

// MARK: - Drums

struct SandProDrumsCard: View {
    let pro: SandProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ถังทรายวันนี้", systemImage: "cylinder.split.1x2")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.ink)

            HStack(spacing: 8) {
                drumChip("ได้", pro.drumsObtained, Color(hex: "#0D9488"))
                drumChip("ล้างบ้าน", pro.drumsHome, Color(hex: "#EA580C"))
                drumChip("คงเหลือ", pro.drumsNet, SandProAccent.pink)
            }

            if pro.washedCubic > 0 {
                Text("ล้างรวม \(DashboardAggregations.formatNumber(pro.washedCubic)) คิว")
                    .font(.caption)
                    .foregroundStyle(RealtimeV4Palette.inkMuted)
            }
        }
        .padding(14)
        .background(SandProCardBackground())
    }

    private func drumChip(_ title: String, _ value: Double, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            Text(DashboardAggregations.formatNumber(value))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(RealtimeV4Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.1))
        )
    }
}

// MARK: - Peak teaser

struct SandProPeakTeaser: View {
    let pro: SandProSnapshot

    var body: some View {
        if let peak = pro.peakHourLabel {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(SandProAccent.rose)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(SandProAccent.rose.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("ชั่วโมงพีค")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                    Text(peak)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.ink)
                    if let count = pro.peakHourCount {
                        Text("\(CountRecordLogic.formatMetric(count)) รอบในช่วงนี้")
                            .font(.caption2)
                            .foregroundStyle(RealtimeV4Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(SandProCardBackground())
        }
    }
}

// MARK: - Analytics Pro link

struct SandProAnalyticsLinkCard: View {
    var body: some View {
        NavigationLink {
            OpsTrendProAnalysisView(focus: .sand)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [SandProAccent.pink, SandProAccent.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    Image(systemName: "chart.xyaxis.line")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("วิเคราะห์ Pro · ร่อนทราย")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text("PRO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SandProAccent.pink))
                    }
                    Text("สัปดาห์ · คะแนน · พีคชั่วโมง · แผนเร่งจังหวะ")
                        .font(.caption)
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.inkFaint)
            }
            .padding(14)
            .background(SandProCardBackground())
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SandProAccent.pink.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เปิดวิเคราะห์ Pro ร่อนทราย")
    }
}

// MARK: - Sparkline

private struct SandProSparkline: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.001)
            let minV = values.min() ?? 0
            let span = max(maxV - minV, 0.001)
            Path { path in
                for (i, v) in values.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1))
                    let y = geo.size.height * (1 - CGFloat((v - minV) / span))
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Card chrome

private struct SandProCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [RealtimeV4Palette.sandPanelTop, RealtimeV4Palette.sandPanelBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SandProAccent.pink.opacity(0.18), lineWidth: 1)
            )
    }
}
