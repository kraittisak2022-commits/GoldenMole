import Foundation

/// Encodable upsert body for count-record DailyLog rows (trip / sand).
/// Mirrors Flutter `AppTransaction.toInsertMap` for the fields we write.
struct TransactionWritePayload: Encodable, Sendable {
    let id: String
    let date: String
    let type: String
    let category: String
    let subCategory: String?
    let description: String
    let amount: Double
    let note: String?
    let vehicleId: String?
    let driverId: String?
    let workDetails: String?
    let tripBillingMode: String?
    let tripCount: Double?
    let perCarTrips: Double?
    let cubicPerTrip: Double?
    let perCarCubic: Double?
    let totalCubic: Double?
    let drumsObtained: Double?
    let workAssignments: [String: [String]]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, date, type, category, description, amount, note
        case subCategory = "sub_category"
        case vehicleId = "vehicle_id"
        case driverId = "driver_id"
        case workDetails = "work_details"
        case tripBillingMode = "trip_billing_mode"
        case tripCount = "trip_count"
        case perCarTrips = "per_car_trips"
        case cubicPerTrip = "cubic_per_trip"
        case perCarCubic = "per_car_cubic"
        case totalCubic = "total_cubic"
        case drumsObtained = "drums_obtained"
        case workAssignments = "work_assignments"
        case createdAt = "created_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(type, forKey: .type)
        try c.encode(category, forKey: .category)
        try c.encode(description, forKey: .description)
        try c.encode(amount, forKey: .amount)
        try c.encodeIfPresent(subCategory, forKey: .subCategory)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(vehicleId, forKey: .vehicleId)
        try c.encodeIfPresent(driverId, forKey: .driverId)
        try c.encodeIfPresent(workDetails, forKey: .workDetails)
        try c.encodeIfPresent(tripBillingMode, forKey: .tripBillingMode)
        try c.encodeIfPresent(tripCount, forKey: .tripCount)
        try c.encodeIfPresent(perCarTrips, forKey: .perCarTrips)
        try c.encodeIfPresent(cubicPerTrip, forKey: .cubicPerTrip)
        try c.encodeIfPresent(perCarCubic, forKey: .perCarCubic)
        try c.encodeIfPresent(totalCubic, forKey: .totalCubic)
        try c.encodeIfPresent(drumsObtained, forKey: .drumsObtained)
        try c.encodeIfPresent(workAssignments, forKey: .workAssignments)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

/// Builds payloads and persists count-record trip/sand rows (online-only MVP).
enum CountRecordWriter {
    static func newTransactionId(suffix: String) -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let safe = suffix
            .replacingOccurrences(of: " ", with: "_")
            .prefix(24)
        return "\(ms)_\(safe)"
    }

    static func formatCubic(_ value: Double) -> String {
        CountRecordLogic.formatMetric(value)
    }

    static func tripPayload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String?,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        omitCreatedAt: Bool,
        cubicPerTrip: Double = Double(CountRecordLogic.queuePerTrip)
    ) -> TransactionWritePayload {
        let r = Double(rounds)
        let totalCubic = r * cubicPerTrip
        let cubicLabel = formatCubic(cubicPerTrip)
        let assignments: [String: [String]]? = lapTimes.isEmpty
            ? nil
            : ["lapTimes": lapTimes]
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: "VehicleTrip",
            description: "\(vehicleId): \(rounds) เที่ยว × \(cubicLabel) คิว",
            amount: 0,
            note: "นับเที่ยวโดย \(adminName)",
            vehicleId: vehicleId,
            driverId: (driverId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 },
            workDetails: nil,
            tripBillingMode: "PerTrip",
            tripCount: r,
            perCarTrips: r,
            cubicPerTrip: cubicPerTrip,
            perCarCubic: totalCubic,
            totalCubic: totalCubic,
            drumsObtained: nil,
            workAssignments: assignments,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date())
        )
    }

    static func sandPayload(
        id: String,
        dateYmd: String,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let assignments: [String: [String]]? = lapTimes.isEmpty
            ? nil
            : ["lapTimes": lapTimes]
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: "Sand",
            description: "ร่อนทราย: \(rounds) รอบ",
            amount: 0,
            note: "ร่อนทรายโดย \(adminName)",
            vehicleId: nil,
            driverId: nil,
            workDetails: nil,
            tripBillingMode: nil,
            tripCount: nil,
            perCarTrips: nil,
            cubicPerTrip: nil,
            perCarCubic: nil,
            totalCubic: nil,
            drumsObtained: Double(rounds),
            workAssignments: assignments,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Persists a non-empty unit, or deletes when rounds/laps are empty.
    @MainActor
    static func saveTrip(
        service: SupabaseService,
        appState: AppState,
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String?,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        wasPersisted: Bool
    ) async throws -> Transaction? {
        if rounds <= 0 && lapTimes.isEmpty {
            if wasPersisted {
                try await service.deleteTransaction(id: id)
                appState.removeTransaction(id: id)
            }
            return nil
        }
        let payload = tripPayload(
            id: id,
            dateYmd: dateYmd,
            vehicleId: vehicleId,
            driverId: driverId,
            rounds: rounds,
            lapTimes: lapTimes,
            adminName: adminName,
            omitCreatedAt: wasPersisted
        )
        let saved = try await service.upsertTransaction(payload)
        appState.upsertTransaction(saved)
        return saved
    }

    @MainActor
    static func saveSand(
        service: SupabaseService,
        appState: AppState,
        id: String,
        dateYmd: String,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        wasPersisted: Bool
    ) async throws -> Transaction? {
        if rounds <= 0 && lapTimes.isEmpty {
            if wasPersisted {
                try await service.deleteTransaction(id: id)
                appState.removeTransaction(id: id)
            }
            return nil
        }
        let payload = sandPayload(
            id: id,
            dateYmd: dateYmd,
            rounds: rounds,
            lapTimes: lapTimes,
            adminName: adminName,
            omitCreatedAt: wasPersisted
        )
        let saved = try await service.upsertTransaction(payload)
        appState.upsertTransaction(saved)
        return saved
    }
}
