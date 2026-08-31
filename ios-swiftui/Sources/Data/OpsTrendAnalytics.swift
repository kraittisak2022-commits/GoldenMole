import Foundation
import Darwin

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

    var dayCount: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        }
    }

    /// Daily trip target used for score / attainment (matches trip board target).
    var tripDailyTarget: Double { 250 }
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

enum OpsTrendGrade: String, Sendable {
    case aPlus = "A+"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    var label: String {
        switch self {
        case .aPlus: return "ยอดเยี่ยม"
        case .a: return "ดีมาก"
        case .b: return "ดี"
        case .c: return "พอใช้"
        case .d: return "ต้องเร่ง"
        }
    }

    static func from(score: Int) -> OpsTrendGrade {
        switch score {
        case 90...: return .aPlus
        case 80..<90: return .a
        case 65..<80: return .b
        case 50..<65: return .c
        default: return .d
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
    let tripVehicles: Int
    let tripMorning: Int
    let tripAfternoon: Int
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
    let cumulative: [Double]
    let prevCumulative: [Double]
    let stdDev: Double
    let consistencyScore: Int
    let activeBucketCount: Int
    let targetAttainmentPct: Double?

    var growthScore: Int {
        guard let changePct else { return pace == .newBaseline ? 55 : 45 }
        let raw = 50.0 + (changePct / 40.0) * 50.0
        return Int(max(0, min(100, raw.rounded())))
    }
}

/// Composite period score with weighted pillars.
struct OpsTrendScorecard: Sendable {
    let score: Int
    let grade: OpsTrendGrade
    let prevScore: Int
    let scoreDelta: Int
    let volumeScore: Int
    let growthScore: Int
    let consistencyScore: Int
    let coverageScore: Int
    let balanceScore: Int
    let headline: String
    let subheadline: String
}

struct OpsTrendBucketScore: Identifiable, Sendable {
    let id: String
    let label: String
    let score: Int
    let tripTotal: Double
    let sandTotal: Double
}

struct OpsTrendReport: Sendable {
    let period: OpsTrendPeriod
    let filter: DateFilter
    let prevFilter: DateFilter
    let points: [OpsTrendPoint]
    let prevPoints: [OpsTrendPoint]
    let dailyPoints: [OpsTrendPoint]
    let trip: OpsTrendMetricCard
    let sand: OpsTrendMetricCard
    let scorecard: OpsTrendScorecard
    let bucketScores: [OpsTrendBucketScore]
    let insights: [String]
    let coverageDays: Int
    let activeDays: Int
    let streakDays: Int
    let tripSandRatio: Double?
    let prevTripSandRatio: Double?

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
            labels: [],
            cumulative: [],
            prevCumulative: [],
            stdDev: 0,
            consistencyScore: 0,
            activeBucketCount: 0,
            targetAttainmentPct: nil
        )
        let emptyScore = OpsTrendScorecard(
            score: 0,
            grade: .d,
            prevScore: 0,
            scoreDelta: 0,
            volumeScore: 0,
            growthScore: 0,
            consistencyScore: 0,
            coverageScore: 0,
            balanceScore: 0,
            headline: "ยังไม่มีข้อมูล",
            subheadline: "เมื่อมีเที่ยวรถหรือร่อนทราย จะให้คะแนนที่นี่"
        )
        return OpsTrendReport(
            period: period,
            filter: filter,
            prevFilter: DashboardAggregations.previousPeriodFilter(filter),
            points: [],
            prevPoints: [],
            dailyPoints: [],
            trip: emptyCard,
            sand: emptyCard,
            scorecard: emptyScore,
            bucketScores: [],
            insights: [],
            coverageDays: 0,
            activeDays: 0,
            streakDays: 0,
            tripSandRatio: nil,
            prevTripSandRatio: nil
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
            let buckets = bucketWeekly(daily)
            points = buckets
            prevPoints = alignSeries(bucketWeekly(prevDaily), toCount: buckets.count)
        }

        let trip = metricCard(
            title: "เที่ยวรถ",
            unit: "เที่ยว",
            points: points,
            prevPoints: prevPoints,
            value: \.tripRounds,
            dailyTarget: period.tripDailyTarget
        )
        let sand = metricCard(
            title: "ร่อนทราย",
            unit: "รอบ",
            points: points,
            prevPoints: prevPoints,
            value: \.sandRounds,
            dailyTarget: nil
        )

        let activeDays = daily.filter { $0.tripRounds > 0 || $0.sandRounds > 0 }.count
        let streak = trailingActiveStreak(daily)
        let ratio = ratioOrNil(trip: trip.average, sand: sand.average)
        let prevRatio = ratioOrNil(trip: trip.prevAverage, sand: sand.prevAverage)

        let scorecard = buildScorecard(
            period: period,
            trip: trip,
            sand: sand,
            activeDays: activeDays,
            totalDays: daily.count,
            streak: streak
        )
        let prevScorecard = buildScorecard(
            period: period,
            trip: flippedPrevAsCurrent(trip),
            sand: flippedPrevAsCurrent(sand),
            activeDays: prevDaily.filter { $0.tripRounds > 0 || $0.sandRounds > 0 }.count,
            totalDays: prevDaily.count,
            streak: trailingActiveStreak(prevDaily)
        )
        let scored = OpsTrendScorecard(
            score: scorecard.score,
            grade: scorecard.grade,
            prevScore: prevScorecard.score,
            scoreDelta: scorecard.score - prevScorecard.score,
            volumeScore: scorecard.volumeScore,
            growthScore: scorecard.growthScore,
            consistencyScore: scorecard.consistencyScore,
            coverageScore: scorecard.coverageScore,
            balanceScore: scorecard.balanceScore,
            headline: scorecard.headline,
            subheadline: scorecard.subheadline
        )

        let bucketScores: [OpsTrendBucketScore] = {
            switch period {
            case .week:
                return daily.enumerated().map { idx, p in
                    let dayScore = dayBucketScore(point: p, target: period.tripDailyTarget)
                    return OpsTrendBucketScore(
                        id: p.id,
                        label: weekdayShort(p.startKey) ?? p.label,
                        score: dayScore,
                        tripTotal: Double(p.tripRounds),
                        sandTotal: Double(p.sandRounds)
                    )
                }
            case .month:
                return points.map { p in
                    OpsTrendBucketScore(
                        id: p.id,
                        label: p.label,
                        score: weekBucketScore(point: p, target: period.tripDailyTarget),
                        tripTotal: Double(p.tripRounds),
                        sandTotal: Double(p.sandRounds)
                    )
                }
            }
        }()

        let insights = buildInsights(
            period: period,
            trip: trip,
            sand: sand,
            scorecard: scored,
            activeDays: activeDays,
            totalDays: daily.count,
            streak: streak,
            ratio: ratio
        )

        return OpsTrendReport(
            period: period,
            filter: filter,
            prevFilter: prevFilter,
            points: points,
            prevPoints: prevPoints,
            dailyPoints: daily,
            trip: trip,
            sand: sand,
            scorecard: scored,
            bucketScores: bucketScores,
            insights: insights,
            coverageDays: daily.count,
            activeDays: activeDays,
            streakDays: streak,
            tripSandRatio: ratio,
            prevTripSandRatio: prevRatio
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
            tripVehicles: m.tripVehicles,
            tripMorning: m.tripMorning,
            tripAfternoon: m.tripAfternoon,
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
                    tripVehicles: slice.map(\.tripVehicles).max() ?? 0,
                    tripMorning: slice.reduce(0) { $0 + $1.tripMorning },
                    tripAfternoon: slice.reduce(0) { $0 + $1.tripAfternoon },
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
                tripVehicles: 0,
                tripMorning: 0,
                tripAfternoon: 0,
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
        value: KeyPath<OpsTrendPoint, Int>,
        dailyTarget: Double?
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
        let std = standardDeviation(series)
        let consistency = consistencyScore(series: series, average: average, stdDev: std)
        let activeBuckets = series.filter { $0 > 0 }.count

        var attainment: Double?
        if let dailyTarget, dailyTarget > 0 {
            attainment = min(150, (average / dailyTarget) * 100)
        }

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
            labels: labels,
            cumulative: cumulative(series),
            prevCumulative: cumulative(prevSeries),
            stdDev: std,
            consistencyScore: consistency,
            activeBucketCount: activeBuckets,
            targetAttainmentPct: attainment
        )
    }

