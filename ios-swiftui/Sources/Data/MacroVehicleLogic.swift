import Foundation

/// Flutter «การใช้รถแม็คโคร» helpers.
enum MacroVehicleLogic {
    static let workQuickPhrases: [String] = [
        "เปิดหน้าดิน",
        "ทอยดิน",
        "ขุดแร่",
        "ร่อนทราย",
        "ชัพพอต",
    ]

    /// Pinned SK200 patterns (Flutter `_kFuelPinnedVehiclePatterns`).
    private static let pinnedPatterns: [(model: String, nickname: String)] = [
        ("SK200-8", "น้องโกลเด้น"),
        ("SK200-10", "พี่ยักษ์ใหญ่"),
        ("SK200-10", "พี่เดอะฮัก"),
    ]

    enum WorkType: String, CaseIterable, Identifiable, Sendable {
        case fullDay = "FullDay"
        case halfDay = "HalfDay"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fullDay: return "เต็มวัน"
            case .halfDay: return "ครึ่งวัน"
            }
        }

        static func from(raw: String?) -> WorkType {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "HalfDay" ? .halfDay : .fullDay
        }
    }

    static func isMacroUsageRow(_ t: Transaction) -> Bool {
        guard t.category == "Vehicle" else { return false }
        if CountRecordLogic.isMacroVehicleId(t.vehicleId) { return true }
        if CountRecordLogic.isMacroVehicleId(t.vehicleName) { return true }
        if CountRecordLogic.isMacroVehicleId(CountRecordLogic.vehicleNameFromDescription(t.description)) {
            return true
        }
        return false
    }

    static func macroCars(from settings: AppSettings) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for car in settings.cars {
            let trimmed = car.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, CountRecordLogic.isMacroVehicleId(trimmed) else { continue }
            if seen.insert(trimmed).inserted { out.append(trimmed) }
        }
        return out
    }

    static func pinnedCars(_ all: [String]) -> [String] {
        var pinned: [String] = []
        var used = Set<String>()
        for pattern in pinnedPatterns {
            if let hit = all.first(where: { !used.contains($0) && $0.contains(pattern.model) && $0.contains(pattern.nickname) }) {
                pinned.append(hit)
                used.insert(hit)
            }
        }
        return pinned
    }

    static func extraCars(_ all: [String]) -> [String] {
        let pinned = Set(pinnedCars(all))
        return all.filter { !pinned.contains($0) }
    }

    static func macroDrivers(from employees: [Employee]) -> [Employee] {
        employees.filter { $0.isActive && $0.isMacroDriver }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func dayRowsByVehicle(dayKey: String, transactions: [Transaction]) -> [String: Transaction] {
        var byVehicle: [String: Transaction] = [:]
        for t in transactions {
            guard String(t.date.prefix(10)) == dayKey, isMacroUsageRow(t) else { continue }
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vid.isEmpty else { continue }
            if let existing = byVehicle[vid] {
                let ta = t.createdAt
                let ea = existing.createdAt
                if ta == nil || (ea != nil && (ta ?? "") > (ea ?? "")) {
                    byVehicle[vid] = t
                }
            } else {
                byVehicle[vid] = t
            }
        }
        return byVehicle
    }

    static func parseWorkTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func joinWorkTags(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }

    static func stripRecorderSuffix(_ raw: String) -> String {
        var s = raw
        let markers = [" • โดย ", " โดย ", " — บันทึกโดย "]
        for m in markers {
            if let range = s.range(of: m) {
                s = String(s[..<range.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
