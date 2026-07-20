import SwiftUI

/// Memoized bundle of all Overview (V.1 + V.2 + V.5) analytics — built off the main thread.
struct OverviewSnapshot: Sendable {
    let financial: FinancialSummary
    let prevFinancial: FinancialSummary
    let prevFilter: DateFilter
    let numDays: Int
    let marginPct: Double
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
    let composite: CompositeScoreResult
    let breakEven: [BreakEvenPoint]
    let quality: DataQualitySummary
    let alerts: [OverviewAlert]
    let insights: [String]
    let csvText: String
    let txCount: Int

    nonisolated static func empty(filter: DateFilter) -> OverviewSnapshot {
        let emptyFin = FinancialSummary(income: 0, expense: 0)
        let emptyScore = CompositeScoreResult(score: 0, breakdown: [])
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
            financial: emptyFin, prevFinancial: emptyFin, prevFilter: filter,
            numDays: 1, marginPct: 0, costSlices: [], dailyBreakdown: [],
            weeklyBuckets: [], vehicleCosts: [], dayChangePct: 0,
            sand: emptySand, sandSeriesWashed: [], sandSeriesTransported: [],
            sandSeriesLabels: [], sandCumulative: [], drums: emptyDrums,
            sandCur: (0, 0), sandPrev: (0, 0), composite: emptyScore,
            breakEven: [], quality: quality, alerts: [], insights: [],
            csvText: "", txCount: 0
        )
    }

    nonisolated static func build(
        filter: DateFilter,
        transactions: [Transaction],
        allTransactions: [Transaction],
        settings: AppSettings
    ) -> OverviewSnapshot {
        let curTx = transactions
        let prevFilter = DashboardAggregations.previousPeriodFilter(filter)
        let prevTx = DashboardAggregations.filterByRange(allTransactions, range: prevFilter)
        let financial = DashboardAggregations.aggregateFinancial(curTx)
        let prevFinancial = DashboardAggregations.aggregateFinancial(prevTx)
        let numDays = DashboardAggregations.countInclusiveDays(filter.start, filter.end)
        let marginPct: Double = financial.income > 0
            ? (financial.profit / financial.income) * 100
            : (financial.profit > 0 ? 100 : 0)

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
        let composite = DashboardAggregations.computeCompositeScore(
            cur: financial, prev: prevFinancial,
            sandWashed: sandCur.washed, sandTransported: sandCur.transported,
            prevSandWashed: sandPrev.washed, prevSandTransported: sandPrev.transported
        )
        let quality = DashboardAggregations.dataQuality(filter: filter, transactions: curTx)
        let alerts = DashboardAggregations.buildOverviewAlerts(
            cur: financial, prev: prevFinancial, quality: quality
        )
        let insights = DashboardAggregations.buildOverviewInsights(
            cur: financial, prev: prevFinancial,
            sandWashed: sandCur.washed, sandTransported: sandCur.transported,
            quality: quality
        )
        let csv = DashboardAggregations.overviewCSV(
            cur: financial, prev: prevFinancial,
            sandCur: sandCur, sandPrev: sandPrev, score: composite.score
        )

        return OverviewSnapshot(
            financial: financial,
            prevFinancial: prevFinancial,
            prevFilter: prevFilter,
            numDays: numDays,
            marginPct: marginPct,
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
            composite: composite,
            breakEven: DashboardAggregations.breakEvenPoints(filter: filter, transactions: curTx),
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
    let settings: AppSettings
    let dateFilter: DateFilter

    @State private var snapshot = OverviewSnapshot.empty(filter: DateFilter(start: "", end: ""))
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showShare = false
    @State private var jumpTarget: OverviewSection?

    private enum OverviewSection: String, CaseIterable, Identifiable, Hashable {
        case finance = "การเงิน"
        case expense = "รายจ่าย"
        case sand = "ทราย"
        case compare = "เปรียบเทียบ"
        case quality = "คุณภาพ"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                    header
                    jumpChips(proxy: proxy)

                    financeSection.id(OverviewSection.finance)
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
        let settingsCopy = settings
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let built = await Task.detached(priority: .userInitiated) {
                OverviewSnapshot.build(
                    filter: filter,
                    transactions: txs,
                    allTransactions: all,
                    settings: settingsCopy
                )
            }.value
            guard !Task.isCancelled else { return }
            snapshot = built
        }
    }

    // MARK: - Header / chips

    private var header: some View {
        HStack(alignment: .top) {
            SectionHeader(
                title: "ภาพรวม",
                systemImage: "chart.pie.fill",
                subtitle: "การเงิน · รายจ่าย · ทราย · เทียบช่วงก่อน"
            )
            Spacer()
            Button {
                showShare = true
            } label: {
                Label("CSV", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.brand)
            .disabled(snapshot.csvText.isEmpty)
        }
    }

    private func jumpChips(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OverviewSection.allCases) { section in
                    Button {
                        jumpTarget = section
                    } label: {
                        Text(section.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.brand.opacity(0.12), in: Capsule())
                            .foregroundStyle(AppTheme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Finance (V.1)

    private var financeSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            SectionHeader(title: "การเงิน", systemImage: "banknote.fill", subtitle: "กำไร · รายรับ · รายจ่าย · โครงสร้างต้นทุน")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "กำไรสุทธิ",
                    value: DashboardAggregations.formatCurrency(snapshot.financial.profit),
                    subtitle: "รายรับ − รายจ่าย",
                    accent: snapshot.financial.profit >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "chart.line.uptrend.xyaxis",
                    trend: expenseTrendSeries,
                    deltaText: compactDelta(snapshot.financial.profit, snapshot.prevFinancial.profit)
                )
                KPITile(
                    title: "รายรับรวม",
                    value: DashboardAggregations.formatCurrency(snapshot.financial.income),
                    accent: AppTheme.income,
                    systemImage: "banknote",
                    deltaText: compactDelta(snapshot.financial.income, snapshot.prevFinancial.income)
                )
                KPITile(
                    title: "รายจ่ายรวม",
                    value: DashboardAggregations.formatCurrency(snapshot.financial.expense),
                    subtitle: "\(snapshot.numDays) วัน",
                    accent: AppTheme.expense,
                    systemImage: "creditcard",
                    trend: expenseTrendSeries,
                    deltaText: compactDelta(snapshot.financial.expense, snapshot.prevFinancial.expense)
                )
                KPITile(
                    title: "อัตรากำไร",
                    value: String(format: "%.1f%%", snapshot.marginPct),
                    subtitle: "ช่วงก่อน \(String(format: "%.1f%%", marginPct(snapshot.prevFinancial)))",
                    accent: AppTheme.info,
                    systemImage: "percent",
                    deltaText: compactDelta(snapshot.marginPct, marginPct(snapshot.prevFinancial))
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
                                    Text(slice.label).font(.caption)
                                    Spacer()
                                    Text(DashboardAggregations.formatCurrency(slice.value))
                                        .font(.caption.bold())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expense analytics (V.2)

    private var expenseSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            SectionHeader(title: "รายจ่ายและแนวโน้ม", systemImage: "chart.bar.xaxis", subtitle: "รายวัน · รายสัปดาห์ · ต่อรถ")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "เฉลี่ย/วัน",
                    value: DashboardAggregations.formatCurrency(
                        snapshot.numDays > 0 ? snapshot.financial.expense / Double(snapshot.numDays) : 0
                    ),
                    subtitle: "vs เมื่อวาน \(snapshot.dayChangePct)%",
                    accent: AppTheme.info,
                    systemImage: "calendar",
                    trend: expenseTrendSeries,
                    deltaText: dayChangeChip
                )
                KPITile(
                    title: "เฉลี่ย/สัปดาห์",
                    value: DashboardAggregations.formatCurrency(
                        snapshot.financial.expense / max(1, Double(snapshot.numDays) / 7)
                    ),
                    accent: AppTheme.warning,
                    systemImage: "chart.bar",
                    trend: expenseTrendSeries
                )
            }

            SectionCard("รายจ่ายรายวัน", systemImage: "chart.bar.fill") {
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
                    BarChartView(
                        labels: snapshot.weeklyBuckets.map(\.label),
                        values: snapshot.weeklyBuckets.map(\.total),
                        barColor: AppTheme.purple
                    )
                    ForEach(snapshot.weeklyBuckets) { week in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(week.label).font(.subheadline.bold())
                                Spacer()
                                Text(DashboardAggregations.formatCurrency(week.total)).font(.subheadline.bold())
                            }
                            Text("ค่าแรง \(DashboardAggregations.formatCurrency(week.labor)) · น้ำมัน \(DashboardAggregations.formatCurrency(week.fuel)) · รถ \(DashboardAggregations.formatCurrency(week.vehicle)) · ที่ดิน \(DashboardAggregations.formatCurrency(week.land))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
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
                                Text(row.name).font(.subheadline.bold())
                                Spacer()
                                Text(DashboardAggregations.formatCurrency(row.total)).font(.subheadline.bold())
                            }
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Color(.tertiarySystemFill))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(AppTheme.vehicle)
                                            .frame(width: geo.size.width * CGFloat(row.total / maxTotal))
                                    }
                            }
                            .frame(height: 6)
                            Text("น้ำมัน \(DashboardAggregations.formatCurrency(row.fuel)) · ซ่อม \(DashboardAggregations.formatCurrency(row.maintenance))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            SectionCard("แนวโน้มรายจ่าย", systemImage: "chart.line.uptrend.xyaxis") {
                LineChartView(
                    labels: snapshot.dailyBreakdown.map(\.label),
                    values: snapshot.dailyBreakdown.map(\.total),
                    lineColor: AppTheme.expense
                )
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
            SectionHeader(title: "วิเคราะห์ทราย", systemImage: "drop.fill", subtitle: "ล้าง · ขน · ถัง · สะสม")

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

    // MARK: - Compare / score (V.5)

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            SectionHeader(
                title: "เปรียบเทียบช่วงก่อน",
                systemImage: "speedometer",
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                KPITile(
                    title: "กำไรสุทธิ (ช่วงนี้)",
                    value: DashboardAggregations.formatCurrency(snapshot.financial.profit),
                    subtitle: deltaText(snapshot.financial.profit, snapshot.prevFinancial.profit),
                    accent: snapshot.financial.profit >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "chart.line.uptrend.xyaxis",
                    trend: expenseTrendSeries,
                    deltaText: compactDelta(snapshot.financial.profit, snapshot.prevFinancial.profit)
                )
                scoreTile
            }

            SectionCard("เทียบตัวเลขหลัก", systemImage: "arrow.left.arrow.right") {
                comparisonRow("รายรับรวม", snapshot.financial.income, snapshot.prevFinancial.income)
                comparisonRow("รายจ่ายรวม", snapshot.financial.expense, snapshot.prevFinancial.expense)
                comparisonRow("กำไรขาดทุน", snapshot.financial.profit, snapshot.prevFinancial.profit)
                comparisonRow("ทรายล้าง (คิว)", snapshot.sandCur.washed, snapshot.sandPrev.washed)
                comparisonRow("ทรายขน (คิว)", snapshot.sandCur.transported, snapshot.sandPrev.transported)
            }

            SectionCard("รายละเอียดคะแนน", systemImage: "star.fill") {
                if snapshot.composite.breakdown.isEmpty {
                    EmptyStateView(title: "ยังไม่มีคะแนน", systemImage: "star")
                } else {
                    ForEach(snapshot.composite.breakdown) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.label).font(.subheadline.bold())
                                Spacer()
                                Text("\(item.scorePart)").font(.subheadline)
                                Text("(\(item.weight))").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(item.changeLabel).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            SectionCard("จุดคุ้มทุนรายวัน", systemImage: "chart.dots.scatter", subtitle: "รายรับ vs รายจ่าย") {
                BreakEvenScatterView(
                    points: snapshot.breakEven.map { ($0.income, $0.expense, $0.label) }
                )
                HStack(spacing: 12) {
                    Label("วันกำไร", systemImage: "circle.fill").font(.caption2).foregroundStyle(.green)
                    Label("วันขาดทุน", systemImage: "circle.fill").font(.caption2).foregroundStyle(.red)
                }
            }

            SectionCard("วิเคราะห์กำไรขาดทุน (สรุป)", systemImage: "doc.text.fill") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    KPITile(
                        title: "รายรับ",
                        value: DashboardAggregations.formatCurrency(snapshot.financial.income),
                        accent: AppTheme.income,
                        systemImage: "arrow.up.circle"
                    )
                    KPITile(
                        title: "รายจ่าย / ต้นทุน",
                        value: DashboardAggregations.formatCurrency(snapshot.financial.expense),
                        accent: AppTheme.expense,
                        systemImage: "arrow.down.circle"
                    )
                }
                KPITile(
                    title: "กำไรสุทธิ (P&L)",
                    value: DashboardAggregations.formatCurrency(snapshot.financial.profit),
                    subtitle: snapshot.financial.income > 0
                        ? "อัตราส่วนรายจ่ายต่อรายรับ: \(String(format: "%.1f%%", (snapshot.financial.expense / snapshot.financial.income) * 100))"
                        : nil,
                    accent: snapshot.financial.profit >= 0 ? AppTheme.income : AppTheme.expense,
                    systemImage: "scalemass.fill"
                )
            }
        }
    }

    // MARK: - Data quality

    private var qualitySection: some View {
        SectionCard("ความน่าเชื่อถือของข้อมูล", systemImage: "checkmark.shield.fill") {
            HStack {
                Text("สถานะคุณภาพข้อมูล")
                    .font(.subheadline)
                Spacer()
                Text(snapshot.quality.statusLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(
                        snapshot.quality.coveragePct >= 80 ? AppTheme.income
                            : snapshot.quality.coveragePct >= 50 ? AppTheme.warning
                            : AppTheme.expense
                    )
            }
            qualityRow("วันในช่วงที่เลือก", "\(snapshot.quality.totalDays)")
            qualityRow(
                "วันมีข้อมูลธุรกรรม",
                "\(snapshot.quality.daysWithRecords) (\(Int(round(snapshot.quality.coveragePct)))%)"
            )
            qualityRow(
                "วันมีข้อมูลทราย",
                "\(snapshot.quality.daysWithSand) (\(Int(round(snapshot.quality.sandCoveragePct)))%)"
            )
        }
    }

    // MARK: - Small UI helpers

    private var scoreTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("คะแนนรวม")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(snapshot.composite.score) / 100)
                        .stroke(AppTheme.purple, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(snapshot.composite.score)")
                        .font(.headline.bold())
                }
                .frame(width: 52, height: 52)
                Text("/ 100")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Capsule()
                .fill(AppTheme.purple)
                .frame(height: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func comparisonRow(_ title: String, _ cur: Double, _ prev: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(DashboardAggregations.formatNumber(cur))
            Text(deltaText(cur, prev))
                .font(.caption)
                .foregroundStyle(cur >= prev ? AppTheme.income : AppTheme.expense)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }

    private func qualityRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.bold())
        }
        .padding(.vertical, 2)
    }

    private func marginPct(_ fin: FinancialSummary) -> Double {
        guard fin.income > 0 else { return fin.profit > 0 ? 100 : 0 }
        return (fin.profit / fin.income) * 100
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
