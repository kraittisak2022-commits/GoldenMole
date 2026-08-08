import Foundation

/// Flutter «น้ำมัน» helpers (`fuel_stock.dart` + classifiers).
enum FuelLogic {
    static let tankCapacityLiters: Double = 9000
    static let stockInSubCategory = "StockIn"
    static let withdrawSubCategory = "Withdraw"
    static let vehicleUsageSubCategory = "VehicleUsage"

    enum SubMode: String, CaseIterable, Identifiable, Sendable {
        case stockIn
        case withdraw
        case macroUsage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stockIn: return "เพิ่มน้ำมัน"
            case .withdraw: return "เบิกน้ำมัน"
            case .macroUsage: return "การใช้น้ำมันรถแม็คโคร"
            }
        }

        var subtitle: String {
            switch self {
            case .stockIn: return "รถน้ำมันมาเติมเข้าถัง"
            case .withdraw: return "เบิกออกจากถังสต็อก"
            case .macroUsage: return "บันทึกลิตรต่อคันแม็คโคร"
            }
        }

        var systemImage: String {
            switch self {
            case .stockIn: return "arrow.down.to.line.circle.fill"
            case .withdraw: return "arrow.up.right.circle.fill"
            case .macroUsage: return "fuelpump.fill"
            }
        }
    }

    enum WithdrawPurpose: String, CaseIterable, Identifiable, Sendable {
        case machine
        case car
        case generator
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .machine: return "เติมเครื่องจักร"
            case .car: return "รถยนต์"
            case .generator: return "เครื่องปั่นไฟเล็ก"
            case .other: return "อื่นๆ"
            }
        }

        static func from(code: String?) -> WithdrawPurpose {
            switch (code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "machine": return .machine
            case "car": return .car
            case "generator": return .generator
            case "other": return .other
            default: return .machine
            }
        }
    }

    struct Balance: Equatable, Sendable {
        var diesel: Double
        var benzine: Double
    }

    struct DayReconcile: Equatable, Sendable {
        var machineWithdraw: Double
        var vehicleUsage: Double
        var remaining: Double
    }

    static func liters(of t: Transaction) -> Double {
        DashboardAggregations.fuelTxToLiters(t)
    }

    static func formatLiters(_ v: Double) -> String {
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        return String(format: "%.2f", v)
    }

    static func isFuelExpense(_ t: Transaction) -> Bool {
        t.category == "Fuel" && t.type == .expense
    }

    static func isStockIn(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        let mov = (t.fuelMovement ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mov == "stock_in" { return true }
        if mov == "stock_out" { return false }
        return (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isWithdraw(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        guard (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == withdrawSubCategory else {
            return false
        }
        return !isStockIn(t)
    }

    static func isVehicleUsage(_ t: Transaction) -> Bool {
        guard isFuelExpense(t), !isStockIn(t) else { return false }
        let vehicle = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicle.isEmpty else { return false }
        return (t.quantity ?? 0) > 0
    }

    /// Flutter `computeFuelStockBalance` parity (daily reconcile machine vs macro usage).
    static func computeBalance(
        transactions: [Transaction],
        opening: FuelStock?
    ) -> Balance {
        struct Bucket {
            var stockIn = 0.0
            var withdraw = 0.0
            var machineWithdraw = 0.0
            var vehicleUsage = 0.0
        }
        var buckets: [String: Bucket] = [:]

        for t in transactions {
            guard isFuelExpense(t) else { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            let day = String(t.date.prefix(10))
            let isBenzine = (t.fuelType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "benzine"
            let key = "\(day)|\(isBenzine ? "B" : "D")"
            var b = buckets[key] ?? Bucket()
            if isStockIn(t) {
                b.stockIn += lit
            } else if isWithdraw(t) {
                b.withdraw += lit
                if (t.workType ?? "").lowercased() == "machine" {
                    b.machineWithdraw += lit
                }
            } else if isVehicleUsage(t) {
                b.vehicleUsage += lit
            }
            buckets[key] = b
        }

        var diesel = opening?.diesel ?? 0
        var benzine = opening?.benzine ?? 0
        for (key, b) in buckets {
            let excess = b.vehicleUsage - b.machineWithdraw
            let delta = b.stockIn - b.withdraw - max(0, excess)
            if key.hasSuffix("|B") {
                benzine += delta
            } else {
                diesel += delta
            }
        }
        return Balance(diesel: diesel, benzine: benzine)
    }

    static func machineReconcile(dayKey: String, transactions: [Transaction]) -> DayReconcile {
        var machineWithdraw = 0.0
        var vehicleUsage = 0.0
        for t in transactions {
            guard String(t.date.prefix(10)) == dayKey, isFuelExpense(t) else { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            if isWithdraw(t), (t.workType ?? "").lowercased() == "machine" {
                machineWithdraw += lit
            } else if isVehicleUsage(t) {
                vehicleUsage += lit
            }
        }
        let remaining = machineWithdraw - vehicleUsage
        return DayReconcile(
            machineWithdraw: machineWithdraw,
            vehicleUsage: vehicleUsage,
            remaining: max(0, remaining)
        )
    }

    static func nowTimeHHmm() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 7 * 3600)
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    static func stripRecorder(_ raw: String) -> String {
        var s = raw
        for m in [" • โดย ", " โดย ", " — บันทึกโดย "] {
            if let r = s.range(of: m) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func dayFuelRows(dayKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { String($0.date.prefix(10)) == dayKey && isFuelExpense($0) }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }
}
