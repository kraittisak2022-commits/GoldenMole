import SwiftUI

/// Adaptive Real-time V.4 palette — clean white/pro in light, premium dark in dark.
enum RealtimeV4Palette {
    static let page = Color(light: Color(hex: "#F4F6FB"), dark: Color(hex: "#020617"))
    static let panel = Color(light: .white, dark: Color(hex: "#0F172A"))
    static let panelTop = Color(light: .white, dark: Color(hex: "#111C31"))
    static let card = Color(light: Color(hex: "#F1F5F9"), dark: Color(hex: "#0B1424"))
    static let cardSoft = Color(light: Color.black.opacity(0.04), dark: Color.white.opacity(0.06))
    static let border = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.08))
    static let textMuted = Color(light: Color(hex: "#64748B"), dark: Color(hex: "#94A3B8"))

    /// Body text / icons on panel & card surfaces (not on colored hero fills).
    static let ink = Color(light: Color(hex: "#0F172A"), dark: .white)
    static let inkSecondary = Color(light: Color(hex: "#334155"), dark: Color.white.opacity(0.75))
    static let inkMuted = Color(light: Color(hex: "#64748B"), dark: Color.white.opacity(0.55))
    static let inkFaint = Color(light: Color(hex: "#94A3B8"), dark: Color.white.opacity(0.4))
    static let hairline = Color(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.15))

    static let liveHeaderStart = Color(light: Color(hex: "#EEF2FF"), dark: Color(hex: "#0F172A"))
    static let liveHeaderMid = Color(light: Color(hex: "#E0E7FF"), dark: Color(hex: "#1E1B4B"))
    static let liveHeaderEnd = Color(light: Color(hex: "#F8FAFC"), dark: Color(hex: "#0F172A"))

    static let sandPanelTop = Color(light: Color(hex: "#FDF2F8"), dark: Color(hex: "#4C0519").opacity(0.55))
    static let sandPanelBottom = Color(light: Color(hex: "#FAE8FF"), dark: Color(hex: "#4A044E").opacity(0.4))
    static let sandLabel = Color(light: Color(hex: "#BE185D"), dark: Color(hex: "#F9A8D4"))
    static let sandTrack = Color(light: Color(hex: "#FBCFE8"), dark: Color.white.opacity(0.12))
    static let sandCellFill = Color(light: Color.white.opacity(0.85), dark: Color.black.opacity(0.28))
}

/// Memoized bundle of all heavy Real-time V.4 analytics.
/// Built off the main thread (see `scheduleRebuild`) so realtime bursts never freeze the UI.
struct RealtimeV4Snapshot: Sendable {
    let tripUnits: [CountRecordTripUnit]
    let sandUnit: CountRecordSandUnit?
    let statusLabel: String?
    let efficiency: VehicleEfficiency
    let fleetWorkSpan: String?
    /// Precomputed morning/afternoon fleet span labels for the trip summary hero.
    let fleetMorningSpanLabel: String?
    let fleetAfternoonSpanLabel: String?
    let tripAnalytics: CountRecordAnalytics.ModeAnalytics
    let sandAnalytics: CountRecordAnalytics.ModeAnalytics
    let activityEvents: [CountRecordAnalytics.ActivityEvent]
    /// Precomputed so view bodies never call parseLapStamp / computeWorkSpan.
    let sandWorkSpan: String?
    let sandMorningSpanLabel: String?
    let sandAfternoonSpanLabel: String?
    let sandHours: Doub่le?
    let sandMorningHours: Double?
    let sandAfternoonHours: Double?
    let tripHours: Double?
    let tripMorningHours: Double?
    let tripAfternoonHours: Double?
    let vehicleWorkSpans: [String: String]
    let leaderboard: [CountRecordTripUnit]
    let isLight: Bool

    var tripTotal: Int { tripUnits.reduce(0) { $0 + $1.rounds } }
    var sandRounds: Int { sandUnit?.rounds ?? 0 }

    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = [],
        light: Bool = false,
        byDay: [String: [Transaction]]? = nil
    ) -> RealtimeV4Snapshot {
        let dayIndex = byDay ?? Dictionary(grouping: transactions) { String($0.date.prefix(10)) }
        let dayTx = dayIndex[dayKey] ?? []
        let units = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: dayTx,
            employees: employees,
            cars: cars,
            catalog: catalog
        )
        let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx)

        let priorTripKey = light
            ? nil
            : CountRecordLogic.findPriorDayWithTripData(
                from: dayKey,
                transactions: transactions,
                employees: employees,
                byDay: dayIndex
            )
        let priorSandKey = light
            ? nil
            : CountRecordAnalytics.findPriorDay(
                from: dayKey,
                mode: .sand,
                transactions: transactions,
                employees: employees,
                byDay: dayIndex
            )

        let tripAnalytics = CountRecordAnalytics.buildTripAnalytics(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees,
            tripUnits: units,
            priorKey: priorTripKey,
            byDay: dayIndex,
            light: light
        )
        let sandAnalytics = CountRecordAnalytics.buildSandAnalytics(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees,
            sandUnit: sand,
            priorKey: priorSandKey,
            byDay: dayIndex,
            light: light
        )

        var vehicleWorkSpans: [String: String] = [:]
        vehicleWorkSpans.reserveCapacity(units.count)
        for unit in units {
            if let label = CountRecordLogic.formatWorkSpanLabel(
                CountRecordLogic.computeWorkSpan(lapTimes: unit.lapTimes, dayKey: dayKey)
            ) {
                vehicleWorkSpans[unit.id] = label
            }
        }

        let sandLaps = sand?.lapTimes ?? []
        let sandWorkSpan = CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: sandLaps, dayKey: dayKey)
        )
        let sandPeriodSpans = CountRecordLogic.periodSpanLabels(lapTimes: sandLaps, dayKey: dayKey)
        let sandHours = CountRecordLogic.activeDurationHours(lapTimes: sandLaps, dayKey: dayKey)
        let sandSplit = CountRecordLogic.splitLapsByPeriod(sandLaps)
        let sandMorningHours = CountRecordLogic.activeDurationHours(lapTimes: sandSplit.morning, dayKey: dayKey)
        let sandAfternoonHours = CountRecordLogic.activeDurationHours(lapTimes: sandSplit.afternoon, dayKey: dayKey)

        let tripLaps = tripAnalytics.lapTimes
        let tripHours = CountRecordLogic.activeDurationHours(lapTimes: tripLaps, dayKey: dayKey)
        let tripSplit = CountRecordLogic.splitLapsByPeriod(tripLaps)
        let tripMorningHours = CountRecordLogic.activeDurationHours(lapTimes: tripSplit.morning, dayKey: dayKey)
        let tripAfternoonHours = CountRecordLogic.activeDurationHours(lapTimes: tripSplit.afternoon, dayKey: dayKey)
        let leaderboard = Array(
            units
                .filter { !$0.lapTimes.isEmpty }
                .sorted { $0.rounds > $1.rounds }
                .prefix(5)
        )
        let periodSpans = CountRecordLogic.fleetPeriodSpanLabels(units: units, dayKey: dayKey)

        return RealtimeV4Snapshot(
            tripUnits: units,
            sandUnit: sand,
            statusLabel: CountRecordLogic.menuStatusLabel(
                dayKey: dayKey,
                transactions: transactions,
                employees: employees,
                tripUnits: units,
                sandUnit: sand
            ),
            efficiency: CountRecordLogic.vehicleEfficiency(
                dayKey: dayKey,
                tripUnits: units,
                transactions: transactions,
                employees: employees,
                priorKey: priorTripKey,
                byDay: dayIndex
            ),
            fleetWorkSpan: CountRecordLogic.fleetWorkSpanLabel(units: units, dayKey: dayKey),
            fleetMorningSpanLabel: periodSpans.morning,
            fleetAfternoonSpanLabel: periodSpans.afternoon,
            tripAnalytics: tripAnalytics,
            sandAnalytics: sandAnalytics,
            activityEvents: CountRecordAnalytics.buildActivityFeed(
                dayKey: dayKey,
                tripUnits: units,
                sandUnit: sand,
                limit: 40
            ),
            sandWorkSpan: sandWorkSpan,
            sandMorningSpanLabel: sandPeriodSpans.morning,
            sandAfternoonSpanLabel: sandPeriodSpans.afternoon,
            sandHours: sandHours,
            sandMorningHours: sandMorningHours,
            sandAfternoonHours: sandAfternoonHours,
            tripHours: tripHours,
            tripMorningHours: tripMorningHours,
            tripAfternoonHours: tripAfternoonHours,
            vehicleWorkSpans: vehicleWorkSpans,
            leaderboard: leaderboard,
            isLight: light
        )
    }

    nonisolated static func buildLight(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee]
    ) -> RealtimeV4Snapshot {
        build(dayKey: dayKey, transactions: transactions, employees: employees, light: true)
    }

    nonisolated static func empty() -> RealtimeV4Snapshot {
        build(dayKey: "", transactions: [], employees: [], light: true)
    }
}

