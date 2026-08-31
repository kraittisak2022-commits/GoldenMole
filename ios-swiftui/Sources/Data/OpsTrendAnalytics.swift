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
    var tripDailyTarget: Double { 200 }
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

/// Per-bucket pace/volume sample derived from lap timestamps.
struct OpsTrendPacePoint: Identifiable, Sendable {
    let id: String
    let label: String
    let startKey: String
    let endKey: String
    let dayCount: Int
    let tripRounds: Int
    let sandRounds: Int
    let tripCubic: Double
    let sandCubic: Double
    let tripAvgIntervalSec: Double?
    let sandAvgIntervalSec: Double?
    let tripPerHour: Double
    let sandPerHour: Double
    let tripActiveHours: Double
    let sandActiveHours: Double
    let tripIntervalSamples: Int
    let sandIntervalSamples: Int
    let tripPeakHourLabel: String?
    let sandPeakHourLabel: String?
}

/// Advanced speed + volume package for one mode (trip or sand).
struct OpsTrendAdvancedMode: Sendable {
    let title: String
    let unit: String
    let volumeTotal: Double
    let volumeAvgPerDay: Double
    let volumePeak: Double
    let volumePeakLabel: String
    let volumeChangePct: Double?
    let cubicTotal: Double
    let avgIntervalSec: Double?
    let prevAvgIntervalSec: Double?
    /// Positive = faster (interval shorter). Derived from interval change.
    let speedChangePct: Double?
    let throughputPerHour: Double
    let prevThroughputPerHour: Double
    let throughputChangePct: Double?
    let activeHoursTotal: Double
    let speedScore: Int
    let volumeScore: Int
    let combinedScore: Int
    let pace: OpsTrendPace
    let peakHourLabel: String?
    let seriesLabels: [String]
    let intervalSeries: [Double]
    let throughputSeries: [Double]
    let volumeSeries: [Double]
    let insights: [String]

    static let emptyTrip = OpsTrendAdvancedMode(
        title: "เที่ยวรถ",
        unit: "เที่ยว",
        volumeTotal: 0,
        volumeAvgPerDay: 0,
        volumePeak: 0,
        volumePeakLabel: "—",
        volumeChangePct: nil,
        cubicTotal: 0,
        avgIntervalSec: nil,
        prevAvgIntervalSec: nil,
        speedChangePct: nil,
        throughputPerHour: 0,
        prevThroughputPerHour: 0,
        throughputChangePct: nil,
        activeHoursTotal: 0,
        speedScore: 0,
        volumeScore: 0,
        combinedScore: 0,
        pace: .newBaseline,
        peakHourLabel: nil,
        seriesLabels: [],
        intervalSeries: [],
        throughputSeries: [],
        volumeSeries: [],
        insights: []
    )

    static let emptySand = OpsTrendAdvancedMode(
        title: "ร่อนทราย",
        unit: "รอบ",
        volumeTotal: 0,
        volumeAvgPerDay: 0,
        volumePeak: 0,
        volumePeakLabel: "—",
        volumeChangePct: nil,
        cubicTotal: 0,
        avgIntervalSec: nil,
        prevAvgIntervalSec: nil,
        speedChangePct: nil,
        throughputPerHour: 0,
        prevThroughputPerHour: 0,
        throughputChangePct: nil,
        activeHoursTotal: 0,
        speedScore: 0,
        volumeScore: 0,
        combinedScore: 0,
        pace: .newBaseline,
        peakHourLabel: nil,
        seriesLabels: [],
        intervalSeries: [],
        throughputSeries: [],
        volumeSeries: [],
        insights: []
    )
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
    let tripAdvanced: OpsTrendAdvancedMode
    let sandAdvanced: OpsTrendAdvancedMode
    let pacePoints: [OpsTrendPacePoint]
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
            tripAdvanced: .emptyTrip,
            sandAdvanced: .emptySand,
            pacePoints: [],
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

