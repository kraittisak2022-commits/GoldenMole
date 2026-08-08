import SwiftUI

struct CountRecordSandPanel: View {
    let session: CountRecordSession
    let onRecord: () -> Void
    let onLongPressUndo: () -> Void
    let onDeleteLap: (String) -> Void

    var body: some View {
        let unit = session.sandUnit
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("นับร่อนทราย", systemImage: "drop.fill")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#AD1457"))
                Spacer()
                if let combo = unit?.comboCount, combo > 1 {
                    Text("×\(combo)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#AD1457").opacity(0.15), in: Capsule())
                        .foregroundStyle(Color(hex: "#AD1457"))
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining: Int = {
                    guard let until = unit?.cooldownUntil else { return 0 }
                    return max(0, Int(ceil(until.timeIntervalSince(context.date))))
                }()
                Button(action: onRecord) {
                    VStack(spacing: 6) {
                        Text("\(unit?.rounds ?? 0)")
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
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: unit?.rounds ?? 0)

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
                                    .background(Color(hex: "#AD1457").opacity(0.12), in: Capsule())
                                    .foregroundStyle(Color(hex: "#AD1457"))
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
                .strokeBorder(Color(hex: "#AD1457").opacity(0.25), lineWidth: 1)
        )
    }

    private func sandButtonLabel(_ unit: CountRecordSandDraft?, cooldownLeft: Int) -> String {
        if unit?.busy == true { return "กำลังบันทึก…" }
        if cooldownLeft > 0 { return "รอ \(cooldownLeft) วิ…" }
        return "แตะเพื่อ +1 รอบ · กดค้างเลิกทำ"
    }
}
