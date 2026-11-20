import SwiftUI

/// Memoized bundle of Overview analytics — kept for mobile ops KPIs on the home summary.
struct OverviewSnapshot: Sendable {
    let expenseTotal: Double
    let prevExpenseTotal: Double
    let prevFilter: DateFilter
    let numDays: Int
    let costSlices: [ChartSlice]
    let dailyBreakdown: [DailyExpenseBreakdown]
    let weeklyBuckets: [WeeklyExpenseBucket]
    let vehicleCosts: [VehicleCostRow]
    let dayChangePct: Int
    let sand: SandOverviewKPIs
    let sandSeriesWashed: [Double]
    let sandSeriesTransported: [Double]
    let sandSeriesLabels: [String]
    let sandCumulative: [Double]
    let drums: SandDrumsSeries
    let sandCur: (washed: Double, transported: Double)
    let sandPrev: (washed: Double, transported: Double)
    let mobileToday: MobileOpsMetrics
    let mobileRange: MobileOpsMetrics
    let mobilePrev: MobileOpsMetrics
    let quality: DataQualitySummary
    let alerts: [OverviewAlert]
    let insights: [String]
    let csvText: String
    let txCount: Int

    nonisolated static func empty(filter: DateFilter) -> OverviewSnapshot {
        let emptySand = SandOverviewKPIs(
            washed: 0, transported: 0, remaining: 0, forecastLabel: "0 (สมดุล)",
            avgWashedPerDay: 0, avgTransportedPerDay: 0,
            drumsObtained: 0, drumsHome: 0, drumsRemaining: 0
        )
        let emptyDrums = SandDrumsSeries(
            obtained: [], home: [], remainingCumulative: [],
            labels: [], dates: [], totalObtained: 0, totalHome: 0
        )
        let quality = DataQualitySummary(
            totalDays: 0, daysWithRecords: 0, coveragePct: 0,
            daysWithSand: 0, sandCoveragePct: 0
        )
        return OverviewSnapshot(
            expenseTotal: 0, prevExpenseTotal: 0, prevFilter: filter,
            numDays: 1, costSlices: [], dailyBreakdown: [],
            weeklyBuckets: [], vehicleCosts: [], dayChangePct: 0,
            sand: emptySand, sandSeriesWashed: [], sandSeriesTransported: [],
            sandSeriesLabels: [], sandCumulative: [], drums: emptyDrums,
            sandCur: (0, 0), sandPrev: (0, 0),
            mobileToday: .empty, mobileRange: .empty, mobilePrev: .empty,
            quality: quality, alerts: [], insights: [],
            csvText: "", txCount: 0
        )
    }

