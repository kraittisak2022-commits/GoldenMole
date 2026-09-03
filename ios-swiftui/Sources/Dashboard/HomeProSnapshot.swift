import Foundation

/// Home-tab Pro command-center metrics: checklist, day deltas, and short insights.
struct HomeProSnapshot: Sendable {
    enum Health: String, Sendable {
        case strong
        case attention
        case critical

        var label: String {
            switch self {
            case .strong: return "วันครบถ้วน"
            case .attention: return "ยังขาดบางอย่าง"
            case .critical: return "ยังเริ่มไม่ครบ"
            }
        }

        var systemImage: String {
            switch self {
            case .strong: return "checkmark.seal.fill"
            case .attention: return "exclamationmark.triangle.fill"
            case .critical: return "bolt.horizontal.circle.fill"
            }
        }
    }

    struct MetricDelta: Sendable {
        let current: Double
        let yesterday: Double
        let avg7: Double

        var vsYesterdayPct: Double? {
            DashboardAggregations.pctChangeVsPrev(cur: current, prev: yesterday)
        }

        var vsAvg7Pct: Double? {
            DashboardAggregations.pctChangeVsPrev(cur: current, prev: avg7)
        }

        var hasSignal: Bool {
            current > 0 || yesterday > 0 || avg7 > 0
        }
    }

    enum ChecklistDestination: String, Sendable {
        case attendance
        case countTrip
        case countSand
        case fuel
        case leave
        case events
        case laborReport
        case vehicleReport
    }

    struct ChecklistItem: Identifiable, Sendable {
        let id: String
        let title: String
        let systemImage: String
        let accentHex: String
        let isDone: Bool
        let detail: String
        let destination: ChecklistDestination
    }

    let dayKey: String
    let health: Health
    let wizard: DailyWizardDay
    let coreCompleted: Int
    let coreTotal: Int
    let checklist: [ChecklistItem]
    let trip: MetricDelta
    let sand: MetricDelta
    let labor: MetricDelta
    let present: MetricDelta
    let insights: [String]
    let alerts: [OverviewAlert]
    let primaryMissingTitle: String?

    var completion: Double {
        guard coreTotal > 0 else { return 0 }
        return Double(coreCompleted) / Double(coreTotal)
    }

