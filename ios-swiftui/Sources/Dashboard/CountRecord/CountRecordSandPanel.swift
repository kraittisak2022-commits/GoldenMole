import SwiftUI

struct CountRecordSandPanel: View {
    let session: CountRecordSession
    let onRecord: () -> Void
    let onLongPressUndo: () -> Void
    let onDeleteLap: (String) -> Void
    let onEditLaps: () -> Void

    private var target: Int { CountRecordLogic.sandTarget }

    private var eta: CountRecordAnalytics.SandTargetEta {
        CountRecordAnalytics.computeSandTargetEta(
            lapTimes: session.sandUnit?.lapTimes ?? [],
            dayKey: session.dayKey,
            target: target
        )
    }

    var body: some View {
        let unit = session.sandUnit
        let rounds = unit?.rounds ?? 0
        let pct = target > 0 ? min(Double(rounds) / Double(target) * 100, 100) : 0
        let accent = Color(hex: "#AD1457")

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("นับร่อนทราย", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
                if let combo = unit?.comboCount, combo > 1 {
                    Text("×\(combo)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.15), in: Capsule())
                        .foregroundStyle(accent)
                }
                Button("แก้ไขรอบ") { onEditLaps() }
                    .font(.caption.weight(.semibold))
                    .disabled((unit?.lapTimes.isEmpty) ?? true)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining: Int = {
                    guard let until = unit?.cooldownUntil else { return 0 }
                    return max(0, Int(ceil(until.timeIntervalSince(context.date))))
                }()
                Button(action: onRecord) {
                    VStack(spacing: 6) {
                        Text("\(rounds)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                        Text(sandButtonLabel(unit, cooldownLeft: remaining))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#AD1457"), Color(hex: "#C2185B")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(unit?.busy == true || remaining > 0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 3).onEnded { _ in
                        onLongPressUndo()
                    }
                )
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: rounds)

            targetProgressCard(rounds: rounds, pct: pct, accent: accent)

            if let recent = unit?.recentLaps, !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("รอบล่าสุด · กดค้างเพื่อลบ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(recent.enumerated()), id: \.offset) { _, stamp in
                                Text(CountRecordLogic.formatLapClock(stamp) ?? stamp)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(accent.opacity(0.12), in: Capsule())
                                    .foregroundStyle(accent)
                                    .onLongPressGesture {
                                        onDeleteLap(stamp)
                                    }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func targetProgressCard(rounds: Int, pct: Double, accent: Color) -> some View {
        let snapshot = eta
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("เป้าหมาย \(CountRecordLogic.formatMetric(target)) คิว/วัน")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
                Text("\(rounds) / \(target) · \(Int(pct.rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: snapshot.reached
                                    ? [Color(hex: "#059669"), Color(hex: "#10B981")]
                                    : [Color(hex: "#AD1457"), Color(hex: "#EC4899")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(pct / 100))
                }
            }
            .frame(height: 8)

            if snapshot.reached {
                Label("ถึงเป้า \(target) คิวแล้ว", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "#059669"))
            } else if let clock = snapshot.etaClock {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                    Text("คาดการณ์ถึงเป้าประมาณ \(clock)")
                        .fontWeight(.semibold)
                    if let hoursLeft = snapshot.hoursLeft {
                        Text("· ~\(CountRecordAnalytics.formatDurationHours(hoursLeft))")
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }
                .font(.caption)
                .foregroundStyle(accent)
            } else {
                Text("นับอย่างน้อย 2 คิว เพื่อคาดการณ์เวลาถึงเป้า")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.06))
        )
    }

    private func sandButtonLabel(_ unit: CountRecordSandDraft?, cooldownLeft: Int) -> String {
        if unit?.busy == true { return "กำลังบันทึก…" }
        if cooldownLeft > 0 { return "รอ \(cooldownLeft) วิ…" }
        return "แตะเพื่อ +1 คิว · กดค้างเลิกทำ"
    }
}
