import SwiftUI

/// Memoized bundle of Overview analytics (expense-focused + mobile ops) — built off the main thread.
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

// MARK: - View

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
    @State private var showShare = false
    @State private var jumpTarget: OverviewSection?
    @State private var activeJump: OverviewSection = .today

    private enum OverviewSection: String, CaseIterable, Identifiable, Hashable {
        case today = "วันนี้"
        case mobileOps = "งานจากแอพ"
        case expense = "รายจ่าย"
        case sand = "ทราย"
        case compare = "เปรียบเทียบ"
        case quality = "คุณภาพ"
        var id: String { rawValue }

        var eyebrow: String {
            switch self {
            case .today: return "TODAY"
            case .mobileOps: return "MOBILE"
            case .expense: return "EXPENSE"
            case .sand: return "SAND"
            case .compare: return "COMPARE"
            case .quality: return "QUALITY"
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceXL) {
                    heroCard
                    jumpChips(proxy: proxy)

                    todayOpsSection.id(OverviewSection.today)
                    mobileOpsSection.id(OverviewSection.mobileOps)
                    expenseSection.id(OverviewSection.expense)
                    sandSection.id(OverviewSection.sand)
                    compareSection.id(OverviewSection.compare)
                    qualitySection.id(OverviewSection.quality)
                }
                .padding(AppTheme.spaceLG)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: jumpTarget) { _, target in
                guard let target else { return }
                activeJump = target
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                jumpTarget = nil
            }
        }
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
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [snapshot.csvText])
        }
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

    // MARK: - Header / chips

    private var greetingDisplay: String {
        let raw = (greetingName ?? settings.appName).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return settings.appName }
        if raw.hasPrefix("คุณ") { return raw }
        return "คุณ\(raw)"
    }

    private var periodLabel: String {
        let start = dateFilter.start
        let end = dateFilter.end
        if start.isEmpty || end.isEmpty { return "ช่วงที่เลือก" }
        if start == end { return DashboardAggregations.thaiDateLong(start) }
        return "\(start) – \(end)"
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [AppTheme.brandDark, AppTheme.brand, AppTheme.cyan.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 160, height: 160)
                .blur(radius: 28)
                .offset(x: 220, y: -50)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ภาพรวมธุรกิจ")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.75))
                        Text("สวัสดี \(greetingDisplay)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(periodLabel)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 8)
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .disabled(snapshot.csvText.isEmpty)
                    .opacity(snapshot.csvText.isEmpty ? 0.45 : 1)
                    .accessibilityLabel("ส่งออก CSV")
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DashboardAggregations.formatCurrency(snapshot.expenseTotal))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if let delta = compactDelta(snapshot.expenseTotal, snapshot.prevExpenseTotal) {
                        Text(delta)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    (snapshot.expenseTotal >= snapshot.prevExpenseTotal
                                     ? AppTheme.expense : AppTheme.income).opacity(0.35)
                                )
                            )
                    }
                }

                Text("รายจ่ายรวมช่วงนี้")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))

                HStack(spacing: 10) {
                    heroMiniStat(
                        title: "เฉลี่ย/วัน",
                        value: DashboardAggregations.formatCurrency(
                            snapshot.numDays > 0 ? snapshot.expenseTotal / Double(snapshot.numDays) : 0
                        ),
                        tint: Color(hex: "#FECACA")
                    )
                    heroMiniStat(
                        title: "บันทึกจากแอพ",
                        value: "\(snapshot.mobileRange.recordCount)",
                        tint: Color(hex: "#A7F3D0")
                    )
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.brand.opacity(0.35), radius: 18, y: 8)
    }

    private func heroMiniStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
    }

    private func jumpChips(proxy _: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OverviewSection.allCases) { section in
                    let isActive = activeJump == section
                    Button {
                        jumpTarget = section
                    } label: {
                        Text(section.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isActive ? .white : AppTheme.brand)
                            .background(
                                Capsule().fill(isActive ? AppTheme.brand : AppTheme.surfaceSoft)
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isActive ? Color.clear : AppTheme.brand.opacity(0.35),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func sectionEyebrow(_ section: OverviewSection, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.eyebrow)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(AppTheme.brand)
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
    }

    // MARK: - Today ops

    private var todayOpsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            sectionEyebrow(
                .today,
                title: "สรุปวันนี้",
                subtitle: todayOps.dayKey.isEmpty
                    ? "น้ำมัน · ค่าแรง · รถ · พนักงาน"
                    : DashboardAggregations.thaiDateLong(todayOps.dayKey)
            )

            HStack(spacing: 12) {
                fuelStockCard(
                    title: "ดีเซลคงเหลือ",
                    liters: todayOps.dieselLiters,
                    systemImage: "fuelpump.fill",
                    accent: AppTheme.fuel
                )
                fuelStockCard(
                    title: "เบนซินคงเหลือ",
                    liters: todayOps.benzineLiters,
                    systemImage: "drop.fill",
                    accent: AppTheme.warning
                )
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "ค่าแรงวันนี้",
                    value: DashboardAggregations.formatCurrency(todayOps.laborBaht),
                    subtitle: "มาทำงาน \(todayOps.presentCount) คน",
                    accent: AppTheme.labor,
                    systemImage: "person.2.fill"
                )
                KPITile(
                    title: "ใช้รถวันนี้",
                    value: DashboardAggregations.formatCurrency(todayOps.vehicleBaht),
                    subtitle: "ค่าเที่ยว / ค่าขับ",
                    accent: AppTheme.vehicle,
                    systemImage: "car.fill"
                )
            }

            HStack(spacing: 10) {
                attendanceChip(count: todayOps.presentCount, title: "มาทำงาน", color: AppTheme.income)
                attendanceChip(count: todayOps.leaveCount, title: "ลา", color: AppTheme.warning)
                attendanceChip(count: todayOps.absentCount, title: "ขาด", color: AppTheme.expense)
            }

            SectionCard("พนักงานวันนี้", systemImage: "person.crop.rectangle.stack.fill") {
                if todayOps.staffRows.isEmpty {
                    EmptyStateView(
                        title: "ยังไม่มีข้อมูลพนักงานวันนี้",
                        message: "รอการบันทึกค่าแรง / ลางาน",
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
        }
    }

    private func fuelStockCard(title: String, liters: Double, systemImage: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.inkMuted)
                    .lineLimit(1)
            }
            Text("\(DashboardAggregations.formatNumber(liters)) L")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("คงเหลือในสต็อก")
                .font(.caption2)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    private func attendanceChip(count: Int, title: String, color: Color) -> some View {
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
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
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

    // MARK: - Mobile ops summary

    private var mobileOpsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            sectionEyebrow(
                .mobileOps,
                title: "สรุปงานจากแอพมือถือ",
                subtitle: "วันนี้เป็นหลัก · รวมช่วงที่เลือกด้านล่าง"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "เที่ยวรถ",
                    value: "\(snapshot.mobileToday.tripRounds) เที่ยว",
                    subtitle: "\(snapshot.mobileToday.tripVehicles) คัน · \(DashboardAggregations.formatNumber(snapshot.mobileToday.tripCubic)) คิว",
                    accent: AppTheme.vehicle,
                    systemImage: "truck.box.fill"
                )
                KPITile(
                    title: "ร่อนทราย",
                    value: "\(snapshot.mobileToday.sandRounds) รอบ",
                    subtitle: "ล้าง \(DashboardAggregations.formatNumber(snapshot.mobileToday.sandWashedCubic)) คิว",
                    accent: AppTheme.sand,
                    systemImage: "drop.fill"
                )
                KPITile(
                    title: "เช็คชื่อ",
                    value: "\(snapshot.mobileToday.presentCount) คน",
                    subtitle: "ลา \(snapshot.mobileToday.leaveCount) · ขาด \(snapshot.mobileToday.absentCount)",
                    accent: AppTheme.labor,
                    systemImage: "person.3.fill"
                )
                KPITile(
                    title: "รถดรัม",
                    value: "เช้า \(snapshot.mobileToday.tripMorning)",
                    subtitle: "บ่าย \(snapshot.mobileToday.tripAfternoon) · ถังบ้าน \(DashboardAggregations.formatNumber(snapshot.mobileToday.drumsHome))",
                    accent: AppTheme.warning,
                    systemImage: "cylinder.split.1x2"
                )
                KPITile(
                    title: "แม็คโคร",
                    value: "\(snapshot.mobileToday.macroUsageCount) ครั้ง",
                    subtitle: "\(snapshot.mobileToday.macroVehicles) คัน",
                    accent: AppTheme.purple,
                    systemImage: "hammer.fill"
                )
                KPITile(
                    title: "น้ำมัน",
                    value: "เข้า \(DashboardAggregations.formatNumber(snapshot.mobileToday.fuelInLiters)) L",
                    subtitle: "ออก \(DashboardAggregations.formatNumber(snapshot.mobileToday.fuelOutLiters)) L",
                    accent: AppTheme.fuel,
                    systemImage: "fuelpump.fill"
                )
                KPITile(
                    title: "ลางาน",
                    value: "\(snapshot.mobileToday.leaveCount) คน",
                    subtitle: "วันนี้",
                    accent: AppTheme.warning,
                    systemImage: "calendar.badge.minus"
                )
            }

            SectionCard("รวมช่วง \(periodLabel)", systemImage: "app.badge.fill", subtitle: "ยอดรวมจากแอพมือถือ") {
                mobileRangeBullet(
                    "เที่ยวรถ",
                    "\(snapshot.mobileRange.tripRounds) เที่ยว · \(snapshot.mobileRange.tripVehicles) คัน · \(DashboardAggregations.formatNumber(snapshot.mobileRange.tripCubic)) คิว"
                )
                mobileRangeBullet(
                    "ร่อนทราย",
                    "\(snapshot.mobileRange.sandRounds) รอบ · ล้าง \(DashboardAggregations.formatNumber(snapshot.mobileRange.sandWashedCubic)) คิว"
                )
                mobileRangeBullet(
                    "เช็คชื่อ",
                    "เฉลี่ย \(snapshot.mobileRange.presentCount) คน/วัน · \(snapshot.mobileRange.attendanceDays) วันที่มีเช็คชื่อ"
                )
                mobileRangeBullet(
                    "รถดรัม",
                    "เช้า \(snapshot.mobileRange.tripMorning) · บ่าย \(snapshot.mobileRange.tripAfternoon) · ถังบ้าน \(DashboardAggregations.formatNumber(snapshot.mobileRange.drumsHome))"
                )
                mobileRangeBullet(
                    "แม็คโคร",
                    "\(snapshot.mobileRange.macroUsageCount) ครั้ง · \(snapshot.mobileRange.macroVehicles) คัน"
                )
                mobileRangeBullet(
                    "น้ำมัน",
                    "เข้า \(DashboardAggregations.formatNumber(snapshot.mobileRange.fuelInLiters)) L · ออก \(DashboardAggregations.formatNumber(snapshot.mobileRange.fuelOutLiters)) L"
                )
                mobileRangeBullet(
                    "ลางาน",
                    "\(snapshot.mobileRange.leaveCount) คน-วัน · บันทึก \(snapshot.mobileRange.recordCount) รายการ"
                )
            }
        }
    }

    private func mobileRangeBullet(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(AppTheme.brand)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Expense analytics

    private var expenseSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            sectionEyebrow(.expense, title: "รายจ่ายและแนวโน้ม", subtitle: "โครงสร้าง · รายวัน · รายสัปดาห์ · ต่อรถ")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "เฉลี่ย/สัปดาห์",
                    value: DashboardAggregations.formatCurrency(
                        snapshot.expenseTotal / max(1, Double(snapshot.numDays) / 7)
                    ),
                    accent: AppTheme.warning,
                    systemImage: "chart.bar",
                    trend: expenseTrendSeries
                )
                KPITile(
                    title: "วันในช่วง",
                    value: "\(snapshot.numDays)",
                    subtitle: "vs เมื่อวาน \(snapshot.dayChangePct)%",
                    accent: AppTheme.info,
                    systemImage: "calendar",
                    deltaText: dayChangeChip
                )
            }

            SectionCard("โครงสร้างต้นทุน", systemImage: "circle.grid.cross.fill") {
                if snapshot.costSlices.isEmpty {
                    EmptyStateView(title: "ไม่มีรายจ่ายในช่วงนี้", systemImage: "tray")
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        DonutChartView(slices: snapshot.costSlices)
                            .frame(width: 140, height: 140)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.costSlices) { slice in
                                HStack {
                                    Circle().fill(Color(hex: slice.colorHex)).frame(width: 8, height: 8)
                                    Text(slice.label).font(.caption).foregroundStyle(AppTheme.ink)
                                    Spacer()
                                    Text(DashboardAggregations.formatCurrency(slice.value))
                                        .font(.caption.bold())
                                        .foregroundStyle(AppTheme.ink)
                                }
                            }
                        }
                    }
                }
            }

            SectionCard("รายจ่ายรายวัน", systemImage: "chart.bar.fill") {
                HStack {
                    Spacer(minLength: 0)
                    PillBadge(
                        text: DashboardAggregations.formatCurrency(
                            snapshot.dailyBreakdown.map(\.total).reduce(0, +)
                        ),
                        color: AppTheme.expense
                    )
                }
                BarChartView(
                    labels: snapshot.dailyBreakdown.map(\.label),
                    values: snapshot.dailyBreakdown.map(\.total),
                    barColor: AppTheme.expense
                )
                if !snapshot.dailyBreakdown.isEmpty {
                    Divider().padding(.vertical, 4)
                    dailyBreakdownTable
                }
            }

            SectionCard("เปรียบเทียบรายสัปดาห์", systemImage: "calendar.badge.clock") {
                if snapshot.weeklyBuckets.isEmpty {
                    EmptyStateView(title: "ไม่มีข้อมูล", systemImage: "calendar")
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        PillBadge(
                            text: DashboardAggregations.formatCurrency(
                                snapshot.weeklyBuckets.map(\.total).reduce(0, +)
                            ),
                            color: AppTheme.purple
                        )
                    }
                    BarChartView(
                        labels: snapshot.weeklyBuckets.map(\.label),
                        values: snapshot.weeklyBuckets.map(\.total),
                        barColor: AppTheme.purple
                    )
                    ForEach(snapshot.weeklyBuckets) { week in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(week.label).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text(DashboardAggregations.formatCurrency(week.total)).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                            }
                            Text("ค่าแรง \(DashboardAggregations.formatCurrency(week.labor)) · น้ำมัน \(DashboardAggregations.formatCurrency(week.fuel)) · รถ \(DashboardAggregations.formatCurrency(week.vehicle)) · ที่ดิน \(DashboardAggregations.formatCurrency(week.land))")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !snapshot.vehicleCosts.isEmpty {
                SectionCard("ต้นทุนต่อรถ", systemImage: "car.fill", subtitle: "น้ำมัน + ซ่อมบำรุง (สูงสุด 5 คัน)") {
                    let maxTotal = max(snapshot.vehicleCosts.map(\.total).max() ?? 1, 1)
                    ForEach(snapshot.vehicleCosts) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(row.name).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                                Spacer()
                                Text(DashboardAggregations.formatCurrency(row.total)).font(.subheadline.bold()).foregroundStyle(AppTheme.ink)
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(AppTheme.surfaceSoft)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(AppTheme.vehicle)
                                            .frame(width: geo.size.width * CGFloat(row.total / maxTotal))
                                    }
                            }
                            .frame(height: 6)
                            Text("น้ำมัน \(DashboardAggregations.formatCurrency(row.fuel)) · ซ่อม \(DashboardAggregations.formatCurrency(row.maintenance))")
                                .font(.caption2)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            SectionCard("แนวโน้มรายจ่าย", systemImage: "chart.line.uptrend.xyaxis") {
                if snapshot.dailyBreakdown.isEmpty {
                    EmptyStateView(title: "ยังไม่มีข้อมูลรายวัน", systemImage: "chart.line.uptrend.xyaxis")
                } else {
                    LineChartView(
                        labels: snapshot.dailyBreakdown.map(\.label),
                        values: snapshot.dailyBreakdown.map(\.total),
                        lineColor: AppTheme.expense
                    )
                }
            }
        }
    }

    private var dailyBreakdownTable: some View {
        let rows = Array(snapshot.dailyBreakdown.suffix(10).reversed())
        return VStack(alignment: .leading, spacing: 6) {
            Text("ตารางแยกหมวด (10 วันล่าสุด)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.label).font(.caption.bold())
                        Spacer()
                        Text(DashboardAggregations.formatCurrency(row.total)).font(.caption.bold())
                    }
                    Text("แรง \(fmtShort(row.labor)) · น้ำมัน \(fmtShort(row.fuel)) · รถ \(fmtShort(row.vehicle)) · ซ่อม \(fmtShort(row.maintenance)) · ที่ดิน \(fmtShort(row.land))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Sand (V.1 full)

    private var sandSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            sectionEyebrow(.sand, title: "วิเคราะห์ทราย", subtitle: "ล้าง · ขน · ถัง · สะสม")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                KPITile(
                    title: "ล้างทรายรวม",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.washed)) คิว",
                    subtitle: "เฉลี่ย \(DashboardAggregations.formatNumber(snapshot.sand.avgWashedPerDay)) คิว/วัน",
                    accent: AppTheme.info,
                    systemImage: "drop",
                    trend: snapshot.sandSeriesWashed,
                    deltaText: compactDelta(snapshot.sandCur.washed, snapshot.sandPrev.washed)
                )
                KPITile(
                    title: "ขนทรายรวม",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.transported)) คิว",
                    subtitle: "เฉลี่ย \(DashboardAggregations.formatNumber(snapshot.sand.avgTransportedPerDay)) คิว/วัน",
                    accent: AppTheme.warning,
                    systemImage: "truck.box",
                    trend: snapshot.sandSeriesTransported,
                    deltaText: compactDelta(snapshot.sandCur.transported, snapshot.sandPrev.transported)
                )
                KPITile(
                    title: "ทรายคงเหลือ",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.remaining)) คิว",
                    subtitle: "ล้าง − ขน",
                    accent: snapshot.sand.remaining >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "scalemass"
                )
                KPITile(
                    title: "คาดการณ์",
                    value: snapshot.sand.forecastLabel,
                    subtitle: "ทรายพอล้างอีก",
                    accent: AppTheme.purple,
                    systemImage: "calendar"
                )
                KPITile(
                    title: "ถังที่ได้",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.drumsObtained)) ถัง",
                    accent: AppTheme.sand,
                    systemImage: "archivebox.fill"
                )
                KPITile(
                    title: "ล้างที่บ้าน",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.drumsHome)) ถัง",
                    accent: Color(hex: "#e11d48"),
                    systemImage: "house"
                )
                KPITile(
                    title: "ถังคงเหลือ",
                    value: "\(DashboardAggregations.formatNumber(snapshot.sand.drumsRemaining)) ถัง",
                    subtitle: "สะสมสุทธิ (ได้ − ล้างบ้าน)",
                    accent: Color(hex: "#0ea5e9"),
                    systemImage: "cylinder.split.1x2"
                )
            }

            SectionCard("ล้างทราย vs ขนทราย", systemImage: "chart.xyaxis.line") {
                SandDualLineChart(
                    labels: snapshot.sandSeriesLabels,
                    washed: snapshot.sandSeriesWashed,
                    transported: snapshot.sandSeriesTransported
                )
                .frame(height: 180)
            }

            SectionCard("เปรียบเทียบแท่ง: ล้าง vs ขน", systemImage: "chart.bar.xaxis") {
                GroupedBarChartView(
                    labels: snapshot.sandSeriesLabels,
                    seriesA: snapshot.sandSeriesWashed,
                    seriesB: snapshot.sandSeriesTransported,
                    colorA: AppTheme.info,
                    colorB: AppTheme.warning,
                    labelA: "ล้าง",
                    labelB: "ขน"
                )
            }

            SectionCard("ทรายคงเหลือสะสม", systemImage: "chart.line.uptrend.xyaxis") {
                LineChartView(
                    labels: snapshot.sandSeriesLabels,
                    values: snapshot.sandCumulative,
                    lineColor: (snapshot.sandCumulative.last ?? 0) >= 0 ? AppTheme.income : AppTheme.expense
                )
                Text("เริ่มต้น: 0 คิว · ปัจจุบัน: \(DashboardAggregations.formatNumber(snapshot.sandCumulative.last ?? 0)) คิว")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            SectionCard("ถังที่ได้ vs ล้างที่บ้าน", systemImage: "archivebox") {
                GroupedBarChartView(
                    labels: snapshot.drums.labels,
                    seriesA: snapshot.drums.obtained,
                    seriesB: snapshot.drums.home,
                    colorA: Color(hex: "#10b981"),
                    colorB: Color(hex: "#e11d48"),
                    labelA: "ถังที่ได้",
                    labelB: "ล้างที่บ้าน"
                )
            }

            SectionCard("จำนวนถังคงเหลือสะสม", systemImage: "chart.line.flattrend.xyaxis") {
                LineChartView(
                    labels: snapshot.drums.labels,
                    values: snapshot.drums.remainingCumulative,
                    lineColor: Color(hex: "#0ea5e9")
                )
                Text("เริ่มต้น: 0 ถัง · คงเหลือสะสม: \(DashboardAggregations.formatNumber(snapshot.drums.drumsRemaining)) ถัง")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Compare (period vs previous)

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            sectionEyebrow(
                .compare,
                title: "เปรียบเทียบช่วงก่อน",
                subtitle: "\(snapshot.prevFilter.start) ถึง \(snapshot.prevFilter.end)"
            )

            if !snapshot.alerts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.alerts) { alert in
                            Text(alert.label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(alertColor(alert.severity).opacity(0.15), in: Capsule())
                                .foregroundStyle(alertColor(alert.severity))
                        }
                    }
                }
            }

            SectionCard("สัญญาณที่ควรติดตาม", systemImage: "lightbulb.fill", subtitle: "ใช้ข้อมูล \(snapshot.txCount) รายการ") {
                ForEach(Array(snapshot.insights.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(AppTheme.brand)
                            .padding(.top, 5)
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 2)
                }
            }

            SectionCard("เทียบตัวเลขหลัก", systemImage: "arrow.left.arrow.right") {
                comparisonRow("รายจ่ายรวม", snapshot.expenseTotal, snapshot.prevExpenseTotal, higherIsBetter: false)
                comparisonRow("ทรายล้าง (คิว)", snapshot.sandCur.washed, snapshot.sandPrev.washed)
                comparisonRow("ทรายขน (คิว)", snapshot.sandCur.transported, snapshot.sandPrev.transported)
                comparisonRow("เที่ยวรถ", Double(snapshot.mobileRange.tripRounds), Double(snapshot.mobilePrev.tripRounds))
                comparisonRow("ร่อนทราย (รอบ)", Double(snapshot.mobileRange.sandRounds), Double(snapshot.mobilePrev.sandRounds))
                comparisonRow("วันที่เช็คชื่อ", Double(snapshot.mobileRange.attendanceDays), Double(snapshot.mobilePrev.attendanceDays))
            }
        }
    }

    // MARK: - Data quality

    private var qualitySection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(AppTheme.hairline, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(snapshot.quality.coveragePct, 0), 100) / 100))
                    .stroke(
                        snapshot.quality.coveragePct >= 80 ? AppTheme.income
                            : snapshot.quality.coveragePct >= 50 ? AppTheme.warning
                            : AppTheme.expense,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(round(snapshot.quality.coveragePct)))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("คุณภาพข้อมูล")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text(snapshot.quality.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        snapshot.quality.coveragePct >= 80 ? AppTheme.income
                            : snapshot.quality.coveragePct >= 50 ? AppTheme.warning
                            : AppTheme.expense
                    )
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(snapshot.quality.daysWithRecords)/\(snapshot.quality.totalDays) วัน")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("ทราย \(snapshot.quality.daysWithSand) วัน")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surfaceSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    // MARK: - Small UI helpers

    private func comparisonRow(
        _ title: String,
        _ cur: Double,
        _ prev: Double,
        higherIsBetter: Bool = true
    ) -> some View {
        let improving = higherIsBetter ? (cur >= prev) : (cur <= prev)
        return HStack {
            Text(title).foregroundStyle(AppTheme.ink)
            Spacer()
            Text(DashboardAggregations.formatNumber(cur)).foregroundStyle(AppTheme.ink)
            Text(deltaText(cur, prev))
                .font(.caption)
                .foregroundStyle(improving ? AppTheme.income : AppTheme.expense)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    private var expenseTrendSeries: [Double] {
        snapshot.dailyBreakdown.map(\.total)
    }

    private var dayChangeChip: String? {
        let pct = snapshot.dayChangePct
        guard pct != 0 || !snapshot.dailyBreakdown.isEmpty else { return nil }
        let sign = pct > 0 ? "+" : ""
        return "\(sign)\(pct)%"
    }

    /// Compact delta for KPI chip, e.g. "+12%" / "-5%".
    private func compactDelta(_ cur: Double, _ prev: Double) -> String? {
        guard let pct = DashboardAggregations.pctChangeVsPrev(cur: cur, prev: prev) else { return nil }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(round(pct)))%"
    }

    private func deltaText(_ cur: Double, _ prev: Double) -> String {
        guard let pct = DashboardAggregations.pctChangeVsPrev(cur: cur, prev: prev) else {
            return "ไม่มีฐานเทียบ"
        }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(Int(round(pct)))% vs ช่วงก่อน"
    }

    private func alertColor(_ severity: OverviewAlert.Severity) -> Color {
        switch severity {
        case .red: return AppTheme.expense
        case .amber: return AppTheme.warning
        case .green: return AppTheme.income
        }
    }

    private func fmtShort(_ v: Double) -> String {
        if abs(v) < 0.005 { return "0" }
        return DashboardAggregations.formatNumber(v)
    }
}

