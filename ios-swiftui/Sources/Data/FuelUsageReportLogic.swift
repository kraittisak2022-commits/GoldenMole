import Foundation

/// Web parity — `src/utils/fuelUsageReport.ts` + `computeFuelStockBalances` in `src/utils/index.ts`.
enum FuelUsageReportLogic {
    enum Kind: String, Sendable, Equatable {
        case stockIn
        case vehicle
        case withdraw
        case sandSieve
        case otherOut
    }

    enum FuelTypeFilter: String, Sendable {
        case diesel = "Diesel"
        case benzine = "Benzine"
    }

    enum Tank: String, Sendable {
        case main
        case reserve
    }

    struct Filters: Sendable {
        var start: String
        var end: String
        var vehicleId: String = ""
        var fuelType: FuelTypeFilter?
        var kind: Kind?
        var estimatedSieveByDay: [String: Double] = [:]
        var cars: [String] = []
        var catalog: [VehicleCatalogRow] = []
    }

    struct Row: Identifiable, Sendable {
        let id: String
        let date: String
        let kind: Kind
        let fuelType: FuelTypeFilter
        let tank: Tank
        let vehicleId: String
        let liters: Double
        let amount: Double
        let description: String
        let subCategory: String?
        let workType: String?
        let estimated: Bool
    }

    struct Totals: Sendable {
        var stockInLiters: Double = 0
        var stockInAmount: Double = 0
        var vehicleLiters: Double = 0
        var vehicleAmount: Double = 0
        var withdrawLiters: Double = 0
        var sandSieveLiters: Double = 0
        var otherOutLiters: Double = 0
        var usageLiters: Double = 0
        var usageAmount: Double = 0
        var count: Int = 0
    }

    struct VehicleRow: Identifiable, Sendable {
        var id: String { vehicleId }
        let vehicleId: String
        let liters: Double
        let amount: Double
        let count: Int
    }

    struct DayRow: Identifiable, Sendable {
        var id: String { date }
        let date: String
        let stockInLiters: Double
        let usageLiters: Double
        let usageAmount: Double
        let count: Int
    }

    struct Report: Sendable {
        let rows: [Row]
        let totals: Totals
        let byVehicle: [VehicleRow]
        let byDay: [DayRow]
    }

    struct StockBalances: Sendable {
        var diesel: Double
        var benzine: Double
        var dieselReserve: Double
        var benzineReserve: Double
        var reserveShortfallLiters: Double
    }

    private static let unnamedVehicle = "ไม่ระบุรถ"
    private static let taplienLegacyIds: Set<String> = [
        "รถตาเปลื่ยน",
        "ISUZU KB",
        "รถISUZUKB",
        "ISUZUตา",
        "IsuzuKB",
    ]

    static func normalizeDate(_ d: String?) -> String {
        guard let d, d.count >= 10 else { return d ?? "" }
        return String(d.prefix(10))
    }

    static func kindLabel(_ kind: Kind) -> String {
        switch kind {
        case .stockIn: return "รับเข้า (ถังหลัก)"
        case .vehicle: return "ใช้แล้ว (รถ/แม็คโคร)"
        case .withdraw: return "เบิกไปถังสำรอง"
        case .sandSieve: return "ใช้แล้ว (ร่อนทราย)"
        case .otherOut: return "ใช้แล้ว (อื่น ๆ)"
        }
    }

    static func tankLabel(_ tank: Tank) -> String {
        tank == .reserve ? "ถังสำรอง" : "ถังหลัก"
    }

    static func fuelTypeLabel(_ fuelType: FuelTypeFilter) -> String {
        fuelType == .benzine ? "เบนซิน" : "ดีเซล"
    }

