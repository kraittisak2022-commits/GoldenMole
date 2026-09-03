import Foundation

/// Pro command-center metrics for the Real-time ร่อนทราย tab.
struct SandProSnapshot: Sendable {
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

    let dayKey: String
    let rounds: Int
    let target: Int
    let progressPct: Double
    let remaining: Int
    let reached: Bool
    let etaClock: String?
    let hoursLeft: Double?
    let perHour: Double?

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

    let tripRounds: Int
    let tripQueueCubic: Int
    let balance: BalanceSide
    let balanceDelta: Int

    let drumsObtained: Double
    let drumsHome: Double
    let drumsNet: Double
    let washedCubic: Double

    let insights: [String]
    let ctaTitle: String?

    var hasSandData: Bool { rounds > 0 }

    static let empty = SandProSnapshot(
        dayKey: "",
        rounds: 0,
        target: CountRecordLogic.sandTarget,
        progressPct: 0,
        remaining: CountRecordLogic.sandTarget,
        reached: false,
        etaClock: nil,
        hoursLeft: nil,
        perHour: nil,
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
        tripRounds: 0,
        tripQueueCubic: 0,
        balance: .none,
        balanceDelta: 0,
        drumsObtained: 0,
        drumsHome: 0,
        drumsNet: 0,
        washedCubic: 0,
        insights: [],
        ctaTitle: nil
    )

    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        sandUnit: CountRecordSandUnit?,
        sandAnalytics: CountRecordAnalytics.ModeAnalytics,
        tripTotal: Int,
        sandHours: Double?,
        byDay: [String: [Transaction]]? = nil
    ) -> SandProSnapshot {
        guard !dayKey.isEmpty else { return .empty }

        let dayIndex = byDay ?? Dictionary(grouping: transactions) { String($0.date.prefix(10)) }
        let dayTx = dayIndex[dayKey] ?? []
        let rounds = sandUnit?.rounds ?? sandAnalytics.rounds
        let target = CountRecordLogic.sandTarget
        let remaining = max(0, target - rounds)
        let progress = target > 0 ? min(Double(rounds) / Double(target) * 100, 100) : 0
        let eta = sandAnalytics.eta
        let hours = sandHours
            ?? sandAnalytics.workDuration?.totalActiveHours
        let perHour = hours.flatMap { $0 > 0 ? Double(rounds) / $0 : nil }

        let comparison = sandAnalytics.comparison
        let priorLabel = comparison.priorLabel.isEmpty
            ? (comparison.isCalendarYesterday ? "เมื่อวาน" : "วันก่อน")
            : comparison.priorLabel

        var avgSum = 0.0
        for i in 1...7 {
            let key = DashboardAggregations.shiftDateStr(dayKey, deltaDays: -i)
            let tx = dayIndex[key] ?? []
            avgSum += Double(CountRecordLogic.buildSandUnit(dayKey: key, transactions: tx)?.rounds ?? 0)
        }
        let avg7 = avgSum / 7.0
        let vsAvg7 = DashboardAggregations.pctChangeVsPrev(cur: Double(rounds), prev: avg7)

        let consistency = sandAnalytics.consistency
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

        let tripQueue = tripTotal * CountRecordLogic.queuePerTrip
        let balanceDelta = rounds - tripQueue
        let balance: BalanceSide
        if rounds == 0 && tripQueue == 0 {
            balance = .none
        } else if abs(balanceDelta) <= max(20, Int(Double(max(rounds, tripQueue)) * 0.08)) {
            balance = .balanced
        } else if balanceDelta > 0 {
            balance = .sandAhead
        } else {
            balance = .tripAhead
        }

        let sandRows = dayTx.filter {
            $0.category == "DailyLog"
                && ($0.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "Sand"
        }
        let obtained = sandRows.compactMap(\.drumsObtained).max()
            ?? Double(rounds)
        let home = DashboardAggregations.persistedSandHomeDrums(sandRows)
        let washed = sandRows.reduce(0.0) { $0 + DashboardAggregations.sandWashedCubic($1) }
        let net = max(0, obtained - home)

        let peak = sandAnalytics.peak
        let insights = buildInsights(
            rounds: rounds,
            target: target,
            reached: eta?.reached == true || rounds >= target,
            roundsVsPrior: comparison.roundsDeltaPct,
            paceVsPrior: comparison.paceDeltaPct,
            priorLabel: priorLabel,
            vsAvg7: vsAvg7,
            paceHealth: paceHealth,
            balance: balance,
            balanceDelta: balanceDelta,
            tripQueue: tripQueue,
            etaClock: eta?.etaClock,
            peakLabel: peak?.label,
            consistencyPct: consistency?.pctInBand
        )

        let cta: String?
        if rounds == 0 {
            cta = "เริ่มนับร่อนทราย"
        } else if eta?.reached != true, rounds < target {
            if let clock = eta?.etaClock {
                cta = "เร่งจังหวะ · เป้า ~\(clock)"
            } else if paceHealth == .uneven {
                cta = "จังหวะสะดุด · เปิดนับต่อ"
            } else {
                cta = "นับร่อนต่อ · เหลือ \(CountRecordLogic.formatMetric(remaining)) คิว"
            }
        } else {
            cta = nil
        }

        return SandProSnapshot(
            dayKey: dayKey,
            rounds: rounds,
            target: target,
            progressPct: progress,
            remaining: remaining,
            reached: eta?.reached == true || rounds >= target,
            etaClock: eta?.etaClock,
            hoursLeft: eta?.hoursLeft,
            perHour: perHour,
            priorLabel: priorLabel,
            roundsVsPriorPct: comparison.roundsDeltaPct,
            paceVsPriorPct: comparison.paceDeltaPct,
            roundsAvg7: avg7,
            roundsVsAvg7Pct: vsAvg7,
            paceHealth: paceHealth,
            consistencyPct: consistency?.pctInBand,
            sparkline: sandAnalytics.sparkline,
            peakHourLabel: peak?.label,
            peakHourCount: peak?.count,
            tripRounds: tripTotal,
            tripQueueCubic: tripQueue,
            balance: balance,
            balanceDelta: balanceDelta,
            drumsObtained: obtained,
            drumsHome: home,
            drumsNet: net,
            washedCubic: washed,
            insights: insights,
            ctaTitle: cta
        )
    }

    private nonisolated static func buildInsights(
        rounds: Int,
        target: Int,
        reached: Bool,
        roundsVsPrior: Double?,
        paceVsPrior: Double?,
        priorLabel: String,
        vsAvg7: Double?,
        paceHealth: PaceHealth,
        balance: BalanceSide,
        balanceDelta: Int,
        tripQueue: Int,
        etaClock: String?,
        peakLabel: String?,
        consistencyPct: Double?
    ) -> [String] {
        var lines: [String] = []

        if rounds == 0 {
            lines.append("ยังไม่มีคิวร่อนวันนี้ — กดนับร่อนเพื่อเริ่มติดตามเป้า \(CountRecordLogic.formatMetric(target)) คิว")
            return lines
        }

        if reached {
            lines.append("ถึงเป้า \(CountRecordLogic.formatMetric(target)) คิวแล้ว")
        } else if let clock = etaClock {
            lines.append("คาดการณ์ถึงเป้าประมาณ \(clock) · เหลือ \(CountRecordLogic.formatMetric(max(0, target - rounds))) คิว")
        }

        if let pct = roundsVsPrior, abs(pct) >= 8 {
            let arrow = pct >= 0 ? "มากกว่า" : "น้อยกว่า"
            lines.append("คิวร่อน\(arrow)\(priorLabel) \(abs(Int(pct.rounded())))%")
        } else if let pct = vsAvg7, abs(pct) >= 12 {
            let arrow = pct >= 0 ? "สูงกว่า" : "ต่ำกว่า"
            lines.append("คิวร่อน\(arrow)ค่าเฉลี่ย 7 วัน \(abs(Int(pct.rounded())))%")
        }

        // paceDeltaPct: positive = slower (longer interval) in typical analytics — check web/iOS meaning
        if let pct = paceVsPrior, abs(pct) >= 10 {
            // In CountRecordAnalytics, paceDelta is usually (todayAvg - priorAvg) / priorAvg
            // so positive means slower intervals.
            if pct > 0 {
                lines.append("จังหวะช้าลง \(Int(pct.rounded()))% เทียบ\(priorLabel)")
            } else {
                lines.append("จังหวะเร็วขึ้น \(abs(Int(pct.rounded())))% เทียบ\(priorLabel)")
            }
        } else if paceHealth == .uneven, let c = consistencyPct {
            lines.append("จังหวะสะดุด · อยู่ในแบนด์ \(Int(c.rounded()))%")
        } else if paceHealth == .steady {
            lines.append("จังหวะนิ่งดี")
        }

        switch balance {
        case .sandAhead:
            lines.append("ร่อนนำเที่ยว \(CountRecordLogic.formatMetric(balanceDelta)) คิว — ทรายอาจค้างกอง")
        case .tripAhead:
            lines.append("เที่ยวนำร่อน \(CountRecordLogic.formatMetric(-balanceDelta)) คิว — อาจขาดทรายล้าง")
        case .balanced:
            if tripQueue > 0 {
                lines.append("คิวร่อนกับคิวจากเที่ยวสมดุลกัน")
            }
        case .none:
            break
        }

        if let peak = peakLabel, lines.count < 3 {
            lines.append("ชั่วโมงพีค \(peak)")
        }

        return Array(lines.prefix(3))
    }
}
