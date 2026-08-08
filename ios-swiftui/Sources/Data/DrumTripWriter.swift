import Foundation

enum DrumTripWriter {
    static func newId(suffix: String = "trip") -> String {
        CountRecordWriter.newTransactionId(suffix: suffix)
    }

    static func perTripPayload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String,
        tripMorning: Double,
        tripAfternoon: Double,
        cubicPerTrip: Double,
        workDetails: String,
        workType: DrumTripLogic.WorkType,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let totalTrips = tripMorning + tripAfternoon
        let totalCubic = totalTrips * cubicPerTrip
        let cubicLabel = DrumTripLogic.formatMetric(cubicPerTrip)
        let tripLabel = DrumTripLogic.formatMetric(totalTrips)
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: "VehicleTrip",
            description: "\(vehicleId): \(tripLabel) เที่ยว × \(cubicLabel) คิว",
            amount: 0,
            note: nil,
            vehicleId: vehicleId,
            driverId: driverId,
            workDetails: workDetails.isEmpty ? nil : workDetails,
            tripBillingMode: DrumTripLogic.BillingMode.perTrip.rawValue,
            tripCount: totalTrips,
            perCarTrips: totalTrips,
            cubicPerTrip: cubicPerTrip,
            perCarCubic: totalCubic,
            totalCubic: totalCubic,
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
            tripMorning: tripMorning,
            tripAfternoon: tripAfternoon
        )
    }

    static func lumpSumPayload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        driverId: String,
        tripMorning: Double,
        tripAfternoon: Double,
        lumpCubic: Double,
        workDetails: String,
        workType: DrumTripLogic.WorkType,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let totalTrips = tripMorning + tripAfternoon
        let lumpLabel = DrumTripLogic.formatMetric(lumpCubic)
        let am = DrumTripLogic.formatMetric(tripMorning)
        let pm = DrumTripLogic.formatMetric(tripAfternoon)
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: "VehicleTrip",
            description: "\(vehicleId): เหมา \(lumpLabel) คิว • เช้า \(am) เที่ยว บ่าย \(pm) เที่ยว",
            amount: 0,
            note: nil,
            vehicleId: vehicleId,
            driverId: driverId,
            workDetails: workDetails.isEmpty ? nil : workDetails,
            tripBillingMode: DrumTripLogic.BillingMode.lumpSum.rawValue,
            tripCount: totalTrips,
            perCarTrips: totalTrips,
            cubicPerTrip: 0,
            perCarCubic: lumpCubic,
            totalCubic: lumpCubic,
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
            tripMorning: tripMorning,
            tripAfternoon: tripAfternoon
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
