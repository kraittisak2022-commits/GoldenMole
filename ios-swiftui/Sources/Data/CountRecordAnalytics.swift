import Foundation

/// Port of web `countRecordAnalytics.ts` for Real-time V.4 pace analysis.
enum CountRecordAnalytics {
    static let lunchStartHour = 12
    static let lunchEndHour = 13
    static let workHoursTarget: Double = 8

    // MARK: - Models

    struct IntervalStats: Sendable {
        let avg: Double?
        let median: Double?
        let min: Double?
        let max: Double?
        let last: Double?
    }

    struct HourlyBucket: Identifiable, Sendable {
        var id: Int { hour }
        let hour: Int
        let count: Int
        let label: String
    }

    struct CumulativePoint: Identifiable, Sendable {
        var id: Double { timeMs }
        let label: String
        let value: Int
        let timeMs: Double
    }

    struct HourlyHeatmapCell: Identifiable, Sendable {
        var id: Int { hour }
        let hour: Int
        let count: Int
        let label: String
        let intensity: Double
        let isLunch: Bool
    }

    struct PeriodSplit: Sendable {
        let morning: Int
        let afternoon: Int
        let morningPct: Double
        let afternoonPct: Double
    }

    struct PeakHourInfo: Sendable {
        let hour: Int
        let count: Int
        let label: String
    }

    struct DayModeComparison: Sendable {
        let todayRounds: Int
        let yesterdayRounds: Int
        let roundsDeltaPct: Double?
        let todayAvgSec: Double?
        let yesterdayAvgSec: Double?
        let paceDeltaPct: Double?
        let hasYesterdayData: Bool
        let referenceDayKey: String?
        let isCalendarYesterday: Bool
        let priorLabel: String
    }

    struct SandTargetEta: Sendable {
        let rounds: Int
        let target: Int
        let remaining: Int
        let reached: Bool
        let progressPct: Double
        let etaClock: String?
        let hoursLeft: Double?
    }

    struct PaceConsistency: Sendable {
        let pctInBand: Double
        let medianSec: Double
        let sampleSize: Int
    }

    struct WorkDurationSummary: Sendable {
        let totalActiveHours: Double
        let lunchDeductedHours: Double
        let startClock: String?
        let endClock: String?
    }

    struct VehicleComparisonRow: Identifiable, Sendable {
        var id: String { vehicleId }
        let vehicleId: String
        let rounds: Int
        let morning: Int
        let afternoon: Int
    }

    struct ActivityEvent: Identifiable, Sendable {
        let id: String
        let kind: Kind
        let stamp: String
        let label: String
        let timeMs: Double

        enum Kind: String, Sendable {
            case trip
            case sand
        }
    }

    struct ModeAnalytics: Sendable {
        let mode: Mode
        let unitLabel: String
        let rounds: Int
        let lapTimes: [String]
        let intervals: [Double]
        let stats: IntervalStats
        let sparkline: [Double]
        let comparison: DayModeComparison
        let periodSplit: PeriodSplit
        let heatmap: [HourlyHeatmapCell]
        let peak: PeakHourInfo?
        let cumulative: [CumulativePoint]
        let hourly: [HourlyBucket]
        let workDuration: WorkDurationSummary?
        let vehicleComparison: [VehicleComparisonRow]
        let eta: SandTargetEta?
        let consistency: PaceConsistency?
        let minuteSpeed: [(label: String, count: Int)]

        enum Mode: String, Sendable {
            case trip
            case sand
        }
    }

    // MARK: - Core helpers

    static func isLunchHour(_ hour: Int) -> Bool {
        hour >= lunchStartHour && hour < lunchEndHour
    }

    static func activeDurationSec(startMs: Double, endMs: Double) -> Double {
        guard endMs > startMs else { return 0 }
        let lunch = CountRecordLogic.lunchOverlapSeconds(start: startMs, end: endMs)
        return max(0, (endMs - startMs) - lunch)
    }

    static func computeLapIntervals(lapTimes: [String], dayKey: String) -> [Double] {
        var intervals: [Double] = []
        guard lapTimes.count > 1 else { return intervals }
        for i in 1..<lapTimes.count {
            guard let prev = CountRecordLogic.parseLapStamp(lapTimes[i - 1], dayKey: dayKey),
                  let curr = CountRecordLogic.parseLapStamp(lapTimes[i], dayKey: dayKey)
            else { continue }
            let sec = activeDurationSec(startMs: prev, endMs: curr)
            if sec > 0 { intervals.append(sec) }
        }
        return intervals
    }

