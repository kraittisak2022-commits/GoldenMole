import Foundation

/// Port of web `countRecordUtils.ts` + essential analytics helpers for Real-time V.4.
enum CountRecordLogic {
    static let tripTarget = 266
    /// Daily sand wash target (คิว/วัน) — machine lap counts toward this goal.
    static let sandTarget = 1000
    static let queuePerTrip = 4
    static let otStartHour = 17
    static let lunchStartHour = 12
    static let lunchEndHour = 13
    static let priorDayLookback = 14
    static let sandRecentLaps = 5
    static let bangkokOffsetMs: TimeInterval = 7 * 60 * 60

    static let vehicleColors: [String] = [
        "#1565C0", "#2E7D32", "#E65100", "#6A1B9A",
        "#00838F", "#C62828", "#4527A0", "#558B2F"
    ]

    // MARK: - Formatting

    static func formatMetric(_ v: Double) -> String {
        if abs(v) < 1e-9 { return "0" }
        if abs(v - v.rounded()) < 1e-9 { return String(Int(v.rounded())) }
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    static func formatMetric(_ v: Int) -> String { formatMetric(Double(v)) }

    // MARK: - Row filters

    static func isCountRecordVehicleRow(_ t: Transaction) -> Bool {
        guard t.category == "DailyLog",
              (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "vehicletrip"
        else { return false }
        return !t.description.contains("ทรายที่ล้างที่บ้าน")
    }

    static func isCountRecordSandTapRow(_ t: Transaction) -> Bool {
        guard t.category == "DailyLog",
              (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sand"
        else { return false }
        let desc = t.description
        if desc.contains("เครื่องร่อน") || desc.contains("จำนวนถัง") || desc.contains("ทรายที่ล้างที่บ้าน") {
            return false
        }
        return desc.contains("ร่อนทราย")
    }

    // MARK: - Focus calendar day marks (เที่ยวรถ / ร่อนทราย)

    enum DayOpsMark: Equatable, Sendable {
        case none
        case tripOnly
        case sandOnly
        case both
    }

    /// Per-day activity marks for the Real-time focus date picker (month grid).
    static func dayOpsMarks(
        inMonth monthStart: Date,
        transactions: [Transaction],
        employees: [Employee]
    ) -> [String: DayOpsMark] {
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

        var out: [String: DayOpsMark] = [:]
        for d in range {
            let key = String(format: "%04d-%02d-%02d", year, month, d)
            let dayTx = byDay[key] ?? []
            guard !dayTx.isEmpty else {
                out[key] = .none
                continue
            }
            let tripTotal = buildTripUnits(dayKey: key, transactions: dayTx, employees: employees)
                .reduce(0) { $0 + $1.rounds }
            let sandRounds = buildSandUnit(dayKey: key, transactions: dayTx)?.rounds ?? 0
            let hasTrip = tripTotal > 0
            let hasSand = sandRounds > 0
            switch (hasTrip, hasSand) {
            case (true, true): out[key] = .both
            case (true, false): out[key] = .tripOnly
            case (false, true): out[key] = .sandOnly
            case (false, false): out[key] = .none
            }
        }
        return out
    }

    static func isMacroVehicleId(_ raw: String?) -> Bool {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return false }
        return s.contains("แม็คโคร") || s.contains("แมคโคร") || s.contains("excavator") || s.contains("backhoe")
    }

    /// Drum / dump / 6-wheel / 10-wheel vehicles used by the Android drum-trip menu (excludes macro).
    static func isDrumTripVehicleId(_ raw: String?) -> Bool {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !isMacroVehicleId(s) else { return false }
        let compact = s.lowercased().replacingOccurrences(of: " ", with: "")
        if compact.contains("ดั๊ม") || compact.contains("ดั้ม") || compact.contains("ดรัม") || compact.contains("dump") {
            return true
        }
        if compact.contains("หกล้อ") || compact.contains("6ล้อ") { return true }
        if compact.contains("สิบล้อ") || compact.contains("10ล้อ") { return true }
        if s.range(of: #"6\s*ล้อ"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"10\s*ล้อ"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Catalog ids look like `v_` + hex (web `makeVehicleId`).
    static func looksLikeCatalogVehicleId(_ raw: String?) -> Bool {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.hasPrefix("v_") && s.count >= 4
    }

    /// Port of web `makeVehicleId` — stable hash id for a display name.
    static func makeVehicleId(from name: String) -> String {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var hash: Int32 = 0
        for scalar in key.unicodeScalars {
            let c = Int32(bitPattern: UInt32(scalar.value))
            hash = ((hash &<< 5) &- hash) &+ c
        }
        let absHash = hash == Int32.min ? Int64(Int32.max) + 1 : Int64(abs(hash))
        return "v_\(String(absHash, radix: 16))"
    }

    /// Name hint from description prefixes like `"รถดรัมโอเว่น: 2 เที่ยว × 4 คิว"`.
    static func vehicleNameFromDescription(_ raw: String?) -> String? {
        let desc = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !desc.isEmpty else { return nil }
        let head: String
        if let r = desc.range(of: ":") {
            head = String(desc[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            head = desc
        }
        guard !head.isEmpty, !looksLikeCatalogVehicleId(head) else { return nil }
        return head
    }

    /// Display label for trip cards — prefer `vehicleName`, then catalog / cars / description.
    static func vehicleDisplayLabel(
        vehicleId: String?,
        vehicleName: String?,
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = [],
        description: String? = nil,
        nameById: [String: String] = [:]
    ) -> String {
        let name = (vehicleName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, !looksLikeCatalogVehicleId(name) { return name }

        let id = (vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            return vehicleNameFromDescription(description) ?? name
        }

        if let mapped = nameById[id]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mapped.isEmpty,
           !looksLikeCatalogVehicleId(mapped) {
            return mapped
        }

        if let hit = catalog.first(where: {
            $0.id == id || $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == id
        }) {
            let hitName = hit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hitName.isEmpty { return hitName }
        }

        if looksLikeCatalogVehicleId(id) {
            let idLower = id.lowercased()
            if let hit = catalog.first(where: { $0.id.lowercased() == idLower }) {
                let hitName = hit.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !hitName.isEmpty { return hitName }
            }
            for car in cars {
                let trimmed = car.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if makeVehicleId(from: trimmed) == id || makeVehicleId(from: trimmed).lowercased() == idLower {
                    return trimmed
                }
            }
            if let fromDesc = vehicleNameFromDescription(description) {
                return fromDesc
            }
        } else if !isMacroVehicleId(id) {
            return id
        }

        if let fromDesc = vehicleNameFromDescription(description) {
            return fromDesc
        }
        if !name.isEmpty { return name }
        return id
    }

    /// Collect vehicle_id → display name from rows that already carry `vehicle_name`.
    static func vehicleNameIndex(from transactions: [Transaction]) -> [String: String] {
        var map: [String: String] = [:]
        for t in transactions {
            let id = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { continue }
            let name = (t.vehicleName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !looksLikeCatalogVehicleId(name) {
                map[id] = name
                continue
            }
            if map[id] == nil, let fromDesc = vehicleNameFromDescription(t.description) {
                map[id] = fromDesc
            }
        }
        return map
    }

    static func getLapTimes(_ t: Transaction) -> [String] {
        t.workAssignments?["lapTimes"] ?? []
    }

    static func isWorkDetailsBroken(_ details: String?) -> Bool {
        let d = details ?? ""
        guard let lastBroken = d.range(of: "รถเสีย", options: .backwards)?.lowerBound else { return false }
        if let lastNormal = d.range(of: "รถปกติ", options: .backwards)?.lowerBound {
            return lastNormal < lastBroken
        }
        return true
    }

    static func driverDisplayName(_ driverId: String, employees: [Employee]) -> String {
        let id = driverId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "ยังไม่ระบุ" }
        if let emp = employees.first(where: { $0.id == id }) { return emp.displayName }
        return id
    }

    // MARK: - Lap periods

    static func lapHour(_ lap: String) -> Int? {
        let s = lap.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sp = s.firstIndex(of: " ") else { return nil }
        let time = String(s[s.index(after: sp)...])
        let hourStr = time.split(separator: ":").first.map(String.init) ?? time
        return Int(hourStr.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func lapPeriods(_ t: Transaction) -> (morning: Int, afternoon: Int, unknown: Int, ot: Int) {
        var morning = 0, afternoon = 0, unknown = 0, ot = 0
        for lap in getLapTimes(t) {
            guard let h = lapHour(lap) else {
                unknown += 1
                continue
            }
            if h < 12 {
                morning += 1
            } else {
                afternoon += 1
                if h >= otStartHour { ot += 1 }
            }
        }
        return (morning, afternoon, unknown, ot)
    }

    static func vehicleTripPeriodSplit(_ t: Transaction) -> (morning: Int, afternoon: Int, ot: Int) {
        let lapOt = lapPeriods(t).ot
        let tm = Int(t.tripMorning ?? 0)
        let ta = Int(t.tripAfternoon ?? 0)
        if tm != 0 || ta != 0 { return (tm, ta, lapOt) }

        let periods = lapPeriods(t)
        if periods.morning > 0 || periods.afternoon > 0 || periods.unknown > 0 {
            return (periods.morning + periods.unknown, periods.afternoon, periods.ot)
        }

        let total = Int(t.perCarTrips ?? t.tripCount ?? 0)
        return (total, 0, 0)
    }

    static func tripRounds(from t: Transaction) -> Int {
        let laps = getLapTimes(t)
        var tripRounds = Int((t.perCarTrips ?? t.tripCount ?? 0).rounded())
        if laps.count > tripRounds { tripRounds = laps.count }
        return tripRounds
    }

    static func sandRounds(from t: Transaction) -> Int {
        let laps = getLapTimes(t)
        let fromDrums = Int((t.drumsObtained ?? 0).rounded())
        if !laps.isEmpty { return max(laps.count, fromDrums) }
        return fromDrums
    }

    private static func sandRowScore(_ t: Transaction) -> Int {
        let laps = getLapTimes(t)
        if !laps.isEmpty { return laps.count * 1000 }
        return Int((t.drumsObtained ?? 0).rounded())
    }

    private static func sandRowIsEmpty(_ t: Transaction) -> Bool {
        getLapTimes(t).isEmpty && Int((t.drumsObtained ?? 0).rounded()) <= 0
    }

    // MARK: - Build units

    static func buildTripUnits(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = []
    ) -> [CountRecordTripUnit] {
        let key = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameById = vehicleNameIndex(from: transactions)
        var units: [CountRecordTripUnit] = []
        for t in transactions {
            guard String(t.date.prefix(10)) == key else { continue }
            guard isCountRecordVehicleRow(t) else { continue }
            let label = vehicleDisplayLabel(
                vehicleId: t.vehicleId,
                vehicleName: t.vehicleName,
                cars: cars,
                catalog: catalog,
                description: t.description,
                nameById: nameById
            )
            guard !label.isEmpty, !isMacroVehicleId(label) else { continue }
            let periods = vehicleTripPeriodSplit(t)
            units.append(
                CountRecordTripUnit(
                    id: t.id,
                    vehicleId: label,
                    driverId: (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    driverLabel: driverDisplayName(t.driverId ?? "", employees: employees),
                    rounds: tripRounds(from: t),
                    morning: periods.morning,
                    afternoon: periods.afternoon,
                    ot: periods.ot,
                    lapTimes: getLapTimes(t),
                    broken: isWorkDetailsBroken(t.workDetails)
                )
            )
        }
        return units
    }

    static func buildSandUnit(dayKey: String, transactions: [Transaction]) -> CountRecordSandUnit? {
        let key = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var sandRow: Transaction?
        for t in transactions {
            guard String(t.date.prefix(10)) == key else { continue }
            guard isCountRecordSandTapRow(t), !sandRowIsEmpty(t) else { continue }
            if sandRow == nil || sandRowScore(t) > sandRowScore(sandRow!) {
                sandRow = t
            }
        }
        guard let sandRow else { return nil }
        let periods = lapPeriods(sandRow)
        return CountRecordSandUnit(
            id: sandRow.id,
            rounds: sandRounds(from: sandRow),
            morning: periods.morning,
            afternoon: periods.afternoon,
            ot: periods.ot,
            lapTimes: getLapTimes(sandRow)
        )
    }

    static func menuStatusLabel(
        dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        tripUnits: [CountRecordTripUnit]? = nil,
        sandUnit: CountRecordSandUnit? = nil
    ) -> String? {
        let trips = tripUnits ?? buildTripUnits(dayKey: dayKey, transactions: transactions, employees: employees)
        let sand = sandUnit ?? buildSandUnit(dayKey: dayKey, transactions: transactions)
        let tripTotal = trips.reduce(0) { $0 + $1.rounds }
        var parts: [String] = []
        if tripTotal > 0 || !trips.isEmpty {
            parts.append("\(trips.count) คัน · \(formatMetric(tripTotal)) เที่ยว")
        }
        if let sand, sand.rounds > 0 {
            var sandText = "ร่อน \(formatMetric(sand.rounds)) รอบ"
            if sand.morning > 0 || sand.afternoon > 0 {
                sandText += " (เช้า \(sand.morning) · บ่าย \(sand.afternoon))"
            }
            parts.append(sandText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Dates / work span
    // Integer civil-date math (Howard Hinnant) — no Calendar / TimeZone allocations.

    /// Days since Unix epoch for Gregorian Y-M-D (proleptic).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        let m = month
        let d = day
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Inverse of `daysFromCivil`.
    static func civilFromDays(_ zIn: Int) -> (year: Int, month: Int, day: Int) {
        let z = zIn + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        var y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        y += m <= 2 ? 1 : 0
        return (y, m, d)
    }

    /// Bangkok wall-clock → UTC epoch seconds (no Foundation date objects).
    static func bangkokEpochSeconds(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> TimeInterval {
        let days = daysFromCivil(year: year, month: month, day: day)
        let localSec = days * 86_400 + hour * 3_600 + minute * 60 + second
        return TimeInterval(localSec) - bangkokOffsetMs
    }

    static func bangkokHourFromEpoch(_ epoch: TimeInterval) -> Int {
        let local = Int((epoch + bangkokOffsetMs).rounded(.towardZero))
        let sod = ((local % 86_400) + 86_400) % 86_400
        return sod / 3_600
    }

    static func bangkokMinuteFromEpoch(_ epoch: TimeInterval) -> Int {
        let local = Int((epoch + bangkokOffsetMs).rounded(.towardZero))
        let sod = ((local % 86_400) + 86_400) % 86_400
        return (sod % 3_600) / 60
    }

    /// UTC epoch of Bangkok midnight for the civil day containing `epoch`.
    static func bangkokMidnightUTC(containing epoch: TimeInterval) -> TimeInterval {
        let local = epoch + bangkokOffsetMs
        let dayStartLocal = floor(local / 86_400) * 86_400
        return dayStartLocal - bangkokOffsetMs
    }

    static func addDays(to ymd: String, delta: Int) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        let days = daysFromCivil(year: parts[0], month: parts[1], day: parts[2]) + delta
        let c = civilFromDays(days)
        return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    /// Lap stamp `dd/MM HH:mm:ss` + year from dayKey → epoch seconds (Bangkok)
    static func parseLapStamp(_ stamp: String, dayKey: String) -> TimeInterval? {
        let s = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let space = s.firstIndex(of: " ") else { return nil }
        let datePart = String(s[..<space])
        let timePart = String(s[s.index(after: space)...])
        let dm = datePart.split(separator: "/").compactMap { Int($0) }
        let hms = timePart.split(separator: ":").compactMap { Int($0) }
        guard dm.count >= 2, hms.count >= 1 else { return nil }
        let yy = Int(dayKey.prefix(4)) ?? 0
        guard yy > 0 else { return nil }
        let month = dm[1]
        let day = dm[0]
        let hour = hms[0]
        let minute = hms.count > 1 ? hms[1] : 0
        let second = hms.count > 2 ? hms[2] : 0
        guard month >= 1, month <= 12, day >= 1, day <= 31,
              hour >= 0, hour < 24, minute >= 0, minute < 60, second >= 0, second < 60
        else { return nil }
        return bangkokEpochSeconds(year: yy, month: month, day: day, hour: hour, minute: minute, second: second)
    }

    /// Lap stamp matching Flutter: `dd/MM HH:mm:ss` (Bangkok civil clock).
    static func formatLapStamp(_ date: Date = Date()) -> String {
        let cal = DashboardAggregations.gregorian
        let d = cal.component(.day, from: date)
        let m = cal.component(.month, from: date)
        let h = cal.component(.hour, from: date)
        let min = cal.component(.minute, from: date)
        let s = cal.component(.second, from: date)
        return String(format: "%02d/%02d %02d:%02d:%02d", d, m, h, min, s)
    }

    /// Build stamp for a dayKey using edited Bangkok clock components.
    static func formatLapStamp(dayKey: String, hour: Int, minute: Int, second: Int) -> String? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let month = parts[1]
        let day = parts[2]
        guard hour >= 0, hour < 24, minute >= 0, minute < 60, second >= 0, second < 60,
              month >= 1, month <= 12, day >= 1, day <= 31
        else { return nil }
        return String(format: "%02d/%02d %02d:%02d:%02d", day, month, hour, minute, second)
    }

    /// Parse `HH`, `mm`, `ss` from a lap stamp (ignores date part).
    static func lapClockComponents(_ stamp: String) -> (hour: Int, minute: Int, second: Int)? {
        let s = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
        let timePart: String
        if let space = s.firstIndex(of: " ") {
            timePart = String(s[s.index(after: space)...])
        } else {
            timePart = s
        }
        let hms = timePart.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard hms.count >= 2 else { return nil }
        let hour = hms[0]
        let minute = hms[1]
        let second = hms.count > 2 ? hms[2] : 0
        guard hour >= 0, hour < 24, minute >= 0, minute < 60, second >= 0, second < 60 else { return nil }
        return (hour, minute, second)
    }

    static func formatLapClock(_ stamp: String) -> String? {
        let s = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
        let timePart: String
        if let space = s.firstIndex(of: " ") {
            timePart = String(s[s.index(after: space)...])
        } else {
            timePart = s
        }
        let parts = timePart.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let hh = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let mm = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hh.isEmpty, !mm.isEmpty else { return nil }
        return String(format: "%02d:%02d", Int(hh) ?? 0, Int(mm) ?? 0)
    }

    static func computeWorkSpan(lapTimes: [String], dayKey: String) -> CountRecordWorkSpan {
        var parsed: [(stamp: String, time: TimeInterval)] = []
        for stamp in lapTimes {
            if let t = parseLapStamp(stamp, dayKey: dayKey) {
                parsed.append((stamp, t))
            }
        }
        guard !parsed.isEmpty else {
            return CountRecordWorkSpan(startStamp: nil, endStamp: nil, startClock: nil, endClock: nil)
        }
        parsed.sort { $0.time < $1.time }
        let first = parsed.first!
        let last = parsed.last!
        return CountRecordWorkSpan(
            startStamp: first.stamp,
            endStamp: last.stamp,
            startClock: formatLapClock(first.stamp),
            endClock: formatLapClock(last.stamp)
        )
    }

    static func formatWorkSpanLabel(_ span: CountRecordWorkSpan) -> String? {
        guard let start = span.startClock else { return nil }
        if let end = span.endClock, end != start {
            return "เริ่ม \(start) · เลิก \(end)"
        }
        return "เริ่ม \(start)"
    }

    static func fleetWorkSpanLabel(units: [CountRecordTripUnit], dayKey: String) -> String? {
        let allLaps = units.flatMap(\.lapTimes)
        return formatWorkSpanLabel(computeWorkSpan(lapTimes: allLaps, dayKey: dayKey))
    }

    /// Split lap stamps into morning (hour < 12) and afternoon (hour >= 12), matching `lapPeriods`.
    static func splitLapsByPeriod(_ lapTimes: [String]) -> (morning: [String], afternoon: [String]) {
        var morning: [String] = []
        var afternoon: [String] = []
        for lap in lapTimes {
            guard let h = lapHour(lap) else { continue }
            if h < 12 {
                morning.append(lap)
            } else {
                afternoon.append(lap)
            }
        }
        return (morning, afternoon)
    }

    /// Clock display with a period separator, e.g. `08.31`.
    static func formatClockDot(_ clock: String) -> String {
        clock.replacingOccurrences(of: ":", with: ".")
    }

    /// e.g. `ตอนเช้า เริ่ม 08.31 ถึง 12.01` or `ตอนเช้า เริ่ม 08.31` when only one lap.
    static func formatPeriodSpanLabel(prefix: String, span: CountRecordWorkSpan) -> String? {
        guard let start = span.startClock else { return nil }
        let startDot = formatClockDot(start)
        if let end = span.endClock, end != start {
            return "\(prefix) เริ่ม \(startDot) ถึง \(formatClockDot(end))"
        }
        return "\(prefix) เริ่ม \(startDot)"
    }

    static func periodSpanLabels(
        lapTimes: [String],
        dayKey: String
    ) -> (morning: String?, afternoon: String?) {
        let split = splitLapsByPeriod(lapTimes)
        let morningLabel = formatPeriodSpanLabel(
            prefix: "ตอนเช้า",
            span: computeWorkSpan(lapTimes: split.morning, dayKey: dayKey)
        )
        let afternoonLabel = formatPeriodSpanLabel(
            prefix: "ตอนบ่าย",
            span: computeWorkSpan(lapTimes: split.afternoon, dayKey: dayKey)
        )
        return (morningLabel, afternoonLabel)
    }

    static func fleetPeriodSpanLabels(
        units: [CountRecordTripUnit],
        dayKey: String
    ) -> (morning: String?, afternoon: String?) {
        periodSpanLabels(lapTimes: units.flatMap(\.lapTimes), dayKey: dayKey)
    }

    static func lunchOverlapSeconds(start: TimeInterval, end: TimeInterval) -> TimeInterval {
        guard end > start else { return 0 }
        // Lunch window is local to the Bangkok civil day of `start` (same as Calendar-based path).
        let midnight = bangkokMidnightUTC(containing: start)
        let lunchStart = midnight + TimeInterval(lunchStartHour * 3_600)
        let lunchEnd = midnight + TimeInterval(lunchEndHour * 3_600)
        let oStart = max(start, lunchStart)
        let oEnd = min(end, lunchEnd)
        return max(0, oEnd - oStart)
    }

    static func activeDurationHours(lapTimes: [String], dayKey: String) -> Double? {
        let span = computeWorkSpan(lapTimes: lapTimes, dayKey: dayKey)
        guard let startStamp = span.startStamp, let endStamp = span.endStamp,
              let start = parseLapStamp(startStamp, dayKey: dayKey),
              let end = parseLapStamp(endStamp, dayKey: dayKey),
              end > start
        else { return nil }
        let active = (end - start) - lunchOverlapSeconds(start: start, end: end)
        return max(0, active) / 3600
    }

    static func findPriorDayWithTripData(
        from dayKey: String,
        transactions: [Transaction],
        employees: [Employee],
        byDay: [String: [Transaction]]? = nil
    ) -> String? {
        for offset in 1...priorDayLookback {
            let key = addDays(to: dayKey, delta: -offset)
            let dayTx = byDay?[key] ?? transactions
            let rounds = buildTripUnits(dayKey: key, transactions: dayTx, employees: employees)
                .reduce(0) { $0 + $1.rounds }
            if rounds > 0 { return key }
        }
        return nil
    }

    static func comparisonDayLabel(prior: String?, focus: String) -> String {
        guard let prior else { return "" }
        if prior == addDays(to: focus, delta: -1) { return "เมื่อวาน" }
        let parts = prior.split(separator: "-")
        guard parts.count == 3 else { return prior }
        return "\(parts[2])/\(parts[1])"
    }

    static func vehicleEfficiency(
        dayKey: String,
        tripUnits: [CountRecordTripUnit],
        transactions: [Transaction],
        employees: [Employee],
        priorKey: String? = nil,
        byDay: [String: [Transaction]]? = nil
    ) -> VehicleEfficiency {
        let tripTotal = tripUnits.reduce(0) { $0 + $1.rounds }
        let activeToday = tripUnits.filter { $0.rounds > 0 }
        let countToday = activeToday.isEmpty ? tripUnits.count : activeToday.count
        let perVehToday = countToday > 0 ? Double(tripTotal) / Double(countToday) : 0

        let resolvedPrior = priorKey
            ?? findPriorDayWithTripData(from: dayKey, transactions: transactions, employees: employees, byDay: byDay)
        let yesterday: [CountRecordTripUnit]
        if let resolvedPrior {
            let dayTx = byDay?[resolvedPrior] ?? transactions
            yesterday = buildTripUnits(dayKey: resolvedPrior, transactions: dayTx, employees: employees)
        } else {
            yesterday = []
        }
        let yTotal = yesterday.reduce(0) { $0 + $1.rounds }
        let activeYest = yesterday.filter { $0.rounds > 0 }
        let countYest = activeYest.isEmpty ? yesterday.count : activeYest.count
        let perVehYest: Double? = (countYest > 0 && yTotal > 0) ? Double(yTotal) / Double(countYest) : nil
        let delta: Double? = {
            guard let perVehYest, perVehYest > 0 else { return nil }
            return ((perVehToday - perVehYest) / perVehYest) * 100
        }()

        return VehicleEfficiency(
            perVehToday: perVehToday,
            countToday: countToday,
            deltaPct: delta,
            priorLabel: comparisonDayLabel(prior: resolvedPrior, focus: dayKey),
            isCalendarYesterday: resolvedPrior == addDays(to: dayKey, delta: -1)
        )
    }
}
