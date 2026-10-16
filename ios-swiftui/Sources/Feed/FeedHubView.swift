import SwiftUI

private enum FeedHubSegment: String, CaseIterable, Identifiable {
    case feed = "ฟีด"
    case tasks = "งาน"
    var id: String { rawValue }
}

struct FeedHubView: View {
    @Environment(AuthService.self) private var auth
    @Environment(FeedStore.self) private var feedStore
    @Environment(TaskStore.self) private var taskStore

    @State private var segment: FeedHubSegment = .feed
    @State private var showComposer = false
    @State private var showTaskEditor = false
    @State private var commentingPost: FeedPost?
    @State private var editingPost: FeedPost?
    @State private var editDraft = ""
    @State private var mediaViewer: FeedMediaViewerPayload?
    @State private var confirmDeleteId: String?

    private var isSuperAdmin: Bool {
        auth.currentAdmin?.role == .superAdmin
    }

    var body: some View {
        Group {
            switch segment {
            case .feed:
                feedPage
            case .tasks:
                TasksHubView()
            }
        }
        .navigationTitle("อัพเดตงาน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showComposer) {
            FeedComposerSheet()
                .environment(auth)
                .environment(feedStore)
        }
        .sheet(isPresented: $showTaskEditor) {
            taskEditorSheet
        }
        .sheet(item: $commentingPost) { post in
            FeedCommentsSheet(post: post)
                .environment(auth)
                .environment(feedStore)
        }
        .sheet(item: $mediaViewer) { payload in
            FeedMediaViewerSheet(media: payload.media, startIndex: payload.index)
        }
        .alert("แก้ไขโพสต์", isPresented: Binding(
            get: { editingPost != nil },
            set: { if !$0 { editingPost = nil } }
        )) {
            TextField("ข้อความ", text: $editDraft)
            Button("บันทึก") {
                if let id = editingPost?.id {
                    Task { await feedStore.editPost(id: id, body: editDraft) }
                }
                editingPost = nil
            }
            Button("ยกเลิก", role: .cancel) { editingPost = nil }
        }
        .confirmationDialog("ลบโพสต์นี้?", isPresented: Binding(
            get: { confirmDeleteId != nil },
            set: { if !$0 { confirmDeleteId = nil } }
        ), titleVisibility: .visible) {
            Button("ลบ", role: .destructive) {
                if let id = confirmDeleteId {
                    Task { await feedStore.deletePost(id: id) }
                }
                confirmDeleteId = nil
            }
            Button("ยกเลิก", role: .cancel) { confirmDeleteId = nil }
        }
        .task {
            feedStore.currentAdminId = auth.currentAdmin?.id ?? ""
            await feedStore.loadIfNeeded()
            feedStore.startRealtime()
            feedStore.markSeen()
        }
        .onDisappear {
            feedStore.stopRealtime()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("ส่วน", selection: $segment) {
                ForEach(FeedHubSegment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
        if segment == .feed {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("โพสต์อัพเดต")
            }
        }
    }

    // MARK: - Feed page

    private var feedPage: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.spaceMD) {
                todayStrip
                composerPrompt
                filterChips
                feedList
            }
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.bottom, 88)
        }
        .background(DashboardBackground())
        .refreshable {
            await feedStore.refresh()
            feedStore.markSeen()
        }
        .overlay(alignment: .bottomTrailing) {
            fab
        }
    }

    private var todayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                highlightChip(
                    title: "ลาวันนี้",
                    value: "\(feedStore.todayLeaveCount)",
                    icon: "person.crop.circle.badge.moon",
                    tint: AppTheme.slate
                ) {
                    feedStore.filter = .system
                }
                highlightChip(
                    title: "งานค้าง",
                    value: "\(feedStore.openTaskNagCount)",
                    icon: "bell.badge.fill",
                    tint: AppTheme.warning
                ) {
                    feedStore.filter = .tasks
                }
                highlightChip(
                    title: "แจ้งงานวันนี้",
                    value: "\(feedStore.todayTaskCreatedCount)",
                    icon: "plus.circle.fill",
                    tint: AppTheme.info
                ) {
                    feedStore.filter = .tasks
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func highlightChip(
        title: String,
        value: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(AppTheme.spaceMD)
            .frame(minWidth: 120, alignment: .leading)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
    }

    private var composerPrompt: some View {
        HStack(spacing: 12) {
            Button {
                showComposer = true
            } label: {
                HStack(spacing: 12) {
                    AvatarCircle(
                        avatar: auth.currentAdmin?.avatar ?? "",
                        initials: initials(auth.currentAdmin?.displayName ?? "?"),
                        size: 40
                    )
                    Text("อัพเดตอะไรวันนี้?")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(AppTheme.surfaceSoft, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("โพสต์อัพเดต")

            Button {
                showComposer = true
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(AppTheme.brand)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("แนบรูป")

            Button {
                showTaskEditor = true
            } label: {
                Image(systemName: "checklist")
                    .foregroundStyle(AppTheme.info)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("แจ้งงาน")
        }
        .padding(AppTheme.spaceMD)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilter.allCases) { filter in
                    let selected = feedStore.filter == filter
                    Button {
                        withAnimation(.snappy) { feedStore.filter = filter }
                    } label: {
                        Text(filter.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : AppTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selected ? AppTheme.brand : AppTheme.surface,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var feedList: some View {
        if feedStore.isLoading && feedStore.items.isEmpty {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surfaceSoft)
                    .frame(height: 140)
                    .redacted(reason: .placeholder)
            }
        } else if let error = feedStore.errorMessage, feedStore.items.isEmpty {
            ContentUnavailableView(
                "โหลดฟีดไม่ได้",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
            .padding(.vertical, 40)
        } else if feedStore.filteredItems.isEmpty {
            ContentUnavailableView(
                "ยังไม่มีอัพเดต",
                systemImage: "newspaper",
                description: Text("แตะ «โพสต์» เพื่อเล่าความคืบหน้าให้ทีม หรือแจ้งงานจากปุ่มด้านล่าง")
            )
            .padding(.vertical, 40)
        } else {
            if !feedStore.pinnedItems.isEmpty {
                ForEach(feedStore.pinnedItems) { item in
                    postCard(item)
                }
            }
            ForEach(feedStore.unpinnedItems) { item in
                postCard(item)
                    .onAppear {
                        if item.id == feedStore.unpinnedItems.last?.id {
                            Task { await feedStore.loadMore() }
                        }
                    }
            }
            if feedStore.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func postCard(_ item: FeedPostItem) -> some View {
        let task: WorkTask? = item.post.taskId.flatMap { id in
            taskStore.tasks.first { $0.id == id }
        }
        return FeedPostCard(
            item: item,
            adminId: auth.currentAdmin?.id ?? "",
            isSuperAdmin: isSuperAdmin,
            taskStatus: task?.status,
            onReact: { type in
                Task { await feedStore.setReaction(postId: item.id, type: type) }
            },
            onComment: { commentingPost = item.post },
            onEdit: {
                editingPost = item.post
                editDraft = item.post.body
            },
            onDelete: { confirmDeleteId = item.id },
            onPin: {
                Task { await feedStore.setPinned(id: item.id, pinned: !item.post.pinned) }
            },
            onStartTask: task.map { t in
                {
                    Task {
                        await taskStore.setStatus(t, to: .inProgress)
                    }
                }
            },
            onCompleteTask: task.map { t in
                {
                    Task { await taskStore.setStatus(t, to: .done) }
                }
            },
            onOpenMedia: { index in
                mediaViewer = FeedMediaViewerPayload(media: item.post.media, index: index)
            }
        )
    }

    private var fab: some View {
        Menu {
            Button {
                showComposer = true
            } label: {
                Label("โพสต์อัพเดต", systemImage: "square.and.pencil")
            }
            Button {
                showTaskEditor = true
            } label: {
                Label("แจ้งงาน", systemImage: "checklist")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.brand, in: Circle())
                .shadow(color: AppTheme.brand.opacity(0.35), radius: 10, y: 4)
        }
        .padding(.trailing, AppTheme.spaceLG)
        .padding(.bottom, AppTheme.spaceLG)
        .accessibilityLabel("สร้างอัพเดตหรือแจ้งงาน")
    }

    @ViewBuilder
    private var taskEditorSheet: some View {
        if let admin = auth.currentAdmin {
            TaskEditorSheet(
                task: WorkTask.new(ownerAdminId: admin.id, ownerName: admin.displayName),
                isNew: true,
                admins: taskStore.admins,
                onSave: { tasks in
                    Task { await taskStore.saveAll(tasks, adminId: admin.id) }
                }
            )
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}

private struct FeedMediaViewerPayload: Identifiable {
    let id = UUID()
    let media: [FeedMedia]
    let index: Int
}