    nonisolated static func build(
        filter: DateFilter,
        transactions: [Transaction],
        allTransactions: [Transaction],
        settings: AppSettings,
        employees: [Employee]
    ) -> OverviewSnapshot {
        let curTx = transactions
        let prevFilter = DashboardAggregations.previousPeriodFilter(filter)
        let prevTx = DashboardAggregations.filterByRange(allTransactions, range: prevFilter)
        let expenseTotal = DashboardAggregations.totalExpense(curTx)
        let prevExpenseTotal = DashboardAggregations.totalExpense(prevTx)
        let numDays = DashboardAggregations.countInclusiveDays(filter.start, filter.end)

        let daily = DashboardAggregations.dailyExpenseBreakdown(filter: filter, transactions: curTx)
        var dayChange = 0
        if daily.count >= 2 {
            let today = daily[daily.count - 1].total
            let yesterday = daily[daily.count - 2].total
            if yesterday > 0 {
                dayChange = Int(round(((today - yesterday) / yesterday) * 100))
            }
        }

        let sandSeries = DashboardAggregations.buildDailySandSeries(filter: filter, transactions: curTx)
        let sandKPIs = DashboardAggregations.sandOverviewKPIs(filter: filter, transactions: curTx)
        let drums = DashboardAggregations.sandDrumsSeries(filter: filter, transactions: curTx)
        let sandCum = DashboardAggregations.cumulative(
            zip(sandSeries.washed, sandSeries.transported).map { $0 - $1 }
        )
        let sandCur = DashboardAggregations.sandTotals(curTx)
        let sandPrev = DashboardAggregations.sandTotals(prevTx)
        let focusDay = DashboardAggregations.focusDayKey(from: filter)
        let mobile = MobileOpsSnapshot.build(
            filter: filter,
            allTransactions: allTransactions,
            employees: employees,
            todayKey: focusDay
        )
        let quality = DashboardAggregations.dataQuality(filter: filter, transactions: curTx)
        let alerts = DashboardAggregations.buildOverviewAlerts(
            curExpense: expenseTotal, prevExpense: prevExpenseTotal, quality: quality
        )
        let insights = DashboardAggregations.buildOverviewInsights(
            curExpense: expenseTotal,
            prevExpense: prevExpenseTotal,
            sandWashed: sandCur.washed,
            sandTransported: sandCur.transported,
            quality: quality,
            mobileCur: mobile.range,
            mobilePrev: mobile.prevRange
        )
        let csv = DashboardAggregations.overviewCSV(
            curExpense: expenseTotal,
            prevExpense: prevExpenseTotal,
            sandCur: sandCur,
            sandPrev: sandPrev,
            mobileCur: mobile.range,
            mobilePrev: mobile.prevRange
        )

        return OverviewSnapshot(
            expenseTotal: expenseTotal,
            prevExpenseTotal: prevExpenseTotal,
            prevFilter: prevFilter,
            numDays: numDays,
            costSlices: DashboardAggregations.costStructureSlices(curTx),
            dailyBreakdown: daily,
            weeklyBuckets: DashboardAggregations.weeklyExpenseBuckets(filter: filter, transactions: curTx),
            vehicleCosts: DashboardAggregations.vehicleCostBreakdown(transactions: curTx, cars: settings.cars),
            dayChangePct: dayChange,
            sand: sandKPIs,
            sandSeriesWashed: sandSeries.washed,
            sandSeriesTransported: sandSeries.transported,
            sandSeriesLabels: sandSeries.labels,
            sandCumulative: sandCum,
            drums: drums,
            sandCur: sandCur,
            sandPrev: sandPrev,
            mobileToday: mobile.today,
            mobileRange: mobile.range,
            mobilePrev: mobile.prevRange,
            quality: quality,
            alerts: alerts,
            insights: insights,
            csvText: csv,
            txCount: curTx.count
        )
    }
}

// MARK: - View (clean executive ops summary)

struct OverviewHubView: View {
    let transactions: [Transaction]
    let allTransactions: [Transaction]
    /// Full fuel ledger (since cutover) merged with the window — tank balances only.
    var fuelTransactions: [Transaction]? = nil
    let employees: [Employee]
    let settings: AppSettings
    let dateFilter: DateFilter
    var greetingName: String? = nil
    /// Prefer revision over Equatable-diffing the full transaction arrays.
    var transactionsRevision: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var snapshot = OverviewSnapshot.empty(filter: DateFilter(start: "", end: ""))
    @State private var todayOps = TodayOpsSnapshot.empty
    @State private var homePro = HomeProSnapshot.empty
    @State private var analyticsWatchlist: [OpsTrendAlert] = []
    @State private var drumRows: [HomeDrumTripRow] = []
    @State private var macroRows: [HomeMacroVehicleRow] = []
    @State private var dailyEventRows: [Transaction] = []
    @State private var hasBuiltInitialSnapshot = false
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showAllWorkingStaff = false

    private var leaveNamesToday: [String] {
        todayOps.staffRows
            .filter { $0.status == .leave }
            .map(\.name)
    }

    private var focusDayKey: String {
        DashboardAggregations.focusDayKey(from: dateFilter)
    }

    private var isFocusToday: Bool {
        focusDayKey == DashboardAggregations.todayYMD()
    }

    private var isMultiDayRange: Bool {
        !dateFilter.start.isEmpty && !dateFilter.end.isEmpty && dateFilter.start != dateFilter.end
    }

    private var summaryDayTitle: String {
        isFocusToday ? "การเงินและน้ำมันวันนี้" : "การเงินและน้ำมัน · \(DashboardAggregations.thaiDateLong(focusDayKey))"
    }

