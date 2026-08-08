import SwiftUI

/// Interactive attendance check-in hub (Flutter «เช็คชื่อ» parity — tap-to-assign).
struct AttendanceHubView: View {
    @Environment(AppState.self) private var appState

    @State private var session = AttendanceSession()

    private var sync: CountRecordOfflineSync { .shared }

    var body: some View {
        Group {
            if let section = session.section {
                board(section: section)
            } else {
                AttendanceSectionPicker(
                    sandSummary: session.summary(for: .sandYard),
                    driverSummary: session.summary(for: .driver)
                ) { section in
                    session.section = section
                    session.pickedIds.removeAll()
                }
            }
        }
        .navigationTitle(session.section?.title ?? "เช็คชื่อ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.section != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("กลุ่ม") {
                        session.section = nil
                        session.pickedIds.removeAll()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if sync.failedCount > 0 {
                        Button {
                            session.showFailedQueue = true
                        } label: {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .foregroundStyle(AppTheme.expense)
                        }
                    }
                    if sync.pendingCount > 0 {
                        Button {
                            sync.syncNow()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $session.showFailedQueue) {
            CountRecordFailedQueueSheet(sync: sync)
        }
        .task {
            if let service = appState.supabaseService {
                session.configureOffline(service: service, appState: appState)
            }
            session.reload(
                transactions: appState.transactions,
                employees: appState.employees,
                force: true
            )
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            session.reload(
                transactions: appState.transactions,
                employees: appState.employees
            )
        }
    }

    @ViewBuilder
    private func board(section: AttendanceSection) -> some View {
        VStack(spacing: 0) {
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

            ScrollView {
                Group {
                    switch section {
                    case .sandYard:
                        AttendanceSandPanel(session: session, employees: appState.employees)
                    case .driver:
                        AttendanceDriverPanel(session: session, employees: appState.employees)
                    }
                }
                .padding(AppTheme.spaceLG)
                .padding(.bottom, 88)
            }

            saveBar
        }
        .background(DashboardBackground())
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await session.saveCurrentSection() }
            } label: {
                HStack {
                    if session.isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(session.isSaving ? "กำลังบันทึก..." : "บันทึกเช็คชื่อ")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.labor)
                )
            }
            .disabled(session.isSaving)
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.vertical, 12)
            .background(AppTheme.surface.opacity(0.96))
        }
    }
}
