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

    /// Matches Android «การใช้รถแม็คโคร» (`category: Vehicle` + macro vehicle label).
    /// Resolves catalog `v_…` ids via `cars` / `vehicleCatalog` / `nameById` when present.
    static func isMacroUsageRow(
        _ t: Transaction,
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = [],
        nameById: [String: String] = [:]
    ) -> Bool {
        guard t.category == "Vehicle" else { return false }
        if CountRecordLogic.isMacroVehicleId(t.vehicleId) { return true }
        if CountRecordLogic.isMacroVehicleId(t.vehicleName) { return true }
        if CountRecordLogic.isMacroVehicleId(CountRecordLogic.vehicleNameFromDescription(t.description)) {
            return true
        }

        let label = CountRecordLogic.vehicleDisplayLabel(
            vehicleId: t.vehicleId,
            vehicleName: t.vehicleName,
            cars: cars,
            catalog: catalog,
            description: t.description,
            nameById: nameById
        )
        if CountRecordLogic.isMacroVehicleId(label) { return true }

        let id = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }

        if catalog.contains(where: {
            ($0.id == id || $0.id.lowercased() == id.lowercased())
                && CountRecordLogic.isMacroVehicleId($0.name)
        }) {
            return true
        }

        for car in cars where CountRecordLogic.isMacroVehicleId(car) {
            let trimmed = car.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed == id { return true }
            let made = CountRecordLogic.makeVehicleId(from: trimmed)
            if made == id || made.lowercased() == id.lowercased() { return true }
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
        for row in settings.vehicleCatalog {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, CountRecordLogic.isMacroVehicleId(name) else { continue }
            if seen.insert(name).inserted { out.append(name) }
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

    static func dayRowsByVehicle(
        dayKey: String,
        transactions: [Transaction],
        cars: [String] = [],
        catalog: [VehicleCatalogRow] = []
    ) -> [String: Transaction] {
        let nameById = CountRecordLogic.vehicleNameIndex(from: transactions)
        var byVehicle: [String: Transaction] = [:]

        func put(_ key: String, _ t: Transaction) {
            let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !k.isEmpty else { return }
            if let existing = byVehicle[k] {
                let ta = t.createdAt
                let ea = existing.createdAt
                if ta == nil || (ea != nil && (ta ?? "") > (ea ?? "")) {
                    byVehicle[k] = t
                }
            } else {
                byVehicle[k] = t
            }
        }

        for t in transactions {
            guard String(t.date.prefix(10)) == dayKey,
                  isMacroUsageRow(t, cars: cars, catalog: catalog, nameById: nameById)
            else { continue }
            let vid = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vid.isEmpty else { continue }
            put(vid, t)
            let label = CountRecordLogic.vehicleDisplayLabel(
                vehicleId: t.vehicleId,
                vehicleName: t.vehicleName,
                cars: cars,
                catalog: catalog,
                description: t.description,
                nameById: nameById
            )
            if !label.isEmpty, label != vid {
                put(label, t)
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
