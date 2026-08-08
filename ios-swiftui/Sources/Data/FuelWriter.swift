import Foundation

enum FuelWriter {
    static func newId(suffix: String) -> String {
        CountRecordWriter.newTransactionId(suffix: suffix)
    }

    static func stockInPayload(
        id: String,
        dateYmd: String,
        liters: Double,
        unitPrice: Double?,
        amount: Double,
        time: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.stockInSubCategory,
            description: "เพิ่มน้ำมันเข้าถัง: \(FuelLogic.formatLiters(liters)) ลิตร (ดีเซล)",
            amount: amount,
            note: nil,
            vehicleId: nil,
            driverId: nil,
            workDetails: time,
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
            workType: nil,
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: liters,
            unit: "L",
            unitPrice: (unitPrice ?? 0) > 0 ? unitPrice : nil,
            fuelType: "Diesel",
            fuelMovement: "stock_in"
        )
    }

    static func withdrawPayload(
        id: String,
        dateYmd: String,
        liters: Double,
        purpose: FuelLogic.WithdrawPurpose,
        otherText: String,
        time: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let label = purpose.label
        let descPrefix = purpose == .other
            ? "เบิกน้ำมัน: \(label) — \(otherText)"
            : "เบิกน้ำมัน: \(label)"
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.withdrawSubCategory,
            description: "\(descPrefix) \(FuelLogic.formatLiters(liters)) ลิตร (ดีเซล)",
            amount: 0,
            note: nil,
            vehicleId: nil,
            driverId: nil,
            workDetails: time,
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
            workType: purpose.rawValue,
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: liters,
            unit: "L",
            unitPrice: nil,
            fuelType: "Diesel",
            fuelMovement: "stock_out"
        )
    }

    static func vehicleUsagePayload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        liters: Double,
        time: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.vehicleUsageSubCategory,
            description: "ใช้น้ำมันรถ \(vehicleId): \(FuelLogic.formatLiters(liters)) ลิตร (ดีเซล)",
            amount: 0,
            note: nil,
            vehicleId: vehicleId,
            driverId: nil,
            workDetails: time,
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
            workType: nil,
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: liters,
            unit: "L",
            unitPrice: nil,
            fuelType: "Diesel",
            fuelMovement: "stock_out"
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
