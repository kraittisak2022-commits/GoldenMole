import SwiftUI

/// Full Android-parity count-record hub (offline, vehicles, UX, settings, shell).
struct CountRecordHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var session = CountRecordSession()
    @State private var confirmLongPressTripId: String?
    @State private var confirmLongPressSand = false
    @State private var confirmDeleteLap: String?
    @State private var confirmRemoveId: String?
    @State private var shareImage: UIImage?

    private var adminName: String {
        auth.currentAdmin?.displayName
            ?? auth.currentAdmin?.username
            ?? "admin"
    }

    private var sync: CountRecordOfflineSync { .shared }

    var body: some View {
        CountRecordMenuShell {
            Group {
                if let mode = session.mode {
                    counterContent(mode: mode)
                } else {
                    CountRecordWorkModePicker { mode in
                        session.loadFromAppState(appState, force: true)
                        session.mode = mode
                    }
                }
            }
        }
        .navigationTitle("บันทึกและนับจำนวน")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if session.mode != nil {
                        session.mode = nil
                        CountRecordPrefs.setWorkMode(nil, for: session.dayKey)
                        session.statusMessage = nil
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("ย้อนกลับ")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("ปิด")
            }
        }
        .onAppear {
            if let service = appState.supabaseService {
                CountRecordOfflineSync.shared.configure(service: service, appState: appState)
            }
            session.bootstrap(appState: appState)
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            session.loadFromAppState(appState)
        }
        .sheet(isPresented: $session.showAddVehicle) {
            CountRecordAddVehicleSheet(
                cars: session.availableCars(settings: appState.settings),
                drivers: session.drivers(from: appState.employees),
                defaultDriverFor: { session.defaultDriverId(for: $0, appState: appState) },
                onAdd: { picks in
                    Task { await session.addVehicles(picks, appState: appState, adminName: adminName) }
                }
            )
        }
        .sheet(isPresented: $session.showSettings) {
            CountRecordSettingsSheet {
                Task { await session.resyncCubic(appState: appState, adminName: adminName) }
            }
        }
        .sheet(isPresented: $session.showTutorial) {
            CountRecordTutorialView(markComplete: true)
        }
        .sheet(isPresented: $session.showFailedQueue) {
            CountRecordFailedQueueSheet(sync: sync)
        }
        .sheet(isPresented: Binding(
            get: { session.lapEditorTripUnitId != nil },
            set: { if !$0 { session.lapEditorTripUnitId = nil } }
        )) {
            if let id = session.lapEditorTripUnitId {
                CountRecordLapEditorSheet(
                    session: session,
                    tripUnitId: id,
                    onDelete: { index in
                        Task {
                            await session.removeTripLap(
                                unitId: id,
                                at: index,
                                appState: appState,
                                adminName: adminName
                            )
                        }
                    },
                    onUpdate: { index, hour, minute, second in
                        Task {
                            await session.updateTripLap(
                                unitId: id,
                                at: index,
                                hour: hour,
                                minute: minute,
                                second: second,
                                appState: appState,
                                adminName: adminName
                            )
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $session.showSandLapEditor) {
            CountRecordLapEditorSheet(
                session: session,
                tripUnitId: nil,
                onDelete: { index in
                    Task {
                        await session.removeSandLap(at: index, appState: appState, adminName: adminName)
                    }
                },
                onUpdate: { index, hour, minute, second in
                    Task {
                        await session.updateSandLap(
                            at: index,
                            hour: hour,
                            minute: minute,
                            second: second,
                            appState: appState,
                            adminName: adminName
                        )
                    }
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { session.editUnitId != nil },
            set: { if !$0 { session.editUnitId = nil } }
        )) {
            if let id = session.editUnitId,
               let unit = session.tripUnits.first(where: { $0.id == id }) {
                CountRecordEditVehicleSheet(
                    unit: unit,
                    drivers: session.drivers(from: appState.employees),
                    onSaveDriver: { driverId in
                        Task { await session.updateDriver(unitId: unit.id, driverId: driverId, appState: appState, adminName: adminName) }
                    },
                    onToggleKind: {
                        Task { await session.toggleWorkKind(unitId: unit.id, appState: appState, adminName: adminName) }
                    },
                    onBroken: {
                        Task {
                            await session.reportBroken(
                                unitId: unit.id,
                                appState: appState,
                                adminName: adminName,
                                employees: appState.employees
                            )
                        }
                    },
                    onRestore: {
                        Task {
                            await session.restoreNormal(
                                unitId: unit.id,
                                appState: appState,
                                adminName: adminName,
                                employees: appState.employees
                            )
                        }
                    },
                    onRemove: {
                        confirmRemoveId = unit.id
                        session.editUnitId = nil
                    }
                )
            }
        }
        .sheet(isPresented: $session.showShare) {
            Group {
                if let shareImage {
                    ShareSheet(items: [shareImage])
                } else {
                    ProgressView("กำลังสร้างภาพ…")
                        .task { await renderShare() }
                }
            }
        }
        .alert("ลบเที่ยวล่าสุด?", isPresented: Binding(
            get: { confirmLongPressTripId != nil },
            set: { if !$0 { confirmLongPressTripId = nil } }
        )) {
            Button("ลบ", role: .destructive) {
                if let id = confirmLongPressTripId {
                    Task { await session.undoTrip(unitId: id, appState: appState, adminName: adminName) }
                }
                confirmLongPressTripId = nil
            }
            Button("ยกเลิก", role: .cancel) { confirmLongPressTripId = nil }
        }
        .alert("ลบรอบล่าสุด?", isPresented: $confirmLongPressSand) {
            Button("ลบ", role: .destructive) {
                Task { await session.undoSand(appState: appState, adminName: adminName) }
            }
            Button("ยกเลิก", role: .cancel) {}
        }
        .alert("ลบรอบนี้?", isPresented: Binding(
            get: { confirmDeleteLap != nil },
            set: { if !$0 { confirmDeleteLap = nil } }
        )) {
            Button("ลบ", role: .destructive) {
                if let stamp = confirmDeleteLap {
                    Task { await session.undoSand(appState: appState, adminName: adminName, removeStamp: stamp) }
                }
                confirmDeleteLap = nil
            }
            Button("ยกเลิก", role: .cancel) { confirmDeleteLap = nil }
        } message: {
            if let stamp = confirmDeleteLap { Text(stamp) }
        }
        .alert("ลบคันนี้ออกจากวันนี้?", isPresented: Binding(
            get: { confirmRemoveId != nil },
            set: { if !$0 { confirmRemoveId = nil } }
        )) {
            Button("ลบ", role: .destructive) {
                if let id = confirmRemoveId {
                    Task { await session.removeVehicle(unitId: id, appState: appState, adminName: adminName) }
                }
                confirmRemoveId = nil
            }
            Button("ยกเลิก", role: .cancel) { confirmRemoveId = nil }
        }
    }

    @ViewBuilder
    private func counterContent(mode: CountRecordWorkMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                syncBanner
                dayBanner

                if let undo = session.pendingUndo {
                    HStack {
                        Text(undo.message)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button("เลิกทำ") {
                            Task { await session.performPendingUndo(appState: appState, adminName: adminName) }
                        }
                        .font(.caption.weight(.bold))
                    }
                    .padding(10)
                    .background(AppTheme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if mode == .both {
                    ViewThatFits {
                        HStack(alignment: .top, spacing: 16) {
                            tripPanel.frame(maxWidth: .infinity)
                            sandPanel.frame(maxWidth: .infinity)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            tripPanel
                            sandPanel
                        }
                    }
                } else if mode == .trip {
                    tripPanel
                } else {
                    sandPanel
                }
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
        .overlay(alignment: .top) {
            if let msg = session.statusMessage {
                CountRecordStatusToast(
                    message: msg,
                    isError: session.isErrorStatus
                ) {
                    session.statusMessage = nil
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
                .zIndex(20)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: session.statusMessage)
    }

    private var tripPanel: some View {
        CountRecordTripPanel(
            session: session,
            employees: appState.employees,
            onRecord: { unit in
                Task { await session.recordTrip(unitId: unit.id, appState: appState, adminName: adminName) }
            },
            onLongPressUndo: { unit in
                confirmLongPressTripId = unit.id
            },
            onAddVehicle: { session.showAddVehicle = true },
            onEdit: { unit in session.editUnitId = unit.id },
            onEditLaps: { unit in session.lapEditorTripUnitId = unit.id },
            onRemove: { unit in confirmRemoveId = unit.id },
            onOpenSettings: { session.showSettings = true }
        )
    }

    private var sandPanel: some View {
        CountRecordSandPanel(
            session: session,
            onRecord: {
                Task { await session.recordSand(appState: appState, adminName: adminName) }
            },
            onLongPressUndo: { confirmLongPressSand = true },
            onDeleteLap: { stamp in confirmDeleteLap = stamp },
            onEditLaps: { session.showSandLapEditor = true }
        )
    }

    private var dayBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("วันนี้")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Text(session.dayKey)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            Spacer()
            Text(sync.isOnline ? "ออนไลน์" : "ออฟไลน์")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (sync.isOnline ? AppTheme.income : AppTheme.warning).opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(sync.isOnline ? AppTheme.income : AppTheme.warning)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surface)
        )
    }

    private var syncBanner: some View {
        Group {
            if sync.pendingCount > 0 || sync.failedCount > 0 || sync.isSyncing {
                Button {
                    session.showFailedQueue = true
                } label: {
                    HStack {
                        Image(systemName: sync.isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                        Text(
                            sync.isSyncing
                                ? "กำลังซิงค์…"
                                : "รออัปโหลด \(sync.pendingCount) · ล้มเหลว \(sync.failedCount)"
                        )
                        .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.ink)
                    .padding(10)
                    .background(AppTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func renderShare() async {
        let card = CountRecordShareCard(
            dayKey: session.dayKey,
            tripUnits: session.tripUnits,
            sandRounds: session.sandUnit?.rounds ?? 0,
            employees: appState.employees
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage
    }
}