    private nonisolated static func flippedPrevAsCurrent(_ card: OpsTrendMetricCard) -> OpsTrendMetricCard {
        OpsTrendMetricCard(
            title: card.title,
            unit: card.unit,
            total: card.prevTotal,
            average: card.prevAverage,
            prevTotal: card.total,
            prevAverage: card.average,
            bestLabel: card.bestLabel,
            bestValue: card.bestValue,
            worstLabel: card.worstLabel,
            worstValue: card.worstValue,
            changePct: DashboardAggregations.pctChangeVsPrev(cur: card.prevAverage, prev: card.average),
            pace: .steady,
            series: card.prevSeries,
            prevSeries: card.series,
            labels: card.labels,
            cumulative: card.prevCumulative,
            prevCumulative: card.cumulative,
            stdDev: standardDeviation(card.prevSeries),
            consistencyScore: consistencyScore(
                series: card.prevSeries,
                average: card.prevAverage,
                stdDev: standardDeviation(card.prevSeries)
            ),
            activeBucketCount: card.prevSeries.filter { $0 > 0 }.count,
            targetAttainmentPct: card.targetAttainmentPct
        )
    }

    // MARK: - Scorecard

    private nonisolated static func buildScorecard(
        period: OpsTrendPeriod,
        trip: OpsTrendMetricCard,
        sand: OpsTrendMetricCard,
        activeDays: Int,
        totalDays: Int,
        streak: Int
    ) -> OpsTrendScorecard {
        let target = period.tripDailyTarget
        let tripVolume = min(100, Int(((trip.average / max(target, 1)) * 100).rounded()))
        let sandVolume = min(100, Int(min(100, sand.average * 2).rounded())) // ~50 rounds/day → 100
        let volumeScore = Int((Double(tripVolume) * 0.6 + Double(sandVolume) * 0.4).rounded())

        let growthScore = Int((Double(trip.growthScore) * 0.55 + Double(sand.growthScore) * 0.45).rounded())
        let consistencyScore = Int((Double(trip.consistencyScore) * 0.55 + Double(sand.consistencyScore) * 0.45).rounded())

        let coveragePct = totalDays > 0 ? Double(activeDays) / Double(totalDays) : 0
        let streakBonus = min(20, streak * 3)
        let coverageScore = Int(min(100, coveragePct * 80 + Double(streakBonus)).rounded())

        // Balance: prefer trip/sand ratio near 8–15 trips per sand round.
        let balanceScore: Int = {
            guard let r = ratioOrNil(trip: trip.average, sand: sand.average) else { return 50 }
            if r >= 8 && r <= 15 { return 95 }
            if r >= 5 && r <= 20 { return 75 }
            if r >= 3 && r <= 25 { return 55 }
            return 35
        }()

        let score = Int((
            Double(volumeScore) * 0.30
                + Double(growthScore) * 0.25
                + Double(consistencyScore) * 0.20
                + Double(coverageScore) * 0.15
                + Double(balanceScore) * 0.10
        ).rounded())
        let grade = OpsTrendGrade.from(score: score)

        let headline: String
        switch grade {
        case .aPlus, .a:
            headline = "\(period.shortLabel)นี้ผลงาน\(grade.label)"
        case .b:
            headline = "\(period.shortLabel)นี้เดินหน้าได้ดี"
        case .c:
            headline = "\(period.shortLabel)นี้ยังพอใช้ — มีจุดเร่ง"
        case .d:
            headline = "\(period.shortLabel)นี้ต้องเร่งจังหวะ"
        }

        let paceNote: String
        if trip.pace == .faster || sand.pace == .faster {
            paceNote = "จังหวะโดยรวมเร็วขึ้นเมื่อเทียบ\(period.shortLabel)ก่อน"
        } else if trip.pace == .slower || sand.pace == .slower {
            paceNote = "จังหวะชะลอ — โฟกัสวันที่มีงานต่ำ"
        } else {
            paceNote = "จังหวะค่อนข้างคงที่"
        }

        return OpsTrendScorecard(
            score: score,
            grade: grade,
            prevScore: 0,
            scoreDelta: 0,
            volumeScore: volumeScore,
            growthScore: growthScore,
            consistencyScore: consistencyScore,
            coverageScore: coverageScore,
            balanceScore: balanceScore,
            headline: headline,
            subheadline: paceNote
        )
    }

