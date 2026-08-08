import Foundation

/// Encodable upsert body for count-record DailyLog rows (trip / sand / status events).
struct TransactionWritePayload: Codable, Sendable, Equatable {
    var id: String
    var date: String
    var type: String
    var category: String
    var subCategory: String?
    var description: String
    var amount: Double
    var note: String?
    var vehicleId: String?
    var driverId: String?
    var workDetails: String?
    var tripBillingMode: String?
    var tripCount: Double?
    var perCarTrips: Double?
    var cubicPerTrip: Double?
    var perCarCubic: Double?
    var totalCubic: Double?
    var drumsObtained: Double?
    var workAssignments: [String: [String]]?
    var createdAt: String?
    var eventType: String?
    var eventPriority: String?
    var eventTime: String?
    /// Labor / attendance / leave fields (optional — unused by count-record DailyLog rows).
    var employeeIds: [String]? = nil
    var laborStatus: String? = nil
    var workType: String? = nil
    var workTypeByEmployee: [String: String]? = nil
    var leaveReason: String? = nil
    var leaveDays: Double? = nil
    var tripMorning: Double? = nil
    var tripAfternoon: Double? = nil

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
        case eventType = "event_type"
        case eventPriority = "event_priority"
        case eventTime = "event_time"
        case employeeIds = "employee_ids"
        case laborStatus = "labor_status"
        case workType = "work_type"
        case workTypeByEmployee = "work_type_by_employee"
        case leaveReason = "leave_reason"
        case leaveDays = "leave_days"
        case tripMorning = "trip_morning"
        case tripAfternoon = "trip_afternoon"
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
        try c.encodeIfPresent(eventType, forKey: .eventType)
        try c.encodeIfPresent(eventPriority, forKey: .eventPriority)
        try c.encodeIfPresent(eventTime, forKey: .eventTime)
        try c.encodeIfPresent(employeeIds, forKey: .employeeIds)
        try c.encodeIfPresent(laborStatus, forKey: .laborStatus)
        try c.encodeIfPresent(workType, forKey: .workType)
        try c.encodeIfPresent(workTypeByEmployee, forKey: .workTypeByEmployee)
        try c.encodeIfPresent(leaveReason, forKey: .leaveReason)
        try c.encodeIfPresent(leaveDays, forKey: .leaveDays)
        try c.encodeIfPresent(tripMorning, forKey: .tripMorning)
        try c.encodeIfPresent(tripAfternoon, forKey: .tripAfternoon)
    }
}

extension Transaction {
    /// Optimistic local row from a write payload (offline / before server round-trip).
    static func localFromPayload(_ payload: TransactionWritePayload) -> Transaction? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return try? JSONDecoder().decode(Transaction.self, from: data)
    }
}

enum CountRecordWorkKind: String, CaseIterable, Identifiable, Sendable {
    case sandTransport = "sand"
    case support = "support"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sandTransport: return "ขนทราย"
        case .support: return "ชัพพอต"
        }
    }

    var tag: String {
        switch self {
        case .sandTransport: return "งาน: ขนทราย"
        case .support: return "งาน: ชัพพอต"
        }
    }

    static func from(workDetails: String?) -> CountRecordWorkKind {
        let d = workDetails ?? ""
        let lastSupport = d.range(of: "งาน: ชัพพอต", options: .backwards)?.lowerBound
        let lastSand = d.range(of: "งาน: ขนทราย", options: .backwards)?.lowerBound
        if lastSupport == nil && lastSand == nil { return .sandTransport }
        if let s = lastSupport, let a = lastSand { return s > a ? .support : .sandTransport }
        return lastSupport != nil ? .support : .sandTransport
    }

    static func appendTag(to details: String, kind: CountRecordWorkKind) -> String {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if from(workDetails: trimmed) == kind { return trimmed }
        if trimmed.isEmpty { return kind.tag }
        return "\(trimmed), \(kind.tag)"
    }
}

