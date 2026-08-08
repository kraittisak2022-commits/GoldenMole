import Foundation

enum EventWriter {
    static func newId() -> String {
        CountRecordWriter.newTransactionId(suffix: "event")
    }

    static func payload(
        id: String,
        dateYmd: String,
        description: String,
        eventType: EventLogic.EventKind,
        priority: EventLogic.Priority,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "DailyLog",
            subCategory: EventLogic.subCategory,
            description: description,
            amount: 0,
            note: nil,
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
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: eventType.rawValue,
            eventPriority: priority.rawValue,
            eventTime: nil
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
