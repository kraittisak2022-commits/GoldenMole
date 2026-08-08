import SwiftUI

/// Edit / delete individual lap timestamps and persist to Supabase.
/// Reads live lap arrays from `session` so deletes/edits refresh the list.
struct CountRecordLapEditorSheet: View {
    let session: CountRecordSession
    /// `nil` = sand editor; otherwise trip unit id.
    let tripUnitId: String?
    let onDelete: (Int) -> Void
    let onUpdate: (_ index: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingIndex: Int?
    @State private var editHour = 0
    @State private var editMinute = 0
    @State private var editSecond = 0
    @State private var confirmDeleteIndex: Int?

    private var title: String {
        if let id = tripUnitId,
           let unit = session.tripUnits.first(where: { $0.id == id }) {
            return "แก้ไขรอบ · \(unit.vehicleId)"
        }
        return "แก้ไขรอบ · ร่อนทราย"
    }

    private var laps: [String] {
        if let id = tripUnitId {
            return session.tripUnits.first(where: { $0.id == id })?.lapTimes ?? []
        }
        return session.sandUnit?.lapTimes ?? []
    }

    private var isBusy: Bool {
        if let id = tripUnitId {
            return session.tripUnits.first(where: { $0.id == id })?.busy ?? false
        }
        return session.sandUnit?.busy ?? false
    }

    var body: some View {
        NavigationStack {
            Group {
                if laps.isEmpty {
                    ContentUnavailableView(
                        "ยังไม่มีรอบ",
                        systemImage: "clock.badge.questionmark",
                        description: Text("กดนับก่อน แล้วกลับมาแก้เวลาหรือลบรอบได้ที่นี่")
                    )
                } else {
                    List {
                        Section {
                            Text("วันที่ \(session.dayKey) · แตะแถวเพื่อแก้เวลา · ปัดซ้ายเพื่อลบ · บันทึกลงฐานข้อมูลทันที")
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        Section("รอบทั้งหมด (\(laps.count))") {
                            ForEach(Array(laps.enumerated()), id: \.offset) { index, stamp in
                                Button {
                                    beginEdit(index: index, stamp: stamp)
                                } label: {
                                    HStack {
                                        Text("#\(index + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(AppTheme.brand)
                                            .frame(width: 36, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stamp)
                                                .font(.body.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(AppTheme.ink)
                                            if let clock = CountRecordLogic.formatLapClock(stamp) {
                                                Text("นาฬิกา \(clock)")
                                                    .font(.caption2)
                                                    .foregroundStyle(AppTheme.inkMuted)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "pencil")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(AppTheme.inkMuted)
                                    }
                                }
                                .disabled(isBusy)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        confirmDeleteIndex = index
                                    } label: {
                                        Label("ลบ", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
            .sheet(isPresented: Binding(
                get: { editingIndex != nil },
                set: { if !$0 { editingIndex = nil } }
            )) {
                timeEditSheet
            }
            .alert("ลบรอบนี้?", isPresented: Binding(
                get: { confirmDeleteIndex != nil },
                set: { if !$0 { confirmDeleteIndex = nil } }
            )) {
                Button("ลบ", role: .destructive) {
                    if let i = confirmDeleteIndex {
                        onDelete(i)
                    }
                    confirmDeleteIndex = nil
                }
                Button("ยกเลิก", role: .cancel) { confirmDeleteIndex = nil }
            } message: {
                if let i = confirmDeleteIndex, laps.indices.contains(i) {
                    Text(laps[i])
                }
            }
        }
    }

    private var timeEditSheet: some View {
        NavigationStack {
            Form {
                if let i = editingIndex, laps.indices.contains(i) {
                    Section("รอบเดิม") {
                        Text(laps[i])
                            .font(.body.monospacedDigit())
                    }
                }
                Section("เวลาใหม่ (วัน \(session.dayKey))") {
                    Stepper("ชั่วโมง \(editHour)", value: $editHour, in: 0...23)
                    Stepper("นาที \(editMinute)", value: $editMinute, in: 0...59)
                    Stepper("วินาที \(editSecond)", value: $editSecond, in: 0...59)
                    if let preview = CountRecordLogic.formatLapStamp(
                        dayKey: session.dayKey,
                        hour: editHour,
                        minute: editMinute,
                        second: editSecond
                    ) {
                        Text("จะบันทึกเป็น \(preview)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.brand)
                    }
                }
            }
            .navigationTitle("แก้เวลารอบ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { editingIndex = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("บันทึก") {
                        if let i = editingIndex {
                            onUpdate(i, editHour, editMinute, editSecond)
                        }
                        editingIndex = nil
                    }
                    .disabled(isBusy)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func beginEdit(index: Int, stamp: String) {
        let comps = CountRecordLogic.lapClockComponents(stamp) ?? (0, 0, 0)
        editHour = comps.hour
        editMinute = comps.minute
        editSecond = comps.second
        editingIndex = index
    }
}