        let dailyPace = dayKeys.map {
            dayPace(dayKey: $0, byDay: byDay, transactions: transactions, employees: employees)
        }
        let prevDailyPace = prevKeys.map {
            dayPace(dayKey: $0, byDay: byDay, transactions: transactions, employees: employees)
        }
        let pacePoints: [OpsTrendPacePoint]
        let prevPacePoints: [OpsTrendPacePoint]
        switch period {
        case .week:
            pacePoints = dailyPace
            prevPacePoints = alignPaceSeries(prevDailyPace, toCount: dailyPace.count)
        case .month:
            let buckets = bucketPaceWeekly(dailyPace)
            pacePoints = buckets
            prevPacePoints = alignPaceSeries(bucketPaceWeekly(prevDailyPace), toCount: buckets.count)
        }

        let tripAdvanced = buildAdvancedMode(
            title: "เที่ยวรถ",
            unit: "เที่ยว",
            period: period,
            points: pacePoints,
            prevPoints: prevPacePoints,
            rounds: \.tripRounds,
            cubic: \.tripCubic,
            interval: \.tripAvgIntervalSec,
            perHour: \.tripPerHour,
            activeHours: \.tripActiveHours,
            samples: \.tripIntervalSamples,
            peak: \.tripPeakHourLabel,
            idealIntervalSec: 150,
            volumeDailyTarget: period.tripDailyTarget
        )
        let sandAdvanced = buildAdvancedMode(
            title: "ร่อนทราย",
            unit: "รอบ",
            period: period,
            points: pacePoints,
            prevPoints: prevPacePoints,
            rounds: \.sandRounds,
            cubic: \.sandCubic,
            interval: \.sandAvgIntervalSec,
            perHour: \.sandPerHour,
            activeHours: \.sandActiveHours,
            samples: \.sandIntervalSamples,
            peak: \.sandPeakHourLabel,
            idealIntervalSec: 240,
            volumeDailyTarget: 40
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
            tripAdvanced: tripAdvanced,
            sandAdvanced: sandAdvanced,
            pacePoints: pacePoints,
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

    nonisolated static func formatIntervalSec(_ sec: Double?) -> String {
        CountRecordAnalytics.formatPace(sec)
    }

    nonisolated static func formatPerHour(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return String(format: "%.1f/ชม.", v)
    }

    // MARK: - Advanced speed / volume

    private nonisolated static func dayPace(
        dayKey: String,
        byDay: [String: [Transaction]],
        transactions: [Transaction],
        employees: [Employee]
    ) -> OpsTrendPacePoint {
        let dayTx = byDay[dayKey] ?? transactions.filter { String($0.date.prefix(10)) == dayKey }
        let tripUnits = CountRecordLogic.buildTripUnits(dayKey: dayKey, transactions: dayTx, employees: employees)
        let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx)
        let tripLaps = tripUnits.flatMap(\.lapTimes)
        let sandLaps = sand?.lapTimes ?? []
        let tripRounds = tripUnits.reduce(0) { $0 + $1.rounds }
        let sandRounds = sand?.rounds ?? 0

        let tripIntervals = CountRecordAnalytics.computeLapIntervals(lapTimes: tripLaps, dayKey: dayKey)
        let sandIntervals = CountRecordAnalytics.computeLapIntervals(lapTimes: sandLaps, dayKey: dayKey)
        let tripStats = CountRecordAnalytics.computeIntervalStats(tripIntervals)
        let sandStats = CountRecordAnalytics.computeIntervalStats(sandIntervals)
        let tripDur = CountRecordAnalytics.computeWorkDuration(lapTimes: tripLaps, dayKey: dayKey)
        let sandDur = CountRecordAnalytics.computeWorkDuration(lapTimes: sandLaps, dayKey: dayKey)
        let tripHours = tripDur?.totalActiveHours ?? 0
        let sandHours = sandDur?.totalActiveHours ?? 0
        let tripPeak = CountRecordAnalytics.computePeakHour(
            CountRecordAnalytics.computeHourlyHeatmap(lapTimes: tripLaps, dayKey: dayKey)
        )
        let sandPeak = CountRecordAnalytics.computePeakHour(
            CountRecordAnalytics.computeHourlyHeatmap(lapTimes: sandLaps, dayKey: dayKey)
        )
        let tripCubic = dayTx
            .filter { CountRecordLogic.isCountRecordVehicleRow($0) }
            .reduce(0.0) { $0 + ($1.totalCubic ?? $1.perCarCubic ?? 0) }
        let sandCubic = dayTx
            .filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
            .reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }

        return OpsTrendPacePoint(
            id: dayKey,
            label: DashboardAggregations.dayLabel(dayKey),
            startKey: dayKey,
            endKey: dayKey,
            dayCount: 1,
            tripRounds: tripRounds,
            sandRounds: sandRounds,
            tripCubic: tripCubic,
            sandCubic: sandCubic,
            tripAvgIntervalSec: tripStats.avg,
            sandAvgIntervalSec: sandStats.avg,
            tripPerHour: tripHours > 0 ? Double(tripRounds) / tripHours : 0,
            sandPerHour: sandHours > 0 ? Double(sandRounds) / sandHours : 0,
            tripActiveHours: tripHours,
            sandActiveHours: sandHours,
            tripIntervalSamples: tripIntervals.count,
            sandIntervalSamples: sandIntervals.count,
            tripPeakHourLabel: tripPeak?.label,
            sandPeakHourLabel: sandPeak?.label
        )
    }

    private nonisolated static func bucketPaceWeekly(_ daily: [OpsTrendPacePoint]) -> [OpsTrendPacePoint] {
        guard !daily.isEmpty else { return [] }
        var out: [OpsTrendPacePoint] = []
        var i = 0
        var week = 1
        while i < daily.count {
            let end = min(i + 7, daily.count)
            let slice = Array(daily[i..<end])
            out.append(mergePacePoints(slice, id: "pw\(week)-\(slice.first!.startKey)", label: "W\(week)"))
            week += 1
            i = end
        }
        return out
    }

    private nonisolated static func mergePacePoints(_ slice: [OpsTrendPacePoint], id: String, label: String) -> OpsTrendPacePoint {
        let tripRounds = slice.reduce(0) { $0 + $1.tripRounds }
        let sandRounds = slice.reduce(0) { $0 + $1.sandRounds }
        let tripHours = slice.reduce(0.0) { $0 + $1.tripActiveHours }
        let sandHours = slice.reduce(0.0) { $0 + $1.sandActiveHours }
        let tripSamples = slice.reduce(0) { $0 + $1.tripIntervalSamples }
        let sandSamples = slice.reduce(0) { $0 + $1.sandIntervalSamples }

        func weightedInterval(_ keyPath: KeyPath<OpsTrendPacePoint, Double?>, samples: KeyPath<OpsTrendPacePoint, Int>) -> Double? {
            var sum = 0.0
            var n = 0
            for p in slice {
                guard let v = p[keyPath: keyPath], p[keyPath: samples] > 0 else { continue }
                sum += v * Double(p[keyPath: samples])
                n += p[keyPath: samples]
            }
            return n > 0 ? sum / Double(n) : nil
        }

        let peakTrip = slice.max(by: { $0.tripRounds < $1.tripRounds })?.tripPeakHourLabel
        let peakSand = slice.max(by: { $0.sandRounds < $1.sandRounds })?.sandPeakHourLabel

        return OpsTrendPacePoint(
            id: id,
            label: label,
            startKey: slice.first!.startKey,
            endKey: slice.last!.endKey,
            dayCount: slice.reduce(0) { $0 + $1.dayCount },
            tripRounds: tripRounds,
            sandRounds: sandRounds,
            tripCubic: slice.reduce(0) { $0 + $1.tripCubic },
            sandCubic: slice.reduce(0) { $0 + $1.sandCubic },
            tripAvgIntervalSec: weightedInterval(\.tripAvgIntervalSec, samples: \.tripIntervalSamples),
            sandAvgIntervalSec: weightedInterval(\.sandAvgIntervalSec, samples: \.sandIntervalSamples),
            tripPerHour: tripHours > 0 ? Double(tripRounds) / tripHours : 0,
            sandPerHour: sandHours > 0 ? Double(sandRounds) / sandHours : 0,
            tripActiveHours: tripHours,
            sandActiveHours: sandHours,
            tripIntervalSamples: tripSamples,
            sandIntervalSamples: sandSamples,
            tripPeakHourLabel: peakTrip,
            sandPeakHourLabel: peakSand
        )
    }

    private nonisolated static func alignPaceSeries(_ points: [OpsTrendPacePoint], toCount count: Int) -> [OpsTrendPacePoint] {
        if points.count == count { return points }
        if points.count > count { return Array(points.suffix(count)) }
        let pad = count - points.count
        let blanks: [OpsTrendPacePoint] = (0..<pad).map { idx in
            OpsTrendPacePoint(
                id: "ppad-\(idx)",
                label: "—",
                startKey: "",
                endKey: "",
                dayCount: 1,
                tripRounds: 0,
                sandRounds: 0,
                tripCubic: 0,
                sandCubic: 0,
                tripAvgIntervalSec: nil,
                sandAvgIntervalSec: nil,
                tripPerHour: 0,
                sandPerHour: 0,
                tripActiveHours: 0,
                sandActiveHours: 0,
                tripIntervalSamples: 0,
                sandIntervalSamples: 0,
                tripPeakHourLabel: nil,
                sandPeakHourLabel: nil
            )
        }
        return blanks + points
    }

    private nonisolated static func buildAdvancedMode(
        title: String,
        unit: String,
        period: OpsTrendPeriod,
        points: [OpsTrendPacePoint],
        prevPoints: [OpsTrendPacePoint],
        rounds: KeyPath<OpsTrendPacePoint, Int>,
        cubic: KeyPath<OpsTrendPacePoint, Double>,
        interval: KeyPath<OpsTrendPacePoint, Double?>,
        perHour: KeyPath<OpsTrendPacePoint, Double>,
        activeHours: KeyPath<OpsTrendPacePoint, Double>,
        samples: KeyPath<OpsTrendPacePoint, Int>,
        peak: KeyPath<OpsTrendPacePoint, String?>,
        idealIntervalSec: Double,
        volumeDailyTarget: Double
    ) -> OpsTrendAdvancedMode {
        let labels = points.map(\.label)
        let volumeSeries = points.map { Double($0[keyPath: rounds]) }
        let throughputSeries = points.map { $0[keyPath: perHour] }
        let intervalSeries = points.map { $0[keyPath: interval] ?? 0 }

        let volumeTotal = volumeSeries.reduce(0, +)
        let days = max(1, points.reduce(0) { $0 + $1.dayCount })
        let prevDays = max(1, prevPoints.reduce(0) { $0 + $1.dayCount })
        let volumeAvg = volumeTotal / Double(days)
        let prevVolume = prevPoints.reduce(0.0) { $0 + Double($1[keyPath: rounds]) }
        let prevVolumeAvg = prevVolume / Double(prevDays)
        let volumeChange = DashboardAggregations.pctChangeVsPrev(cur: volumeAvg, prev: prevVolumeAvg)

        var peakVal = 0.0
        var peakLabel = "—"
        for p in points {
            let v = Double(p[keyPath: rounds])
            if v >= peakVal {
                peakVal = v
                peakLabel = p.label
            }
        }

        func weightedAvgInterval(_ list: [OpsTrendPacePoint]) -> Double? {
            var sum = 0.0
            var n = 0
            for p in list {
                guard let v = p[keyPath: interval], p[keyPath: samples] > 0 else { continue }
                sum += v * Double(p[keyPath: samples])
                n += p[keyPath: samples]
            }
            return n > 0 ? sum / Double(n) : nil
        }

        let avgInterval = weightedAvgInterval(points)
        let prevInterval = weightedAvgInterval(prevPoints)
        // Shorter interval = faster → invert sign of pct change on interval
        let speedChange: Double? = {
            guard let avgInterval, let prevInterval, prevInterval > 0 else { return nil }
            return ((prevInterval - avgInterval) / prevInterval) * 100
        }()

        let hours = points.reduce(0.0) { $0 + $1[keyPath: activeHours] }
        let prevHours = prevPoints.reduce(0.0) { $0 + $1[keyPath: activeHours] }
        let throughput = hours > 0 ? volumeTotal / hours : 0
        let prevThroughput = prevHours > 0 ? prevVolume / prevHours : 0
        let throughputChange = DashboardAggregations.pctChangeVsPrev(cur: throughput, prev: prevThroughput)

        let cubicTotal = points.reduce(0.0) { $0 + $1[keyPath: cubic] }
        let peakHour = points.max(by: { $0[keyPath: rounds] < $1[keyPath: rounds] })?[keyPath: peak]

        let speedScore: Int = {
            guard let avgInterval, avgInterval > 0 else { return 40 }
            let ratio = idealIntervalSec / avgInterval
            return Int(min(100, max(10, ratio * 70)).rounded())
        }()
        let volumeScore = Int(min(100, (volumeAvg / max(volumeDailyTarget, 1)) * 100).rounded())
        let combined = Int((Double(speedScore) * 0.45 + Double(volumeScore) * 0.55).rounded())

        let pace: OpsTrendPace = {
            if prevVolumeAvg == 0 && volumeAvg > 0 { return .newBaseline }
            if let speedChange {
                if speedChange >= 8 { return .faster }
                if speedChange <= -8 { return .slower }
            }
            if let volumeChange {
                if volumeChange >= 8 { return .faster }
                if volumeChange <= -8 { return .slower }
            }
            return .steady
        }()

        var insights: [String] = []
        insights.append("ปริมาณเฉลี่ย \(formatCompact(volumeAvg)) \(unit)/วัน (\(formatSignedPct(volumeChange)) vs \(period.shortLabel)ก่อน)")
        if let avgInterval {
            insights.append("จังหวะเฉลี่ย \(formatIntervalSec(avgInterval)) · \(formatSignedPct(speedChange)) ความเร็ว")
        }
        if throughput > 0 {
            insights.append("อัตราผลิต \(formatPerHour(throughput)) (\(formatSignedPct(throughputChange)) vs \(period.shortLabel)ก่อน)")
        }
        if hours > 0 {
            insights.append("ชั่วโมงทำงานรวม \(CountRecordAnalytics.formatDurationHours(hours))")
        }
        if let peakHour, !peakHour.isEmpty {
            insights.append("ชั่วโมงพีคโดยรวม \(peakHour)")
        }
        if cubicTotal > 0 {
            insights.append("คิวรวม \(formatCompact(cubicTotal)) คิว")
        }
        insights.append("คะแนนความเร็ว \(speedScore) · ปริมาณ \(volumeScore) · รวมขั้นสูง \(combined)")

        return OpsTrendAdvancedMode(
            title: title,
            unit: unit,
            volumeTotal: volumeTotal,
            volumeAvgPerDay: volumeAvg,
            volumePeak: peakVal,
            volumePeakLabel: peakLabel,
            volumeChangePct: volumeChange,
            cubicTotal: cubicTotal,
            avgIntervalSec: avgInterval,
            prevAvgIntervalSec: prevInterval,
            speedChangePct: speedChange,
            throughputPerHour: throughput,
            prevThroughputPerHour: prevThroughput,
            throughputChangePct: throughputChange,
            activeHoursTotal: hours,
            speedScore: speedScore,
            volumeScore: volumeScore,
            combinedScore: combined,
            pace: pace,
            peakHourLabel: peakHour,
            seriesLabels: labels,
            intervalSeries: intervalSeries,
            throughputSeries: throughputSeries,
            volumeSeries: volumeSeries,
            insights: insights
        )
    }
}
