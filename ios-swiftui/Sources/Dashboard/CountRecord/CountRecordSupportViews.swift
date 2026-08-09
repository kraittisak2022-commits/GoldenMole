import SwiftUI
import UIKit

// MARK: - Settings

struct CountRecordSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tripGoal = CountRecordPrefs.tripGoal
    @State private var cubic = CountRecordPrefs.cubicPerTrip
    var onResyncCubic: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("เป้าหมายเที่ยวต่อคัน") {
                    Stepper(value: $tripGoal, in: 0...200) {
                        Text(tripGoal == 0 ? "ปิด" : "\(tripGoal) เที่ยว")
                    }
                    Text("0 = ปิดการแสดงเป้า")
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Section("คิวต่อเที่ยว") {
                    Stepper(value: $cubic, in: 0.5...99, step: 0.5) {
                        Text(CountRecordLogic.formatMetric(cubic))
                    }
                    Button("บันทึกและอัปเดตแถววันนี้") {
                        CountRecordPrefs.tripGoal = tripGoal
                        CountRecordPrefs.cubicPerTrip = cubic
                        onResyncCubic()
                        dismiss()
                    }
                }
            }
            .navigationTitle("ตั้งค่านับจำนวน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") {
                        CountRecordPrefs.tripGoal = tripGoal
                        CountRecordPrefs.cubicPerTrip = cubic
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Multi-add vehicles

struct CountRecordAddVehicleSheet: View {
    let cars: [String]
    let drivers: [Employee]
    let defaultDriverFor: (String) -> String
    let onAdd: ([CountRecordSession.VehiclePick]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var driverByCar: [String: String] = [:]
    @State private var kindByCar: [String: CountRecordWorkKind] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if cars.isEmpty {
                    ContentUnavailableView("ไม่มีรถให้เพิ่ม", systemImage: "truck.box", description: Text("รถทั้งหมดถูกเพิ่มแล้ว หรือยังไม่มีในตั้งค่า"))
                } else {
                    List {
                        ForEach(cars, id: \.self) { car in
                            Section {
                                Toggle(isOn: Binding(
                                    get: { selected.contains(car) },
                                    set: { on in
                                        if on {
                                            selected.insert(car)
                                            if driverByCar[car] == nil {
                                                driverByCar[car] = defaultDriverFor(car)
                                            }
                                            if kindByCar[car] == nil {
                                                kindByCar[car] = .sandTransport
                                            }
                                        } else {
                                            selected.remove(car)
                                        }
                                    }
                                )) {
                                    Text(car).font(.headline)
                                }
                                if selected.contains(car) {
                                    Picker("คนขับ", selection: Binding(
                                        get: { driverByCar[car] ?? "" },
                                        set: { driverByCar[car] = $0 }
                                    )) {
                                        Text("ยังไม่ระบุ").tag("")
                                        ForEach(drivers) { emp in
                                            Text(emp.displayName).tag(emp.id)
                                        }
                                    }
                                    Picker("ประเภทงาน", selection: Binding(
                                        get: { kindByCar[car] ?? .sandTransport },
                                        set: { kindByCar[car] = $0 }
                                    )) {
                                        ForEach(CountRecordWorkKind.allCases) { kind in
                                            Text(kind.label).tag(kind)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("เพิ่มคัน")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("เพิ่ม (\(selected.count))") {
                        let picks = selected.map {
                            CountRecordSession.VehiclePick(
                                vehicleId: $0,
                                driverId: driverByCar[$0] ?? "",
                                workKind: kindByCar[$0] ?? .sandTransport
                            )
                        }
                        onAdd(picks)
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit vehicle

struct CountRecordEditVehicleSheet: View {
    let unit: CountRecordTripDraft
    let drivers: [Employee]
    let onSaveDriver: (String) -> Void
    let onToggleKind: () -> Void
    let onBroken: () -> Void
    let onRestore: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var driverId: String

    init(
        unit: CountRecordTripDraft,
        drivers: [Employee],
        onSaveDriver: @escaping (String) -> Void,
        onToggleKind: @escaping () -> Void,
        onBroken: @escaping () -> Void,
        onRestore: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.unit = unit
        self.drivers = drivers
        self.onSaveDriver = onSaveDriver
        self.onToggleKind = onToggleKind
        self.onBroken = onBroken
        self.onRestore = onRestore
        self.onRemove = onRemove
        _driverId = State(initialValue: unit.driverId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(unit.vehicleId) {
                    Picker("คนขับ", selection: $driverId) {
                        Text("ยังไม่ระบุ").tag("")
                        ForEach(drivers) { emp in
                            Text(emp.displayName).tag(emp.id)
                        }
                    }
                    Button("บันทึกคนขับ") {
                        onSaveDriver(driverId)
                        dismiss()
                    }
                }
                Section("ประเภทงาน") {
                    Text("ปัจจุบัน: \(unit.workKind.label)")
                    Button(unit.isSupport ? "เปลี่ยนเป็นขนทราย" : "เปลี่ยนเป็นชัพพอต") {
                        onToggleKind()
                        dismiss()
                    }
                }
                Section("สถานะรถ") {
                    if unit.isBroken {
                        Button("รถกลับมาปกติ") {
                            onRestore()
                            dismiss()
                        }
                    } else {
                        Button("แจ้งรถเสีย", role: .destructive) {
                            onBroken()
                            dismiss()
                        }
                    }
                }
                Section {
                    Button("ลบคันนี้ออกจากวันนี้", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
            }
            .navigationTitle("แก้ไขรถ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Failed queue

struct CountRecordFailedQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sync: CountRecordOfflineSync

    var body: some View {
        NavigationStack {
            List {
                Section("สถานะ") {
                    LabeledContent("รออัปโหลด", value: "\(sync.pendingCount)")
                    LabeledContent("ล้มเหลว", value: "\(sync.failedCount)")
                    LabeledContent("เครือข่าย", value: sync.isOnline ? "พร้อม" : "ออฟไลน์/เซิร์ฟเวอร์ไม่ตอบ")
                }
                if !sync.pendingOps.isEmpty {
                    Section("คิวที่รอ") {
                        ForEach(sync.pendingOps, id: \.transactionId) { op in
                            opRow(op)
                        }
                    }
                }
                if !sync.failedOps.isEmpty {
                    Section("ล้มเหลว") {
                        ForEach(sync.failedOps, id: \.transactionId) { op in
                            opRow(op)
                        }
                    }
                }
                Section {
                    Button("ลองใหม่ทั้งหมด") {
                        sync.retryFailed()
                        dismiss()
                    }
                    Button("ซิงค์คิวที่รอ") {
                        sync.syncNow()
                        dismiss()
                    }
                    Button("ทิ้งรายการที่ล้มเหลว", role: .destructive) {
                        sync.discardFailed()
                        dismiss()
                    }
                }
            }
            .navigationTitle("คิวออฟไลน์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func opRow(_ op: CountRecordOfflineSync.PendingOp) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(opLabel(op))
                .font(.subheadline.weight(.semibold))
            Text(op.transactionId)
                .font(.caption2.monospaced())
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
        }
    }

    private func opLabel(_ op: CountRecordOfflineSync.PendingOp) -> String {
        switch op {
        case .upsert(let payload, _):
            return "อัปโหลด · \(payload.subCategory ?? payload.category)"
        case .delete:
            return "ลบรายการ"
        }
    }
}

// MARK: - Tutorial

struct CountRecordTutorialView: View {
    var markComplete: Bool = true
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let steps: [(String, String, String)] = [
        ("plusminus.circle.fill", "ยินดีต้อนรับ", "เมนูบันทึกและนับจำนวนใช้บันทึกเที่ยวรถและร่อนทรายแบบเร็วในสนาม"),
        ("hand.tap.fill", "แตะเพื่อนับ", "แตะการ์ดรถหรือปุ่มร่อนทรายเพื่อ +1 พร้อมบันทึกเวลา"),
        ("hand.point.up.left.fill", "ท่าทาง", "กดค้าง 3 วินาทีเพื่อเลิกทำรอบล่าสุด · กดค้างชิปรอบทรายเพื่อลบรอบนั้น"),
        ("truck.box.fill", "หลายคัน", "เพิ่มรถได้หลายคัน ตั้งคนขับ ชัพพอต หรือแจ้งรถเสียได้"),
        ("drop.fill", "ร่อนทราย", "แผงร่อนทรายนับรอบรวมของวัน และแสดงรอบล่าสุด"),
        ("wifi.slash", "ออฟไลน์", "ไม่มีเน็ตก็บันทึกได้ — ระบบจะอัปโหลดเมื่อออนไลน์"),
        ("battery.100", "ประหยัดแบต", "หน้าจอดิมเองเมื่อไม่ใช้งาน และกดเพื่อปลุก"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TabView(selection: $page) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        VStack(spacing: 16) {
                            Image(systemName: step.0)
                                .font(.system(size: 48))
                                .foregroundStyle(AppTheme.brand)
                            Text(step.1)
                                .font(.title2.weight(.bold))
                            Text(step.2)
                                .font(.body)
                                .foregroundStyle(AppTheme.inkMuted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                HStack {
                    if page < steps.count - 1 {
                        Button("ข้าม") { finish() }
                        Spacer()
                        Button("ถัดไป") { page += 1 }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("เข้าใจแล้ว") { finish() }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle("วิธีใช้")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // จำทันทีที่เปิดครั้งแรก — กันโผล่ซ้ำทุกครั้งแม้ปัดปิดชีต
                if markComplete { CountRecordPrefs.tutorialCompleted = true }
            }
        }
    }

    private func finish() {
        if markComplete { CountRecordPrefs.tutorialCompleted = true }
        dismiss()
    }
}

// MARK: - Share card

struct CountRecordShareCard: View {
    let dayKey: String
    let tripUnits: [CountRecordTripDraft]
    let sandRounds: Int
    let employees: [Employee]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("สรุปนับจำนวน")
                .font(.title2.weight(.bold))
            Text(DashboardAggregations.thaiDateLong(dayKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(tripUnits.filter { $0.rounds > 0 || $0.isSupport }) { unit in
                let p = unit.periodSplit
                HStack {
                    VStack(alignment: .leading) {
                        Text(unit.vehicleId).font(.headline)
                        Text(CountRecordLogic.driverDisplayName(unit.driverId, employees: employees))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(unit.isSupport ? "ชัพพอต" : "\(unit.rounds) เที่ยว")
                            .font(.headline)
                        if !unit.isSupport {
                            Text("เช้า \(p.morning) · บ่าย \(p.afternoon)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }

            HStack {
                Text("ร่อนทราย")
                Spacer()
                Text("\(sandRounds) รอบ").font(.headline)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }
}

// MARK: - Power shell

struct CountRecordMenuShell<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var lastActivity = Date()
    @State private var dimmed = false
    @State private var sleeping = false
    @State private var tick = Date()
    @State private var savedBrightness: CGFloat?

    private let dimAfter: TimeInterval = 60
    private let sleepAfter: TimeInterval = 600

    var body: some View {
        ZStack {
            content()
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in bump() }
                )

            if dimmed || sleeping {
                Color.black.opacity(sleeping ? 0.92 : 0.55)
                    .ignoresSafeArea()
                    .onTapGesture { wake() }
                    .overlay {
                        if sleeping {
                            VStack(spacing: 8) {
                                Text(clockString)
                                    .font(.system(size: 48, weight: .light, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("แตะเพื่อปลุก")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if savedBrightness == nil {
                savedBrightness = UIScreen.main.brightness
            }
            bump()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            restoreBrightness()
        }
        .onChange(of: dimmed) { _, _ in applyBrightness() }
        .onChange(of: sleeping) { _, _ in applyBrightness() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now in
            tick = now
            let idle = now.timeIntervalSince(lastActivity)
            if idle >= sleepAfter {
                sleeping = true
                dimmed = true
            } else if idle >= dimAfter {
                dimmed = true
                sleeping = false
            }
        }
    }

    private var clockString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "HH:mm"
        return f.string(from: tick)
    }

    private func bump() {
        lastActivity = Date()
        if dimmed || sleeping { wake() }
    }

    private func wake() {
        withAnimation(.easeOut(duration: 0.25)) {
            dimmed = false
            sleeping = false
        }
        lastActivity = Date()
        restoreBrightness()
    }

    private func applyBrightness() {
        let base = savedBrightness ?? UIScreen.main.brightness
        if sleeping {
            UIScreen.main.brightness = 0.06
        } else if dimmed {
            UIScreen.main.brightness = max(0.12, base * 0.35)
        } else {
            restoreBrightness()
        }
    }

    private func restoreBrightness() {
        if let savedBrightness {
            UIScreen.main.brightness = savedBrightness
        }
    }
}
