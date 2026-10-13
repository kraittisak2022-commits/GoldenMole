import SwiftUI

/// «อัลบั้ม» tab — albums from GoldenMole Photos (photo.goldenmole.pro), read-only.
struct PhotoAlbumsView: View {
    @Environment(AuthService.self) private var auth

    @State private var albums: [PhotoAlbumSummary] = []
    @State private var loading = false
    @State private var error: PhotoAlbumError?
    @State private var search = ""

    private var filtered: [PhotoAlbumSummary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        content
            .background(DashboardBackground())
            .navigationTitle("อัลบั้ม")
            .navigationDestination(for: PhotoAlbumSummary.self) { album in
                PhotoAlbumDetailView(album: album)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: PhotoAlbumAPI.webURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("เปิด GoldenMole Photos บนเว็บ")
                }
            }
            .task(id: auth.currentAdmin?.id) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if error == .needsPassword || error == .unauthorized {
            PhotoAlbumSignInCard { await load() }
        } else if albums.isEmpty && loading {
            ProgressView("กำลังโหลดอัลบั้ม…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if albums.isEmpty, let error {
            ScrollView {
                EmptyStateView(
                    title: "โหลดอัลบั้มไม่สำเร็จ",
                    message: error.localizedDescription,
                    systemImage: "exclamationmark.triangle"
                )
                if error != .forbidden {
                    Button("ลองใหม่") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.brand)
                }
            }
            .refreshable { await load() }
        } else {
            ScrollView {
                if filtered.isEmpty {
                    EmptyStateView(
                        title: search.isEmpty ? "ยังไม่มีอัลบั้ม" : "ไม่พบอัลบั้ม «\(search)»",
                        message: search.isEmpty ? "สร้างอัลบั้มได้ที่ photo.goldenmole.pro" : nil,
                        systemImage: "photo.on.rectangle.angled"
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160), spacing: AppTheme.spaceMD)],
                        spacing: AppTheme.spaceMD
                    ) {
                        ForEach(filtered) { album in
                            NavigationLink(value: album) {
                                PhotoAlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(AppTheme.spaceLG)
                }
            }
            .searchable(text: $search, prompt: "ค้นหาอัลบั้ม")
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let admin = auth.currentAdmin else { return }
        loading = true
        defer { loading = false }
        do {
            albums = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.albums(token: $0)
            }
            error = nil
        } catch let err as PhotoAlbumError {
            error = err
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}

// MARK: - Album card

private struct PhotoAlbumCard: View {
    let album: PhotoAlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let cover = album.cover {
                        PhotoRemoteImage(sources: cover)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(AppTheme.inkMuted)
                    }
                }
                .background(AppTheme.surfaceSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))

            Text(album.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("\(PhotoAlbumFormat.shortDate(album.reportDate)) · \(album.mediaCount) รายการ")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Album detail

struct PhotoAlbumDetailView: View {
    let album: PhotoAlbumSummary

    @Environment(AuthService.self) private var auth
    @State private var media: [PhotoMediaItem] = []
    @State private var loading = false
    @State private var error: PhotoAlbumError?
    @State private var viewerStart: ViewerStart?

    private struct ViewerStart: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                header
                if media.isEmpty && loading {
                    ProgressView("กำลังโหลดรูป…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if media.isEmpty, let error {
                    EmptyStateView(
                        title: "โหลดรูปไม่สำเร็จ",
                        message: error.localizedDescription,
                        systemImage: "exclamationmark.triangle"
                    )
                } else if media.isEmpty {
                    EmptyStateView(title: "อัลบั้มนี้ยังไม่มีรูป", systemImage: "photo")
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(media.enumerated()), id: \.element.id) { index, item in
                            Button {
                                viewerStart = ViewerStart(index: index)
                            } label: {
                                PhotoGridCell(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.spaceMD)
        }
        .background(DashboardBackground())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let drive = URL(string: album.driveFolderUrl) {
                    Link(destination: drive) { Image(systemName: "folder") }
                        .accessibilityLabel("เปิดโฟลเดอร์ใน Google Drive")
                }
                ShareLink(item: "\(album.title)\n\(album.shareUrl)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("แชร์ชื่ออัลบั้มและลิงก์")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .fullScreenCover(item: $viewerStart) { start in
            PhotoMediaViewer(items: media, startIndex: start.index)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DashboardAggregations.thaiDateLong(album.reportDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("\(media.isEmpty ? album.mediaCount : media.count) รายการ")
                .font(.caption)
                .foregroundStyle(AppTheme.inkMuted)
        }
        .padding(.horizontal, AppTheme.spaceLG)
    }

    private func load() async {
        guard let admin = auth.currentAdmin else { return }
        loading = true
        defer { loading = false }
        do {
            let detail = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.album(id: album.id, token: $0)
            }
            media = detail.media
            error = nil
        } catch let err as PhotoAlbumError {
            error = err
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }
}

private struct PhotoGridCell: View {
    let item: PhotoMediaItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { PhotoRemoteImage(sources: item.src) }
            .background(AppTheme.surfaceSoft)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if item.isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .shadow(radius: 3)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(item.isVideo ? "วิดีโอ \(item.name)" : "รูป \(item.name)")
    }
}

// MARK: - Full-screen viewer

private struct PhotoMediaViewer: View {
    let items: [PhotoMediaItem]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(items: [PhotoMediaItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    page(item)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("ปิด")
                Spacer()
                Text("\(index + 1) / \(items.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Spacer()
                if items.indices.contains(index), let url = URL(string: items[index].src.download) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("แชร์ลิงก์ดาวน์โหลด")
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.spaceLG)
            .padding(.top, AppTheme.spaceSM)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func page(_ item: PhotoMediaItem) -> some View {
        if item.isVideo {
            ZStack {
                PhotoRemoteImage(sources: item.src, large: true, contentMode: .fit)
                Button {
                    if let url = URL(string: item.src.preview ?? item.src.download) { openURL(url) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .shadow(radius: 6)
                }
                .accessibilityLabel("เล่นวิดีโอ")
            }
        } else {
            ZoomablePhoto(sources: item.src)
        }
    }
}

private struct ZoomablePhoto: View {
    let sources: PhotoMediaSources
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        PhotoRemoteImage(sources: sources, large: true, contentMode: .fit)
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(5, max(1, lastScale * $0.magnification)) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }
}

// MARK: - Remote image (Drive thumbnail with fallback)

private struct PhotoRemoteImage: View {
    let sources: PhotoMediaSources
    var large = false
    var contentMode: ContentMode = .fill
    @State private var useFallback = false

    private var url: URL? {
        URL(string: useFallback ? sources.thumbFallback : (large ? sources.large : sources.thumb))
    }

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(AppTheme.inkMuted)
                    .onAppear { if !useFallback { useFallback = true } }
            default:
                ProgressView()
            }
        }
    }
}

// MARK: - One-time sign-in for the photo site

private struct PhotoAlbumSignInCard: View {
    let onSignedIn: () async -> Void

    @Environment(AuthService.self) private var auth
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            SectionCard("เข้าสู่ระบบอัลบั้ม", systemImage: "lock.shield", subtitle: "ใช้รหัสผ่านเดียวกับที่เข้าแอปนี้ — ถามครั้งเดียว") {
                VStack(alignment: .leading, spacing: AppTheme.spaceMD) {
                    Label(auth.currentAdmin?.username ?? "-", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.inkSecondary)
                    SecureField("รหัสผ่าน", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .padding(12)
                        .background(AppTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: AppTheme.radiusSM, style: .continuous))
                    if let message {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                    }
                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? "กำลังเข้าสู่ระบบ…" : "เข้าสู่ระบบ")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brand)
                    .disabled(busy || password.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(AppTheme.spaceLG)
        }
    }

    private func submit() async {
        guard let admin = auth.currentAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await PhotoAlbumSession.shared.signIn(
                admin: admin,
                password: password.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            password = ""
            message = nil
            await onSignedIn()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Formatting

private enum PhotoAlbumFormat {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .buddhist)
        f.locale = Locale(identifier: "th_TH")
        f.timeZone = TimeZone(identifier: "Asia/Bangkok")
        f.dateFormat = "d MMM yy"
        return f
    }()

    static func shortDate(_ ymd: String) -> String {
        guard let date = Self.ymd.date(from: ymd) else { return ymd }
        return display.string(from: date)
    }
}
