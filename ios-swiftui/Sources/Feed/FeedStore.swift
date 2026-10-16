import Foundation
import Observation
import Supabase

/// Enriched post for the feed list (reactions + comment count attached).
struct FeedPostItem: Identifiable, Hashable, Sendable {
    var post: FeedPost
    var reactions: [FeedReaction]
    var commentCount: Int

    var id: String { post.id }

    func myReaction(adminId: String) -> FeedReactionType? {
        reactions.first { $0.adminId == adminId }?.type
    }

    var reactionSummary: [(FeedReactionType, Int)] {
        var counts: [FeedReactionType: Int] = [:]
        for r in reactions { counts[r.type, default: 0] += 1 }
        return FeedReactionType.allCases.compactMap { type in
            guard let n = counts[type], n > 0 else { return nil }
            return (type, n)
        }
    }
}

enum FeedFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case team
    case tasks
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "ทั้งหมด"
        case .team: return "โพสต์ทีม"
        case .tasks: return "งาน"
        case .system: return "ระบบ"
        }
    }

    func matches(_ post: FeedPost) -> Bool {
        switch self {
        case .all: return true
        case .team: return post.kind == .admin
        case .tasks: return post.kind.isTaskRelated
        case .system: return post.kind.isSystem
        }
    }
}

/// Loads and mutates the อัพเดตงาน feed. Optimistic local updates, then write to Supabase.
@MainActor
@Observable
final class FeedStore {
    var items: [FeedPostItem] = []
    var isLoading = false
    var isLoadingMore = false
    var hasMore = true
    var errorMessage: String?
    var filter: FeedFilter = .all
    var currentAdminId = ""
    var unreadCount = 0

    @ObservationIgnored private var dataService: SupabaseService?
    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var streamTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var lastSeenAt: Date = FeedStore.loadLastSeen()

    private static let lastSeenKey = "feed.lastSeenAt"
    private static let pageSize = 20

    func configure(dataService: SupabaseService) {
        self.dataService = dataService
    }

    var filteredItems: [FeedPostItem] {
        let visible = Self.collapseNags(items)
        return visible.filter { filter.matches($0.post) }
    }

    var pinnedItems: [FeedPostItem] {
        filteredItems.filter(\.post.pinned)
    }

    var unpinnedItems: [FeedPostItem] {
        filteredItems.filter { !$0.post.pinned }
    }

    // MARK: - Today strip stats

    var todayLeaveCount: Int {
        let today = DashboardAggregations.todayYMD()
        return items
            .first { $0.post.kind == .leaveDigest && $0.post.meta.date == today }
            .flatMap { $0.post.meta.leaves?.count } ?? 0
    }

    var openTaskNagCount: Int {
        Set(
            items
                .filter { $0.post.kind == .taskNag }
                .compactMap(\.post.taskId)
        ).count
    }

    var todayTaskCreatedCount: Int {
        let today = DashboardAggregations.todayYMD()
        return items.filter {
            $0.post.kind == .taskCreated && $0.post.createdAt.hasPrefix(today)
        }.count
    }

    // MARK: - Loading

