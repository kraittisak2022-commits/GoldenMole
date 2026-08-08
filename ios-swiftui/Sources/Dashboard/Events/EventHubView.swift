import SwiftUI

/// Interactive daily-event hub — Flutter «เหตุการณ์» parity (add / edit / delete).
struct EventHubView: View {
    @Environment(AppState.self) private var appState
    @State private var session = EventSession()
    @FocusState private var descFocused: Bool

    private var sync: CountRecordOfflineSync { .shared }
    private var accent: Color { AppTheme.purple }

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
        .navigationTitle("เหตุการณ์")
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
            "ลบเหตุการณ์นี้?",
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
        .onTapGesture { descFocused = false }
    }

    // MARK: - Form

    private func formCard(_ session: EventSession) -> some View {
        @Bindable var session = session
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 0.90, green: 0.32, blue: 0.0))
                Text("เหตุการณ์สำคัญประจำวัน")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color(red: 0.90, green: 0.32, blue: 0.0))
                Spacer(minLength: 0)
                if session.draft.isPersisted {
                    Text("กำลังแก้ไข")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent.opacity(0.15)))
                        .foregroundStyle(accent)
                }
            }

            Text("ประเภท")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)

            FlexibleChipWrap(spacing: 8) {
                ForEach(EventLogic.EventKind.allCases) { kind in
                    Button {
                        session.draft.kind = kind
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: kind.systemImage)
                                .font(.caption2)
                            Text(kind.label)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .foregroundStyle(session.draft.kind == kind ? .white : AppTheme.ink)
                        .background(
                            Capsule().fill(
                                session.draft.kind == kind
                                    ? kind.accent
                                    : AppTheme.surfaceSoft
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("ความสำคัญ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)

            Picker("priority", selection: $session.draft.priority) {
                ForEach(EventLogic.Priority.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)

            Text("รายละเอียดเหตุการณ์")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)

            TextField(
                "เช่น ฝนตกหนักต้องหยุดงาน หรือกดวลีด่วนด้านล่าง",
                text: $session.draft.description,
                axis: .vertical
            )
            .lineLimit(3...6)
            .focused($descFocused)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
            )

            if !session.suggestions.isEmpty {
                Text("จากประวัติ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                FlexibleChipWrap(spacing: 8) {
                    ForEach(session.suggestions, id: \.self) { s in
                        Button {
                            session.applySuggestion(s)
                        } label: {
                            Text(s)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .foregroundStyle(AppTheme.ink)
                                .background(Capsule().fill(AppTheme.surfaceSoft))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("วลีด่วน")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)

            FlexibleChipWrap(spacing: 8) {
                ForEach(EventLogic.quickPhrases, id: \.self) { phrase in
                    Button {
                        session.appendQuickPhrase(phrase)
                    } label: {
                        Text(phrase)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .foregroundStyle(accent)
                            .background(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await session.save(appState: appState) }
                } label: {
                    Text(session.isSaving
                         ? "กำลังบันทึก..."
                         : (session.draft.isPersisted ? "บันทึกการแก้ไข" : "บันทึกเหตุการณ์"))
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 1.0, green: 0.60, blue: 0.0))
                        )
                }
                .buttonStyle(.plain)
                .disabled(session.isSaving)

                if session.draft.isPersisted {
                    Button {
                        session.clearDraft()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .padding(14)
                            .foregroundStyle(AppTheme.inkMuted)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.surfaceSoft)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - History

    private func historySection(_ session: EventSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("เหตุการณ์วันนี้")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if session.todayEvents.isEmpty {
                Text("ยังไม่มีเหตุการณ์วันนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                ForEach(session.todayEvents) { t in
                    eventRow(t, session: session)
                }
            }
        }
    }

    private func eventRow(_ t: Transaction, session: EventSession) -> some View {
        let kind = EventLogic.EventKind.from(raw: t.eventType)
        let priority = EventLogic.Priority.from(raw: t.eventPriority)
        let text = EventLogic.stripRecorder(t.description)

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                session.loadForEdit(t)
                descFocused = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: kind.systemImage)
                            .foregroundStyle(kind.accent)
                        Text(kind.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(kind.accent)
                        if priority == .urgent {
                            Text("ด่วน")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppTheme.expense.opacity(0.15)))
                                .foregroundStyle(AppTheme.expense)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(text.isEmpty ? "—" : text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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

    // MARK: - Status

    private func statusBanner(_ session: EventSession) -> some View {
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
