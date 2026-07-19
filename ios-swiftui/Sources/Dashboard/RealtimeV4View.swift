import SwiftUI

/// Fixed dark palette for the always-dark Real-time V.4 dashboard (matches the web share view).
enum RealtimeV4Palette {
    static let page = Color(hex: "#020617")       // slate-950 page background
    static let panel = Color(hex: "#0F172A")      // slate-900 panel body
    static let panelTop = Color(hex: "#111C31")   // slightly lifted top of panel body
    static let card = Color(hex: "#0B1424")        // inner card surface
    static let cardSoft = Color.white.opacity(0.06)
    static let border = Color.white.opacity(0.08)
    static let textMuted = Color(hex: "#94A3B8")   // slate-400
}

/// Memoized bundle of all heavy Real-time V.4 analytics.
/// Built off the main thread (see `scheduleRebuild`) so realtime bursts never freeze the UI.
struct RealtimeV4Snapshot: Sendable {
    let tripUnits: [CountRecordTripUnit]
    let sandUnit: CountRecordSandUnit?
    let statusLabel: String?
    let efficiency: VehicleEfficiency
    let fleetWorkSpan: String?
    let tripAnalytics: CountRecordAnalytics.ModeAnalytics
    let sandAnalytics: CountRecordAnalytics.ModeAnalytics
    let activityEvents: [CountRecordAnalytics.ActivityEvent]

    var tripTotal: Int { tripUnits.reduce(0) { $0 + $1.rounds } }
    var sandRounds: Int { sandUnit?.rounds ?? 0 }

    nonisolated static func build(dayKey: String, transactions: [Transaction], employees: [Employee]) -> RealtimeV4Snapshot {
        let units = CountRecordLogic.buildTripUnits(dayKey: dayKey, transactions: transactions, employees: employees)
        return RealtimeV4Snapshot(
            tripUnits: units,
            sandUnit: CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: transactions),
            statusLabel: CountRecordLogic.menuStatusLabel(dayKey: dayKey, transactions: transactions, employees: employees),
            efficiency: CountRecordLogic.vehicleEfficiency(
                dayKey: dayKey,
                tripUnits: units,
                transactions: transactions,
                employees: employees
            ),
            fleetWorkSpan: CountRecordLogic.fleetWorkSpanLabel(units: units, dayKey: dayKey),
            tripAnalytics: CountRecordAnalytics.buildTripAnalytics(dayKey: dayKey, transactions: transactions, employees: employees),
            sandAnalytics: CountRecordAnalytics.buildSandAnalytics(dayKey: dayKey, transactions: transactions, employees: employees),
            activityEvents: CountRecordAnalytics.buildActivityFeed(dayKey: dayKey, transactions: transactions, employees: employees)
        )
    }
}

struct RealtimeV4View: View {
    let transactions: [Transaction]
    let employees: [Employee]
    let settings: AppSettings

    @State private var focusDate = Date()
    @State private var snapshot = RealtimeV4Snapshot.build(dayKey: "", transactions: [], employees: [])
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showDatePicker = false
    @State private var lastRefresh = Date()
    @State private var boardPulse = false
    @State private var livePing = false
    @State private var selectedVehicle: CountRecordTripUnit?
    @State private var showSandDetail = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focusDateStr: String { DashboardAggregations.formatYMD(focusDate) }
    private var todayStr: String { DashboardAggregations.formatYMD(Date()) }
    private var isToday: Bool { focusDateStr == todayStr }

