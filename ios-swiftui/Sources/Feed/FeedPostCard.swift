import SwiftUI

struct FeedPostCard: View {
    let item: FeedPostItem
    let adminId: String
    let isSuperAdmin: Bool
    var taskStatus: TaskStatus?
    var onReact: (FeedReactionType?) -> Void
    var onComment: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onPin: () -> Void
    var onStartTask: (() -> Void)?
    var onCompleteTask: (() -> Void)?
    var onOpenMedia: (Int) -> Void

    @State private var expanded = false
    @State private var showReactionPicker = false

    private var post: FeedPost { item.post }
    private var canManage: Bool {
        isSuperAdmin || post.authorAdminId == adminId
    }
    private var myReaction: FeedReactionType? {
        item.myReaction(adminId: adminId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
            header
            bodyText
            if post.kind == .leaveDigest {
                leaveBlock
            }
            if post.kind.isTaskRelated {
                taskBlock
            }
            if !post.media.isEmpty {
                FeedMediaGrid(media: post.media, onTap: onOpenMedia)
            }
            if !item.reactionSummary.isEmpty || item.commentCount > 0 {
                summaryRow
            }
            Divider().opacity(0.5)
            actionBar
        }
        .padding(AppTheme.spaceLG)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if post.pinned {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.brand.opacity(0.35), lineWidth: 1)
            }
        }
        .contextMenu { contextMenu }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(
                avatar: "",
                initials: initials(post.authorName),
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    kindBadge
                }
                HStack(spacing: 4) {
                    if post.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.brand)
                    }
                    Text(FeedTimeFormat.relative(post.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppTheme.inkMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var kindBadge: some View {
        Label(post.kind.label, systemImage: post.kind.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(post.kind.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(post.kind.tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(post.kind.label)
    }

    @ViewBuilder
    private var bodyText: some View {
        let text = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(expanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if needsExpand(text) {
                    Button(expanded ? "ย่อ" : "ดูเพิ่มเติม") {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.brand)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var leaveBlock: some View {
        let leaves = post.meta.leaves ?? []
        return VStack(alignment: .leading, spacing: 8) {
            if leaves.isEmpty {
                Label("วันนี้ทุกคนมาทำงาน", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.income)
            } else {
                ForEach(leaves) { entry in
                    HStack(spacing: 8) {
                        AvatarCircle(avatar: "", initials: initials(entry.name), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.subheadline.weight(.medium))
                            Text(entry.kindLabel + (entry.halfDay ? " · ครึ่งวัน" : ""))
                                .font(.caption)
                                .foregroundStyle(AppTheme.inkMuted)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(AppTheme.spaceMD)
        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var taskBlock: some View {
        let overdue = post.meta.daysOverdue ?? 0
        let status = taskStatus ?? (post.kind == .taskDone ? .done : .todo)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statusPill(status)
                if overdue > 0 && status != .done {
                    Text("ค้างมา \(overdue) วัน")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(overdue >= 3 ? AppTheme.expense : AppTheme.warning, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            if let name = post.meta.assigneeName, !name.isEmpty {
                Label(name, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            if let due = post.meta.dueDate, !due.isEmpty {
                Label("กำหนด \(due)", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
            if status != .done, post.taskId != nil {
                HStack(spacing: 8) {
                    if status == .todo, let onStartTask {
                        Button("เริ่มทำ", action: onStartTask)
                            .buttonStyle(.bordered)
                            .tint(AppTheme.brand)
                    }
                    if let onCompleteTask {
                        Button("เสร็จแล้ว", action: onCompleteTask)
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.income)
                    }
                }
            }
        }
        .padding(AppTheme.spaceMD)
        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusPill(_ status: TaskStatus) -> some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.12), in: Capsule())
    }

    private var summaryRow: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(item.reactionSummary, id: \.0.rawValue) { pair in
                    Label("\(pair.1)", systemImage: pair.0.systemImage)
                        .font(.caption)
                        .foregroundStyle(pair.0.tint)
                        .labelStyle(.titleAndIcon)
                }
            }
            Spacer()
            if item.commentCount > 0 {
                Text("\(item.commentCount) ความคิดเห็น")
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkMuted)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onReact(myReaction == .like ? nil : .like)
            } label: {
                Label(
                    myReaction?.label ?? "ถูกใจ",
                    systemImage: myReaction?.systemImage ?? "hand.thumbsup"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(myReaction?.tint ?? AppTheme.inkMuted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                    showReactionPicker = true
                }
            )
            .confirmationDialog("ความรู้สึก", isPresented: $showReactionPicker, titleVisibility: .visible) {
                ForEach(FeedReactionType.allCases) { type in
                    Button(type.label) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onReact(type)
                    }
                }
                if myReaction != nil {
                    Button("เอาออก", role: .destructive) { onReact(nil) }
                }
                Button("ยกเลิก", role: .cancel) {}
            }

            Button(action: onComment) {
                Label("แสดงความคิดเห็น", systemImage: "bubble.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ShareLink(item: post.body) {
                Label("แชร์", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.inkMuted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if canManage && post.kind == .admin {
            Button("แก้ไข", systemImage: "pencil", action: onEdit)
        }
        if isSuperAdmin {
            Button(post.pinned ? "เลิกปักหมุด" : "ปักหมุด", systemImage: post.pinned ? "pin.slash" : "pin", action: onPin)
        }
        Button("คัดลอกข้อความ", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = post.body
        }
        if canManage {
            Button("ลบ", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }

    private func needsExpand(_ text: String) -> Bool {
        text.split(separator: "\n").count > 5 || text.count > 180
    }
}
