import SwiftUI

struct FeedPostCard: View {
    let item: FeedPostItem
    let adminId: String
    let isSuperAdmin: Bool
    var authorAvatar: String = ""
    var currentUserAvatar: String = ""
    var currentUserName: String = ""
    var taskStatus: TaskStatus?
    var onReact: (FeedReactionType?) -> Void
    var onShowReactions: () -> Void = {}
    var onComment: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onPin: () -> Void
    var onStartTask: (() -> Void)?
    var onCompleteTask: (() -> Void)?
    var onOpenMedia: (Int) -> Void

    @State private var expanded = false
    @State private var showReactionPicker = false
    @State private var suppressNextTap = false
    @State private var likeBounce = false
    @State private var reactHapticToken = 0
    @State private var dockHapticToken = 0
    @State private var taskCompleteHapticToken = 0

    private var post: FeedPost { item.post }
    private var canManage: Bool {
        isSuperAdmin || post.authorAdminId == adminId
    }
    private var myReaction: FeedReactionType? {
        item.myReaction(adminId: adminId)
    }

    private var isEdited: Bool {
        guard post.kind == .admin,
              let created = TaskDates.parseISO(post.createdAt),
              let updated = TaskDates.parseISO(post.updatedAt) else {
            return false
        }
        return abs(updated.timeIntervalSince(created)) > 15
    }

    private var shareText: String {
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let title = post.meta.title, !title.isEmpty { return title }
        return "\(post.authorName) · \(post.kind.label)"
    }

    private var hasEngagementSummary: Bool {
        !item.reactionSummary.isEmpty || item.commentCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.pinned {
                pinnedBanner
            }

            header
                .padding(.horizontal, 16)
                .padding(.top, post.pinned ? 10 : 14)
                .padding(.bottom, 10)

            bodyText

            if post.kind == .leaveDigest {
                leaveBlock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if post.kind.isTaskRelated {
                taskBlock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if !post.media.isEmpty {
                FeedMediaGrid(media: post.media, edgeToEdge: true, onTap: onOpenMedia)
                    .padding(.top, 2)
            }

            if hasEngagementSummary {
                summaryRow
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }

            Rectangle()
                .fill(FeedPalette.hairline)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, hasEngagementSummary ? 0 : 8)

            actionBar
                .padding(.horizontal, 8)
                .padding(.vertical, 2)

            if item.commentCount > 0 {
                quickCommentRow
            }
        }
        .background(FeedPalette.card)
        .overlay(alignment: .top) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(FeedPalette.hairline.opacity(0.8)).frame(height: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
            if showReactionPicker {
                FeedFloatingReactionDock(
                    currentReaction: myReaction,
                    onSelect: { selected in
                        withAnimation(.snappy(duration: 0.2)) {
                            showReactionPicker = false
                        }
                        reactHapticToken += 1
                        triggerLikeBounce()
                        onReact(myReaction == selected ? nil : selected)
                    },
                    onDismiss: {
                        withAnimation(.snappy(duration: 0.18)) {
                            showReactionPicker = false
                        }
                    }
                )
                .padding(.leading, 12)
                .padding(.bottom, item.commentCount > 0 ? 94 : 52)
                .transition(.scale(scale: 0.84, anchor: .bottomLeading).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .contextMenu { postMenuItems }
        .onDisappear { showReactionPicker = false }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: reactHapticToken)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: dockHapticToken)
        .sensoryFeedback(.success, trigger: taskCompleteHapticToken)
    }

    // MARK: - Pinned Banner

    private var pinnedBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FeedPalette.fbBlue)
                Text("โพสต์ปักหมุด")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(FeedPalette.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(FeedPalette.surfaceSubtle)

            Rectangle()
                .fill(FeedPalette.hairline)
                .frame(height: 0.5)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            FeedAvatar(
                avatar: authorAvatar,
                name: post.authorName,
                size: 42,
                badgeSymbol: post.kind == .admin ? nil : post.kind.systemImage,
                badgeColor: kindColor
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FeedPalette.ink)
                        .lineLimit(1)

                    if post.kind != .admin {
                        Text(post.kind.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(kindColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(kindColor.opacity(0.11), in: Capsule())
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    Text(FeedTimeFormat.relative(post.createdAt))
                        .font(.caption)
                        .foregroundStyle(FeedPalette.inkSecondary)
                    Text("·")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FeedPalette.inkTertiary)
                    Image(systemName: post.kind.isSystem ? "bolt.fill" : "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FeedPalette.inkTertiary)
                    if isEdited {
                        Text("· แก้ไขแล้ว")
                            .font(.caption2)
                            .foregroundStyle(FeedPalette.inkTertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                postMenuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedPalette.inkSecondary)
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .accessibilityLabel("ตัวเลือกโพสต์")
        }
    }

    private var kindColor: Color {
        switch post.kind {
        case .admin: return FeedPalette.fbBlue
        case .taskCreated: return FeedPalette.fbBlue
        case .taskDone: return FeedPalette.fbOk
        case .taskNag: return FeedPalette.fbOrange
        case .leaveDigest: return Color(hex: "#6366F1")
        }
    }

    // MARK: - Body Text

    @ViewBuilder
    private var bodyText: some View {
        let text = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let isLargeStatus = post.kind == .admin
                && post.media.isEmpty
                && text.count <= 85
                && text.split(separator: "\n").count <= 2

            VStack(alignment: .leading, spacing: 5) {
                Text(text)
                    .font(isLargeStatus ? .title3.weight(.medium) : .body)
                    .lineSpacing(isLargeStatus ? 4 : 3)
                    .foregroundStyle(FeedPalette.ink)
                    .lineLimit(expanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if needsExpand(text) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "ดูน้อยลง" : "ดูเพิ่มเติม")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FeedPalette.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, post.media.isEmpty ? 10 : 12)
        }
    }

    // MARK: - Leave Digest Attachment

    private var leaveBlock: some View {
        let leaves = post.meta.leaves ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: "#6366F1"))
                Text("สรุปลางานประจำวัน")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)
                Spacer(minLength: 0)
                if !leaves.isEmpty {
                    Text("\(leaves.count) คน")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color(hex: "#6366F1"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#6366F1").opacity(0.11), in: Capsule())
                }
            }

