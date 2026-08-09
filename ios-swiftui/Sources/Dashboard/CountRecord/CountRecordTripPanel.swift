import SwiftUI

struct CountRecordTripPanel: View {
    let session: CountRecordSession
    let employees: [Employee]
    let onRecord: (CountRecordTripDraft) -> Void
    let onLongPressUndo: (CountRecordTripDraft) -> Void
    let onAddVehicle: () -> Void
    let onEdit: (CountRecordTripDraft) -> Void
    let onEditLaps: (CountRecordTripDraft) -> Void
    let onRemove: (CountRecordTripDraft) -> Void
    let onOpenSettings: () -> Void

    private var columns: [GridItem] {
        let count = session.tripUnits.count
        if count <= 2 { return [GridItem(.flexible())] }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("นับเที่ยวรถ", systemImage: "truck.box.fill")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#1565C0"))
                Spacer()
                let total = session.tripUnits.reduce(0) { $0 + $1.rounds }
                Text("\(total) เที่ยว")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
                Button(action: onOpenSettings) {
                    Label("ตั้งค่า", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: "#1565C0"))
                .accessibilityLabel("ตั้งค่านับจำนวน")
                Button(action: onAddVehicle) {
                    Label("เพิ่มคัน", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#1565C0"))
            }

            if session.tripUnits.isEmpty {
                Text("ยังไม่มีรถในวันนี้ — กด «เพิ่มคัน» เพื่อเริ่มนับ")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(session.tripUnits.enumerated()), id: \.element.id) { index, unit in
                        tripCard(unit, colorIndex: index)
                    }
                }
            }
        }
    }

    private func tripCard(_ unit: CountRecordTripDraft, colorIndex: Int) -> some View {
        let accent = Color(hex: CountRecordLogic.vehicleColors[colorIndex % CountRecordLogic.vehicleColors.count])
        let periods = unit.periodSplit
        let driver = CountRecordLogic.driverDisplayName(unit.driverId, employees: employees)
        let goal = CountRecordPrefs.tripGoal
        let progress = goal > 0 ? min(1, Double(unit.rounds) / Double(goal)) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.vehicleId)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(driver)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    Button("แก้ไขรอบ / เวลา…") { onEditLaps(unit) }
                    Button("จัดการรถ…") { onEdit(unit) }
                    Button("ลบคัน", role: .destructive) { onRemove(unit) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }

            HStack(spacing: 6) {
                if unit.isSupport {
                    badge("ชัพพอต", AppTheme.slate)
                }
                if unit.isBroken {
                    badge("รถเสีย", AppTheme.expense)
                }
                if unit.comboCount > 1 {
                    badge("×\(unit.comboCount)", accent)
                }
                if goal > 0 && unit.rounds >= goal {
                    badge("ครบเป้า", Color(hex: "#C9A227"))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(unit.rounds)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                Text("เที่ยว")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
            }

            if goal > 0 {
                ProgressView(value: progress)
                    .tint(unit.rounds >= goal ? Color(hex: "#C9A227") : accent)
            }

            HStack(spacing: 6) {
                periodChip("เช้า", periods.morning, Color(hex: "#1565C0"))
                periodChip("บ่าย", periods.afternoon, Color(hex: "#2E7D32"))
                periodChip("เย็น", periods.ot, Color(hex: "#E65100"))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = cooldownSecondsLeft(unit, now: context.date)
                Button {
                    onRecord(unit)
                } label: {
                    Text(buttonLabel(unit, cooldownLeft: remaining))
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!unit.canRecord || remaining > 0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 3).onEnded { _ in
                        onLongPressUndo(unit)
                    }
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func cooldownSecondsLeft(_ unit: CountRecordTripDraft, now: Date) -> Int {
        guard let until = unit.cooldownUntil else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSince(now))))
    }

    private func buttonLabel(_ unit: CountRecordTripDraft, cooldownLeft: Int) -> String {
        if unit.busy { return "กำลังบันทึก…" }
        if cooldownLeft > 0 { return "รอ \(cooldownLeft) วิ…" }
        if unit.isSupport { return "ชัพพอต" }
        if unit.isBroken { return "รถเสีย" }
        return "แตะ +1 เที่ยว"
    }

    private func periodChip(_ title: String, _ value: Int, _ color: Color) -> some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
