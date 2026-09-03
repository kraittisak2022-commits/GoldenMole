import SwiftUI

/// One step of the web Daily Wizard (`DailyStepRecorder`), summarized for a single day.
struct DailyWizardStep: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case labor, vehicle, trip, sand, fuel, income, event

        var title: String {
            switch self {
            case .labor: return "ค่าแรง"
            case .vehicle: return "การใช้รถ"
            case .trip: return "เที่ยวรถ"
            case .sand: return "ล้างทราย"
            case .fuel: return "น้ำมัน"
            case .income: return "รายรับ"
            case .event: return "เหตุการณ์"
            }
        }

        var systemImage: String {
            switch self {
            case .labor: return "person.2.fill"
            case .vehicle: return "car.fill"
            case .trip: return "truck.box.fill"
            case .sand: return "drop.fill"
            case .fuel: return "fuelpump.fill"
            case .income: return "banknote.fill"
            case .event: return "exclamationmark.bubble.fill"
            }
        }

        var accent: Color {
            switch self {
            case .labor: return AppTheme.labor
            case .vehicle: return AppTheme.vehicle
            case .trip: return AppTheme.info
            case .sand: return AppTheme.sand
            case .fuel: return AppTheme.fuel
            case .income: return AppTheme.income
            case .event: return AppTheme.purple
            }
        }
    }

    let kind: Kind
    let recordCount: Int
    let headline: String
    let detail: String?

    var id: String { kind.rawValue }
    var isRecorded: Bool { recordCount > 0 }
}

/// A whole day's wizard progress: what was recorded, what is still missing, and the money.
struct DailyWizardDay: Sendable {
    let dayKey: String
    let steps: [DailyWizardStep]
    /// Labor + vehicle hire + fuel, mirroring the web `sumWizardDailySpend`.
    let totalSpend: Double
    let totalIncome: Double
    let recordCount: Int

    var completedCount: Int { steps.filter(\.isRecorded).count }
    var stepCount: Int { steps.count }
    var isEmpty: Bool { recordCount == 0 }
    var missingTitles: [String] { steps.filter { !$0.isRecorded }.map(\.kind.title) }

    var completion: Double {
        guard stepCount > 0 else { return 0 }
        return Double(completedCount) / Double(stepCount)
    }

    static func empty(dayKey: String) -> DailyWizardDay {
        DailyWizardDay(
            dayKey: dayKey,
            steps: DailyWizardStep.Kind.allCases.map {
                DailyWizardStep(kind: $0, recordCount: 0, headline: "—", detail: nil)
            },
            totalSpend: 0,
            totalIncome: 0,
            recordCount: 0
        )
    }
}

/// Off-main builder for the daily wizard summary shown at the top of the Reports tab.
enum DailyWizardSnapshot {
    nonisolated static func build(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee]
    ) -> DailyWizardDay {
        guard !dayKey.isEmpty else { return .empty(dayKey: dayKey) }

        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }
        guard !dayTx.isEmpty else { return .empty(dayKey: dayKey) }

        // Trips, sand and headcount already have battle-tested parsers; reuse them.
        let ops = MobileOpsSnapshot.metricsForDay(
            dayKey: dayKey,
            transactions: transactions,
            employees: employees
        )

        let labor = dayTx.filter { $0.category == "Labor" }
        let laborBaht = DashboardAggregations.laborCostForDay(
            dayLaborTx: labor,
            employees: employees
        )
        let laborHeads = Set(labor.flatMap { $0.employeeIds ?? [] }.filter { !$0.isEmpty }).count

        // Paid vehicle hire only — macro usage and trip rows belong to other steps.
        let vehicle = dayTx.filter {
            $0.category == "Vehicle" && !DashboardAggregations.isMacroUsageRow($0)
        }
        let vehicleBaht = vehicle.reduce(0.0) { $0 + DashboardAggregations.inferredVehicleSpend($1) }
        let vehicleCars = Set(
            vehicle.compactMap { $0.vehicleId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count

        let trips = dayTx.filter { $0.category == "DailyLog" && $0.subCategory == "VehicleTrip" }
        let sand = dayTx.filter { $0.category == "DailyLog" && $0.subCategory == "Sand" }
        let fuel = dayTx.filter { $0.category == "Fuel" }
        let fuelBaht = fuel.reduce(0.0) { $0 + $1.amount }
        let income = dayTx.filter { $0.type == .income }
        let incomeBaht = income.reduce(0.0) { $0 + $1.amount }
        let events = dayTx.filter { $0.category == "DailyLog" && $0.subCategory == "Event" }

        let netDrums = max(0, ops.drumsObtained - ops.drumsHome)

        let steps: [DailyWizardStep] = [
            DailyWizardStep(
                kind: .labor,
                recordCount: labor.count,
                headline: laborHeads > 0 ? "\(laborHeads) คน" : DashboardAggregations.formatCurrency(laborBaht),
                detail: laborBaht > 0 ? DashboardAggregations.formatCurrency(laborBaht) : "\(labor.count) รายการ"
            ),
            DailyWizardStep(
                kind: .vehicle,
                recordCount: vehicle.count,
                headline: DashboardAggregations.formatCurrency(vehicleBaht),
                detail: "\(vehicleCars) คัน · \(vehicle.count) รายการ"
            ),
            DailyWizardStep(
                kind: .trip,
                recordCount: trips.count,
                headline: "\(ops.tripRounds) เที่ยว",
                detail: "\(ops.tripVehicles) คัน · \(DashboardAggregations.formatNumber(ops.tripCubic)) คิว"
            ),
            DailyWizardStep(
                kind: .sand,
                recordCount: sand.count,
                headline: "\(DashboardAggregations.formatNumber(ops.sandWashedCubic)) คิว",
                detail: "ถังสุทธิ \(DashboardAggregations.formatNumber(netDrums))"
            ),
            DailyWizardStep(
                kind: .fuel,
                recordCount: fuel.count,
                headline: fuelBaht > 0
                    ? DashboardAggregations.formatCurrency(fuelBaht)
                    : "\(DashboardAggregations.formatNumber(ops.fuelOutLiters)) ลิตร",
                detail: "เข้า \(DashboardAggregations.formatNumber(ops.fuelInLiters)) L · ออก \(DashboardAggregations.formatNumber(ops.fuelOutLiters)) L"
            ),
            DailyWizardStep(
                kind: .income,
                recordCount: income.count,
                headline: DashboardAggregations.formatCurrency(incomeBaht),
                detail: "\(income.count) รายการ"
            ),
            DailyWizardStep(
                kind: .event,
                recordCount: events.count,
                headline: "\(events.count) เรื่อง",
                detail: events.first?.description
            )
        ]

        return DailyWizardDay(
            dayKey: dayKey,
            steps: steps,
            totalSpend: laborBaht + vehicleBaht + fuelBaht,
            totalIncome: incomeBaht,
            recordCount: dayTx.count
        )
    }

    /// Newest day at or before `from` that has any wizard-relevant rows. Used by the
    /// empty state so an unrecorded day offers somewhere useful to go.
    nonisolated static func latestDayWithRecords(
        in transactions: [Transaction],
        onOrBefore from: String
    ) -> String? {
        transactions
            .map { String($0.date.prefix(10)) }
            .filter { $0 <= from && !$0.isEmpty }
            .max()
    }
}
