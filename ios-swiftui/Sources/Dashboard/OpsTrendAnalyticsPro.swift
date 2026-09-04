import Foundation
import SwiftUI

// MARK: - Range mode (week / month / custom)

enum OpsTrendRangeMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "วันนี้"
        case .week: return "สัปดาห์"
        case .month: return "เดือน"
        case .custom: return "กำหนดเอง"
        }
    }

    var period: OpsTrendPeriod? {
        switch self {
        case .day: return .day
        case .week: return .week
        case .month: return .month
        case .custom: return nil
        }
    }
}

// MARK: - Watchlist (pinned alerts)

enum OpsTrendWatchlistStore {
    private static let key = "opsTrend.watchlist.alertIds"

    static func pinnedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func isPinned(_ id: String) -> Bool {
        pinnedIds().contains(id)
    }

    static func toggle(_ id: String) {
        var ids = pinnedIds()
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.standard.set(Array(ids).sorted(), forKey: key)
    }

    static func pinnedAlerts(matching alerts: [OpsTrendAlert]) -> [OpsTrendAlert] {
        let ids = pinnedIds()
        guard !ids.isEmpty else { return [] }
        return alerts.filter { ids.contains($0.id) }
    }

    static func resolvedPins(from alerts: [OpsTrendAlert]) -> [OpsTrendAlert] {
        let pinned = pinnedAlerts(matching: alerts)
        if !pinned.isEmpty { return pinned }
        // Keep titles for home even if current period lacks the alert id match —
        // fall back is empty; home builds from latest week report.
        return []
    }
}

// MARK: - Pro extras (briefing / forecast / cost)

struct OpsTrendAnalyticsPro: Sendable {
    enum Health: String, Sendable {
        case strong
        case caution
        case critical

        var label: String {
            switch self {
            case .strong: return "จังหวะดี"
            case .caution: return "ต้องเฝ้า"
            case .critical: return "เร่งแก้"
            }
        }

        var systemImage: String {
            switch self {
            case .strong: return "checkmark.seal.fill"
            case .caution: return "exclamationmark.triangle.fill"
            case .critical: return "bolt.horizontal.circle.fill"
            }
        }

        var accentHex: String {
            switch self {
            case .strong: return "#059669"
            case .caution: return "#D97706"
            case .critical: return "#DC2626"
            }
        }
    }

    struct Signal: Identifiable, Sendable {
        let id: String
        let severity: OpsTrendAlertSeverity
        let title: String
        let action: String
        let area: String
    }

    struct Forecast: Sendable {
        let isLivePeriod: Bool
        let daysElapsed: Int
        let daysTotal: Int
        let daysRemaining: Int
        let tripProjected: Double
        let tripTarget: Double
        let tripGap: Double
        let tripPaceNeeded: Double?
        let sandProjected: Double
        let sandAvgNeeded: Double?
        let willHitTripTarget: Bool?
        let headline: String
        let detail: String

        static let empty = Forecast(
            isLivePeriod: false,
            daysElapsed: 0,
            daysTotal: 0,
            daysRemaining: 0,
            tripProjected: 0,
            tripTarget: 0,
            tripGap: 0,
            tripPaceNeeded: nil,
            sandProjected: 0,
            sandAvgNeeded: nil,
            willHitTripTarget: nil,
            headline: "ยังไม่มีพยากรณ์",
            detail: "เลือกช่วงปัจจุบันเพื่อดูว่าจะถึงเป้าหรือไม่"
        )
    }

    struct CostLens: Sendable {
        let laborBaht: Double
        let fuelBaht: Double
        let opsBaht: Double
        let prevOpsBaht: Double
        let tripRounds: Double
        let sandRounds: Double
        let bahtPerTrip: Double?
        let bahtPerSand: Double?
        let prevBahtPerTrip: Double?
        let tripCostChangePct: Double?
        let headline: String
        let detail: String

        var hasData: Bool { opsBaht > 0 || tripRounds > 0 || sandRounds > 0 }

        static let empty = CostLens(
            laborBaht: 0,
            fuelBaht: 0,
            opsBaht: 0,
            prevOpsBaht: 0,
            tripRounds: 0,
            sandRounds: 0,
            bahtPerTrip: nil,
            bahtPerSand: nil,
            prevBahtPerTrip: nil,
            tripCostChangePct: nil,
            headline: "ยังไม่มีต้นทุน",
            detail: "เมื่อมีค่าแรง/น้ำมัน จะเทียบคุ้มค่าปฏิบัติการที่นี่"
        )
    }