    private nonisolated static func dayBucketScore(point: OpsTrendPoint, target: Double) -> Int {
        let tripPart = min(100, (Double(point.tripRounds) / max(target, 1)) * 100)
        let sandPart = min(100, Double(point.sandRounds) * 2)
        let active = (point.tripRounds > 0 || point.sandRounds > 0) ? 15.0 : 0
        return Int(min(100, tripPart * 0.55 + sandPart * 0.30 + active).rounded())
    }

    private nonisolated static func weekBucketScore(point: OpsTrendPoint, target: Double) -> Int {
        let days = max(1, point.dayCount)
        let avgTrip = Double(point.tripRounds) / Double(days)
        let avgSand = Double(point.sandRounds) / Double(days)
        let tripPart = min(100, (avgTrip / max(target, 1)) * 100)
        let sandPart = min(100, avgSand * 2)
        return Int(min(100, tripPart * 0.6 + sandPart * 0.4).rounded())
    }

    // MARK: - Stats helpers

    private nonisolated static func cumulative(_ values: [Double]) -> [Double] {
        var sum = 0.0
        return values.map { v in
            sum += v
            return sum
        }
    }

    private nonisolated static func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let varSum = values.reduce(0.0) { $0 + pow($1 - mean, 2) }
        return sqrt(varSum / Double(values.count))
    }

    private nonisolated static func consistencyScore(series: [Double], average: Double, stdDev: Double) -> Int {
        guard average > 0 else { return series.allSatisfy({ $0 == 0 }) ? 40 : 20 }
        let cv = stdDev / average
        // Lower CV = steadier → higher score
        if cv <= 0.25 { return 95 }
        if cv <= 0.4 { return 80 }
        if cv <= 0.6 { return 65 }
        if cv <= 0.9 { return 45 }
        return 25
    }

    private nonisolated static func trailingActiveStreak(_ daily: [OpsTrendPoint]) -> Int {
        var streak = 0
        for p in daily.reversed() {
            if p.tripRounds > 0 || p.sandRounds > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    private nonisolated static func ratioOrNil(trip: Double, sand: Double) -> Double? {
        guard sand > 0.001 else { return nil }
        return trip / sand
    }

    private nonisolated static func classifyPace(changePct: Double?, cur: Double, prev: Double) -> OpsTrendPace {
        if prev == 0 && cur > 0 { return .newBaseline }
        if prev == 0 && cur == 0 { return .steady }
        guard let changePct else { return .steady }
        if changePct >= 8 { return .faster }
        if changePct <= -8 { return .slower }
        return .steady
    }

    private nonisolated static func weekdayShort(_ ymd: String) -> String? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        guard let d = DashboardAggregations.gregorian.date(from: comps) else { return nil }
        let names = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"]
        let w = DashboardAggregations.gregorian.component(.weekday, from: d) // 1=Sun
        guard w >= 1, w <= 7 else { return nil }
        return names[w - 1]
    }

    // MARK: - Insights

    private nonisolated static func buildInsights(
        period: OpsTrendPeriod,
        trip: OpsTrendMetricCard,
        sand: OpsTrendMetricCard,
        scorecard: OpsTrendScorecard,
        activeDays: Int,
        totalDays: Int,
        streak: Int,
        ratio: Double?
    ) -> [String] {
        var lines: [String] = []
        let scope = period.shortLabel

        lines.append("คะแนน\(scope) \(scorecard.score)/100 (\(scorecard.grade.rawValue) · \(scorecard.grade.label))")
        if scorecard.scoreDelta != 0 {
            let sign = scorecard.scoreDelta > 0 ? "+" : ""
            lines.append("เทียบ\(scope)ก่อน \(sign)\(scorecard.scoreDelta) คะแนน")
        }

        lines.append(insightLine(prefix: "เที่ยวรถ", card: trip, scope: scope))
        lines.append(insightLine(prefix: "ร่อนทราย", card: sand, scope: scope))

        if let attainment = trip.targetAttainmentPct {
            lines.append(String(format: "ถึงเป้าเที่ยวรถ %.0f%% ของ %.0f เที่ยว/วัน", attainment, period.tripDailyTarget))
        }

        if totalDays > 0 {
            let coverage = Int(round(Double(activeDays) / Double(totalDays) * 100))
            lines.append("วันทำงาน \(activeDays)/\(totalDays) (\(coverage)%) · สตรีคต่อเนื่อง \(streak) วัน")
        }

        if let ratio {
            lines.append(String(format: "อัตราเที่ยวรถต่อรอบร่อน ≈ %.1f เที่ยว/รอบ", ratio))
        }

        if trip.consistencyScore >= 80 {
            lines.append("เที่ยวรถค่อนข้างสม่ำเสมอ (ความนิ่ง \(trip.consistencyScore))")
        } else if trip.consistencyScore > 0, trip.consistencyScore < 50 {
            lines.append("เที่ยวรถผันผวนสูง — วันสูงสุด \(trip.bestLabel) vs ต่ำสุด \(trip.worstLabel)")
        }

        return lines
    }

    private nonisolated static func insightLine(prefix: String, card: OpsTrendMetricCard, scope: String) -> String {
        let avgText = formatCompact(card.average)
        switch card.pace {
        case .faster:
            let pct = Int((card.changePct ?? 0).rounded())
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · \(card.pace.label) \(pct)% vs \(scope)ก่อน"
        case .slower:
            let pct = Int(abs(card.changePct ?? 0).rounded())
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · \(card.pace.label) \(pct)% vs \(scope)ก่อน"
        case .steady:
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · จังหวะคงที่"
        case .newBaseline:
            return "\(prefix): เฉลี่ย \(avgText) \(card.unit)/วัน · เริ่มมีข้อมูลช่วงนี้"
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

    nonisolated static func formatSignedInt(_ value: Int) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(value)"
    }
}
