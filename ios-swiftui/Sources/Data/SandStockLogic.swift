import Foundation

/// Sand stock pond (บ่อสต๊อก) balance in cubic meters (คิว / ลบ.ม.).
///
/// - **IN** — vehicle trip rows that dump sand into the pond
/// - **OUT** — sand sieve / wash rows that scoop sand out of the pond
///
/// Remaining = opening + Σ(in) − Σ(out) through the as-of date.
enum SandStockLogic {
    static let openingStockDefaultsKey = "sand_stock_opening_cubic_v1"
    static let pondCapacityDefaultsKey = "sand_stock_pond_capacity_cubic_v1"
    static let defaultPondCapacityCubic: Double = 500
    static let unitLabel = "คิว"
    static let maxFeedEvents = 8
    /// Stock outflow keeps 70% of sieve rounds (subtract 30% first).
    static let sieveOutKeepRatio = 0.70

    static func applySieveOutHaircut(_ cubic: Double) -> Double {
        max(0, cubic * sieveOutKeepRatio)
    }

    enum PaceStatus: String, Sendable {
        case keepingUp
        case tight
        case fallingBehind
        case surplusBuilding
        case idle

        var title: String {
            switch self {
            case .keepingUp: return "ขนทัน"
            case .tight: return "กระชั้น"
            case .fallingBehind: return "ขนไม่ทัน"
            case .surplusBuilding: return "ขนเกินใช้"
            case .idle: return "ยังไม่มีข้อมูล"
            }
        }

        var detail: String {
            switch self {
            case .keepingUp: return "ปริมาณขนเข้าใกล้เคียงหรือมากกว่าที่ร่อนออก — บ่อไม่น่าแห้ง"
            case .tight: return "ร่อนออกเร็วกว่าขนเข้าเล็กน้อย — ควรเฝ้าติดตาม"
            case .fallingBehind: return "ร่อนออกเร็วกว่าขนเข้าชัดเจน — เสี่ยงทรายในบ่อหมด"
            case .surplusBuilding: return "ขนเข้ามากกว่าที่ร่อน — ทรายในบ่อกำลังสะสม"
            case .idle: return "ยังไม่มีการขนเข้าหรือร่อนออกในช่วงนี้"
            }
        }
    }

    enum FeedDirection: String, Sendable, Equatable {
        case inbound
        case outbound

        var title: String {
            switch self {
            case .inbound: return "ขนเข้า"
            case .outbound: return "ร่อนออก"
            }
        }
    }

    struct FeedEvent: Identifiable, Sendable, Equatable {
        let id: String
        let direction: FeedDirection
        let cubic: Double
        let label: String
        let timeLabel: String
        let sortKey: String
    }

    struct DayPoint: Identifiable, Sendable, Equatable {
        var id: String { date }
        let date: String
        let label: String
        let inCubic: Double
        let outCubic: Double
        let remainingEndOfDay: Double
    }

    struct Snapshot: Sendable, Equatable {
        let asOfDate: String
        let openingCubic: Double
        let pondCapacityCubic: Double
        let fillRatio: Double
        let remainingCubic: Double
        let periodInCubic: Double
        let periodOutCubic: Double
        let periodNetCubic: Double
        let todayInCubic: Double
        let todayOutCubic: Double
        /// คงเหลือท้ายวันก่อนวันโฟกัส (ต้นวัน asOf)
        let priorRemainingCubic: Double
        let avgDailyInCubic: Double
        let avgDailyOutCubic: Double
        let pace: PaceStatus
        let daysUntilEmpty: Double?
        let insight: String
        let series: [DayPoint]
        let recentEvents: [FeedEvent]

        static let empty = Snapshot(
            asOfDate: "",
            openingCubic: 0,
            pondCapacityCubic: defaultPondCapacityCubic,
            fillRatio: 0,
            remainingCubic: 0,
            periodInCubic: 0,
            periodOutCubic: 0,
            periodNetCubic: 0,
            todayInCubic: 0,
            todayOutCubic: 0,
            priorRemainingCubic: 0,
            avgDailyInCubic: 0,
            avgDailyOutCubic: 0,
            pace: .idle,
            daysUntilEmpty: nil,
            insight: "ยังไม่มีข้อมูลสต๊อก",
            series: [],
            recentEvents: []
        )
    }