    let health: Health
    let healthCaption: String
    let signals: [Signal]
    let primaryCTA: String?
    let forecast: Forecast
    let cost: CostLens
    let shareText: String

    static let empty = OpsTrendAnalyticsPro(
        health: .caution,
        healthCaption: "กำลังโหลด…",
        signals: [],
        primaryCTA: nil,
        forecast: .empty,
        cost: .empty,
        shareText: ""
    )

    nonisolated static func build(
        report: OpsTrendReport,
        focus: OpsTrendFocus,
        periodOffset: Int,
        isCustomRange: Bool,
        transactions: [Transaction],
        employees: [Employee],
        byDay: [String: [Transaction]]
    ) -> OpsTrendAnalyticsPro {
        let plan = report.actionPlan
        let alerts: [OpsTrendAlert] = {
            switch focus {
            case .both: return plan.alerts
            case .trip: return plan.alerts.filter { $0.area != "ร่อนทราย" }
            case .sand: return plan.alerts.filter { $0.area != "เที่ยวรถ" }
            }
        }()

        let critical = alerts.filter { $0.severity == .critical }
        let warning = alerts.filter { $0.severity == .warning }
        let opportunity = alerts.filter { $0.severity == .opportunity }

        let health: Health
        let healthCaption: String
        if !critical.isEmpty {
            health = .critical
            healthCaption = "ต้องเร่งแก้ \(critical.count) จุด · คะแนน \(report.scorecard.score)"
        } else if !warning.isEmpty {
            health = .caution
            healthCaption = "เฝ้าระวัง \(warning.count) จุด · \(plan.healthLabel)"
        } else if report.scorecard.score >= 70 || (!opportunity.isEmpty && critical.isEmpty) {
            health = .strong
            healthCaption = plan.healthLabel.isEmpty
                ? "จังหวะดี · คะแนน \(report.scorecard.score)"
                : plan.healthLabel
        } else if report.activeDays == 0 {
            health = .caution
            healthCaption = "ยังไม่มีข้อมูลในช่วงนี้"
        } else {
            health = .caution
            healthCaption = plan.healthLabel
        }

        var ranked = critical + warning + opportunity
        if ranked.isEmpty { ranked = alerts }
        let signals = Array(ranked.prefix(3)).map {
            Signal(id: $0.id, severity: $0.severity, title: $0.title, action: $0.action, area: $0.area)
        }

        let primaryCTA: String? = {
            if let first = ranked.first { return first.action }
            if let play = plan.playbook.first, focus == .both { return play }
            return nil
        }()

        let forecast = buildForecast(report: report, periodOffset: periodOffset, isCustomRange: isCustomRange)
        let cost = buildCostLens(
            filter: report.filter,
            prevFilter: report.prevFilter,
            tripTotal: report.trip.total,
            sandTotal: report.sand.total,
            prevTripTotal: report.trip.prevTotal,
            transactions: transactions,
            employees: employees,
            byDay: byDay
        )

        let shareText = buildShareText(
            report: report,
            focus: focus,
            health: health,
            healthCaption: healthCaption,
            signals: signals,
            primaryCTA: primaryCTA,
            forecast: forecast,
            cost: cost
        )

        return OpsTrendAnalyticsPro(
            health: health,
            healthCaption: healthCaption,
            signals: signals,
            primaryCTA: primaryCTA,
            forecast: forecast,
            cost: cost,
            shareText: shareText
        )
    }

    // MARK: - Forecast

