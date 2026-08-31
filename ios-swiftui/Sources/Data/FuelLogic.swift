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
    static let sandSieveVehicleId = "เครื่องจักรร่อนทราย เครื่องปั่นไฟ"
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
            case .withdraw: return "เครื่องจักร: หลัก→สำรอง · ปั่นไฟ/อื่นๆ: หักถังหลัก"
            case .carFill: return "หักจากถังหลัก"
            case .macroUsage: return "หักจากถังหลังหรือถังสำรองตามที่เลือก"
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
            case .taplien: return "รถตาเปลื่ยน (ISUZU KB)"
            case .ahming: return "อาหมิง"
            case .other: return "อื่นๆ"
            }
        }

        static let taplienLegacyId = "รถตาเปลื่ยน"

        static func from(vehicleId: String) -> CarFillVehicle {
            let v = vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
            switch v {
            case "ไมตี้": return .mighty
            case "รถตาเปลื่ยน (ISUZU KB)", taplienLegacyId: return .taplien
            case "อาหมิง": return .ahming
            default: return .other
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

    /// Flutter `fuelUsageTankOf` — VehicleUsage ที่ไม่ระบุถัง = สำรอง; อื่น ๆ = หลัก
    static func fuelUsageTankOf(_ t: Transaction) -> String {
        let raw = (t.fuelTank ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return normalizeTank(raw) }
        if (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == vehicleUsageSubCategory {
            return tankReserve
        }
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

    /// เติมน้ำมันรถยนต์ (เมนูแยก — workType=car, หักถังหลัก)
    static func isCarFill(_ t: Transaction) -> Bool {
        guard isWithdraw(t) else { return false }
        if (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "car" {
            return true
        }
        return t.description.hasPrefix("เติมน้ำมันรถยนต์")
    }

    /// เบิกเครื่องปั่นไฟเล็ก (workType=generator)
    static func isGenerator(_ t: Transaction) -> Bool {
        guard isWithdraw(t), !isCarFill(t) else { return false }
        return (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "generator"
    }

    static func isTransfer(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        return (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == transferSubCategory
    }

    static func isSandSieve(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        return (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == sandSieveSubCategory
    }

    struct SandSieveUsage: Equatable, Sendable {
        let dayKey: String
        let liters: Double
        let hours: Double
        let fromPersistedRow: Bool
    }

    /// ลิตรเครื่องร่อนของวันนั้น: แถว SandSieve ถ้ามี ไม่งั้นชั่วโมงร่อน × 18 L
    static func sandSieveUsage(on date: String, transactions: [Transaction]) -> SandSieveUsage? {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == date }
        // Use Self.liters — a local `liters` binding would shadow the static method for the whole function.
        let persistedLiters = dayTx.filter(isSandSieve).reduce(0.0) { $0 + Self.liters(of: $1) }
        if persistedLiters > 0 {
            return SandSieveUsage(dayKey: date, liters: persistedLiters, hours: 0, fromPersistedRow: true)
        }
        guard let sand = CountRecordLogic.buildSandUnit(dayKey: date, transactions: dayTx) else { return nil }
        let hours = CountRecordAnalytics.computeWorkDuration(lapTimes: sand.lapTimes, dayKey: date)?.totalActiveHours ?? 0
        guard hours > 0 else { return nil }
        let inferredLiters = ((hours * sandSieveLitersPerHour) * 100).rounded() / 100
        guard inferredLiters > 0 else { return nil }
        return SandSieveUsage(dayKey: date, liters: inferredLiters, hours: hours, fromPersistedRow: false)
    }

    static func sandSieveLiters(on date: String, transactions: [Transaction]) -> Double {
        sandSieveUsage(on: date, transactions: transactions)?.liters ?? 0
    }

    static func sandSieveLiters(in transactions: [Transaction], dates: [String]) -> Double {
        dates.reduce(0.0) { $0 + sandSieveLiters(on: $1, transactions: transactions) }
    }

    /// ลิตรที่คำนวณจากชั่วโมงร่อน เพราะยังไม่มีแถว SandSieve
    static func inferredSandSieveLiters(on date: String, transactions: [Transaction]) -> Double {
        guard let usage = sandSieveUsage(on: date, transactions: transactions), !usage.fromPersistedRow else { return 0 }
        return usage.liters
    }

    /// แม็คโคร / การใช้น้ำมันรถ — เฉพาะ subCategory VehicleUsage (Flutter parity)
    static func isMacroVehicleUsageRow(_ t: Transaction) -> Bool {
        guard isFuelExpense(t) else { return false }
        return (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == vehicleUsageSubCategory
    }

    static func isVehicleUsage(_ t: Transaction) -> Bool {
        isMacroVehicleUsageRow(t)
    }

    /// วันตัดยอด — ก่อนวันนี้ถือว่าน้ำมันเหลือ 0; ตั้งแต่วันนี้หักถังปกติ (พ.ศ. 1 ส.ค. 2569)
    static let stockCutoverYmd = "2026-08-01"

    /// วันตรวจนับถังสำรองจริง — รีเซ็ตเป็น [reserveAnchorLiters] แล้วจึงนับเฉพาะรายการตั้งแต่วันนี้
    static let reserveAnchorYmd = "2026-08-31"
    static let reserveAnchorLiters: Double = 100
    /// ยอดยกมาถังสำรองดีเซลเมื่อยังไม่ตั้งค่าในระบบ
    static let openingReserveDieselDefault: Double = 100

    static func reserveAnchorIsActive(asOfYmd: String?) -> Bool {
        guard let asOfYmd, !asOfYmd.isEmpty else { return false }
        return asOfYmd >= reserveAnchorYmd
    }

    static func effectiveOpeningReserveDiesel(_ configured: Double?) -> Double {
        let v = configured ?? 0
        return v > 0 ? v : openingReserveDieselDefault
    }

    /// Dual-tank balance — Flutter `computeFuelStockBalance` parity.
    /// `delta = stockIn − withdraw` per tank; reserve diesel uses the 2026-08-31 anchor.
    static func computeBalance(
        transactions: [Transaction],
        opening: FuelStock?,
        asOfYmd: String? = nil
    ) -> Balance {
        struct Bucket {
            var stockIn = 0.0
            var withdraw = 0.0
        }
        var buckets: [String: Bucket] = [:]

        func key(day: String, tank: String, benzine: Bool) -> String {
            "\(day)|\(tank)|\(benzine ? "B" : "D")"
        }

        var sandSieveDays = Set<String>()
        var transferMachineDays = Set<String>()
        var sandByDay: [String: Transaction] = [:]

        for t in transactions {
            let day = String(t.date.prefix(10))
            guard day >= stockCutoverYmd else { continue }
            if isSandSieve(t) { sandSieveDays.insert(day) }
            if isTransfer(t),
               (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "machine" {
                transferMachineDays.insert(day)
            }
            if t.category == "DailyLog",
               (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "Sand" {
                let laps = CountRecordLogic.getLapTimes(t)
                guard !laps.isEmpty else { continue }
                if let prev = sandByDay[day] {
                    if laps.count >= CountRecordLogic.getLapTimes(prev).count {
                        sandByDay[day] = t
                    }
                } else {
                    sandByDay[day] = t
                }
            }
        }

        for t in transactions {
            guard isFuelExpense(t) else { continue }
            let day = String(t.date.prefix(10))
            guard day >= stockCutoverYmd else { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            let isBenzine = (t.fuelType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "benzine"
            let tank = fuelUsageTankOf(t)
            let bucketKey = key(day: day, tank: tank, benzine: isBenzine)

            if isStockIn(t) {
                buckets[bucketKey, default: Bucket()].stockIn += lit
                continue
            }
            if isWithdraw(t) {
                buckets[bucketKey, default: Bucket()].withdraw += lit
                let purpose = (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if purpose == "machine", !transferMachineDays.contains(day) {
                    let reserveKey = key(day: day, tank: tankReserve, benzine: isBenzine)
                    buckets[reserveKey, default: Bucket()].stockIn += lit
                }
                continue
            }
            if isTransfer(t) || isSandSieve(t) || isMacroVehicleUsageRow(t) {
                buckets[bucketKey, default: Bucket()].withdraw += lit
            }
        }

        let asOf = asOfYmd ?? DashboardAggregations.todayYMD()
        let skipPreAnchorSieve = reserveAnchorIsActive(asOfYmd: asOf)
        for (day, sandTx) in sandByDay {
            if sandSieveDays.contains(day) { continue }
            if skipPreAnchorSieve, day < reserveAnchorYmd { continue }
            let laps = CountRecordLogic.getLapTimes(sandTx)
            let hours = CountRecordAnalytics.computeWorkDuration(lapTimes: laps, dayKey: day)?.totalActiveHours ?? 0
            guard hours > 0 else { continue }
            let inferred = ((hours * sandSieveLitersPerHour) * 100).rounded() / 100
            guard inferred > 0 else { continue }
            buckets[key(day: day, tank: tankReserve, benzine: false), default: Bucket()].withdraw += inferred
        }

        var mainDiesel = opening?.diesel ?? 0
        var mainBenzine = opening?.benzine ?? 0
        var reserveBenzine = opening?.benzineReserve ?? 0
        let openingReserve = effectiveOpeningReserveDiesel(opening?.dieselReserve)

        for (bucketKey, b) in buckets {
            let delta = b.stockIn - b.withdraw
            let isReserve = bucketKey.contains("|\(tankReserve)|")
            let isBenzine = bucketKey.hasSuffix("|B")
            if isReserve {
                if isBenzine { reserveBenzine += delta }
            } else if isBenzine {
                mainBenzine += delta
            } else {
                mainDiesel += delta
            }
        }

        // Reserve diesel: Flutter applyFuelReserveDieselAnchor
        var byDay: [String: Double] = [:]
        for (bucketKey, b) in buckets {
            let parts = bucketKey.split(separator: "|").map(String.init)
            guard parts.count >= 3, parts[1] == tankReserve, !bucketKey.hasSuffix("|B") else { continue }
            let delta = b.stockIn - b.withdraw
            if delta == 0 { continue }
            byDay[parts[0], default: 0] += delta
        }

        let reserveDiesel: Double
        let postDays = byDay.keys.filter { $0 >= reserveAnchorYmd }.sorted()
        if reserveAnchorIsActive(asOfYmd: asOf) || !postDays.isEmpty {
            reserveDiesel = postDays.reduce(reserveAnchorLiters) { $0 + (byDay[$1] ?? 0) }
        } else {
            reserveDiesel = byDay.keys.sorted().reduce(openingReserve) { $0 + (byDay[$1] ?? 0) }
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
            let lit = liters(of: t)
            guard lit > 0 else { continue }
            if isWithdraw(t), (t.workType ?? "").lowercased() == "machine" {
                machineWithdraw += lit
            } else if isTransfer(t), (t.workType ?? "").lowercased() == "machine" {
                if !isStockIn(t) { machineWithdraw += lit }
            } else if isMacroVehicleUsageRow(t) {
                if let filterTank, fuelUsageTankOf(t) != filterTank { continue }
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

    // MARK: - Focus calendar day marks (น้ำมัน)

    struct DayFuelMark: Equatable, Sendable {
        var stockIn: Bool = false
        var withdraw: Bool = false
        var sandSieve: Bool = false
        var macroUsage: Bool = false

        var isEmpty: Bool { !stockIn && !withdraw && !sandSieve && !macroUsage }

        static let none = DayFuelMark()
    }

    /// Per-day fuel activity marks for the oil report date picker.
    static func dayFuelMarks(
        inMonth monthStart: Date,
        transactions: [Transaction]
    ) -> [String: DayFuelMark] {
        let cal = DashboardAggregations.gregorian
        let year = cal.component(.year, from: monthStart)
        let month = cal.component(.month, from: monthStart)
        let prefix = String(format: "%04d-%02d-", year, month)

        var byDay: [String: [Transaction]] = [:]
        for t in transactions {
            let key = String(t.date.prefix(10))
            guard key.hasPrefix(prefix) else { continue }
            byDay[key, default: []].append(t)
        }

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first)
        else { return [:] }

        var out: [String: DayFuelMark] = [:]
        for d in range {
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            let dayTx = byDay[key] ?? []
            var mark = DayFuelMark.none
            for t in dayTx where isFuelExpense(t) {
                if isStockIn(t) {
                    mark.stockIn = true
                } else if isWithdraw(t), !isCarFill(t) {
                    mark.withdraw = true
                } else if isVehicleUsage(t), !isCarFill(t), !isSandSieve(t) {
                    mark.macroUsage = true
                }
            }
            // Pass dayTx only — sandSieveUsage filters/scans its input; full list per day was O(days × n).
            if sandSieveLiters(on: key, transactions: dayTx) > 0 {
                mark.sandSieve = true
            }
            out[key] = mark
        }
        return out
    }

    // MARK: - Monthly usage report

    enum MonthlyLineKind: String, Equatable, Sendable {
        case carFill
        case generator
        case macro
    }

    struct MonthlyLineItem: Identifiable, Equatable, Sendable {
        let id: String
        let kind: MonthlyLineKind
        let title: String
        let liters: Double
        let time: String?
        let tankLabel: String?
        let detail: String?
    }

    struct MonthlyDayRow: Identifiable, Equatable, Sendable {
        var id: String { date }
        let date: String
        let liters: Double
        let subtitle: String?
        let items: [MonthlyLineItem]

        init(date: String, liters: Double, subtitle: String? = nil, items: [MonthlyLineItem] = []) {
            self.date = date
            self.liters = liters
            self.subtitle = subtitle
            self.items = items
        }
    }

    struct MonthlyVehicleRow: Identifiable, Equatable, Sendable {
        var id: String { vehicleId }
        let vehicleId: String
        let liters: Double
    }

    struct MonthlyUsageReport: Equatable, Sendable {
        let monthKey: String
        /// เติมรถยนต์อย่างเดียว
        let carFillLiters: Double
        /// เบิกปั่นไฟเล็ก
        let generatorLiters: Double
        let machineLiters: Double
        let macroLiters: Double
        let carFillByDay: [MonthlyDayRow]
        let machineByDay: [MonthlyDayRow]
        let macroByDay: [MonthlyDayRow]
        let carFillByVehicle: [MonthlyVehicleRow]
        let macroByVehicle: [MonthlyVehicleRow]

        /// รถยนต์ + ปั่นไฟเล็ก (หมวดเดียวกันในรายงาน)
        var carAndGeneratorLiters: Double { carFillLiters + generatorLiters }
        var totalLiters: Double { carAndGeneratorLiters + machineLiters + macroLiters }

        static let empty = MonthlyUsageReport(
            monthKey: "",
            carFillLiters: 0,
            generatorLiters: 0,
            machineLiters: 0,
            macroLiters: 0,
            carFillByDay: [],
            machineByDay: [],
            macroByDay: [],
            carFillByVehicle: [],
            macroByVehicle: []
        )
    }

    private static func tankLabel(of t: Transaction) -> String {
        normalizeTank(t.fuelTank) == tankReserve ? "ถังสำรอง" : "ถังหลัก"
    }

    private static func lineTime(of t: Transaction) -> String? {
        let details = (t.workDetails ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { return details }
        if let created = t.createdAt, created.count >= 16 {
            return String(created.prefix(16)).replacingOccurrences(of: "T", with: " ")
        }
        return nil
    }

    private static func monthlyLine(from t: Transaction, kind: MonthlyLineKind) -> MonthlyLineItem {
        let lit = liters(of: t)
        let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String
        switch kind {
        case .carFill:
            title = vid.isEmpty ? "รถยนต์" : vid
        case .generator:
            title = "ปั่นไฟเล็ก"
        case .macro:
            title = vid.isEmpty ? "แม็คโคร" : vid
        }
        let desc = stripRecorder(t.description)
        let detail: String? = {
            guard !desc.isEmpty, desc != title else { return nil }
            return desc
        }()
        return MonthlyLineItem(
            id: t.id,
            kind: kind,
            title: title,
            liters: lit,
            time: lineTime(of: t),
            tankLabel: tankLabel(of: t),
            detail: detail
        )
    }

    /// สรุปรายเดือน: เติมรถยนต์+ปั่นไฟ · เครื่องร่อน · แม็คโคร
    static func buildMonthly(monthStart: Date, transactions: [Transaction]) -> MonthlyUsageReport {
        let cal = DashboardAggregations.gregorian
        let year = cal.component(.year, from: monthStart)
        let month = cal.component(.month, from: monthStart)
        let monthKey = String(format: "%04d-%02d", year, month)

        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let first = cal.date(from: comps),
              let dayRange = cal.range(of: .day, in: .month, for: first)
        else { return .empty }

        let dates = dayRange.map { day -> String in
            String(format: "%04d-%02d-%02d", year, month, day)
        }

        var carByDay: [String: Double] = [:]
        var genByDay: [String: Double] = [:]
        var macroByDay: [String: Double] = [:]
        var carByVehicle: [String: Double] = [:]
        var genByLabel: [String: Double] = [:]
        var macroByVehicle: [String: Double] = [:]
        var carItemsByDay: [String: [MonthlyLineItem]] = [:]
        var macroItemsByDay: [String: [MonthlyLineItem]] = [:]

        for t in transactions {
            let day = String(t.date.prefix(10))
            guard day.hasPrefix(monthKey) else { continue }
            guard isFuelExpense(t) else { continue }
            let lit = liters(of: t)
            guard lit > 0 else { continue }

            if isCarFill(t) {
                carByDay[day, default: 0] += lit
                let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                carByVehicle[vid.isEmpty ? "ไม่ระบุรถ" : vid, default: 0] += lit
                carItemsByDay[day, default: []].append(monthlyLine(from: t, kind: .carFill))
            } else if isGenerator(t) {
                genByDay[day, default: 0] += lit
                genByLabel["ปั่นไฟเล็ก", default: 0] += lit
                carItemsByDay[day, default: []].append(monthlyLine(from: t, kind: .generator))
            } else if isVehicleUsage(t), !isSandSieve(t), !isCarFill(t) {
                macroByDay[day, default: 0] += lit
                let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                macroByVehicle[vid.isEmpty ? "ไม่ระบุรถ" : vid, default: 0] += lit
                macroItemsByDay[day, default: []].append(monthlyLine(from: t, kind: .macro))
            }
        }

        var machineByDay: [MonthlyDayRow] = []
        var machineTotal = 0.0
        var monthTxByDay: [String: [Transaction]] = [:]
        for t in transactions {
            let day = String(t.date.prefix(10))
            guard day.hasPrefix(monthKey) else { continue }
            monthTxByDay[day, default: []].append(t)
        }
        for date in dates {
            guard let usage = sandSieveUsage(on: date, transactions: monthTxByDay[date] ?? []) else { continue }
            machineTotal += usage.liters
            let subtitle: String? = usage.fromPersistedRow
                ? nil
                : "\(formatLiters(usage.hours)) ชม. × \(formatLiters(sandSieveLitersPerHour)) L"
            machineByDay.append(MonthlyDayRow(date: date, liters: usage.liters, subtitle: subtitle))
        }
        machineByDay.sort { $0.date > $1.date }

        let carFillLiters = carByDay.values.reduce(0, +)
        let generatorLiters = genByDay.values.reduce(0, +)
        let macroLiters = macroByDay.values.reduce(0, +)

        let allCarDays = Set(carByDay.keys).union(genByDay.keys)
        let carFillByDay: [MonthlyDayRow] = allCarDays.map { day in
            let items = (carItemsByDay[day] ?? []).sorted {
                ($0.time ?? "") > ($1.time ?? "")
            }
            return MonthlyDayRow(
                date: day,
                liters: (carByDay[day] ?? 0) + (genByDay[day] ?? 0),
                subtitle: nil,
                items: items
            )
        }.sorted { $0.date > $1.date }

        let macroDayRows: [MonthlyDayRow] = macroByDay.map { day, lit in
            let items = (macroItemsByDay[day] ?? []).sorted {
                ($0.time ?? "") > ($1.time ?? "")
            }
            return MonthlyDayRow(date: day, liters: lit, subtitle: nil, items: items)
        }.sorted { $0.date > $1.date }

        var vehicleRows = carByVehicle
            .map { MonthlyVehicleRow(vehicleId: $0.key, liters: $0.value) }
        vehicleRows.append(contentsOf: genByLabel.map { MonthlyVehicleRow(vehicleId: $0.key, liters: $0.value) })
        vehicleRows.sort { $0.liters > $1.liters }

        return MonthlyUsageReport(
            monthKey: monthKey,
            carFillLiters: carFillLiters,
            generatorLiters: generatorLiters,
            machineLiters: machineTotal,
            macroLiters: macroLiters,
            carFillByDay: carFillByDay,
            machineByDay: machineByDay,
            macroByDay: macroDayRows,
            carFillByVehicle: vehicleRows,
            macroByVehicle: macroByVehicle
                .map { MonthlyVehicleRow(vehicleId: $0.key, liters: $0.value) }
                .sorted { $0.liters > $1.liters }
        )
    }
}
