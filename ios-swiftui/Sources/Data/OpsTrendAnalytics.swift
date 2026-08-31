import Foundation

/// Period scope for the ops trend analytics tab (trip + sand).
enum OpsTrendPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "รายสัปดาห์"
        case .month: return "รายเดือน"
        }
    }

    var shortLabel: String {
        switch self {
        case .week: return "สัปดาห์"
        case .month: return "เดือน"
        }
    }

    /// Inclusive day count for the active window.
    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }
}

enum OpsTrendFocus: String, CaseIterable, Identifiable, Sendable {
    case both
    case trip
    case sand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both: return "รวม"
        case .trip: return "เที่ยวรถ"
        case .sand: return "ร่อนทราย"
        }
    }
}

enum OpsTrendPace: String, Sendable {
    case faster
    case slower
    case steady
    case newBaseline

    var label: String {
        switch self {
        case .faster: return "เร็วขึ้น"
        case .slower: return "ช้าลง"
        case .steady: return "คงที่"
        case .newBaseline: return "เริ่มต้น"
        }
    }

    var systemImage: String {
        switch self {
        case .faster: return "arrow.up.right"
        case .slower: return "arrow.down.right"
        case .steady: return "arrow.right"
        case .newBaseline: return "sparkles"
        }
    }
}

struct OpsTrendPoint: Identifiable, Sendable {
    let id: String
    let startKey: String
    let endKey: String
    let label: String
    let tripRounds: Int
    let sandRounds: Int
    let tripCubic: Double
    let sandWashedCubic: Double
    let dayCount: Int

    var tripAvgPerDay: Double {
        dayCount > 0 ? Double(tripRounds) / Double(dayCount) : 0
    }

    var sandAvgPerDay: Double {
        dayCount > 0 ? Double(sandRounds) / Double(dayCount) : 0
    }
}

struct OpsTrendMetricCard: Sendable {
    let title: String
    let unit: String
    let total: Double
    let average: Double
    let prevTotal: Double
    let prevAverage: Double
    let bestLabel: String
    let bestValue: Double
    let worstLabel: String
    let worstValue: Double
    let changePct: Double?
    let pace: OpsTrendPace
    let series: [Double]
    let prevSeries: [Double]
    let labels: [String]

    var growthScore: Int {
        guard let changePct else { return pace == .newBaseline ? 50 : 0 }
        // Map −50%…+50% → 0…100, clamped.
        let raw = 50.0 + (changePct / 50.0) * 50.0
        return Int(max(0, min(100, raw.rounded())))
    }
}

struct OpsTrendReport: Sendable {
    let period: OpsTrendPeriod
    let filter: DateFilter
    let prevFilter: DateFilter
    let points: [OpsTrendPoint]
    let prevPoints: [OpsTrendPoint]
    let trip: OpsTrendMetricCard
    let sand: OpsTrendMetricCard
    let insights: [String]
    let coverageDays: Int
    let activeDays: Int

    nonisolated static func empty(period: OpsTrendPeriod) -> OpsTrendReport {
        let filter = DashboardAggregations.dateFilter(
            preset: period == .week ? .days7 : .days30,
            customStart: nil,
            customEnd: nil
        )
        let emptyCard = OpsTrendMetricCard(
            title: "",
            unit: "",
            total: 0,
            average: 0,
            prevTotal: 0,
            prevAverage: 0,
            bestLabel: "—",
            bestValue: 0,
            worstLabel: "—",
            worstValue: 0,
            changePct: nil,
            pace: .newBaseline,
            series: [],
            prevSeries: [],
            labels: []
        )
        return OpsTrendReport(
            period: period,
            filter: filter,
            prevFilter: DashboardAggregations.previousPeriodFilter(filter),
            points: [],
            prevPoints: [],
            trip: emptyCard,
            sand: emptyCard,
            insights: [],
            coverageDays: 0,
            activeDays: 0
        )
    }
}

