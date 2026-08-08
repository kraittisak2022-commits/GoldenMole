import Foundation

/// Helpers for the drum-trip form menu (Flutter `จำนวนเที่ยวรถ` / vehicle trip QuickInput).
enum DrumTripLogic {
    struct PeriodSplit: Equatable, Sendable {
        var morning: Double
        var afternoon: Double
    }

    enum BillingMode: String, CaseIterable, Identifiable, Sendable {
        case perTrip = "PerTrip"
        case lumpSum = "LumpSum"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .perTrip: return "คิดเป็นเที่ยว"
            case .lumpSum: return "เหมา"
            }
        }

        static func from(raw: String?) -> BillingMode {
            let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if s.lowercased() == "lumpsum" || s == "เหมา" { return .lumpSum }
            return .perTrip
        }
    }

    enum WorkType: String, CaseIterable, Identifiable, Sendable {
        case fullDay = "FullDay"
        case halfDay = "HalfDay"
        case hourly = "Hourly"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fullDay: return "เต็มวัน"
            case .halfDay: return "ครึ่งวัน"
            case .hourly: return "รายชั่วโมง"
            }
        }

        static func from(raw: String?) -> WorkType {
            switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            case "HalfDay": return .halfDay
            case "Hourly": return .hourly
            default: return .fullDay
            }
        }
    }

    /// Flutter `vehicleTripPeriodSplit`.
    static func periodSplit(_ t: Transaction) -> PeriodSplit {
        let tm = t.tripMorning ?? 0
        let ta = t.tripAfternoon ?? 0
        if tm != 0 || ta != 0 {
            return PeriodSplit(morning: tm, afternoon: ta)
        }

        let laps = CountRecordLogic.getLapTimes(t)
        if !laps.isEmpty {
            var morning = 0
            var afternoon = 0
            for lap in laps {
                guard let h = CountRecordLogic.lapHour(lap) else {
                    morning += 1
                    continue
                }
                if h < 12 { morning += 1 } else { afternoon += 1 }
            }
            return PeriodSplit(morning: Double(morning), afternoon: Double(afternoon))
        }

        let total = t.perCarTrips ?? t.tripCount ?? 0
        return PeriodSplit(morning: total, afternoon: 0)
    }

    static func defaultCubicPerTrip(for vehicleName: String) -> Double {
        let n = vehicleName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.contains("สิบล้อ") || n.contains("10ล้อ") || n.range(of: #"10\s*ล้อ"#, options: .regularExpression) != nil {
            return 7
        }
        return 3
    }

    static func isHydrateSource(_ t: Transaction) -> Bool {
        if CountRecordLogic.isMacroVehicleId(t.vehicleId) { return false }
        if t.description.contains("ทรายที่ล้างที่บ้าน") { return false }
        if t.description.contains("ตัดรอบล้างทรายที่บ้าน") { return false }
        let sc = (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.category == "DailyLog", sc == "vehicletrip" { return true }
        if t.category == "Vehicle" { return true }
        return false
    }

    static func dayRows(dayKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions.filter { String($0.date.prefix(10)) == dayKey && isHydrateSource($0) }
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
    }

    static func availableCars(settings: AppSettings, includeVehicleId: String? = nil) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        if let include = includeVehicleId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !include.isEmpty,
           seen.insert(include).inserted {
            out.append(include)
        }
        for car in settings.cars {
            let trimmed = car.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, CountRecordLogic.isDrumTripVehicleId(trimmed) else { continue }
            if seen.insert(trimmed).inserted { out.append(trimmed) }
        }
        return out
    }

    static func drivers(from employees: [Employee]) -> [Employee] {
        let active = employees.filter(\.isActive)
        let drivers = active.filter { emp in
            emp.positionTokens.contains { token in
                let t = token.replacingOccurrences(of: " ", with: "")
                return t.contains("คนขับรถ") && !t.contains("แม็คโคร") && !t.contains("แมคโคร")
            }
        }
        return drivers.isEmpty ? active : drivers
    }

    static func formatMetric(_ v: Double) -> String {
        CountRecordLogic.formatMetric(v)
    }

    static func stripRecorderSuffix(_ raw: String) -> String {
        var s = raw
        // Flutter `_stripRecorderSuffix` patterns — keep simple common suffixes.
        let markers = [" • โดย ", " โดย ", " — บันทึกโดย "]
        for m in markers {
            if let range = s.range(of: m) {
                s = String(s[..<range.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
