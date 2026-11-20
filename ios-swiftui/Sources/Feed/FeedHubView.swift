import SwiftUI

private enum FeedHubSegment: String, CaseIterable, Identifiable {
    case feed = "ฟีดอัพเดต"
    case tasks = "งานของทีม"
    var id: String { rawValue }
}

struct FeedHubView: View {
    @Environment(AuthService.self) private var auth
    @Environment(FeedStore.self) private var feedStore
    @Environment(TaskStore.self) private var taskStore

    @Namespace private var tabIndicatorNS

    @State private var segment: FeedHubSegment = .feed
    @State private var showSearchBar = false
    @State private var searchQuery = ""
    @State private var onlyMedia = false
    @State private var showComposer = false
    @State private var showTaskEditor = false
    @State private var commentingItem: FeedPostItem?
    @State private var reactionsItem: FeedPostItem?
    @State private var editingPost: FeedPost?
    @State private var mediaViewer: FeedMediaViewerPayload?
    @State private var confirmDeleteId: String?
    @FocusState private var searchFocused: Bool

    private var isSuperAdmin: Bool {
        auth.currentAdmin?.role == .superAdmin
    }

    private var trimmedSearch: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var mediaPostCount: Int {
        feedStore.items.filter { !$0.post.media.isEmpty }.count
    }

    private var displayedPinned: [FeedPostItem] {
        applyLocalFilters(feedStore.pinnedItems)
    }

    private var displayedUnpinned: [FeedPostItem] {
        applyLocalFilters(feedStore.unpinnedItems)
    }

    private var hasDisplayedPosts: Bool {
        !displayedPinned.isEmpty || !displayedUnpinned.isEmpty
    }

    private var isFeedWhiteMode: Bool { segment == .feed }

