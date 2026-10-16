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
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var canPublish: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spaceLG) {
                    HStack(alignment: .top, spacing: 12) {
                        AvatarCircle(
                            avatar: auth.currentAdmin?.avatar ?? "",
                            initials: initials(auth.currentAdmin?.displayName ?? "?"),
                            size: 44
                        )
                        TextField("อัพเดตอะไรวันนี้?", text: $bodyText, axis: .vertical)
                            .lineLimit(4...12)
                            .focused($focused)
                    }

                    PhotoPickedMediaGrid(items: $items)

                    if let progressText {
                        Label(progressText, systemImage: "arrow.up.circle")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.expense)
                    }
                }
                .padding(AppTheme.spaceLG)
            }
            .background(DashboardBackground())
            .navigationTitle("โพสต์อัพเดต")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                        .disabled(isPublishing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPublishing ? "กำลังโพสต์…" : "โพสต์") {
                        Task { await publish() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPublish || isPublishing)
                }
            }
            .interactiveDismissDisabled(isPublishing)
            .onAppear { focused = true }
        }
    }

    private func publish() async {
        guard let admin = auth.currentAdmin else {
            errorMessage = "กรุณาเข้าสู่ระบบ"
            return
        }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        var media: [FeedMedia] = []
        let limited = Array(items.prefix(20))
        for (index, item) in limited.enumerated() {
            progressText = "กำลังอัปโหลด \(index + 1)/\(limited.count)"
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
            } catch {
                errorMessage = error.localizedDescription
                progressText = nil
                return
            }
        }

        progressText = "กำลังบันทึกโพสต์…"
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await feedStore.createPost(
                body: text,
                media: media,
                authorAdminId: admin.id,
                authorName: admin.displayName
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            progressText = nil
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let s = parts.map { String($0.prefix(1)) }.joined()
        return s.isEmpty ? "?" : s.uppercased()
    }
}
