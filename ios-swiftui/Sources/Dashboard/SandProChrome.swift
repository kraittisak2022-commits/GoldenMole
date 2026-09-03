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

            if pro.hasSandData {
                Button {
                    onOpenDetail?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: pro.reached ? "checkmark.seal.fill" : "chart.bar.fill")
                        Text(pro.reached ? "งานร่อนถึงเป้า · ดูรายละเอียด" : "ดูรายละเอียดร่อนทราย")
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.caption)
                    .foregroundStyle(pro.reached ? Color(hex: "#059669") : SandProAccent.pink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill((pro.reached ? Color(hex: "#059669") : SandProAccent.pink).opacity(0.12))
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
