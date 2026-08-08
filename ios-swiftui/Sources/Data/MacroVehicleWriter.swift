import Foundation

enum MacroVehicleWriter {
    static func newId(index: Int = 0) -> String {
        CountRecordWriter.newTransactionId(suffix: "macro_vehicle_\(index)")
    }

    static func payload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String,
        workDetails: String,
        workType: MacroVehicleLogic.WorkType,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let details = workDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let dayLabel = workType == .halfDay ? "ครึ่งวัน" : "เต็มวัน"
        let detailPart = details.isEmpty ? "—" : details
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Vehicle",
            subCategory: nil,
            description: "รถ: \(vehicleId) (\(detailPart)) [\(dayLabel)]",
            amount: 0,
            note: nil,
            vehicleId: vehicleId,
            driverId: driverId,
            workDetails: details.isEmpty ? nil : details,
            tripBillingMode: nil,
            tripCount: nil,
            perCarTrips: nil,
            cubicPerTrip: nil,
            perCarCubic: nil,
            totalCubic: nil,
            drumsObtained: nil,
            workAssignments: nil,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: nil,
            laborStatus: nil,
            workType: workType.rawValue,
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil
        )
    }

    @MainActor
    @discardableResult
    static func persist(payload: TransactionWritePayload, wasPersisted: Bool) async -> Bool {
        await CountRecordOfflineSync.shared.persist(payload: payload, wasPersisted: wasPersisted)
    }

    @MainActor
    @discardableResult
    static func delete(id: String) async -> Bool {
        await CountRecordOfflineSync.shared.delete(id: id)
    }
}
