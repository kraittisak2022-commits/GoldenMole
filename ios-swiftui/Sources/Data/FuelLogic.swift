import Foundation

/// Flutter «น้ำมัน» helpers (`fuel_stock.dart` + classifiers) — dual tank parity.
enum FuelLogic {
    static let tankCapacityMainLiters: Double = 12000
    static let tankCapacityReserveLiters: Double = 1000
    /// ความเข้ากันได้ — ถังหลัก
    static let tankCapacityLiters: Double = tankCapacityMainLiters

    static let tankMain = "main"
    static let tankReserve = "reserve"
    static let stockInSubCategory = "StockIn"
    static let withdrawSubCategory = "Withdraw"
    static let transferSubCategory = "Transfer"
    static let sandSieveSubCategory = "SandSieve"
    static let vehicleUsageSubCategory = "VehicleUsage"
    static let sandSieveLitersPerHour: Double = 18

    enum SubMode: String, CaseIterable, Identifiable, Sendable {
        case stockIn
        case withdraw
        case carFill
        case macroUsage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .stockIn: return "เพิ่มน้ำมัน"
            case .withdraw: return "เบิกน้ำมัน"
            case .carFill: return "เติมน้ำมันรถยนต์"
            case .macroUsage: return "การใช้น้ำมันรถแม็คโคร"
            }
        }

        var subtitle: String {
            switch self {
            case .stockIn: return "รถน้ำมันมาเติมเข้าถังหลัก"
            case .withdraw: return "เครื่องจักร→สำรอง · อื่นๆ→ถังหลัก"
            case .carFill: return "หักจากถังหลัก"
            case .macroUsage: return "ค่าเริ่มต้นหักจากถังสำรอง"
            }
        }

        var systemImage: String {
            switch self {
            case .stockIn: return "arrow.down.to.line.circle.fill"
            case .withdraw: return "arrow.up.right.circle.fill"
            case .carFill: return "car.fill"
            case .macroUsage: return "fuelpump.fill"
            }
        }
    }

    enum CarFillVehicle: String, CaseIterable, Identifiable, Sendable {
        case mighty
        case taplien
        case ahming
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .mighty: return "ไมตี้"
            case .taplien: return "รถตาเปลื่ยน"
            case .ahming: return "อาหมิง"
            case .other: return "อื่นๆ"
            }
        }

        func vehicleId(otherText: String) -> String {
            switch self {
            case .mighty, .taplien, .ahming: return label
            case .other: return otherText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    enum WithdrawPurpose: String, CaseIterable, Identifiable, Sendable {
        case machine
        case car
        case generator
        case other

        var id: String { rawValue }

        /// เมนูเบิก — ไม่รวมรถยนต์ (ใช้เมนูเติมน้ำมันรถยนต์)
        static var withdrawMenuCases: [WithdrawPurpose] { [.machine, .generator, .other] }

        var label: String {
            switch self {
            case .machine: return "เติมเครื่องจักร (ถังสำรอง)"
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
        var mainDiesel: Double
        var reserveDiesel: Double
        var mainBenzine: Double
        var reserveBenzine: Double

        var diesel: Double { mainDiesel }
        var benzine: Double { mainBenzine }

        func diesel(forTank tank: String?) -> Double {
            normalizeTank(tank) == tankReserve ? reserveDiesel : mainDiesel
        }
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

    static func normalizeTank(_ raw: String?) -> String {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v == tankReserve || v == "สำรอง" { return tankReserve }
        return tankMain
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

    static func isTransfer(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        return (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == transferSubCategory
    }

    static func isSandSieve(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        return (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == sandSieveSubCategory
    }

    static func isVehicleUsage(_ t: Transaction) -> Bool {
        guard isFuelExpense(t), !isStockIn(t) else { return false }
        let vehicle = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicle.isEmpty else { return false }
        return (t.quantity ?? 0) > 0
    }

    /// วันตัดยอด — ก่อนวันนี้ถือว่าน้ำมันเหลือ 0; ตั้งแต่วันนี้หักถังปกติ (พ.ศ. 5 ส.ค. 2569)
    static let stockCutoverYmd = "2026-08-05"

    /// Flutter `computeFuelStockBalance` parity (dual tank + machine reconcile).
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
            let day = String(t.date.prefix(10))
            guard day >= stockCutoverYmd else { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            let isBenzine = (t.fuelType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "benzine"
            let tank = normalizeTank(t.fuelTank)
            let key = "\(day)|\(tank)|\(isBenzine ? "B" : "D")"
            var b = buckets[key] ?? Bucket()
            if isStockIn(t) {
                b.stockIn += lit
            } else if isWithdraw(t) {
                b.withdraw += lit
                if (t.workType ?? "").lowercased() == "machine" {
                    b.machineWithdraw += lit
                }
            } else if isTransfer(t) || isSandSieve(t) {
                b.withdraw += lit
                if isTransfer(t), (t.workType ?? "").lowercased() == "machine" {
                    b.machineWithdraw += lit
                }
            } else if isVehicleUsage(t) {
                b.vehicleUsage += lit
            }
            buckets[key] = b
        }

        var mainDiesel = opening?.diesel ?? 0
        var mainBenzine = opening?.benzine ?? 0
        var reserveDiesel = 0.0
        var reserveBenzine = 0.0
        for (key, b) in buckets {
            let excess = b.vehicleUsage - b.machineWithdraw
            let delta = b.stockIn - b.withdraw - max(0, excess)
            let isReserve = key.contains("|\(tankReserve)|")
            let isBenzine = key.hasSuffix("|B")
            if isReserve {
                if isBenzine { reserveBenzine += delta } else { reserveDiesel += delta }
            } else if isBenzine {
                mainBenzine += delta
            } else {
                mainDiesel += delta
            }
        }
        return Balance(
            mainDiesel: mainDiesel,
            reserveDiesel: reserveDiesel,
            mainBenzine: mainBenzine,
            reserveBenzine: reserveBenzine
        )
    }

    static func machineReconcile(
        dayKey: String,
        transactions: [Transaction],
        tank: String? = nil
    ) -> DayReconcile {
        let filterTank = tank.map { normalizeTank($0) }
        var machineWithdraw = 0.0
        var vehicleUsage = 0.0
        for t in transactions {
            guard String(t.date.prefix(10)) == dayKey, isFuelExpense(t) else { continue }
            if let filterTank, normalizeTank(t.fuelTank) != filterTank { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            if isWithdraw(t), (t.workType ?? "").lowercased() == "machine" {
                machineWithdraw += lit
            } else if isTransfer(t), (t.workType ?? "").lowercased() == "machine" {
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

    static func sandSieveTxId(dateYmd: String) -> String {
        "\(dateYmd.trimmingCharacters(in: .whitespacesAndNewlines))_fuel_sand_sieve"
    }
}