    private nonisolated static func buildForecast(
        report: OpsTrendReport,
        periodOffset: Int,
        isCustomRange: Bool
    ) -> Forecast {
        let daily = report.dailyPoints
        let daysTotal = max(1, daily.count)
        let today = DashboardAggregations.todayYMD()
        let end = report.filter.end
        let start = report.filter.start

        // Live = current window that includes today (offset 0, or custom that hasn't ended).
        let isLive = (!isCustomRange && periodOffset == 0 && end >= today && start <= today)
            || (isCustomRange && end >= today && start <= today)

        guard isLive, !daily.isEmpty else {
            let tripTarget = report.period.tripDailyTarget * Double(daysTotal)
            return Forecast(
                isLivePeriod: false,
                daysElapsed: daysTotal,
                daysTotal: daysTotal,
                daysRemaining: 0,
                tripProjected: report.trip.total,
                tripTarget: tripTarget,
                tripGap: tripTarget - report.trip.total,
                tripPaceNeeded: nil,
                sandProjected: report.sand.total,
                sandAvgNeeded: nil,
                willHitTripTarget: nil,
                headline: isCustomRange || periodOffset > 0
                    ? "ช่วงย้อนหลัง — ดูผลจริงแล้ว"
                    : "รอข้อมูลช่วงปัจจุบัน",
                detail: "เที่ยวรวม \(OpsTrendAnalytics.formatCompact(report.trip.total)) · ร่อน \(OpsTrendAnalytics.formatCompact(report.sand.total))"
            )
        }

        let elapsedDays = daily.filter { $0.id <= today }.count
        let daysElapsed = max(1, min(daysTotal, elapsedDays))
        let daysRemaining = max(0, daysTotal - daysElapsed)

        let tripSoFar = daily.filter { $0.id <= today }.reduce(0.0) { $0 + Double($1.tripRounds) }
        let sandSoFar = daily.filter { $0.id <= today }.reduce(0.0) { $0 + Double($1.sandRounds) }
        let tripAvg = tripSoFar / Double(daysElapsed)
        let sandAvg = sandSoFar / Double(daysElapsed)

        let tripProjected = tripAvg * Double(daysTotal)
        let sandProjected = sandAvg * Double(daysTotal)
        let tripTarget = report.period.tripDailyTarget * Double(daysTotal)
        let tripGap = tripTarget - tripSoFar
        let tripPaceNeeded: Double? = daysRemaining > 0 ? max(0, tripGap / Double(daysRemaining)) : nil
        let sandAvgNeeded: Double? = daysRemaining > 0 ? sandAvg : nil

        let willHit: Bool? = {
            guard tripTarget > 0 else { return nil }
            return tripProjected >= tripTarget * 0.98
        }()

        let headline: String
        let detail: String
        if let willHit {
            if willHit {
                headline = "แนวโน้มถึงเป้าเที่ยวรถ"
                detail = daysRemaining == 0
                    ? "ปิดช่วงที่ \(OpsTrendAnalytics.formatCompact(tripSoFar)) / \(OpsTrendAnalytics.formatCompact(tripTarget)) เที่ยว"
                    : "คาด \(OpsTrendAnalytics.formatCompact(tripProjected)) เที่ยว · เหลือ \(daysRemaining) วัน · รักษาระดับ \(OpsTrendAnalytics.formatCompact(tripAvg))/วัน"
            } else {
                let need = tripPaceNeeded ?? 0
                headline = "จังหวะปัจจุบันยังไม่ถึงเป้า"
                detail = daysRemaining == 0
                    ? "จบช่วงที่ \(OpsTrendAnalytics.formatCompact(tripSoFar)) / \(OpsTrendAnalytics.formatCompact(tripTarget)) เที่ยว"
                    : "ต้องดัน ~\(OpsTrendAnalytics.formatCompact(need)) เที่ยว/วัน ใน \(daysRemaining) วันที่เหลือ (ช่องว่าง \(OpsTrendAnalytics.formatCompact(max(0, tripGap))))"
            }
        } else {
            headline = "พยากรณ์รอบนี้"
            detail = "คาดเที่ยว \(OpsTrendAnalytics.formatCompact(tripProjected)) · ร่อน \(OpsTrendAnalytics.formatCompact(sandProjected))"
        }

        return Forecast(
            isLivePeriod: true,
            daysElapsed: daysElapsed,
            daysTotal: daysTotal,
            daysRemaining: daysRemaining,
            tripProjected: tripProjected,
            tripTarget: tripTarget,
            tripGap: tripGap,
            tripPaceNeeded: tripPaceNeeded,
            sandProjected: sandProjected,
            sandAvgNeeded: sandAvgNeeded,
            willHitTripTarget: willHit,
            headline: headline,
            detail: detail
        )
    }

    // MARK: - Cost lens

