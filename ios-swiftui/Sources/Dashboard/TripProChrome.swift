import SwiftUI

// MARK: - Accent

private enum TripProAccent {
    static let blue = Color(hex: "#2563EB")
    static let indigo = Color(hex: "#4338CA")
    static let cyan = Color(hex: "#0891B2")
    static let sand = Color(hex: "#DB2777")
}

// MARK: - Command strip

struct TripProCommandStrip: View {
    let pro: TripProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                healthBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text("COMMAND · เที่ยวรถ")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(TripProAccent.blue)
                    Text(pro.paceHealth.label)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.ink)
                    if let eta = pro.etaClock, !pro.reached {
                        Text("เป้า ~\(eta)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    } else if pro.reached {
                        Text("ถึงเป้าแล้ว · \(pro.vehicleCount) คัน")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(hex: "#059669"))
                    } else {
                        Text("\(pro.vehicleCount) คันที่นับ")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(pro.progressPct.rounded()))%")
                        .font(.title3.weight(.black).monospacedDigit())
                        .foregroundStyle(TripProAccent.blue)
                    Text("\(CountRecordLogic.formatMetric(pro.rounds))/\(CountRecordLogic.formatMetric(pro.target))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(light: Color(hex: "#DBEAFE"), dark: TripProAccent.blue.opacity(0.2)))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: pro.reached
                                    ? [Color(hex: "#10B981"), Color(hex: "#059669")]
                                    : [TripProAccent.blue, TripProAccent.indigo],
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
                    isUp: (pro.paceVsPriorPct ?? 0) <= 0
                )
                compareChip(
                    title: "vs เฉลี่ย 7 วัน",
                    label: pctLabel(pro.roundsVsAvg7Pct),
                    isUp: (pro.roundsVsAvg7Pct ?? 0) >= 0
                )
            }
        }
        .padding(14)
        .background(TripProCardBackground())
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
        case .moderate: return [TripProAccent.blue, TripProAccent.indigo]
        case .uneven: return [Color(hex: "#F59E0B"), Color(hex: "#EA580C")]
        case .unknown: return [Color(hex: "#94A3B8"), Color(hex: "#64748B")]
        }
    }

    private func compareChip(title: String, label: String, isUp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(RealtimeV4Palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(label == "—" ? RealtimeV4Palette.inkMuted : (isUp ? Color(hex: "#15803D") : Color(hex: "#B91C1C")))
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
        if pct > 0 { return "ช้า +\(Int(pct.rounded()))%" }
        if pct < 0 { return "เร็ว \(abs(Int(pct.rounded())))%" }
        return "เท่าเดิม"
    }
}

// MARK: - Insights

struct TripProInsightStrip: View {
    let insights: [String]

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("สัญญาณเที่ยว", systemImage: "lightbulb.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TripProAccent.blue)

                ForEach(Array(insights.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(TripProAccent.blue)
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
            .background(TripProCardBackground())
        }
    }
}

// MARK: - Efficiency

struct TripProEfficiencyCard: View {
    let pro: TripProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("ประสิทธิภาพฝูงรถ", systemImage: "gauge.with.needle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.ink)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("เที่ยว / คัน")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TripProAccent.blue)
                    Text(String(format: "%.1f", pro.efficiencyPerVeh))
                        .font(.title3.weight(.black).monospacedDigit())
                        .foregroundStyle(RealtimeV4Palette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TripProAccent.blue.opacity(0.1))
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("เทียบ\(effPrior)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let pct = pro.efficiencyDeltaPct {
                        Text("\(pct >= 0 ? "+" : "")\(Int(pct.rounded()))%")
                            .font(.title3.weight(.black).monospacedDigit())
                            .foregroundStyle(pct >= 0 ? Color(hex: "#15803D") : Color(hex: "#B91C1C"))
                    } else {
                        Text("—")
                            .font(.title3.weight(.black))
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(RealtimeV4Palette.cardSoft)
                )
            }

            Text("\(pro.vehicleCount) คันที่นับ · คิวรวม \(CountRecordLogic.formatMetric(pro.queueCubic))")
                .font(.caption)
                .foregroundStyle(RealtimeV4Palette.inkMuted)
        }
        .padding(14)
        .background(TripProCardBackground())
    }

    private var effPrior: String {
        if pro.efficiencyPriorLabel.isEmpty { return pro.priorLabel }
        return pro.efficiencyIsCalendarYesterday ? "เมื่อวาน" : pro.efficiencyPriorLabel
    }
}

// MARK: - Leaderboard

struct TripProLeaderboardCard: View {
    let leaders: [TripProSnapshot.LeaderRow]

    var body: some View {
        if !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("กระดานผู้นำ", systemImage: "trophy.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.ink)

                ForEach(leaders) { row in
                    HStack(spacing: 10) {
                        Text(rankGlyph(row.rank))
                            .font(.subheadline.weight(.black))
                            .foregroundStyle(rankColor(row.rank))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.vehicleId)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(RealtimeV4Palette.ink)
                            Text(row.driverLabel.isEmpty ? "—" : row.driverLabel)
                                .font(.caption2)
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(CountRecordLogic.formatMetric(row.rounds))")
                                .font(.subheadline.weight(.black).monospacedDigit())
                                .foregroundStyle(TripProAccent.blue)
                            Text("\(Int(row.sharePct.rounded()))%")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RealtimeV4Palette.inkFaint)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(rankColor(row.rank).opacity(0.08))
                    )
                }
            }
            .padding(14)
            .background(TripProCardBackground())
        }
    }

    private func rankGlyph(_ rank: Int) -> String {
        switch rank {
        case 1: return "1"
        case 2: return "2"
        case 3: return "3"
        default: return "\(rank)"
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(hex: "#EAB308")
        case 2: return Color(hex: "#94A3B8")
        case 3: return Color(hex: "#D97706")
        default: return TripProAccent.blue
        }
    }
}

