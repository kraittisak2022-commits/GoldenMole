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
            fuelMovement: "stock_in",
            fuelTank: FuelLogic.tankMain
        )
    }

    static func withdrawPayload(
        id: String,
        dateYmd: String,
        liters: Double,
        purpose: FuelLogic.WithdrawPurpose,
        otherText: String,
        time: String,
        omitCreatedAt: Bool,
        fuelTank: String = FuelLogic.tankMain
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
            fuelMovement: "stock_out",
            fuelTank: fuelTank
        )
    }

    static func vehicleUsagePayload(
        id: String,
        dateYmd: String,
        vehicleId: String,
        liters: Double,
        time: String,
        omitCreatedAt: Bool,
        fuelTank: String = FuelLogic.tankReserve
    ) -> TransactionWritePayload {
        let tank = FuelLogic.normalizeTank(fuelTank)
        let tankLabel = tank == FuelLogic.tankReserve ? "ปั่นไฟ/สำรอง" : "พล่าม/หลัก"
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.vehicleUsageSubCategory,
            description: "ใช้น้ำมันรถ \(vehicleId): \(FuelLogic.formatLiters(liters)) ลิตร (ดีเซล · \(tankLabel))",
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
            fuelMovement: "stock_out",
            fuelTank: tank
        )
    }

    /// คู่แถวโอนหลัก→สำรอง เมื่อเบิก purpose = machine
    static func transferToReservePayloads(
        dateYmd: String,
        liters: Double,
        time: String,
        omitCreatedAt: Bool
    ) -> (out: TransactionWritePayload, `in`: TransactionWritePayload) {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let pairNote = "xfer:\(ts)"
        let created = omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date())
        let out = TransactionWritePayload(
            id: "\(ts)_fuel_xfer_out",
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.transferSubCategory,
            description: "เติมเครื่องจักร: โอนถังหลัก → สำรอง \(FuelLogic.formatLiters(liters)) ลิตร",
            amount: 0,
            note: pairNote,
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
            createdAt: created,
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: nil,
            laborStatus: nil,
            workType: "machine",
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: liters,
            unit: "L",
            unitPrice: nil,
            fuelType: "Diesel",
            fuelMovement: "stock_out",
            fuelTank: FuelLogic.tankMain
        )
        let inn = TransactionWritePayload(
            id: "\(ts)_fuel_xfer_in",
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Fuel",
            subCategory: FuelLogic.transferSubCategory,
            description: "รับเข้าถังสำรองจากถังหลัก: \(FuelLogic.formatLiters(liters)) ลิตร",
            amount: 0,
            note: pairNote,
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
            createdAt: created,
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: nil,
            laborStatus: nil,
            workType: "machine",
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: liters,
            unit: "L",
            unitPrice: nil,
            fuelType: "Diesel",
            fuelMovement: "stock_in",
            fuelTank: FuelLogic.tankReserve
        )
        return (out, inn)
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