// MARK: - Dual line (washed vs transported)

private struct SandDualLineChart: View {
    let labels: [String]
    let washed: [Double]
    let transported: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxV = max((washed + transported).max() ?? 1, 1)
            let w = geo.size.width
            let h = geo.size.height
            let count = max(labels.count, 1)
            ZStack(alignment: .topLeading) {
                path(values: washed, color: AppTheme.info, maxV: maxV, w: w, h: h, count: count)
                path(values: transported, color: AppTheme.warning, maxV: maxV, w: w, h: h, count: count)
                HStack(spacing: 12) {
                    Label("ล้าง", systemImage: "circle.fill").font(.caption2).foregroundStyle(AppTheme.info)
                    Label("ขน", systemImage: "circle.fill").font(.caption2).foregroundStyle(AppTheme.warning)
                }
                .padding(.top, 4)
            }
        }
    }

    private func path(values: [Double], color: Color, maxV: Double, w: CGFloat, h: CGFloat, count: Int) -> some View {
        Path { p in
            for (i, v) in values.enumerated() {
                let x = count <= 1 ? w / 2 : CGFloat(i) / CGFloat(count - 1) * w
                let y = h - CGFloat(v / maxV) * (h - 20) - 10
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(color, lineWidth: 2.5)
    }
}
