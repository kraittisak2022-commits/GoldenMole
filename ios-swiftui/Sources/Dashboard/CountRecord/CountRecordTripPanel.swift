import SwiftUI

struct CountRecordTripPanel: View {
    let session: CountRecordSession
    let employees: [Employee]
    let settings: AppSettings
    let onRecord: (CountRecordTripDraft) -> Void
    let onLongPressUndo: (CountRecordTripDraft) -> Void
    let onAddVehicle: () -> Void
    let onEdit: (CountRecordTripDraft) -> Void
    let onEditLaps: (CountRecordTripDraft) -> Void
    let onRemove: (CountRecordTripDraft) -> Void
    let onOpenSettings: () -> Void

    private var columns: [GridItem] {
        let count = session.tripUnits.count
        if count <= 2 { return [GridItem(.flexible())] }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var fleetTotal: Int {
        session.tripUnits.reduce(0) { $0 + $1.rounds }
    }

    private var fleetEta: CountRecordAnalytics.SandTargetEta {
        let units = session.tripUnits.map {
            CountRecordTripUnit(
                id: $0.id,
                vehicleId: $0.vehicleId,
                driverId: $0.driverId,
                driverLabel: "",
                rounds: $0.rounds,
                morning: $0.periodSplit.morning,
                afternoon: $0.periodSplit.afternoon,
                ot: $0.periodSplit.ot,
                lapTimes: $0.lapTimes,
                broken: $0.isBroken
            )
        }
        return CountRecordAnalytics.computeTripTargetEta(
            tripUnits: units,
            dayKey: session.dayKey,
            target: CountRecordLogic.tripTarget
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("นับเที่ยวรถ", systemImage: "truck.box.fill")
                    .font(.headline)
                    .foregroundStyle(Color(hex: "#1565C0"))
                Spacer()
                Text("\(fleetTotal) เที่ยว")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
                Button(action: onOpenSettings) {
                    Label("ตั้งค่า", systemImage: "gearshape")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: "#1565C0"))
                .accessibilityLabel("ตั้งค่านับจำนวน")
                Button(action: onAddVehicle) {
                    Label("เพิ่มคัน", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#1565C0"))
            }

            fleetTargetCard

            if session.tripUnits.isEmpty {
                Text("ยังไม่มีรถในวันนี้ — กด «เพิ่มคัน» เพื่อเริ่มนับ")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkMuted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(session.tripUnits.enumerated()), id: \.element.id) { index, unit in
                        tripCard(unit, colorIndex: index)
                    }
                }
            }
        }
    }

    private var fleetTargetCard: some View {
        let target = CountRecordLogic.tripTarget
        let eta = fleetEta
        let pct = eta.progressPct
        let accent = Color(hex: "#1565C0")
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("เป้าหมาย \(target) เที่ยว/วัน")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Spacer()
                Text("\(fleetTotal) / \(target) · \(Int(pct.rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: eta.reached
                                    ? [Color(hex: "#059669"), Color(hex: "#10B981")]
                                    : [Color(hex: "#1565C0"), Color(hex: "#4338CA")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(pct / 100, 1)))
                }
            }
            .frame(height: 8)

            if eta.reached {
                Label("ถึงเป้า \(target) เที่ยวแล้ว", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "#059669"))
            } else if let clock = eta.etaClock {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark")
                    Text("คาดการณ์ถึงเป้าประมาณ \(clock)")
                        .fontWeight(.semibold)
                    if let hoursLeft = eta.hoursLeft {
                        Text("· ~\(CountRecordAnalytics.formatDurationHours(hoursLeft))")
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }
                .font(.caption)
                .foregroundStyle(accent)
            } else {
                Text("นับอย่างน้อย 2 เที่ยว เพื่อคาดการณ์เวลาถึงเป้า")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.06))
        )
    }

    private func displayName(for unit: CountRecordTripDraft) -> String {
        CountRecordLogic.vehicleDisplayLabel(
            vehicleId: unit.vehicleId,
            vehicleName: nil,
            cars: settings.cars,
            catalog: settings.vehicleCatalog
        )
    }

    private func tripCard(_ unit: CountRecordTripDraft, colorIndex: Int) -> some View {
        let accent = Color(hex: CountRecordLogic.vehicleColors[colorIndex % CountRecordLogic.vehicleColors.count])
        let periods = unit.periodSplit
        let driver = CountRecordLogic.driverDisplayName(unit.driverId, employees: employees)
        let goal = CountRecordPrefs.tripGoal
        let progress = goal > 0 ? min(1, Double(unit.rounds) / Double(goal)) : 0
        let name = displayName(for: unit)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(driver)
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    Button("แก้ไขรอบ / เวลา…") { onEditLaps(unit) }
                    Button("จัดการรถ…") { onEdit(unit) }
                    Button("ลบคัน", role: .destructive) { onRemove(unit) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }

            HStack(spacing: 6) {
                if unit.isSupport {
                    badge("ชัพพอต", AppTheme.slate)
                }
                if unit.isBroken {
                    badge("รถเสีย", AppTheme.expense)
                }
                if unit.comboCount > 1 {
                    badge("×\(unit.comboCount)", accent)
                }
                if goal > 0 && unit.rounds >= goal {
                    badge("ครบเป้า", Color(hex: "#C9A227"))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(unit.rounds)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.32, dampingFraction: 0.78), value: unit.rounds)
                    .modifier(TripPlusOneBurst(value: unit.rounds, dayKey: unit.id))
                Text("เที่ยว")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer()
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.85), trigger: unit.rounds)

            if goal > 0 {
                ProgressView(value: progress)
                    .tint(unit.rounds >= goal ? Color(hex: "#C9A227") : accent)
            }

            HStack(spacing: 6) {
                periodChip("เช้า", periods.morning, Color(hex: "#1565C0"))
                periodChip("บ่าย", periods.afternoon, Color(hex: "#2E7D32"))
                periodChip("เย็น", periods.ot, Color(hex: "#E65100"))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = cooldownSecondsLeft(unit, now: context.date)
                Button {
                    onRecord(unit)
                } label: {
                    Text(buttonLabel(unit, cooldownLeft: remaining))
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!unit.canRecord || remaining > 0)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 3).onEnded { _ in
                        onLongPressUndo(unit)
                    }
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private func cooldownSecondsLeft(_ unit: CountRecordTripDraft, now: Date) -> Int {
        guard let until = unit.cooldownUntil else { return 0 }
        return max(0, Int(ceil(until.timeIntervalSince(now))))
    }

    private func buttonLabel(_ unit: CountRecordTripDraft, cooldownLeft: Int) -> String {
        if unit.busy { return "กำลังบันทึก…" }
        if cooldownLeft > 0 { return "รอ \(cooldownLeft) วิ…" }
        if unit.isSupport { return "ชัพพอต" }
        if unit.isBroken { return "รถเสีย" }
        return "แตะ +1 เที่ยว"
    }

    private func periodChip(_ title: String, _ value: Int, _ color: Color) -> some View {
        Text("\(title) \(value)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Pro floating +N toast when trip count ticks up on the counting pad.
private struct TripPlusOneBurst: ViewModifier {
    let value: Int
    let dayKey: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastValue: Int?
    @State private var lastDayKey: String?
    @State private var popupDelta: Int?
    @State private var popupID = UUID()
    @State private var floatAway = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let delta = popupDelta, delta != 0 {
                    let positive = delta > 0
                    HStack(spacing: 6) {
                        Image(systemName: positive ? "truck.box.fill" : "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .bold))
                        Text(positive ? "+\(delta)" : "\(delta)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                        Text("เที่ยว")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: positive
                                        ? [Color(hex: "#1D4ED8"), Color(hex: "#2563EB"), Color(hex: "#38BDF8")]
                                        : [Color(hex: "#E11D48"), Color(hex: "#FB7185")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(
                                color: (positive ? Color(hex: "#2563EB") : Color(hex: "#E11D48")).opacity(0.55),
                                radius: 16,
                                y: 6
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    )
                    .scaleEffect(floatAway ? 1.12 : 0.7)
                    .opacity(floatAway ? 0 : 1)
                    .offset(y: floatAway ? -48 : -8)
                    .allowsHitTesting(false)
                    .id(popupID)
                }
            }
            .onAppear {
                lastValue = value
                lastDayKey = dayKey
            }
            .onChange(of: dayKey) { _, newKey in
                lastDayKey = newKey
                lastValue = value
                popupDelta = nil
                floatAway = false
            }
            .onChange(of: value) { _, newValue in
                guard !reduceMotion else {
                    lastValue = newValue
                    lastDayKey = dayKey
                    return
                }
                guard lastDayKey == dayKey, let previous = lastValue else {
                    lastValue = newValue
                    lastDayKey = dayKey
                    return
                }
                let delta = newValue - previous
                lastValue = newValue
                lastDayKey = dayKey
                guard delta != 0 else { return }

                popupID = UUID()
                floatAway = false
                popupDelta = delta
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                        floatAway = true
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                    if popupDelta == delta {
                        popupDelta = nil
                        floatAway = false
                    }
                }
            }
    }
}
