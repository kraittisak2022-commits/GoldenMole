import Foundation
import SwiftUI

// MARK: - Post kinds

enum FeedPostKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case admin
    case taskCreated = "task_created"
    case taskDone = "task_done"
    case taskNag = "task_nag"
    case leaveDigest = "leave_digest"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .admin: return "โพสต์ทีม"
        case .taskCreated: return "แจ้งงาน"
        case .taskDone: return "ปิดงาน"
        case .taskNag: return "ทวงงาน"
        case .leaveDigest: return "ลาประจำวัน"
        }
    }

    var systemImage: String {
        switch self {
        case .admin: return "text.bubble.fill"
        case .taskCreated: return "plus.circle.fill"
        case .taskDone: return "checkmark.circle.fill"
        case .taskNag: return "bell.badge.fill"
        case .leaveDigest: return "person.crop.circle.badge.moon"
        }
    }

    var tint: Color {
        switch self {
        case .admin: return AppTheme.brand
        case .taskCreated: return AppTheme.info
        case .taskDone: return AppTheme.income
        case .taskNag: return AppTheme.warning
        case .leaveDigest: return AppTheme.slate
        }
    }

    var isSystem: Bool {
        switch self {
        case .leaveDigest, .taskNag: return true
        default: return false
        }
    }

    var isTaskRelated: Bool {
        switch self {
        case .taskCreated, .taskDone, .taskNag: return true
        default: return false
        }
    }
}

enum FeedReactionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case like
    case love
    case wow
    case ok

    var id: String { rawValue }

    var label: String {
        switch self {
        case .like: return "ถูกใจ"
        case .love: return "รักเลย"
        case .wow: return "ว้าว"
        case .ok: return "โอเค"
        }
    }

    var systemImage: String {
        switch self {
        case .like: return "hand.thumbsup.fill"
        case .love: return "heart.fill"
        case .wow: return "face.smiling.inverse"
        case .ok: return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .like: return AppTheme.brand
        case .love: return AppTheme.expense
        case .wow: return AppTheme.warning
        case .ok: return AppTheme.info
        }
    }
}

// MARK: - Media

struct FeedMedia: Codable, Hashable, Identifiable, Sendable {
    var driveFileId: String
    var kind: String
    var mimeType: String
    var width: Int
    var height: Int

    var id: String { driveFileId }
    var isVideo: Bool { kind == "video" }

    enum CodingKeys: String, CodingKey {
        case driveFileId = "driveFileId"
        case kind
        case mimeType
        case width
        case height
    }

    /// Accept both camelCase (API) and snake_case if ever stored differently.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FlexibleKeys.self)
        driveFileId = try c.decodeIfPresent(String.self, forKey: .driveFileId)
            ?? c.decode(String.self, forKey: .drive_file_id)
        kind = try c.decode(String.self, forKey: .kind)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
            ?? c.decodeIfPresent(String.self, forKey: .mime_type)
            ?? c.decodeIfPresent(String.self, forKey: .mime)
            ?? "image/jpeg"
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(driveFileId, forKey: .driveFileId)
        try c.encode(kind, forKey: .kind)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
    }

    init(driveFileId: String, kind: String, mimeType: String, width: Int, height: Int) {
        self.driveFileId = driveFileId
        self.kind = kind
        self.mimeType = mimeType
        self.width = width
        self.height = height
    }

    private enum FlexibleKeys: String, CodingKey {
        case driveFileId, drive_file_id
        case kind
        case mimeType, mime_type, mime
        case width, height
    }

    var sources: PhotoMediaSources {
        let id = driveFileId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? driveFileId
        return PhotoMediaSources(
            thumb: "https://lh3.googleusercontent.com/d/\(id)=s640",
            thumbFallback: "https://drive.google.com/thumbnail?id=\(id)&sz=w640",
            large: "https://lh3.googleusercontent.com/d/\(id)=s2048",
            download: "https://drive.google.com/uc?export=download&id=\(id)",
            preview: isVideo ? "https://drive.google.com/file/d/\(id)/preview" : nil
        )
    }
}

// MARK: - Meta

struct FeedLeaveEntry: Codable, Hashable, Identifiable, Sendable {
    var employeeId: String
    var name: String
    var kind: String
    var halfDay: Bool

    var id: String { employeeId }

    enum CodingKeys: String, CodingKey {
        case employeeId, name, kind, halfDay
    }

    var kindLabel: String {
        switch kind {
        case "sick": return "ลาป่วย"
        case "personal": return "ลากิจ"
        default: return "ลางาน"
        }
    }
}

struct FeedPostMeta: Codable, Hashable, Sendable {
    var date: String?
    var daysOverdue: Int?
    var assigneeName: String?
    var priority: String?
    var title: String?
    var dueDate: String?
    var leaves: [FeedLeaveEntry]?
}

// MARK: - Rows