enum RealtimeBoardMode: String, Sendable {
    case trip
    case sand
}

struct RealtimeV4View: View {
    let transactions: [Transaction]
    /// Pre-grouped day index from AppState — skips O(n) regroup on every rebuild.
    var transactionsByDay: [String: [Transaction]] = [:]
    let employees: [Employee]
    let settings: AppSettings
    var transactionsRevision: Int = 0
    var mode: RealtimeBoardMode = .trip
    /// True when either Real-time bottom tab is selected — drives snapshot rebuilds.
    var isRealtimeTabActive: Bool = true
    /// True when this specific trip/sand board is the visible tab.
    var isBoardVisible: Bool = true
    /// Shared with the sibling trip/sand tab so the selected day carries over.
    @Binding var focusDate: Date

    @State private var snapshot = RealtimeV4Snapshot.empty()
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showDatePicker = false
    @State private var lastRefresh = Date()
    @State private var boardPulse = false
    @State private var livePing = false
    @State private var selectedVehicle: CountRecordTripUnit?
    @State private var showSandDetail = false
    @State private var showFleetDetail = false
    @State private var pendingRebuild = false
    @State private var recentEventTimes: [Date] = []
    @State private var lastBuiltDayKey: String = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var buildSupervisor: RealtimeBuildSupervisor { RealtimeBuildSupervisor.shared }
    private var hangWatchdog: MainThreadWatchdog { MainThreadWatchdog.shared }

    private var focusDateStr: String { DashboardAggregations.formatYMD(focusDate) }
    private var todayStr: String { DashboardAggregations.formatYMD(Date()) }
    private var isToday: Bool { focusDateStr == todayStr }

    // Memoized analytics — rebuilt off-main (debounced) when inputs change.
    private var tripUnits: [CountRecordTripUnit] { snapshot.tripUnits }
    private var sandUnit: CountRecordSandUnit? { snapshot.sandUnit }
    private var tripTotal: Int { snapshot.tripTotal }
    private var sandRounds: Int { snapshot.sandRounds }
    private var efficiency: VehicleEfficiency { snapshot.efficiency }