// MARK: - Idle vehicles

struct TripProIdleCard: View {
    let idleVehicles: [TripProSnapshot.IdleVehicle]

    var body: some View {
        if !idleVehicles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("รถเงียบ / ยังไม่วิ่ง", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(hex: "#EA580C"))

                ForEach(idleVehicles.prefix(4)) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.rounds == 0 ? "truck.box" : "clock.badge.exclamationmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(hex: "#EA580C"))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.vehicleId)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(RealtimeV4Palette.ink)
                            Text(row.driverLabel.isEmpty ? row.reason : "\(row.driverLabel) · \(row.reason)")
                                .font(.caption2)
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        if row.rounds > 0 {
                            Text("\(row.rounds)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(RealtimeV4Palette.inkSecondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "#EA580C").opacity(0.08))
                    )
                }

                if idleVehicles.count > 4 {
                    Text("และอีก \(idleVehicles.count - 4) คัน")
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
            .padding(14)
            .background(TripProCardBackground())
        }
    }
}

// MARK: - Pace

struct TripProPaceCard: View {
    let pro: TripProSnapshot
    let analytics: CountRecordAnalytics.ModeAnalytics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("สถานะจังหวะฝูงรถ", systemImage: pro.paceHealth.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Spacer(minLength: 0)
                Text(pro.paceHealth.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TripProAccent.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(TripProAccent.blue.opacity(0.12)))
            }

            HStack(spacing: 8) {
                miniStat("เที่ยว/ชม.", pro.perHour.map { String(format: "%.1f", $0) } ?? "—")
                miniStat("จังหวะเฉลี่ย", CountRecordAnalytics.formatPace(analytics.stats.avg))
                miniStat("นิ่งในแบนด์", pro.consistencyPct.map { "\(Int($0.rounded()))%" } ?? "—")
            }

            if pro.sparkline.count >= 2 {
                TripProSparkline(values: pro.sparkline, accent: TripProAccent.blue)
                    .frame(height: 36)
                    .accessibilityLabel("แนวโน้มจังหวะล่าสุด")
            }

            if analytics.rounds > 0 {
                RealtimeV4AnalyticsPanel(
                    analytics: analytics,
                    accent: Color(hex: "#38BDF8"),
                    chartsAlwaysExpanded: false
                )
            }
        }
        .padding(14)
        .background(TripProCardBackground())
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

// MARK: - Sand balance

struct TripProSandBalanceCard: View {
    let pro: TripProSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("คู่ขนานร่อนทราย", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RealtimeV4Palette.ink)

            HStack(spacing: 8) {
                balancePill(
                    title: "คิวจากเที่ยว",
                    value: CountRecordLogic.formatMetric(pro.tripQueueCubic),
                    accent: TripProAccent.blue
                )
                balancePill(
                    title: "คิวร่อน",
                    value: CountRecordLogic.formatMetric(pro.sandRounds),
                    accent: TripProAccent.sand
                )
            }

            Text(balanceMessage)
                .font(.caption)
                .foregroundStyle(RealtimeV4Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("อ้างอิง \(CountRecordLogic.queuePerTrip) คิว / 1 เที่ยว · \(CountRecordLogic.formatMetric(pro.rounds)) เที่ยว")
                .font(.caption2)
                .foregroundStyle(RealtimeV4Palette.inkFaint)
        }
        .padding(14)
        .background(TripProCardBackground())
    }

    private var balanceMessage: String {
        switch pro.balance {
        case .sandAhead:
            return "ร่อนนำอยู่ \(CountRecordLogic.formatMetric(pro.balanceDelta)) คิว — ทรายอาจค้างกอง"
        case .tripAhead:
            return "เที่ยวนำอยู่ \(CountRecordLogic.formatMetric(-pro.balanceDelta)) คิว — อาจขาดทรายล้าง"
        case .balanced:
            return "คิวจากเที่ยวกับคิวร่อนสมดุลกันดี"
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

// MARK: - Peak

struct TripProPeakTeaser: View {
    let pro: TripProSnapshot

    var body: some View {
        if let peak = pro.peakHourLabel {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(TripProAccent.cyan)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TripProAccent.cyan.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("ชั่วโมงพีค")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.inkMuted)
                    Text(peak)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(RealtimeV4Palette.ink)
                    if let count = pro.peakHourCount {
                        Text("\(CountRecordLogic.formatMetric(count)) เที่ยวในช่วงนี้")
                            .font(.caption2)
                            .foregroundStyle(RealtimeV4Palette.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(TripProCardBackground())
        }
    }
}

// MARK: - Sparkline

private struct TripProSparkline: View {
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

private struct TripProCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(light: Color(hex: "#EFF6FF"), dark: Color(hex: "#0B1220")),
                        Color(light: Color(hex: "#DBEAFE"), dark: Color(hex: "#111827")),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(TripProAccent.blue.opacity(0.18), lineWidth: 1)
            )
    }
}