    static func computeIntervalStats(_ intervals: [Double]) -> IntervalStats {
        guard !intervals.isEmpty else {
            return IntervalStats(avg: nil, median: nil, min: nil, max: nil, last: nil)
        }
        let sorted = intervals.sorted()
        let sum = intervals.reduce(0, +)
        let mid = sorted.count / 2
        let median: Double = sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
        return IntervalStats(
            avg: sum / Double(intervals.count),
            median: median,
            min: sorted.first,
            max: sorted.last,
            last: intervals.last
        )
    }

    static func computeHourlyBuckets(lapTimes: [String], dayKey: String) -> [HourlyBucket] {
        var counts = Array(repeating: 0, count: 24)
        for lap in lapTimes {
            guard let ms = CountRecordLogic.parseLapStamp(lap, dayKey: dayKey) else { continue }
            let h = bangkokHour(ms)
            if h >= 0 && h < 24 && !isLunchHour(h) {
                counts[h] += 1
            }
        }
        return counts.enumerated().compactMap { hour, count in
            guard count > 0 else { return nil }
            return HourlyBucket(hour: hour, count: count, label: String(format: "%02d:00", hour))
        }
    }

    static func computeCumulativeSeries(lapTimes: [String], dayKey: String) -> [CumulativePoint] {
        var points: [CumulativePoint] = []
        for (i, lap) in lapTimes.enumerated() {
            guard let ms = CountRecordLogic.parseLapStamp(lap, dayKey: dayKey) else { continue }
            let h = bangkokHour(ms)
            let m = bangkokMinute(ms)
            points.append(
                CumulativePoint(
                    label: String(format: "%02d:%02d", h, m),
                    value: i + 1,
                    timeMs: ms
                )
            )
        }
        return points
    }

    static func computeHourlyHeatmap(lapTimes: [String], dayKey: String) -> [HourlyHeatmapCell] {
        var counts = Array(repeating: 0, count: 24)
        for lap in lapTimes {
            guard let ms = CountRecordLogic.parseLapStamp(lap, dayKey: dayKey) else { continue }
            let h = bangkokHour(ms)
            if h >= 0 && h < 24 && !isLunchHour(h) {
                counts[h] += 1
            }
        }
        let maxCount = max(counts.enumerated().filter { !isLunchHour($0.offset) }.map(\.element).max() ?? 1, 1)
        return (0..<24).map { hour in
            let lunch = isLunchHour(hour)
            let count = lunch ? 0 : counts[hour]
            return HourlyHeatmapCell(
                hour: hour,
                count: count,
                label: String(format: "%02d:00", hour),
                intensity: lunch ? 0 : Double(count) / Double(maxCount),
                isLunch: lunch
            )
        }
    }

    static func computePeakHour(_ cells: [HourlyHeatmapCell]) -> PeakHourInfo? {
        let active = cells.filter { $0.count > 0 && !$0.isLunch }
        guard let best = active.max(by: { $0.count < $1.count }) else { return nil }
        return PeakHourInfo(hour: best.hour, count: best.count, label: best.label)
    }

    static func periodSplit(morning: Int, afternoon: Int) -> PeriodSplit {
        let total = morning + afternoon
        return PeriodSplit(
            morning: morning,
            afternoon: afternoon,
            morningPct: total > 0 ? Double(morning) / Double(total) * 100 : 0,
            afternoonPct: total > 0 ? Double(afternoon) / Double(total) * 100 : 0
        )
    }

    static func computeWorkDuration(lapTimes: [String], dayKey: String) -> WorkDurationSummary? {
        let span = CountRecordLogic.computeWorkSpan(lapTimes: lapTimes, dayKey: dayKey)
        guard let startStamp = span.startStamp, let endStamp = span.endStamp,
              let startMs = CountRecordLogic.parseLapStamp(startStamp, dayKey: dayKey),
              let endMs = CountRecordLogic.parseLapStamp(endStamp, dayKey: dayKey)
        else { return nil }
        let rawSec = max(0, endMs - startMs)
        let activeSec = activeDurationSec(startMs: startMs, endMs: endMs)
        return WorkDurationSummary(
            totalActiveHours: activeSec / 3600,
            lunchDeductedHours: max(0, (rawSec - activeSec) / 3600),
            startClock: span.startClock,
            endClock: span.endClock
        )
    }

