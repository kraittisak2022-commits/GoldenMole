import AVFoundation
import AVKit
import Combine
import PhotosUI
import SwiftUI

/// «อัลบั้ม» tab — albums from GoldenMole Photos (photo.goldenmole.pro): browse, create, upload.
struct PhotoAlbumsView: View {
    @Environment(AuthService.self) private var auth

    @State private var albums: [PhotoAlbumSummary] = []
    @State private var loading = false
    @State private var error: PhotoAlbumError?
    @State private var search = ""
    @State private var showCreate = false
    @State private var openedAlbum: PhotoAlbumSummary?

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
            .navigationDestination(item: $openedAlbum) { album in
                PhotoAlbumDetailView(album: album)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Link(destination: PhotoAlbumAPI.webURL) {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("เปิด GoldenMole Photos บนเว็บ")
                    if error == nil {
                        Button { showCreate = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("สร้างอัลบั้ม")
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                PhotoCreateAlbumSheet { album in
                    albums.insert(album, at: 0)
                    openedAlbum = album
                }
                .environment(auth)
            }
            .task(id: auth.currentAdmin?.id) { await load() }
            .onAppear {
                // Quiet refresh when coming back from an album (counts / covers after uploads).
                if !albums.isEmpty { Task { await load() } }
            }
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
                        message: search.isEmpty ? "กดปุ่ม + มุมขวาบนเพื่อสร้างอัลบั้มแรก" : nil,
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
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var queue: PhotoUploadQueue

    private struct ViewerStart: Identifiable {
        let index: Int
        var id: Int { index }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    init(album: PhotoAlbumSummary) {
        self.album = album
        _queue = State(initialValue: PhotoUploadQueue(albumId: album.id))
    }

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
                    VStack(spacing: AppTheme.spaceSM) {
                        EmptyStateView(title: "อัลบั้มนี้ยังไม่มีรูป", systemImage: "photo")
                        addMediaPicker {
                            Label("เพิ่มรูป / วิดีโอ", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(AppTheme.brand, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
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
                addMediaPicker {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("เพิ่มรูปหรือวิดีโอ")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !queue.jobs.isEmpty {
                PhotoUploadTray(queue: queue)
                    .padding(.horizontal, AppTheme.spaceLG)
                    .padding(.bottom, AppTheme.spaceSM)
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty, let admin = auth.currentAdmin else { return }
            queue.enqueue(items, admin: admin)
            pickerItems = []
        }
        .refreshable { await load() }
        .task {
            queue.onUploaded = { item in
                if !media.contains(where: { $0.id == item.id }) { media.append(item) }
            }
            await load()
        }
        .fullScreenCover(item: $viewerStart) { start in
            PhotoMediaViewer(items: media, startIndex: start.index)
        }
    }

    private func addMediaPicker<Content: View>(@ViewBuilder label: () -> Content) -> some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: 100,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .current,
            label: label
        )
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

    init(items: [PhotoMediaItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    page(item, isActive: i == index)
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
    private func page(_ item: PhotoMediaItem, isActive: Bool) -> some View {
        if item.isVideo {
            PhotoVideoPage(item: item, isActive: isActive)
        } else {
            ZoomablePhoto(sources: item.src)
        }
    }
}

/// Streams the Drive file with AVPlayer; Drive's web player is only a fallback for formats iOS can't play.
private struct PhotoVideoPage: View {
    let item: PhotoMediaItem
    let isActive: Bool

    @State private var player: AVPlayer?
    @State private var failed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                PhotoRemoteImage(sources: item.src, large: true, contentMode: .fit)
                if !failed {
                    Button(action: start) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.white)
                            .shadow(radius: 6)
                    }
                    .accessibilityLabel("เล่นวิดีโอ")
                }
            }
            if failed {
                VStack(spacing: 10) {
                    Text("เล่นวิดีโอนี้ในแอปไม่ได้")
                        .font(.subheadline.weight(.semibold))
                    if let url = URL(string: item.src.preview ?? item.src.download) {
                        Button("เปิดใน Google Drive") { openURL(url) }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.brand)
                    }
                }
                .foregroundStyle(.white)
                .padding(AppTheme.spaceLG)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous))
            }
        }
        .onChange(of: isActive) { _, active in
            if !active { player?.pause() }
        }
        .onDisappear { player?.pause() }
    }

    private func start() {
        guard let url = item.streamURL else {
            failed = true
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let asset = AVURLAsset(url: url, options: [AVURLAssetOverrideMIMETypeKey: item.mime])
        let playerItem = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: playerItem)
        player = newPlayer
        newPlayer.play()
        Task {
            for await status in playerItem.publisher(for: \.status).values {
                if status == .failed {
                    player = nil
                    failed = true
                    return
                }
                if status == .readyToPlay { return }
            }
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

    static func reportDateKey(_ date: Date) -> String {
        ymd.string(from: date)
    }
}

// MARK: - Upload tray

private struct PhotoUploadTray: View {
    let queue: PhotoUploadQueue
    @Environment(AuthService.self) private var auth
    @State private var expanded = false

    private var title: String {
        if queue.hasActiveJobs {
            return "กำลังอัปโหลด \(queue.doneCount + 1)/\(queue.jobs.count)"
        }
        if queue.failedCount > 0 {
            return "อัปโหลดไม่สำเร็จ \(queue.failedCount) ไฟล์"
        }
        return "อัปโหลดเสร็จ \(queue.doneCount) ไฟล์"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: queue.hasActiveJobs
                      ? "arrow.up.circle.fill"
                      : (queue.failedCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.title3)
                    .foregroundStyle(queue.hasActiveJobs ? AppTheme.brand : (queue.failedCount > 0 ? AppTheme.expense : AppTheme.income))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if queue.failedCount > 0 && !queue.hasActiveJobs, let admin = auth.currentAdmin {
                    Button("ลองใหม่") { queue.retryFailed(admin: admin) }
                        .font(.caption.weight(.bold))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                }
                .accessibilityLabel(expanded ? "ซ่อนรายการ" : "แสดงรายการ")
                if queue.hasActiveJobs {
                    Button { queue.cancelAll() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("ยกเลิกการอัปโหลด")
                } else {
                    Button { queue.clearFinished() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("ปิด")
                }
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.inkSecondary)

            if queue.hasActiveJobs {
                ProgressView(value: queue.progress)
                    .tint(AppTheme.brand)
            }

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(queue.jobs) { job in
                            HStack(spacing: 8) {
                                Image(systemName: job.isVideo ? "video" : "photo")
                                    .foregroundStyle(AppTheme.inkMuted)
                                Text("ไฟล์ที่ \(job.index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.ink)
                                Spacer(minLength: 0)
                                jobStatus(job.state)
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(AppTheme.spaceMD)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .fill(AppTheme.surface)
                .shadow(color: AppTheme.cardShadow, radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMD, style: .continuous)
                .strokeBorder(AppTheme.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func jobStatus(_ state: PhotoUploadQueue.JobState) -> some View {
        switch state {
        case .waiting:
            Text("รอคิว").font(.caption2).foregroundStyle(AppTheme.inkMuted)
        case .uploading(let p):
            Text("\(Int((p * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(AppTheme.brand)
        case .done:
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(AppTheme.income)
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(AppTheme.expense)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Create album

private struct PhotoCreateAlbumSheet: View {
    let onCreated: (PhotoAlbumSummary) -> Void

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var reportDate = Date()
    @State private var busy = false
    @State private var message: String?
    @FocusState private var titleFocused: Bool

    private var cleanTitle: String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ชื่อรายงาน เช่น เทปูนชั้น 2", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    DatePicker("วันที่รายงาน", selection: $reportDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "th_TH"))
                        .environment(\.calendar, Calendar(identifier: .buddhist))
                } footer: {
                    Text("เก็บรูปใน Google Drive ใต้โฟลเดอร์ ปี / เดือน ของวันที่รายงาน · ทุกคนที่มีลิงก์อัลบั้มเพิ่มรูปได้")
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.expense)
                    }
                }
            }
            .navigationTitle("สร้างอัลบั้ม")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ยกเลิก") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "กำลังสร้าง…" : "สร้าง") { Task { await submit() } }
                        .fontWeight(.semibold)
                        .disabled(busy || cleanTitle.isEmpty || cleanTitle.count > 200)
                }
            }
            .onAppear { titleFocused = true }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private func submit() async {
        guard let admin = auth.currentAdmin, !busy else { return }
        busy = true
        defer { busy = false }
        let title = cleanTitle
        let reportDate = PhotoAlbumFormat.reportDateKey(reportDate)
        do {
            let album = try await PhotoAlbumSession.shared.withToken(admin: admin) {
                try await PhotoAlbumAPI.createAlbum(title: title, reportDate: reportDate, token: $0)
            }
            dismiss()
            onCreated(album)
        } catch {
            message = error.localizedDescription
        }
    }
}