enum OpsTrendAnalytics {
    nonisolated static func build(
        period: OpsTrendPeriod,
        transactions: [Transaction],
        employees: [Employee],
        byDay: [String: [Transaction]] = [:]
    ) -> OpsTrendReport {
        let filter = DashboardAggregations.dateFilter(
            preset: period == .week ? .days7 : .days30,
            customStart: nil,
            customEnd: nil
        )
        let prevFilter = DashboardAggregations.previousPeriodFilter(filter)
        let dayKeys = DashboardAggregations.enumerateDates(in: filter)
        let prevKeys = DashboardAggregations.enumerateDates(in: prevFilter)

        let daily = dayKeys.map { dayMetrics(dayKey: $0, byDay: byDay, transactions: transactions, employees: employees) }
        let prevDaily = prevKeys.map { dayMetrics(dayKey: $0, byDay: byDay, transactions: transactions, employees: employees) }

        let points: [OpsTrendPoint]
        let prevPoints: [OpsTrendPoint]
        switch period {
        case .week:
            points = daily
            prevPoints = alignSeries(prevDaily, toCount: daily.count)
        case .month:
            points = bucketWeekly(daily)
            prevPoints = alignSeries(bucketWeekly(prevDaily), toCount: bucketWeekly(daily).count)
        }

        let trip = metricCard(
            title: "เที่ยวรถ",
            unit: "เที่ยว",
            points: points,
            prevPoints: prevPoints,
            value: \.tripRounds
        )
        let sand = metricCard(
            title: "ร่อนทราย",
            unit: "รอบ",
            points: points,
            prevPoints: prevPoints,
            value: \.sandRounds
        )

        let activeDays = daily.filter { $0.tripRounds > 0 || $0.sandRounds > 0 }.count
        let insights = buildInsights(period: period, trip: trip, sand: sand, activeDays: activeDays, totalDays: daily.count)

        return OpsTrendReport(
            period: period,
            filter: filter,
            prevFilter: prevFilter,
            points: points,
            prevPoints: prevPoints,
            trip: trip,
            sand: sand,
            insights: insights,
            coverageDays: daily.count,
            activeDays: activeDays
        )
    }

    // MARK: - Daily / weekly points

    private nonisolated static func dayMetrics(
        dayKey: String,
        byDay: [String: [Transaction]],
        transactions: [Transaction],
        employees: [Employee]
    ) -> OpsTrendPoint {
        let dayTx = byDay[dayKey] ?? transactions.filter { String($0.date.prefix(10)) == dayKey }
        let m = MobileOpsSnapshot.metricsForDay(dayKey: dayKey, transactions: dayTx, employees: employees)
        return OpsTrendPoint(
            id: dayKey,
            startKey: dayKey,
            endKey: dayKey,
            label: DashboardAggregations.dayLabel(dayKey),
            tripRounds: m.tripRounds,
            sandRounds: m.sandRounds,
            tripCubic: m.tripCubic,
            sandWashedCubic: m.sandWashedCubic,
            dayCount: 1
        )
    }

    private nonisolated static func bucketWeekly(_ daily: [OpsTrendPoint]) -> [OpsTrendPoint] {
        guard !daily.isEmpty else { return [] }
        var out: [OpsTrendPoint] = []
        var i = 0
        var week = 1
        while i < daily.count {
            let end = min(i + 7, daily.count)
            let slice = Array(daily[i..<end])
            let start = slice.first!.startKey
            let finish = slice.last!.endKey
            out.append(
                OpsTrendPoint(
                    id: "w\(week)-\(start)",
                    startKey: start,
                    endKey: finish,
                    label: "W\(week)",
                    tripRounds: slice.reduce(0) { $0 + $1.tripRounds },
                    sandRounds: slice.reduce(0) { $0 + $1.sandRounds },
                    tripCubic: slice.reduce(0) { $0 + $1.tripCubic },
                    sandWashedCubic: slice.reduce(0) { $0 + $1.sandWashedCubic },
                    dayCount: slice.count
                )
            )
            week += 1
            i = end
        }
        return out
    }

    private nonisolated static func alignSeries(_ points: [OpsTrendPoint], toCount count: Int) -> [OpsTrendPoint] {
        if points.count == count { return points }
        if points.count > count { return Array(points.suffix(count)) }
        let pad = count - points.count
        let blanks: [OpsTrendPoint] = (0..<pad).map { idx in
            OpsTrendPoint(
                id: "pad-\(idx)",
                startKey: "",
                endKey: "",
                label: "—",
                tripRounds: 0,
                sandRounds: 0,
                tripCubic: 0,
                sandWashedCubic: 0,
                dayCount: 1
            )
        }
        return blanks + points
    }

