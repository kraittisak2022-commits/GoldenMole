import Foundation

/// Detects stale count-record payloads that would overwrite a newer higher total.
enum CountRecordStaleGuard {
    /// Reject when incoming has meaningfully fewer laps that end earlier than existing.
    /// Allows small intentional undo/edit steps (drop < 5).
    static func isStaleOverwrite(
        incomingLaps: [String],
        incomingRounds: Int,
        existingLaps: [String],
        existingRounds: Int
    ) -> Bool {
        let inLaps = incomingLaps
        let exLaps = existingLaps
        let inRounds = max(incomingRounds, inLaps.count)
        let exRounds = max(existingRounds, exLaps.count)
        let drop = exRounds - inRounds
        guard drop >= 5 else { return false }

        let inLast = inLaps.last ?? ""
        let exLast = exLaps.last ?? ""
        guard !exLast.isEmpty else { return false }
        if inLast.isEmpty { return true }
        return inLast < exLast
    }

    static func isStaleSandOverwrite(
        payload: TransactionWritePayload,
        existing: Transaction?
    ) -> Bool {
        guard let existing else { return false }
        let sub = (payload.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isSand = sub == "sand" || (payload.description ?? "").hasPrefix("ร่อนทราย:")
        guard isSand else { return false }
        return isStaleOverwrite(
            incomingLaps: payload.workAssignments?["lapTimes"] ?? [],
            incomingRounds: Int((payload.drumsObtained ?? 0).rounded()),
            existingLaps: existing.workAssignments?["lapTimes"] ?? [],
            existingRounds: CountRecordLogic.sandRounds(from: existing)
        )
    }

    static func isStaleTripOverwrite(
        payload: TransactionWritePayload,
        existing: Transaction?
    ) -> Bool {
        guard let existing else { return false }
        let sub = (payload.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isTrip = sub == "vehicletrip" || !(payload.vehicleId ?? "").isEmpty
        guard isTrip, sub != "sand", sub != "event" else { return false }
        let incomingRounds = Int((payload.perCarTrips ?? payload.tripCount ?? 0).rounded())
        return isStaleOverwrite(
            incomingLaps: payload.workAssignments?["lapTimes"] ?? [],
            incomingRounds: incomingRounds,
            existingLaps: existing.workAssignments?["lapTimes"] ?? [],
            existingRounds: CountRecordLogic.tripRounds(from: existing)
        )
    }

    static func isStaleCountRecordOverwrite(
        payload: TransactionWritePayload,
        existing: Transaction?
    ) -> Bool {
        isStaleSandOverwrite(payload: payload, existing: existing)
            || isStaleTripOverwrite(payload: payload, existing: existing)
    }
}
