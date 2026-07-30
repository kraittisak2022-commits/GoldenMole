import Foundation

/// Port of web `countRecordUtils.ts` + essential analytics helpers for Real-time V.4.
enum CountRecordLogic {
    static let tripTarget = 266
    static let sandTarget = 800
    static let queuePerTrip = 3
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

    static func isMacroVehicleId(_ raw: String?) -> Bool {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return false }
        return s.contains("แม็คโคร") || s.contains("แมคโคร") || s.contains("excavator") || s.contains("backhoe")
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
        employees: [Employee]
    ) -> [CountRecordTripUnit] {
        let key = dayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        var units: [CountRecordTripUnit] = []
        for t in transactions {
            guard String(t.date.prefix(10)) == key else { continue }
            guard isCountRecordVehicleRow(t) else { continue }
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vid.isEmpty, !isMacroVehicleId(vid) else { continue }
            let periods = vehicleTripPeriodSplit(t)
            units.append(
                CountRecordTripUnit(
                    id: t.id,
                    vehicleId: vid,
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

    static func addDays(to ymd: String, delta: Int) -> String {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return ymd }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2] + delta
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = cal.date(from: comps) else { return ymd }
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
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
        var comps = DateComponents()
        comps.year = yy
        comps.month = dm[1]
        comps.day = dm[0]
        comps.hour = hms[0]
        comps.minute = hms.count > 1 ? hms[1] : 0
        comps.second = hms.count > 2 ? hms[2] : 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? TimeZone(secondsFromGMT: Int(bangkokOffsetMs))!
        return cal.date(from: comps)?.timeIntervalSince1970
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

    static func lunchOverlapSeconds(start: TimeInterval, end: TimeInterval) -> TimeInterval {
        guard end > start else { return 0 }
        let tz = TimeZone(identifier: "Asia/Bangkok") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let startDate = Date(timeIntervalSince1970: start)
        guard let lunchStart = cal.date(bySettingHour: lunchStartHour, minute: 0, second: 0, of: startDate),
              let lunchEnd = cal.date(bySettingHour: lunchEndHour, minute: 0, second: 0, of: startDate)
        else { return 0 }
        let oStart = max(start, lunchStart.timeIntervalSince1970)
        let oEnd = min(end, lunchEnd.timeIntervalSince1970)
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
        employees: [Employee]
    ) -> String? {
        for offset in 1...priorDayLookback {
            let key = addDays(to: dayKey, delta: -offset)
            let rounds = buildTripUnits(dayKey: key, transactions: transactions, employees: employees)
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
        employees: [Employee]
    ) -> VehicleEfficiency {
        let tripTotal = tripUnits.reduce(0) { $0 + $1.rounds }
        let activeToday = tripUnits.filter { $0.rounds > 0 }
        let countToday = activeToday.isEmpty ? tripUnits.count : activeToday.count
        let perVehToday = countToday > 0 ? Double(tripTotal) / Double(countToday) : 0

        let priorKey = findPriorDayWithTripData(from: dayKey, transactions: transactions, employees: employees)
        let yesterday = priorKey.map { buildTripUnits(dayKey: $0, transactions: transactions, employees: employees) } ?? []
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
            priorLabel: comparisonDayLabel(prior: priorKey, focus: dayKey),
            isCalendarYesterday: priorKey == addDays(to: dayKey, delta: -1)
        )
    }
}
