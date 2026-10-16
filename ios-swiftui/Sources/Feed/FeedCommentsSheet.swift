import SwiftUI

struct FeedCommentsSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(FeedStore.self) private var feedStore
    @Environment(\.dismiss) private var dismiss

    let post: FeedPost

    @State private var comments: [FeedComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                            Text(post.body)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.inkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 4)

                            if isLoading {
                                ProgressView("โหลดความคิดเห็น…")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 24)
                            } else if comments.isEmpty {
                                ContentUnavailableView(
                                    "ยังไม่มีความคิดเห็น",
                                    systemImage: "bubble.left",
                                    description: Text("เป็นคนแรกที่แสดงความคิดเห็น")
                                )
                                .padding(.vertical, 24)
                            } else {
                                ForEach(comments) { comment in
                                    commentRow(comment)
                                        .id(comment.id)
                                }
                            }
                        }
                        .padding(AppTheme.spaceLG)
                    }
                    .onChange(of: comments.count) { _, _ in
                        if let last = comments.last {
                            withAnimation(.snappy) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
                inputBar
            }
            .background(DashboardBackground())
            .navigationTitle("ความคิดเห็น")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ปิด") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func commentRow(_ comment: FeedComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(
                avatar: "",
                initials: initials(comment.authorName),
                size: 32
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(FeedTimeFormat.relative(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.inkMuted)
                }
                Text(comment.body)
                    .font(.body)
                    .foregroundStyle(AppTheme.ink)
            }
            .padding(AppTheme.spaceMD)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("เขียนความคิดเห็น…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceSoft, in: Capsule())

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        canSend ? AppTheme.brand : AppTheme.inkMuted.opacity(0.35),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .accessibilityLabel("ส่งความคิดเห็น")
        }
        .padding(.horizontal, AppTheme.spaceLG)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .safeAreaPadding(.bottom, 4)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        } catch {
            comments.removeAll { $0.id == comment.id }
            draft = text
            errorMessage = error.localizedDescription
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}