    var body: some View {
        VStack(spacing: 0) {
            facebookTopTabBar

            if segment == .feed && showSearchBar {
                searchBarStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch segment {
                case .feed:
                    feedPage
                case .tasks:
                    TasksHubView()
                }
            }
        }
        .navigationTitle("อัพเดตงาน")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(isFeedWhiteMode ? FeedPalette.card : Color.clear, for: .navigationBar)
        .toolbarBackground(isFeedWhiteMode ? .visible : .automatic, for: .navigationBar)
        .toolbarColorScheme(isFeedWhiteMode ? .light : nil, for: .navigationBar)
        .sheet(isPresented: $showComposer) {
            FeedComposerSheet()
                .environment(auth)
                .environment(feedStore)
        }
        .sheet(isPresented: $showTaskEditor) {
            taskEditorSheet
        }
        .sheet(item: $commentingItem) { item in
            FeedCommentsSheet(
                post: item.post,
                reactionSummary: item.reactionSummary,
                reactionTotal: item.reactions.count
            )
            .environment(auth)
            .environment(feedStore)
            .environment(taskStore)
        }
        .sheet(item: $reactionsItem) { item in
            FeedReactionsSheet(
                reactions: item.reactions,
                admins: taskStore.admins,
                currentAdmin: auth.currentAdmin
            )
        }
        .sheet(item: $editingPost) { post in
            FeedEditPostSheet(
                post: post,
                authorAvatar: FeedAvatar.resolveAvatar(
                    adminId: post.authorAdminId,
                    admins: taskStore.admins,
                    currentAdmin: auth.currentAdmin
                )
            ) { updatedBody in
                Task { await feedStore.editPost(id: post.id, body: updatedBody) }
            }
        }
        .sheet(item: $mediaViewer) { payload in
            FeedMediaViewerSheet(media: payload.media, startIndex: payload.index)
        }
        .confirmationDialog("ลบโพสต์นี้?", isPresented: Binding(
            get: { confirmDeleteId != nil },
            set: { if !$0 { confirmDeleteId = nil } }
        ), titleVisibility: .visible) {
            Button("ลบโพสต์", role: .destructive) {
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
        .sensoryFeedback(.selection, trigger: segment)
    }

    // MARK: - Facebook Top Tab Bar

    private var facebookTopTabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(FeedHubSegment.allCases) { tab in
                    let isSelected = segment == tab
                    Button {
                        withAnimation(.snappy(duration: 0.24)) {
                            segment = tab
                            if tab != .feed {
                                showSearchBar = false
                                searchFocused = false
                            }
                        }
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 5) {
                                Image(systemName: tab == .feed ? "newspaper.fill" : "checklist")
                                    .font(.caption.weight(.semibold))
                                Text(tab.rawValue)
                                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                                    .lineLimit(1)
                                if tab == .tasks && taskStore.inboxCount > 0 {
                                    Text("\(taskStore.inboxCount)")
                                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(FeedPalette.fbRed))
                                }
                            }
                            .foregroundStyle(
                                isSelected
                                    ? FeedPalette.fbBlue
                                    : (isFeedWhiteMode ? FeedPalette.inkSecondary : AppTheme.inkMuted)
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)

                            ZStack {
                                Color.clear.frame(height: 2.5)
                                if isSelected {
                                    Capsule()
                                        .fill(FeedPalette.fbBlue)
                                        .frame(height: 2.5)
                                        .padding(.horizontal, 8)
                                        .matchedGeometryEffect(id: "fbTopTabIndicator", in: tabIndicatorNS)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            Spacer(minLength: 4)

            if segment == .feed {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            showSearchBar.toggle()
                            if showSearchBar {
                                searchFocused = true
                            } else {
                                searchQuery = ""
                                searchFocused = false
                            }
                        }
                    } label: {
                        Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(showSearchBar ? FeedPalette.fbBlue : FeedPalette.ink)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle().fill(showSearchBar ? FeedPalette.fbBlueSoft : FeedPalette.surfaceMuted)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ค้นหาในฟีด")

                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(FeedPalette.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(FeedPalette.surfaceMuted))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("สร้างโพสต์ใหม่")
                }
                .padding(.trailing, 14)
            }
        }
        .padding(.leading, 6)
        .background(isFeedWhiteMode ? FeedPalette.card : AppTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isFeedWhiteMode ? FeedPalette.hairline : AppTheme.hairline)
                .frame(height: 0.75)
        }
    }

    // MARK: - Live Search Bar

    private var searchBarStrip: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeedPalette.inkSecondary)
                TextField("ค้นหาโพสต์ ชื่อคน หรืองาน…", text: $searchQuery)
                    .font(.subheadline)
                    .foregroundStyle(FeedPalette.ink)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(FeedPalette.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ล้างคำค้นหา")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(FeedPalette.surfaceMuted, in: Capsule())

            Button("ยกเลิก") {
                withAnimation(.snappy(duration: 0.2)) {
                    searchQuery = ""
                    showSearchBar = false
                    searchFocused = false
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FeedPalette.fbBlue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(FeedPalette.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FeedPalette.hairline).frame(height: 0.75)
        }
    }

    // MARK: - Facebook White Feed Page

    private var feedPage: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                composerCard
                dailyHighlightsTray
                filterBarSection
                feedList
            }
            .padding(.bottom, 28)
        }
        .background(FeedPalette.canvas.ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .environment(\.colorScheme, .light)
        .refreshable {
            await feedStore.refresh()
            feedStore.markSeen()
        }
    }

    // MARK: - 1. Facebook Composer Card ("What's on your mind?")

    private var composerCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button {
                    showComposer = true
                } label: {
                    HStack(spacing: 11) {
                        FeedAvatar(
                            avatar: auth.currentAdmin?.avatar ?? "",
                            name: auth.currentAdmin?.displayName ?? "คุณ",
                            size: 42,
                            showOnlineDot: true
                        )
                        Text("คุณกำลังอัพเดตอะไรอยู่?")
                            .font(.subheadline)
                            .foregroundStyle(FeedPalette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 11)
                            .background(FeedPalette.surfaceMuted, in: Capsule())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("โพสต์อัพเดต")

                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(FeedPalette.fbGreen)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("แนบรูปภาพหรือวิดีโอ")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(FeedPalette.hairline)
                .frame(height: 0.75)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                composerQuickAction(
                    title: "รูป/วิดีโอ",
                    icon: "photo.fill",
                    color: FeedPalette.fbGreen
                ) {
                    showComposer = true
                }

                Rectangle().fill(FeedPalette.hairline).frame(width: 0.75, height: 20)

                composerQuickAction(
                    title: "แจ้งงาน",
                    icon: "checklist",
                    color: FeedPalette.fbBlue
                ) {
                    showTaskEditor = true
                }

                Rectangle().fill(FeedPalette.hairline).frame(width: 0.75, height: 20)

                composerQuickAction(
                    title: "โพสต์ด่วน",
                    icon: "square.and.pencil",
                    color: FeedPalette.fbOrange
                ) {
                    showComposer = true
                }
            }
            .padding(.vertical, 4)
        }
        .background(FeedPalette.card)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
    }

    private func composerQuickAction(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeedPalette.inkSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Facebook Stories-Style Daily Highlights Tray

    private var dailyHighlightsTray: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("สรุปความเคลื่อนไหววันนี้")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle()
                        .fill(FeedPalette.fbGreen)
                        .frame(width: 6, height: 6)
                    Text("เรียลไทม์")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FeedPalette.inkSecondary)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    storyHighlightCard(
                        title: "ทั้งหมด",
                        subtitle: "โพสต์ล่าสุด",
                        value: "\(feedStore.items.count)",
                        icon: "newspaper.fill",
                        tint: FeedPalette.fbBlue,
                        isSelected: feedStore.filter == .all && !onlyMedia
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            feedStore.filter = .all
                            onlyMedia = false
                        }
                    }

                    storyHighlightCard(
                        title: "ลาวันนี้",
                        subtitle: "สรุปประจำวัน",
                        value: "\(feedStore.todayLeaveCount)",
                        icon: "person.crop.circle.badge.moon",
                        tint: Color(hex: "#6366F1"),
                        isSelected: feedStore.filter == .system && !onlyMedia
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            feedStore.filter = .system
                            onlyMedia = false
                        }
                    }

                    storyHighlightCard(
                        title: "งานค้าง",
                        subtitle: "รอติดตาม",
                        value: "\(feedStore.openTaskNagCount)",
                        icon: "bell.badge.fill",
                        tint: FeedPalette.fbOrange,
                        isSelected: feedStore.filter == .tasks && !onlyMedia
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            feedStore.filter = .tasks
                            onlyMedia = false
                        }
                    }

                    storyHighlightCard(
                        title: "แจ้งงานวันนี้",
                        subtitle: "งานเข้าใหม่",
                        value: "\(feedStore.todayTaskCreatedCount)",
                        icon: "plus.circle.fill",
                        tint: FeedPalette.fbOk,
                        isSelected: false
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            feedStore.filter = .tasks
                            onlyMedia = false
                        }
                    }

                    storyHighlightCard(
                        title: "รูป & วิดีโอ",
                        subtitle: "อัปเดตหน้างาน",
                        value: "\(mediaPostCount)",
                        icon: "photo.stack.fill",
                        tint: FeedPalette.fbGreen,
                        isSelected: onlyMedia
                    ) {
                        withAnimation(.snappy(duration: 0.22)) {
                            feedStore.filter = .all
                            onlyMedia.toggle()
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 13)
        .background(FeedPalette.card)
        .overlay(alignment: .top) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
    }

    private func storyHighlightCard(
        title: String,
        subtitle: String,
        value: String,
        icon: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(tint))
                    .overlay(Circle().strokeBorder(FeedPalette.card, lineWidth: 2))

                Spacer(minLength: 10)

                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(FeedPalette.ink)
                    .contentTransition(.numericText())

                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FeedPalette.inkSecondary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(width: 108, height: 122, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.11), FeedPalette.surfaceSubtle],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? tint : FeedPalette.hairline, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
    }

    // MARK: - 3. Filter Pill Strip

    private var filterBarSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedFilter.allCases) { filter in
                    let isSelected = feedStore.filter == filter && !onlyMedia
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            feedStore.filter = filter
                            onlyMedia = false
                        }
                    } label: {
                        Text(filter.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? FeedPalette.fbBlue : FeedPalette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? FeedPalette.fbBlueSoft : FeedPalette.surfaceMuted,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        onlyMedia.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.fill")
                            .font(.caption2.weight(.bold))
                        Text("มีรูป/วิดีโอ")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(onlyMedia ? FeedPalette.fbGreen : FeedPalette.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        onlyMedia ? FeedPalette.fbGreen.opacity(0.14) : FeedPalette.surfaceMuted,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(onlyMedia ? .isSelected : [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(FeedPalette.card)
        .overlay(alignment: .top) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
        .sensoryFeedback(.selection, trigger: "\(feedStore.filter.rawValue)-\(onlyMedia)")
    }

    // MARK: - 4. Feed Post Stream

    @ViewBuilder
    private var feedList: some View {
        if feedStore.isLoading && feedStore.items.isEmpty {
            ForEach(0..<3, id: \.self) { _ in
                feedSkeletonCard
            }
        } else if let error = feedStore.errorMessage, feedStore.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(FeedPalette.inkTertiary)
                Text("โหลดฟีดไม่สำเร็จ")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(FeedPalette.inkSecondary)
                    .multilineTextAlignment(.center)
                Button("ลองโหลดใหม่") {
                    Task { await feedStore.refresh() }
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(FeedPalette.fbBlue, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
            .padding(.horizontal, 24)
            .background(FeedPalette.card)
        } else if !hasDisplayedPosts {
            emptyFeedCard
        } else {
            if !displayedPinned.isEmpty {
                ForEach(displayedPinned) { item in
                    postCard(item)
                }
            }
            ForEach(displayedUnpinned) { item in
                postCard(item)
                    .onAppear {
                        if item.id == displayedUnpinned.last?.id, trimmedSearch.isEmpty {
                            Task { await feedStore.loadMore() }
                        }
                    }
            }
            if feedStore.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(FeedPalette.fbBlue)
                    Text("กำลังโหลดโพสต์เพิ่มเติม…")
                        .font(.caption)
                        .foregroundStyle(FeedPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if !feedStore.hasMore && trimmedSearch.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(FeedPalette.inkTertiary)
                    Text("แสดงอัพเดตครบทั้งหมดแล้ว")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(FeedPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
        }
    }

    private var emptyFeedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: trimmedSearch.isEmpty ? "newspaper" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(FeedPalette.inkTertiary)
            Text(trimmedSearch.isEmpty ? "ยังไม่มีโพสต์ในหมวดนี้" : "ไม่พบโพสต์ที่ตรงกับ «\(trimmedSearch)»")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FeedPalette.ink)
            Text(
                trimmedSearch.isEmpty
                    ? "เริ่มแชร์ความคืบหน้าหน้างาน รูปถ่าย หรือแจ้งงานให้ทีมได้เลย"
                    : "ลองเปลี่ยนคำค้นหาหรือเลือกดูโพสต์ทั้งหมด"
            )
            .font(.caption)
            .foregroundStyle(FeedPalette.inkSecondary)
            .multilineTextAlignment(.center)

            if !trimmedSearch.isEmpty || onlyMedia || feedStore.filter != .all {
                Button("ดูโพสต์ทั้งหมด") {
                    withAnimation(.snappy(duration: 0.2)) {
                        searchQuery = ""
                        onlyMedia = false
                        feedStore.filter = .all
                    }
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(FeedPalette.fbBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(FeedPalette.fbBlueSoft, in: Capsule())
                .padding(.top, 4)
            } else {
                Button("สร้างโพสต์แรก") {
                    showComposer = true
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(FeedPalette.fbBlue, in: Capsule())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
        .background(FeedPalette.card)
    }

    private var feedSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(FeedPalette.surfaceMuted)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(FeedPalette.surfaceMuted)
                        .frame(width: 130, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(FeedPalette.surfaceMuted)
                        .frame(width: 80, height: 10)
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(FeedPalette.surfaceMuted)
                .frame(height: 12)
            RoundedRectangle(cornerRadius: 4)
                .fill(FeedPalette.surfaceMuted)
                .frame(width: 220, height: 12)
            RoundedRectangle(cornerRadius: 10)
                .fill(FeedPalette.surfaceMuted)
                .frame(height: 160)
        }
        .padding(16)
        .background(FeedPalette.card)
        .redacted(reason: .placeholder)
    }

    // MARK: - Post Card Wiring

    private func postCard(_ item: FeedPostItem) -> some View {
        let task: WorkTask? = item.post.taskId.flatMap { id in
            taskStore.tasks.first { $0.id == id }
        }
        let authorAvatar = FeedAvatar.resolveAvatar(
            adminId: item.post.authorAdminId,
            admins: taskStore.admins,
            currentAdmin: auth.currentAdmin
        )
        return FeedPostCard(
            item: item,
            adminId: auth.currentAdmin?.id ?? "",
            isSuperAdmin: isSuperAdmin,
            authorAvatar: authorAvatar,
            currentUserAvatar: auth.currentAdmin?.avatar ?? "",
            currentUserName: auth.currentAdmin?.displayName ?? "คุณ",
            taskStatus: task?.status,
            onReact: { type in
                Task { await feedStore.setReaction(postId: item.id, type: type) }
            },
            onShowReactions: {
                reactionsItem = item
            },
            onComment: { commentingItem = item },
            onEdit: { editingPost = item.post },
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

    private func applyLocalFilters(_ source: [FeedPostItem]) -> [FeedPostItem] {
        var list = source
        if onlyMedia {
            list = list.filter { !$0.post.media.isEmpty }
        }
        let q = trimmedSearch
        guard !q.isEmpty else { return list }
        return list.filter { item in
            let p = item.post
            if p.body.localizedCaseInsensitiveContains(q) { return true }
            if p.authorName.localizedCaseInsensitiveContains(q) { return true }
            if let title = p.meta.title, title.localizedCaseInsensitiveContains(q) { return true }
            if let assignee = p.meta.assigneeName, assignee.localizedCaseInsensitiveContains(q) { return true }
            if let leaves = p.meta.leaves, leaves.contains(where: { $0.name.localizedCaseInsensitiveContains(q) }) {
                return true
            }
            return false
        }
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
}

private struct FeedMediaViewerPayload: Identifiable {
    let id = UUID()
    let media: [FeedMedia]
    let index: Int
}
