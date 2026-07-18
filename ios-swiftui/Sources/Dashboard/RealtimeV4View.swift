import SwiftUI

struct RealtimeV4View: View {
    let transactions: [Transaction]
    let employees: [Employee]
    let settings: AppSettings

    @State private var focusDate = Date()
    @State private var lastRefresh = Date()
    @State private var boardPulse = false
    @State private var livePing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusDateStr: String { DashboardAggregations.formatYMD(focusDate) }
    private var todayStr: String { DashboardAggregations.formatYMD(Date()) }
    private var isToday: Bool { focusDateStr == todayStr }

    private var tripUnits: [CountRecordTripUnit] {
        CountRecordLogic.buildTripUnits(dayKey: focusDateStr, transactions: transactions, employees: employees)
    }

    private var sandUnit: CountRecordSandUnit? {
        CountRecordLogic.buildSandUnit(dayKey: focusDateStr, transactions: transactions)
    }

    private var tripTotal: Int { tripUnits.reduce(0) { $0 + $1.rounds } }
    private var sandRounds: Int { sandUnit?.rounds ?? 0 }

    private var statusLabel: String? {
        CountRecordLogic.menuStatusLabel(dayKey: focusDateStr, transactions: transactions, employees: employees)
    }

    private var efficiency: VehicleEfficiency {
        CountRecordLogic.vehicleEfficiency(
            dayKey: focusDateStr,
            tripUnits: tripUnits,
            transactions: transactions,
            employees: employees
        )
    }

