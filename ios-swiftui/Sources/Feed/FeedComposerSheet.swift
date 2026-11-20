import PhotosUI
import SwiftUI

struct FeedComposerSheet: View {
    @Environment(AuthService.self) private var auth
    @Environment(FeedStore.self) private var feedStore
    @Environment(\.dismiss) private var dismiss

    @State private var bodyText = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var isPublishing = false
    @State private var progressText: String?
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var publishHapticToken = 0
    @FocusState private var focused: Bool

    private struct QuickTag: Identifiable {
        let label: String
        let icon: String
        let color: Color
        let prefix: String
        var id: String { label }
    }

    private static let quickTags: [QuickTag] = [
        QuickTag(label: "หน้างาน", icon: "mappin.and.ellipse", color: FeedPalette.fbBlue, prefix: "[หน้างาน] "),
        QuickTag(label: "เสร็จแล้ว", icon: "checkmark.circle.fill", color: FeedPalette.fbOk, prefix: "[เสร็จแล้ว] "),
        QuickTag(label: "แจ้งปัญหา", icon: "exclamationmark.triangle.fill", color: FeedPalette.fbOrange, prefix: "[แจ้งปัญหา] "),
        QuickTag(label: "รถ / น้ำมัน", icon: "truck.box.fill", color: FeedPalette.fbPurple, prefix: "[รถ/น้ำมัน] ")
    ]

    private var canPublish: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !items.isEmpty
    }

    private var useLargeComposerFont: Bool {
        items.isEmpty && bodyText.count < 85
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        authorHeader

                        TextField("คุณกำลังอัพเดตอะไรอยู่?", text: $bodyText, axis: .vertical)
                            .font(useLargeComposerFont ? .title3 : .body)
                            .foregroundStyle(FeedPalette.ink)
                            .lineLimit(4...14)
                            .focused($focused)
                            .padding(.top, 2)

                        if let progressText {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(FeedPalette.fbBlue)
                                    Text(progressText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(FeedPalette.ink)
                                    Spacer(minLength: 0)
                                }
                                if uploadProgress > 0 {
                                    ProgressView(value: uploadProgress)
                                        .tint(FeedPalette.fbBlue)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FeedPalette.fbBlueSoft)
                            )
                        }

                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(errorMessage)
                                    .font(.caption)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(FeedPalette.fbRed)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FeedPalette.fbRed.opacity(0.08))
                            )
                        }

                        mediaAttachmentSection
                    }
                    .padding(16)
                }

                quickTagBar
            }
            .background(FeedPalette.card)
            .navigationTitle("สร้างโพสต์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FeedPalette.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                        .foregroundStyle(FeedPalette.inkSecondary)
                        .disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await publish() }
                    } label: {
                        Text(isPublishing ? "กำลังโพสต์…" : "โพสต์")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(canPublish && !isPublishing ? .white : FeedPalette.inkTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    canPublish && !isPublishing
                                        ? FeedPalette.fbBlue
                                        : FeedPalette.surfaceMuted
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canPublish || isPublishing)
                }
            }
            .interactiveDismissDisabled(isPublishing)
            .onAppear { focused = true }
        }
        .preferredColorScheme(.light)
        .sensoryFeedback(.success, trigger: publishHapticToken)
    }

    // MARK: - Subviews

    private var authorHeader: some View {
        HStack(spacing: 12) {
            FeedAvatar(
                avatar: auth.currentAdmin?.avatar ?? "",
                name: auth.currentAdmin?.displayName ?? "คุณ",
                size: 46,
                showOnlineDot: true
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(auth.currentAdmin?.displayName ?? "ทีมงาน")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)

                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("ทีม Golden Mole")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(FeedPalette.fbBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(FeedPalette.fbBlueSoft, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var mediaAttachmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedPalette.fbGreen)
                Text("รูปภาพ / วิดีโอ")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(FeedPalette.ink)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    Text("\(min(items.count, 20))/20")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(FeedPalette.fbGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(FeedPalette.fbGreen.opacity(0.12), in: Capsule())
                }
            }

            PhotoPickedMediaGrid(items: $items)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FeedPalette.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(FeedPalette.hairline, lineWidth: 1)
        )
    }

    private var quickTagBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(FeedPalette.hairline).frame(height: 0.75)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.quickTags) { tag in
                        Button {
                            insertPrefix(tag.prefix)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tag.icon)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tag.color)
                                Text(tag.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FeedPalette.ink)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(FeedPalette.surfaceMuted, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(FeedPalette.card)
        }
    }

    private func insertPrefix(_ prefix: String) {
        if bodyText.hasPrefix(prefix) { return }
        if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bodyText = prefix
        } else {
            bodyText = prefix + bodyText
        }
        focused = true
    }

    // MARK: - Publish

    private func publish() async {
        guard let admin = auth.currentAdmin else {
            errorMessage = "กรุณาเข้าสู่ระบบ"
            return
        }
        isPublishing = true
        errorMessage = nil
        uploadProgress = 0
        defer { isPublishing = false }

        var media: [FeedMedia] = []
        let limited = Array(items.prefix(20))
        for (index, item) in limited.enumerated() {
            progressText = "กำลังอัปโหลด \(index + 1)/\(limited.count)"
            uploadProgress = Double(index) / Double(max(1, limited.count))
            do {
                let file = try await PhotoUploadPreparer.prepare(item, index: index)
                defer { try? FileManager.default.removeItem(at: file.fileURL) }
                let sessionURL = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                    try await PhotoAlbumAPI.startFeedUpload(
                        name: file.name,
                        mimeType: file.mimeType,
                        size: file.size,
                        date: DashboardAggregations.todayYMD(),
                        token: $0
                    )
                }
                let fileId = try await DriveResumableUploader.upload(
                    fileURL: file.fileURL,
                    size: file.size,
                    to: sessionURL
                ) { _ in }
                let uploaded = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                    try await PhotoAlbumAPI.completeFeedUpload(
                        fileId: fileId,
                        width: file.width,
                        height: file.height,
                        date: DashboardAggregations.todayYMD(),
                        token: $0
                    )
                }
                media.append(uploaded)
                uploadProgress = Double(index + 1) / Double(max(1, limited.count))
            } catch {
                errorMessage = error.localizedDescription
                progressText = nil
                uploadProgress = 0
                return
            }
        }

        progressText = "กำลังเผยแพร่โพสต์…"
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await feedStore.createPost(
                body: text,
                media: media,
                authorAdminId: admin.id,
                authorName: admin.displayName
            )
            publishHapticToken += 1
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            progressText = nil
            uploadProgress = 0
        }
    }
}