    // MARK: - Metric cards

    private nonisolated static func metricCard(
        title: String,
        unit: String,
        points: [OpsTrendPoint],
        prevPoints: [OpsTrendPoint],
        value: KeyPath<OpsTrendPoint, Int>
    ) -> OpsTrendMetricCard {
        let series = points.map { Double($0[keyPath: value]) }
        let prevSeries = prevPoints.map { Double($0[keyPath: value]) }
        let labels = points.map(\.label)
        let total = series.reduce(0, +)
        let prevTotal = prevSeries.reduce(0, +)
        let days = max(1, points.reduce(0) { $0 + $1.dayCount })
        let prevDays = max(1, prevPoints.reduce(0) { $0 + $1.dayCount })
        let average = total / Double(days)
        let prevAverage = prevTotal / Double(prevDays)

        var bestLabel = "—"
        var bestValue = 0.0
        var worstLabel = "—"
        var worstValue = Double.greatestFiniteMagnitude
        for p in points {
            let v = Double(p[keyPath: value])
            if v >= bestValue {
                bestValue = v
                bestLabel = p.label
            }
            if v <= worstValue {
                worstValue = v
                worstLabel = p.label
            }
        }
        if points.isEmpty { worstValue = 0 }

        let changePct = DashboardAggregations.pctChangeVsPrev(cur: average, prev: prevAverage)
        let pace = classifyPace(changePct: changePct, cur: average, prev: prevAverage)

        return OpsTrendMetricCard(
            title: title,
            unit: unit,
            total: total,
            average: average,
            prevTotal: prevTotal,
            prevAverage: prevAverage,
            bestLabel: bestLabel,
            bestValue: bestValue,
            worstLabel: worstLabel,
            worstValue: worstValue,
            changePct: changePct,
            pace: pace,
            series: series,
            prevSeries: prevSeries,
            labels: labels
        )
    }

    private nonisolated static func classifyPace(changePct: Double?, cur: Double, prev: Double) -> OpsTrendPace {
        if prev == 0 && cur > 0 { return .newBaseline }
        if prev == 0 && cur == 0 { return .steady }
        guard let changePct else { return .steady }
        if changePct >= 8 { return .faster }
        if changePct <= -8 { return .slower }
        return .steady
    }

    private nonisolated static func buildInsights(
        period: OpsTrendPeriod,
        trip: OpsTrendMetricCard,
        sand: OpsTrendMetricCard,
        activeDays: Int,
        totalDays: Int
    ) -> [String] {
        var lines: [String] = []
        let scope = period.shortLabel

        lines.append(insightLine(prefix: "เที่ยวรถ", card: trip, scope: scope))
        lines.append(insightLine(prefix: "ร่อนทราย", card: sand, scope: scope))

        if totalDays > 0 {
            let coverage = Int(round(Double(activeDays) / Double(totalDays) * 100))
            lines.append("วันที่มีงาน \(activeDays)/\(totalDays) วัน (ครอบคลุม \(coverage)%)")
        }

        if trip.average > 0, sand.average > 0 {
            let ratio = trip.average / max(sand.average, 0.001)
            lines.append(String(format: "เฉลี่ยเที่ยวรถต่อรอบร่อน ≈ %.1f เที่ยว/รอบ", ratio))
        }

        return lines
    }

    private nonisolated static func insightLine(prefix: String, card: OpsTrendMetricCard, scope: String) -> String {
        let avgText = formatCompact(card.average)
        switch card.pace {
        case .faster:
            let pct = Int((card.changePct ?? 0).rounded())
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · \(card.pace.label) \(pct)% เทียบ\(scope)ก่อน"
        case .slower:
            let pct = Int(abs(card.changePct ?? 0).rounded())
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · \(card.pace.label) \(pct)% เทียบ\(scope)ก่อน"
        case .steady:
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · จังหวะคงที่เทียบ\(scope)ก่อน"
        case .newBaseline:
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · มีข้อมูลช่วงนี้เป็นครั้งแรก"
        }
    }

    nonisolated static func formatCompact(_ value: Double) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if abs(value - value.rounded()) < 0.05 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }

    nonisolated static func formatSignedPct(_ value: Double?) -> String {
        guard let value else { return "—" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Int(value.rounded()))%"
    }
}