    static func computeSandTargetEta(lapTimes: [String], dayKey: String, target: Int = CountRecordLogic.sandTarget) -> SandTargetEta {
        let rounds = lapTimes.count
        let remaining = max(0, target - rounds)
        let progressPct = target > 0 ? min(Double(rounds) / Double(target) * 100, 100) : 0
        if remaining == 0 {
            return SandTargetEta(rounds: rounds, target: target, remaining: 0, reached: true, progressPct: progressPct, etaClock: nil, hoursLeft: 0)
        }
        let stats = computeIntervalStats(computeLapIntervals(lapTimes: lapTimes, dayKey: dayKey))
        guard let avg = stats.avg, avg > 0 else {
            return SandTargetEta(rounds: rounds, target: target, remaining: remaining, reached: false, progressPct: progressPct, etaClock: nil, hoursLeft: nil)
        }
        let span = CountRecordLogic.computeWorkSpan(lapTimes: lapTimes, dayKey: dayKey)
        guard let endStamp = span.endStamp,
              let lastMs = CountRecordLogic.parseLapStamp(endStamp, dayKey: dayKey)
        else {
            return SandTargetEta(rounds: rounds, target: target, remaining: remaining, reached: false, progressPct: progressPct, etaClock: nil, hoursLeft: nil)
        }
        let hoursLeft = (Double(remaining) * avg) / 3600
        let etaMs = lastMs + Double(remaining) * avg
        let h = bangkokHour(etaMs)
        let m = bangkokMinute(etaMs)
        return SandTargetEta(
            rounds: rounds,
            target: target,
            remaining: remaining,
            reached: false,
            progressPct: progressPct,
            etaClock: String(format: "%02d:%02d", h, m),
            hoursLeft: hoursLeft
        )
    }

    static func computePaceConsistency(_ intervals: [Double]) -> PaceConsistency? {
        guard intervals.count >= 3 else { return nil }
        let stats = computeIntervalStats(intervals)
        guard let median = stats.median, median > 0 else { return nil }
        let lo = median * 0.75
        let hi = median * 1.25
        let inBand = intervals.filter { $0 >= lo && $0 <= hi }.count
        return PaceConsistency(
            pctInBand: Double(inBand) / Double(intervals.count) * 100,
            medianSec: median,
            sampleSize: intervals.count
        )
    }

