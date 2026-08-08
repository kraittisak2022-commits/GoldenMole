import SwiftUI

/// Drum trip form hub — Flutter «บันทึกรถดรัมและจำนวนเที่ยว» parity.
struct DrumTripHubView: View {
    @Environment(AppState.self) private var appState

    @State private var session = DrumTripSession()

    private var sync: CountRecordOfflineSync { .shared }

    private var cars: [String] {
        DrumTripLogic.availableCars(
            settings: appState.settings,
            includeVehicleId: session.draft.vehicleId
        )
    }

    private var drivers: [Employee] {
        DrumTripLogic.drivers(from: appState.employees)
    }

    private var driverById: [String: Employee] {
        Dictionary(uniqueKeysWithValues: appState.employees.map { ($0.id, $0) })
    }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
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
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("บันทึกรถดรัมและจำนวนเที่ยว")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.vehicle)
                        Text("บันทึกทีละคัน — เลือกรถที่มีอยู่แล้ววันนี้จะโหลดมาแก้ไข หรือแตะการ์ดด้านล่าง — ช่วงเช้า/บ่าย ไม่บังคับเมื่อคิดเหมา")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    DrumTripRowEditor(
                        draft: $session.draft,
                        cars: cars,
                        drivers: drivers,
                        onVehicleSelected: { vehicle in
                            session.onVehicleSelected(
                                vehicle,
                                transactions: appState.transactions,
                                appState: appState
                            )
                        }
                    )

                    Button {
                        Task { await session.save(appState: appState) }
                    } label: {
                        HStack {
                            if session.isSaving { ProgressView().tint(.white) }
                            Text(session.isSaving ? "กำลังบันทึก..." : "บันทึกรถคันนี้")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppTheme.vehicle)
                        )
                    }
                    .disabled(session.isSaving)

                    if session.draft.hasAnyInput || session.draft.isPersisted {
                        Button("ล้างฟอร์ม") {
                            session.clearDraft()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    }

                    savedSection
                }
                .padding(AppTheme.spaceLG)
                .padding(.bottom, 24)
            }
        }
        .background(DashboardBackground())
        .navigationTitle("รถดรัมและเที่ยว")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            "ลบรายการนี้?",
            isPresented: Binding(
                get: { session.confirmDeleteId != nil },
                set: { if !$0 { session.confirmDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ลบ", role: .destructive) {
                if let id = session.confirmDeleteId {
                    Task { await session.deleteSaved(id: id, appState: appState) }
                }
                session.confirmDeleteId = nil
            }
            Button("ยกเลิก", role: .cancel) {
                session.confirmDeleteId = nil
            }
        }
        .task {
            if let service = appState.supabaseService {
                session.configureOffline(service: service, appState: appState)
            }
            session.reload(transactions: appState.transactions, force: true)
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            session.reload(transactions: appState.transactions)
        }
    }

    @ViewBuilder
    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("บันทึกวันนี้")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if session.savedToday.isEmpty {
                Text("ยังไม่มีบันทึกรถดรัมในวันที่เลือก — เลือกรถด้านบนเพื่อเพิ่ม")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(session.savedToday) { t in
                    let driverId = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let driverName = driverById[driverId]?.displayName ?? (driverId.isEmpty ? "—" : driverId)
                    DrumTripSavedCard(
                        transaction: t,
                        driverName: driverName,
                        onTap: {
                            session.loadTransaction(t, settings: appState.settings, appState: appState)
                        },
                        onDelete: {
                            session.confirmDeleteId = t.id
                        }
                    )
                }
            }
        }
    }
}
