import SwiftUI

/// Interactive leave hub — Flutter «ลางาน» parity (add / edit / delete).
struct LeaveHubView: View {
    @Environment(AppState.self) private var appState
    @State private var session = LeaveSession()
    @FocusState private var reasonFocused: Bool

    private var sync: CountRecordOfflineSync { .shared }
    private var accent: Color { Color(red: 0.0, green: 0.537, blue: 0.482) } // #00897B
    private var accentDeep: Color { Color(red: 0.0, green: 0.412, blue: 0.361) } // #00695C

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            statusBanner(session)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formCard(session)
                    historySection(session)
                }
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(DashboardBackground())
        .navigationTitle("ลางาน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if session.draft.isPersisted {
                    Button("ใหม่") { session.clearDraft() }
                }
                if sync.failedCount > 0 {
                    Button { session.showFailedQueue = true } label: {
                        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                            .foregroundStyle(AppTheme.expense)
                    }
                }
                if sync.pendingCount > 0 {
                    Button { sync.syncNow() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
        .sheet(isPresented: $session.showFailedQueue) {
            CountRecordFailedQueueSheet(sync: sync)
        }
        .sheet(isPresented: $session.showDateRangeSheet) {
            LeaveDateRangeSheet(
                startYmd: session.draft.startYmd,
                endYmd: session.draft.endYmd,
                halfDayLocked: session.draft.isHalfDay,
                accent: accent
            ) { start, end in
                session.applyDateRange(start: start, end: end)
            }
        }
        .confirmationDialog(
            "ลบรายการลางานนี้?",
            isPresented: Binding(
                get: { session.confirmDeleteId != nil },
                set: { if !$0 { session.confirmDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ลบ", role: .destructive) {
                if let id = session.confirmDeleteId {
                    Task { await session.delete(id: id, appState: appState) }
                }
                session.confirmDeleteId = nil
            }
            Button("ยกเลิก", role: .cancel) { session.confirmDeleteId = nil }
        }
        .task {
            if let service = appState.supabaseService {
                session.configureOffline(service: service, appState: appState)
            }
            session.reload(appState: appState, force: true)
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            session.reload(appState: appState)
        }
        .onChange(of: appState.employees.map(\.id)) { _, _ in
            session.reload(appState: appState, force: true)
        }
    }

    // MARK: - Form

    private func formCard(_ session: LeaveSession) -> some View {
        @Bindable var session = session
        let rangeLabel: String = {
            if session.draft.endYmd > session.draft.startYmd {
                return "\(LeaveLogic.formatThaiYmd(session.draft.startYmd)) - \(LeaveLogic.formatThaiYmd(session.draft.endYmd))"
            }
            return "เริ่ม \(LeaveLogic.formatThaiYmd(session.draft.startYmd))"
        }()
        let summaryDuration = session.draft.isHalfDay
            ? "ครึ่งวัน (\(session.draft.halfPart.label))"
            : "\(session.draft.rangeDayCount) วัน"

        return VStack(alignment: .leading, spacing: 14) {
            Text("บันทึกลางาน")
                .font(.title2.weight(.bold))
                .foregroundStyle(accentDeep)

            if session.draft.isPersisted {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.and.list.clipboard")
                        .foregroundStyle(AppTheme.info)
                    Text("กำลังแก้ไขรายการเดิม — กดบันทึกการแก้ไขเมื่อเสร็จ")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.05, green: 0.28, blue: 0.63))
                    Spacer(minLength: 0)
                    Button("ยกเลิก") { session.clearDraft() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.info)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(red: 0.89, green: 0.95, blue: 0.99))
                )
            }

            Text("รูปแบบสอดคล้องเว็บแอพ: ค่าแรง/ลา → ลา")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)

            fieldLabel("ประเภทการลา")
            Picker("leaveType", selection: $session.draft.leaveType) {
                ForEach(LeaveLogic.LeaveType.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)

            fieldLabel("ระยะเวลาลา")
            Picker("duration", selection: Binding(
                get: { session.draft.isHalfDay },
                set: { session.setHalfDay($0) }
            )) {
                Text("เต็มวัน").tag(false)
                Text("ครึ่งวัน").tag(true)
            }
            .pickerStyle(.segmented)

            if session.draft.isHalfDay {
                fieldLabel("ช่วงครึ่งวัน")
                Picker("half", selection: $session.draft.halfPart) {
                    ForEach(LeaveLogic.HalfPart.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            fieldLabel("ช่วงวันลา")
            Button {
                session.showDateRangeSheet = true
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(
                        session.draft.endYmd > session.draft.startYmd
                        ? "\(LeaveLogic.formatThaiYmd(session.draft.startYmd)) → \(LeaveLogic.formatThaiYmd(session.draft.endYmd))"
                        : LeaveLogic.formatThaiYmd(session.draft.startYmd)
                    )
                    .font(.body.weight(.heavy))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(accentDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.55), lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(accentDeep)
                Text(
                    session.draft.isHalfDay
                    ? "รวม 0.5 วัน (ครึ่งวัน — \(session.draft.halfPart.label))"
                    : "รวม \(session.draft.rangeDayCount) วัน"
                )
                .font(.body.weight(.heavy))
                .foregroundStyle(accentDeep)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.88, green: 0.95, blue: 0.945))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.45), lineWidth: 1)
            )

            fieldLabel("เลือกพนักงาน")
            Text("แสดงเฉพาะตำแหน่ง: พนักงานท่าทราย, คนขับรถแม็คโคร")
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)

            if session.eligibleEmployees.isEmpty {
                Text("ยังไม่พบพนักงานท่าทราย/คนขับรถแม็คโคร — ตรวจตำแหน่งงานที่เมนูพนักงาน")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.54, green: 0.42, blue: 0.17))
                    .padding(.vertical, 8)
            } else {
                FlexibleChipWrap(spacing: 8) {
                    ForEach(session.eligibleEmployees) { emp in
                        let selected = session.draft.employeeIds.contains(emp.id)
                        Button {
                            session.toggleEmployee(emp.id)
                        } label: {
                            Text(emp.displayName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .foregroundStyle(selected ? .white : AppTheme.ink)
                                .background(
                                    Capsule().fill(selected ? accent : AppTheme.surfaceSoft)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            fieldLabel("เหตุผลการลา (ไม่บังคับ)")
            TextField("ไม่ใส่ก็บันทึกได้", text: $session.draft.reason)
                .focused($reasonFocused)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.surfaceSoft)
                )
                .submitLabel(.done)
                .onSubmit {
                    reasonFocused = false
                    Task { await session.save(appState: appState) }
                }

            if session.draft.isHalfDay
                || session.draft.rangeDayCount > 0
                || !session.draft.employeeIds.isEmpty {
                Text("สรุป: \(session.draft.employeeIds.count) คน · \(rangeLabel) · \(summaryDuration)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(red: 0.48, green: 0.42, blue: 0.29))
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.973, blue: 0.925))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(red: 0.95, green: 0.83, blue: 0.62), lineWidth: 1)
                    )
            }

            Button {
                reasonFocused = false
                Task { await session.save(appState: appState) }
            } label: {
                Label(
                    session.isSaving
                    ? "กำลังบันทึก..."
                    : (session.draft.isPersisted ? "บันทึกการแก้ไข" : "บันทึกลางาน"),
                    systemImage: "square.and.arrow.down"
                )
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(session.isSaving)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - History

    private func historySection(_ session: LeaveSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("รายการลาที่ครอบคลุมวันนี้")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if session.coveringLeaves.isEmpty {
                Text("ยังไม่มีบันทึกลางานวันนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                ForEach(session.coveringLeaves) { t in
                    leaveRow(t, session: session)
                }
            }
        }
    }

    private func leaveRow(_ t: Transaction, session: LeaveSession) -> some View {
        let names = LeaveLogic.employeeNames(ids: t.employeeIds ?? [], employees: appState.employees)
        let reason = LeaveLogic.resolvedReason(t)
        let duration = LeaveLogic.durationLabel(t)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                session.loadForEdit(t)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(LeaveLogic.typeLabel(t))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accentDeep)
                        if !duration.isEmpty {
                            Text(duration)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accent.opacity(0.12)))
                                .foregroundStyle(accentDeep)
                        }
                        Spacer(minLength: 0)
                        Text(LeaveLogic.formatThaiYmd(String(t.date.prefix(10))))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    Text(names.isEmpty ? "—" : names)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    if !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkMuted)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack {
                Text("แตะเพื่อแก้ไข")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                Button("ลบ", role: .destructive) {
                    session.confirmDeleteId = t.id
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    session.draft.txId == t.id ? accent.opacity(0.7) : accent.opacity(0.15),
                    lineWidth: session.draft.txId == t.id ? 1.6 : 1
                )
        )
    }

    // MARK: - Bits

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(red: 0.19, green: 0.30, blue: 0.43))
    }

    private func statusBanner(_ session: LeaveSession) -> some View {
        Group {
            if let msg = session.statusMessage {
                Text(msg)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.isErrorStatus ? AppTheme.expense : AppTheme.income)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppTheme.spaceLG)
                    .padding(.top, 8)
            }
            if !sync.isOnline || sync.pendingCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: sync.isOnline ? "icloud.and.arrow.up" : "wifi.slash")
                    Text(sync.isOnline
                         ? "รอซิงก์ \(sync.pendingCount) รายการ"
                         : "ออฟไลน์ — บันทึกเข้าคิวแล้วซิงก์ภายหลัง")
                        .font(.caption.weight(.medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(AppTheme.inkMuted)
                .padding(.horizontal, AppTheme.spaceLG)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Date range sheet

private struct LeaveDateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    let halfDayLocked: Bool
    let accent: Color
    let onApply: (Date, Date) -> Void

    init(
        startYmd: String,
        endYmd: String,
        halfDayLocked: Bool,
        accent: Color,
        onApply: @escaping (Date, Date) -> Void
    ) {
        let s = LeaveLogic.date(fromYmd: startYmd) ?? Date()
        let e = LeaveLogic.date(fromYmd: endYmd) ?? s
        _start = State(initialValue: s)
        _end = State(initialValue: halfDayLocked ? s : e)
        self.halfDayLocked = halfDayLocked
        self.accent = accent
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("วันเริ่มลา", selection: $start, displayedComponents: .date)
                    .onChange(of: start) { _, new in
                        if halfDayLocked || end < new { end = new }
                    }
                if halfDayLocked {
                    Text("ครึ่งวันใช้วันเดียวเท่านั้น")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker("วันสุดท้าย", selection: $end, in: start..., displayedComponents: .date)
                }
            }
            .navigationTitle("เลือกช่วงวันลา")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("ตกลง") {
                        onApply(start, halfDayLocked ? start : end)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(accent)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
