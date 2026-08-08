import SwiftUI

struct MacroVehicleRowCard: View {
    let draft: MacroVehicleDraft
    let displayIndex: Int
    let drivers: [Employee]
    let defaultDriverId: String?
    let onDriverChange: (String) -> Void
    let onWorkTypeChange: (MacroVehicleLogic.WorkType) -> Void
    let onToggleTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onAddCustom: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    private var sortedDrivers: [Employee] {
        guard let defaultDriverId else { return drivers }
        return drivers.sorted { a, b in
            if a.id == defaultDriverId { return true }
            if b.id == defaultDriverId { return false }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    private var customTags: [String] {
        draft.workTags.filter { !MacroVehicleLogic.workQuickPhrases.contains($0) }
    }

    private var accent: Color { AppTheme.warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: "gearshape.2.fill")
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("รถแม็คโคร คันที่ \(displayIndex)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    Text(draft.vehicleId)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(red: 0.75, green: 0.21, blue: 0.05))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if draft.isPersisted {
                    Text("บันทึกแล้ว")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.income.opacity(0.15)))
                        .foregroundStyle(AppTheme.income)
                }
            }

            Text("คนขับ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Menu {
                ForEach(sortedDrivers) { emp in
                    Button(emp.displayName) { onDriverChange(emp.id) }
                }
            } label: {
                let name = drivers.first(where: { $0.id == draft.driverId })?.displayName
                HStack {
                    Text(name ?? (draft.driverId.isEmpty ? "เลือกคนขับแม็คโคร" : draft.driverId))
                        .foregroundStyle(draft.driverId.isEmpty ? AppTheme.inkMuted : AppTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.surfaceSoft)
                )
            }

            Text("ประเภทงาน")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            Picker("workType", selection: Binding(
                get: { draft.workType },
                set: onWorkTypeChange
            )) {
                ForEach(MacroVehicleLogic.WorkType.allCases) { wt in
                    Text(wt.label).tag(wt)
                }
            }
            .pickerStyle(.segmented)

            Text("งานวันนี้")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)

            FlexibleChipWrap(spacing: 8) {
                ForEach(MacroVehicleLogic.workQuickPhrases, id: \.self) { phrase in
                    macroChip(
                        label: phrase,
                        selected: draft.workTags.contains(phrase),
                        onTap: { onToggleTag(phrase) }
                    )
                }
                ForEach(customTags, id: \.self) { tag in
                    macroChip(
                        label: tag,
                        selected: true,
                        onTap: { onToggleTag(tag) },
                        onRemove: { onRemoveTag(tag) }
                    )
                }
                Button(action: onAddCustom) {
                    Label("งานอื่น", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button(action: onSave) {
                    Text(draft.isPersisted ? "อัปเดตคันนี้" : "บันทึกคันนี้")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent)
                        )
                }
                .buttonStyle(.plain)

                if draft.isPersisted || draft.hasDriver || draft.hasDetails {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.body.weight(.semibold))
                            .padding(12)
                            .foregroundStyle(AppTheme.expense)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.expense.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(draft.isPersisted || (draft.hasDriver && draft.hasDetails)
                      ? Color(red: 1, green: 0.973, blue: 0.941)
                      : AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    draft.isPersisted || (draft.hasDriver && draft.hasDetails)
                    ? accent.opacity(0.85)
                    : accent.opacity(0.28),
                    lineWidth: draft.isPersisted || (draft.hasDriver && draft.hasDetails) ? 1.8 : 1
                )
        )
    }

    private func macroChip(
        label: String,
        selected: Bool,
        onTap: @escaping () -> Void,
        onRemove: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? accent : AppTheme.ink)
            }
            .buttonStyle(.plain)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(selected ? accent.opacity(0.16) : AppTheme.surfaceSoft)
        )
        .overlay(
            Capsule().strokeBorder(selected ? accent.opacity(0.55) : AppTheme.inkMuted.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Interactive macro excavator usage hub (Flutter parity — edit / delete).
struct MacroVehicleHubView: View {
    @Environment(AppState.self) private var appState

    @State private var session = MacroVehicleSession()

    private var sync: CountRecordOfflineSync { .shared }

    private var allCars: [String] {
        MacroVehicleLogic.macroCars(from: appState.settings)
    }

    private var pinnedCars: [String] { MacroVehicleLogic.pinnedCars(allCars) }
    private var extraCars: [String] { MacroVehicleLogic.extraCars(allCars) }

    private var drivers: [Employee] {
        MacroVehicleLogic.macroDrivers(from: appState.employees)
    }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            headerStatus(session)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("บันทึกการใช้รถแม็คโคร")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(AppTheme.warning)
                        Text("แตะเลือกคนขับและงานของแต่ละคัน — เปลี่ยนงานระหว่างวันได้ แล้วกดอัปเดตคันนั้น")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    if allCars.isEmpty {
                        Text("ยังไม่พบรายการรถแม็คโครในตั้งค่าแอพ")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.expense.opacity(0.08))
                            )
                    } else {
                        if drivers.isEmpty {
                            Text("ยังไม่พบพนักงานที่ตำแหน่งเป็น «คนขับรถแม็คโคร» (ตั้งค่าในเมนูพนักงาน)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.expense)
                        }

                        ForEach(Array(pinnedCars.enumerated()), id: \.element) { index, car in
                            row(for: car, displayIndex: index + 1, session: session)
                        }

                        if !extraCars.isEmpty {
                            DisclosureGroup(isExpanded: $session.extraExpanded) {
                                ForEach(Array(extraCars.enumerated()), id: \.element) { index, car in
                                    row(for: car, displayIndex: pinnedCars.count + index + 1, session: session)
                                        .padding(.top, 10)
                                }
                            } label: {
                                Text("เพิ่มเติม (\(extraCars.count) คัน)")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.warning)
                            }
                        }

                        Button {
                            Task { await session.saveAll(appState: appState) }
                        } label: {
                            HStack {
                                if session.isSaving { ProgressView().tint(.white) }
                                Text(session.isSaving ? "กำลังบันทึก..." : "บันทึกการใช้รถแม็คโคร")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppTheme.warning)
                            )
                        }
                        .disabled(session.isSaving || allCars.isEmpty)
                    }
                }
                .padding(AppTheme.spaceLG)
                .padding(.bottom, 24)
            }
        }
        .background(DashboardBackground())
        .navigationTitle("การใช้รถแม็คโคร")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
        .alert(
            "เพิ่มงานเอง",
            isPresented: Binding(
                get: { session.customWorkPromptVehicleId != nil },
                set: { if !$0 { session.customWorkPromptVehicleId = nil; session.customWorkText = "" } }
            )
        ) {
            TextField("ชื่องาน", text: $session.customWorkText)
            Button("เพิ่ม") {
                if let vid = session.customWorkPromptVehicleId {
                    let text = session.customWorkText
                    session.updateDraft(vid) { $0.addCustomWorkTag(text) }
                }
                session.customWorkPromptVehicleId = nil
                session.customWorkText = ""
            }
            Button("ยกเลิก", role: .cancel) {
                session.customWorkPromptVehicleId = nil
                session.customWorkText = ""
            }
        } message: {
            Text("พิมพ์ชื่องานภาษาไทย แล้วเพิ่มเป็นชิป")
        }
        .confirmationDialog(
            "ลบรายการแม็คโครนี้?",
            isPresented: Binding(
                get: { session.confirmDeleteVehicleId != nil },
                set: { if !$0 { session.confirmDeleteVehicleId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ลบ", role: .destructive) {
                if let vid = session.confirmDeleteVehicleId {
                    Task { await session.deleteRow(vehicleId: vid, appState: appState) }
                }
                session.confirmDeleteVehicleId = nil
            }
            Button("ยกเลิก", role: .cancel) {
                session.confirmDeleteVehicleId = nil
            }
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

    @ViewBuilder
    private func headerStatus(_ session: MacroVehicleSession) -> some View {
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

    @ViewBuilder
    private func row(for car: String, displayIndex: Int, session: MacroVehicleSession) -> some View {
        if let draft = session.drafts.first(where: { $0.vehicleId == car }) {
            let defaultDriver = CountRecordVehicleDefaults.resolveDriverId(
                vehicleId: car,
                drivers: drivers,
                tripHistory: appState.transactions,
                vehicleDefaultDrivers: appState.settings.vehicleDefaultDrivers
            )
            MacroVehicleRowCard(
                draft: draft,
                displayIndex: displayIndex,
                drivers: drivers,
                defaultDriverId: defaultDriver,
                onDriverChange: { id in session.updateDraft(car) { $0.driverId = id } },
                onWorkTypeChange: { wt in session.updateDraft(car) { $0.workType = wt } },
                onToggleTag: { tag in session.updateDraft(car) { $0.toggleWorkTag(tag) } },
                onRemoveTag: { tag in session.updateDraft(car) { $0.removeWorkTag(tag) } },
                onAddCustom: { session.customWorkPromptVehicleId = car },
                onSave: { Task { await session.saveSingle(vehicleId: car, appState: appState) } },
                onDelete: { session.confirmDeleteVehicleId = car }
            )
        }
    }
}
