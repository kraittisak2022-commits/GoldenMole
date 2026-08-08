import Foundation

enum LeaveWriter {
    static func newId() -> String {
        CountRecordWriter.newTransactionId(suffix: "leave")
    }

    static func payload(
        id: String,
        startYmd: String,
        leaveType: LeaveLogic.LeaveType,
        employeeIds: [String],
        reason: String,
        effectiveDays: Double,
        isHalfDay: Bool,
        halfPart: LeaveLogic.HalfPart,
        endYmd: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let reasonTrim = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let descCore = reasonTrim.isEmpty
            ? "ลา\(leaveType.shortTh)"
            : "ลา\(leaveType.shortTh): \(reasonTrim)"

        let description: String
        let workDetails: String?
        if isHalfDay {
            description = "\(descCore) (ครึ่งวัน — \(halfPart.label))"
            workDetails = halfPart.workDetailsMeta
        } else {
            let rangeTh: String
            if endYmd > startYmd {
                let startLabel = LeaveLogic.formatThaiYmd(startYmd)
                let endLabel = LeaveLogic.formatThaiYmd(endYmd)
                rangeTh = " (\(startLabel) - \(endLabel) รวม \(Int(effectiveDays.rounded())) วัน)"
            } else {
                rangeTh = ""
            }
            description = "\(descCore)\(rangeTh)"
            workDetails = nil
        }

        return TransactionWritePayload(
            id: id,
            date: startYmd,
            type: TransactionType.leave.rawValue,
            category: "Leave",
            subCategory: leaveType.rawValue,
            description: description,
            amount: 0,
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
            employeeIds: employeeIds.sorted(),
            laborStatus: "Leave",
            workType: nil,
            workTypeByEmployee: nil,
            leaveReason: reasonTrim,
            leaveDays: effectiveDays
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
