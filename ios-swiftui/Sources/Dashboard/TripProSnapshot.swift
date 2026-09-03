import Foundation

/// Pro command-center metrics for the Real-time เที่ยวรถ tab.
struct TripProSnapshot: Sendable {
    enum PaceHealth: String, Sendable {
        case steady
        case moderate
        case uneven
        case unknown

        var label: String {
            switch self {
            case .steady: return "จังหวะนิ่ง"
            case .moderate: return "จังหวะปานกลาง"
            case .uneven: return "จังหวะสะดุด"
            case .unknown: return "รอข้อมูลจังหวะ"
            }
        }

        var systemImage: String {
            switch self {
            case .steady: return "checkmark.seal.fill"
            case .moderate: return "gauge.with.dots.needle.33percent"
            case .uneven: return "exclamationmark.triangle.fill"
            case .unknown: return "ellipsis.circle"
            }
        }
    }

    enum BalanceSide: String, Sendable {
        case sandAhead
        case tripAhead
        case balanced
        case none
    }

    struct LeaderRow: Identifiable, Sendable {
        let id: String
        let rank: Int
        let vehicleId: String
        let driverLabel: String
        let rounds: Int
        let sharePct: Double
    }

    struct IdleVehicle: Identifiable, Sendable {
        let id: String
        let vehicleId: String
        let driverLabel: String
        let rounds: Int
        /// Minutes since last lap (nil = never lapped today / unknown).
        let idleMinutes: Int?
        let reason: String
    }

    let dayKey: String
    let rounds: Int
    let vehicleCount: Int
    let target: Int
    let progressPct: Double
    let remaining: Int
    let reached: Bool
    let etaClock: String?
    let hoursLeft: Double?
    let perHour: Double?
    let queueCubic: Int

    let priorLabel: String
    let roundsVsPriorPct: Double?
    let paceVsPriorPct: Double?
    let roundsAvg7: Double
    let roundsVsAvg7Pct: Double?

    let paceHealth: PaceHealth
    let consistencyPct: Double?
    let sparkline: [Double]
    let peakHourLabel: String?
    let peakHourCount: Int?

    let efficiencyPerVeh: Double
    let efficiencyDeltaPct: Double?
    let efficiencyPriorLabel: String
    let efficiencyIsCalendarYesterday: Bool

    let leaders: [LeaderRow]
    let idleVehicles: [IdleVehicle]

    let sandRounds: Int
    let tripQueueCubic: Int
    let balance: BalanceSide
    let balanceDelta: Int

    let insights: [String]
    let ctaTitle: String?

    var hasTripData: Bool { rounds > 0 }

    /// Idle alert threshold in minutes (active vehicles only).
    static let idleThresholdMinutes = 30

