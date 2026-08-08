import Foundation

/// Flutter `count_record_vehicle_defaults.dart` parity.
enum CountRecordVehicleDefaults {
    static func compactVehicleLabel(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    static func vehicleIdsLikelyMatch(_ a: String, _ b: String) -> Bool {
        let ca = compactVehicleLabel(a)
        let cb = compactVehicleLabel(b)
        guard !ca.isEmpty, !cb.isEmpty else { return false }
        if ca == cb { return true }
        return ca.contains(cb) || cb.contains(ca)
    }

    /// 1) web `vehicleDefaultDrivers` 2) most frequent driver from trip history.
    static func resolveDriverId(
        vehicleId: String,
        drivers: [Employee],
        tripHistory: [Transaction],
        vehicleDefaultDrivers: [String: String]
    ) -> String? {
        let vehicle = vehicleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !vehicle.isEmpty else { return nil }
        let driverIds = Set(drivers.map(\.id))

        if let configured = vehicleDefaultDrivers[vehicle]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty,
           driverIds.contains(configured) {
            return configured
        }
        // Fuzzy key match in defaults map
        for (key, value) in vehicleDefaultDrivers {
            let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, driverIds.contains(id), vehicleIdsLikelyMatch(key, vehicle) else { continue }
            return id
        }

        var counts: [String: Int] = [:]
        for t in tripHistory {
            guard CountRecordLogic.isCountRecordVehicleRow(t) else { continue }
            let v = (t.vehicleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty, vehicleIdsLikelyMatch(v, vehicle) else { continue }
            let driverId = (t.driverId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !driverId.isEmpty else { continue }
            counts[driverId, default: 0] += 1
        }
        let best = counts.max(by: { $0.value < $1.value })?.key
        if let best, driverIds.contains(best) { return best }
        return nil
    }
}