    static func computeMinuteSpeed(lapTimes: [String], dayKey: String) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for lap in lapTimes {
            guard let ms = CountRecordLogic.parseLapStamp(lap, dayKey: dayKey) else { continue }
            let h = bangkokHour(ms)
            if isLunchHour(h) { continue }
            let key = String(format: "%02d:%02d", h, bangkokMinute(ms))
            counts[key, default: 0] += 1
        }
        return counts.keys.sorted().map { (label: $0, count: counts[$0] ?? 0) }
    }

    static func findPriorDay(
        from dayKey: String,
        mode: ModeAnalytics.Mode,
        transactions: [Transaction],
        employees: [Employee]
    ) -> String? {
        for offset in 1...CountRecordLogic.priorDayLookback {
            let key = CountRecordLogic.addDays(to: dayKey, delta: -offset)
            switch mode {
            case .sand:
                if (CountRecordLogic.buildSandUnit(dayKey: key, transactions: transactions)?.rounds ?? 0) > 0 {
                    return key
                }
            case .trip:
                let trips = CountRecordLogic.buildTripUnits(dayKey: key, transactions: transactions, employees: employees)
                if trips.reduce(0, { $0 + $1.rounds }) > 0 { return key }
            }
        }
        return nil
    }

    static func comparisonDayLabel(dayKey: String?, focusDayKey: String) -> String {
        guard let dayKey else { return "" }
        let yesterday = CountRecordLogic.addDays(to: focusDayKey, delta: -1)
        if dayKey == yesterday { return "เมื่อวาน" }
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3 else { return dayKey }
        return "\(parts[2])/\(parts[1])"
    }

    static func formatPace(_ sec: Double?) -> String {
        guard let sec, sec.isFinite else { return "—" }
        if sec < 60 { return "\(Int(sec.rounded())) วิน." }
        let m = Int(sec) / 60
        let s = Int(sec.rounded()) % 60
        return s > 0 ? "\(m):\(String(format: "%02d", s)) นาที" : "\(m) นาที"
    }

    static func formatDurationHours(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0 ชม." }
        if hours < 1 { return "\(Int((hours * 60).rounded())) นาที" }
        return String(format: "%.1f ชม.", hours)
    }

    static func formatDeltaPct(_ pct: Double?) -> String {
        guard let pct, pct.isFinite else { return "—" }
        let abs = abs(Int(pct.rounded()))
        if abs < 1 { return "เท่าเดิม" }
        return pct >= 0 ? "+\(abs)%" : "−\(abs)%"
    }

    // MARK: - Build analytics packages

    static func buildTripAnalytics(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        tripUnits: [CountRecordTripUnit]? = nil
    ) -> ModeAnalytics {
        let units = tripUnits ?? CountRecordLogic.buildTripUnits(dayKey: dayKey, transactions: transactions, employees: employees)
        let lapTimes = units.flatMap(\.lapTimes).sorted { a, b in
            (CountRecordLogic.parseLapStamp(a, dayKey: dayKey) ?? 0) < (CountRecordLogic.parseLapStamp(b, dayKey: dayKey) ?? 0)
        }
        let rounds = units.reduce(0) { $0 + $1.rounds }
        let morning = units.reduce(0) { $0 + $1.morning }
        let afternoon = units.reduce(0) { $0 + $1.afternoon }
        let intervals = computeLapIntervals(lapTimes: lapTimes, dayKey: dayKey)
        let stats = computeIntervalStats(intervals)
        let heatmap = computeHourlyHeatmap(lapTimes: lapTimes, dayKey: dayKey)
        let ref = findPriorDay(from: dayKey, mode: .trip, transactions: transactions, employees: employees)
        let comparison = buildModeComparison(
            todayLaps: lapTimes,
            todayRounds: rounds,
            todayKey: dayKey,
            priorKey: ref,
            transactions: transactions,
            employees: employees,
            mode: .trip
        )
        let vehicleRows = units
            .filter { $0.rounds > 0 }
            .sorted { $0.rounds > $1.rounds }
            .map { VehicleComparisonRow(vehicleId: $0.vehicleId, rounds: $0.rounds, morning: $0.morning, afternoon: $0.afternoon) }

        return ModeAnalytics(
            mode: .trip,
            unitLabel: "เที่ยว",
            rounds: rounds,
            lapTimes: lapTimes,
            intervals: intervals,
            stats: stats,
            sparkline: Array(intervals.suffix(10)),
            comparison: comparison,
            periodSplit: periodSplit(morning: morning, afternoon: afternoon),
            heatmap: heatmap,
            peak: computePeakHour(heatmap),
            cumulative: computeCumulativeSeries(lapTimes: lapTimes, dayKey: dayKey),
            hourly: computeHourlyBuckets(lapTimes: lapTimes, dayKey: dayKey),
            workDuration: computeWorkDuration(lapTimes: lapTimes, dayKey: dayKey),
            vehicleComparison: vehicleRows,
            eta: nil,
            consistency: computePaceConsistency(intervals),
            minuteSpeed: []
        )
    }

    static func buildSandAnalytics(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        sandUnit: CountRecordSandUnit? = nil
    ) -> ModeAnalytics {
        let sand = sandUnit ?? CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: transactions)
        let lapTimes = sand?.lapTimes ?? []
        let rounds = sand?.rounds ?? 0
        let intervals = computeLapIntervals(lapTimes: lapTimes, dayKey: dayKey)
        let stats = computeIntervalStats(intervals)
        let heatmap = computeHourlyHeatmap(lapTimes: lapTimes, dayKey: dayKey)
        let ref = findPriorDay(from: dayKey, mode: .sand, transactions: transactions, employees: employees)
        let comparison = buildModeComparison(
            todayLaps: lapTimes,
            todayRounds: rounds,
            todayKey: dayKey,
            priorKey: ref,
            transactions: transactions,
            employees: employees,
            mode: .sand
        )

        return ModeAnalytics(
            mode: .sand,
            unitLabel: "รอบ",
            rounds: rounds,
            lapTimes: lapTimes,
            intervals: intervals,
            stats: stats,
            sparkline: Array(intervals.suffix(10)),
            comparison: comparison,
            periodSplit: periodSplit(morning: sand?.morning ?? 0, afternoon: sand?.afternoon ?? 0),
            heatmap: heatmap,
            peak: computePeakHour(heatmap),
            cumulative: computeCumulativeSeries(lapTimes: lapTimes, dayKey: dayKey),
            hourly: computeHourlyBuckets(lapTimes: lapTimes, dayKey: dayKey),
            workDuration: computeWorkDuration(lapTimes: lapTimes, dayKey: dayKey),
            vehicleComparison: [],
            eta: computeSandTargetEta(lapTimes: lapTimes, dayKey: dayKey),
            consistency: computePaceConsistency(intervals),
            minuteSpeed: computeMinuteSpeed(lapTimes: lapTimes, dayKey: dayKey)
        )
    }

    static func buildActivityFeed(
        dayKey: String,
        transactions: [Transaction] = [],
        employees: [Employee] = [],
        tripUnits: [CountRecordTripUnit]? = nil,
        sandUnit: CountRecordSandUnit? = nil,
        limit: Int = 20
    ) -> [ActivityEvent] {
        var events: [ActivityEvent] = []
        let trips = tripUnits ?? CountRecordLogic.buildTripUnits(dayKey: dayKey, transactions: transactions, employees: employees)
        for u in trips {
            for (i, stamp) in u.lapTimes.enumerated() {
                guard let ms = CountRecordLogic.parseLapStamp(stamp, dayKey: dayKey) else { continue }
                events.append(
                    ActivityEvent(
                        id: "trip-\(u.id)-\(i)",
                        kind: .trip,
                        stamp: stamp,
                        label: "\(u.vehicleId) · เที่ยวที่ \(i + 1)",
                        timeMs: ms
                    )
                )
            }
        }
        let sand = sandUnit ?? CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: transactions)
        if let sand {
            for (i, stamp) in sand.lapTimes.enumerated() {
                guard let ms = CountRecordLogic.parseLapStamp(stamp, dayKey: dayKey) else { continue }
                events.append(
                    ActivityEvent(
                        id: "sand-\(sand.id)-\(i)",
                        kind: .sand,
                        stamp: stamp,
                        label: "ร่อนทราย · รอบที่ \(i + 1)",
                        timeMs: ms
                    )
                )
            }
        }
        // Partial top-N: sort only when needed; keep memory bounded for live updates.
        if events.count <= limit {
            return events.sorted { $0.timeMs > $1.timeMs }
        }
        return events.sorted { $0.timeMs > $1.timeMs }.prefix(limit).map { $0 }
    }

    // MARK: - Private

    private static func buildModeComparison(
        todayLaps: [String],
        todayRounds: Int,
        todayKey: String,
        priorKey: String?,
        transactions: [Transaction],
        employees: [Employee],
        mode: ModeAnalytics.Mode
    ) -> DayModeComparison {
        let calendarYesterday = CountRecordLogic.addDays(to: todayKey, delta: -1)
        let refKey = priorKey
        let compareKey = refKey ?? calendarYesterday

        let priorLaps: [String]
        let priorRounds: Int
        switch mode {
        case .trip:
            let units = CountRecordLogic.buildTripUnits(dayKey: compareKey, transactions: transactions, employees: employees)
            priorLaps = units.flatMap(\.lapTimes)
            priorRounds = units.reduce(0) { $0 + $1.rounds }
        case .sand:
            let sand = CountRecordLogic.buildSandUnit(dayKey: compareKey, transactions: transactions)
            priorLaps = sand?.lapTimes ?? []
            priorRounds = sand?.rounds ?? 0
        }

        let todayStats = computeIntervalStats(computeLapIntervals(lapTimes: todayLaps, dayKey: todayKey))
        let priorStats = computeIntervalStats(computeLapIntervals(lapTimes: priorLaps, dayKey: compareKey))
        let hasData = priorRounds > 0 && refKey != nil

        let roundsDelta: Double? = priorRounds > 0
            ? (Double(todayRounds - priorRounds) / Double(priorRounds)) * 100
            : nil
        let paceDelta: Double? = {
            guard let t = todayStats.avg, let y = priorStats.avg, y > 0 else { return nil }
            return ((t - y) / y) * 100
        }()

        return DayModeComparison(
            todayRounds: todayRounds,
            yesterdayRounds: priorRounds,
            roundsDeltaPct: roundsDelta,
            todayAvgSec: todayStats.avg,
            yesterdayAvgSec: priorStats.avg,
            paceDeltaPct: paceDelta,
            hasYesterdayData: hasData,
            referenceDayKey: hasData ? refKey : nil,
            isCalendarYesterday: hasData && refKey == calendarYesterday,
            priorLabel: comparisonDayLabel(dayKey: hasData ? refKey : nil, focusDayKey: todayKey)
        )
    }

    private static func bangkokCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok")
            ?? TimeZone(secondsFromGMT: Int(CountRecordLogic.bangkokOffsetMs))!
        return cal
    }

    private static func bangkokHour(_ ms: Double) -> Int {
        bangkokCalendar().component(.hour, from: Date(timeIntervalSince1970: ms))
    }

    private static func bangkokMinute(_ ms: Double) -> Int {
        bangkokCalendar().component(.minute, from: Date(timeIntervalSince1970: ms))
    }
}
