import Foundation
import SwiftUI

/// Flutter «เหตุการณ์» DailyLog/Event helpers.
enum EventLogic {
    static let subCategory = "Event"

    static let quickPhrases: [String] = [
        "ฝนตก หยุดงาน",
        "เครื่องจักรเสีย",
        "ทรายไม่ครบ",
        "คนงานมาสาย",
        "งานเสร็จตามแผน",
        "ไฟฟ้าดับ",
        "อุบัติเหตุเล็กน้อย",
    ]

    enum EventKind: String, CaseIterable, Identifiable, Sendable {
        case info
        case warning
        case problem
        case success
        case complaint
        case request

        var id: String { rawValue }

        var label: String {
            switch self {
            case .info: return "ข้อมูล"
            case .warning: return "เตือน"
            case .problem: return "ปัญหา"
            case .success: return "สำเร็จ"
            case .complaint: return "ข้อร้องเรียน"
            case .request: return "ความต้องการ"
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .problem: return "exclamationmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            case .complaint: return "megaphone.fill"
            case .request: return "list.clipboard.fill"
            }
        }

        var accent: Color {
            switch self {
            case .info: return AppTheme.info
            case .warning: return AppTheme.warning
            case .problem: return AppTheme.expense
            case .success: return AppTheme.income
            case .complaint: return AppTheme.purple
            case .request: return AppTheme.slate
            }
        }

        static func from(raw: String?) -> EventKind {
            EventKind(rawValue: (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                ?? .info
        }
    }

    enum Priority: String, CaseIterable, Identifiable, Sendable {
        case normal
        case urgent

        var id: String { rawValue }

        var label: String {
            switch self {
            case .normal: return "ปกติ"
            case .urgent: return "ด่วน"
            }
        }

        static func from(raw: String?) -> Priority {
            (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "urgent"
                ? .urgent
                : .normal
        }
    }

    static func isDailyEvent(_ t: Transaction) -> Bool {
        t.category == "DailyLog"
            && (t.subCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(subCategory) == .orderedSame
    }

    static func dayEvents(dayKey: String, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { String($0.date.prefix(10)) == dayKey && isDailyEvent($0) }
            .sorted { ($0.createdAt ?? $0.date) > ($1.createdAt ?? $1.date) }
    }

    /// Recent unique descriptions for suggestion chips (Flutter `_eventDescSuggestionsFromDay`).
    static func suggestions(from transactions: [Transaction], limit: Int = 10) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let sorted = transactions
            .filter(isDailyEvent)
            .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        for t in sorted {
            let text = stripRecorder(t.description)
            guard !text.isEmpty, seen.insert(text).inserted else { continue }
            out.append(text)
            if out.count >= limit { break }
        }
        return out
    }

    static func stripRecorder(_ raw: String) -> String {
        var s = raw
        for m in [" • โดย ", " โดย ", " — บันทึกโดย "] {
            if let r = s.range(of: m) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