    // Memoized analytics — rebuilt off-main (debounced) when inputs change.
    private var tripUnits: [CountRecordTripUnit] { snapshot.tripUnits }
    private var sandUnit: CountRecordSandUnit? { snapshot.sandUnit }
    private var tripTotal: Int { snapshot.tripTotal }
    private var sandRounds: Int { snapshot.sandRounds }
    private var statusLabel: String? { snapshot.statusLabel }
    private var efficiency: VehicleEfficiency { snapshot.efficiency }
    private var fleetWorkSpan: String? { snapshot.fleetWorkSpan }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroHeader
            liveBoard
        }
        .onAppear {
            scheduleRebuild()
            lastRefresh = Date()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    livePing = true
                }
            }
        }
        .onDisappear {
            rebuildTask?.cancel()
            rebuildTask = nil
        }
        .onChange(of: focusDateStr) { _, _ in scheduleRebuild() }
        .onChange(of: transactions) { _, _ in
            scheduleRebuild()
            lastRefresh = Date()
        }
        .onChange(of: employees) { _, _ in scheduleRebuild() }
        .onChange(of: tripTotal) { _, _ in triggerPulse() }
        .onChange(of: sandRounds) { _, _ in triggerPulse() }
        .sheet(item: $selectedVehicle) { unit in
            VehicleDetailSheet(unit: unit, dayKey: focusDateStr)
        }
        .sheet(isPresented: $showSandDetail) {
            if let sand = sandUnit {
                SandDetailSheet(sand: sand, dayKey: focusDateStr, analytics: sandAnalytics)
            }
        }
    }

    /// Coalesces rapid realtime/delta updates into one off-main snapshot build.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let dayKey = focusDateStr
        let txs = transactions
        let emps = employees
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled else { return }
            let built = await Task.detached(priority: .userInitiated) {
                RealtimeV4Snapshot.build(dayKey: dayKey, transactions: txs, employees: emps)
            }.value
            guard !Task.isCancelled else { return }
            snapshot = built
        }
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
                .blur(radius: 26)
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
        .sheet(isPresented: $showDatePicker) {
            focusDatePickerSheet
        }
    }

    private var dateChip: some View {
        Button {
            showDatePicker = true
        } label: {
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
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("เลือกวันที่กำลังดู")
        .accessibilityHint("แตะเพื่อเลือกวันย้อนหลัง")
    }

    private var focusDatePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "เลือกวันที่",
                    selection: $focusDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .tint(Color(hex: "#6366F1"))
                .padding(.horizontal, 8)

                Button {
                    focusDate = Date()
                } label: {
                    Label("วันนี้", systemImage: "sun.max.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color.emerald)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("กำลังดู")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("เสร็จ") { showDatePicker = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: - Live board

    private var tripAnalytics: CountRecordAnalytics.ModeAnalytics { snapshot.tripAnalytics }
    private var sandAnalytics: CountRecordAnalytics.ModeAnalytics { snapshot.sandAnalytics }
    private var activityEvents: [CountRecordAnalytics.ActivityEvent] { snapshot.activityEvents }

    private var liveBoard: some View {
        VStack(spacing: 0) {
            liveBoardHeader
            VStack(spacing: 16) {
                tripPanel
                sandPanel
                RealtimeV4ActivityFeed(events: activityEvents)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#0F172A"), Color(hex: "#0B1120"), Color(hex: "#0F172A")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(boardPulse ? Color(hex: "#A5B4FC").opacity(0.8) : RealtimeV4Palette.border, lineWidth: boardPulse ? 2 : 1)
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
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onTapGesture { selectedVehicle = unit }
                        }
                    }
                    tripLeaderboard
                    if tripAnalytics.rounds > 0 {
                        RealtimeV4AnalyticsPanel(analytics: tripAnalytics, accent: Color(hex: "#38BDF8"))
                    }
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
                .blur(radius: 16)
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
                        .modifier(ScoreFloatOverlay(value: tripTotal, dayKey: focusDateStr))
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
                .foregroundStyle(RealtimeV4Palette.textMuted)
            if ranked.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { rank, unit in
                    HStack(spacing: 8) {
                        if rank == 0 {
                            Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "#FBBF24"))
                        } else if rank <= 2 {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(rank == 1 ? Color(hex: "#CBD5E1") : Color(hex: "#D97706"))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.vehicleId)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            if let last = unit.lapTimes.last {
                                Text(CountRecordLogic.formatLapClock(last) ?? last)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
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
                            .fill(rank == 0 ? Color(hex: "#F59E0B").opacity(0.14) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(rank == 0 ? Color(hex: "#FCD34D").opacity(0.5) : .clear, lineWidth: 1.5)
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(RealtimeV4Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(RealtimeV4Palette.border, lineWidth: 1)
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
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture { showSandDetail = true }
                    sandKPI(sand)
                    sandRecentLaps(sand)
                    if sandAnalytics.rounds > 0 {
                        RealtimeV4AnalyticsPanel(analytics: sandAnalytics, accent: Color(hex: "#F472B6"))
                    }
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
                    .modifier(ScoreFloatOverlay(value: sand.rounds, dayKey: focusDateStr))
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
        let perHour = hours.flatMap { $0 > 0 ? Double(sand.rounds) / $0 : nil }
        let perMin = hours.flatMap { $0 > 0 ? Double(sand.rounds) / ($0 * 60) : nil }
        let pct = CountRecordLogic.sandTarget > 0
            ? min(Double(sand.rounds) / Double(CountRecordLogic.sandTarget) * 100, 100)
            : 0

        return VStack(alignment: .leading, spacing: 10) {
            Text("ตัวชี้วัดร่อนทราย")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color(hex: "#F9A8D4"))

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
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(CountRecordLogic.formatMetric(sand.rounds)) / \(CountRecordLogic.formatMetric(CountRecordLogic.sandTarget)) · \(Int(pct.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Color(hex: "#EC4899"))
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
                        colors: [Color(hex: "#4C0519").opacity(0.55), Color(hex: "#4A044E").opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#EC4899").opacity(0.3), lineWidth: 1)
        )
    }

    private func kpiCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(hex: "#F9A8D4"))
            Text(value)
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.28)))
    }

    private func sandRecentLaps(_ sand: CountRecordSandUnit) -> some View {
        let start = max(0, sand.lapTimes.count - CountRecordLogic.sandRecentLaps)
        let recent = Array(sand.lapTimes.enumerated()).filter { $0.offset >= start }
        return VStack(alignment: .leading, spacing: 8) {
            Text("รอบล่าสุด")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(RealtimeV4Palette.textMuted)
            if recent.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                FlexibleChipWrap {
                    ForEach(recent, id: \.offset) { item in
                        let roundNo = item.offset + 1
                        let latest = roundNo == sand.lapTimes.count
                        HStack(spacing: 6) {
                            Text("รอบ \(roundNo)")
                                .foregroundStyle(latest ? Color(hex: "#FCE7F3") : Color(hex: "#F9A8D4"))
                            Text(CountRecordLogic.formatLapClock(item.element) ?? item.element)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(latest ? .white.opacity(0.9) : .white.opacity(0.6))
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(latest ? Color(hex: "#DB2777") : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(latest ? Color.clear : Color(hex: "#EC4899").opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: latest ? Color(hex: "#DB2777").opacity(0.25) : .clear, radius: 4, y: 2)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(RealtimeV4Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(RealtimeV4Palette.border, lineWidth: 1)
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
                .background(
                    LinearGradient(
                        colors: [RealtimeV4Palette.panelTop, RealtimeV4Palette.panel],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RealtimeV4Palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(Color.white.opacity(0.15))
        )
    }

    // MARK: - Helpers

    private func thaiDateShort(_ ymd: String) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        return String(format: "%02d/%02d/%04d", parts[2], parts[1], parts[0])
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = DashboardAggregations.gregorian
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func timeString(_ date: Date) -> String {
        Self.clockFormatter.string(from: date)
    }
}

// MARK: - Score popup (+N / -N game-style float)

/// Floating +N / -N badge when a live count changes (skips day switches and Reduce Motion).
private struct ScoreFloatOverlay: ViewModifier {
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
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(delta > 0 ? Color.emerald : Color(hex: "#FB7185"))
                        .shadow(color: (delta > 0 ? Color.emerald : Color(hex: "#FB7185")).opacity(0.55), radius: 8, y: 0)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                        .scaleEffect(floatAway ? 1.15 : 0.55)
                        .opacity(floatAway ? 0 : 1)
                        .offset(y: floatAway ? -42 : -6)
                        .allowsHitTesting(false)
                        .id(popupID)
                        .accessibilityHidden(true)
                }
            }
            .onAppear {
                lastValue = value
                lastDayKey = dayKey
            }
            .onChange(of: dayKey) { newKey in
                lastDayKey = newKey
                lastValue = value
                popupDelta = nil
                floatAway = false
            }
            .onChange(of: value) { newValue in
                handleValueChange(newValue)
            }
    }

    private func handleValueChange(_ newValue: Int) {
        defer {
            lastValue = newValue
            lastDayKey = dayKey
        }

        guard !reduceMotion else { return }
        guard lastDayKey == dayKey, let previous = lastValue else { return }
        let delta = newValue - previous
        guard delta != 0 else { return }

        popupID = UUID()
        floatAway = false
        popupDelta = delta

        // Appear at rest, then float up and fade (game score popup).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.easeOut(duration: 0.85)) {
                floatAway = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            if popupDelta == delta {
                popupDelta = nil
                floatAway = false
            }
        }
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
                .blur(radius: 12)
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
                        .modifier(ScoreFloatOverlay(value: unit.rounds, dayKey: dayKey))
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
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(6)
                .background(Circle().fill(Color.black.opacity(0.22)))
                .padding(8)
        }
    }
}

// MARK: - Detail sheets (tap to inspect)

private struct VehicleDetailSheet: View {
    let unit: CountRecordTripUnit
    let dayKey: String
    @Environment(\.dismiss) private var dismiss

    private var workSpan: String? {
        CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: unit.lapTimes, dayKey: dayKey)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(unit.vehicleId)
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                        Label(unit.driverLabel, systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(unit.rounds)")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("เที่ยว").font(.title3.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        if unit.broken {
                            Label("รถเสีย", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: "#451A03"))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color(hex: "#FCD34D")))
                        }
                    }

                    DetailStatRow(items: [
                        ("เช้า", "\(unit.morning)"),
                        ("บ่าย", "\(max(0, unit.afternoon - unit.ot))"),
                        ("OT", "\(unit.ot)")
                    ])

                    if let workSpan {
                        Label(workSpan, systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    LapTimeList(title: "เวลาประทับทุกเที่ยว", lapTimes: unit.lapTimes)
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("รายละเอียดรถ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct SandDetailSheet: View {
    let sand: CountRecordSandUnit
    let dayKey: String
    let analytics: CountRecordAnalytics.ModeAnalytics
    @Environment(\.dismiss) private var dismiss

    private var workSpan: String? {
        CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: sand.lapTimes, dayKey: dayKey)
        )
    }
    private var hours: Double? { CountRecordLogic.activeDurationHours(lapTimes: sand.lapTimes, dayKey: dayKey) }
    private var perHour: Double? { hours.flatMap { $0 > 0 ? Double(sand.rounds) / $0 : nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CountRecordLogic.formatMetric(sand.rounds))
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("รอบ").font(.title3.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                    }

                    DetailStatRow(items: [
                        ("เช้า", "\(sand.morning)"),
                        ("บ่าย", "\(max(0, sand.afternoon - sand.ot))"),
                        ("OT", "\(sand.ot)")
                    ])

                    DetailStatRow(items: [
                        ("รอบ/ชม.", perHour.map { String(format: "%.1f", $0) } ?? "—"),
                        ("เป้าหมาย", "\(CountRecordLogic.formatMetric(CountRecordLogic.sandTarget))"),
                        ("คงเหลือ", "\(max(0, CountRecordLogic.sandTarget - sand.rounds))")
                    ])

                    if let workSpan {
                        Label(workSpan, systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    LapTimeList(title: "เวลาประทับทุกรอบ", lapTimes: sand.lapTimes)
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("รายละเอียดร่อนทราย")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

private struct DetailStatRow: View {
    let items: [(String, String)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Text(item.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    Text(item.1).font(.title3.weight(.black)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            }
        }
    }
}

private struct LapTimeList: View {
    let title: String
    let lapTimes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))
            if lapTimes.isEmpty {
                Text("ยังไม่มีเวลาประทับ").font(.caption).foregroundStyle(.white.opacity(0.4))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(lapTimes.enumerated()), id: \.offset) { idx, stamp in
                        HStack(spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(CountRecordLogic.formatLapClock(stamp) ?? stamp)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