            if leaves.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(FeedPalette.fbOk)
                    Text("วันนี้ทุกคนมาทำงานครบ")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeedPalette.ink)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(leaves.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle()
                                .fill(FeedPalette.hairline)
                                .frame(height: 0.5)
                                .padding(.leading, 40)
                        }
                        HStack(spacing: 10) {
                            FeedAvatar(avatar: "", name: entry.name, size: 30)
                            Text(entry.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FeedPalette.ink)
                            Spacer(minLength: 6)
                            Text(entry.kindLabel + (entry.halfDay ? " · ครึ่งวัน" : ""))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(leaveTagColor(entry.kind))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(leaveTagColor(entry.kind).opacity(0.11), in: Capsule())
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FeedPalette.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FeedPalette.hairline, lineWidth: 1)
        )
    }

    private func leaveTagColor(_ kind: String) -> Color {
        switch kind {
        case "sick": return FeedPalette.fbRed
        case "personal": return FeedPalette.fbOrange
        default: return FeedPalette.inkSecondary
        }
    }

    // MARK: - Task Attachment Card

    private var taskBlock: some View {
        let overdue = post.meta.daysOverdue ?? 0
        let status = taskStatus ?? (post.kind == .taskDone ? .done : .todo)
        let accent = taskAccentColor(status: status, overdue: overdue)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Label(status.label, systemImage: status.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.12), in: Capsule())

                    if overdue > 0 && status != .done {
                        Text("ค้างมา \(overdue) วัน")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                overdue >= 3 ? FeedPalette.fbRed : FeedPalette.fbOrange,
                                in: Capsule()
                            )
                    }
                    Spacer(minLength: 0)
                }

                if let title = post.meta.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(FeedPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    if let name = post.meta.assigneeName, !name.isEmpty {
                        Label(name, systemImage: "person.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FeedPalette.inkSecondary)
                            .lineLimit(1)
                    }
                    if let due = post.meta.dueDate, !due.isEmpty {
                        Label("กำหนด \(due)", systemImage: "calendar")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FeedPalette.inkSecondary)
                            .lineLimit(1)
                    }
                }

                if status != .done, post.taskId != nil, (onStartTask != nil || onCompleteTask != nil) {
                    HStack(spacing: 8) {
                        if status == .todo, let onStartTask {
                            Button {
                                onStartTask()
                            } label: {
                                Label("เริ่มทำ", systemImage: "play.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(FeedPalette.fbBlue)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(FeedPalette.fbBlueSoft)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        if let onCompleteTask {
                            Button {
                                taskCompleteHapticToken += 1
                                onCompleteTask()
                            } label: {
                                Label("เสร็จแล้ว", systemImage: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(FeedPalette.fbOk)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(FeedPalette.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FeedPalette.hairline, lineWidth: 1)
        )
    }

    private func taskAccentColor(status: TaskStatus, overdue: Int) -> Color {
        switch status {
        case .done: return FeedPalette.fbOk
        case .inProgress: return FeedPalette.fbOrange
        case .todo: return overdue >= 3 ? FeedPalette.fbRed : FeedPalette.fbBlue
        }
    }

    // MARK: - Engagement Summary Row (Facebook Stacked Bubbles)

    private var summaryRow: some View {
        HStack(spacing: 8) {
            if !item.reactionSummary.isEmpty {
                Button(action: onShowReactions) {
                    HStack(spacing: 6) {
                        FeedStackedReactions(summary: item.reactionSummary, circleSize: 19)
                        Text(reactionCountLabel)
                            .font(.footnote)
                            .foregroundStyle(FeedPalette.inkSecondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ความรู้สึก \(item.reactions.count) รายการ")
            }

            Spacer(minLength: 8)

            if item.commentCount > 0 {
                Button(action: onComment) {
                    Text("\(item.commentCount) ความคิดเห็น")
                        .font(.footnote)
                        .foregroundStyle(FeedPalette.inkSecondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reactionCountLabel: String {
        let total = item.reactions.count
        if myReaction != nil {
            if total <= 1 { return "คุณ" }
            return "คุณและอีก \(total - 1) คน"
        }
        return "\(total)"
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                if suppressNextTap {
                    suppressNextTap = false
                    return
                }
                if showReactionPicker {
                    withAnimation(.snappy(duration: 0.18)) {
                        showReactionPicker = false
                    }
                    return
                }
                reactHapticToken += 1
                triggerLikeBounce()
                onReact(myReaction != nil ? nil : .like)
            } label: {
                HStack(spacing: 6) {
                    if let active = myReaction {
                        FeedReactionCircle(type: active, size: 19)
                            .scaleEffect(likeBounce ? 1.24 : 1.0)
                    } else {
                        Image(systemName: "hand.thumbsup")
                            .font(.subheadline.weight(.medium))
                            .scaleEffect(likeBounce ? 1.2 : 1.0)
                    }
                    Text(myReaction?.label ?? "ถูกใจ")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(myReaction?.fbColor ?? FeedPalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.32).onEnded { _ in
                    suppressNextTap = true
                    dockHapticToken += 1
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        showReactionPicker = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 650_000_000)
                        suppressNextTap = false
                    }
                }
            )
            .accessibilityHint("แตะเพื่อถูกใจ หรือกดค้างเพื่อเลือกความรู้สึก")

            Button(action: onComment) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left")
                        .font(.subheadline.weight(.medium))
                    Text("แสดงความคิดเห็น")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(FeedPalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.subheadline.weight(.medium))
                    Text("แชร์")
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(FeedPalette.inkSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Quick Comment Prompt

    private var quickCommentRow: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(FeedPalette.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            Button(action: onComment) {
                HStack(spacing: 8) {
                    FeedAvatar(
                        avatar: currentUserAvatar,
                        name: currentUserName.isEmpty ? "คุณ" : currentUserName,
                        size: 28
                    )
                    Text("เขียนความคิดเห็น…")
                        .font(.caption)
                        .foregroundStyle(FeedPalette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(FeedPalette.surfaceMuted, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("เขียนความคิดเห็น")
        }
    }

    // MARK: - Context / Ellipsis Menu

    @ViewBuilder
    private var postMenuItems: some View {
        if canManage && post.kind == .admin {
            Button("แก้ไขโพสต์", systemImage: "pencil", action: onEdit)
        }
        if isSuperAdmin {
            Button(
                post.pinned ? "เลิกปักหมุด" : "ปักหมุดไว้ด้านบน",
                systemImage: post.pinned ? "pin.slash" : "pin",
                action: onPin
            )
        }
        Button("คัดลอกข้อความ", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = shareText
        }
        if canManage {
            Button("ลบโพสต์", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func triggerLikeBounce() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
            likeBounce = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
                likeBounce = false
            }
        }
    }

    private func needsExpand(_ text: String) -> Bool {
        text.split(separator: "\n").count > 5 || text.count > 180
    }
}
