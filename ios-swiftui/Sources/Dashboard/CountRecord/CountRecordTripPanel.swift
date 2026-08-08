import SwiftUI

struct CountRecordTripPanel: View {
    let session: CountRecordSession
    let employees: [Employee]
    let onRecord: (CountRecordTripDraft) -> Void
    let onUndo: (CountRecordTripDraft) -> Void
    let onAddVehicle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("นับเที่ยวรถ", systemImage: "truck.box.fill")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#1565C0"))
                Spacer()
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
                ForEach(session.tripUnits) { unit in
                    tripCard(unit)
                }
            }
        }
    }

    private func tripCard(_ unit: CountRecordTripDraft) -> some View {
        let periods = unit.periodSplit
        let driver = CountRecordLogic.driverDisplayName(unit.driverId, employees: employees)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.vehicleId)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("คนขับ: \(driver)")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Spacer()
                Text("\(unit.rounds)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#1565C0"))
                Text("เที่ยว")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            HStack(spacing: 8) {
                periodChip("เช้า", periods.morning, Color(hex: "#1565C0"))
                periodChip("บ่าย", periods.afternoon, Color(hex: "#2E7D32"))
                periodChip("เย็น", periods.ot, Color(hex: "#E65100"))
                Spacer()
                Button {
                    onUndo(unit)
                } label: {
                    Label("เลิกทำ", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(unit.busy || unit.rounds <= 0)
            }

            Button {
                onRecord(unit)
            } label: {
                Text(unit.busy ? "กำลังบันทึก…" : "แตะเพื่อ +1 เที่ยว")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "#1565C0"))
            .disabled(unit.busy)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func periodChip(_ title: String, _ value: Int, _ color: Color) -> some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
