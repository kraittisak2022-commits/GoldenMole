import Foundation

/// UserDefaults prefs for count-record (goal, cubic, work mode, tutorial).
enum CountRecordPrefs {
    private static let tripGoalKey = "count_record_trip_goal_v1"
    private static let cubicKey = "count_record_trip_cubic_per_trip_v1"
    private static let modePrefix = "count_record_work_mode_"
    private static let tutorialKey = "count_record_tutorial_done_v1"

    static var tripGoal: Int {
        get {
            if UserDefaults.standard.object(forKey: tripGoalKey) == nil { return 10 }
            return UserDefaults.standard.integer(forKey: tripGoalKey)
        }
        set { UserDefaults.standard.set(max(0, newValue), forKey: tripGoalKey) }
    }

    static var cubicPerTrip: Double {
        get {
            let v = UserDefaults.standard.double(forKey: cubicKey)
            return v > 0 ? v : Double(CountRecordLogic.queuePerTrip)
        }
        set {
            let clamped = min(99, max(0.5, (newValue * 2).rounded() / 2))
            UserDefaults.standard.set(clamped, forKey: cubicKey)
        }
    }

    static func workMode(for dayKey: String) -> CountRecordWorkMode? {
        let raw = UserDefaults.standard.string(forKey: modePrefix + dayKey)
        return CountRecordWorkMode(rawValue: raw ?? "")
    }

    static func setWorkMode(_ mode: CountRecordWorkMode?, for dayKey: String) {
        let key = modePrefix + dayKey
        if let mode {
            UserDefaults.standard.set(mode.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static var tutorialCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: tutorialKey) }
        set { UserDefaults.standard.set(newValue, forKey: tutorialKey) }
    }
}