    // MARK: - Device-local settings

    static func loadOpeningCubic() -> Double {
        let value = UserDefaults.standard.double(forKey: openingStockDefaultsKey)
        return value.isFinite ? max(0, value) : 0
    }

    static func saveOpeningCubic(_ value: Double) {
        let clamped = value.isFinite ? max(0, value) : 0
        UserDefaults.standard.set(clamped, forKey: openingStockDefaultsKey)
    }

    static func loadPondCapacityCubic() -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: pondCapacityDefaultsKey) == nil {
            return defaultPondCapacityCubic
        }
        let value = defaults.double(forKey: pondCapacityDefaultsKey)
        guard value.isFinite, value > 0 else { return defaultPondCapacityCubic }
        return value
    }

    static func savePondCapacityCubic(_ value: Double) {
        let clamped = value.isFinite ? max(1, value) : defaultPondCapacityCubic
        UserDefaults.standard.set(clamped, forKey: pondCapacityDefaultsKey)
    }

    static func fillRatio(remaining: Double, capacity: Double) -> Double {
        let cap = max(capacity, 1)
        return min(1, max(0, remaining / cap))
    }

    // MARK: - Row helpers

    static func isTripInRow(_ t: Transaction) -> Bool {
        if CountRecordLogic.isCountRecordVehicleRow(t) { return true }
        return t.category == "Vehicle"
    }

    static func isWashOutRow(_ t: Transaction) -> Bool {
        t.category == "DailyLog" &&
            (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sand"
    }

    /// Wash-form cubic rows that are not the count-record sieve tap.
    static func isLegacyWashCubicRow(_ t: Transaction) -> Bool {
        isWashOutRow(t) && !CountRecordLogic.isCountRecordSandTapRow(t)
    }

    /// Prefer stored cubic fields; fall back to trips × cubic/trip when both are present.
    static func tripCubicIn(_ t: Transaction) -> Double {
        if let c = t.perCarCubic, c > 0 { return c }
        if let c = t.totalCubic, c > 0 { return c }
        let trips = t.perCarTrips
            ?? t.tripCount
            ?? ((t.tripMorning ?? 0) + (t.tripAfternoon ?? 0))
        let cpt = t.cubicPerTrip ?? 0
        if trips > 0, cpt > 0 { return trips * cpt }
        return 0
    }

    static func washCubicOut(_ t: Transaction) -> Double {
        DashboardAggregations.sandWashedCubic(t)
    }

    // MARK: - Aggregations

    static func cubicIn(on date: String, transactions: [Transaction]) -> Double {
        transactions
            .filter { String($0.date.prefix(10)) == date && isTripInRow($0) }
            .reduce(0.0) { $0 + tripCubicIn($1) }
    }

    /// ร่อนออก = รอบจากเมนูร่อนทราย (1 รอบ = 1 คิว) แล้วหัก 30%. Fallback คิวฟอร์มล้างทรายเมื่อไม่มีแถวนับร่อน.
    static func cubicOut(on date: String, transactions: [Transaction]) -> Double {
        let dayTx = transactions.filter { String($0.date.prefix(10)) == date }
        if let sand = CountRecordLogic.buildSandUnit(dayKey: date, transactions: dayTx), sand.rounds > 0 {
            return applySieveOutHaircut(Double(sand.rounds))
        }
        let raw = dayTx
            .filter(isLegacyWashCubicRow)
            .reduce(0.0) { $0 + washCubicOut($1) }
        return applySieveOutHaircut(raw)
    }

    static func cubicOutBefore(_ startDate: String, transactions: [Transaction]) -> Double {
        let priorDates = Set(
            transactions
                .map { String($0.date.prefix(10)) }
                .filter { !$0.isEmpty && $0 < startDate }
        )
        return priorDates.reduce(0.0) { $0 + cubicOut(on: $1, transactions: transactions) }
    }

    static func buildRecentEvents(
        dayKey: String,
        transactions: [Transaction],
        limit: Int = maxFeedEvents
    ) -> [FeedEvent] {
        var events: [FeedEvent] = []
        let dayTx = transactions.filter { String($0.date.prefix(10)) == dayKey }
        for t in dayTx {
            if isTripInRow(t) {
                let cubic = tripCubicIn(t)
                guard cubic > 0 else { continue }
                let vehicle = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                events.append(
                    FeedEvent(
                        id: "in-\(t.id)",
                        direction: .inbound,
                        cubic: cubic,
                        label: vehicle.isEmpty ? "เที่ยวรถ" : vehicle,
                        timeLabel: formatEventTime(t),
                        sortKey: eventSortKey(t)
                    )
                )
            }
        }
        if let sand = CountRecordLogic.buildSandUnit(dayKey: dayKey, transactions: dayTx), sand.rounds > 0,
           let tap = dayTx.first(where: { $0.id == sand.id }) {
            events.append(
                FeedEvent(
                    id: "out-\(sand.id)",
                    direction: .outbound,
                    cubic: applySieveOutHaircut(Double(sand.rounds)),
                    label: "ร่อนทราย \(sand.rounds) รอบ −30%",
                    timeLabel: formatEventTime(tap),
                    sortKey: eventSortKey(tap)
                )
            )
        } else {
            for t in dayTx where isLegacyWashCubicRow(t) {
                let cubic = applySieveOutHaircut(washCubicOut(t))
                guard cubic > 0 else { continue }
                events.append(
                    FeedEvent(
                        id: "out-\(t.id)",
                        direction: .outbound,
                        cubic: cubic,
                        label: "ร่อนทราย −30%",
                        timeLabel: formatEventTime(t),
                        sortKey: eventSortKey(t)
                    )
                )
            }
        }
        return Array(
            events
                .sorted { $0.sortKey > $1.sortKey }
                .prefix(max(1, limit))
        )
    }

    static func build(
        filter: DateFilter,
        transactions: [Transaction],
        openingCubic: Double = loadOpeningCubic(),
        pondCapacityCubic: Double = loadPondCapacityCubic()
    ) -> Snapshot {
        let dates = DashboardAggregations.enumerateDates(in: filter)
        guard !dates.isEmpty else { return .empty }

        let asOf = filter.end
        let today = DashboardAggregations.todayYMD()
        let opening = max(0, openingCubic)
        let capacity = max(pondCapacityCubic, 1)

        // Cumulative balance from opening through each day in the selected window,
        // seeded with movements before the window start (within loaded transactions).
        let priorIn = transactions
            .filter { isTripInRow($0) && String($0.date.prefix(10)) < filter.start }
            .reduce(0.0) { $0 + tripCubicIn($1) }
        let priorOut = cubicOutBefore(filter.start, transactions: transactions)

        var running = opening + priorIn - priorOut
        var series: [DayPoint] = []
        var periodIn = 0.0
        var periodOut = 0.0
        var priorRemainingCubic = running

        for date in dates {
            if date == asOf {
                priorRemainingCubic = running
            }
            let inn = cubicIn(on: date, transactions: transactions)
            let out = cubicOut(on: date, transactions: transactions)
            periodIn += inn
            periodOut += out
            running += inn - out
            series.append(
                DayPoint(
                    date: date,
                    label: DashboardAggregations.dayLabel(date),
                    inCubic: inn,
                    outCubic: out,
                    remainingEndOfDay: running
                )
            )
        }

        let remaining = series.last?.remainingEndOfDay ?? (opening + priorIn - priorOut)
        let dayCount = max(dates.count, 1)
        let avgIn = periodIn / Double(dayCount)
        let avgOut = periodOut / Double(dayCount)
        let asOfIn = cubicIn(on: asOf, transactions: transactions)
        let asOfOut = cubicOut(on: asOf, transactions: transactions)
        let feedDay = asOf.isEmpty ? today : asOf

        let pace = resolvePace(avgIn: avgIn, avgOut: avgOut, periodIn: periodIn, periodOut: periodOut)
        let burn = avgOut - avgIn
        let daysUntilEmpty: Double? = {
            guard burn > 0.05, remaining > 0 else { return nil }
            return remaining / burn
        }()

        return Snapshot(
            asOfDate: asOf,
            openingCubic: opening,
            pondCapacityCubic: capacity,
            fillRatio: fillRatio(remaining: max(0, remaining), capacity: capacity),
            remainingCubic: remaining,
            periodInCubic: periodIn,
            periodOutCubic: periodOut,
            periodNetCubic: periodIn - periodOut,
            todayInCubic: asOfIn,
            todayOutCubic: asOfOut,
            priorRemainingCubic: priorRemainingCubic,
            avgDailyInCubic: avgIn,
            avgDailyOutCubic: avgOut,
            pace: pace,
            daysUntilEmpty: daysUntilEmpty,
            insight: makeInsight(
                pace: pace,
                remaining: remaining,
                avgIn: avgIn,
                avgOut: avgOut,
                daysUntilEmpty: daysUntilEmpty,
                periodNet: periodIn - periodOut
            ),
            series: series,
            recentEvents: buildRecentEvents(dayKey: feedDay, transactions: transactions)
        )
    }

    // MARK: - Private

    private static func eventSortKey(_ t: Transaction) -> String {
        if let created = t.createdAt, !created.isEmpty { return created }
        if let updated = t.updatedAt, !updated.isEmpty { return updated }
        return t.date
    }

    private static func formatEventTime(_ t: Transaction) -> String {
        let raw = t.createdAt ?? t.updatedAt ?? t.date
        // ISO-ish: 2026-08-10T14:32:01 or date-only
        if let tIndex = raw.firstIndex(of: "T") {
            let afterT = raw[raw.index(after: tIndex)...]
            let hhmm = String(afterT.prefix(5))
            if hhmm.count == 5 { return hhmm }
        }
        if raw.count >= 16, raw.contains(" ") {
            let parts = raw.split(separator: " ")
            if parts.count >= 2 {
                return String(parts[1].prefix(5))
            }
        }
        return String(raw.prefix(10))
    }

    private static func resolvePace(
        avgIn: Double,
        avgOut: Double,
        periodIn: Double,
        periodOut: Double
    ) -> PaceStatus {
        if periodIn <= 0, periodOut <= 0 { return .idle }
        if avgOut <= 0.05 {
            return avgIn > 0.05 ? .surplusBuilding : .idle
        }
        let ratio = avgIn / avgOut
        if ratio >= 1.05 { return .surplusBuilding }
        if ratio >= 0.92 { return .keepingUp }
        if ratio >= 0.75 { return .tight }
        return .fallingBehind
    }

    private static func makeInsight(
        pace: PaceStatus,
        remaining: Double,
        avgIn: Double,
        avgOut: Double,
        daysUntilEmpty: Double?,
        periodNet: Double
    ) -> String {
        let remText = DashboardAggregations.formatNumber(max(0, remaining))
        switch pace {
        case .idle:
            return "ยังไม่มีการขนเข้าหรือร่อนออกในช่วงที่เลือก"
        case .keepingUp:
            return "คงเหลือประมาณ \(remText) \(unitLabel) — ขนเข้าเฉลี่ย \(DashboardAggregations.formatNumber(avgIn)) คิว/วัน ใกล้เคียงร่อนออก \(DashboardAggregations.formatNumber(avgOut)) คิว/วัน"
        case .tight:
            if let days = daysUntilEmpty {
                return "คงเหลือ \(remText) \(unitLabel) — ถ้ารอบนี้ต่อเนื่อง อาจหมดใน ~\(DashboardAggregations.formatNumber(days)) วัน"
            }
            return "คงเหลือ \(remText) \(unitLabel) — ร่อนออกเร็วกว่าขนเข้าเล็กน้อย"
        case .fallingBehind:
            if let days = daysUntilEmpty {
                return "ขนไม่ทัน — คงเหลือ \(remText) \(unitLabel) อาจหมดใน ~\(DashboardAggregations.formatNumber(days)) วัน ถ้าอัตรานี้คงที่"
            }
            return "ขนไม่ทัน — ร่อนออกเร็วกว่าขนเข้าชัดเจน (สุทธิ \(DashboardAggregations.formatNumber(periodNet)) \(unitLabel))"
        case .surplusBuilding:
            return "ขนเกินใช้ — คงเหลือ \(remText) \(unitLabel) สุทธิ +\(DashboardAggregations.formatNumber(periodNet)) \(unitLabel) ในช่วงนี้"
        }
    }
}