struct FeedPost: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var kind: FeedPostKind
    var authorAdminId: String?
    var authorName: String
    var body: String
    var taskId: String?
    var media: [FeedMedia]
    var meta: FeedPostMeta
    var dedupeKey: String?
    var pinned: Bool
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, body, media, meta, pinned
        case authorAdminId = "author_admin_id"
        case authorName = "author_name"
        case taskId = "task_id"
        case dedupeKey = "dedupe_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(
        id: String = UUID().uuidString,
        kind: FeedPostKind,
        authorAdminId: String?,
        authorName: String,
        body: String,
        taskId: String? = nil,
        media: [FeedMedia] = [],
        meta: FeedPostMeta = FeedPostMeta(),
        dedupeKey: String? = nil,
        pinned: Bool = false,
        createdAt: String = TaskDates.nowISO(),
        updatedAt: String = TaskDates.nowISO(),
        deletedAt: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.authorAdminId = authorAdminId
        self.authorName = authorName
        self.body = body
        self.taskId = taskId
        self.media = media
        self.meta = meta
        self.dedupeKey = dedupeKey
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString.lowercased()
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        kind = try c.decode(FeedPostKind.self, forKey: .kind)
        authorAdminId = try c.decodeIfPresent(String.self, forKey: .authorAdminId)
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? "ระบบ"
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        taskId = try c.decodeIfPresent(String.self, forKey: .taskId)
        media = (try? c.decode([FeedMedia].self, forKey: .media)) ?? []
        meta = (try? c.decode(FeedPostMeta.self, forKey: .meta)) ?? FeedPostMeta()
        dedupeKey = try c.decodeIfPresent(String.self, forKey: .dedupeKey)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}

struct FeedReaction: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var postId: String
    var adminId: String
    var type: FeedReactionType
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type
        case postId = "post_id"
        case adminId = "admin_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString.lowercased()
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        if let uuid = try? c.decode(UUID.self, forKey: .postId) {
            postId = uuid.uuidString.lowercased()
        } else {
            postId = try c.decode(String.self, forKey: .postId)
        }
        adminId = try c.decode(String.self, forKey: .adminId)
        type = try c.decode(FeedReactionType.self, forKey: .type)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    init(id: String = UUID().uuidString, postId: String, adminId: String, type: FeedReactionType) {
        self.id = id
        self.postId = postId
        self.adminId = adminId
        self.type = type
        self.createdAt = TaskDates.nowISO()
    }
}

struct FeedComment: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var postId: String
    var authorAdminId: String
    var authorName: String
    var body: String
    var createdAt: String
    var deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case authorAdminId = "author_admin_id"
        case authorName = "author_name"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            id = uuid.uuidString.lowercased()
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        if let uuid = try? c.decode(UUID.self, forKey: .postId) {
            postId = uuid.uuidString.lowercased()
        } else {
            postId = try c.decode(String.self, forKey: .postId)
        }
        authorAdminId = try c.decode(String.self, forKey: .authorAdminId)
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        deletedAt = try c.decodeIfPresent(String.self, forKey: .deletedAt)
    }

    init(
        id: String = UUID().uuidString,
        postId: String,
        authorAdminId: String,
        authorName: String,
        body: String
    ) {
        self.id = id
        self.postId = postId
        self.authorAdminId = authorAdminId
        self.authorName = authorName
        self.body = body
        self.createdAt = TaskDates.nowISO()
        self.deletedAt = nil
    }
}

// MARK: - Insert payloads (explicit encode so UUID columns get lowercase strings)

struct FeedPostInsert: Encodable, Sendable {
    var id: String
    var kind: String
    var authorAdminId: String?
    var authorName: String
    var body: String
    var taskId: String?
    var media: [FeedMedia]
    var meta: FeedPostMeta
    var dedupeKey: String?
    var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, body, media, meta, pinned
        case authorAdminId = "author_admin_id"
        case authorName = "author_name"
        case taskId = "task_id"
        case dedupeKey = "dedupe_key"
    }

    init(from post: FeedPost) {
        id = post.id
        kind = post.kind.rawValue
        authorAdminId = post.authorAdminId
        authorName = post.authorName
        body = post.body
        taskId = post.taskId
        media = post.media
        meta = post.meta
        dedupeKey = post.dedupeKey
        pinned = post.pinned
    }
}

struct FeedReactionInsert: Encodable, Sendable {
    var postId: String
    var adminId: String
    var type: String

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case adminId = "admin_id"
        case type
    }
}

struct FeedCommentInsert: Encodable, Sendable {
    var id: String
    var postId: String
    var authorAdminId: String
    var authorName: String
    var body: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case authorAdminId = "author_admin_id"
        case authorName = "author_name"
    }
}

// MARK: - Relative time

enum FeedTimeFormat {
    static func relative(_ iso: String, now: Date = Date()) -> String {
        guard let date = TaskDates.parseISO(iso) else { return "" }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "เมื่อสักครู่" }
        if seconds < 3600 { return "\(seconds / 60) นาทีที่แล้ว" }
        if seconds < 86_400 { return "\(seconds / 3600) ชม. ที่แล้ว" }
        if seconds < 86_400 * 7 { return "\(seconds / 86_400) วันที่แล้ว" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "th_TH")
        f.calendar = Calendar(identifier: .buddhist)
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
