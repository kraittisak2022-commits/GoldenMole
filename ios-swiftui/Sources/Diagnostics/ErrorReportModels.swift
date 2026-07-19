import Foundation

/// One row inserted into the shared `mobile_error_reports` table (viewed in the web app:
/// ตั้งค่า > รายงานจากแอป iOS). Mirrors the Android payload but with `platform = "ios"`.
struct MobileErrorReportInsert: Codable, Sendable {
    let id: String
    let platform: String
    let reportedByUsername: String?
    let reportedByName: String?
    let appVersion: String?
    let deviceInfo: String?
    let errorSummary: String
    let errorDetail: String?
    let userNote: String?
    let source: String
    let screenPage: String?
    let screenPageId: String?
    let screenStepId: String?
    let screenAction: String?
    let screenButton: String?
    let errorField: String?
    let reviewed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case platform
        case reportedByUsername = "reported_by_username"
        case reportedByName = "reported_by_name"
        case appVersion = "app_version"
        case deviceInfo = "device_info"
        case errorSummary = "error_summary"
        case errorDetail = "error_detail"
        case userNote = "user_note"
        case source
        case screenPage = "screen_page"
        case screenPageId = "screen_page_id"
        case screenStepId = "screen_step_id"
        case screenAction = "screen_action"
        case screenButton = "screen_button"
        case errorField = "error_field"
        case reviewed
    }
}
