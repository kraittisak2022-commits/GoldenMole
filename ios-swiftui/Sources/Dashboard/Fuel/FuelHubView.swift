import SwiftUI

/// Interactive fuel hub — Flutter «น้ำมัน» parity (add / edit / delete).
struct FuelHubView: View {
    @Environment(AppState.self) private var appState
    @State private var session = FuelSession()
    /// When set, open that form on first appear (home ops cards / deep links).
    private let initialSubMode: FuelLogic.SubMode?

    init(initialSubMode: FuelLogic.SubMode? = nil) {
        self.initialSubMode = initialSubMode
    }

    private var sync: CountRecordOfflineSync { .shared }
    private var accent: Color { AppTheme.fuel }

    private var allCars: [String] { MacroVehicleLogic.macroCars(from: appState.settings) }
    private var pinnedCars: [String] { MacroVehicleLogic.pinnedCars(allCars) }
    private var extraCars: [String] { MacroVehicleLogic.extraCars(allCars) }

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 0) {
            statusBanner(session)

            Group {
                if let mode = session.subMode {
                    switch mode {
                    case .stockIn: stockInForm(session)
                    case .withdraw: withdrawForm(session)
                    case .macroUsage: macroUsageForm(session)
                    }
                } else {
                    picker(session)
                }
            }
        }
        .background(DashboardBackground())
        .navigationTitle(session.subMode?.title ?? "น้ำมัน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.subMode != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("เมนู") {
                        session.subMode = nil
                        session.clearStatusSoft()
                    }
                }
            }
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
        .confirmationDialog(
            "ลบรายการน้ำมันนี้?",
            isPresented: Binding(
                get: { session.confirmDeleteId != nil },
                set: { if !$0 { session.confirmDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("ลบ", role: .destructive) {
                if let id = session.confirmDeleteId {
                    Task { await session.deleteTransaction(id: id, appState: appState) }
                }
                session.confirmDeleteId = nil
            }
            Button("ยกเลิก", role: .cancel) { session.confirmDeleteId = nil }
        }
        .task {
            if session.subMode == nil, let initialSubMode {
                session.subMode = initialSubMode
            }
            if let service = appState.supabaseService {
                session.configureOffline(service: service, appState: appState)
            }
            session.reload(appState: appState, force: true)
        }
        .onChange(of: appState.transactionsRevision) { _, _ in
            session.reload(appState: appState)
        }
    }

    // MARK: - Picker

    private func picker(_ session: FuelSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tankGauge(
                    mainDiesel: session.dieselBalance,
                    reserveDiesel: session.reserveDieselBalance
                )

                Text("เลือกเมนูน้ำมัน")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)

                ForEach(FuelLogic.SubMode.allCases) { mode in
                    Button {
                        session.subMode = mode
                        if mode == .stockIn, session.stockIn.time.isEmpty {
                            session.stockIn.time = FuelLogic.nowTimeHHmm()
                        }
                        if mode == .withdraw, session.withdraw.time.isEmpty {
                            session.withdraw.time = FuelLogic.nowTimeHHmm()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(accent.opacity(0.14))
                                    .frame(width: 52, height: 52)
                                Image(systemName: mode.systemImage)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(mode.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(AppTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(accent.opacity(0.3), lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.spaceLG)
        }
    }

    private func tankGauge(mainDiesel: Double, reserveDiesel: Double) -> some View {
        func row(title: String, liters: Double, capacity: Double) -> some View {
            let pct = min(1, max(0, liters / capacity))
            return VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(FuelLogic.formatLiters(liters)) / \(FuelLogic.formatLiters(capacity)) L")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppTheme.surfaceSoft)
                        Capsule()
                            .fill(accent)
                            .frame(width: max(8, geo.size.width * pct))
                    }
                }
                .frame(height: 12)
            }
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("สต็อกดีเซล")
                .font(.headline)
            row(title: "ถังหลัก", liters: mainDiesel, capacity: FuelLogic.tankCapacityMainLiters)
            row(title: "ถังสำรอง", liters: reserveDiesel, capacity: FuelLogic.tankCapacityReserveLiters)
            if mainDiesel < 0 || reserveDiesel < 0 {
                Text("คงเหลือติดลบ — ตรวจสอบรายการเบิก/ใช้รถ")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.expense)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: - Stock in

    private func stockInForm(_ session: FuelSession) -> some View {
        @Bindable var session = session
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                formCard {
                    Text("เพิ่มน้ำมันเข้าถัง (ดีเซล)")
                        .font(.headline)
                    stepperField(title: "ลิตร", value: $session.stockIn.liters, step: 1, range: 0...50_000) {
                        session.stockIn.syncAmountFromPrice()
                    }
                    stepperField(title: "ราคา / ลิตร", value: $session.stockIn.unitPrice, step: 0.5, range: 0...200) {
                        session.stockIn.syncAmountFromPrice()
                    }
                    stepperField(title: "ยอดเงิน (บาท)", value: $session.stockIn.amount, step: 10, range: 0...5_000_000)
                    timeField(title: "เวลาที่เติม", text: $session.stockIn.time)
                }

                primaryButton(
                    title: session.stockIn.isPersisted ? "อัปเดตรายการนี้" : "บันทึกเพิ่มน้ำมัน",
                    busy: session.isSaving
                ) {
                    Task { await session.saveStockIn(appState: appState) }
                }

                if session.stockIn.isPersisted {
                    Button("ล้างฟอร์ม (รายการใหม่)") { session.clearStockInForm() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                historySection(
                    title: "รับเข้าวันนี้",
                    rows: session.dayStockInRows,
                    onEdit: { session.loadStockIn($0) },
                    onDelete: { session.confirmDeleteId = $0.id }
                )
            }
            .padding(AppTheme.spaceLG)
        }
    }

    // MARK: - Withdraw

    private func withdrawForm(_ session: FuelSession) -> some View {
        @Bindable var session = session
        let reconcile = FuelLogic.machineReconcile(dayKey: session.dayKey, transactions: appState.transactions)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                formCard {
                    Text("เบิกน้ำมันออกจากถัง (ดีเซล)")
                        .font(.headline)
                    stepperField(title: "ลิตร", value: $session.withdraw.liters, step: 1, range: 0...50_000)
                    timeField(title: "เวลา", text: $session.withdraw.time)

                    Text("วัตถุประสงค์")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(FuelLogic.WithdrawPurpose.allCases) { purpose in
                            Button {
                                session.withdraw.purpose = purpose
                            } label: {
                                Text(purpose.label)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(session.withdraw.purpose == purpose ? .white : AppTheme.ink)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(session.withdraw.purpose == purpose ? accent : AppTheme.surfaceSoft)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if session.withdraw.purpose == .other {
                        TextField("ระบุรายละเอียด", text: $session.withdraw.otherText)
                            .textFieldStyle(.roundedBorder)
                    }

                    if reconcile.machineWithdraw > 0 || reconcile.vehicleUsage > 0 {
                        Text("วันนี้: เบิกเครื่องจักร \(FuelLogic.formatLiters(reconcile.machineWithdraw)) L · ใช้รถ \(FuelLogic.formatLiters(reconcile.vehicleUsage)) L · คงเหลือโควตา \(FuelLogic.formatLiters(reconcile.remaining)) L")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }

                primaryButton(
                    title: session.withdraw.isPersisted ? "อัปเดตรายการนี้" : "บันทึกเบิกน้ำมัน",
                    busy: session.isSaving
                ) {
                    Task { await session.saveWithdraw(appState: appState) }
                }

                if session.withdraw.isPersisted {
                    Button("ล้างฟอร์ม (รายการใหม่)") { session.clearWithdrawForm() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                historySection(
                    title: "เบิกวันนี้",
                    rows: session.dayWithdrawRows,
                    onEdit: { session.loadWithdraw($0) },
                    onDelete: { session.confirmDeleteId = $0.id }
                )
            }
            .padding(AppTheme.spaceLG)
        }
    }

    // MARK: - Macro usage

    private func macroUsageForm(_ session: FuelSession) -> some View {
        @Bindable var session = session
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("บันทึกการใช้น้ำมันรายรถแม็คโคร")
                    .font(.title3.weight(.bold))
                Text("กรอกลิตรและเวลาต่อคัน — บันทึกแล้วแก้/ลบได้")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkMuted)

                if allCars.isEmpty {
                    Text("ยังไม่พบรถแม็คโครในตั้งค่าแอพ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.expense)
                } else {
                    ForEach(Array(pinnedCars.enumerated()), id: \.element) { index, car in
                        vehicleRow(car: car, index: index + 1, session: session)
                    }
                    if !extraCars.isEmpty {
                        DisclosureGroup(isExpanded: $session.extraExpanded) {
                            ForEach(Array(extraCars.enumerated()), id: \.element) { index, car in
                                vehicleRow(car: car, index: pinnedCars.count + index + 1, session: session)
                                    .padding(.top, 10)
                            }
                        } label: {
                            Text("เพิ่มเติม (\(extraCars.count) คัน)")
                                .font(.headline)
                                .foregroundStyle(accent)
                        }
                    }

                    primaryButton(title: "บันทึกการใช้น้ำมันรายรถ", busy: session.isSaving) {
                        Task { await session.saveVehicleUsage(appState: appState) }
                    }
                }
            }
            .padding(AppTheme.spaceLG)
        }
    }

    private func vehicleRow(car: String, index: Int, session: FuelSession) -> some View {
        let draft = session.vehicleDrafts.first(where: { $0.vehicleId == car })
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("คันที่ \(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
                if draft?.isPersisted == true {
                    Text("บันทึกแล้ว")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.income)
                }
            }
            Text(car)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            if let draft {
                HStack(spacing: 12) {
                    stepperField(
                        title: "ลิตร",
                        value: Binding(
                            get: { draft.liters },
                            set: { v in session.updateVehicle(car) { $0.liters = v } }
                        ),
                        step: 1,
                        range: 0...5000
                    )
                }
                timeField(
                    title: "เวลา",
                    text: Binding(
                        get: { draft.time },
                        set: { v in session.updateVehicle(car) { $0.time = v } }
                    )
                )
                if draft.isPersisted || draft.isActive {
                    HStack {
                        Button("ลบ/ล้าง") {
                            if let id = draft.txId, !id.isEmpty {
                                session.confirmDeleteId = id
                            } else {
                                session.clearVehicleDraft(car)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.expense)
                        Spacer()
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Shared bits

    private func statusBanner(_ session: FuelSession) -> some View {
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

    private func historySection(
        title: String,
        rows: [Transaction],
        onEdit: @escaping (Transaction) -> Void,
        onDelete: @escaping (Transaction) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            if rows.isEmpty {
                Text("ยังไม่มีรายการวันนี้")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            } else {
                ForEach(rows) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        Button { onEdit(t) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.description)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                Text("\(FuelLogic.formatLiters(FuelLogic.liters(of: t))) L · \(FuelLogic.stripRecorder(t.workDetails ?? "—"))")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.inkMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Text("แตะเพื่อแก้ไข")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                            Spacer()
                            Button("ลบ", role: .destructive) { onDelete(t) }
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                }
            }
        }
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
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

    private func primaryButton(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "กำลังบันทึก..." : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent)
            )
        }
        .disabled(busy)
    }

    private func stepperField(
        title: String,
        value: Binding<Double>,
        step: Double,
        range: ClosedRange<Double>,
        onChange: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            HStack(spacing: 10) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                    onChange?()
                } label: {
                    Image(systemName: "minus.circle.fill").font(.title2).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                Text(FuelLogic.formatLiters(value.wrappedValue))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .frame(minWidth: 56)
                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                    onChange?()
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
            )
        }
    }

    private func timeField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            HStack {
                TextField("HH:mm", text: text)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                Button("ตอนนี้") {
                    text.wrappedValue = FuelLogic.nowTimeHHmm()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            }
        }
    }
}

private extension FuelSession {
    func clearStatusSoft() {
        statusMessage = nil
        isErrorStatus = false
    }
}