    static let empty = TripProSnapshot(
        dayKey: "",
        rounds: 0,
        vehicleCount: 0,
        target: CountRecordLogic.tripTarget,
        progressPct: 0,
        remaining: CountRecordLogic.tripTarget,
        reached: false,
        etaClock: nil,
        hoursLeft: nil,
        perHour: nil,
        queueCubic: 0,
        priorLabel: "วันก่อน",
        roundsVsPriorPct: nil,
        paceVsPriorPct: nil,
        roundsAvg7: 0,
        roundsVsAvg7Pct: nil,
        paceHealth: .unknown,
        consistencyPct: nil,
        sparkline: [],
        peakHourLabel: nil,
        peakHourCount: nil,
        efficiencyPerVeh: 0,
        efficiencyDeltaPct: nil,
        efficiencyPriorLabel: "",
        efficiencyIsCalendarYesterday: false,
        leaders: [],
        idleVehicles: [],
        sandRounds: 0,
        tripQueueCubic: 0,
        balance: .none,
        balanceDelta: 0,
        insights: [],
        ctaTitle: nil
    )

    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        tripUnits: [CountRecordTripUnit],
        tripAnalytics: CountRecordAnalytics.ModeAnalytics,
        efficiency: VehicleEfficiency,
        sandRounds: Int,
        tripHours: Double?,
        byDay: [String: [Transaction]]? = nil,
        now: Date = Date()
    ) -> TripProSnapshot {
        guard !dayKey.isEmpty else { return .empty }

        let dayIndex = byDay ?? Dictionary(grouping: transactions) { String($0.date.prefix(10)) }
        let rounds = tripUnits.reduce(0) { $0 + $1.rounds }
        let target = CountRecordLogic.tripTarget
        let remaining = max(0, target - rounds)
        let progress = target > 0 ? min(Double(rounds) / Double(target) * 100, 100) : 0
        let eta = tripAnalytics.eta
            ?? CountRecordAnalytics.computeTripTargetEta(
                tripUnits: tripUnits,
                dayKey: dayKey,
                target: target
            )
        let hours = tripHours ?? tripAnalytics.workDuration?.totalActiveHours
        let perHour = hours.flatMap { $0 > 0 ? Double(rounds) / $0 : nil }
        let queueCubic = rounds * CountRecordLogic.queuePerTrip

        let comparison = tripAnalytics.comparison
        let priorLabel = comparison.priorLabel.isEmpty
            ? (comparison.isCalendarYesterday ? "เมื่อวาน" : "วันก่อน")
            : comparison.priorLabel

        var avgSum = 0.0
        for i in 1...7 {
            let key = DashboardAggregations.shiftDateStr(dayKey, deltaDays: -i)
            let tx = dayIndex[key] ?? []
            let dayUnits = CountRecordLogic.buildTripUnits(
                dayKey: key,
                transactions: tx,
                employees: employees
            )
            avgSum += Double(dayUnits.reduce(0) { $0 + $1.rounds })
        }
        let avg7 = avgSum / 7.0
        let vsAvg7 = DashboardAggregations.pctChangeVsPrev(cur: Double(rounds), prev: avg7)

        let consistency = tripAnalytics.consistency
        let paceHealth: PaceHealth
        if let c = consistency {
            if c.pctInBand >= 70 { paceHealth = .steady }
            else if c.pctInBand >= 45 { paceHealth = .moderate }
            else { paceHealth = .uneven }
        } else if rounds > 0 {
            paceHealth = .moderate
        } else {
            paceHealth = .unknown
        }

        let tripQueue = queueCubic
        let balanceDelta = sandRounds - tripQueue
        let balance: BalanceSide
        if sandRounds == 0 && tripQueue == 0 {
            balance = .none
        } else if abs(balanceDelta) <= max(20, Int(Double(max(sandRounds, tripQueue)) * 0.08)) {
            balance = .balanced
        } else if balanceDelta > 0 {
            balance = .sandAhead
        } else {
            balance = .tripAhead
        }

        let leaders: [LeaderRow] = Array(
            tripUnits
                .filter { $0.rounds > 0 }
                .sorted { $0.rounds > $1.rounds }
                .prefix(3)
                .enumerated()
        ).map { index, unit in
            LeaderRow(
                id: unit.id,
                rank: index + 1,
                vehicleId: unit.vehicleId,
                driverLabel: unit.driverLabel,
                rounds: unit.rounds,
                sharePct: rounds > 0 ? Double(unit.rounds) / Double(rounds) * 100 : 0
            )
        }

        let idleVehicles = buildIdleVehicles(
            dayKey: dayKey,
            tripUnits: tripUnits,
            fleetHasActivity: rounds > 0,
            now: now
        )

        let peak = tripAnalytics.peak
        let insights = buildInsights(
            rounds: rounds,
            target: target,
            reached: eta.reached || rounds >= target,
            vehicleCount: tripUnits.filter { $0.rounds > 0 }.count,
            roundsVsPrior: comparison.roundsDeltaPct,
            paceVsPrior: comparison.paceDeltaPct,
            priorLabel: priorLabel,
            vsAvg7: vsAvg7,
            paceHealth: paceHealth,
            efficiencyDelta: efficiency.deltaPct,
            efficiencyPriorLabel: efficiency.priorLabel.isEmpty ? priorLabel : efficiency.priorLabel,
            leaders: leaders,
            idleCount: idleVehicles.count,
            balance: balance,
            balanceDelta: balanceDelta,
            etaClock: eta.etaClock,
            peakLabel: peak?.label,
            consistencyPct: consistency?.pctInBand
        )

        let cta: String?
        if rounds == 0 {
            cta = "เริ่มนับเที่ยวรถ"
        } else if !eta.reached, rounds < target {
            if let topIdle = idleVehicles.first {
                cta = "ไล่\(topIdle.vehicleId) · นับเที่ยวต่อ"
            } else if let clock = eta.etaClock {
                cta = "เร่งจังหวะ · เป้า ~\(clock)"
            } else if paceHealth == .uneven {
                cta = "จังหวะสะดุด · เปิดนับต่อ"
            } else {
                cta = "นับเที่ยวต่อ · เหลือ \(CountRecordLogic.formatMetric(remaining)) เที่ยว"
            }
        } else {
            cta = nil
        }

        return TripProSnapshot(
            dayKey: dayKey,
            rounds: rounds,
            vehicleCount: tripUnits.filter { $0.rounds > 0 }.count,
            target: target,
            progressPct: progress,
            remaining: remaining,
            reached: eta.reached || rounds >= target,
            etaClock: eta.etaClock,
            hoursLeft: eta.hoursLeft,
            perHour: perHour,
            queueCubic: queueCubic,
            priorLabel: priorLabel,
            roundsVsPriorPct: comparison.roundsDeltaPct,
            paceVsPriorPct: comparison.paceDeltaPct,
            roundsAvg7: avg7,
            roundsVsAvg7Pct: vsAvg7,
            paceHealth: paceHealth,
            consistencyPct: consistency?.pctInBand,
            sparkline: tripAnalytics.sparkline,
            peakHourLabel: peak?.label,
            peakHourCount: peak?.count,
            efficiencyPerVeh: efficiency.perVehToday,
            efficiencyDeltaPct: efficiency.deltaPct,
            efficiencyPriorLabel: efficiency.priorLabel,
            efficiencyIsCalendarYesterday: efficiency.isCalendarYesterday,
            leaders: leaders,
            idleVehicles: idleVehicles,
            sandRounds: sandRounds,
            tripQueueCubic: tripQueue,
            balance: balance,
            balanceDelta: balanceDelta,
            insights: insights,
            ctaTitle: cta
        )
    }

    private nonisolated static func buildIdleVehicles(
        dayKey: String,
        tripUnits: [CountRecordTripUnit],
        fleetHasActivity: Bool,
        now: Date
    ) -> [IdleVehicle] {
        guard fleetHasActivity else { return [] }
        let today = DashboardAggregations.todayYMD()
        let isFocusToday = dayKey == today
        let nowMs = now.timeIntervalSince1970 * 1000

        var out: [IdleVehicle] = []
        for unit in tripUnits {
            if unit.rounds == 0 {
                out.append(
                    IdleVehicle(
                        id: unit.id,
                        vehicleId: unit.vehicleId,
                        driverLabel: unit.driverLabel,
                        rounds: 0,
                        idleMinutes: nil,
                        reason: "ยังไม่มีเที่ยว"
                    )
                )
                continue
            }
            guard isFocusToday else { continue }
            guard let last = unit.lapTimes.last,
                  let ms = CountRecordLogic.parseLapStamp(last, dayKey: dayKey)
            else { continue }
            let idleMin = Int(max(0, (nowMs - ms) / 60_000).rounded())
            if idleMin >= idleThresholdMinutes {
                out.append(
                    IdleVehicle(
                        id: unit.id,
                        vehicleId: unit.vehicleId,
                        driverLabel: unit.driverLabel,
                        rounds: unit.rounds,
                        idleMinutes: idleMin,
                        reason: "เงียบ \(idleMin) นาที"
                    )
                )
            }
        }

        return out.sorted { lhs, rhs in
            let lm = lhs.idleMinutes ?? Int.max
            let rm = rhs.idleMinutes ?? Int.max
            if lm != rm { return lm > rm }
            return lhs.rounds < rhs.rounds
        }
    }

    private nonisolated static func buildInsights(
        rounds: Int,
        target: Int,
        reached: Bool,
        vehicleCount: Int,
        roundsVsPrior: Double?,
        paceVsPrior: Double?,
        priorLabel: String,
        vsAvg7: Double?,
        paceHealth: PaceHealth,
        efficiencyDelta: Double?,
        efficiencyPriorLabel: String,
        leaders: [LeaderRow],
        idleCount: Int,
        balance: BalanceSide,
        balanceDelta: Int,
        etaClock: String?,
        peakLabel: String?,
        consistencyPct: Double?
    ) -> [String] {
        var lines: [String] = []

        if rounds == 0 {
            lines.append("ยังไม่มีเที่ยววันนี้ — กดนับเที่ยวเพื่อเริ่มติดตามเป้า \(CountRecordLogic.formatMetric(target)) เที่ยว")
            return lines
        }

        if reached {
            lines.append("ถึงเป้า \(CountRecordLogic.formatMetric(target)) เที่ยวแล้ว · \(vehicleCount) คัน")
        } else if let clock = etaClock {
            lines.append("คาดการณ์ถึงเป้าประมาณ \(clock) · เหลือ \(CountRecordLogic.formatMetric(max(0, target - rounds))) เที่ยว")
        }

        if let pct = roundsVsPrior, abs(pct) >= 8 {
            let arrow = pct >= 0 ? "มากกว่า" : "น้อยกว่า"
            lines.append("เที่ยว\(arrow)\(priorLabel) \(abs(Int(pct.rounded())))%")
        } else if let pct = vsAvg7, abs(pct) >= 12 {
            let arrow = pct >= 0 ? "สูงกว่า" : "ต่ำกว่า"
            lines.append("เที่ยว\(arrow)ค่าเฉลี่ย 7 วัน \(abs(Int(pct.rounded())))%")
        }

        if let pct = paceVsPrior, abs(pct) >= 10 {
            if pct > 0 {
                lines.append("จังหวะช้าลง \(Int(pct.rounded()))% เทียบ\(priorLabel)")
            } else {
                lines.append("จังหวะเร็วขึ้น \(abs(Int(pct.rounded())))% เทียบ\(priorLabel)")
            }
        } else if paceHealth == .uneven, let c = consistencyPct {
            lines.append("จังหวะสะดุด · อยู่ในแบนด์ \(Int(c.rounded()))%")
        }

        if let pct = efficiencyDelta, abs(pct) >= 8 {
            let arrow = pct >= 0 ? "ดีกว่า" : "ด้อยกว่า"
            lines.append("ประสิทธิภาพ\(arrow)\(efficiencyPriorLabel) \(abs(Int(pct.rounded())))%")
        }

        if let top = leaders.first, lines.count < 3 {
            lines.append("นำ \(top.vehicleId) · \(CountRecordLogic.formatMetric(top.rounds)) เที่ยว")
        }

        if idleCount > 0, lines.count < 3 {
            lines.append("มี \(idleCount) คันเงียบ/ยังไม่วิ่ง — ควรไล่เช็ค")
        }

        switch balance {
        case .sandAhead:
            if lines.count < 3 {
                lines.append("ร่อนนำเที่ยว \(CountRecordLogic.formatMetric(balanceDelta)) คิว")
            }
        case .tripAhead:
            if lines.count < 3 {
                lines.append("เที่ยวนำร่อน \(CountRecordLogic.formatMetric(-balanceDelta)) คิว")
            }
        case .balanced, .none:
            break
        }

        if let peak = peakLabel, lines.count < 3 {
            lines.append("ชั่วโมงพีค \(peak)")
        }

        return Array(lines.prefix(3))
    }
}