    private nonisolated static func buildCostLens(
        filter: DateFilter,
        prevFilter: DateFilter,
        tripTotal: Double,
        sandTotal: Double,
        prevTripTotal: Double,
        transactions: [Transaction],
        employees: [Employee],
        byDay: [String: [Transaction]]
    ) -> CostLens {
        let current = periodCosts(filter: filter, byDay: byDay, employees: employees)
        let prev = periodCosts(filter: prevFilter, byDay: byDay, employees: employees)

        let bahtPerTrip: Double? = tripTotal > 0 ? current.ops / tripTotal : nil
        let bahtPerSand: Double? = sandTotal > 0 ? current.ops / sandTotal : nil
        let prevBahtPerTrip: Double? = prevTripTotal > 0 ? prev.ops / prevTripTotal : nil
        let tripCostChangePct = DashboardAggregations.pctChangeVsPrev(
            cur: bahtPerTrip ?? 0,
            prev: prevBahtPerTrip ?? 0
        )

        let headline: String
        let detail: String
        if current.ops <= 0 {
            headline = "ยังไม่มีต้นทุนช่วงนี้"
            detail = "บันทึกค่าแรง/น้ำมันเพื่อวัดบาทต่อเที่ยว"
        } else if let bpt = bahtPerTrip {
            let changeNote: String = {
                guard let pct = tripCostChangePct, prevBahtPerTrip != nil else { return "" }
                let arrow = pct <= 0 ? "ดีลง" : "แพงขึ้น"
                return " · บาท/เที่ยว\(arrow) \(String(format: "%+.0f", pct))%"
            }()
            headline = "~\(DashboardAggregations.formatCurrency(bpt))/เที่ยว"
            detail = "ค่าแรง \(DashboardAggregations.formatCurrency(current.labor)) · น้ำมัน \(DashboardAggregations.formatCurrency(current.fuel))\(changeNote)"
        } else {
            headline = "ต้นทุน \(DashboardAggregations.formatCurrency(current.ops))"
            detail = "ค่าแรง \(DashboardAggregations.formatCurrency(current.labor)) · น้ำมัน \(DashboardAggregations.formatCurrency(current.fuel))"
        }

        return CostLens(
            laborBaht: current.labor,
            fuelBaht: current.fuel,
            opsBaht: current.ops,
            prevOpsBaht: prev.ops,
            tripRounds: tripTotal,
            sandRounds: sandTotal,
            bahtPerTrip: bahtPerTrip,
            bahtPerSand: bahtPerSand,
            prevBahtPerTrip: prevBahtPerTrip,
            tripCostChangePct: tripCostChangePct,
            headline: headline,
            detail: detail
        )
    }

    private nonisolated static func periodCosts(
        filter: DateFilter,
        byDay: [String: [Transaction]],
        employees: [Employee]
    ) -> (labor: Double, fuel: Double, ops: Double) {
        let keys = DashboardAggregations.enumerateDates(in: filter)
        var labor = 0.0
        var fuel = 0.0
        for key in keys {
            let dayTx = byDay[key] ?? []
            labor += DashboardAggregations.laborDayCost(
                dayLaborTx: dayTx.filter { $0.category == "Labor" },
                employees: employees
            ).total
            fuel += dayTx.filter { $0.category == "Fuel" && $0.type == .expense }
                .reduce(0.0) { $0 + $1.amount }
        }
        return (labor, fuel, labor + fuel)
    }

    // MARK: - Share text

    private nonisolated static func buildShareText(
        report: OpsTrendReport,
        focus: OpsTrendFocus,
        health: Health,
        healthCaption: String,
        signals: [Signal],
        primaryCTA: String?,
        forecast: Forecast,
        cost: CostLens
    ) -> String {
        let range = "\(report.filter.start) – \(report.filter.end)"
        var lines: [String] = [
            "GoldenMole · สรุปวิเคราะห์\(focus == .both ? "" : " · \(focus.label)")",
            "ช่วง \(range)",
            "สุขภาพ: \(health.label) — \(healthCaption)",
            "คะแนน \(report.scorecard.score) (\(report.scorecard.grade.rawValue))",
            "เที่ยวรถ \(OpsTrendAnalytics.formatCompact(report.trip.total)) · ร่อนทราย \(OpsTrendAnalytics.formatCompact(report.sand.total))",
        ]
        if forecast.isLivePeriod {
            lines.append("พยากรณ์: \(forecast.headline)")
            lines.append(forecast.detail)
        }
        if cost.hasData {
            lines.append("ต้นทุน: \(cost.headline)")
            lines.append(cost.detail)
        }
        if !signals.isEmpty {
            lines.append("สัญญาณสำคัญ:")
            for s in signals {
                lines.append("• [\(s.area)] \(s.title)")
            }
        }
        if let cta = primaryCTA {
            lines.append("ทำต่อ: \(cta)")
        }
        return lines.joined(separator: "\n")
    }
}
