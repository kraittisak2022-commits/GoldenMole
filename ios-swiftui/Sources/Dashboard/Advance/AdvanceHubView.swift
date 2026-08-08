import SwiftUI

/// Interactive advance hub — Flutter «เบิกเงิน» parity (submit / edit / delete).
struct AdvanceHubView: View {
    @Environment(AppState.self) private var appState
    @State private var session = AdvanceSession()
    @FocusState private var amountFocused: Bool
    @FocusState private var accountFocused: Bool

    private var sync: CountRecordOfflineSync { .shared }
    private var accent: Color { Color(red: 0.902, green: 0.318, blue: 0.0) } // #E65100
    private var accentDeep: Color { Color(red: 0.749, green: 0.212, blue: 0.047) } // #BF360C

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
        .navigationTitle("เบิกเงิน")
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
        .confirmationDialog(
            "ลบคำขอเบิกเงินนี้?",
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
    }

    // MARK: - Form

    private func formCard(_ session: AdvanceSession) -> some View {
        @Bindable var session = session
        let nSel = session.draft.employeeIds.count
        let totalHint = session.draft.estimatedTotal

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 52, height: 52)
                    Image(systemName: "banknote.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.draft.isPersisted ? "แก้ไขคำขอเบิกเงิน" : "ส่งคำขอเบิกเงิน")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color(red: 0.306, green: 0.204, blue: 0.180))
                    Text("เลือกพนักงาน กรอกยอด และรูปแบบรับเงิน แล้วกดส่งด้านล่าง")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.427, green: 0.298, blue: 0.255))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.878, blue: 0.698),
                        Color(red: 1.0, green: 0.800, blue: 0.502),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            VStack(alignment: .leading, spacing: 16) {
                if session.draft.isPersisted {
                    HStack {
                        Text("กำลังแก้ไขรายการเดิม")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.info)
                        Spacer()
                        Button("ยกเลิก") { session.clearDraft() }
                            .font(.caption.weight(.bold))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.info.opacity(0.10))
                    )
                }

                stepHeader("1", title: "เลือกพนักงาน", hint: "เลือกได้หลายคน — เฉพาะพนักงานท่าทรายและคนขับรถแม็คโคร")

                warmPanel {
                    if session.eligibleEmployees.isEmpty {
                        Text("ยังไม่พบพนักงานท่าทราย/คนขับรถแม็คโคร — ตรวจตำแหน่งงานที่เมนูพนักงาน")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.54, green: 0.42, blue: 0.17))
                    } else {
                        FlexibleChipWrap(spacing: 8) {
                            ForEach(session.eligibleEmployees) { emp in
                                let selected = session.draft.employeeIds.contains(emp.id)
                                Button {
                                    session.toggleEmployee(emp.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        if selected {
                                            Image(systemName: "checkmark")
                                                .font(.caption2.weight(.bold))
                                        }
                                        Text(emp.displayName)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(selected ? accentDeep : AppTheme.ink)
                                    .background(
                                        Capsule().fill(selected ? accent.opacity(0.20) : Color.white)
                                    )
                                    .overlay(
                                        Capsule().strokeBorder(
                                            selected ? accent : Color.gray.opacity(0.25),
                                            lineWidth: selected ? 1.8 : 1
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                stepHeader("2", title: "จำนวนเงินที่ขอ (บาทต่อคน)", hint: "ทุกคนที่เลือกใช้ยอดเดียวกัน")

                HStack {
                    Image(systemName: "banknote")
                        .foregroundStyle(accent)
                    TextField("บาทต่อคน", value: $session.draft.amountPerPerson, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .font(.title3.weight(.heavy))
                        .focused($amountFocused)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
                )

                if let totalHint {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.forwardslash.minus")
                            .foregroundStyle(Color(red: 0.106, green: 0.369, blue: 0.125))
                        Text("ประมาณการรวม \(nSel) คน × ฿\(AdvanceLogic.formatBaht(session.draft.amountPerPerson)) = ฿\(AdvanceLogic.formatBaht(totalHint))")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color(red: 0.106, green: 0.369, blue: 0.125))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.910, green: 0.961, blue: 0.914).opacity(0.65))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(red: 0.784, green: 0.902, blue: 0.788), lineWidth: 1)
                    )
                }

                stepHeader("3", title: "รับเงินเมื่อไหร่ และรูปแบบใด", hint: "ถ้าโอนให้กรอกธนาคารและเลขบัญชี")

                warmPanel {
                    Text("ช่วงรับเงิน")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(AppTheme.inkSecondary)
                    HStack(spacing: 10) {
                        ForEach(AdvanceLogic.PayoutSlot.allCases) { slot in
                            choiceButton(
                                label: slot.label,
                                systemImage: slot.systemImage,
                                selected: session.draft.meta.payoutSlot == slot
                            ) {
                                session.draft.meta.payoutSlot = slot
                            }
                        }
                    }

                    Text("รูปแบบการรับ")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(AppTheme.inkSecondary)
                        .padding(.top, 8)
                    HStack(spacing: 10) {
                        ForEach(AdvanceLogic.PaymentMethod.allCases) { method in
                            choiceButton(
                                label: method.label,
                                systemImage: method.systemImage,
                                selected: session.draft.meta.paymentMethod == method
                            ) {
                                session.draft.meta.paymentMethod = method
                            }
                        }
                    }
                }

                if session.draft.meta.paymentMethod == .transfer {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "building.columns.fill")
                                .foregroundStyle(AppTheme.info)
                            Text("ข้อมูลบัญชีรับโอน")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Color(red: 0.05, green: 0.28, blue: 0.63))
                        }

                        Text("ธนาคาร")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                        Menu {
                            ForEach(AdvanceLogic.bankOptions(including: session.draft.meta.bank), id: \.self) { bank in
                                Button(bank) { session.draft.meta.bank = bank }
                            }
                        } label: {
                            HStack {
                                Text(session.draft.meta.bank.isEmpty ? "เลือกธนาคาร" : session.draft.meta.bank)
                                    .foregroundStyle(session.draft.meta.bank.isEmpty ? AppTheme.inkMuted : AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(red: 0.73, green: 0.87, blue: 0.98), lineWidth: 1)
                            )
                        }

                        Text("เลขบัญชี")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                        TextField("เช่น 1234567890", text: $session.draft.meta.accountNumber)
                            .keyboardType(.numberPad)
                            .focused($accountFocused)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color(red: 0.73, green: 0.87, blue: 0.98), lineWidth: 1)
                            )
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.89, green: 0.95, blue: 0.99).opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(red: 0.565, green: 0.792, blue: 0.976), lineWidth: 1)
                    )
                }

                Button {
                    amountFocused = false
                    accountFocused = false
                    Task { await session.save(appState: appState) }
                } label: {
                    Label(
                        session.isSaving
                        ? "กำลังส่ง..."
                        : (session.draft.isPersisted ? "บันทึกการแก้ไข" : "ส่งคำขอเบิกเงิน"),
                        systemImage: "paperplane.fill"
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
            .background(AppTheme.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - History

    private func historySection(_ session: AdvanceSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("คำขอเบิกเงินวันนี้")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if session.todayAdvances.isEmpty {
                Text("ยังไม่มีรายการเบิกเงินวันนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                ForEach(session.todayAdvances) { t in
                    advanceRow(t, session: session)
                }
            }
        }
    }

    private func advanceRow(_ t: Transaction, session: AdvanceSession) -> some View {
        let meta = AdvanceLogic.Meta.decode(workDetails: t.workDetails)
        let empId = (t.employeeIds ?? []).first ?? ""
        let name = AdvanceLogic.employeeName(id: empId, employees: appState.employees)
        let amount = AdvanceLogic.amount(of: t)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                session.loadForEdit(t)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("฿\(AdvanceLogic.formatBaht(amount))")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(accentDeep)
                    }
                    HStack(spacing: 8) {
                        Label(meta.payoutSlot.label, systemImage: meta.payoutSlot.systemImage)
                        Text("·")
                        Label(meta.paymentMethod.label, systemImage: meta.paymentMethod.systemImage)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)

                    if meta.paymentMethod == .transfer {
                        Text("\(meta.bank.isEmpty ? "—" : meta.bank) · \(meta.accountNumber.isEmpty ? "—" : meta.accountNumber)")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.inkMuted)
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

    private func stepHeader(_ n: String, title: String, hint: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption.weight(.black))
                .foregroundStyle(accentDeep)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(AppTheme.inkSecondary)
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private func warmPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 1.0, green: 0.973, blue: 0.945))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 1.0, green: 0.878, blue: 0.698), lineWidth: 1)
        )
    }

    private func choiceButton(
        label: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(label)
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? accentDeep : AppTheme.ink)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? accent.opacity(0.18) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? accent : Color.gray.opacity(0.25), lineWidth: selected ? 1.8 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusBanner(_ session: AdvanceSession) -> some View {
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