    static func inferFuelMovement(_ t: Transaction) -> String {
        guard t.category == "Fuel" else { return "stock_out" }
        let mov = (t.fuelMovement ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mov == "stock_in" || mov == "stock_out" {
            return mov
        }
        let vehicle = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return vehicle.isEmpty ? "stock_in" : "stock_out"
    }

    static func normalizeFuelTank(_ raw: String?) -> Tank {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v == FuelLogic.tankReserve || v == "สำรอง" { return .reserve }
        return .main
    }

    private static func normalizedSubCategory(_ t: Transaction) -> String {
        (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func subEquals(_ t: Transaction, _ expected: String) -> Bool {
        normalizedSubCategory(t).caseInsensitiveCompare(expected) == .orderedSame
    }

    /// โอนหลัก→สำรอง / เบิกเติมเครื่องจักร — ยังไม่นับเป็นใช้แล้ว
    static func isMachineReserveTransfer(_ t: Transaction) -> Bool {
        guard t.category == "Fuel", t.type == .expense else { return false }
        let purpose = withdrawPurpose(t)
        let movement = inferFuelMovement(t)
        let desc = t.description

        if subEquals(t, FuelLogic.transferSubCategory) {
            // ฝั่งรับเข้าถังสำรองไม่นับซ้ำ
            if movement == "stock_in" { return false }
            return true
        }
        if subEquals(t, FuelLogic.withdrawSubCategory), purpose == "machine" {
            return true
        }
        if desc.contains("โอนถังหลัก") || desc.contains("เติมเครื่องจักร") || desc.contains("รับเข้าถังสำรองจากถังหลัก") {
            return movement != "stock_in"
        }
        return false
    }

    static func fuelUsageTankOf(_ t: Transaction) -> Tank {
        FuelLogic.fuelUsageTankOf(t) == FuelLogic.tankReserve ? .reserve : .main
    }

    static func normalizeVehicleId(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if taplienLegacyIds.contains(v) { return "รถตาเปลื่ยน (ISUZU KB)" }
        return v
    }

    private static func resolveFuelVehicleLabel(
        _ t: Transaction,
        kind: Kind,
        cars: [String],
        catalog: [VehicleCatalogRow],
        nameById: [String: String]
    ) -> String {
        let raw = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            switch kind {
            case .sandSieve: return FuelLogic.sandSieveVehicleId
            case .vehicle, .otherOut: return unnamedVehicle
            default: return ""
            }
        }
        let label = CountRecordLogic.vehicleDisplayLabel(
            vehicleId: t.vehicleId,
            vehicleName: t.vehicleName,
            cars: cars,
            catalog: catalog,
            description: t.description,
            nameById: nameById
        )
        if !label.isEmpty, !CountRecordLogic.looksLikeCatalogVehicleId(label) {
            return label
        }
        return normalizeVehicleId(raw)
    }

    private static func withdrawPurpose(_ t: Transaction) -> String {
        (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func classifyFuelTx(_ t: Transaction) -> Kind? {
        guard t.category == "Fuel", t.type == .expense else { return nil }

        let movement = inferFuelMovement(t)
        let tank = fuelUsageTankOf(t)
        let purpose = withdrawPurpose(t)

        // คู่โอนเข้าถังสำรอง — ไม่แสดงซ้ำ (ฝั่ง stock_out นับเป็นเบิก)
        if subEquals(t, FuelLogic.transferSubCategory), movement == "stock_in" {
            return nil
        }

        // รับเข้าถังหลักจริง (ซื้อ/เพิ่มสต็อก)
        if subEquals(t, FuelLogic.stockInSubCategory)
            || (movement == "stock_in" && tank == .main && !subEquals(t, FuelLogic.transferSubCategory)) {
            return .stockIn
        }

        // โอนหลัก → สำรอง (เติมเครื่องจักร) = เบิก ยังไม่ใช้
        if isMachineReserveTransfer(t) {
            return .withdraw
        }
        if subEquals(t, FuelLogic.transferSubCategory), movement == "stock_out" {
            return .withdraw
        }
        if subEquals(t, FuelLogic.withdrawSubCategory), purpose == "machine" {
            return .withdraw
        }

        // ใช้แล้วจากถังสำรอง (ร่อนทราย)
        if subEquals(t, FuelLogic.sandSieveSubCategory) {
            return .sandSieve
        }

        // เมนูเบิกน้ำมันที่ตัดออกจากถังหลักแล้ว = ใช้แล้ว (รถ / ปั่นไฟ / อื่น)
        if subEquals(t, FuelLogic.withdrawSubCategory) {
            if purpose == "car" { return .vehicle }
            return .otherOut
        }

        // การใช้น้ำมันรถ / แม็คโคร
        if subEquals(t, FuelLogic.vehicleUsageSubCategory)
            || !(t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .vehicle
        }

        if movement == "stock_in" { return .stockIn }
        return .otherOut
    }

    private static func resolveFuelType(_ t: Transaction) -> FuelTypeFilter {
        (t.fuelType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "benzine"
            ? .benzine : .diesel
    }

    private static func isUsageKind(_ kind: Kind) -> Bool {
        kind == .vehicle || kind == .sandSieve || kind == .otherOut
    }

    private static func sandLapTimes(_ t: Transaction) -> [String] {
        guard let raw = t.workAssignments?["lapTimes"] else { return [] }
        return raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Web `estimateSieveUsageByDay` — inferred liters for days without persisted SandSieve row.
    static func estimateSieveByDay(transactions: [Transaction]) -> [String: Double] {
        var sandSieveDays = Set<String>()
        var sandByDay: [String: Transaction] = [:]

        for t in transactions {
            let day = normalizeDate(t.date)
            guard !day.isEmpty, day >= FuelLogic.stockCutoverYmd else { continue }

            if t.category == "Fuel", t.type == .expense,
               (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == FuelLogic.sandSieveSubCategory {
                sandSieveDays.insert(day)
                continue
            }

            guard t.category == "DailyLog",
                  (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "Sand"
            else { continue }

            let laps = sandLapTimes(t)
            guard !laps.isEmpty else { continue }
            if let prev = sandByDay[day] {
                let prevLen = sandLapTimes(prev).count
                if laps.count >= prevLen { sandByDay[day] = t }
            } else {
                sandByDay[day] = t
            }
        }

        var out: [String: Double] = [:]
        let skipPreAnchor = FuelLogic.reserveAnchorIsActive(asOfYmd: DashboardAggregations.todayYMD())
        for (day, sandTx) in sandByDay {
            if sandSieveDays.contains(day) { continue }
            if skipPreAnchor, day < FuelLogic.reserveAnchorYmd { continue }
            let laps = sandLapTimes(sandTx)
            let hours = CountRecordAnalytics.computeWorkDuration(lapTimes: laps, dayKey: day)?.totalActiveHours ?? 0
            guard hours > 0 else { continue }
            let liters = (hours * FuelLogic.sandSieveLitersPerHour * 100).rounded() / 100
            if liters > 0 { out[day] = liters }
        }
        return out
    }

    static func buildReport(
        transactions: [Transaction],
        filters: Filters
    ) -> Report {
        let start = normalizeDate(filters.start)
        let end = normalizeDate(filters.end)
        let vehicleFilter = filters.vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fuelTypeFilter = filters.fuelType
        let kindFilter = filters.kind
        let nameById = CountRecordLogic.vehicleNameIndex(from: transactions)

        var rows: [Row] = []
        for t in transactions {
            guard let kind = classifyFuelTx(t) else { continue }
            let date = normalizeDate(t.date)
            guard date >= start, date <= end else { continue }

            let vehicleId = resolveFuelVehicleLabel(
                t,
                kind: kind,
                cars: filters.cars,
                catalog: filters.catalog,
                nameById: nameById
            )

            if !vehicleFilter.isEmpty, vehicleId != vehicleFilter { continue }
            let fuelType = resolveFuelType(t)
            if let fuelTypeFilter, fuelType != fuelTypeFilter { continue }
            if let kindFilter, kind != kindFilter { continue }

            let desc = (t.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (t.workDetails ?? "") : t.description)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            rows.append(Row(
                id: t.id,
                date: date,
                kind: kind,
                fuelType: fuelType,
                tank: fuelUsageTankOf(t),
                vehicleId: vehicleId,
                liters: DashboardAggregations.fuelTxToLiters(t),
                amount: t.amount,
                description: desc,
                subCategory: (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                workType: (t.workType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                estimated: false
            ))
        }

        let estimated = filters.estimatedSieveByDay
        if vehicleFilter.isEmpty,
           fuelTypeFilter == nil || fuelTypeFilter == .diesel,
           kindFilter == nil || kindFilter == .sandSieve {
            for (dayRaw, liters) in estimated {
                let date = normalizeDate(dayRaw)
                guard liters > 0, date >= start, date <= end else { continue }
                rows.append(Row(
                    id: "\(date)_fuel_sand_sieve_est",
                    date: date,
                    kind: .sandSieve,
                    fuelType: .diesel,
                    tank: .reserve,
                    vehicleId: FuelLogic.sandSieveVehicleId,
                    liters: liters,
                    amount: 0,
                    description: "ประมาณจากชั่วโมงร่อนทราย \(Int(FuelLogic.sandSieveLitersPerHour)) ลิตร/ชม.",
                    subCategory: FuelLogic.sandSieveSubCategory,
                    workType: nil,
                    estimated: true
                ))
            }
        }

        rows.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }

        return aggregateRows(rows)
    }

    static func buildReport(
        transactions: [Transaction],
        start: String,
        end: String,
        allTransactionsForEstimate: [Transaction]? = nil,
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = []
    ) -> Report {
        let source = allTransactionsForEstimate ?? transactions
        let estimated = estimateSieveByDay(transactions: source)
        return buildReport(
            transactions: transactions,
            filters: Filters(
                start: start,
                end: end,
                estimatedSieveByDay: estimated,
                cars: cars,
                catalog: catalog
            )
        )
    }

    static func dayReport(transactions: [Transaction], dayKey: String) -> Report {
        buildReport(transactions: transactions, start: dayKey, end: dayKey)
    }

    private static func aggregateRows(_ rows: [Row]) -> Report {
        var totals = Totals()
        totals.count = rows.count
        var vehicleMap: [String: (liters: Double, amount: Double, count: Int)] = [:]
        var dayMap: [String: (stockInLiters: Double, usageLiters: Double, usageAmount: Double, count: Int)] = [:]

        for row in rows {
            switch row.kind {
            case .stockIn:
                totals.stockInLiters += row.liters
                totals.stockInAmount += row.amount
            case .vehicle:
                totals.vehicleLiters += row.liters
                totals.vehicleAmount += row.amount
            case .withdraw:
                totals.withdrawLiters += row.liters
            case .sandSieve:
                totals.sandSieveLiters += row.liters
            case .otherOut:
                totals.otherOutLiters += row.liters
            }

            if isUsageKind(row.kind) {
                totals.usageLiters += row.liters
                totals.usageAmount += row.amount
            }

            if !row.vehicleId.isEmpty {
                var prev = vehicleMap[row.vehicleId] ?? (0, 0, 0)
                prev.liters += row.liters
                prev.amount += row.amount
                prev.count += 1
                vehicleMap[row.vehicleId] = prev
            }

            var day = dayMap[row.date] ?? (0, 0, 0, 0)
            day.count += 1
            if row.kind == .stockIn { day.stockInLiters += row.liters }
            if isUsageKind(row.kind) {
                day.usageLiters += row.liters
                day.usageAmount += row.amount
            }
            dayMap[row.date] = day
        }

        let byVehicle = vehicleMap.map { VehicleRow(vehicleId: $0.key, liters: $0.value.liters, amount: $0.value.amount, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.liters != rhs.liters { return lhs.liters > rhs.liters }
                return lhs.vehicleId.localizedCompare(rhs.vehicleId) == .orderedAscending
            }

        let byDay = dayMap.map { DayRow(date: $0.key, stockInLiters: $0.value.stockInLiters, usageLiters: $0.value.usageLiters, usageAmount: $0.value.usageAmount, count: $0.value.count) }
            .sorted { $0.date < $1.date }

        return Report(rows: rows, totals: totals, byVehicle: byVehicle, byDay: byDay)
    }

    /// Web `computeFuelStockBalances` — remaining main/reserve through ledger (Flutter parity via FuelLogic).
    static func computeStockBalances(
        transactions: [Transaction],
        opening: FuelStock?,
        estimatedSieveByDay: [String: Double] = [:],
        asOfYmd: String? = nil
    ) -> StockBalances {
        // Prefer FuelLogic path (anchor + tank routing). Optional estimated map is for callers
        // that already filtered sieve days; FuelLogic re-infers from sand laps when empty.
        _ = estimatedSieveByDay
        let bal = FuelLogic.computeBalance(
            transactions: transactions,
            opening: opening,
            asOfYmd: asOfYmd ?? DashboardAggregations.todayYMD()
        )
        let reserveShortfall = max(0, -bal.reserveDiesel) + max(0, -bal.reserveBenzine)
        return StockBalances(
            diesel: bal.mainDiesel,
            benzine: bal.mainBenzine,
            dieselReserve: bal.reserveDiesel,
            benzineReserve: bal.reserveBenzine,
            reserveShortfallLiters: reserveShortfall
        )
    }

    static func stockBalancesThrough(
        endDate: String,
        transactions: [Transaction],
        opening: FuelStock?
    ) -> StockBalances {
        let end = normalizeDate(endDate)
        let through = transactions.filter { normalizeDate($0.date) <= end }
        return computeStockBalances(
            transactions: through,
            opening: opening,
            asOfYmd: end
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
