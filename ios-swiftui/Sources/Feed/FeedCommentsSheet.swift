import SwiftUI

struct FeedCommentsSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(FeedStore.self) private var feedStore
    @Environment(TaskStore.self) private var taskStore
    @Environment(\.dismiss) private var dismiss

    let post: FeedPost
    var reactionSummary: [(FeedReactionType, Int)] = []
    var reactionTotal: Int = 0

    @State private var comments: [FeedComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var copiedCommentId: String?
    @State private var sendHapticToken = 0
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !reactionSummary.isEmpty {
                    reactionHeaderBar
                    Rectangle().fill(FeedPalette.hairline).frame(height: 0.5)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            postPreviewSnippet

                            if let errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                    Text(errorMessage)
                                        .font(.caption)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(FeedPalette.fbRed)
                                .padding(10)
                                .background(
                                    FeedPalette.fbRed.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }

                            if isLoading {
                                commentSkeletons
                            } else if comments.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundStyle(FeedPalette.inkTertiary)
                                    Text("ยังไม่มีความคิดเห็น")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(FeedPalette.ink)
                                    Text("เริ่มพูดคุยเป็นคนแรกของโพสต์นี้")
                                        .font(.caption)
                                        .foregroundStyle(FeedPalette.inkSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                            } else {
                                ForEach(comments) { comment in
                                    commentRow(comment)
                                        .id(comment.id)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .onChange(of: comments.count) { _, _ in
                        if let last = comments.last {
                            withAnimation(.snappy(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Rectangle().fill(FeedPalette.hairline).frame(height: 0.75)
                inputBar
            }
            .background(FeedPalette.card)
            .navigationTitle("ความคิดเห็น")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FeedPalette.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("ปิด") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(FeedPalette.fbBlue)
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: sendHapticToken)
    }

    // MARK: - Subviews

    private var reactionHeaderBar: some View {
        HStack(spacing: 8) {
            FeedStackedReactions(summary: reactionSummary, circleSize: 18)
            Text("\(reactionTotal) ความรู้สึก")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(FeedPalette.inkSecondary)
            Spacer(minLength: 0)
            if !comments.isEmpty {
                Text("\(comments.count) ความคิดเห็น")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FeedPalette.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FeedPalette.card)
    }

    @ViewBuilder
    private var postPreviewSnippet: some View {
        let preview = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                FeedAvatar(
                    avatar: FeedAvatar.resolveAvatar(
                        adminId: post.authorAdminId,
                        admins: taskStore.admins,
                        currentAdmin: auth.currentAdmin
                    ),
                    name: post.authorName,
                    size: 28
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(post.authorName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FeedPalette.ink)
                        Text(FeedTimeFormat.relative(post.createdAt))
                            .font(.caption2)
                            .foregroundStyle(FeedPalette.inkTertiary)
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(FeedPalette.inkSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FeedPalette.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(FeedPalette.hairline, lineWidth: 0.75)
            )
        }
    }

    private var commentSkeletons: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(FeedPalette.surfaceMuted)
                        .frame(width: 34, height: 34)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FeedPalette.surfaceMuted)
                        .frame(height: 54)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private func commentRow(_ comment: FeedComment) -> some View {
        let avatar = FeedAvatar.resolveAvatar(
            adminId: comment.authorAdminId,
            admins: taskStore.admins,
            currentAdmin: auth.currentAdmin
        )
        let isCopied = copiedCommentId == comment.id

        return HStack(alignment: .top, spacing: 9) {
            FeedAvatar(avatar: avatar, name: comment.authorName, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.authorName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FeedPalette.ink)
                    Text(comment.body)
                        .font(.subheadline)
                        .lineSpacing(2)
                        .foregroundStyle(FeedPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FeedPalette.surfaceMuted)
                )

                HStack(spacing: 14) {
                    Text(FeedTimeFormat.relative(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(FeedPalette.inkSecondary)

                    Button {
                        UIPasteboard.general.string = comment.body
                        copiedCommentId = comment.id
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if copiedCommentId == comment.id { copiedCommentId = nil }
                        }
                    } label: {
                        Text(isCopied ? "คัดลอกแล้ว" : "คัดลอก")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isCopied ? FeedPalette.fbBlue : FeedPalette.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 8)
            }

            Spacer(minLength: 12)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 9) {
            FeedAvatar(
                avatar: auth.currentAdmin?.avatar ?? "",
                name: auth.currentAdmin?.displayName ?? "คุณ",
                size: 34
            )
            .padding(.bottom, 3)

            TextField("เขียนความคิดเห็น…", text: $draft, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(FeedPalette.ink)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(FeedPalette.surfaceMuted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        canSend ? FeedPalette.fbBlue : FeedPalette.border,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .padding(.bottom, 2)
            .accessibilityLabel("ส่งความคิดเห็น")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FeedPalette.card)
        .safeAreaPadding(.bottom, 4)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await feedStore.fetchComments(postId: post.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        guard let admin = auth.currentAdmin else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        sendHapticToken += 1
        let comment = FeedComment(
            postId: post.id,
            authorAdminId: admin.id,
            authorName: admin.displayName,
            body: text
        )
        comments.append(comment)
        draft = ""
        do {
            try await feedStore.addComment(comment)
            errorMessage = nil
        } catch {
            comments.removeAll { $0.id == comment.id }
            draft = text
            errorMessage = error.localizedDescription
        }
    }
}