    private var modeActivityEvents: [CountRecordAnalytics.ActivityEvent] {
        let want: CountRecordAnalytics.ActivityEvent.Kind = mode == .trip ? .trip : .sand
        return snapshot.activityEvents.filter { $0.kind == want }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroHeader
            healthStatusRow
            liveBoard
        }
        .onAppear {
            hangWatchdog.start()
            scheduleRebuild(force: lastBuiltDayKey != focusDateStr)
            lastRefresh = Date()
            // Soft pulse only — avoid repeatForever scale animations that invalidate layout every frame while scrolling.
            if !reduceMotion {
                livePing = true
            }
        }
        .onDisappear {
            hangWatchdog.stop()
            rebuildTask?.cancel()
            rebuildTask = nil
        }
        .onChange(of: focusDateStr) { _, _ in scheduleRebuild(force: true) }
        .onChange(of: transactionsRevision) { _, _ in
            noteIncomingEvent()
            scheduleRebuild()
            lastRefresh = Date()
        }
        .onChange(of: employees) { _, _ in scheduleRebuild() }
        .onChange(of: tripTotal) { _, _ in
            if mode == .trip { triggerPulse() }
        }
        .onChange(of: sandRounds) { _, _ in
            if mode == .sand { triggerPulse() }
        }
        .onChange(of: isRealtimeTabActive) { _, active in
            if active, pendingRebuild || lastBuiltDayKey != focusDateStr {
                scheduleRebuild(force: true)
            }
        }
        .onChange(of: isBoardVisible) { _, visible in
            if visible {
                scheduleRebuild(force: lastBuiltDayKey != focusDateStr)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                hangWatchdog.start()
                if pendingRebuild || lastBuiltDayKey != focusDateStr {
                    scheduleRebuild(force: true)
                }
            } else {
                hangWatchdog.stop()
            }
        }
        .sheet(item: $selectedVehicle) { unit in
            VehicleDetailSheet(unit: unit, dayKey: focusDateStr)
        }
        .sheet(isPresented: $showSandDetail) {
            if let sand = sandUnit {
                SandDetailSheet(
                    sand: sand,
                    dayKey: focusDateStr,
                    analytics: sandAnalytics,
                    morningSpanLabel: snapshot.sandMorningSpanLabel,
                    afternoonSpanLabel: snapshot.sandAfternoonSpanLabel,
                    activityEvents: modeActivityEvents
                )
            }
        }
        .sheet(isPresented: $showFleetDetail) {
            FleetTripDetailSheet(
                tripUnits: tripUnits,
                tripTotal: tripTotal,
                morningSpanLabel: snapshot.fleetMorningSpanLabel,
                afternoonSpanLabel: snapshot.fleetAfternoonSpanLabel,
                efficiency: efficiency,
                leaderboard: snapshot.leaderboard,
                analytics: tripAnalytics,
                activityEvents: modeActivityEvents,
                dayKey: focusDateStr
            )
        }
    }

    /// Coalesces rapid realtime/delta updates into one off-main snapshot build.
    private func scheduleRebuild(force: Bool = false) {
        let canBuild = force
            || (isRealtimeTabActive && scenePhase == .active)
        guard canBuild else {
            pendingRebuild = true
            return
        }
        pendingRebuild = false
        rebuildTask?.cancel()
        let dayKey = focusDateStr
        let txs = transactions
        let byDay = transactionsByDay.isEmpty
            ? Dictionary(grouping: transactions) { String($0.date.prefix(10)) }
            : transactionsByDay
        let emps = employees
        let cars = settings.cars
        let catalog = settings.vehicleCatalog
        let light = buildSupervisor.isEconomyMode
        let debounceNs = adaptiveDebounceNs()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled else { return }
            await MainActor.run { buildSupervisor.beginBuild() }
            let (built, ms) = await Task.detached(priority: .userInitiated) {
                RealtimeBuildSupervisor.measureBuild {
                    let focusTx = byDay[dayKey] ?? []
                    return RealtimeV4Snapshot.build(
                        dayKey: dayKey,
                        // Light builds only need the focus day; full builds keep the list for prior-day scans.
                        transactions: light ? focusTx : txs,
                        employees: emps,
                        cars: cars,
                        catalog: catalog,
                        light: light,
                        byDay: byDay
                    )
                }
            }.value
            await MainActor.run {
                buildSupervisor.endBuild(durationMs: ms, light: light)
                guard !Task.isCancelled else { return }
                snapshot = built
                lastBuiltDayKey = dayKey
            }
        }
    }

    private func noteIncomingEvent() {
        let now = Date()
        recentEventTimes.append(now)
        recentEventTimes.removeAll { now.timeIntervalSince($0) > 2 }
    }

    private func adaptiveDebounceNs() -> UInt64 {
        // More events in the last 2s → longer debounce (250ms … 900ms).
        // Economy mode always prefers the longer end to keep the main thread free.
        if buildSupervisor.isEconomyMode { return 900_000_000 }
        let n = recentEventTimes.count
        if n >= 8 { return 800_000_000 }
        if n >= 4 { return 500_000_000 }
        return 250_000_000
    }

    private func triggerPulse() {
        guard !reduceMotion else { return }
        // Pulse only the header badge — animating the whole board border/shadow during scroll caused freezes.
        withAnimation(.easeOut(duration: 0.2)) { boardPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeOut(duration: 0.25)) { boardPulse = false }
        }
    }

    // MARK: - Hero (date picker only)

    private var heroAccentColors: [Color] {
        switch mode {
        case .trip:
            return [Color(hex: "#1D4ED8"), Color(hex: "#2563EB"), Color(hex: "#0891B2")]
        case .sand:
            return [Color(hex: "#BE185D"), Color(hex: "#DB2777"), Color(hex: "#A21CAF")]
        }
    }

    private var heroHeader: some View {
        HStack(spacing: 10) {
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("กำลังดู")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.72))
                        HStack(spacing: 8) {
                            Text(thaiDateShort(focusDateStr))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if isToday {
                                Text("วันนี้")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color(hex: "#ECFDF5"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.22)))
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เลือกวันที่กำลังดู")
            .accessibilityHint("แตะเพื่อเลือกวันย้อนหลัง")

            if !isToday {
                Button {
                    focusDate = Date()
                } label: {
                    Text("กลับวันนี้")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: heroAccentColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: heroAccentColors.first?.opacity(0.18) ?? .clear, radius: 6, y: 2)
        .sheet(isPresented: $showDatePicker) {
            focusDatePickerSheet
        }
    }

    @ViewBuilder
    private var healthStatusRow: some View {
        let showBuilding = buildSupervisor.showBuildingChip
        let economy = buildSupervisor.isEconomyMode
        let hadHang = hangWatchdog.hangCount > 0
        if showBuilding || economy || hadHang {
            HStack(spacing: 8) {
                if showBuilding {
                    healthChip(icon: "hourglass", text: "กำลังคำนวณ…", action: nil)
                }
                if economy {
                    healthChip(icon: "bolt.slash.fill", text: "โหมดประหยัด") {
                        buildSupervisor.exitEconomyMode()
                        scheduleRebuild(force: true)
                    }
                }
                if hadHang {
                    healthChip(icon: "arrow.clockwise", text: "คำนวณใหม่") {
                        scheduleRebuild(force: true)
                    }
                }
            }
        }
    }

    private func healthChip(icon: String, text: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color(hex: "#FEF3C7"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(hex: "#92400E").opacity(0.85)))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private var focusDatePickerSheet: some View {
        RealtimeFocusCalendarSheet(
            selection: $focusDate,
            transactions: transactions,
            employees: employees,
            transactionsRevision: transactionsRevision,
            onDismiss: { showDatePicker = false }
        )
    }

    // MARK: - Live board

    private var tripAnalytics: CountRecordAnalytics.ModeAnalytics { snapshot.tripAnalytics }
    private var sandAnalytics: CountRecordAnalytics.ModeAnalytics { snapshot.sandAnalytics }

    private var liveBoard: some View {
        VStack(spacing: 0) {
            liveBoardHeader
            VStack(spacing: 16) {
                switch mode {
                case .trip:
                    tripPanel
                case .sand:
                    sandPanel
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [RealtimeV4Palette.panelTop, RealtimeV4Palette.panel, RealtimeV4Palette.panelTop],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(RealtimeV4Palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }

    private var liveBoardHeader: some View {
        ZStack {
            LinearGradient(
                colors: [RealtimeV4Palette.liveHeaderStart, RealtimeV4Palette.liveHeaderMid, RealtimeV4Palette.liveHeaderEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    liveBadge
                    if boardPulse {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color(hex: "#F59E0B"))
                            .transition(.opacity)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    switch mode {
                    case .trip:
                        metricChip(
                            icon: "truck.box.fill",
                            text: "\(CountRecordLogic.formatMetric(tripTotal)) เที่ยว",
                            bg: Color.blue.opacity(0.12),
                            fg: Color(light: Color(hex: "#1D4ED8"), dark: Color(hex: "#BFDBFE"))
                        )
                    case .sand:
                        metricChip(
                            icon: "drop.fill",
                            text: "\(CountRecordLogic.formatMetric(sandRounds)) รอบ",
                            bg: Color.pink.opacity(0.12),
                            fg: Color(light: Color(hex: "#BE185D"), dark: Color(hex: "#FBCFE8"))
                        )
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("โพล")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(RealtimeV4Palette.textMuted)
                        Text(timeString(lastRefresh))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(RealtimeV4Palette.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12).fill(RealtimeV4Palette.cardSoft))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            ZStack {
                if !reduceMotion && livePing {
                    Circle()
                        .fill(Color.emerald.opacity(0.35))
                        .frame(width: 10, height: 10)
                        .opacity(0.8)
                }
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
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onTapGesture { showFleetDetail = true }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("แตะเพื่อดูรายละเอียดรวมเที่ยวรถ")
                        tripKPI
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(tripUnits.enumerated()), id: \.element.id) { index, unit in
                            TripVehicleCard(
                                unit: unit,
                                index: index,
                                workSpan: snapshot.vehicleWorkSpans[unit.id]
                            )
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .onTapGesture { selectedVehicle = unit }
                        }
                    }
                }
            }
        }
    }

    private var tripMorningTotal: Int { tripUnits.reduce(0) { $0 + $1.morning } }
    private var tripAfternoonTotal: Int { tripUnits.reduce(0) { $0 + $1.afternoon } }

    private var tripSummaryHero: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#2563EB"), Color(hex: "#2563EB"), Color(hex: "#4338CA")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Text("รวมเที่ยวรถวันนี้")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.7))

                Text(CountRecordLogic.formatMetric(tripTotal))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tripTotal)
                    .modifier(ScoreFloatOverlay(value: tripTotal, dayKey: focusDateStr, unitLabel: "เที่ยว"))

                Text("เที่ยว")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))

                PeriodPill(
                    morning: tripMorningTotal,
                    afternoon: tripAfternoonTotal,
                    onDark: true
                )

                if snapshot.fleetMorningSpanLabel != nil || snapshot.fleetAfternoonSpanLabel != nil {
                    VStack(spacing: 6) {
                        if let morning = snapshot.fleetMorningSpanLabel {
                            WorkSpanBadge(label: morning, onDark: true)
                        }
                        if let afternoon = snapshot.fleetAfternoonSpanLabel {
                            WorkSpanBadge(label: afternoon, onDark: true)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text("แตะเพื่อดูรายละเอียด")
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 2)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var tripKPI: some View {
        let target = CountRecordLogic.tripTarget
        let queueTotal = tripTotal * CountRecordLogic.queuePerTrip
        let hours = snapshot.tripHours
        let tripsPerHour = hours.flatMap { $0 > 0 ? Double(tripTotal) / $0 : nil }
        let tripsPerMin = hours.flatMap { $0 > 0 ? Double(tripTotal) / ($0 * 60) : nil }
        let pct = target > 0
            ? min(Double(tripTotal) / Double(target) * 100, 100)
            : 0
        let eta = CountRecordAnalytics.computeTripTargetEta(
            tripUnits: tripUnits,
            dayKey: focusDateStr,
            target: target
        )
        let tripBlue = Color(hex: "#2563EB")
        let tripBlueSoft = Color(hex: "#DBEAFE")
        let tripBlueLabel = Color(light: Color(hex: "#1D4ED8"), dark: Color(hex: "#93C5FD"))

        return VStack(alignment: .leading, spacing: 10) {
            Text("ตัวชี้วัดการขน")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(tripBlueLabel)

            HStack(spacing: 8) {
                kpiCell(
                    title: "เที่ยว / ชม.",
                    value: tripsPerHour.map { String(format: "%.1f", $0) } ?? "—",
                    labelColor: tripBlueLabel,
                    fill: Color(light: tripBlueSoft, dark: tripBlue.opacity(0.22))
                )
                kpiCell(
                    title: "เที่ยว / นาที",
                    value: tripsPerMin.map { String(format: "%.2f", $0) } ?? "—",
                    labelColor: tripBlueLabel,
                    fill: Color(light: tripBlueSoft, dark: tripBlue.opacity(0.22))
                )
            }

            workHoursBlock(
                titleColor: tripBlueLabel,
                cellFill: Color(light: tripBlueSoft, dark: tripBlue.opacity(0.22)),
                total: snapshot.tripHours,
                morning: snapshot.tripMorningHours,
                afternoon: snapshot.tripAfternoonHours
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("เป้าหมาย \(CountRecordLogic.formatMetric(target)) เที่ยว/วัน")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RealtimeV4Palette.inkSecondary)
                    Spacer()
                    Text("\(CountRecordLogic.formatMetric(tripTotal)) / \(CountRecordLogic.formatMetric(target)) · \(Int(pct.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(RealtimeV4Palette.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(light: tripBlueSoft, dark: tripBlue.opacity(0.2)))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: eta.reached
                                        ? [Color(hex: "#10B981"), Color(hex: "#059669")]
                                        : [tripBlue, Color(hex: "#4338CA")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(pct / 100))
                    }
                }
                .frame(height: 8)

                if eta.reached {
                    Label("ถึงเป้าแล้ว", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#059669"))
                } else if let clock = eta.etaClock {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("คาดการณ์ถึงเป้าประมาณ \(clock)")
                            .font(.system(size: 11, weight: .semibold))
                        if let hoursLeft = eta.hoursLeft {
                            Text("· ~\(CountRecordAnalytics.formatDurationHours(hoursLeft))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                        }
                    }
                    .foregroundStyle(tripBlueLabel)
                } else {
                    Text("นับอย่างน้อย 2 เที่ยว เพื่อคาดการณ์เวลาถึงเป้า")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
                }

                Text("\(CountRecordLogic.formatMetric(queueTotal)) คิว · \(CountRecordLogic.queuePerTrip) คิว / 1 เที่ยว")
                    .font(.system(size: 9))
                    .foregroundStyle(RealtimeV4Palette.inkMuted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(light: Color(hex: "#EFF6FF"), dark: Color(hex: "#0B1220")),
                            Color(light: Color(hex: "#DBEAFE"), dark: Color(hex: "#111827"))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tripBlue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Sand panel

    private var sandPanel: some View {
        panelShell(
            title: "การร่อนทราย",
            subtitle: sandUnit.map { "\($0.rounds) คิว" } ?? "ยังไม่มีคิว",
            icon: "drop.fill",
            gradient: [Color(hex: "#BE185D"), Color(hex: "#E11D48"), Color(hex: "#C026D3")]
        ) {
            if let sand = sandUnit, sand.rounds > 0 {
                VStack(spacing: 12) {
                    sandHero(sand)
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture { showSandDetail = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("แตะเพื่อดูรายละเอียดร่อนทราย")
                    sandKPI(sand)
                }
            } else {
                emptyState(icon: "drop", title: "ยังไม่มีคิวทราย", subtitle: "รอการนับร่อนทรายจากมือถือ")
            }
        }
    }

    private func sandHero(_ sand: CountRecordSandUnit) -> some View {
        ZStack {
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
                    .modifier(ScoreFloatOverlay(value: sand.rounds, dayKey: focusDateStr, unitLabel: "คิว"))
                Text("คิว")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.8))
                PeriodPill(morning: sand.morning, afternoon: sand.afternoon, onDark: true)
                if snapshot.sandMorningSpanLabel != nil || snapshot.sandAfternoonSpanLabel != nil {
                    VStack(spacing: 6) {
                        if let morning = snapshot.sandMorningSpanLabel {
                            WorkSpanBadge(label: morning, onDark: true)
                        }
                        if let afternoon = snapshot.sandAfternoonSpanLabel {
                            WorkSpanBadge(label: afternoon, onDark: true)
                        }
                    }
                }
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sandKPI(_ sand: CountRecordSandUnit) -> some View {
        let hours = snapshot.sandHours
        let perHour = hours.flatMap { $0 > 0 ? Double(sand.rounds) / $0 : nil }
        let perMin = hours.flatMap { $0 > 0 ? Double(sand.rounds) / ($0 * 60) : nil }
        let target = CountRecordLogic.sandTarget
        let pct = target > 0
            ? min(Double(sand.rounds) / Double(target) * 100, 100)
            : 0
        let eta = CountRecordAnalytics.computeSandTargetEta(
            lapTimes: sand.lapTimes,
            dayKey: focusDateStr,
            target: target
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("ตัวชี้วัดร่อนทราย")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(RealtimeV4Palette.sandLabel)

            HStack(spacing: 8) {
                kpiCell(
                    title: "คิว / ชม.",
                    value: perHour.map { String(format: "%.1f" , $0) } ?? "—"
                )
                kpiCell(
                    title: "คิว / นาที",
                    value: perMin.map { String(format: "%.2f", $0) } ?? "—"
                )
            }

            workHoursBlock(
                titleColor: RealtimeV4Palette.sandLabel,
                cellFill: RealtimeV4Palette.sandCellFill,
                total: snapshot.sandHours,
                morning: snapshot.sandMorningHours,
                afternoon: snapshot.sandAfternoonHours
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("เป้าหมาย \(CountRecordLogic.formatMetric(target)) คิว/วัน")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RealtimeV4Palette.inkSecondary)
                    Spacer()
                    Text("\(CountRecordLogic.formatMetric(sand.rounds)) / \(CountRecordLogic.formatMetric(target)) · \(Int(pct.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(RealtimeV4Palette.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(RealtimeV4Palette.sandTrack)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: eta.reached
                                        ? [Color(hex: "#10B981"), Color(hex: "#059669")]
                                        : [Color(hex: "#EC4899"), Color(hex: "#DB2777")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(pct / 100))
                    }
                }
                .frame(height: 8)

                if eta.reached {
                    Label("ถึงเป้าแล้ว", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: "#059669"))
                } else if let clock = eta.etaClock {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("คาดการณ์ถึงเป้าประมาณ \(clock)")
                            .font(.system(size: 11, weight: .semibold))
                        if let hoursLeft = eta.hoursLeft {
                            Text("· ~\(CountRecordAnalytics.formatDurationHours(hoursLeft))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                        }
                    }
                    .foregroundStyle(Color(hex: "#BE185D"))
                } else {
                    Text("นับอย่างน้อย 2 คิว เพื่อคาดการณ์เวลาถึงเป้า")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [RealtimeV4Palette.sandPanelTop, RealtimeV4Palette.sandPanelBottom],
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

    /// Total + morning + afternoon active work hours (lunch deducted on full-day total).
    private func workHoursBlock(
        titleColor: Color,
        cellFill: Color,
        total: Double?,
        morning: Double?,
        afternoon: Double?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("เวลาทำงานจริง")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(titleColor)
            HStack(spacing: 8) {
                kpiCell(
                    title: "รวม",
                    value: Self.formatWorkHours(total),
                    labelColor: titleColor,
                    fill: cellFill
                )
                kpiCell(
                    title: "เช้า",
                    value: Self.formatWorkHours(morning),
                    labelColor: titleColor,
                    fill: cellFill
                )
                kpiCell(
                    title: "บ่าย",
                    value: Self.formatWorkHours(afternoon),
                    labelColor: titleColor,
                    fill: cellFill
                )
            }
        }
    }

    private static func formatWorkHours(_ hours: Double?) -> String {
        guard let hours, hours > 0, hours.isFinite else { return "—" }
        return CountRecordAnalytics.formatDurationHours(hours)
    }

    private func kpiCell(
        title: String,
        value: String,
        labelColor: Color = RealtimeV4Palette.sandLabel,
        fill: Color = RealtimeV4Palette.sandCellFill
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(labelColor)
            Text(value)
                .font(.title3.weight(.black))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(RealtimeV4Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(fill))
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
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(RealtimeV4Palette.inkMuted)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 16).fill(RealtimeV4Palette.cardSoft))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RealtimeV4Palette.inkSecondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(RealtimeV4Palette.inkMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                .foregroundStyle(RealtimeV4Palette.border)
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

// MARK: - Score popup (+N / -N pro toast)

/// Floating +N / -N toast when a live count changes (skips day switches and Reduce Motion).
private struct ScoreFloatOverlay: ViewModifier {
    let value: Int
    let dayKey: String
    var unitLabel: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastValue: Int?
    @State private var lastDayKey: String?
    @State private var popupDelta: Int?
    @State private var popupID = UUID()
    @State private var floatAway = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if let delta = popupDelta, delta != 0 {
                    let positive = delta > 0
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            if unitLabel == "เที่ยว" {
                                Image(systemName: "truck.box.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))
                            } else if unitLabel == "คิว" {
                                Image(systemName: "drop.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))
                            }
                            Text(positive ? "+\(delta)" : "\(delta)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        if !unitLabel.isEmpty {
                            Text(unitLabel)
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: positive
                                        ? (unitLabel == "เที่ยว"
                                            ? [Color(hex: "#1D4ED8"), Color(hex: "#2563EB"), Color(hex: "#0EA5E9")]
                                            : [Color(hex: "#059669"), Color(hex: "#10B981")])
                                        : [Color(hex: "#E11D48"), Color(hex: "#FB7185")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(
                                color: (positive
                                    ? (unitLabel == "เที่ยว" ? Color(hex: "#2563EB") : Color(hex: "#059669"))
                                    : Color(hex: "#E11D48")).opacity(0.5),
                                radius: 20,
                                y: 8
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    )
                    .scaleEffect(floatAway ? 1.1 : 0.68)
                    .opacity(floatAway ? 0 : 1)
                    .offset(y: floatAway ? -64 : 0)
                    .allowsHitTesting(false)
                    .id(popupID)
                    .accessibilityHidden(true)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
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

// MARK: - Subviews

private struct TripVehicleCard: View {
    let unit: CountRecordTripUnit
    let index: Int
    var workSpan: String? = nil

    private var accent: Color {
        Color(hex: CountRecordLogic.vehicleColors[index % CountRecordLogic.vehicleColors.count])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [accent, accent.opacity(0.85), Color(hex: "#0F172A")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 80, height: 80)
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
                        .modifier(ScoreFloatOverlay(value: unit.rounds, dayKey: unit.id, unitLabel: "เที่ยว"))
                    Text("เที่ยว")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.75))
                    PeriodPill(
                        morning: unit.morning,
                        afternoon: unit.afternoon,
                        onDark: true
                    )
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 3) {
                    Text(unit.vehicleId)
                        .font(.caption.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
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
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
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

struct VehicleDetailContent: View {
    let unit: CountRecordTripUnit
    let dayKey: String

    private var workSpan: String? {
        CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: unit.lapTimes, dayKey: dayKey)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(unit.vehicleId)
                    .font(.title2.weight(.black))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Label(unit.driverLabel, systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(unit.rounds)")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(RealtimeV4Palette.ink)
                Text("เที่ยว").font(.title3.weight(.bold)).foregroundStyle(RealtimeV4Palette.inkSecondary)
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
                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
            }

            LapTimeList(title: "เวลาประทับทุกเที่ยว", lapTimes: unit.lapTimes)
        }
    }
}

private struct VehicleDetailSheet: View {
    let unit: CountRecordTripUnit
    let dayKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VehicleDetailContent(unit: unit, dayKey: dayKey)
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
    }
}

private struct FleetTripDetailSheet: View {
    let tripUnits: [CountRecordTripUnit]
    let tripTotal: Int
    let morningSpanLabel: String?
    let afternoonSpanLabel: String?
    let efficiency: VehicleEfficiency
    let leaderboard: [CountRecordTripUnit]
    let analytics: CountRecordAnalytics.ModeAnalytics
    let activityEvents: [CountRecordAnalytics.ActivityEvent]
    let dayKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var allRounds: [FleetRoundRow] = []

    private struct FleetRoundRow: Identifiable, Sendable {
        let id: Int
        let vehicleId: String
        let stamp: String
        let gapSec: Double?
    }

    private var morningTotal: Int { tripUnits.reduce(0) { $0 + $1.morning } }
    private var afternoonTotal: Int { tripUnits.reduce(0) { $0 + max(0, $1.afternoon - $1.ot) } }
    private var otTotal: Int { tripUnits.reduce(0) { $0 + $1.ot } }
    private var queueTotal: Int { tripTotal * CountRecordLogic.queuePerTrip }
    private var targetPct: Double {
        CountRecordLogic.tripTarget > 0
            ? min(Double(tripTotal) / Double(CountRecordLogic.tripTarget) * 100, 100)
            : 0
    }
    private var ranked: [CountRecordTripUnit] {
        tripUnits.sorted { $0.rounds > $1.rounds }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CountRecordLogic.formatMetric(tripTotal))
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text("เที่ยว")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.inkSecondary)
                        Spacer()
                    }

                    DetailStatRow(items: [
                        ("คิว", CountRecordLogic.formatMetric(queueTotal)),
                        ("เป้าหมาย", "\(CountRecordLogic.formatMetric(CountRecordLogic.tripTarget)) เที่ยว"),
                        ("คืบหน้า", "\(Int(targetPct.rounded()))%")
                    ])

                    DetailStatRow(items: [
                        ("เช้า", "\(morningTotal)"),
                        ("บ่าย", "\(afternoonTotal)"),
                        ("OT", "\(otTotal)")
                    ])

                    if morningSpanLabel != nil || afternoonSpanLabel != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if let morningSpanLabel {
                                Label(morningSpanLabel, systemImage: "sun.max.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
                            }
                            if let afternoonSpanLabel {
                                Label(afternoonSpanLabel, systemImage: "sunset.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ประสิทธิภาพ")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                        HStack {
                            Text(String(format: "%.1f เที่ยว/คัน", efficiency.perVehToday))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(RealtimeV4Palette.ink)
                            Spacer()
                            EfficiencyBadge(efficiency: efficiency)
                        }
                        Text("\(efficiency.countToday) คันที่นับ")
                            .font(.caption)
                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(RealtimeV4Palette.cardSoft))

                    recentLeaderboardCard

                    RealtimeV4ActivityFeed(
                        events: activityEvents,
                        dayKey: dayKey,
                        tripUnits: tripUnits,
                        sandUnit: nil
                    )

                    if analytics.rounds > 0 {
                        RealtimeV4AnalyticsPanel(analytics: analytics, accent: Color(hex: "#38BDF8"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("แยกรายคัน")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(RealtimeV4Palette.inkMuted)

                        if ranked.isEmpty {
                            Text("ยังไม่มีรถที่นับวันนี้")
                                .font(.caption)
                                .foregroundStyle(RealtimeV4Palette.inkFaint)
                        } else {
                            ForEach(ranked) { unit in
                                NavigationLink {
                                    ScrollView {
                                        VehicleDetailContent(unit: unit, dayKey: dayKey)
                                            .padding(20)
                                    }
                                    .background(RealtimeV4Palette.page.ignoresSafeArea())
                                    .navigationTitle(unit.vehicleId)
                                    .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(unit.vehicleId)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(RealtimeV4Palette.ink)
                                            Text(unit.driverLabel)
                                                .font(.caption)
                                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                                        }
                                        Spacer()
                                        Text("\(unit.rounds) เที่ยว")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color(hex: "#2563EB")))
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(RealtimeV4Palette.inkFaint)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(RealtimeV4Palette.cardSoft)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("รอบทั้งหมด")
                                .font(.system(size: 11, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                            Spacer()
                            Text("\(allRounds.count) รอบ")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RealtimeV4Palette.inkFaint)
                        }

                        if allRounds.isEmpty {
                            Text("ยังไม่มีเวลาประทับ")
                                .font(.caption)
                                .foregroundStyle(RealtimeV4Palette.inkFaint)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(allRounds) { row in
                                    HStack(spacing: 10) {
                                        Text("#\(row.id)")
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(RealtimeV4Palette.inkMuted)
                                            .frame(width: 36, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.vehicleId)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(RealtimeV4Palette.ink)
                                            Text(CountRecordLogic.formatLapClock(row.stamp) ?? row.stamp)
                                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                                        }
                                        Spacer()
                                        if let gap = row.gapSec {
                                            Text(CountRecordAnalytics.formatPace(gap))
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Color(hex: "#2563EB"))
                                        } else {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundStyle(RealtimeV4Palette.inkFaint)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(RealtimeV4Palette.cardSoft)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("รวมเที่ยวรถวันนี้")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                let units = tripUnits
                let key = dayKey
                let built = await Task.detached(priority: .userInitiated) {
                    Self.buildAllRounds(units: units, dayKey: key)
                }.value
                allRounds = built
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var recentLeaderboardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("บันทึกล่าสุด")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(RealtimeV4Palette.textMuted)
            if leaderboard.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(RealtimeV4Palette.inkFaint)
            } else {
                ForEach(Array(leaderboard.enumerated()), id: \.element.id) { rank, unit in
                    HStack(spacing: 8) {
                        if rank == 0 {
                            Image(systemName: "trophy.fill").foregroundStyle(Color(hex: "#FBBF24"))
                        } else if rank <= 2 {
                            Image(systemName: "medal.fill")
                                .foregroundStyle(rank == 1 ? Color(hex: "#94A3B8") : Color(hex: "#D97706"))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(unit.vehicleId)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(RealtimeV4Palette.ink)
                            if let last = unit.lapTimes.last {
                                Text(CountRecordLogic.formatLapClock(last) ?? last)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(RealtimeV4Palette.inkMuted)
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
                            .fill(rank == 0 ? Color(hex: "#F59E0B").opacity(0.14) : RealtimeV4Palette.cardSoft)
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

    nonisolated private static func buildAllRounds(units: [CountRecordTripUnit], dayKey: String) -> [FleetRoundRow] {
        struct StampItem {
            let vehicleId: String
            let stamp: String
            let ms: Double
        }
        var items: [StampItem] = []
        for unit in units {
            for stamp in unit.lapTimes {
                guard let ms = CountRecordLogic.parseLapStamp(stamp, dayKey: dayKey) else { continue }
                items.append(StampItem(vehicleId: unit.vehicleId, stamp: stamp, ms: ms))
            }
        }
        items.sort { $0.ms < $1.ms }
        var rows: [FleetRoundRow] = []
        rows.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            var gap: Double?
            if index > 0 {
                let sec = CountRecordAnalytics.activeDurationSec(startMs: items[index - 1].ms, endMs: item.ms)
                if sec > 0 { gap = sec }
            }
            rows.append(
                FleetRoundRow(
                    id: index + 1,
                    vehicleId: item.vehicleId,
                    stamp: item.stamp,
                    gapSec: gap
                )
            )
        }
        return rows
    }
}

private struct SandRoundsSheet: View {
    let sand: CountRecordSandUnit
    let dayKey: String
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [RoundRow] = []

    private struct RoundRow: Identifiable, Sendable {
        let id: Int
        let stamp: String
        let gapSec: Double?
        let isLatest: Bool
    }

    private var workSpan: String? {
        CountRecordLogic.formatWorkSpanLabel(
            CountRecordLogic.computeWorkSpan(lapTimes: sand.lapTimes, dayKey: dayKey)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CountRecordLogic.formatMetric(sand.lapTimes.count))
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text("รอบ")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(RealtimeV4Palette.inkSecondary)
                        Spacer()
                    }

                    PeriodPill(morning: sand.morning, afternoon: sand.afternoon)

                    if let workSpan {
                        Label(workSpan, systemImage: "clock")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RealtimeV4Palette.inkSecondary)
                    }

                    if rows.isEmpty {
                        Text("ยังไม่มีเวลาประทับ")
                            .font(.caption)
                            .foregroundStyle(RealtimeV4Palette.inkFaint)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(rows) { row in
                                HStack(spacing: 10) {
                                    Text("รอบ \(row.id)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(row.isLatest ? Color(hex: "#FCE7F3") : RealtimeV4Palette.sandLabel)
                                    Text(CountRecordLogic.formatLapClock(row.stamp) ?? row.stamp)
                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(row.isLatest ? .white.opacity(0.95) : RealtimeV4Palette.ink)
                                    Spacer()
                                    if let gap = row.gapSec {
                                        Text(CountRecordAnalytics.formatPace(gap))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(row.isLatest ? Color(hex: "#FCE7F3") : RealtimeV4Palette.inkMuted)
                                    } else {
                                        Text("—")
                                            .font(.caption)
                                            .foregroundStyle(row.isLatest ? .white.opacity(0.55) : RealtimeV4Palette.inkFaint)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(row.isLatest ? Color(hex: "#DB2777") : RealtimeV4Palette.cardSoft)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(row.isLatest ? Color.clear : Color(hex: "#EC4899").opacity(0.25), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(RealtimeV4Palette.page.ignoresSafeArea())
            .navigationTitle("รอบทั้งหมด · ร่อนทราย")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task {
                let laps = sand.lapTimes
                let key = dayKey
                let built = await Task.detached(priority: .userInitiated) {
                    Self.buildRows(lapTimes: laps, dayKey: key)
                }.value
                rows = built
            }
        }
        .presentationDetents([.medium, .large])
    }

    nonisolated private static func buildRows(lapTimes: [String], dayKey: String) -> [RoundRow] {
        let intervals = CountRecordAnalytics.computeLapIntervals(lapTimes: lapTimes, dayKey: dayKey)
        let aligned = intervals.count == max(0, lapTimes.count - 1)
        return lapTimes.enumerated().map { index, stamp in
            let gap: Double?
            if index == 0 {
                gap = nil
            } else if aligned {
                gap = intervals[index - 1]
            } else if let prev = CountRecordLogic.parseLapStamp(lapTimes[index - 1], dayKey: dayKey),
                      let curr = CountRecordLogic.parseLapStamp(stamp, dayKey: dayKey) {
                let sec = CountRecordAnalytics.activeDurationSec(startMs: prev, endMs: curr)
                gap = sec > 0 ? sec : nil
            } else {
                gap = nil
            }
            return RoundRow(
                id: index + 1,
                stamp: stamp,
                gapSec: gap,
                isLatest: index == lapTimes.count - 1
            )
        }
    }
}

private struct SandDetailSheet: View {
    let sand: CountRecordSandUnit
    let dayKey: String
    let analytics: CountRecordAnalytics.ModeAnalytics
    let morningSpanLabel: String?
    let afternoonSpanLabel: String?
    let activityEvents: [CountRecordAnalytics.ActivityEvent]
    @Environment(\.dismiss) private var dismiss
    @State private var showSandRounds = false

    private var hours: Double? { CountRecordLogic.activeDurationHours(lapTimes: sand.lapTimes, dayKey: dayKey) }
    private var perHour: Double? { hours.flatMap { $0 > 0 ? Double(sand.rounds) / $0 : nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(CountRecordLogic.formatMetric(sand.rounds))
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(RealtimeV4Palette.ink)
                        Text("รอบ").font(.title3.weight(.bold)).foregroundStyle(RealtimeV4Palette.inkSecondary)
                    }

                    DetailStatRow(items: [
                        ("เช้า", "\(sand.morning)"),
                        ("บ่าย", "\(max(0, sand.afternoon - sand.ot))"),
                        ("OT", "\(sand.ot)")
                    ])

                    DetailStatRow(items: [
                        ("คิว/ชม.", perHour.map { String(format: "%.1f", $0) } ?? "—"),
                        ("เป้า \(CountRecordLogic.sandTarget) คิว", "\(CountRecordLogic.formatMetric(sand.rounds))"),
                        ("คงเหลือ", "\(max(0, CountRecordLogic.sandTarget - sand.rounds))")
                    ])

                    if morningSpanLabel != nil || afternoonSpanLabel != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if let morningSpanLabel {
                                Label(morningSpanLabel, systemImage: "sun.max.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
                            }
                            if let afternoonSpanLabel {
                                Label(afternoonSpanLabel, systemImage: "sunset.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RealtimeV4Palette.inkSecondary)
                            }
                        }
                    }

                    recentLapsCard

                    RealtimeV4ActivityFeed(
                        events: activityEvents,
                        dayKey: dayKey,
                        tripUnits: [],
                        sandUnit: sand
                    )

                    if analytics.rounds > 0 {
                        RealtimeV4AnalyticsPanel(
                            analytics: analytics,
                            accent: Color(hex: "#F472B6"),
                            chartsAlwaysExpanded: true
                        )
                    }
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
        .sheet(isPresented: $showSandRounds) {
            SandRoundsSheet(sand: sand, dayKey: dayKey)
        }
    }

    private var recentLapsCard: some View {
        let start = max(0, sand.lapTimes.count - CountRecordLogic.sandRecentLaps)
        let recent = Array(sand.lapTimes.enumerated()).filter { $0.offset >= start }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("รอบล่าสุด")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(RealtimeV4Palette.textMuted)
                Spacer()
                if !sand.lapTimes.isEmpty {
                    HStack(spacing: 4) {
                        Text("ดูทั้งหมด")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(RealtimeV4Palette.sandLabel)
                }
            }
            if recent.isEmpty {
                Text("ยังไม่มีเวลาประทับ")
                    .font(.caption)
                    .foregroundStyle(RealtimeV4Palette.inkFaint)
            } else {
                FlexibleChipWrap(spacing: 6) {
                    ForEach(recent, id: \.offset) { item in
                        let roundNo = item.offset + 1
                        let latest = roundNo == sand.lapTimes.count
                        HStack(spacing: 6) {
                            Text("รอบ \(roundNo)")
                                .foregroundStyle(latest ? Color(hex: "#FCE7F3") : RealtimeV4Palette.sandLabel)
                            Text(CountRecordLogic.formatLapClock(item.element) ?? item.element)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(latest ? .white.opacity(0.9) : RealtimeV4Palette.inkMuted)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(latest ? Color(hex: "#DB2777") : RealtimeV4Palette.cardSoft)
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !sand.lapTimes.isEmpty else { return }
            showSandRounds = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("แตะเพื่อดูรอบทั้งหมด")
    }
}

struct DetailStatRow: View {
    let items: [(String, String)]
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Text(item.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(RealtimeV4Palette.inkMuted)
                    Text(item.1).font(.title3.weight(.black)).foregroundStyle(RealtimeV4Palette.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(RealtimeV4Palette.cardSoft))
            }
        }
    }
}

struct LapTimeList: View {
    let title: String
    let lapTimes: [String]
    /// Cap visible stamps to avoid laying out hundreds of cells in detail sheets.
    var visibleLimit: Int = 60

    private var visible: [(offset: Int, element: String)] {
        let total = lapTimes.count
        if total <= visibleLimit {
            return Array(lapTimes.enumerated())
        }
        let start = total - visibleLimit
        return Array(lapTimes.enumerated()).filter { $0.offset >= start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(RealtimeV4Palette.inkMuted)
            if lapTimes.isEmpty {
                Text("ยังไม่มีเวลาประทับ").font(.caption).foregroundStyle(RealtimeV4Palette.inkFaint)
            } else {
                if lapTimes.count > visibleLimit {
                    Text("แสดง \(visibleLimit) รอบล่าสุด จาก \(lapTimes.count)")
                        .font(.caption2)
                        .foregroundStyle(RealtimeV4Palette.inkFaint)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(visible, id: \.offset) { item in
                        HStack(spacing: 6) {
                            Text("\(item.offset + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(RealtimeV4Palette.inkMuted)
                            Text(CountRecordLogic.formatLapClock(item.element) ?? item.element)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(RealtimeV4Palette.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(RealtimeV4Palette.cardSoft))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PeriodPill: View {
    let morning: Int
    /// Includes post-17:00 laps (formerly split out as OT/เย็น).
    let afternoon: Int
    var onDark: Bool = false

    private var hasAny: Bool { morning > 0 || afternoon > 0 }

    @ViewBuilder
    var body: some View {
        if hasAny {
            HStack(spacing: 6) {
                if morning > 0 {
                    pill("sun.max.fill", "เช้า \(morning)",
                         bg: onDark ? Color(hex: "#FBBF24").opacity(0.3) : Color(hex: "#FEF3C7"),
                         fg: onDark ? Color(hex: "#FFFBEB") : Color(hex: "#78350F"))
                }
                if afternoon > 0 {
                    pill("sunset.fill", "บ่าย \(afternoon)",
                         bg: onDark ? Color(hex: "#38BDF8").opacity(0.3) : Color(hex: "#E0E7FF"),
                         fg: onDark ? Color(hex: "#F0F9FF") : Color(hex: "#312E81"))
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

private extension Color {
    static let emerald = Color(hex: "#10B981")
}
