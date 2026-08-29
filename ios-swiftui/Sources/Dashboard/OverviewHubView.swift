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

// MARK: - View (ops summary only — no business analytics)

struct OverviewHubView: View {
    let transactions: [Transaction]
    let allTransactions: [Transaction]
    let employees: [Employee]
    let settings: AppSettings
    let dateFilter: DateFilter
    var greetingName: String? = nil
    /// Prefer revision over Equatable-diffing the full transaction arrays.
    var transactionsRevision: Int = 0

    @State private var snapshot = OverviewSnapshot.empty(filter: DateFilter(start: "", end: ""))
    @State private var todayOps = TodayOpsSnapshot.empty
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showAllWorkingStaff = false

    private var leaveNamesToday: [String] {
        todayOps.staffRows
            .filter { $0.status == .leave }
            .map(\.name)
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                greetingHeader
                todayHighlightCard
                dailyEventsCard
                opsMetricGrid
                drumVehiclesCard
                macroVehiclesCard
                periodRangeCard
                staffCard
            }
            .padding(AppTheme.spaceLG)
        }
        .scrollContentBackground(.hidden)
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

    private var focusDayKey: String {
        DashboardAggregations.focusDayKey(from: dateFilter)
    }

    private var isFocusToday: Bool {
        focusDayKey == DashboardAggregations.todayYMD()
    }

    private var summaryDayTitle: String {
        isFocusToday ? "สรุปวันนี้" : "สรุป \(DashboardAggregations.thaiDateLong(focusDayKey))"
    }

    private var opsDayTitle: String {
        isFocusToday ? "สรุปงานวันนี้" : "สรุปงาน · \(DashboardAggregations.thaiDateLong(focusDayKey))"
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let filter = dateFilter
        let dayKey = DashboardAggregations.focusDayKey(from: filter)
        let txs = transactions
        let all = allTransactions
        let emps = employees
        let settingsCopy = settings
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let built = await Task.detached(priority: .userInitiated) {
                (
                    OverviewSnapshot.build(
                        filter: filter,
                        transactions: txs,
                        allTransactions: all,
                        settings: settingsCopy,
                        employees: emps
                    ),
                    TodayOpsSnapshot.build(
                        transactions: all,
                        employees: emps,
                        settings: settingsCopy,
                        dayKey: dayKey
                    )
                )
            }.value
            guard !Task.isCancelled else { return }
            snapshot = built.0
            todayOps = built.1
        }
    }

    // MARK: - Header

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

    private var greetingHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("สวัสดี \(greetingDisplay)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(todayLabel)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 8)
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(AppTheme.brand)
                .frame(width: 48, height: 48)
                .background(AppTheme.brandSoft, in: Circle())
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Today highlight

    private var todayHighlightCard: some View {
        let metrics = snapshot.mobileToday
        let showFuel = metrics.fuelOutLiters > 0
            || metrics.fuelInLiters > 0
            || todayOps.mainDieselLiters > 0
            || todayOps.reserveDieselLiters > 0
        let showLabor = todayOps.laborBaht > 0 || todayOps.presentCount > 0
        let showVehicle = todayOps.vehicleBaht > 0
        let showAttendance = todayOps.presentCount > 0
            || todayOps.leaveCount > 0
            || todayOps.absentCount > 0

        return Group {
            if showFuel || showLabor || showVehicle || showAttendance {
                VStack(alignment: .leading, spacing: 14) {
                    Label(summaryDayTitle, systemImage: "sparkles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    if showFuel {
                        NavigationLink {
                            CategoryReportScreen(type: .fuel)
                        } label: {
                            fuelTodayCard
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("แตะเพื่อดูรายละเอียดน้ำมัน")
                    }

                    if showLabor || showVehicle {
                        HStack(spacing: 10) {
                            if showLabor {
                                NavigationLink {
                                    CategoryReportScreen(type: .labor)
                                } label: {
                                    moneyPill(
                                        title: "ค่าแรง",
                                        value: DashboardAggregations.formatCurrency(todayOps.laborBaht),
                                        detail: "มา \(todayOps.presentCount) คน",
                                        accent: AppTheme.labor
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("แตะเพื่อดูรายละเอียดค่าแรง")
                            }

                            if showVehicle {
                                NavigationLink {
                                    CategoryReportScreen(type: .vehicle)
                                } label: {
                                    moneyPill(
                                        title: "ใช้รถ",
                                        value: DashboardAggregations.formatCurrency(todayOps.vehicleBaht),
                                        detail: "ค่าเที่ยว / ค่าขับ",
                                        accent: AppTheme.vehicle
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("แตะเพื่อดูรายละเอียดการใช้รถ")
                            }
                        }
                    }

                    if showAttendance {
                        NavigationLink {
                            AttendanceHubView()
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                if todayOps.presentCount > 0 {
                                    attendanceStat(count: todayOps.presentCount, title: "มาทำงาน", color: AppTheme.income)
                                }
                                if todayOps.leaveCount > 0 {
                                    attendanceStat(
                                        count: todayOps.leaveCount,
                                        title: "ลา",
                                        color: AppTheme.warning,
                                        names: leaveNamesToday
                                    )
                                }
                                if todayOps.absentCount > 0 {
                                    attendanceStat(count: todayOps.absentCount, title: "ขาด", color: AppTheme.expense)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("แตะเพื่อดูรายละเอียดเช็คชื่อ")
                    }
                }
                .padding(18)
                .background(summaryCardBackground)
            }
        }
    }

    private var fuelTodayCard: some View {
        let used = snapshot.mobileToday.fuelOutLiters
        let inbound = snapshot.mobileToday.fuelInLiters
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("น้ำมัน", systemImage: "fuelpump.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.fuel)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            HStack(spacing: 8) {
                fuelStockChip(
                    title: "ถังหลัก",
                    value: "\(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) L",
                    accent: AppTheme.fuel
                )
                fuelStockChip(
                    title: "ถังสำรอง",
                    value: "\(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L",
                    accent: Color(hex: "#0F766E")
                )
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ใช้ไปวันนี้")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    Text("\(DashboardAggregations.formatNumber(used)) L")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    Text("ไม่รวมเบิกไปถังสำรอง")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("เข้าวันนี้")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.inkMuted)
                    Text("\(DashboardAggregations.formatNumber(inbound)) L")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.fuel)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                    if snapshot.mobileToday.fuelWithdrawLiters > 0 {
                        Text("เบิกสำรอง \(DashboardAggregations.formatNumber(snapshot.mobileToday.fuelWithdrawLiters)) L")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(AppTheme.warning)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.fuel.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppTheme.fuel.opacity(0.22), lineWidth: 1)
        )
    }

    private func fuelStockChip(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func moneyPill(title: String, value: String, detail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
    }

    private func attendanceStat(
        count: Int,
        title: String,
        color: Color,
        names: [String] = []
    ) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
            if !names.isEmpty {
                Text(names.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ops metrics

    private var opsMetricGrid: some View {
        let m = snapshot.mobileToday
        let showTrips = m.tripRounds > 0 || m.tripVehicles > 0
        let showSand = m.sandRounds > 0 || m.sandWashedCubic > 0
        let showAttendance = m.presentCount > 0 || m.leaveCount > 0 || m.absentCount > 0
        let showMacro = m.macroUsageCount > 0 || m.macroVehicles > 0
        let showFuelIn = m.fuelInLiters > 0
        let showFuelWithdraw = m.fuelWithdrawLiters > 0 || m.fuelWithdrawCount > 0
        let showFuelCarFill = m.fuelCarFillLiters > 0 || m.fuelCarFillCount > 0
        let showFuelMacro = m.fuelMacroUsageLiters > 0 || m.fuelMacroVehicles > 0
        let showLeave = m.leaveCount > 0
        let hasAny = showTrips || showSand || showAttendance || showMacro
            || showFuelIn || showFuelWithdraw || showFuelCarFill || showFuelMacro || showLeave

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 12) {
                    Text(opsDayTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if showTrips {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .trips)
                            } label: {
                                SummaryMetricCard(
                                    title: "เที่ยวรถ",
                                    value: "\(m.tripRounds)",
                                    unit: "เที่ยว",
                                    detail: "\(m.tripVehicles) คัน · \(DashboardAggregations.formatNumber(m.tripCubic)) คิว",
                                    accent: AppTheme.vehicle,
                                    systemImage: "truck.box.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showSand {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .sand)
                            } label: {
                                SummaryMetricCard(
                                    title: "ร่อนทราย",
                                    value: "\(m.sandRounds)",
                                    unit: "รอบ",
                                    detail: "ล้าง \(DashboardAggregations.formatNumber(m.sandWashedCubic)) คิว",
                                    accent: AppTheme.sand,
                                    systemImage: "drop.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showAttendance {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .attendance)
                            } label: {
                                SummaryMetricCard(
                                    title: "เช็คชื่อ",
                                    value: "\(m.presentCount)",
                                    unit: "คน",
                                    detail: "ลา \(m.leaveCount) · ขาด \(m.absentCount)",
                                    accent: AppTheme.labor,
                                    systemImage: "person.3.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showMacro {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .macro)
                            } label: {
                                SummaryMetricCard(
                                    title: "แม็คโคร",
                                    value: "\(m.macroUsageCount)",
                                    unit: "ครั้ง",
                                    detail: "\(m.macroVehicles) คัน",
                                    accent: Color(hex: "#0F766E"),
                                    systemImage: "hammer.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showFuelIn {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .fuelStockIn)
                            } label: {
                                SummaryMetricCard(
                                    title: "เพิ่มน้ำมัน",
                                    value: DashboardAggregations.formatNumber(m.fuelInLiters),
                                    unit: "L",
                                    detail: "หลัก \(DashboardAggregations.formatNumber(todayOps.mainDieselLiters)) · สำรอง \(DashboardAggregations.formatNumber(todayOps.reserveDieselLiters)) L",
                                    accent: AppTheme.fuel,
                                    systemImage: "arrow.down.to.line.circle.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showFuelWithdraw {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .fuelWithdraw)
                            } label: {
                                SummaryMetricCard(
                                    title: "เบิกน้ำมัน",
                                    value: DashboardAggregations.formatNumber(m.fuelWithdrawLiters),
                                    unit: "L",
                                    detail: m.fuelWithdrawCount > 0
                                        ? "\(m.fuelWithdrawCount) ครั้ง"
                                        : (isFocusToday ? "วันนี้" : summaryDayTitle),
                                    accent: AppTheme.fuel,
                                    systemImage: "arrow.up.right.circle.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showFuelCarFill {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .fuelCarFill)
                            } label: {
                                SummaryMetricCard(
                                    title: "เติมน้ำมันรถยนต์",
                                    value: DashboardAggregations.formatNumber(m.fuelCarFillLiters),
                                    unit: "L",
                                    detail: m.fuelCarFillCount > 0
                                        ? "\(m.fuelCarFillCount) ครั้ง"
                                        : (isFocusToday ? "วันนี้" : summaryDayTitle),
                                    accent: AppTheme.fuel,
                                    systemImage: "car.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showFuelMacro {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .fuelMacroUsage)
                            } label: {
                                SummaryMetricCard(
                                    title: "การใช้น้ำมันรถแม็คโคร",
                                    value: DashboardAggregations.formatNumber(m.fuelMacroUsageLiters),
                                    unit: "L",
                                    detail: m.fuelMacroVehicles > 0
                                        ? "\(m.fuelMacroVehicles) คัน"
                                        : (isFocusToday ? "วันนี้" : summaryDayTitle),
                                    accent: AppTheme.fuel,
                                    systemImage: "fuelpump.fill"
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        if showLeave {
                            NavigationLink {
                                TodayOpsDetailScreen(kind: .leave)
                            } label: {
                                SummaryMetricCard(
                                    title: "ลางาน",
                                    value: "\(m.leaveCount)",
                                    unit: "คน",
                                    detail: leaveNamesToday.isEmpty
                                        ? (isFocusToday ? "วันนี้" : summaryDayTitle)
                                        : leaveNamesToday.joined(separator: " · "),
                                    accent: AppTheme.warning,
                                    systemImage: "calendar.badge.minus"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Daily events (Android «เหตุการณ์»)

    private var dailyEventRows: [Transaction] {
        EventLogic.dayEvents(dayKey: focusDayKey, transactions: allTransactions)
    }

    private var dailyEventsCard: some View {
        let rows = dailyEventRows
        let title: String = {
            if isFocusToday {
                return "เหตุการณ์วันนี้ · \(rows.count) รายการ"
            }
            return "เหตุการณ์ · \(DashboardAggregations.thaiDateLong(focusDayKey)) · \(rows.count) รายการ"
        }()

        return Group {
            if !rows.isEmpty {
                NavigationLink {
                    EventHubView()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(title, systemImage: "exclamationmark.bubble.fill")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Divider() }
                            dailyEventRow(event)
                        }
                    }
                    .padding(18)
                    .background(summaryCardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityHint("แตะเพื่อเปิดเมนูเหตุการณ์")
            }
        }
    }

    private func dailyEventRow(_ t: Transaction) -> some View {
        let kind = EventLogic.EventKind.from(raw: t.eventType)
        let priority = EventLogic.Priority.from(raw: t.eventPriority)
        let text = EventLogic.stripRecorder(t.description)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(kind.accent)
                Text(kind.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kind.accent)
                if priority == .urgent {
                    Text("ด่วน")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppTheme.expense.opacity(0.15)))
                        .foregroundStyle(AppTheme.expense)
                }
                Spacer(minLength: 0)
            }
            Text(text.isEmpty ? "—" : text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Drum vehicles

    /// Drum vehicles from count-record trip menu (`buildTripUnits`), same source as Realtime «จำนวนเที่ยวรถ».
    private var todayDrumTripRows: [DrumTripRow] {
        let dayKey = focusDayKey
        let catalog = settings.vehicleCatalog
        let units = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: allTransactions,
            employees: employees,
            cars: settings.cars,
            catalog: catalog
        )
        .filter { unit in
            if CountRecordLogic.isDrumTripVehicleId(unit.vehicleId) { return true }
            // Unresolved catalog id: still show if settings list this id as a drum car by name.
            if CountRecordLogic.looksLikeCatalogVehicleId(unit.vehicleId) {
                return catalog.contains {
                    $0.id == unit.vehicleId && CountRecordLogic.isDrumTripVehicleId($0.name)
                }
            }
            // Named non-macro trip vehicles that aren't "แม็คโคร" — treat as fleet drum/dump list.
            return !CountRecordLogic.isMacroVehicleId(unit.vehicleId)
        }

        var byVehicle: [String: DrumTripRow] = [:]
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
                byVehicle[key] = DrumTripRow(
                    id: key,
                    vehicleName: unit.vehicleId,
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

    private var drumVehiclesCard: some View {
        let rows = todayDrumTripRows
        return Group {
            if !rows.isEmpty {
                NavigationLink {
                    CountRecordHubView()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(
                                "รถดรัม · \(rows.count) คัน",
                                systemImage: "cylinder.split.1x2"
                            )
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider() }
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.vehicleName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                        .lineLimit(1)
                                    Text(row.driverLabel)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(row.rounds) เที่ยว")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(AppTheme.warning)
                                    if row.morning > 0 || row.afternoon > 0 {
                                        Text("เช้า \(row.morning) · บ่าย \(row.afternoon)")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.inkMuted)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(18)
                    .background(summaryCardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityHint("แตะเพื่อเปิดเมนูบันทึกจำนวนเที่ยวรถ")
            }
        }
    }

    private struct DrumTripRow: Identifiable {
        let id: String
        let vehicleName: String
        var driverLabel: String
        var rounds: Int
        var morning: Int
        var afternoon: Int
    }

    // MARK: - Macro vehicles

    private struct MacroVehicleRow: Identifiable {
        let id: String
        let vehicleName: String
        let driverLabel: String
        let dayLabel: String
        let workLabels: [String]
    }

    private var todayMacroVehicleRows: [MacroVehicleRow] {
        let dayKey = focusDayKey
        let cars = MacroVehicleLogic.macroCars(from: settings)
        let catalog = settings.vehicleCatalog
        let nameById = CountRecordLogic.vehicleNameIndex(from: allTransactions)
        let byVehicle = MacroVehicleLogic.dayRowsByVehicle(
            dayKey: dayKey,
            transactions: allTransactions,
            cars: cars,
            catalog: catalog
        )
        // Prefer display-name keys (Android) over raw catalog ids when both exist.
        var seenIds = Set<String>()
        var uniqueRows: [Transaction] = []
        for tx in byVehicle.values {
            let key = (tx.id).trimmingCharacters(in: .whitespacesAndNewlines)
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
                return MacroVehicleRow(
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

    private var macroVehiclesCard: some View {
        let rows = todayMacroVehicleRows
        let accent = Color(hex: "#0F766E")
        return Group {
            if !rows.isEmpty {
                NavigationLink {
                    MacroVehicleHubView()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(
                                "รถแม็คโคร · \(rows.count) คัน",
                                systemImage: "hammer.fill"
                            )
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.inkMuted)
                        }

                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider() }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.vehicleName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                            .lineLimit(2)
                                        Text(row.driverLabel)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.inkMuted)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text(row.dayLabel)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(accent)
                                }
                                if row.workLabels.isEmpty {
                                    Text("ยังไม่ระบุงาน")
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.inkMuted)
                                } else {
                                    Text(row.workLabels.joined(separator: " · "))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(18)
                    .background(summaryCardBackground)
                }
                .buttonStyle(.plain)
                .accessibilityHint("แตะเพื่อเปิดเมนูการใช้รถแม็คโคร")
            }
        }
    }

    // MARK: - Period range

    private var periodRangeCard: some View {
        let r = snapshot.mobileRange
        let showTrips = r.tripRounds > 0 || r.tripVehicles > 0
        let showSand = r.sandRounds > 0 || r.sandWashedCubic > 0
        let showAttendance = r.attendanceDays > 0 || r.presentCount > 0
        let showMacro = r.macroUsageCount > 0 || r.macroVehicles > 0
        let showFuel = r.fuelInLiters > 0 || r.fuelOutLiters > 0
        let hasAny = showTrips || showSand || showAttendance || showMacro || showFuel

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("รวมช่วงที่เลือก")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text(periodLabel)
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkMuted)
                    }

                    if showTrips {
                        periodRow(
                            "เที่ยวรถ",
                            "\(r.tripRounds) เที่ยว · \(r.tripVehicles) คัน"
                        )
                    }
                    if showSand {
                        periodRow(
                            "ร่อนทราย",
                            "\(r.sandRounds) รอบ · ล้าง \(DashboardAggregations.formatNumber(r.sandWashedCubic)) คิว"
                        )
                    }
                    if showAttendance {
                        periodRow(
                            "เช็คชื่อ",
                            "เฉลี่ย \(r.presentCount) คน/วัน · \(r.attendanceDays) วัน"
                        )
                    }
                    if showMacro {
                        periodRow(
                            "แม็คโคร",
                            "\(r.macroUsageCount) ครั้ง · \(r.macroVehicles) คัน"
                        )
                    }
                    if showFuel {
                        periodRow(
                            "น้ำมัน",
                            "เข้า \(DashboardAggregations.formatNumber(r.fuelInLiters)) L · ออก \(DashboardAggregations.formatNumber(r.fuelOutLiters)) L"
                        )
                    }
                }
                .padding(18)
                .background(summaryCardBackground)
            }
        }
    }

    private func periodRow(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AppTheme.brand)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Staff

    private var staffCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                AttendanceHubView()
            } label: {
                HStack {
                    Label("พนักงานวันนี้", systemImage: "person.crop.rectangle.stack.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("แตะเพื่อดูรายละเอียดเช็คชื่อ")

            if todayOps.staffRows.isEmpty {
                EmptyStateView(
                    title: "ยังไม่มีพนักงานท่าทราย / แม็คโคร",
                    message: "นับเฉพาะพนักงานท่าทรายและคนขับรถแม็คโครจากเมนูพนักงาน",
                    systemImage: "person.slash"
                )
            } else {
                let working = todayOps.staffRows.filter { $0.status == .work }
                let onLeave = todayOps.staffRows.filter { $0.status == .leave }
                let absent = todayOps.staffRows.filter { $0.status == .absent }
                let visibleWorking = showAllWorkingStaff ? working : Array(working.prefix(2))

                if !working.isEmpty {
                    staffGroupHeader("มาทำงาน · ทำอะไรบ้าง", count: working.count, color: AppTheme.income)
                    ForEach(visibleWorking) { row in
                        staffRowView(row)
                    }
                    if working.count > 2 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAllWorkingStaff.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(
                                    showAllWorkingStaff
                                        ? "ย่อ"
                                        : "ดูทั้งหมด (\(working.count) คน)"
                                )
                                .font(.caption.weight(.bold))
                                Image(systemName: showAllWorkingStaff ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(AppTheme.brand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                AppTheme.brand.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !onLeave.isEmpty {
                    if !working.isEmpty { Divider().padding(.vertical, 4) }
                    staffGroupHeader("ลางาน", count: onLeave.count, color: AppTheme.warning)
                    ForEach(onLeave) { row in
                        staffRowView(row)
                    }
                }
                if !absent.isEmpty {
                    if !working.isEmpty || !onLeave.isEmpty { Divider().padding(.vertical, 4) }
                    staffGroupHeader("ขาดงาน", count: absent.count, color: AppTheme.expense)
                    ForEach(absent.prefix(12)) { row in
                        staffRowView(row)
                    }
                    if absent.count > 12 {
                        Text("และอีก \(absent.count - 12) คน")
                            .font(.caption)
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }
            }
        }
        .padding(18)
        .background(summaryCardBackground)
    }

    private func staffGroupHeader(_ title: String, count: Int, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            PillBadge(text: "\(count) คน", color: color)
        }
        .padding(.bottom, 2)
    }

    private func staffRowView(_ row: TodayOpsSnapshot.StaffRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(staffStatusColor(row.status).opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Text(String(row.name.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(staffStatusColor(row.status))
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 8)
                    Text(row.status.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(staffStatusColor(row.status))
                }
                if !row.workLabels.isEmpty {
                    Text(row.workLabels.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if row.status == .work {
                    Text(DashboardAggregations.formatCurrency(row.wage))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.labor)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func staffStatusColor(_ status: TodayOpsSnapshot.StaffRow.Status) -> Color {
        switch status {
        case .work: return AppTheme.income
        case .leave: return AppTheme.warning
        case .absent: return AppTheme.expense
        }
    }

    private var summaryCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.surface)
            .shadow(color: AppTheme.cardShadow, radius: 14, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppTheme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Summary metric card

private struct SummaryMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    let accent: Color
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
            }

            Text(detail)
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.18), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [accent.opacity(0.16), accent.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 16,
                    style: .continuous
                )
            )
            .allowsHitTesting(false)
        }
    }
}