    func load() async {
        guard let dataService else { return }
        if items.isEmpty { isLoading = true }
        do {
            let posts = try await dataService.fetchFeedPosts(limit: Self.pageSize)
            let enriched = try await enrich(posts, service: dataService)
            items = enriched
            hasMore = posts.count >= Self.pageSize
            errorMessage = nil
            recomputeUnread()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadIfNeeded() async {
        if !items.isEmpty { return }
        await load()
    }

    func refresh() async {
        await load()
    }

    func loadMore() async {
        guard let dataService, hasMore, !isLoadingMore, !isLoading else { return }
        guard let oldest = items.last?.post.createdAt, !oldest.isEmpty else { return }
        isLoadingMore = true
        do {
            let posts = try await dataService.fetchFeedPosts(before: oldest, limit: Self.pageSize)
            let enriched = try await enrich(posts, service: dataService)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: enriched.filter { !existing.contains($0.id) })
            hasMore = posts.count >= Self.pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    func markSeen() {
        lastSeenAt = Date()
        UserDefaults.standard.set(lastSeenAt.timeIntervalSince1970, forKey: Self.lastSeenKey)
        unreadCount = 0
    }

    // MARK: - Mutations

    func createPost(
        body: String,
        media: [FeedMedia],
        authorAdminId: String,
        authorName: String
    ) async throws {
        guard let dataService else { return }
        let post = FeedPost(
            kind: .admin,
            authorAdminId: authorAdminId,
            authorName: authorName,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            media: media
        )
        let item = FeedPostItem(post: post, reactions: [], commentCount: 0)
        items.insert(item, at: 0)
        do {
            let saved = try await dataService.insertFeedPost(post)
            replace(saved, reactions: [], commentCount: 0)
        } catch {
            items.removeAll { $0.id == post.id }
            throw error
        }
    }

    func postTaskCreated(_ task: WorkTask) async {
        guard let dataService else { return }
        guard task.visibility == .shared else { return }
        let body = [
            "แจ้งงานใหม่: \(task.title)",
            task.assigneeName.map { "มอบหมายให้: \($0)" },
            task.note.flatMap { $0.isEmpty ? nil : $0 },
        ].compactMap { $0 }.joined(separator: "\n")
        let post = FeedPost(
            kind: .taskCreated,
            authorAdminId: task.ownerAdminId,
            authorName: task.ownerName ?? "แอดมิน",
            body: body,
            taskId: task.id,
            meta: FeedPostMeta(
                date: task.dueDate,
                assigneeName: task.assigneeName,
                priority: task.priority.rawValue,
                title: task.title,
                dueDate: task.dueDate
            ),
            dedupeKey: "task_created:\(task.id)"
        )
        items.insert(FeedPostItem(post: post, reactions: [], commentCount: 0), at: 0)
        if let saved = try? await dataService.insertFeedPost(post) {
            replace(saved, reactions: [], commentCount: 0)
        }
    }

    func postTaskDone(_ task: WorkTask, byAdminId: String, byName: String) async {
        guard let dataService else { return }
        guard task.visibility == .shared else { return }
        let body = "ปิดงานแล้ว: \(task.title)"
        let post = FeedPost(
            kind: .taskDone,
            authorAdminId: byAdminId,
            authorName: byName,
            body: body,
            taskId: task.id,
            meta: FeedPostMeta(
                assigneeName: task.assigneeName,
                priority: task.priority.rawValue,
                title: task.title,
                dueDate: task.dueDate
            )
        )
        items.insert(FeedPostItem(post: post, reactions: [], commentCount: 0), at: 0)
        if let saved = try? await dataService.insertFeedPost(post) {
            replace(saved, reactions: [], commentCount: 0)
        }
    }

    func setReaction(postId: String, type: FeedReactionType?) async {
        guard let dataService, !currentAdminId.isEmpty else { return }
        guard let idx = items.firstIndex(where: { $0.id == postId }) else { return }
        let previous = items[idx].reactions
        var next = previous.filter { $0.adminId != currentAdminId }
        if let type {
            next.append(FeedReaction(postId: postId, adminId: currentAdminId, type: type))
        }
        items[idx].reactions = next

        do {
            if let type {
                try await dataService.upsertFeedReaction(postId: postId, adminId: currentAdminId, type: type)
            } else {
                try await dataService.deleteFeedReaction(postId: postId, adminId: currentAdminId)
            }
        } catch {
            items[idx].reactions = previous
            errorMessage = error.localizedDescription
        }
    }

    func toggleLike(postId: String) async {
        guard let item = items.first(where: { $0.id == postId }) else { return }
        let current = item.myReaction(adminId: currentAdminId)
        await setReaction(postId: postId, type: current == .like ? nil : .like)
    }

    func editPost(id: String, body: String) async {
        guard let dataService else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = items[idx].post.body
        items[idx].post.body = trimmed
        do {
            let saved = try await dataService.updateFeedPostBody(id: id, body: trimmed)
            items[idx].post = saved
        } catch {
            items[idx].post.body = snapshot
            errorMessage = error.localizedDescription
        }
    }

    func deletePost(id: String) async {
        guard let dataService else { return }
        let snapshot = items
        items.removeAll { $0.id == id }
        do {
            try await dataService.softDeleteFeedPost(id: id)
        } catch {
            items = snapshot
            errorMessage = error.localizedDescription
        }
    }

    func setPinned(id: String, pinned: Bool) async {
        guard let dataService else { return }
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let snapshot = items[idx].post.pinned
        items[idx].post.pinned = pinned
        do {
            let saved = try await dataService.setFeedPostPinned(id: id, pinned: pinned)
            items[idx].post = saved
        } catch {
            items[idx].post.pinned = snapshot
            errorMessage = error.localizedDescription
        }
    }

    func fetchComments(postId: String) async throws -> [FeedComment] {
        guard let dataService else { return [] }
        return try await dataService.fetchFeedComments(postId: postId)
    }

    func addComment(_ comment: FeedComment) async throws {
        guard let dataService else { return }
        if let idx = items.firstIndex(where: { $0.id == comment.postId }) {
            items[idx].commentCount += 1
        }
        _ = try await dataService.insertFeedComment(comment)
    }

    func bumpCommentCount(postId: String, delta: Int) {
        guard let idx = items.firstIndex(where: { $0.id == postId }) else { return }
        items[idx].commentCount = max(0, items[idx].commentCount + delta)
    }

    // MARK: - Realtime

    func startRealtime() {
        stopRealtime()
        guard let dataService else { return }
        let channel = dataService.realtimeChannel("realtime:public:feed_posts")
        self.channel = channel

        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "feed_posts")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "feed_posts")
        streamTasks.append(Task { [weak self] in
            for await action in inserts { await self?.handleRealtimeUpsert(action.record) }
        })
        streamTasks.append(Task { [weak self] in
            for await action in updates { await self?.handleRealtimeUpsert(action.record) }
        })

        Task {
            try? await channel.subscribeWithError()
        }
    }

    func stopRealtime() {
        streamTasks.forEach { $0.cancel() }
        streamTasks.removeAll()
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }

    // MARK: - Helpers

    /// Keep only the latest task_nag per task_id so the feed stays readable.
    private static func collapseNags(_ items: [FeedPostItem]) -> [FeedPostItem] {
        var seenTask = Set<String>()
        var out: [FeedPostItem] = []
        out.reserveCapacity(items.count)
        for item in items {
            if item.post.kind == .taskNag, let taskId = item.post.taskId {
                if seenTask.contains(taskId) { continue }
                seenTask.insert(taskId)
            }
            out.append(item)
        }
        return out
    }

    private func enrich(_ posts: [FeedPost], service: SupabaseService) async throws -> [FeedPostItem] {
        let ids = posts.map(\.id)
        async let reactions = service.fetchFeedReactions(postIds: ids)
        async let counts = service.fetchFeedCommentCounts(postIds: ids)
        let (rx, cc) = try await (reactions, counts)
        var byPost: [String: [FeedReaction]] = [:]
        for r in rx { byPost[r.postId, default: []].append(r) }
        return posts.map {
            FeedPostItem(
                post: $0,
                reactions: byPost[$0.id] ?? [],
                commentCount: cc[$0.id] ?? 0
            )
        }
    }

    private func replace(_ post: FeedPost, reactions: [FeedReaction], commentCount: Int) {
        let item = FeedPostItem(post: post, reactions: reactions, commentCount: commentCount)
        if let idx = items.firstIndex(where: { $0.id == post.id || ($0.post.dedupeKey != nil && $0.post.dedupeKey == post.dedupeKey) }) {
            let keepRx = items[idx].reactions.isEmpty ? reactions : items[idx].reactions
            let keepCc = items[idx].commentCount > 0 ? items[idx].commentCount : commentCount
            items[idx] = FeedPostItem(post: post, reactions: keepRx, commentCount: keepCc)
        } else {
            items.insert(item, at: 0)
        }
    }

    private func handleRealtimeUpsert(_ record: JSONObject) async {
        guard let data = try? JSONEncoder().encode(record),
              let post = try? JSONDecoder().decode(FeedPost.self, from: data)
        else { return }
        if post.deletedAt != nil {
            items.removeAll { $0.id == post.id }
            return
        }
        if let idx = items.firstIndex(where: { $0.id == post.id }) {
            items[idx].post = post
        } else if let dedupe = post.dedupeKey,
                  let idx = items.firstIndex(where: { $0.post.dedupeKey == dedupe }) {
            items[idx].post = post
        } else {
            items.insert(FeedPostItem(post: post, reactions: [], commentCount: 0), at: 0)
            recomputeUnread()
        }
    }

    private func recomputeUnread() {
        unreadCount = items.filter { item in
            guard let date = TaskDates.parseISO(item.post.createdAt) else { return false }
            return date > lastSeenAt
        }.count
    }

    private static func loadLastSeen() -> Date {
        let t = UserDefaults.standard.double(forKey: lastSeenKey)
        if t > 0 { return Date(timeIntervalSince1970: t) }
        return Date().addingTimeInterval(-86_400)
    }
}
