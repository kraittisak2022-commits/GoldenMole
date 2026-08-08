import Foundation

enum AdvanceWriter {
    static func newId(index: Int, employeeId: String) -> String {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        return "\(ts)_adv_\(index)_\(employeeId)"
    }

    static func payload(
        id: String,
        dateYmd: String,
        employeeId: String,
        employeeName: String,
        amountPerPerson: Double,
        meta: AdvanceLogic.Meta,
        existingWorkDetails: String?,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let workDetails = meta.encodeIntoWorkDetails(existing: existingWorkDetails)
        let slotTh = meta.payoutSlot.descriptionLabel
        let payTh = meta.paymentMethod.label
        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Labor",
            subCategory: "Advance",
            description: "คำขอเบิกเงิน · \(employeeName) · \(slotTh) · \(payTh)",
            amount: amountPerPerson,
            note: nil,
            vehicleId: nil,
            driverId: nil,
            workDetails: workDetails,
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
            employeeIds: [employeeId],
            laborStatus: "Advance",
            workType: nil,
            workTypeByEmployee: nil,
            leaveReason: nil,
            leaveDays: nil,
            tripMorning: nil,
            tripAfternoon: nil,
            quantity: nil,
            unit: nil,
            unitPrice: nil,
            fuelType: nil,
            fuelMovement: nil,
            advanceAmount: amountPerPerson
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