// MARK: - Multiline White Edit Post Sheet

struct FeedEditPostSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: FeedPost
    let authorAvatar: String
    let onSave: (String) -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(post: FeedPost, authorAvatar: String, onSave: @escaping (String) -> Void) {
        self.post = post
        self.authorAvatar = authorAvatar
        self.onSave = onSave
        self._draft = State(initialValue: post.body)
    }

    private var canSave: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != post.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 11) {
                        FeedAvatar(avatar: authorAvatar, name: post.authorName, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.authorName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(FeedPalette.ink)
                            Text(FeedTimeFormat.relative(post.createdAt))
                                .font(.caption)
                                .foregroundStyle(FeedPalette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    TextField("แก้ไขข้อความโพสต์…", text: $draft, axis: .vertical)
                        .font(.body)
                        .foregroundStyle(FeedPalette.ink)
                        .lineLimit(5...16)
                        .focused($focused)
                }
                .padding(16)
            }
            .background(FeedPalette.card)
            .navigationTitle("แก้ไขโพสต์")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FeedPalette.card, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                        .foregroundStyle(FeedPalette.inkSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(draft)
                        dismiss()
                    } label: {
                        Text("บันทึก")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(canSave ? .white : FeedPalette.inkTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(canSave ? FeedPalette.fbBlue : FeedPalette.surfaceMuted)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .onAppear { focused = true }
        }
        .preferredColorScheme(.light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