/// Builds payloads and persists via offline-capable sync layer.
enum CountRecordWriter {
    static func newTransactionId(suffix: String) -> String {
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let safe = suffix.replacingOccurrences(of: " ", with: "_").prefix(24)
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
        workDetails: String? = nil,
        cubicPerTrip: Double = CountRecordPrefs.cubicPerTrip,
        isSupport: Bool = false
    ) -> TransactionWritePayload {
        let assignments: [String: [String]]? = lapTimes.isEmpty ? nil : ["lapTimes": lapTimes]
        let driver = (driverId?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

        if isSupport {
            return TransactionWritePayload(
                id: id,
                date: dateYmd,
                type: TransactionType.expense.rawValue,
                category: "DailyLog",
                subCategory: "VehicleTrip",
                description: "\(vehicleId): ชัพพอต",
                amount: 0,
                note: "นับเที่ยวโดย \(adminName)",
                vehicleId: vehicleId,
                driverId: driver,
                workDetails: workDetails,
                tripBillingMode: "PerTrip",
                tripCount: 0,
                perCarTrips: 0,
                cubicPerTrip: nil,
                perCarCubic: nil,
                totalCubic: nil,
                drumsObtained: nil,
                workAssignments: assignments,
                createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
                eventType: nil,
                eventPriority: nil,
                eventTime: nil
            )
        }

        let r = Double(rounds)
        let totalCubic = r * cubicPerTrip
        let cubicLabel = formatCubic(cubicPerTrip)
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
            driverId: driver,
            workDetails: workDetails,
            tripBillingMode: "PerTrip",
            tripCount: r,
            perCarTrips: r,
            cubicPerTrip: cubicPerTrip,
            perCarCubic: totalCubic,
            totalCubic: totalCubic,
            drumsObtained: nil,
            workAssignments: assignments,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: nil,
            eventPriority: nil,
            eventTime: nil
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
        let assignments: [String: [String]]? = lapTimes.isEmpty ? nil : ["lapTimes": lapTimes]
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
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: nil,
            eventPriority: nil,
            eventTime: nil
        )
    }

    static func vehicleStatusEventPayload(
        dateYmd: String,
        vehicleId: String,
        driverLabel: String,
        adminName: String,
        broken: Bool,
        stamp: String
    ) -> TransactionWritePayload {
        let driverPart = driverLabel.isEmpty || driverLabel == "ยังไม่ระบุ"
            ? ""
            : " • คนขับ \(driverLabel)"
        let desc = broken
            ? "แจ้งรถเสีย: \(vehicleId)\(driverPart) • เวลา \(stamp) (บันทึกโดย \(adminName))"
            : "รถกลับมาใช้งานปกติ: \(vehicleId)\(driverPart) • เวลา \(stamp) (บันทึกโดย \(adminName))"
        return TransactionWritePayload(
            id: newTransactionId(suffix: "vehstatus"),
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: "Event",
            description: desc,
            amount: 0,
            note: "บันทึกอัตโนมัติจากเมนูบันทึกและนับจำนวน",
            vehicleId: nil,
            driverId: nil,
            workDetails: nil,
            tripBillingMode: nil,
            tripCount: nil,
            perCarTrips: nil,
            cubicPerTrip: nil,
            perCarCubic: nil,
            totalCubic: nil,
            drumsObtained: nil,
            workAssignments: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            eventType: broken ? "problem" : "success",
            eventPriority: broken ? "urgent" : "normal",
            eventTime: nil
        )
    }

    /// Persist trip (or delete when empty and not support). Returns whether queued offline.
    @MainActor
    @discardableResult
    static func saveTrip(
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String?,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        wasPersisted: Bool,
        workDetails: String?,
        isSupport: Bool
    ) async -> (queued: Bool, deleted: Bool) {
        if rounds <= 0 && lapTimes.isEmpty && !isSupport {
            if wasPersisted {
                let queued = await CountRecordOfflineSync.shared.delete(id: id)
                return (queued, true)
            }
            return (false, true)
        }
        let payload = tripPayload(
            id: id,
            dateYmd: dateYmd,
            vehicleId: vehicleId,
            driverId: driverId,
            rounds: rounds,
            lapTimes: lapTimes,
            adminName: adminName,
            omitCreatedAt: wasPersisted,
            workDetails: workDetails,
            isSupport: isSupport
        )
        let queued = await CountRecordOfflineSync.shared.persist(payload: payload, wasPersisted: wasPersisted)
        return (queued, false)
    }

    @MainActor
    @discardableResult
    static func saveSand(
        id: String,
        dateYmd: String,
        rounds: Int,
        lapTimes: [String],
        adminName: String,
        wasPersisted: Bool
    ) async -> (queued: Bool, deleted: Bool) {
        if rounds <= 0 && lapTimes.isEmpty {
            if wasPersisted {
                let queued = await CountRecordOfflineSync.shared.delete(id: id)
                return (queued, true)
            }
            return (false, true)
        }
        let payload = sandPayload(
            id: id,
            dateYmd: dateYmd,
            rounds: rounds,
            lapTimes: lapTimes,
            adminName: adminName,
            omitCreatedAt: wasPersisted
        )
        let queued = await CountRecordOfflineSync.shared.persist(payload: payload, wasPersisted: wasPersisted)
        return (queued, false)
    }
}