    static let empty = HomeProSnapshot(
        dayKey: "",
        health: .critical,
        wizard: .empty(dayKey: ""),
        coreCompleted: 0,
        coreTotal: 4,
        checklist: [],
        trip: MetricDelta(current: 0, yesterday: 0, avg7: 0),
        sand: MetricDelta(current: 0, yesterday: 0, avg7: 0),
        labor: MetricDelta(current: 0, yesterday: 0, avg7: 0),
        present: MetricDelta(current: 0, yesterday: 0, avg7: 0),
        insights: [],
        alerts: [],
        primaryMissingTitle: nil
    )

    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        periodAlerts: [OverviewAlert],
        periodInsights: [String]
    ) -> HomeProSnapshot {
        guard !dayKey.isEmpty else { return .empty }

        let wizard = DailyWizardSnapshot.build(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees
        )
        let stepByKind = Dictionary(uniqueKeysWithValues: wizard.steps.map { ($0.kind, $0) })

        let checklist: [ChecklistItem] = [
            item(
                kind: .labor,
                titleOverride: "เช็คชื่อ",
                step: stepByKind[.labor],
                destination: .attendance,
                fallbackDetail: "เช็คชื่อ / ค่าแรง"
            ),
            item(
                kind: .trip,
                titleOverride: nil,
                step: stepByKind[.trip],
                destination: .countTrip,
                fallbackDetail: "บันทึกเที่ยวรถ"
            ),
            item(
                kind: .sand,
                titleOverride: "ร่อนทราย",
                step: stepByKind[.sand],
                destination: .countSand,
                fallbackDetail: "บันทึกร่อนทราย"
            ),
            item(
                kind: .fuel,
                titleOverride: nil,
                step: stepByKind[.fuel],
                destination: .fuel,
                fallbackDetail: "น้ำมันเข้า–ออก"
            ),
        ]

        let coreCompleted = checklist.filter(\.isDone).count
        let coreTotal = checklist.count
        let health: Health
        if coreCompleted >= coreTotal {
            health = .strong
        } else if coreCompleted == 0 {
            health = .critical
        } else {
            health = .attention
        }

        let today = MobileOpsSnapshot.metricsForDay(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees
        )
        let yesterdayKey = DashboardAggregations.shiftDateStr(dayKey, deltaDays: -1)
        let yesterday = MobileOpsSnapshot.metricsForDay(
            dayKey: yesterdayKey,
            transactions: transactions,
            employees: employees
        )

        let todayLabor = DashboardAggregations.laborCostForDay(
            dayLaborTx: transactions.filter {
                String($0.date.prefix(10)) == dayKey && $0.category == "Labor"
            },
            employees: employees
        )
        let yesterdayLabor = DashboardAggregations.laborCostForDay(
            dayLaborTx: transactions.filter {
                String($0.date.prefix(10)) == yesterdayKey && $0.category == "Labor"
            },
            employees: employees
        )

        var tripSum = 0.0
        var sandSum = 0.0
        var laborSum = 0.0
        var presentSum = 0.0
        for i in 1...7 {
            let key = DashboardAggregations.shiftDateStr(dayKey, deltaDays: -i)
            let m = MobileOpsSnapshot.metricsForDay(
                dayKey: key,
                transactions: transactions,
                employees: employees
            )
            tripSum += Double(m.tripRounds)
            sandSum += Double(m.sandRounds)
            presentSum += Double(m.presentCount)
            laborSum += DashboardAggregations.laborCostForDay(
                dayLaborTx: transactions.filter {
                    String($0.date.prefix(10)) == key && $0.category == "Labor"
                },
                employees: employees
            )
        }

        let trip = MetricDelta(
            current: Double(today.tripRounds),
            yesterday: Double(yesterday.tripRounds),
            avg7: tripSum / 7
        )
        let sand = MetricDelta(
            current: Double(today.sandRounds),
            yesterday: Double(yesterday.sandRounds),
            avg7: sandSum / 7
        )
        let labor = MetricDelta(
            current: todayLabor,
            yesterday: yesterdayLabor,
            avg7: laborSum / 7
        )
        let present = MetricDelta(
            current: Double(today.presentCount),
            yesterday: Double(yesterday.presentCount),
            avg7: presentSum / 7
        )

        let insights = buildDayInsights(
            dayKey: dayKey,
            health: health,
            checklist: checklist,
            trip: trip,
            sand: sand,
            labor: labor,
            present: present,
            periodInsights: periodInsights
        )

        let dayAlerts = buildDayAlerts(
            health: health,
            checklist: checklist,
            trip: trip,
            sand: sand,
            periodAlerts: periodAlerts
        )

        return HomeProSnapshot(
            dayKey: dayKey,
            health: health,
            wizard: wizard,
            coreCompleted: coreCompleted,
            coreTotal: coreTotal,
            checklist: checklist,
            trip: trip,
            sand: sand,
            labor: labor,
            present: present,
            insights: insights,
            alerts: dayAlerts,
            primaryMissingTitle: checklist.first(where: { !$0.isDone })?.title
        )
    }

    private nonisolated static func item(
        kind: DailyWizardStep.Kind,
        titleOverride: String?,
        step: DailyWizardStep?,
        destination: ChecklistDestination,
        fallbackDetail: String
    ) -> ChecklistItem {
        let done = step?.isRecorded == true
        let detail: String
        if done, let step {
            if let d = step.detail, !d.isEmpty {
                detail = "\(step.headline) · \(d)"
            } else {
                detail = step.headline
            }
        } else {
            detail = fallbackDetail
        }
        return ChecklistItem(
            id: kind.rawValue,
            title: titleOverride ?? kind.title,
            systemImage: kind.systemImage,
            accentHex: hex(for: kind),
            isDone: done,
            detail: detail,
            destination: destination
        )
    }

    private nonisolated static func hex(for kind: DailyWizardStep.Kind) -> String {
        switch kind {
        case .labor: return "#10B981"
        case .trip: return "#2563EB"
        case .sand: return "#DB2777"
        case .fuel: return "#0D9488"
        case .vehicle: return "#F59E0B"
        case .income: return "#16A34A"
        case .event: return "#8B5CF6"
        }
    }

    private nonisolated static func buildDayInsights(
        dayKey: String,
        health: Health,
        checklist: [ChecklistItem],
        trip: MetricDelta,
        sand: MetricDelta,
        labor: MetricDelta,
        present: MetricDelta,
        periodInsights: [String]
    ) -> [String] {
        var lines: [String] = []

        let missingTitles = checklist.filter { !$0.isDone }.map(\.title)
        if !missingTitles.isEmpty, health != .strong {
            lines.append("ยังไม่บันทึก \(missingTitles.prefix(3).joined(separator: " · "))")
        }

        if let pct = trip.vsYesterdayPct, abs(pct) >= 8, trip.hasSignal {
            let arrow = pct >= 0 ? "เพิ่มขึ้น" : "ลดลง"
            lines.append("เที่ยวรถ\(arrow) \(abs(Int(pct.rounded())))% เทียบเมื่อวาน")
        } else if let pct = trip.vsAvg7Pct, abs(pct) >= 12, trip.hasSignal {
            let arrow = pct >= 0 ? "สูงกว่า" : "ต่ำกว่า"
            lines.append("เที่ยวรถ\(arrow)ค่าเฉลี่ย 7 วัน \(abs(Int(pct.rounded())))%")
        }

        if let pct = sand.vsYesterdayPct, abs(pct) >= 8, sand.hasSignal {
            let arrow = pct >= 0 ? "เพิ่มขึ้น" : "ลดลง"
            lines.append("ร่อนทราย\(arrow) \(abs(Int(pct.rounded())))% เทียบเมื่อวาน")
        }

        if let pct = present.vsYesterdayPct, abs(pct) >= 10, present.hasSignal {
            let arrow = pct >= 0 ? "มาทำงานมากขึ้น" : "มาทำงานน้อยลง"
            lines.append("พนักงาน\(arrow) \(abs(Int(pct.rounded())))% เทียบเมื่อวาน")
        } else if let pct = labor.vsYesterdayPct, abs(pct) >= 12, labor.hasSignal {
            let arrow = pct >= 0 ? "สูงขึ้น" : "ลดลง"
            lines.append("ค่าแรง\(arrow) \(abs(Int(pct.rounded())))% เทียบเมื่อวาน")
        }

        for line in periodInsights where lines.count < 3 {
            if !lines.contains(line) { lines.append(line) }
        }

        if lines.isEmpty {
            let label = DashboardAggregations.thaiDateLong(dayKey)
            lines.append("แนวโน้ม \(label) ค่อนข้างนิ่ง — ไม่มีสัญญาณผิดปกติชัดเจน")
        }

        return Array(lines.prefix(3))
    }

    private nonisolated static func buildDayAlerts(
        health: Health,
        checklist: [ChecklistItem],
        trip: MetricDelta,
        sand: MetricDelta,
        periodAlerts: [OverviewAlert]
    ) -> [OverviewAlert] {
        var out: [OverviewAlert] = []

        switch health {
        case .strong:
            out.append(OverviewAlert(id: "home_health", label: "งานวันนี้ครบถ้วน", severity: .green))
        case .attention:
            let n = checklist.filter { !$0.isDone }.count
            out.append(OverviewAlert(id: "home_health", label: "ยังขาด \(n) รายการ", severity: .amber))
        case .critical:
            out.append(OverviewAlert(id: "home_health", label: "ยังเริ่มบันทึกไม่ครบ", severity: .red))
        }

        if let pct = trip.vsYesterdayPct, pct <= -20, trip.yesterday > 0 {
            out.append(OverviewAlert(id: "trip_drop", label: "เที่ยวรถร่วงแรง", severity: .red))
        }
        if let pct = sand.vsYesterdayPct, pct <= -20, sand.yesterday > 0 {
            out.append(OverviewAlert(id: "sand_drop", label: "ร่อนทรายร่วงแรง", severity: .amber))
        }

        for a in periodAlerts where out.count < 3 {
            if !out.contains(where: { $0.id == a.id }) {
                out.append(a)
            }
        }
        return Array(out.prefix(3))
    }
}

extension HomeProSnapshot.MetricDelta {
    /// Short Thai label for UI chips — prefers yesterday, else 7-day avg.
    var compactCompareLabel: String? {
        if let pct = vsYesterdayPct, yesterday > 0 || current > 0 {
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(Int(pct.rounded()))% vs เมื่อวาน"
        }
        if let pct = vsAvg7Pct, avg7 > 0 {
            let sign = pct >= 0 ? "+" : ""
            return "\(sign)\(Int(pct.rounded()))% vs เฉลี่ย 7 วัน"
        }
        return nil
    }

    var isUp: Bool {
        (vsYesterdayPct ?? vsAvg7Pct ?? 0) >= 0
    }
}
