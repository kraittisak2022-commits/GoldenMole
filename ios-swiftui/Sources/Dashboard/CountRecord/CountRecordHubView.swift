import SwiftUI

/// Ops menu destination: work-mode picker → trip/sand counter panels (online MVP).
struct CountRecordHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthService.self) private var auth

    @State private var session = CountRecordSession()
    @State private var pendingUndoTripId: String?
    @State private var confirmUndoSand = false
    @State private var addVehicleId = ""
    @State private var addDriverId = ""

    private var adminName: String {
        auth.currentAdmin?.displayName
            ?? auth.currentAdmin?.username
            ?? "admin"
    }

    var body: some View {
        Group {
            if let mode = session.mode {
                counterContent(mode: mode)
            } else {
                CountRecordWorkModePicker { mode in
                    session.loadFromAppState(appState)
                    session.mode = mode
                }
            }
        }
        .navigationTitle("บันทึกและนับจำนวน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.mode != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("เปลี่ยนโหมด") {
                        session.mode = nil
                        session.statusMessage = nil
                    }
                }
            }
        }
        .alert("ลบเที่ยวล่าสุด?", isPresented: Binding(
            get: { pendingUndoTripId != nil },
            set: { if !$0 { pendingUndoTripId = nil } }
        )) {
            Button("ลบ", role: .destructive) {
                if let id = pendingUndoTripId {
                    Task { await session.undoTrip(unitId: id, appState: appState, adminName: adminName) }
                }
                pendingUndoTripId = nil
            }
            Button("ยกเลิก", role: .cancel) { pendingUndoTripId = nil }
        } message: {
            if let id = pendingUndoTripId,
               let unit = session.tripUnits.first(where: { $0.id == id }),
               let last = unit.lapTimes.last {
                Text("ลบเที่ยวที่ \(unit.rounds) ของ \"\(unit.vehicleId)\"\nเวลา \(last)")
            }
        }
        .alert("ลบรอบล่าสุด?", isPresented: $confirmUndoSand) {
            Button("ลบ", role: .destructive) {
                Task { await session.undoSand(appState: appState, adminName: adminName) }
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            if let unit = session.sandUnit, let last = unit.lapTimes.last {
                Text("ลบรอบที่ \(unit.rounds)\nเวลา \(last)")
            }
        }
        .sheet(isPresented: $session.showAddVehicle) {
            addVehicleSheet
        }
    }

    @ViewBuilder
    private func counterContent(mode: CountRecordWorkMode) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dayBanner

                if let msg = session.statusMessage {
                    Text(msg)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(session.isErrorStatus ? AppTheme.expense : AppTheme.inkSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            (session.isErrorStatus ? AppTheme.expense : AppTheme.brand)
                                .opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }

                if mode == .trip || mode == .both {
                    CountRecordTripPanel(
                        session: session,
                        employees: appState.employees,
                        onRecord: { unit in
                            Task { await session.recordTrip(unitId: unit.id, appState: appState, adminName: adminName) }
                        },
                        onUndo: { unit in
                            pendingUndoTripId = unit.id
                        },
                        onAddVehicle: {
                            prepareAddVehicle()
                            session.showAddVehicle = true
                        }
                    )
                }

                if mode == .sand || mode == .both {
                    CountRecordSandPanel(
                        session: session,
                        onRecord: {
                            Task { await session.recordSand(appState: appState, adminName: adminName) }
                        },
                        onUndo: {
                            confirmUndoSand = true
                        }
                    )
                }

                Text("ต้องออนไลน์ตอนบันทึก · ข้อมูลไปที่ Real-time ชุดเดียวกับ Android")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.top, 4)
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
        .background(DashboardBackground())
        .onAppear {
            if session.tripUnits.isEmpty && session.sandUnit == nil {
                session.loadFromAppState(appState)
            }
        }
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
            Text("ออนไลน์เท่านั้น")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.warning.opacity(0.15), in: Capsule())
                .foregroundStyle(AppTheme.warning)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surface)
        )
    }

    private var addVehicleSheet: some View {
        NavigationStack {
            Form {
                Section("รถ") {
                    let cars = session.availableCars(settings: appState.settings)
                    if cars.isEmpty {
                        Text("ไม่มีรถที่ยังไม่ถูกเพิ่ม (จากรายการรถในตั้งค่า)")
                            .foregroundStyle(AppTheme.inkMuted)
                    } else {
                        Picker("เลือกรถ", selection: $addVehicleId) {
                            Text("— เลือก —").tag("")
                            ForEach(cars, id: \.self) { car in
                                Text(car).tag(car)
                            }
                        }
                    }
                }
                Section("คนขับ (ไม่บังคับ)") {
                    Picker("คนขับ", selection: $addDriverId) {
                        Text("ยังไม่ระบุ").tag("")
                        ForEach(appState.employees.filter(\.isActive)) { emp in
                            Text(emp.displayName).tag(emp.id)
                        }
                    }
                }
            }
            .navigationTitle("เพิ่มคัน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { session.showAddVehicle = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม") {
                        session.addVehicle(vehicleId: addVehicleId, driverId: addDriverId)
                        session.showAddVehicle = false
                    }
                    .disabled(addVehicleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func prepareAddVehicle() {
        let cars = session.availableCars(settings: appState.settings)
        addVehicleId = cars.first ?? ""
        addDriverId = ""
    }
}
