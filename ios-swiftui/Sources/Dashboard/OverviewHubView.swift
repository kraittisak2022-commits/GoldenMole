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
        let mobile = MobileOpsSnapshot.build(
            filter: filter,
            allTransactions: allTransactions,
            employees: employees
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

    @State private var snapshot = OverviewSnapshot.empty(filter: DateFilter(start: "", end: ""))
    @State private var todayOps = TodayOpsSnapshot.empty
    @State private var rebuildTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                greetingHeader
                todayHighlightCard
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
        .onChange(of: dateFilter) { _, _ in scheduleRebuild() }
        .onChange(of: transactions) { _, _ in scheduleRebuild() }
        .onChange(of: allTransactions.count) { _, _ in scheduleRebuild() }
        .onChange(of: employees.count) { _, _ in scheduleRebuild() }
        .onChange(of: settings.cars) { _, _ in scheduleRebuild() }
    }

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        let filter = dateFilter
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
                        settings: settingsCopy
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
        VStack(alignment: .leading, spacing: 14) {
            Label("สรุปวันนี้", systemImage: "sparkles")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            NavigationLink {
                CategoryReportScreen(type: .fuel)
            } label: {
                fuelTodayCard
            }
            .buttonStyle(.plain)
            .accessibilityHint("แตะเพื่อดูรายละเอียดน้ำมัน")

            HStack(spacing: 10) {
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

            NavigationLink {
                AttendanceHubView()
            } label: {
                HStack(spacing: 8) {
                    attendanceStat(count: todayOps.presentCount, title: "มาทำงาน", color: AppTheme.income)
                    attendanceStat(count: todayOps.leaveCount, title: "ลา", color: AppTheme.warning)
                    attendanceStat(count: todayOps.absentCount, title: "ขาด", color: AppTheme.expense)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("แตะเพื่อดูรายละเอียดเช็คชื่อ")
        }
        .padding(18)
        .background(summaryCardBackground)
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

            fuelStockChip(
                title: "ดีเซลคงเหลือ",
                value: "\(DashboardAggregations.formatNumber(todayOps.dieselLiters)) L",
                accent: AppTheme.fuel
            )

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

    private func attendanceStat(count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Ops metrics

    private var opsMetricGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("สรุปงานวันนี้")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    TodayOpsDetailScreen(kind: .trips)
                } label: {
                    SummaryMetricCard(
                        title: "เที่ยวรถ",
                        value: "\(snapshot.mobileToday.tripRounds)",
                        unit: "เที่ยว",
                        detail: "\(snapshot.mobileToday.tripVehicles) คัน · \(DashboardAggregations.formatNumber(snapshot.mobileToday.tripCubic)) คิว",
                        accent: AppTheme.vehicle,
                        systemImage: "truck.box.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .sand)
                } label: {
                    SummaryMetricCard(
                        title: "ร่อนทราย",
                        value: "\(snapshot.mobileToday.sandRounds)",
                        unit: "รอบ",
                        detail: "ล้าง \(DashboardAggregations.formatNumber(snapshot.mobileToday.sandWashedCubic)) คิว",
                        accent: AppTheme.sand,
                        systemImage: "drop.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .attendance)
                } label: {
                    SummaryMetricCard(
                        title: "เช็คชื่อ",
                        value: "\(snapshot.mobileToday.presentCount)",
                        unit: "คน",
                        detail: "ลา \(snapshot.mobileToday.leaveCount) · ขาด \(snapshot.mobileToday.absentCount)",
                        accent: AppTheme.labor,
                        systemImage: "person.3.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .macro)
                } label: {
                    SummaryMetricCard(
                        title: "แม็คโคร",
                        value: "\(snapshot.mobileToday.macroUsageCount)",
                        unit: "ครั้ง",
                        detail: "\(snapshot.mobileToday.macroVehicles) คัน",
                        accent: Color(hex: "#0F766E"),
                        systemImage: "hammer.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .fuelStockIn)
                } label: {
                    SummaryMetricCard(
                        title: "เพิ่มน้ำมัน",
                        value: DashboardAggregations.formatNumber(snapshot.mobileToday.fuelInLiters),
                        unit: "L",
                        detail: "คงเหลือ \(DashboardAggregations.formatNumber(todayOps.dieselLiters)) L",
                        accent: AppTheme.fuel,
                        systemImage: "arrow.down.to.line.circle.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .fuelWithdraw)
                } label: {
                    SummaryMetricCard(
                        title: "เบิกน้ำมัน",
                        value: DashboardAggregations.formatNumber(snapshot.mobileToday.fuelWithdrawLiters),
                        unit: "L",
                        detail: snapshot.mobileToday.fuelWithdrawCount > 0
                            ? "\(snapshot.mobileToday.fuelWithdrawCount) ครั้ง · วันนี้"
                            : "วันนี้",
                        accent: AppTheme.fuel,
                        systemImage: "arrow.up.right.circle.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .fuelMacroUsage)
                } label: {
                    SummaryMetricCard(
                        title: "การใช้น้ำมันรถแม็คโคร",
                        value: DashboardAggregations.formatNumber(snapshot.mobileToday.fuelMacroUsageLiters),
                        unit: "L",
                        detail: snapshot.mobileToday.fuelMacroVehicles > 0
                            ? "\(snapshot.mobileToday.fuelMacroVehicles) คัน · วันนี้"
                            : "วันนี้",
                        accent: AppTheme.fuel,
                        systemImage: "fuelpump.fill"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodayOpsDetailScreen(kind: .leave)
                } label: {
                    SummaryMetricCard(
                        title: "ลางาน",
                        value: "\(snapshot.mobileToday.leaveCount)",
                        unit: "คน",
                        detail: "วันนี้",
                        accent: AppTheme.warning,
                        systemImage: "calendar.badge.minus"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Drum vehicles

    private var todayDrumTripRows: [DrumTripRow] {
        let dayKey = todayOps.dayKey.isEmpty ? DashboardAggregations.todayYMD() : todayOps.dayKey
        let units = CountRecordLogic.buildTripUnits(
            dayKey: dayKey,
            transactions: allTransactions,
            employees: employees
        )
        .filter { CountRecordLogic.isDrumTripVehicleId($0.vehicleId) && $0.rounds > 0 }

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
        return byVehicle.values.sorted {
            if $0.rounds != $1.rounds { return $0.rounds > $1.rounds }
            return $0.vehicleName.localizedStandardCompare($1.vehicleName) == .orderedAscending
        }
    }

    private var drumVehiclesCard: some View {
        let rows = todayDrumTripRows
        return NavigationLink {
            CategoryReportScreen(type: .vehicle)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        rows.isEmpty ? "รถดรัมวันนี้" : "รถดรัม · \(rows.count) คัน",
                        systemImage: "cylinder.split.1x2"
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                if rows.isEmpty {
                    Text("วันนี้ยังไม่มีรถดรัม")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.vertical, 8)
                } else {
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
            }
            .padding(18)
            .background(summaryCardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("แตะเพื่อดูรายละเอียดการใช้รถ")
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
        let dayKey = todayOps.dayKey.isEmpty ? DashboardAggregations.todayYMD() : todayOps.dayKey
        let byVehicle = MacroVehicleLogic.dayRowsByVehicle(
            dayKey: dayKey,
            transactions: allTransactions
        )
        return byVehicle.values
            .map { tx in
                let vid = (tx.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let details = MacroVehicleLogic.stripRecorderSuffix(tx.workDetails ?? "")
                let tags = MacroVehicleLogic.parseWorkTags(details)
                let workLabels = tags.isEmpty
                    ? (details.isEmpty ? [] : [details])
                    : tags
                return MacroVehicleRow(
                    id: vid.isEmpty ? tx.id : vid,
                    vehicleName: vid.isEmpty ? "แม็คโคร" : vid,
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
        return NavigationLink {
            TodayOpsDetailScreen(kind: .macro)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(
                        rows.isEmpty ? "รถแม็คโครวันนี้" : "รถแม็คโคร · \(rows.count) คัน",
                        systemImage: "hammer.fill"
                    )
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

                if rows.isEmpty {
                    Text("วันนี้ยังไม่มีรถแม็คโคร")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                        .padding(.vertical, 8)
                } else {
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
            }
            .padding(18)
            .background(summaryCardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("แตะเพื่อดูรายละเอียดรถแม็คโคร")
    }

    // MARK: - Period range

    private var periodRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("รวมช่วงที่เลือก")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(periodLabel)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }

            periodRow("เที่ยวรถ", "\(snapshot.mobileRange.tripRounds) เที่ยว · \(snapshot.mobileRange.tripVehicles) คัน")
            periodRow("ร่อนทราย", "\(snapshot.mobileRange.sandRounds) รอบ · ล้าง \(DashboardAggregations.formatNumber(snapshot.mobileRange.sandWashedCubic)) คิว")
            periodRow("เช็คชื่อ", "เฉลี่ย \(snapshot.mobileRange.presentCount) คน/วัน · \(snapshot.mobileRange.attendanceDays) วัน")
            periodRow("แม็คโคร", "\(snapshot.mobileRange.macroUsageCount) ครั้ง · \(snapshot.mobileRange.macroVehicles) คัน")
            periodRow(
                "น้ำมัน",
                "เข้า \(DashboardAggregations.formatNumber(snapshot.mobileRange.fuelInLiters)) L · ออก \(DashboardAggregations.formatNumber(snapshot.mobileRange.fuelOutLiters)) L"
            )
        }
        .padding(18)
        .background(summaryCardBackground)
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
        NavigationLink {
            AttendanceHubView()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("พนักงานวันนี้", systemImage: "person.crop.rectangle.stack.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.inkMuted)
                }

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

                    if !working.isEmpty {
                        staffGroupHeader("มาทำงาน · ทำอะไรบ้าง", count: working.count, color: AppTheme.income)
                        ForEach(working) { row in
                            staffRowView(row)
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
        .buttonStyle(.plain)
        .accessibilityHint("แตะเพื่อดูรายละเอียดเช็คชื่อ")
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
                .lineLimit(2)
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