    private var fleetWorkSpan: String? {
        CountRecordLogic.fleetWorkSpanLabel(units: tripUnits, dayKey: focusDateStr)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroHeader
            liveBoard
        }
        .onAppear {
            lastRefresh = Date()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    livePing = true
                }
            }
        }
        .onChange(of: transactions.count) { _ in
            lastRefresh = Date()
            triggerPulse()
        }
        .onChange(of: tripTotal) { _ in triggerPulse() }
        .onChange(of: sandRounds) { _ in triggerPulse() }
    }

    private func triggerPulse() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.25)) { boardPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.35)) { boardPulse = false }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "#020617"), Color(hex: "#0F172A"), Color(hex: "#1E1B4B")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(hex: "#6366F1").opacity(0.28))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: 220, y: -40)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                    Text("OPERATIONS MONITOR")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.8)
                }
                .foregroundStyle(Color(hex: "#C7D2FE").opacity(0.9))

                Text("Real-time (V.4)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)

                Text("ติดตามการนับเที่ยวรถและร่อนทรายแบบสด")
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: "#CBD5E1"))

                HStack(spacing: 8) {
                    dateChip
                    if !isToday {
                        Button("กลับวันนี้") {
                            focusDate = Date()
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.25)).background(Capsule().fill(Color.white.opacity(0.1))))
                        .foregroundStyle(.white)
                    }
                }

                if let statusLabel {
                    Text(statusLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: "#A5B4FC"))
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    private var dateChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
            Text("กำลังดู: \(thaiDateShort(focusDateStr))")
                .font(.caption.weight(.semibold))
            if isToday {
                Text("วันนี้")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.emerald.opacity(0.3)))
                    .foregroundStyle(Color(hex: "#A7F3D0"))
            }
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .overlay {
            DatePicker("", selection: $focusDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .colorMultiply(.clear)
                .opacity(0.02)
        }
    }

    // MARK: - Live board

    private var liveBoard: some View {
        VStack(spacing: 0) {
            liveBoardHeader
            VStack(spacing: 16) {
                tripPanel
                sandPanel
            }
            .padding(16)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(boardPulse ? Color(hex: "#A5B4FC").opacity(0.8) : Color(.separator).opacity(0.4), lineWidth: boardPulse ? 2 : 1)
        )
        .shadow(color: boardPulse ? Color(hex: "#6366F1").opacity(0.25) : .black.opacity(0.06), radius: boardPulse ? 18 : 10, y: 6)
        .animation(.easeOut(duration: 0.35), value: boardPulse)
    }

    private var liveBoardHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#0F172A"), Color(hex: "#1E1B4B"), Color(hex: "#0F172A")],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    liveBadge
                    dateChipCompact
                    if !isToday {
                        Button("กลับวันนี้") { focusDate = Date() }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                    }
                    if boardPulse {
                        Group {
                            if #available(iOS 17.0, *) {
                                Image(systemName: "bolt.fill")
                                    .symbolEffect(.pulse, options: .repeating)
                            } else {
                                Image(systemName: "bolt.fill")
                            }
                        }
                        .foregroundStyle(Color(hex: "#FCD34D"))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    metricChip(
                        icon: "truck.box.fill",
                        text: "\(CountRecordLogic.formatMetric(tripTotal)) เที่ยว",
                        bg: Color.blue.opacity(0.18),
                        fg: Color(hex: "#BFDBFE")
                    )
                    metricChip(
                        icon: "drop.fill",
                        text: "\(CountRecordLogic.formatMetric(sandRounds)) รอบ",
                        bg: Color.pink.opacity(0.18),
                        fg: Color(hex: "#FBCFE8")
                    )
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("โพล")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(hex: "#94A3B8"))
                        Text(timeString(lastRefresh))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#E2E8F0"))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.emerald.opacity(livePing ? 0.55 : 0.15))
                    .frame(width: 10, height: 10)
                    .scaleEffect(livePing ? 1.6 : 1)
                Circle()
                    .fill(Color.emerald)
                    .frame(width: 8, height: 8)
            }
            Text("LIVE")
                .font(.system(size: 10, weight: .black))
                .tracking(2)
                .foregroundStyle(Color(hex: "#6EE7B7"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.emerald.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Color.emerald.opacity(0.35)))
    }

    private var dateChipCompact: some View {
        HStack(spacing: 5) {
            Image(systemName: "calendar").font(.system(size: 10))
            Text(thaiDateShort(focusDateStr)).font(.caption.weight(.semibold))
            if isToday {
                Text("วันนี้")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.emerald.opacity(0.28)))
                    .foregroundStyle(Color(hex: "#A7F3D0"))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.1)))
        .overlay {
            DatePicker("", selection: $focusDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .opacity(0.02)
        }
    }

    private func metricChip(icon: String, text: String, bg: Color, fg: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12).fill(bg))
    }

    // MARK: - Trip panel

    private var tripPanel: some View {
        panelShell(
            title: "จำนวนเที่ยวรถ",
            subtitle: "\(tripUnits.count) คัน · \(CountRecordLogic.formatMetric(tripTotal)) เที่ยว",
            icon: "truck.box.fill",
            gradient: [Color(hex: "#1D4ED8"), Color(hex: "#2563EB"), Color(hex: "#0891B2")]
        ) {
            if tripUnits.isEmpty {
                emptyState(icon: "truck.box", title: "ยังไม่มีเที่ยวรถ", subtitle: "รอการนับจากแอปมือถือ")
            } else {
                VStack(spacing: 12) {
                    if tripTotal > 0 {
                        tripSummaryHero
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(tripUnits.enumerated()), id: \.element.id) { index, unit in
                            TripVehicleCard(unit: unit, index: index, dayKey: focusDateStr)
                        }
                    }
                    tripLeaderboard
                }
            }
        }
    }

    private var tripSummaryHero: some View {
        let pct = CountRecordLogic.tripTarget > 0
            ? min(Double(tripTotal) / Double(CountRecordLogic.tripTarget) * 100, 100)
            : 0
        let atTarget = tripTotal >= CountRecordLogic.tripTarget

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "#2563EB"), Color(hex: "#2563EB"), Color(hex: "#4338CA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 110, height: 110)
                .blur(radius: 24)
                .offset(x: 240, y: -30)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("รวมเที่ยวรถวันนี้")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    if let fleetWorkSpan {
                        WorkSpanBadge(label: fleetWorkSpan, onDark: true)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CountRecordLogic.formatMetric(tripTotal))
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tripTotal)
                    Text("เที่ยว")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(spacing: 4) {
                    HStack {
                        Label("เป้าหมาย", systemImage: "target")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                        Text("\(CountRecordLogic.formatMetric(tripTotal)) / \(CountRecordLogic.formatMetric(CountRecordLogic.tripTarget)) · \(Int(pct.rounded()))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(atTarget ? Color(hex: "#6EE7B7") : Color.white)
                                .frame(width: geo.size.width * CGFloat(pct / 100))
                        }
                    }
                    .frame(height: 8)
                }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("จำนวนคิว", systemImage: "shippingbox.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(CountRecordLogic.formatMetric(tripTotal * CountRecordLogic.queuePerTrip))
                                .font(.title2.weight(.black))
                                .foregroundStyle(.white)
                            Text("คิว")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Text("\(CountRecordLogic.queuePerTrip) คิว / 1 เที่ยว")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 10)

                    Divider().background(Color.white.opacity(0.2))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("เฉลี่ย/คัน", systemImage: "speedometer")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer(minLength: 0)
                            EfficiencyBadge(efficiency: efficiency)
                        }
                        Text(String(format: "%.1f เที่ยว/คัน", efficiency.perVehToday))
                            .font(.headline.weight(.black))
                            .foregroundStyle(.white)
                        Text("\(efficiency.countToday) คันที่นับ")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Divider().background(Color.white.opacity(0.15))
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tripLeaderboard: some View {
        let ranked = tripUnits.filter { !$0.lapTimes.isEmpty }.sorted { $0.rounds > $1.rounds }
        return VStack(alignment: .leading, spacing: 8) {
            Text("บันทึกล่าสุด")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if ranked.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { rank, unit in
                    HStack(spacing: 8) {
                        if rank == 0 {
                            Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "#F59E0B"))
                        } else if rank <= 2 {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(rank == 1 ? Color.gray : Color(hex: "#B45309"))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.vehicleId).font(.caption.weight(.bold))
                            if let last = unit.lapTimes.last {
                                Text(CountRecordLogic.formatLapClock(last) ?? last)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(unit.rounds) เที่ยว")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(hex: "#2563EB")))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(rank == 0 ? Color(hex: "#FFFBEB") : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(rank == 0 ? Color(hex: "#FCD34D").opacity(0.8) : .clear, lineWidth: 1.5)
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Sand panel

    private var sandPanel: some View {
        panelShell(
            title: "การร่อนทราย",
            subtitle: sandUnit.map { "\($0.rounds) รอบ" } ?? "ยังไม่มีรอบ",
            icon: "drop.fill",
            gradient: [Color(hex: "#BE185D"), Color(hex: "#E11D48"), Color(hex: "#C026D3")]
        ) {
            if let sand = sandUnit, sand.rounds > 0 {
                VStack(spacing: 12) {
                    sandHero(sand)
                    sandKPI(sand)
                    sandRecentLaps(sand)
                }
            } else {
                emptyState(icon: "drop", title: "ยังไม่มีรอบทราย", subtitle: "รอการนับร่อนทรายจากมือถือ")
            }
        }
    }

    private func sandHero(_ sand: CountRecordSandUnit) -> some View {
        let span = CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: sand.lapTimes, dayKey: focusDateStr)
        )
        return ZStack {
            LinearGradient(
                colors: [Color(hex: "#DB2777"), Color(hex: "#E11D48"), Color(hex: "#A21CAF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Text(CountRecordLogic.formatMetric(sand.rounds))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: sand.rounds)
                Text("รอบ")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
                PeriodPill(morning: sand.morning, afternoon: sand.afternoon, ot: sand.ot, onDark: true)
                if let span {
                    WorkSpanBadge(label: span, onDark: true)
                }
                if let last = sand.lapTimes.last {
                    Label(CountRecordLogic.formatLapClock(last) ?? last, systemImage: "clock")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.15)))
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sandKPI(_ sand: CountRecordSandUnit) -> some View {
        let hours = CountRecordLogic.activeDurationHours(lapTimes: sand.lapTimes, dayKey: focusDateStr)
        let perHour = hours.flatMap { $0 > 0 ? sand.rounds / $0 : nil }
        let perMin = hours.flatMap { $0 > 0 ? Double(sand.rounds) / ($0 * 60) : nil }
        let pct = CountRecordLogic.sandTarget > 0
            ? min(Double(sand.rounds) / Double(CountRecordLogic.sandTarget) * 100, 100)
            : 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("ตัวชี้วัดร่อนทราย")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color(hex: "#DB2777"))

            HStack(spacing: 8) {
                kpiCell(
                    title: "รอบ / ชม.",
                    value: perHour.map { String(format: "%.1f" , $0) } ?? "—"
                )
                kpiCell(
                    title: "รอบ / นาที",
                    value: perMin.map { String(format: "%.2f", $0) } ?? "—"
                )
            }

            VStack(spacing: 4) {
                HStack {
                    Text("เป้าหมาย")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(CountRecordLogic.formatMetric(sand.rounds)) / \(CountRecordLogic.formatMetric(CountRecordLogic.sandTarget)) · \(Int(pct.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(Color(hex: "#DB2777"))
                            .frame(width: geo.size.width * CGFloat(pct / 100))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#FDF2F8"), Color(hex: "#FFF1F2")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#FBCFE8"), lineWidth: 1)
        )
    }

    private func kpiCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "#DB2777"))
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(Color(hex: "#831843"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.85)))
    }

    private func sandRecentLaps(_ sand: CountRecordSandUnit) -> some View {
        let start = max(0, sand.lapTimes.count - CountRecordLogic.sandRecentLaps)
        let recent = Array(sand.lapTimes.enumerated()).filter { $0.offset >= start }
        return VStack(alignment: .leading, spacing: 8) {
            Text("รอบล่าสุด")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if recent.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlexibleChipWrap {
                    ForEach(recent, id: \.offset) { item in
                        let roundNo = item.offset + 1
                        let latest = roundNo == sand.lapTimes.count
                        HStack(spacing: 6) {
                            Text("รอบ \(roundNo)")
                                .foregroundStyle(latest ? Color(hex: "#FCE7F3") : Color(hex: "#DB2777"))
                            Text(CountRecordLogic.formatLapClock(item.element) ?? item.element)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(latest ? .white.opacity(0.9) : .secondary)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(latest ? Color(hex: "#DB2777") : Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(latest ? Color.clear : Color(hex: "#FBCFE8"), lineWidth: 1)
                        )
                        .shadow(color: latest ? Color(hex: "#DB2777").opacity(0.25) : .clear, radius: 4, y: 2)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Shared shells

    private func panelShell<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        gradient: [Color],
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            .padding(14)
            .background(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(Color(.separator))
        )
    }

    // MARK: - Helpers

    private func thaiDateShort(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        return String(format: "%02d/%02d/%04d", parts[2], parts[1], parts[0])
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Subviews

private struct TripVehicleCard: View {
    let unit: CountRecordTripUnit
    let index: Int
    let dayKey: String

    private var accent: Color {
        Color(hex: CountRecordLogic.vehicleColors[index % CountRecordLogic.vehicleColors.count])
    }

    private var workSpan: String? {
        CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: unit.lapTimes, dayKey: dayKey)
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [accent, accent.opacity(0.85), Color(hex: "#0F172A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 80, height: 80)
                .blur(radius: 18)
                .offset(x: 90, y: -20)

            VStack(spacing: 8) {
                HStack {
                    Text("คัน \(index + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.2)))
                    Spacer()
                    if unit.broken {
                        Label("รถเสีย", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#451A03"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: "#FCD34D")))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))

                VStack(spacing: 4) {
                    Text("\(unit.rounds)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: unit.rounds)
                    Text("เที่ยว")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.75))
                    PeriodPill(morning: unit.morning, afternoon: unit.afternoon, ot: unit.ot, onDark: true)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 3) {
                    Text(unit.vehicleId)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                    Label(unit.driverLabel, systemImage: "person.fill")
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    if let workSpan {
                        Label(workSpan, systemImage: "clock")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    if let last = unit.lapTimes.last {
                        Text(CountRecordLogic.formatLapClock(last) ?? last)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.2)))
            }
            .padding(12)
        }
        .frame(minHeight: 168)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

private struct PeriodPill: View {
    let morning: Int
    let afternoon: Int
    let ot: Int
    var onDark: Bool = false

    private var afternoonDisplay: Int { max(0, afternoon - ot) }
    private var hasAny: Bool { morning > 0 || afternoonDisplay > 0 || ot > 0 }

    @ViewBuilder
    var body: some View {
        if hasAny {
            HStack(spacing: 6) {
                if morning > 0 {
                    pill("sun.max.fill", "เช้า \(morning)",
                         bg: onDark ? Color(hex: "#FBBF24").opacity(0.3) : Color(hex: "#FEF3C7"),
                         fg: onDark ? Color(hex: "#FFFBEB") : Color(hex: "#78350F"))
                }
                if afternoonDisplay > 0 {
                    pill("sunset.fill", "บ่าย \(afternoonDisplay)",
                         bg: onDark ? Color(hex: "#38BDF8").opacity(0.3) : Color(hex: "#E0E7FF"),
                         fg: onDark ? Color(hex: "#F0F9FF") : Color(hex: "#312E81"))
                }
                if ot > 0 {
                    pill("moon.fill", "OT \(ot)",
                         bg: onDark ? Color(hex: "#A78BFA").opacity(0.3) : Color(hex: "#EDE9FE"),
                         fg: onDark ? Color(hex: "#F5F3FF") : Color(hex: "#4C1D95"))
                }
            }
        }
    }

    private func pill(_ icon: String, _ text: String, bg: Color, fg: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
    }
}

private struct WorkSpanBadge: View {
    let label: String
    var onDark: Bool = false

    var body: some View {
        Label(label, systemImage: "clock")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(onDark ? .white.opacity(0.9) : Color.primary.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(onDark ? Color.black.opacity(0.2) : Color(.secondarySystemBackground))
            )
    }
}

private struct EfficiencyBadge: View {
    let efficiency: VehicleEfficiency

    var body: some View {
        Group {
            if let delta = efficiency.deltaPct {
                let rounded = Int(abs(delta).rounded())
                if rounded == 0 {
                    Text(efficiency.isCalendarYesterday ? "เท่าเมื่อวาน" : "เท่า\(efficiency.priorLabel)")
                        .foregroundStyle(Color(hex: "#64748B"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                } else if delta > 0 {
                    Text("▲ มีประสิทธิภาพกว่า\(efficiency.isCalendarYesterday ? "เมื่อวาน" : efficiency.priorLabel) \(rounded)%")
                        .foregroundStyle(Color(hex: "#A7F3D0"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.emerald.opacity(0.25)))
                } else {
                    Text("▼ ด้อยกว่า\(efficiency.isCalendarYesterday ? "เมื่อวาน" : efficiency.priorLabel) \(rounded)%")
                        .foregroundStyle(Color(hex: "#FECDD3"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: "#F43F5E").opacity(0.25)))
                }
            } else {
                Text(efficiency.priorLabel.isEmpty ? "ไม่มีข้อมูลก่อนหน้า" : "ไม่มีข้อมูล\(efficiency.priorLabel)")
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
        }
        .font(.system(size: 9, weight: .bold))
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
}

/// Simple wrapping layout for sand lap chips (iOS 16-friendly).
private struct FlexibleChipWrap<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Use LazyVGrid as a stable wrap substitute for iOS 16.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
            content
        }
    }
}

private extension Color {
    static let emerald = Color(hex: "#10B981")
}