    private var opsDayTitle: String {
        isFocusToday ? "สรุปงานภาคสนามวันนี้" : "สรุปงาน · \(DashboardAggregations.thaiDateLong(focusDayKey))"
    }

    private var dailyEventsTitle: String {
        if isFocusToday { return "เหตุการณ์วันนี้" }
        return "เหตุการณ์ · \(DashboardAggregations.thaiDateLong(focusDayKey))"
    }

    private var greetingDisplay: String {
        let raw = (greetingName ?? settings.appName).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return settings.appName }
        if raw.hasPrefix("คุณ") { return raw }
        return "คุณ\(raw)"
    }

    private var todayLabel: String {
        let key = todayOps.dayKey.isEmpty ? DashboardAggregations.todayYMD() : todayOps.dayKey
        return DashboardAggregations.thaiDateLong(key)
    }

    private var periodLabel: String {
        let start = dateFilter.start
        let end = dateFilter.end
        if start.isEmpty || end.isEmpty { return "ช่วงที่เลือก" }
        if start == end { return DashboardAggregations.thaiDateLong(start) }
        return "\(start) – \(end)"
    }

    private var showFuelCard: Bool {
        let metrics = snapshot.mobileToday
        return metrics.fuelOutLiters > 0
            || metrics.fuelInLiters > 0
            || todayOps.mainDieselLiters != 0
            || todayOps.reserveDieselLiters != 0
    }

    private var showLaborCard: Bool {
        todayOps.laborBaht > 0 || todayOps.presentCount > 0
    }

    private var showVehicleCard: Bool {
        todayOps.vehicleBaht > 0
    }

    var body: some View {
        Group {
            if !hasBuiltInitialSnapshot && !allTransactions.isEmpty {
                HomeOverviewSkeletonView()
                    .transition(.opacity)
            } else {
                overviewScroll
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .none : .smooth(duration: 0.28), value: hasBuiltInitialSnapshot)
        .onAppear { scheduleRebuild() }
        .onDisappear {
            rebuildTask?.cancel()
            rebuildTask = nil
        }
        .onChange(of: dateFilter) { _, _ in
            showAllWorkingStaff = false
            scheduleRebuild()
        }
        .onChange(of: transactionsRevision) { _, _ in scheduleRebuild() }
        .onChange(of: employees.count) { _, _ in scheduleRebuild() }
        .onChange(of: settings.cars) { _, _ in scheduleRebuild() }
        .onChange(of: settings.vehicleCatalog) { _, _ in scheduleRebuild() }
    }

    private var overviewScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                HomeProCommandHero(
                    greetingName: greetingDisplay,
                    dayTitle: todayLabel,
                    pro: homePro,
                    laborBahtLabel: homePro.health == .strong
                        ? "งานหลักครบ · ค่าแรง \(DashboardAggregations.formatCurrency(todayOps.laborBaht))"
                        : "",
                    presentCount: todayOps.presentCount
                )
                .homeAppear(index: 0)

                HomeProChecklistCard(pro: homePro)
                    .homeAppear(index: 1)

                HomeProInsightStrip(insights: homePro.insights, alerts: homePro.alerts)
                    .homeAppear(index: 2)

                OpsTrendHomeWatchlistCard(alerts: analyticsWatchlist)
                    .homeAppear(index: 2)

                HomeDailyEventsCard(rows: dailyEventRows, title: dailyEventsTitle)
                    .homeAppear(index: 3)

                financeAndFuelSection
                    .homeAppear(index: 4)

                HomeOpsMetricsSection(
                    title: opsDayTitle,
                    metrics: snapshot.mobileToday,
                    homePro: homePro,
                    leaveNamesToday: leaveNamesToday,
                    isFocusToday: isFocusToday,
                    summaryDayTitle: summaryDayTitle
                )
                .homeAppear(index: 5)

                HomeFleetSection(drumRows: drumRows, macroRows: macroRows)
                    .homeAppear(index: 6)

                HomeStaffCard(
                    todayOps: todayOps,
                    leaveNamesToday: leaveNamesToday,
                    showAllWorkingStaff: $showAllWorkingStaff
                )
                .homeAppear(index: 7)

                if isMultiDayRange {
                    HomePeriodRangeCard(range: snapshot.mobileRange, periodLabel: periodLabel)
                        .homeAppear(index: 7)
                }
            }
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.top, 10)
            .padding(.bottom, AppTheme.spaceXL)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var financeAndFuelSection: some View {
        if showFuelCard || showLaborCard || showVehicleCard {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionHeader(title: summaryDayTitle)

                if showFuelCard {
                    HomeFuelOverviewCard(
                        metrics: snapshot.mobileToday,
                        mainDieselLiters: todayOps.mainDieselLiters,
                        reserveDieselLiters: todayOps.reserveDieselLiters,
                        isFocusToday: isFocusToday,
                        summaryDayTitle: summaryDayTitle
                    )
                }

                HomeCostPairSection(
                    laborBaht: todayOps.laborBaht,
                    presentCount: todayOps.presentCount,
                    vehicleBaht: todayOps.vehicleBaht,
                    showLabor: showLaborCard,
                    showVehicle: showVehicleCard,
                    laborDeltaLabel: homePro.labor.compactCompareLabel,
                    laborDeltaIsUp: homePro.labor.isUp
                )
            }
        }
    }

    // MARK: - Off-Main Snapshot Rebuild

    private struct RebuiltOverview: Sendable {
        let overview: OverviewSnapshot
        let today: TodayOpsSnapshot
        let pro: HomeProSnapshot
        let watch: [OpsTrendAlert]
        let drums: [HomeDrumTripRow]
        let macros: [HomeMacroVehicleRow]
        let events: [Transaction]
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let filter = dateFilter
        let dayKey = DashboardAggregations.focusDayKey(from: filter)
        let txs = transactions
        let all = allTransactions
        let fuelTxs = fuelTransactions
        let emps = employees
        let settingsCopy = settings
        let shouldDebounce = hasBuiltInitialSnapshot
        rebuildTask = Task {
            if shouldDebounce {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            guard !Task.isCancelled else { return }
            let built: RebuiltOverview = await Task.detached(priority: .userInitiated) {
                let overview = OverviewSnapshot.build(
                    filter: filter,
                    transactions: txs,
                    allTransactions: all,
                    settings: settingsCopy,
                    employees: emps
                )
                let today = TodayOpsSnapshot.build(
                    transactions: all,
                    fuelTransactions: fuelTxs,
                    employees: emps,
                    settings: settingsCopy,
                    dayKey: dayKey
                )
                let pro = HomeProSnapshot.build(
                    dayKey: dayKey,
                    transactions: all,
                    employees: emps,
                    periodAlerts: overview.alerts,
                    periodInsights: overview.insights
                )
                let byDay = Dictionary(grouping: all) { String($0.date.prefix(10)) }
                let weekReport = OpsTrendAnalytics.build(
                    period: .week,
                    periodOffset: 0,
                    transactions: all,
                    employees: emps,
                    byDay: byDay
                )
                let watch = OpsTrendWatchlistStore.pinnedAlerts(matching: weekReport.actionPlan.alerts)
                let drums = Self.buildDrumRows(
                    dayKey: dayKey,
                    allTransactions: all,
                    employees: emps,
                    settings: settingsCopy
                )
                let macros = Self.buildMacroRows(
                    dayKey: dayKey,
                    allTransactions: all,
                    employees: emps,
                    settings: settingsCopy
                )
                let events = EventLogic.dayEvents(dayKey: dayKey, transactions: all)
                return RebuiltOverview(
                    overview: overview,
                    today: today,
                    pro: pro,
                    watch: watch,
                    drums: drums,
                    macros: macros,
                    events: events
                )
            }.value
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                snapshot = built.overview
                todayOps = built.today
                homePro = built.pro
                analyticsWatchlist = built.watch
                drumRows = built.drums
                macroRows = built.macros
                dailyEventRows = built.events
                hasBuiltInitialSnapshot = true
            }
        }
    }

    // MARK: - Off-Main Fleet Builders

    private nonisolated static func buildDrumRows(
        dayKey: String,
        allTransactions: [Transaction],
        employees: [Employee],
        settings: AppSettings
    ) -> [HomeDrumTripRow] {
        let catalog = settings.vehicleCatalog
        let nameById = CountRecordLogic.vehicleNameIndex(from: allTransactions)
        let units = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: allTransactions,
            employees: employees,
            cars: settings.cars,
            catalog: catalog
        )
        .filter { unit in
            if CountRecordLogic.isDrumTripVehicleId(unit.vehicleId) { return true }
            if CountRecordLogic.looksLikeCatalogVehicleId(unit.vehicleId) {
                return catalog.contains {
                    $0.id == unit.vehicleId && CountRecordLogic.isDrumTripVehicleId($0.name)
                }
            }
            return !CountRecordLogic.isMacroVehicleId(unit.vehicleId)
        }

        var byVehicle: [String: HomeDrumTripRow] = [:]
        for unit in units {
            let key = unit.vehicleId
            if var existing = byVehicle[key] {
                existing.rounds += unit.rounds
                existing.morning += unit.morning
                existing.afternoon += max(0, unit.afternoon - unit.ot)
                if existing.driverLabel == "ยังไม่ระบุ", unit.driverLabel != "ยังไม่ระบุ" {
                    existing.driverLabel = unit.driverLabel
                }
                byVehicle[key] = existing
            } else {
                byVehicle[key] = HomeDrumTripRow(
                    id: key,
                    vehicleName: CountRecordLogic.vehicleDisplayLabel(
                        vehicleId: unit.vehicleId,
                        vehicleName: nil,
                        cars: settings.cars,
                        catalog: catalog,
                        nameById: nameById
                    ),
                    driverLabel: unit.driverLabel,
                    rounds: unit.rounds,
                    morning: unit.morning,
                    afternoon: max(0, unit.afternoon - unit.ot)
                )
            }
        }
        return byVehicle.values
            .filter { $0.rounds > 0 }
            .sorted {
                if $0.rounds != $1.rounds { return $0.rounds > $1.rounds }
                return $0.vehicleName.localizedStandardCompare($1.vehicleName) == .orderedAscending
            }
    }

    private nonisolated static func buildMacroRows(
        dayKey: String,
        allTransactions: [Transaction],
        employees: [Employee],
        settings: AppSettings
    ) -> [HomeMacroVehicleRow] {
        let cars = settings.cars
        let catalog = settings.vehicleCatalog
        let nameById = CountRecordLogic.vehicleNameIndex(from: allTransactions)
        let byVehicle = MacroVehicleLogic.dayRowsByVehicle(
            dayKey: dayKey,
            transactions: allTransactions,
            cars: cars,
            catalog: catalog
        )
        var seenIds = Set<String>()
        var uniqueRows: [Transaction] = []
        for tx in byVehicle.values {
            let key = tx.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if seenIds.insert(key).inserted {
                uniqueRows.append(tx)
            }
        }
        return uniqueRows
            .map { tx in
                let label = CountRecordLogic.vehicleDisplayLabel(
                    vehicleId: tx.vehicleId,
                    vehicleName: tx.vehicleName,
                    cars: cars,
                    catalog: catalog,
                    description: tx.description,
                    nameById: nameById
                )
                let details = MacroVehicleLogic.stripRecorderSuffix(tx.workDetails ?? "")
                let tags = MacroVehicleLogic.parseWorkTags(details)
                let workLabels = tags.isEmpty
                    ? (details.isEmpty ? [] : [details])
                    : tags
                return HomeMacroVehicleRow(
                    id: label.isEmpty ? tx.id : label,
                    vehicleName: label.isEmpty ? "แม็คโคร" : label,
                    driverLabel: CountRecordLogic.driverDisplayName(tx.driverId ?? "", employees: employees),
                    dayLabel: MacroVehicleLogic.WorkType.from(raw: tx.workType).label,
                    workLabels: workLabels
                )
            }
            .sorted {
                $0.vehicleName.localizedStandardCompare($1.vehicleName) == .orderedAscending
            }
    }
}
