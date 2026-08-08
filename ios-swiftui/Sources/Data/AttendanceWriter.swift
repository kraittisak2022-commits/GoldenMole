import Foundation

/// Builds Labor / Leave attendance payloads matching Flutter `_saveAttendance*Entry`.
enum AttendanceWriter {
    static func newId(suffix: String) -> String {
        CountRecordWriter.newTransactionId(suffix: suffix)
    }

    static func sandWorkPayload(
        id: String,
        dateYmd: String,
        work: Set<String>,
        halfMorning: Set<String>,
        halfAfternoon: Set<String>,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let present = work.union(halfMorning).union(halfAfternoon)
        var workType: [String: String] = [:]
        for id in work { workType[id] = "FullDay" }
        for id in halfMorning { workType[id] = "HalfDay" }
        for id in halfAfternoon { workType[id] = "HalfDay" }

        var assignments: [String: [String]] = [:]
        if !work.isEmpty { assignments["work"] = Array(work).sorted() }
        if !halfMorning.isEmpty { assignments["half:morning"] = Array(halfMorning).sorted() }
        if !halfAfternoon.isEmpty { assignments["half:afternoon"] = Array(halfAfternoon).sorted() }

        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Labor",
            subCategory: "Attendance",
            description: "เช็คชื่อพนักงานท่าทราย: มาทำงาน \(present.count) คน",
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
            workAssignments: assignments.isEmpty ? nil : assignments,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: Array(present).sorted(),
            laborStatus: "Work",
            workType: nil,
            workTypeByEmployee: workType.isEmpty ? nil : workType,
            leaveReason: nil,
            leaveDays: nil
        )
    }

    static func sandLeavePayload(
        id: String,
        dateYmd: String,
        employeeIds: Set<String>,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        leavePayload(
            id: id,
            dateYmd: dateYmd,
            employeeIds: employeeIds,
            leaveReason: AttendanceLogic.leaveReasonSand,
            description: "เช็คชื่อพนักงานท่าทราย: ลางาน \(employeeIds.count) คน",
            omitCreatedAt: omitCreatedAt
        )
    }

    static func driverWorkPayload(
        id: String,
        dateYmd: String,
        macro: Set<String>,
        drum: Set<String>,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        let present = macro.union(drum)
        var workType: [String: String] = [:]
        for id in present { workType[id] = "FullDay" }

        var assignments: [String: [String]] = [:]
        if !macro.isEmpty { assignments["macro_driver"] = Array(macro).sorted() }
        if !drum.isEmpty { assignments["drum"] = Array(drum).sorted() }

        return TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.expense.rawValue,
            category: "Labor",
            subCategory: "Attendance",
            description: "เช็คชื่อคนขับรถ: มาทำงาน \(present.count) คน",
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
            workAssignments: assignments.isEmpty ? nil : assignments,
            createdAt: omitCreatedAt ? nil : ISO8601DateFormatter().string(from: Date()),
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: Array(present).sorted(),
            laborStatus: "Work",
            workType: nil,
            workTypeByEmployee: workType.isEmpty ? nil : workType,
            leaveReason: nil,
            leaveDays: nil
        )
    }

    static func driverLeavePayload(
        id: String,
        dateYmd: String,
        employeeIds: Set<String>,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        leavePayload(
            id: id,
            dateYmd: dateYmd,
            employeeIds: employeeIds,
            leaveReason: AttendanceLogic.leaveReasonDriver,
            description: "เช็คชื่อคนขับรถ: ลางาน \(employeeIds.count) คน",
            omitCreatedAt: omitCreatedAt
        )
    }

    private static func leavePayload(
        id: String,
        dateYmd: String,
        employeeIds: Set<String>,
        leaveReason: String,
        description: String,
        omitCreatedAt: Bool
    ) -> TransactionWritePayload {
        TransactionWritePayload(
            id: id,
            date: dateYmd,
            type: TransactionType.leave.rawValue,
            category: "Leave",
            subCategory: "Personal",
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
            eventType: nil,
            eventPriority: nil,
            eventTime: nil,
            employeeIds: Array(employeeIds).sorted(),
            laborStatus: "Leave",
            workType: nil,
            workTypeByEmployee: nil,
            leaveReason: leaveReason,
            leaveDays: 1
        )
    }

    @MainActor
    @discardableResult
    static func persist(payload: TransactionWritePayload, wasPersisted: Bool) async -> Bool {
        await CountRecordOfflineSync.shared.persist(payload: payload, wasPersisted: wasPersisted)
    }

    @MainActor
    @discardableResult
    static func deleteIfNeeded(id: String?) async {
        guard let id, !id.isEmpty else { return }
        _ = await CountRecordOfflineSync.shared.delete(id: id)
    }
}
